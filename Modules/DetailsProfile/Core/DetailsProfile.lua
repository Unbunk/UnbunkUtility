-- Modules/DetailsProfile/Core/DetailsProfile.lua
-- Owner utility: drive the Details! damage-meter by context using a user-defined list
-- of "profiles". Each profile names a Details! profile to apply and carries two
-- independent criteria cadres — one keyed on the GROUP composition (solo / party /
-- raid / custom member-count ranges) and one on the INSTANCE type (outdoor / dungeon /
-- raid / battleground). When a criterion matches the current context the profile can
-- (a) apply its named Details! profile and/or (b) FADE the Details! window(s) to a low
-- alpha so the meter dims without fully disappearing. Leaving the matching context
-- restores full opacity.
--
-- Profile switching is skipped in combat (it would reset the meter windows mid-fight)
-- and deferred to PLAYER_REGEN_ENABLED; fading is a plain frame-alpha change so it is
-- applied immediately. Per-profile config (ns.db.profile.detailsSwitch) so a profile
-- reset clears the list; the module is disabled by default and only reachable from the
-- owner-gated "Personal utilities" panel.

local ADDON, ns = ...
ns.DetailsProfile = ns.DetailsProfile or {}
local DP = ns.DetailsProfile

-- A profile with "Fade Details!" on dims the meter to its configured opacity (a
-- percentage) instead of hiding it; new profiles default to 30% (matching ns.Fader).
local DEFAULT_FADE_OPACITY = 30

local function PctToAlpha(pct)
    local a = (tonumber(pct) or DEFAULT_FADE_OPACITY) / 100
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

-- Template for a single profile entry. New profiles deep-copy this; existing ones are
-- backfilled key-by-key in InitCfg so older saved profiles gain any new fields.
local PROFILE_DEFAULTS = {
    changeProfile = false,                 -- "Change Details! profile" master for this entry
    profileName   = "",                    -- Details! profile to apply when a criterion matches
    fadeDetails   = false,                 -- fade the meter (instead of hide) when a criterion matches
    fadeOpacity   = DEFAULT_FADE_OPACITY,  -- % opacity to fade to
    mouseOverEnabled = false,              -- reveal on hover at all (master for the mouse-over opacity); default off
    mouseOverOpacity = 100,                -- % opacity while the cursor is over the meter (hover reveal)
    group = {                              -- "Change with group" cadre
        enabled = false,
        solo    = false,                   -- not in a group
        group   = false,                   -- party of 2-5
        raid    = false,                   -- raid group
        custom  = {},                      -- { { enabled = true, min = 1, max = 5 }, ... }
    },
    instance = {                           -- "Change with instance" cadre
        enabled      = false,
        outdoor      = false,              -- open world (instType "none")
        dungeon      = false,              -- 5-player ("party")
        raid         = false,              -- raid instance ("raid")
        battleground = false,              -- ("pvp")
    },
    combat = {                             -- "Change only in combat state :" gate
        enabled = false,
        state   = "in",                    -- "in" | "out": restrict matching to this state
    },
}
DP.PROFILE_DEFAULTS = PROFILE_DEFAULTS

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.detailsSwitch end
DP.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    -- One-shot migration: detailsSwitch used to live in ns.db.global (account-wide), so a
    -- profile reset never cleared the user's created profiles. Fold the legacy global blob
    -- into the CURRENT profile once, then drop it + flag done so a later reset truly wipes
    -- the list. Only the active profile inherits the old shared data; others start empty.
    if ns.db.global.detailsSwitch and not ns.db.global.detailsSwitchMigrated then
        if p.detailsSwitch == nil then
            p.detailsSwitch = ns.DeepCopy(ns.db.global.detailsSwitch)
        end
        ns.db.global.detailsSwitch = nil
        ns.db.global.detailsSwitchMigrated = true
    end
    p.detailsSwitch = p.detailsSwitch or {}
    local c = p.detailsSwitch
    -- Drop the pre-redesign single-context keys (mode / raidProfile / dungeonProfile).
    c.mode = nil; c.raidProfile = nil; c.dungeonProfile = nil
    if c.enabled == nil then c.enabled = false end
    c.profiles = c.profiles or {}
    for _, prof in ipairs(c.profiles) do
        ns.MergeDefaults(prof, PROFILE_DEFAULTS)
    end
end
ns.RegisterCfgInitHook(InitCfg)

-- ── Profile list mutation (called by the config panel) ────────────────────────
function DP.NewProfile()
    local c = Cfg(); if not c then return nil end
    c.profiles = c.profiles or {}
    local p = ns.DeepCopy(PROFILE_DEFAULTS)
    c.profiles[#c.profiles + 1] = p
    DP.Apply()
    return p
end

function DP.RemoveProfile(p)
    local c = Cfg(); if not c or not c.profiles then return end
    for i, pp in ipairs(c.profiles) do
        if pp == p then table.remove(c.profiles, i); break end
    end
    DP.Apply()
end

-- Details! + its profile API present?
function DP.DetailsReady()
    return Details ~= nil and Details.GetCurrentProfileName and Details.ApplyProfile and true or false
end

-- ── Per-window geometry (the "Windows settings" cadre) ────────────────────────
-- Enumerate + tweak each CREATED Details! window (instance). All guarded so a missing /
-- older API never errors. X/Y use Details!'s OWN convention (offset from screen centre —
-- what inst:GetPositionOnScreen returns); W/H are the base-frame size in logical (pre-scale) units.
function DP.NumWindows()
    if not (Details and Details.GetNumInstances) then return 0 end
    return Details:GetNumInstances() or 0
end

function DP.GetWindow(i)
    if not (Details and Details.GetInstance) then return nil end
    return Details:GetInstance(i)
end

-- A window whose geometry Details! owns: LOCKED, or LINKED (snapped) to another window.
-- Its size/pos cadre is greyed then — a manual W/H/X/Y would fight Details! or break the
-- snapped group. inst.snap is Details!'s per-side neighbour map ({} when unlinked).
function DP.IsWindowLocked(inst)
    return (inst and inst.isLocked) and true or false
end

function DP.IsWindowLinked(inst)
    return (inst and type(inst.snap) == "table" and next(inst.snap) ~= nil) and true or false
end

function DP.IsWindowGated(inst)
    return DP.IsWindowLocked(inst) or DP.IsWindowLinked(inst)
end

-- An OPEN (enabled) window with a real base frame. Details!'s close [x] (DesativarInstancia) sets
-- ativa=false but KEEPS baseframe, so a baseframe-only check would leak a closed window into the list
-- as an editable, non-greyed cadre. IsEnabled() reads that ativa flag (ativa fallback for older API).
function DP.IsWindowOpen(inst)
    if not (inst and inst.baseframe) then return false end
    if inst.IsEnabled then return inst:IsEnabled() and true or false end
    return inst.ativa and true or false
end

-- Current width, height, x, y of a window (rounded to whole pixels for the inputs).
function DP.GetWindowRect(inst)
    if not (inst and inst.baseframe) then return 0, 0, 0, 0 end
    local w = math.floor((inst.baseframe:GetWidth()  or 0) + 0.5)
    local h = math.floor((inst.baseframe:GetHeight() or 0) + 0.5)
    local x, y = 0, 0
    if inst.GetPositionOnScreen then
        local px, py = inst:GetPositionOnScreen()
        if px then x = math.floor(px + 0.5) end
        if py then y = math.floor(py + 0.5) end
    end
    return w, h, x, y
end

-- Resize a window. Details!'s SetSize -> Resize also persists via SaveMainWindowPosition.
function DP.SetWindowSize(inst, w, h)
    if not (inst and inst.SetSize) or DP.IsWindowGated(inst) then return end
    if not (w and h) then return end
    inst:SetSize(w, h)
end

-- Move a window to an exact X/Y (screen-centre offset), mirroring Details!'s own
-- RestoreMainWindowPositionNoResize scale math, then persist via SaveMainWindowPosition.
function DP.SetWindowPos(inst, x, y)
    if not (inst and inst.baseframe) or DP.IsWindowGated(inst) then return end
    if not (x and y) then return end
    local sc  = inst.baseframe:GetEffectiveScale()
    local uis = UIParent:GetScale()
    if not (sc and uis and sc ~= 0) then return end
    inst.baseframe:ClearAllPoints()
    inst.baseframe:SetPoint("CENTER", UIParent, "CENTER", x * uis / sc, y * uis / sc)
    if inst.SaveMainWindowPosition then inst:SaveMainWindowPosition() end
end

-- ── Details! window fade ──────────────────────────────────────────────────────
-- Details! exposes each meter window as an "instance" whose frame is instance.baseframe.
-- We tweak that frame's alpha so the whole window (bars + text) dims together; this is a
-- plain frame-alpha change Details! does not overwrite on its refresh tick. Guarded so a
-- missing / older API never errors. NOTE: verify in-game against your Details! version.
local function EachWindow(fn)
    if not Details then return end
    local n = 0
    if Details.GetNumInstances then n = Details:GetNumInstances() or 0 end
    if (not n or n == 0) and Details.GetNumRunningInstances then n = Details:GetNumRunningInstances() or 0 end
    if not n or n == 0 then n = 4 end   -- probe the first few even if no count API exists
    for i = 1, n do
        local inst = Details.GetInstance and Details:GetInstance(i)
        if inst then fn(inst, inst.baseframe) end
    end
end

function DP.SetDetailsAlpha(a)
    if not Details then return end
    EachWindow(function(inst, frame)
        if frame and frame.SetAlpha then
            frame:SetAlpha(a)
        elseif inst.SetBackgroundAlpha then
            inst:SetBackgroundAlpha(a)
        end
        -- The bar rows live on a SEPARATE frame (inst.rowframe), NOT a child of baseframe, so the
        -- window-frame alpha above never reaches them. Dim the row container too so the bars share the
        -- same opacity (their own per-bar alpha stays 1, so effective alpha = rowframe alpha = a).
        -- Details! only resets rowframe alpha on window show/hide (lock/unlock), not on data refreshes,
        -- so this sticks; DP.Apply re-applies on the relevant events.
        local rf = inst.rowframe
        if rf and rf.SetAlpha then rf:SetAlpha(a) end
    end)
end

-- ── Mouse-over reveal ─────────────────────────────────────────────────────────
-- While we hold Details! at its faded alpha, hovering any meter window raises it to the matching
-- profile's "Mouse over Opacity" so it stays readable on demand, dropping back on leave. The poller only
-- runs while we are actively fading (hidden otherwise) and is throttled, so it costs ~nothing at rest.
local curFadeAlpha, curMouseAlpha = 1, 1   -- winning profile's faded / hovered alphas
local curHoverOn = false                   -- winning profile's mouse-over reveal toggle
local hovering = false

local function AnyWindowHovered()
    local hot = false
    EachWindow(function(inst, frame)
        -- Details! maintains inst.is_interacting = "mouse is over this window", set by its OWN
        -- OnEnter/OnLeaveMainWindow across EVERY part of the window (the title-bar header "Damage Done"
        -- + its option buttons, the background, and the bars). It's the authoritative signal -- a
        -- geometric IsMouseOver on baseframe misses the title-bar strip, which sits above baseframe's hit
        -- rect. Keep IsMouseOver on baseframe + rowframe as a fallback for any skin/mode where the flag
        -- isn't set.
        if inst.is_interacting then hot = true end
        if frame and frame.IsMouseOver and frame:IsMouseOver() then hot = true end
        local rf = inst.rowframe
        if rf and rf.IsMouseOver and rf:IsMouseOver() then hot = true end
    end)
    return hot
end

-- Maintenance ticker: runs ONLY while we hold a dim. Details! restores its OWN saved window alpha at
-- several points after a /reload (synchronously during profile load AND on delayed timers -- including a
-- hard +5s refresh loop) and on every skin/mode change, so a one-shot apply (or even a hook on one of its
-- restore funcs) can lose that race. Re-asserting the target alpha every tick -- but ONLY on windows that
-- have actually drifted off it, so we never fight Details!'s own animations or waste SetAlpha calls --
-- makes the dim self-heal within ~0.1s no matter which path Details! used to overwrite it. The same tick
-- tracks the hover state for the mouse-over reveal.
local hoverPoller = CreateFrame("Frame")
hoverPoller:Hide()
local hoverAccum = 0
hoverPoller:SetScript("OnUpdate", function(_, dt)
    hoverAccum = hoverAccum + dt
    if hoverAccum < 0.1 then return end
    hoverAccum = 0
    hovering = curHoverOn and AnyWindowHovered() or false
    local target = hovering and curMouseAlpha or curFadeAlpha
    EachWindow(function(inst, frame)
        if frame and frame.SetAlpha then
            if math.abs((frame:GetAlpha() or 1) - target) > 0.01 then frame:SetAlpha(target) end
        elseif inst.SetBackgroundAlpha then
            inst:SetBackgroundAlpha(target)
        end
        local rf = inst.rowframe
        if rf and rf.SetAlpha and math.abs((rf:GetAlpha() or 1) - target) > 0.01 then rf:SetAlpha(target) end
    end)
end)

-- Stop the hover reveal and forget the hover state (fading ended / module off).
local function StopHoverReveal()
    hoverPoller:Hide()
    hovering = false
end

-- ── Context evaluation ────────────────────────────────────────────────────────
local function GroupMet(g)
    if not g or not g.enabled then return false end
    local inGroup = IsInGroup()
    local inRaid  = IsInRaid()
    if g.solo  and not inGroup            then return true end
    if g.group and inGroup and not inRaid then return true end
    if g.raid  and inRaid                 then return true end
    if g.custom then
        local count = inGroup and (GetNumGroupMembers() or 1) or 1
        for _, fdef in ipairs(g.custom) do
            if fdef.enabled ~= false and fdef.min and fdef.max
                and count >= fdef.min and count <= fdef.max then
                return true
            end
        end
    end
    return false
end

local function InstanceMet(ins)
    if not ins or not ins.enabled then return false end
    local _, t = IsInInstance()
    if ins.outdoor      and t == "none"  then return true end
    if ins.dungeon      and t == "party" then return true end
    if ins.raid         and t == "raid"  then return true end
    if ins.battleground and t == "pvp"   then return true end
    return false
end

-- A gate (NOT a trigger): when enabled, the profile may only apply in the chosen combat
-- state; disabled = no restriction. Returns whether the profile is allowed right now.
local function CombatGateOk(cb)
    if not cb or not cb.enabled then return true end
    if cb.state == "out" then return not InCombatLockdown() end
    return InCombatLockdown()   -- "in" (default)
end

local fadedByUs = false   -- we are currently holding Details! at the faded alpha
-- The profile we last auto-switched to for the CURRENT matched context. The switch fires only when the
-- wanted profile CHANGES (a real context change), never on every re-evaluation — so once you manually
-- pick another Details profile inside the same context (e.g. a dungeon), the auto-switch stops reforcing
-- it back. Reset to nil when no rule matches, so re-entering the context applies again.
local lastAppliedProfile = nil

-- Evaluate every profile against the current context and apply the winning actions.
-- Re-armed on config change, the relevant events, and the reload hook.
function DP.Apply()
    local c = Cfg()
    if not c or not c.enabled then
        -- Module off: undo any fade we are still holding.
        if fadedByUs and DP.DetailsReady() then StopHoverReveal(); DP.SetDetailsAlpha(1); fadedByUs = false end
        return
    end
    if not DP.DetailsReady() then return end

    local wantFade, fadeAlpha, mouseAlpha, hoverOn, wantProfile = false, 1, 1, false, nil
    for _, p in ipairs(c.profiles or {}) do
        -- Group/instance decide WHAT matches; the combat gate (if on) restricts WHEN.
        if (GroupMet(p.group) or InstanceMet(p.instance)) and CombatGateOk(p.combat) then
            if p.fadeDetails then
                wantFade   = true
                fadeAlpha  = PctToAlpha(p.fadeOpacity)        -- later matching profiles win
                hoverOn    = p.mouseOverEnabled == true       -- mouse-over reveal toggle (default off)
                mouseAlpha = hoverOn and PctToAlpha(p.mouseOverOpacity) or fadeAlpha
            end
            if p.changeProfile and p.profileName and p.profileName ~= "" then
                wantProfile = p.profileName             -- later matching profiles win
            end
        end
    end

    -- Profile switch: fire ONLY on a real context change (wantProfile differs from the last one we acted
    -- on), never on every event — otherwise every roster/zone/combat-end re-forced the profile and
    -- overwrote a manual change ("couldn't switch it back"). Never mid-combat (it resets the meter
    -- windows); in combat we leave lastAppliedProfile untouched so PLAYER_REGEN_ENABLED retries.
    if wantProfile then
        if Details:GetCurrentProfileName() == wantProfile then
            lastAppliedProfile = wantProfile          -- already on it (we or the user) -> context handled
        elseif wantProfile ~= lastAppliedProfile and not InCombatLockdown() then
            Details:ApplyProfile(wantProfile)          -- new context / first entry -> switch ONCE
            lastAppliedProfile = wantProfile
        end
        -- else: same context we already handled (respect a manual switch), or in combat (retry on REGEN)
    else
        lastAppliedProfile = nil                       -- no rule matches now -> re-arm for next entry
    end

    -- Fade: dim to the matching profile's opacity, else restore full opacity once we
    -- leave the fade context (only if we were the one holding it faded).
    if wantFade then
        curFadeAlpha, curMouseAlpha, curHoverOn = fadeAlpha, mouseAlpha, hoverOn
        fadedByUs = true
        hoverPoller:Show()   -- maintenance ticker: holds the dim against Details!'s restores + tracks hover
        DP.SetDetailsAlpha(hovering and curMouseAlpha or curFadeAlpha)
    elseif fadedByUs then
        StopHoverReveal()
        DP.SetDetailsAlpha(1); fadedByUs = false
    end
end

-- After login/reload Details! restores each window's saved alpha at SEVERAL points -- synchronously
-- during profile load AND on delayed startup timers (+1s/+2s plus a hard +5s refresh loop) -- so a fixed
-- timer burst always lost the race past +4s. Every one of those restore/refresh paths (AtivarInstancia,
-- ChangeSkin, the +5s refresh, profile apply, skin/mode changes) funnels through instance:SetMenuAlpha,
-- which sets baseframe + rowframe alpha back to Details!'s own value AFTER us. So instead of racing the
-- timers we HOOK SetMenuAlpha and re-land our dim the instant Details! clobbers it -- no timing guesses.
local hookInstalled = false
local reasserting   = false
local function ReassertFade()
    -- DP.Apply may call Details:ApplyProfile -> re-skin -> SetMenuAlpha -> back here; the flag breaks that.
    if reasserting or not DP.DetailsReady() then return end
    reasserting = true
    DP.Apply()
    reasserting = false
end

local function EnsureDetailsHook()
    if hookInstalled then return end
    if not (Details and Details.SetMenuAlpha and hooksecurefunc) then return end
    hooksecurefunc(Details, "SetMenuAlpha", ReassertFade)
    hookInstalled = true
end

-- Login/reload: install the hook (once Details! exposes SetMenuAlpha) + apply now, plus a short bounded
-- retry to catch the first window build. Once the hook is live it self-heals against Details!'s late
-- refreshes, so the old long +4s burst is no longer needed.
local function ReapplyAfterLoad()
    EnsureDetailsHook()
    DP.Apply()
    C_Timer.After(0.5, function() EnsureDetailsHook(); DP.Apply() end)
    C_Timer.After(2.0, function() EnsureDetailsHook(); DP.Apply() end)
end

-- Combat enter/leave are registered so the "only in combat state" gate (and any combat-gated fade)
-- re-evaluate; the rest cover zone/instance/roster transitions. Login/reload burst-reapply (above).
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_ENTERING_WORLD" and (isInitialLogin or isReloadingUi) then
        ReapplyAfterLoad()
    else
        DP.Apply()
    end
end)

ns.RegisterReloadHook(ReapplyAfterLoad)
