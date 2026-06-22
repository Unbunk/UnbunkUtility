-- Core/CDMEditModeLock.lua
-- Lock the Essential / Utility Cooldown Manager viewers in Blizzard's Edit Mode (the same
-- approach Ayije_CDM uses). UnbunkUtility owns their position + per-row icon size, so the
-- native Edit Mode controls would fight ours — we therefore: hide the Edit Mode settings
-- dialog whenever it attaches to one of these viewers, make the frame non-movable, and
-- overlay a short "managed by UnbunkUtility" note while it's selected. All four native
-- Cooldown Manager viewers are locked — Essential, Utility, Tracked Buffs (buff icons,
-- owned by BuffGroups) and Tracked Bars (buff bars, owned by BarGroups). The below-player
-- row is our own frame, not an Edit Mode system, so it is not listed here.

local ADDON, ns = ...
-- NOTE: this file loads before the locale engine creates ns.L, so DON'T cache it here
-- (`local L = ns.L` would capture nil). All strings are looked up via Loc() at runtime.
local function Loc(key) return (ns.L and ns.L[key]) or key end

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
    if InCombatLockdown() then return end
    local selection = frame.Selection
    if not selection then return end
    if not shown then
        local st = lockState[selection]
        if st then
            if st.text then st.text:Hide() end
            if st.overlay then st.overlay:Hide() end
        end
        return
    end
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
    -- Flash the note on click, auto-hiding after 2s (token guards against overlap).
    selection:HookScript("OnMouseDown", function()
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

local function LockFrames()
    for _, name in ipairs(LOCK_NAMES) do
        local f = _G[name]
        if IsLockedViewer(f) then
            f:SetMovable(false)
            local selection = f.Selection
            if selection then
                selection:SetScript("OnDragStart", nil)
                selection:SetScript("OnDragStop", nil)
            end
            SetupHandlers(f)
        end
    end
end

local didSetup = false
local function TrySetup()
    local dialog = _G.EditModeSystemSettingsDialog
    if not (dialog and Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer) then
        return false
    end
    if didSetup then return true end
    didSetup = true

    -- The settings dialog attaching to a locked viewer -> close it immediately.
    hooksecurefunc(dialog, "AttachToSystemFrame", function(dlg, systemFrame)
        if not IsLockedViewer(systemFrame) then return end
        dlg:Hide()
        SetupHandlers(systemFrame)
        ShowNotice()
    end)

    for _, name in ipairs(LOCK_NAMES) do
        local f = _G[name]
        if IsLockedViewer(f) then
            hooksecurefunc(f, "SelectSystem", function(sf)
                sf:SetMovable(false)
                if dialog.attachedToSystem == sf then dialog:Hide() end
                SetupHandlers(sf)
                ShowNotice()
            end)
            hooksecurefunc(f, "HighlightSystem", function(sf) SetupHandlers(sf) end)
            hooksecurefunc(f, "ClearHighlight", function(sf) ShowLockText(sf, false) end)
        end
    end

    LockFrames()
    return true
end

if not TrySetup() then
    -- Edit Mode loads on demand; wire up once it does.
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", TrySetup)
    end
end
