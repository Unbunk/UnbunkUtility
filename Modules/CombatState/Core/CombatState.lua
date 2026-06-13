-- Modules/CombatState/Core/CombatState.lua
-- On-screen "Combat state text": shows a customizable message while in combat and
-- (optionally) a different message out of combat. The text blinks on every combat
-- state change. Per-profile config (ns.db.profile.CombatState); the whole module
-- is disabled by default, and only active in the instance types its filter allows.
-- Modelled on Modules/SpeedDisplay (movable on-screen text + position editor).

local _, ns = ...
ns.CombatState = ns.CombatState or {}
local CS = ns.CombatState

local floor = math.floor

-- ── Config ───────────────────────────────────────────────────────────────────
local DEFAULTS = {
    enabled         = false,
    instanceFilter  = { dungeon = true, raid = true, battleground = true, outdoor = true },
    message         = "In Combat",
    showOutOfCombat = false,
    outOfCombatText = "Out of Combat",
    fontKey         = "2002 Bold",   -- LSM key; resolved via ns.ResolveFontPath (FRIZQT fallback)
    fontPath        = nil,
    fontSize        = 18,
    color           = { r = 1, g = 1, b = 1, a = 1 },
    outline         = "OUTLINE",
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
function CS.ApplyPosition()
    if CS.IsUnlocked() then return end   -- while unlocked the user owns placement
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", CS.CfgGet("posX") or 0, CS.CfgGet("posY") or 0)
end

function CS.ApplyFont()
    local path = ns.ResolveFontPath(CS.CfgGet("fontPath"), CS.CfgGet("fontKey"))
    text:SetFont(path, CS.CfgGet("fontSize") or 18, CS.CfgGet("outline") or "")
    local c = CS.CfgGet("color") or { r = 1, g = 1, b = 1, a = 1 }
    text:SetTextColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
end

-- The message to show for the current state, honouring enabled + the instance
-- filter; nil means "hide".
local function DesiredText()
    if not CS.CfgGet("enabled") then return nil end
    if not ns.IsActiveInInstance(CS.CfgGet("instanceFilter")) then return nil end
    if inCombat then
        return CS.CfgGet("message")
    elseif CS.CfgGet("showOutOfCombat") then
        return CS.CfgGet("outOfCombatText")
    end
    return nil
end

-- Re-apply the on-screen text WITHOUT blinking (login / reload / config edits).
function CS.Refresh()
    if CS.IsUnlocked() then return end   -- unlocked owns the preview text
    local str = DesiredText()
    if str then
        text:SetText(str)
        CS.ApplyFont()
        CS.ApplyPosition()
        frame:Show()
    else
        frame:Hide()
    end
end

-- Re-apply on a combat-state change, blinking the text when it is shown.
function CS.OnStateChanged()
    if CS.IsUnlocked() then return end
    local str = DesiredText()
    if str then
        text:SetText(str)
        CS.ApplyFont()
        CS.ApplyPosition()
        frame:Show()
        DoBlink()
    else
        frame:Hide()
    end
end

-- Called from the config when enable / instance filter changes.
CS.ApplyEnabled = CS.Refresh

-- ── Unlock / drag (position editor) ──────────────────────────────────────────
function CS.SetUnlocked(val)
    if val then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", CS.CfgGet("posX") or 0, CS.CfgGet("posY") or 0)
        CS.ApplyFont()
        local preview = CS.CfgGet("message")
        text:SetText((preview and preview ~= "") and preview or "Combat State Text")
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
