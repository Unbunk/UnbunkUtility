-- Core/CDMEditModeLock.lua
-- Lock the Essential / Utility Cooldown Manager viewers in Blizzard's Edit Mode.
-- UnbunkUtility owns their position + per-row icon size, so the
-- native Edit Mode controls would fight ours — we therefore: hide the Edit Mode settings
-- dialog whenever it attaches to one of these viewers, clear the selection's drag scripts so it
-- can't be moved (NOT frame:SetMovable(false) — that taints a registered Edit Mode system, which
-- crashes Blizzard's secure passes in 12.1.0), and overlay a short "managed by UnbunkUtility" note
-- while it's selected. All four native
-- Cooldown Manager viewers are locked — Essential, Utility, Tracked Buffs (buff icons,
-- owned by BuffGroups) and Tracked Bars (buff bars, owned by BarGroups). The below-player
-- row is our own frame, not an Edit Mode system, so it is not listed here.
--
-- ALL of this is gated on the "Enable Cooldown Manager takeover" master switch
-- (ns.IsCDMTakeoverEnabled): with it OFF the addon has fully ceded the CDM back to Blizzard, so the
-- native viewers must be draggable in Edit Mode again like any other system. ns.CDMEditModeLock.Apply()
-- re-syncs the lock/unlock state to the switch and is called from Mode.lua's M.Apply() (world enter,
-- profile reload, and the switch itself), so a live toggle takes effect without a /reload.

local ADDON, ns = ...
-- NOTE: this file loads before the locale engine creates ns.L, so DON'T cache it here
-- (`local L = ns.L` would capture nil). All strings are looked up via Loc() at runtime.
local function Loc(key) return (ns.L and ns.L[key]) or key end

local function TakeoverOn() return ns.IsCDMTakeoverEnabled and ns.IsCDMTakeoverEnabled() end

-- The four native CooldownViewer Edit Mode systems whose layout UnbunkUtility owns
-- (CDMGroups: Essential/Utility; BuffGroups: Tracked Buffs; BarGroups: Tracked Bars).
local LOCK_NAMES = {
    ns.CDM_VIEWER.essential, ns.CDM_VIEWER.utility,
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
}

local function IsCooldownViewerSystem(frame)
    local sys = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
    return (sys and frame and frame.system == sys) and true or false
end

-- One of the viewers we lock?
local function IsLockedViewer(frame)
    if not IsCooldownViewerSystem(frame) then return false end
    local nm = frame.GetName and frame:GetName()
    for _, name in ipairs(LOCK_NAMES) do
        if nm == name then return true end
    end
    return false
end

-- ── "Managed by UnbunkUtility" overlay shown on the selection while it's active ──
local lockState = setmetatable({}, { __mode = "k" })   -- selection -> { overlay, text, token }

local function EnsureLockText(selection)
    local st = lockState[selection]
    if st and st.text then return st end
    st = st or {}
    if not st.overlay then
        st.overlay = CreateFrame("Frame", nil, selection)
        st.overlay:SetAllPoints(selection)
        st.overlay:SetFrameLevel(selection:GetFrameLevel() + 5)
        -- The note must be free to spill past the (often narrow) viewer edges, so never
        -- clip our overlay's children to its rect.
        st.overlay:SetClipsChildren(false)
    end
    local t = st.overlay:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH4")
    -- Much bigger than the H4 default: keep the font face, bump to a large size with a
    -- thick outline so the lock notice is clearly visible over the cooldown icons.
    local fp = t:GetFont()
    t:SetFont(fp or "Fonts\\FRIZQT__.TTF", 32, "THICKOUTLINE")
    t:SetPoint("CENTER")
    -- One centred line, word-wrap OFF: the auto-sized FontString overflows the viewer's
    -- left/right edges instead of wrapping inside a narrow cadre.
    t:SetJustifyH("CENTER"); t:SetJustifyV("MIDDLE"); t:SetWordWrap(false)
    t:SetTextColor(1, 0.3, 0.2)
    st.text = t
    lockState[selection] = st
    return st
end

local function ShowLockText(frame, shown)
    local selection = frame.Selection
    if not selection then return end
    if not shown then
        -- The hide path must ALWAYS run, even in combat: skipping it (e.g. the 2s
        -- auto-hide firing mid-fight) would leave the overlay stuck on screen. These
        -- are display-only regions (a plain Frame + a FontString, never protected),
        -- so hiding them in combat is safe.
        local st = lockState[selection]
        if st then
            if st.text then st.text:Hide() end
            if st.overlay then st.overlay:Hide() end
        end
        return
    end
    -- Show creates the overlay/FontString on first use (CreateFrame is taint-safe but
    -- can taint a protected parent's execution path), so keep the combat guard here.
    if InCombatLockdown() then return end
    local st = EnsureLockText(selection)
    st.overlay:Show()
    st.text:SetText(Loc("Managed by UnbunkUtility (/ubu)"))
    st.text:Show()
end

local handlersSet = setmetatable({}, { __mode = "k" })
local function SetupHandlers(frame)
    local selection = frame.Selection
    if not selection or handlersSet[selection] then return end
    handlersSet[selection] = true
    -- Flash the note on click, auto-hiding after 2s (token guards against overlap). HookScript is
    -- permanent for the session, so re-check the takeover switch live on every click rather than only
    -- at install time — with the switch OFF this viewer is no longer ours to annotate.
    selection:HookScript("OnMouseDown", function()
        if not TakeoverOn() then return end
        ShowLockText(frame, true)
        local st = lockState[selection]
        local token = ((st and st.token) or 0) + 1
        if st then st.token = token end
        C_Timer.After(2, function()
            local s2 = lockState[selection]
            if s2 and s2.token == token then ShowLockText(frame, false) end
        end)
    end)
    selection:HookScript("OnHide", function() ShowLockText(frame, false) end)
end

local noticeShown = false
local function ShowNotice()
    if noticeShown then return end
    noticeShown = true
    ns.Print(Loc("Cooldown Manager viewers are managed by UnbunkUtility — configure them in /ubu."))
end

-- Prevent the viewer being dragged in Edit Mode by clearing the SELECTION's drag scripts, instead of
-- frame:SetMovable(false). SetMovable is a durable state write on a REGISTERED Edit Mode system; in
-- 12.1.0 (secret frame state) tainting such a system crashes Blizzard's secure RefreshEncounterEvents /
-- HideSystemSelections ("secret number value") on Edit Mode enter/exit. Clearing OnDragStart/Stop on
-- the selection is a handler change (not a geometry/movable write on the system) -> taint-safe, and
-- alone it stops the drag (no OnDragStart = no StartMoving). Re-applied on every SelectSystem in case
-- Blizzard re-installs the handlers.
--
-- The native OnDragStart/OnDragStop are saved off the FIRST time a given selection is killed (per kill
-- cycle — RestoreDrag clears the "killed" flag so a later re-kill re-captures fresh handlers, in case
-- Blizzard re-installed new ones while we were unlocked), so RestoreDrag can hand them straight back
-- when the takeover switch flips OFF and give Edit Mode its native dragging back.
local dragState = setmetatable({}, { __mode = "k" })   -- selection -> { start, stop, killed }

local function KillDrag(frame)
    local selection = frame and frame.Selection
    if not selection then return end
    local st = dragState[selection]
    if not st then st = {}; dragState[selection] = st end
    if not st.killed then
        st.start = selection:GetScript("OnDragStart")
        st.stop = selection:GetScript("OnDragStop")
        st.killed = true
    end
    selection:SetScript("OnDragStart", nil)
    selection:SetScript("OnDragStop", nil)
end

-- Give the native drag handlers back — a plain handler swap, never protected, so it's safe in combat
-- too. A no-op if this selection was never killed (nothing saved).
local function RestoreDrag(frame)
    local selection = frame and frame.Selection
    local st = selection and dragState[selection]
    if not st or not st.killed then return end
    selection:SetScript("OnDragStart", st.start)
    selection:SetScript("OnDragStop", st.stop)
    st.killed = false
end

-- Lock/unlock every native viewer to match the live takeover switch. Called on setup, and again from
-- Mode.lua's M.Apply() on every world enter / profile reload / takeover toggle, so a live flip takes
-- effect immediately without a /reload.
local didSetup = false   -- declared here (not below, next to TrySetup) so Apply can close over it: see guard below
local function Apply()
    -- Mode.lua's M.Apply() can reach us (PLAYER_ENTERING_WORLD, profile reload) before TrySetup() has ever
    -- run, e.g. if Blizzard_EditMode hasn't loaded yet. Bail out then: IsLockedViewer would already no-op
    -- via the missing frame.system, but bailing explicitly avoids KillDrag ever capturing a not-yet-wired
    -- (nil) native drag handler as this selection's "killed" baseline.
    if not didSetup then return end
    local on = TakeoverOn()
    for _, name in ipairs(LOCK_NAMES) do
        local f = _G[name]
        if IsLockedViewer(f) then
            if on then
                KillDrag(f)
                SetupHandlers(f)
            else
                RestoreDrag(f)
                ShowLockText(f, false)
            end
        end
    end
end
ns.CDMEditModeLock = { Apply = Apply }

local function TrySetup()
    local dialog = _G.EditModeSystemSettingsDialog
    if not (dialog and Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer) then
        return false
    end
    if didSetup then return true end
    didSetup = true

    -- The settings dialog attaching to a locked viewer -> close it immediately (takeover ON only: with
    -- it OFF the addon has ceded this viewer, so the native dialog must be allowed to open normally).
    hooksecurefunc(dialog, "AttachToSystemFrame", function(dlg, systemFrame)
        if not IsLockedViewer(systemFrame) then return end
        if not TakeoverOn() then return end
        dlg:Hide()
        SetupHandlers(systemFrame)
        ShowNotice()
    end)

    for _, name in ipairs(LOCK_NAMES) do
        local f = _G[name]
        if IsLockedViewer(f) then
            hooksecurefunc(f, "SelectSystem", function(sf)
                -- Permanent hook (hooksecurefunc can't be removed): re-check the switch live on every
                -- selection, not just at install time, so turning takeover OFF stops re-locking a
                -- viewer the addon no longer owns.
                if not TakeoverOn() then return end
                KillDrag(sf)   -- taint-safe drag lock (NOT SetMovable — see KillDrag)
                if dialog.attachedToSystem == sf then dialog:Hide() end
                SetupHandlers(sf)
                ShowNotice()
            end)
            hooksecurefunc(f, "HighlightSystem", function(sf) SetupHandlers(sf) end)
            hooksecurefunc(f, "ClearHighlight", function(sf) ShowLockText(sf, false) end)
        end
    end

    Apply()
    return true
end

if not TrySetup() then
    -- Edit Mode loads on demand; wire up once it does.
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", TrySetup)
    end
end
