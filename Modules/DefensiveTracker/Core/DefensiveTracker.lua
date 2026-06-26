-- Modules/DefensiveTracker/Core/DefensiveTracker.lua
-- Tracks the player's class defensive cooldowns as fully-configurable CDM icons — the
-- same icon engine as the custom CDM icons (cooldown swipe + configurable urgency
-- tiers, optional title and stack/charge text, border, sound alerts, CDM-slot or free
-- placement), one per defensive the player knows for their class + current spec.
--
-- The per-class/spec defensive spell list is adapted from Ayije_CDM (CDM.CONST.
-- DEFENSIVE_SPELLS). Each defensive gets a per-spell config entry keyed by spellId.

local ADDON, ns = ...
ns.DefensiveTracker = ns.DefensiveTracker or {}
local DT = ns.DefensiveTracker
local L = ns.L

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(DT)
AceTimer:Embed(DT)

local issecretvalue = issecretvalue or function() return false end
local FALLBACK_ICON = 134400
local GREEN = { r = 0, g = 1, b = 0 }  -- "active buff up" timer colour (shared, read-only)

-- ── Class / spec defensive spell data (adapted from Ayije_CDM) ─────────────────
-- DEFENSIVE_SPELLS[CLASS] = { class = {ids…}, [specID] = {ids…} }. The active list
-- for the player is the class-wide ids plus the current spec's ids.
local DEFENSIVE_SPELLS = {
    WARRIOR = {
        class = { 23920, 97462 },
        [71] = { 118038 }, [72] = { 184364 }, [73] = { 871 },
    },
    PALADIN = {
        class = { 642 },
        [65] = { 498 }, [66] = { 31850, 86659 }, [70] = { 498 },
    },
    HUNTER = {
        class = { 109304, 186265, 264735 },
    },
    ROGUE = {
        class = { 1966, 5277, 31224, 185311 },
    },
    PRIEST = {
        class = { 586, 19236 },
        [258] = { 47585 },
    },
    DEATHKNIGHT = {
        class = { 48707, 48792, 49039, 51052 },
        [250] = { 55233 },
    },
    SHAMAN = {
        class = { 108271 },
    },
    MAGE = {
        class = { 45438, 342245 },
        [62] = { 235450 }, [63] = { 235313 }, [64] = { 11426 },
    },
    WARLOCK = {
        class = { 104773, 108416 },
    },
    MONK = {
        class = { 115203 },
    },
    DRUID = {
        class = { 22812 },
        [103] = { 61336 }, [104] = { 61336 }, [105] = { 102342 },
    },
    DEMONHUNTER = {
        class = { 196718 },
        [577] = { 198589 }, [581] = { 204021 }, [1480] = { 198589 },
    },
    EVOKER = {
        class = { 363916 },
    },
}

-- ── Per-defensive config defaults (mirrors the custom CDM icon) ───────────────
-- Defensives default to FREE placement (the user arranges/includes them per spell);
-- title is healthstone-styled but empty + hidden; sound off; timer tiers seeded.
local DEFAULTS = {
    enabled        = true,   -- per-defensive global toggle (the section's header checkbox)
    showIcon       = true,
    includeInCdm   = true,
    cdmDest        = "belowPlayer",
    cdmAtEnd       = true,    -- end of the below-player row by default
    cdmRow         = 1,
    posX           = -200,
    posY           = -200,
    iconWidth      = 30,
    iconHeight     = 30,
    borderEnabled  = true,
    borderColor    = { r = 0, g = 0, b = 0, a = 1 },
    borderSize     = 1,
    showTimer      = true,
    timerFontKey   = "Fira Mono",
    timerFontPath  = nil,
    timerFontSize  = 14,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    showTitle      = false,
    titleText      = "",
    titleAnchor    = "TOP",
    titleOffsetX   = 0,
    titleOffsetY   = 0,
    titleFontKey   = "Fira Mono",
    titleFontPath  = nil,
    titleFontSize  = 16,
    titleOutline   = "OUTLINE",
    titleColor     = { r = 1, g = 1, b = 1, a = 1 },
    showStack      = true,
    showAtZero     = true,
    stackAnchor    = "BOTTOMRIGHT",
    stackOffsetX   = 0,
    stackOffsetY   = 0,
    stackFontKey   = "Fira Mono",
    stackFontPath  = nil,
    stackFontSize  = 12,
    stackOutline   = "OUTLINE",
    stackColor     = { r = 1, g = 1, b = 1, a = 1 },
    soundOnUse     = false,
    soundKeyUse    = nil,
    soundPathUse   = nil,
    soundOnReady   = false,
    soundKeyReady  = nil,
    soundPathReady = nil,
}

local DEFAULT_TIERS = {
    { at = 15, scale = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { at = 5,  scale = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
local function SeedTiers(e)
    if e and e.timerTiers == nil then e.timerTiers = ns.DeepCopy(DEFAULT_TIERS) end
end

-- live[spellId] = { icon, titleFS, stackFS, lastUseAt, learnedCd, lastExpiry, hasCooldown }
local live = {}
local activeIds = {}   -- ordered list of the spellIds tracked for the current class/spec
local lastSig          -- signature of activeIds, to rebuild the config panel only on change

local function FrameName(spellId) return "UnbunkUtilityDefensive" .. spellId end

-- ── Config store (per-profile) ────────────────────────────────────────────────
local function Cfg()
    if not (ns.db and ns.db.profile) then return nil end
    local c = ns.db.profile.defensiveTracker
    if not c then
        c = { enabled = true, instanceFilter = { dungeon = true, raid = true, battleground = true, outdoor = true }, spells = {} }
        ns.db.profile.defensiveTracker = c
    end
    c.spells = c.spells or {}
    c.instanceFilter = c.instanceFilter or { dungeon = true, raid = true, battleground = true, outdoor = true }
    return c
end

local function SpellCfg(spellId)
    local c = Cfg()
    if not c then return nil end
    local e = c.spells[spellId]
    if not e then
        e = {}
        ns.MergeDefaults(e, DEFAULTS)
        SeedTiers(e)
        c.spells[spellId] = e
    end
    -- Seed the shared free-look schema once per spell (freeExtras is its marker): migrates the legacy
    -- own-draw anchors → the shared Title/Stacks sections, now drawn by TimerIcon (see ApplyTitle/ApplyStack).
    if not e.freeExtras then ns.SeedTrackerFreeLook(e) end
    return e
end

function DT.Enabled() local c = Cfg(); return c and c.enabled end
function DT.GetEntry(spellId) return SpellCfg(spellId) end
function DT.ActiveIds() return activeIds end

-- Module-level config accessors (the panel's General cadre).
function DT.SetEnabled(v)
    local c = Cfg(); if c then c.enabled = v and true or false end
    DT.Sync()      -- live start/stop of the ticker + aura subscription on toggle
    DT.Rebuild()
end
function DT.GetFilter() local c = Cfg(); return c and c.instanceFilter end
function DT.SetFilter(key, val)
    local c = Cfg(); if not c then return end
    c.instanceFilter = c.instanceFilter or {}
    c.instanceFilter[key] = val
end

local function ActiveInInstance()
    local c = Cfg()
    return c and ns.IsActiveInInstance(c.instanceFilter)
end

-- ── Spell helpers ─────────────────────────────────────────────────────────────
local function SpellTexture(spellId)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
    return tex or FALLBACK_ICON
end
function DT.SpellName(spellId)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    return (info and info.name) or ("[" .. tostring(spellId) .. "]")
end
function DT.SpellTexture(spellId) return SpellTexture(spellId) end

local function GetCooldown(spellId)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(spellId)
        if cd then return cd.startTime, cd.duration end
        return 0, 0
    end
    local start, duration = GetSpellCooldown(spellId)
    return start or 0, duration or 0
end

local function GetCharges(spellId)
    if C_Spell and C_Spell.GetSpellCharges then
        local ci = C_Spell.GetSpellCharges(spellId)
        if ci then
            -- In combat these come back as SECRET values that cannot be compared (==/<)
            -- without erroring. Drop any secret field to nil so the truthiness guards
            -- downstream (cur and …, maxc and …) simply skip the charge logic in combat.
            local cur, maxc = ci.currentCharges, ci.maxCharges
            local cdS, cdD  = ci.cooldownStartTime, ci.cooldownDuration
            if issecretvalue(cur)  then cur  = nil end
            if issecretvalue(maxc) then maxc = nil end
            if issecretvalue(cdS)  then cdS  = nil end
            if issecretvalue(cdD)  then cdD  = nil end
            return cur, maxc, cdS, cdD
        end
    end
    return nil
end

local function SpellKnown(spellId)
    if IsPlayerSpell and IsPlayerSpell(spellId) then return true end
    if IsSpellKnown and IsSpellKnown(spellId) then return true end
    return false
end

local function PlaySound(spellId, which)
    local e = SpellCfg(spellId)
    if not e then return end
    if which == "use" then
        ns.PlaySoundFromCfg(e, "soundPathUse", "soundKeyUse")
    elseif which == "ready" then
        ns.PlaySoundFromCfg(e, "soundPathReady", "soundKeyReady")
    end
end
function DT.TestSound(spellId, which) PlaySound(spellId, which) end

-- ── Title + stack FontStrings ─────────────────────────────────────────────────
-- Anchor placement is centralised in ns (Core/Shared.lua) so every icon shares the
-- same modes (edges + 4 inside corners).
local AnchorFS = ns.AnchorFS

-- Default per-icon override-set for a defensive: ONLY Timer (size 14 + urgency thresholds) and
-- Stacks/Charges (size 12, thick outline, X+3). Everything else stays un-overridden -> inherits the group.
function DT.OverrideSeed()
    return {
        timerFontSize = 14,
        timerThresholdsEnabled = true,
        timerThresholds = ns.DefaultTrackerTimerThresholds(),
        stackFontSize = 12, stackOutline = "THICKOUTLINE", stackOffX = 3, stackOffY = -1,
    }
end

-- Title + Stacks are now drawn by the shared TimerIcon (result.ApplyDestExtras) in EVERY mode — free
-- (the icon's own config, via freeExtras=true) and in-CDM (the per-icon override / below-player bucket).
-- So our own FontStrings stay hidden; these remain only to keep ApplyOne's call sites valid.
local function ApplyTitle(spellId)
    local d = live[spellId]
    if d and d.titleFS then d.titleFS:Hide() end
end

local function ApplyStack(spellId)
    local d = live[spellId]
    if d and d.stackFS then d.stackFS:Hide() end
end

-- ── Per-icon per-tick sync ────────────────────────────────────────────────────
local function ApplyOne(spellId)
    local d = live[spellId]
    if not d then return end
    local e = SpellCfg(spellId)
    -- Inert when: module off, not active in this instance, this defensive disabled (its
    -- header checkbox), or the spell isn't known/usable for the current spec.
    if not e or not DT.Enabled() or not ActiveInInstance() or e.enabled == false or not SpellKnown(spellId) then
        d.icon.Hide(); return
    end

    -- The spell texture is static per spellId; SetIcon every tick is wasted work (SetTexture + re-crop).
    -- Cache the last applied texture and only SetIcon when it actually changes.
    local tex = SpellTexture(spellId)
    if tex ~= d.appliedTex then
        d.icon.SetIcon(tex)
        d.appliedTex = tex
    end
    -- (Re)seed the below-player override to the current default version BEFORE ApplySize repaints
    -- (ApplyDestExtras), so the first in-CDM tick reads this defensive's own look, not the bucket default.
    -- ns.ReseedTrackerOverride already early-returns when the override is current, so this is cheap on
    -- the steady-state tick and only does work right after a config (re)seed is due.
    if e.cdmDest == "belowPlayer" then
        ns.ReseedTrackerOverride(FrameName(spellId), "belowPlayer", DT.OverrideSeed)
    end
    d.icon.ApplySize()

    -- Icon visibility = "Show icon" + the charge "show at 0" rule. The cooldown logic
    -- below still runs when hidden, so a sound-only (Show icon off) defensive alerts.
    local cur, maxc, cdStart, cdDur = GetCharges(spellId)
    local hideForZero = cur and maxc and maxc > 1 and cur == 0 and not e.showAtZero
    if e.showIcon ~= false and not hideForZero then
        d.icon.Show()
        ApplyStack(spellId)
        ApplyTitle(spellId)   -- per-tick too, so the in-CDM suppression re-evaluates as the dest changes
    else
        d.icon.Hide()
    end

    -- 1) Green "active" timer while a positive self-buff (same spellId) is up — exact
    -- when readable, else an in-combat estimate from the recorded cast + learned length.
    -- "Enable positive timer" (default OFF for defensives): off → skip the GREEN active-buff timer (live
    -- aura + in-combat heuristic), leaving foundBuff false so the grey cooldown below runs.
    local foundBuff = false
    local positive = (d.icon.ResolveFlag("timerPositiveEnabled") == true)
    local aura = positive and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(spellId) or nil
    if aura and ns.AuraTimerReadable and ns.AuraTimerReadable(spellId) then
        foundBuff = true
        if ns.LearnAuraDuration then ns.LearnAuraDuration(spellId, aura.duration) end
        d.icon.SetTimer(aura.expirationTime, aura.duration, GREEN)
        d.icon.HideCheck()
    elseif positive and d.lastUseAt and UnitAffectingCombat("player") then
        local dur = ns.GetAuraDuration and ns.GetAuraDuration(spellId)
        if dur and dur > 0 and GetTime() < d.lastUseAt + dur then
            foundBuff = true
            d.icon.SetTimer(d.lastUseAt + dur, dur, GREEN)
            d.icon.HideCheck()
        end
    end
    if foundBuff then return end

    -- 2) Multi-charge: show the recharging charge's timer even while a charge remains.
    if maxc and maxc > 1 and cur and cur < maxc and cdStart and not issecretvalue(cdStart)
        and cdStart > 0 and cdDur and cdDur > 0 then
        d.learnedCd   = cdDur
        d.hasCooldown = true
        d.lastExpiry  = cdStart + cdDur
        d.icon.SetTimer(cdStart + cdDur, cdDur)
        d.icon.HideCheck()
        return
    end

    -- 3) Regular spell cooldown (non-charge spells, or a fully-charged one).
    local start, duration = GetCooldown(spellId)
    if issecretvalue(start) or issecretvalue(duration) then
        if d.lastUseAt and d.learnedCd and GetTime() < d.lastUseAt + d.learnedCd then
            d.hasCooldown = true
            d.lastExpiry  = d.lastUseAt + d.learnedCd
            d.icon.SetTimer(d.lastExpiry, d.learnedCd)
        end
    elseif start and start > 0 and duration and duration > 2.5 then
        d.learnedCd  = duration
        d.hasCooldown = true
        d.lastExpiry  = start + duration
        d.icon.SetTimer(start + duration, duration)
    elseif duration and duration > 0 then
        -- GCD blip: keep state.
    else
        if d.hasCooldown then
            d.hasCooldown = false
            local completed = d.lastExpiry and GetTime() >= d.lastExpiry - (ns.READY_EPSILON or 1.5)
            if completed and not (ns.RecentlyZoned and ns.RecentlyZoned()) then
                if e.soundOnReady then PlaySound(spellId, "ready") end
                d.icon.ClearTimer()
                d.icon.BlinkCheck()
            else
                d.icon.ClearTimer()
                d.icon.HideCheck()
            end
        else
            d.icon.ClearTimer()
        end
    end
end

-- ── Icon construction ─────────────────────────────────────────────────────────
local function EnsureIcon(spellId)
    local d = live[spellId]
    if d then return d end
    local icon = ns.ui.CreateTimerIcon({
        name   = FrameName(spellId),
        getCfg = function(key)
            local e = SpellCfg(spellId)
            if not e then
                if key == "includeInCdm" then return false end
                return DEFAULTS[key]
            end
            if e[key] ~= nil then return e[key] end
            return DEFAULTS[key]
        end,
        -- This defensive's own castable spellId -> keybind text / press overlay (resolved override-aware
        -- by ns.CDGKeybinds). Per-icon via the spellId closure.
        getSpellId = function() return spellId end,
        -- In-CDM stacks: the shared icon draws this defensive's charge count (matching the own-draw's
        -- maxCharges>1 gate). Isolated to ResolveCharges — no spellId exposure (keybind/glow unaffected).
        getCount = function()
            -- Return the RAW currentCharges (a SECRET value in combat) so the shared icon can LAUNDER it
            -- through C_StringUtil.TruncateWhenZero for display — the only way to render a secret count in
            -- combat. Do NOT route this through GetCharges(), which issecretvalue->nil drops the count for the
            -- cooldown maths: that nil is exactly why the number vanished in combat. maxCharges is a structural
            -- field that stays readable in combat, so the multi-charge gate is still valid; it is guarded with
            -- issecretvalue anyway so a future secreting of maxCharges degrades to "no count", never an error.
            if C_Spell and C_Spell.GetSpellCharges then
                local ci = C_Spell.GetSpellCharges(spellId)
                local maxc = ci and ci.maxCharges
                if maxc and not issecretvalue(maxc) and maxc > 1 then return ci.currentCharges end
            end
            return nil
        end,
        -- Lets the CDM reorder strips flip cdmAtEnd (Front <-> End bucket) on a cross-strip drag.
        setCfg = function(key, val)
            local e = SpellCfg(spellId)
            if e then e[key] = val end
        end,
        onDragStop = function(x, y)
            local e = SpellCfg(spellId)
            if e then e.posX = x; e.posY = y end
        end,
    })
    icon.onExpire = function() end
    d = { icon = icon }
    local frame = icon.GetFrame()
    d.titleFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    d.stackFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    live[spellId] = d
    return d
end

local function BuildIcon(spellId)
    local d = EnsureIcon(spellId)
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(spellId)
    ApplyOne(spellId)
    return d
end

-- Re-apply one icon's full visuals after a config edit (used by the config panel).
function DT.ApplyIcon(spellId)
    if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- in-CDM size override -> force the engine to re-pack (its layout sig folds the epoch)
    local d = live[spellId]
    if not d then BuildIcon(spellId); return end
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(spellId)
    ApplyOne(spellId)
    -- Force a re-pin: a config edit may not change the placement signature (e.g. a
    -- border/title-only tweak) but the visuals still need to re-apply.
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
end

function DT.Get(spellId, key)
    local e = SpellCfg(spellId)
    if e and e[key] ~= nil then return e[key] end
    return DEFAULTS[key]
end
function DT.Set(spellId, key, val)
    local e = SpellCfg(spellId)
    if not e then return end
    e[key] = val
    DT.ApplyIcon(spellId)
end
function DT.SetUnlocked(spellId, v)
    local d = live[spellId]
    if d then d.icon.SetUnlocked(v) end
end
function DT.IsUnlocked(spellId)
    local d = live[spellId]
    return d and d.icon.IsUnlocked() or false
end

-- ── Resolve the active defensive list for the player's class + current spec ───
local function Resolve()
    activeIds = {}
    local _, classFile = UnitClass("player")
    local set = classFile and DEFENSIVE_SPELLS[classFile]
    if not set then return end
    local seen = {}
    local function add(list)
        if not list then return end
        for _, id in ipairs(list) do
            if not seen[id] and SpellKnown(id) then
                seen[id] = true
                activeIds[#activeIds + 1] = id
            end
        end
    end
    add(set.class)
    local specIndex = GetSpecialization and GetSpecialization()
    local specId = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if specId then add(set[specId]) end
end

-- ── Public sync ───────────────────────────────────────────────────────────────
function DT.UpdateAll()
    if not DT.Enabled() then return end   -- disabled: no per-spell work / allocation
    for _, id in ipairs(activeIds) do ApplyOne(id) end
end

-- (Re)resolve the active list, build any new icons, hide icons no longer active, lay out.
function DT.Rebuild()
    Resolve()
    local activeSet = {}
    for _, id in ipairs(activeIds) do activeSet[id] = true; BuildIcon(id) end
    -- Hide any previously-built icon that is no longer in the active list.
    for id, d in pairs(live) do
        if not activeSet[id] then d.icon.Hide() end
    end
    -- Rebuild the config panel only when the tracked set actually changed (spec/talent),
    -- not on every SPELLS_CHANGED, so an open panel isn't churned needlessly.
    local sig = table.concat(activeIds, ",")
    if sig ~= lastSig then
        lastSig = sig
        if ns.InvalidatePanel then ns.InvalidatePanel(L["Defensive Tracker"]) end
    end
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
    if DT.Sync then DT.Sync() end   -- reconcile live drivers with enabled state (DB now ready)
end
DT.ApplyAll = DT.Rebuild

-- ── Events ────────────────────────────────────────────────────────────────────
-- UNIT_SPELLCAST_SUCCEEDED on its own RegisterUnitEvent("player") frame: AceEvent has no
-- unit filter, so an unfiltered registration would wake for every unit's cast in a raid.
local castFrame = CreateFrame("Frame")
castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castFrame:SetScript("OnEvent", function(_, _, unit, _, spellId)
    if unit ~= "player" then return end
    local d = live[spellId]
    if d then
        d.lastUseAt = GetTime()   -- recorded for the in-combat estimate regardless
        local e = SpellCfg(spellId)
        if e and e.enabled ~= false and e.soundOnUse and DT.Enabled() then PlaySound(spellId, "use") end
    end
end)

-- SPELL_UPDATE_COOLDOWN fires on essentially every cast/GCD; running the full UpdateAll
-- synchronously per event (stacked on the 0.5s ticker) is wasteful. Debounce: set a dirty
-- flag and flush once on the next frame, coalescing a burst of events into one UpdateAll.
local cdDirty = false
local function FlushCooldown()
    cdDirty = false
    DT.UpdateAll()
end
DT:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
    if cdDirty or not DT.Enabled() then return end   -- disabled: don't schedule a flush
    cdDirty = true
    C_Timer.After(0, FlushCooldown)
end)
DT:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit == "player" then DT.Rebuild() end
end)
DT:RegisterEvent("SPELLS_CHANGED", function() DT.Rebuild() end)

-- ── Always-on drivers, owned so the disabled module is fully stopped ──────────
-- The 0.5s sync ticker and the player-aura subscription are the two continuous drivers.
-- When disabled we Cancel()/Unregister() them outright (not just early-out), so a disabled
-- Defensive Tracker costs ~zero. DT.Start/Stop are idempotent; SetEnabled + login drive them.
local syncTicker          -- truthy while the shared-tick "defensive" callback is registered
local auraCb              -- our AuraDispatch("player") callback handle

function DT.Start()
    if not syncTicker then
        ns.SharedTick.Register("defensive", function() DT.UpdateAll() end)
        syncTicker = true
    end
    -- Coalesced player-aura subscription (shared dispatcher, at most one fire per frame): lets the
    -- green "active buff up" timer react instantly out of combat instead of lagging up to ~0.5s for
    -- the next ticker. Just calls UpdateAll — cheap and additive (no unfiltered UNIT_AURA).
    if ns.AuraDispatch and not auraCb then
        auraCb = ns.AuraDispatch.Register("player", function() DT.UpdateAll() end)
    end
end

function DT.Stop()
    if syncTicker then ns.SharedTick.Unregister("defensive"); syncTicker = nil end
    if ns.AuraDispatch and auraCb then ns.AuraDispatch.Unregister("player", auraCb); auraCb = nil end
end

-- Reconcile the live drivers with the current enabled state (called at login/reload and on toggle).
function DT.Sync()
    if DT.Enabled() then DT.Start() else DT.Stop() end
end

ns.RegisterReloadHook(function() DT.Rebuild() end)

local initDT = CreateFrame("Frame")
initDT:RegisterEvent("PLAYER_LOGIN")
initDT:SetScript("OnEvent", function(self)
    DT.Rebuild()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
