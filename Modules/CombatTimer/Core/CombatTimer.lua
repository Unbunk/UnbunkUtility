-- Modules/CombatTimer/Core/CombatTimer.lua
-- On-screen combat timer: starts counting the instant you enter combat and freezes
-- the duration when you leave, so the last fight's length stays readable until the
-- next pull resets it. Per-profile (ns.db.profile.CombatTimer); the whole module is
-- disabled by default, and only active in the instance types its filter allows.

local _, ns = ...
ns.CombatTimer = ns.CombatTimer or {}
local CT = ns.CombatTimer

local floor   = math.floor
local GetTime = GetTime

-- ── Config ───────────────────────────────────────────────────────────────────
local DEFAULTS = {
    enabled        = false,
    instanceFilter = { dungeon = true, raid = true, battleground = true, outdoor = true },
    fontKey        = "Fira Mono",
    fontPath       = nil,
    fontSize       = 20,
    color          = { r = 1, g = 1, b = 1, a = 1 },
    outline        = "OUTLINE",
    hideOutOfCombat  = false,   -- hide the timer entirely when out of combat
    resetOutOfCombat = false,   -- show 0:00 out of combat instead of the last fight's time
    posX           = 0,
    posY           = -40,
}

function CT.CfgInit()
    if not ns.db then return end
    ns.db.profile.CombatTimer = ns.db.profile.CombatTimer or {}
    ns.MergeDefaults(ns.db.profile.CombatTimer, DEFAULTS)
end
ns.RegisterCfgInitHook(CT.CfgInit)

function CT.CfgGet(key)
    local t = ns.db and ns.db.profile.CombatTimer
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function CT.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.CombatTimer = ns.db.profile.CombatTimer or {}
    ns.db.profile.CombatTimer[key] = value
end

-- ── Frame + text ─────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "UnbunkCombatTimer", UIParent, "BackdropTemplate")
frame:SetSize(120, 40)
frame:SetFrameStrata("MEDIUM")
frame:Hide()

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetPoint("CENTER", frame, "CENTER", 0, 0)
text:SetJustifyH("CENTER")

local startTime   -- GetTime() at combat start; nil when not counting
local frozen      -- last fight's duration (s); nil before the first fight
local ticker

local function UpdateText()
    -- ns.FormatMMSS floors the seconds (standard stopwatch behaviour for elapsed
    -- time) and clamps negatives to 0 — one shared mm:ss implementation instead of
    -- a per-module copy.
    if startTime then
        text:SetText(ns.FormatMMSS(GetTime() - startTime))
    elseif frozen then
        text:SetText(ns.FormatMMSS(frozen))
    else
        text:SetText("0:00")
    end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, UpdateText)
end
local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- ── Apply settings ───────────────────────────────────────────────────────────
function CT.ApplyPosition()
    if CT.IsUnlocked() then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", CT.CfgGet("posX") or 0, CT.CfgGet("posY") or 0)
end

function CT.ApplyFont()
    local path = ns.ResolveFontPath(CT.CfgGet("fontPath"), CT.CfgGet("fontKey"))
    text:SetFont(path, CT.CfgGet("fontSize") or 20, CT.CfgGet("outline") or "")
    local c = CT.CfgGet("color") or { r = 1, g = 1, b = 1, a = 1 }
    text:SetTextColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
end

local function Active()
    return CT.CfgGet("enabled") and ns.IsActiveInInstance(CT.CfgGet("instanceFilter"))
end

-- Re-evaluate visibility without a combat-state change (login / reload / config).
-- Shows the running or frozen value; hides if disabled / filtered out / no fight yet.
function CT.Refresh()
    if CT.IsUnlocked() then return end
    if Active() and startTime then
        -- In combat: counting up.
        CT.ApplyFont()
        CT.ApplyPosition()
        UpdateText()
        frame:Show()
        StartTicker()
    elseif Active() and not CT.CfgGet("hideOutOfCombat")
            and (CT.CfgGet("resetOutOfCombat") or frozen ~= nil) then
        -- Out of combat, visible: the last fight's frozen time, or 0:00 when reset.
        StopTicker()
        CT.ApplyFont()
        CT.ApplyPosition()
        UpdateText()
        frame:Show()
    else
        StopTicker()
        frame:Hide()
    end
end

CT.ApplyEnabled = CT.Refresh

function CT.OnEnterCombat()
    if not Active() then return end
    startTime = GetTime()
    frozen = nil
    CT.ApplyFont()
    CT.ApplyPosition()
    UpdateText()
    frame:Show()
    StartTicker()
end

function CT.OnLeaveCombat()
    if startTime then
        -- Freeze the fight duration, or drop it when "reset out of combat" is on.
        frozen = CT.CfgGet("resetOutOfCombat") and nil or (GetTime() - startTime)
        startTime = nil
    end
    StopTicker()
    CT.Refresh()
end

-- ── Unlock / drag (position editor) ──────────────────────────────────────────
function CT.SetUnlocked(val)
    if val then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", CT.CfgGet("posX") or 0, CT.CfgGet("posY") or 0)
        CT.ApplyFont()
        UpdateText()
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
            CT.CfgSet("posX", x)
            CT.CfgSet("posY", y)
            if CT.pe then CT.pe.Refresh() end
        end)
        frame:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        ns.SetBrandBorder(frame, 0.8)   -- live brand blue
        frame:Show()
    else
        frame:SetMovable(false)
        frame:EnableMouse(false)
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        frame:SetBackdrop(nil)
        CT.Refresh()
    end
end

function CT.IsUnlocked()
    return frame:IsMovable() and frame:IsMouseEnabled()
end

-- ── Reload + login + combat watcher ──────────────────────────────────────────
ns.RegisterReloadHook(function()
    -- Profile switch: drop any stale timer state when out of combat so a fresh
    -- profile starts from a clean baseline. In combat, keep the running timer (its
    -- start is still the real pull, and the new profile may want to show it).
    if not InCombatLockdown() then
        startTime = nil
        frozen = nil
    end
    CT.ApplyFont()
    CT.Refresh()
end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("PLAYER_ENTERING_WORLD")
init:SetScript("OnEvent", function()
    CT.ApplyFont()
    CT.Refresh()
end)

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entering combat
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leaving combat
combatWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        CT.OnEnterCombat()
    else
        CT.OnLeaveCombat()
    end
end)
