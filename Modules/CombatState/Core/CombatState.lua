-- Modules/CombatState/Core/CombatState.lua
-- On-screen "Combat state text": shows a customizable message while in combat and
-- (optionally) a different message out of combat. Each text has its OWN appearance
-- (font / size / colour / outline). The text blinks on every combat-state change.
-- Per-profile (ns.db.profile.CombatState); the whole module is disabled by default
-- and only active in the instance types its filter allows. Modelled on SpeedDisplay.

local _, ns = ...
local L = ns.L
ns.CombatState = ns.CombatState or {}
local CS = ns.CombatState

local floor = math.floor

-- ── Config ───────────────────────────────────────────────────────────────────
-- The in-combat (in*) and out-of-combat (out*) texts are styled independently.
local DEFAULTS = {
    enabled         = false,
    instanceFilter  = { dungeon = true, raid = true, battleground = true, outdoor = true },

    -- In-combat text.
    message         = "In Combat",
    inFontKey       = "Fira Mono",
    inFontPath      = nil,
    inFontSize      = 18,
    inColor         = { r = 1, g = 0.2, b = 0.2, a = 1 },
    inOutline       = "OUTLINE",

    -- Out-of-combat text (optional).
    showOutOfCombat = false,
    outOfCombatText = "Out of Combat",
    outFontKey      = "Fira Mono",
    outFontPath     = nil,
    outFontSize     = 18,
    outColor        = { r = 0.4, g = 1, b = 0.4, a = 1 },
    outOutline      = "OUTLINE",

    posX            = 0,
    posY            = 0,
}

function CS.CfgInit()
    if not ns.db then return end
    ns.db.profile.CombatState = ns.db.profile.CombatState or {}
    ns.MergeDefaults(ns.db.profile.CombatState, DEFAULTS)
end
ns.RegisterCfgInitHook(CS.CfgInit)

function CS.CfgGet(key)
    local t = ns.db and ns.db.profile.CombatState
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function CS.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.CombatState = ns.db.profile.CombatState or {}
    ns.db.profile.CombatState[key] = value
end

-- ── Frame + text ─────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "UnbunkCombatStateText", UIParent, "BackdropTemplate")
frame:SetSize(180, 40)
frame:SetFrameStrata("MEDIUM")
frame:Hide()

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetPoint("CENTER", frame, "CENTER", 0, 0)
text:SetJustifyH("CENTER")

-- Blink: pulse the text's alpha a few times on every combat-state change. The
-- group is non-looping, so the text settles back at full alpha when it ends.
local blink = text:CreateAnimationGroup()
for i = 1, 3 do
    local down = blink:CreateAnimation("Alpha")
    down:SetFromAlpha(1); down:SetToAlpha(0.15); down:SetDuration(0.15); down:SetOrder(i * 2 - 1)
    local up = blink:CreateAnimation("Alpha")
    up:SetFromAlpha(0.15); up:SetToAlpha(1); up:SetDuration(0.15); up:SetOrder(i * 2)
end
local function DoBlink()
    blink:Stop()
    blink:Play()
end

local inCombat = false

-- ── Apply settings ───────────────────────────────────────────────────────────
-- Apply the font + colour of the "in" or "out" text to the shared FontString.
local function ApplyAppearanceFor(which)
    local fk = CS.CfgGet(which .. "FontKey")
    local fp = CS.CfgGet(which .. "FontPath")
    local fs = CS.CfgGet(which .. "FontSize") or 18
    local ol = CS.CfgGet(which .. "Outline") or ""
    text:SetFont(ns.ResolveFontPath(fp, fk), fs, ol)
    local c = CS.CfgGet(which .. "Color") or {}
    text:SetTextColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
end

function CS.ApplyPosition()
    if CS.IsUnlocked() then return end   -- while unlocked the user owns placement
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", CS.CfgGet("posX") or 0, CS.CfgGet("posY") or 0)
end

-- The state to show: "in", "out", or nil (hidden), honouring enabled + filter.
local function CurrentState()
    if not CS.CfgGet("enabled") then return nil end
    if not ns.IsActiveInInstance(CS.CfgGet("instanceFilter")) then return nil end
    if inCombat then return "in"
    elseif CS.CfgGet("showOutOfCombat") then return "out" end
    return nil
end

local function ShowState(st, doBlink)
    text:SetText(st == "in" and CS.CfgGet("message") or CS.CfgGet("outOfCombatText"))
    ApplyAppearanceFor(st)
    CS.ApplyPosition()
    frame:Show()
    if doBlink then DoBlink() end
end

-- Re-apply the on-screen text WITHOUT blinking (login / reload / config edits).
function CS.Refresh()
    if CS.IsUnlocked() then return end   -- unlocked owns the preview text
    local st = CurrentState()
    if st then ShowState(st, false) else frame:Hide() end
end

-- Re-apply on a combat-state change, blinking the text when it is shown.
function CS.OnStateChanged()
    if CS.IsUnlocked() then return end
    local st = CurrentState()
    if st then ShowState(st, true) else frame:Hide() end
end

CS.ApplyEnabled = CS.Refresh

-- Config-side helpers: while unlocked, the floating preview reflects whichever
-- text the user is editing so appearance/message tweaks are visible live.
local function PreviewWhich(which, fallback)
    local m = which == "in" and CS.CfgGet("message") or CS.CfgGet("outOfCombatText")
    text:SetText((m and m ~= "") and m or fallback)
    ApplyAppearanceFor(which)
end
function CS.OnInChanged()
    if CS.IsUnlocked() then PreviewWhich("in", L["Combat State Text"]) else CS.Refresh() end
end
function CS.OnOutChanged()
    if CS.IsUnlocked() then PreviewWhich("out", L["Out of Combat"]) else CS.Refresh() end
end

-- ── Unlock / drag (position editor) ──────────────────────────────────────────
function CS.SetUnlocked(val)
    if val then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", CS.CfgGet("posX") or 0, CS.CfgGet("posY") or 0)
        PreviewWhich("in", L["Combat State Text"])
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local es, ues = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local fx, fy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if not (fx and ux and es > 0) then return end
            local x = floor((fx * es - ux * ues) / es)
            local y = floor((fy * es - uy * ues) / es)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
            CS.CfgSet("posX", x)
            CS.CfgSet("posY", y)
            if CS.pe then CS.pe.Refresh() end
        end)
        frame:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        frame:SetBackdropBorderColor(0.20, 0.55, 1.0, 0.8)
        frame:Show()
    else
        frame:SetMovable(false)
        frame:EnableMouse(false)
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        frame:SetBackdrop(nil)
        CS.Refresh()
    end
end

function CS.IsUnlocked()
    return frame:IsMovable() and frame:IsMouseEnabled()
end

-- ── Reload + login + combat watcher ──────────────────────────────────────────
ns.RegisterReloadHook(function()
    inCombat = InCombatLockdown() and true or false
    CS.Refresh()
end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("PLAYER_ENTERING_WORLD")   -- re-evaluate the instance filter on zone change
init:SetScript("OnEvent", function()
    inCombat = InCombatLockdown() and true or false
    CS.Refresh()
end)

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entering combat
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leaving combat
combatWatcher:SetScript("OnEvent", function(_, event)
    inCombat = (event == "PLAYER_REGEN_DISABLED")
    CS.OnStateChanged()
end)
