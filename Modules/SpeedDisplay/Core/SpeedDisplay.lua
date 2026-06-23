-- Modules/SpeedDisplay/Core/SpeedDisplay.lua
-- On-screen player movement-speed readout, inspired by the ArcWeakAuras speed
-- aura. Shows the current speed as a percentage of base run speed (7 yd/s = 100)
-- and recolours the text by speed tier. The option lives in the General Settings
-- tab, but the config is PER-PROFILE (ns.db.profile.SpeedDisplay) like every other
-- display module, so switching profiles changes the readout.
--
-- SECRET VALUES — in combat GetUnitSpeed("player") can return a "secret value":
-- the addon must NOT read it, compare it, or do arithmetic on it (any of which
-- errors / taints). It may only be passed to a display sink (FontString:SetText),
-- which renders it for the player without revealing it. So when the speed is
-- secret we skip the percentage math + the tier comparison and show the raw value
-- with a neutral colour — exactly the trade-off the source aura makes.

local _, ns = ...
ns.SpeedDisplay = ns.SpeedDisplay or {}
local SD = ns.SpeedDisplay

-- Hot-path globals (the ticker calls these up to 10x/sec) localised once.
local issecretvalue  = issecretvalue
local GetUnitSpeed   = GetUnitSpeed
local IsFlying       = IsFlying
local IsSwimming     = IsSwimming
local UnitInVehicle  = UnitInVehicle
local GetGlidingInfo = C_PlayerInfo and C_PlayerInfo.GetGlidingInfo
local floor          = math.floor

-- 7 yd/s base run speed -> 100%. `or 7` guards the rare case of the Blizzard
-- constant not yet being set when this file loads.
local SPEED_DISPLAY_MULTIPLIER = 100 / (BASE_MOVEMENT_SPEED or 7)

-- Refresh cadence (s). Matches the source aura's 0.1s periodic. The ticker only
-- runs while the readout is shown, and SetText/SetTextColor are skipped when the
-- value/colour is unchanged, so the idle cost stays negligible.
local TICK = 0.1

-- ── Speed-tier colours ───────────────────────────────────────────────────────
-- Hex thresholds from the source aura, converted to 0-1 RGB. Highest matched
-- tier wins; 209 is an exact-match tier sitting between the 65 and 210 bands.
local TIER_PURPLE = { 0.6588, 0.0000, 1.0000 }  -- #A800FF  >= 0
local TIER_BLUE   = { 0.0000, 0.5176, 1.0000 }  -- #0084FF  >= 65
local TIER_TEAL   = { 0.0000, 0.5255, 0.3020 }  -- #00864D  == 209
local TIER_GREEN  = { 0.2706, 1.0000, 0.0000 }  -- #45FF00  >= 210
local TIER_YELLOW = { 0.9765, 1.0000, 0.0000 }  -- #F9FF00  >= 650
local TIER_ORANGE = { 1.0000, 0.2667, 0.0000 }  -- #FF4400  >= 900
local TIER_RED    = { 1.0000, 0.0000, 0.0784 }  -- #FF0014  >= 1150

local function SpeedColor(v)
    if     v >= 1150 then return TIER_RED
    elseif v >= 900  then return TIER_ORANGE
    elseif v >= 650  then return TIER_YELLOW
    elseif v >= 210  then return TIER_GREEN
    elseif v == 209  then return TIER_TEAL
    elseif v >= 65   then return TIER_BLUE
    else                  return TIER_PURPLE
    end
end

-- ── Config ───────────────────────────────────────────────────────────────────
-- Per-profile (ns.db.profile.SpeedDisplay), like every other display module, so
-- switching profiles changes the readout. Disabled by default; default position
-- x=0 y=0; default font "2002 Bold" (the addon-wide default LSM key) with an
-- outline at size 18.
local DEFAULTS = {
    enabled  = false,
    posX     = 0,
    posY     = 0,
    fontSize = 18,
    fontKey  = "Fira Mono",  -- LSM key; resolved via ns.ResolveFontPath (FRIZQT fallback)
    fontPath = nil,
    outline  = "OUTLINE",
}

function SD.CfgInit()
    if not ns.db then return end
    ns.db.profile.SpeedDisplay = ns.db.profile.SpeedDisplay or {}
    ns.MergeDefaults(ns.db.profile.SpeedDisplay, DEFAULTS)
end

ns.RegisterCfgInitHook(SD.CfgInit)

function SD.CfgGet(key)
    local t = ns.db and ns.db.profile.SpeedDisplay
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function SD.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.SpeedDisplay = ns.db.profile.SpeedDisplay or {}
    ns.db.profile.SpeedDisplay[key] = value
end

-- ── Frame ────────────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "UnbunkSpeedDisplay", UIParent, "BackdropTemplate")
frame:SetSize(140, 40)
frame:SetFrameStrata("MEDIUM")
frame:Hide()

-- Centred on the frame but NOT clamped to it, so a large font is never clipped;
-- the 140x40 frame is purely the mouse/drag handle.
local text = frame:CreateFontString(nil, "OVERLAY")
text:SetPoint("CENTER", frame, "CENTER", 0, 0)
text:SetJustifyH("CENTER")

local ticker
local lastText            -- last percentage rendered (nil while secret)
local lastR, lastG, lastB -- last colour rendered
local inCombat = false    -- in combat the player's speed is a "secret value"

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, function() SD.Update() end)
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Mirror of the source aura's speed resolution. Returns a raw speed (yd/s) which
-- MAY be a secret value in combat — the caller must re-test with issecretvalue.
local function ComputeSpeed()
    if GetGlidingInfo then
        local isGliding, _, glidingSpeed = GetGlidingInfo()
        if isGliding then return glidingSpeed end
    end

    local currentSpeed, runSpeed, flightSpeed, swimSpeed = GetUnitSpeed("player")
    if issecretvalue(currentSpeed) then
        return currentSpeed
    elseif currentSpeed ~= 0 then
        return currentSpeed
    elseif UnitInVehicle("player") then
        return GetUnitSpeed("vehicle") or runSpeed
    elseif IsSwimming() then
        return swimSpeed
    elseif IsFlying() then
        return flightSpeed
    else
        return runSpeed
    end
end

function SD.Update()
    local speed = ComputeSpeed()

    -- Secret (in combat): can't multiply or compare. Pass straight to the display
    -- sink and use a neutral colour — the tier can't be evaluated on a secret.
    -- SetText is the secret-aware sink; pcall it so that if a future client ever
    -- makes it non-secret-aware we degrade to a stale value instead of erroring
    -- on every tick.
    if issecretvalue(speed) then
        pcall(text.SetText, text, speed)
        if lastR ~= 1 or lastG ~= 1 or lastB ~= 1 then
            text:SetTextColor(1, 1, 1)
            lastR, lastG, lastB = 1, 1, 1
        end
        lastText = nil  -- force a re-render of the first readable value out of combat
        return
    end

    local pct = floor(speed * SPEED_DISPLAY_MULTIPLIER)
    if pct ~= lastText then
        text:SetText(pct .. "%")
        lastText = pct
    end

    local c = SpeedColor(pct)
    if c[1] ~= lastR or c[2] ~= lastG or c[3] ~= lastB then
        text:SetTextColor(c[1], c[2], c[3])
        lastR, lastG, lastB = c[1], c[2], c[3]
    end
end

-- ── Apply settings ───────────────────────────────────────────────────────────

function SD.ApplyPosition()
    -- Don't fight an in-progress drag: while unlocked the user owns placement
    -- (OnDragStop saves it). A reload-hook re-anchor mid-drag would teleport it.
    if SD.IsUnlocked() then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        SD.CfgGet("posX") or 0,
        SD.CfgGet("posY") or 0)
end

function SD.ApplyFont()
    local path = ns.ResolveFontPath(SD.CfgGet("fontPath"), SD.CfgGet("fontKey"))
    text:SetFont(path, SD.CfgGet("fontSize") or 18, SD.CfgGet("outline") or "")
end

-- Show/hide + ticker driven by the enabled flag. Honours the unlocked state: an
-- unlocked frame stays visible (so it can be positioned) even when disabled.
function SD.ApplyEnabled()
    -- Re-sync combat state: while the module was disabled the combat watcher skipped updating
    -- inCombat (it early-outs), so a mid-combat enable from the config UI could read a stale value.
    inCombat = InCombatLockdown() and true or false
    -- Suppressed in combat: GetUnitSpeed returns a "secret value" there, so the
    -- readout is hidden for the whole fight and restored on PLAYER_REGEN_ENABLED.
    if SD.CfgGet("enabled") and not inCombat then
        -- While unlocked the frame is already shown + ticking for positioning;
        -- leave that to the Lock action (SetUnlocked(false)) so re-enabling can't
        -- strand the frame draggable with the unlock border in normal play.
        if SD.IsUnlocked() then return end
        SD.ApplyPosition()
        SD.ApplyFont()
        frame:Show()
        StartTicker()
        SD.Update()
    elseif not SD.IsUnlocked() then
        StopTicker()
        frame:Hide()
    end
end

-- ── Unlock / drag ────────────────────────────────────────────────────────────

function SD.SetUnlocked(val)
    if val then
        SD.ApplyPosition()
        SD.ApplyFont()
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Compute the centre offset from UIParent directly + re-anchor to a
            -- single CENTER point: StartMoving can leave a different anchor, so
            -- GetPoint() offsets wouldn't match ApplyPosition's CENTER re-anchor and
            -- the readout would jump on the next reapply.
            local es, ues = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local fx, fy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if not (fx and ux and es > 0) then return end
            local x = floor((fx * es - ux * ues) / es)
            local y = floor((fy * es - uy * ues) / es)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
            SD.CfgSet("posX", x)
            SD.CfgSet("posY", y)
            if SD.pe then SD.pe.Refresh() end
        end)
        frame:SetBackdrop({
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        ns.SetBrandBorder(frame, 0.8)   -- live brand blue
        -- Live preview while positioning (and a visible value if disabled/idle).
        StartTicker()
        SD.Update()
        frame:Show()
    else
        frame:SetMovable(false)
        frame:EnableMouse(false)
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        frame:SetBackdrop(nil)
        -- Re-evaluate visibility from the enabled flag now that it's locked again.
        if SD.CfgGet("enabled") then
            frame:Show()
        else
            StopTicker()
            frame:Hide()
        end
    end
end

function SD.IsUnlocked()
    return frame:IsMovable() and frame:IsMouseEnabled()
end

-- ── Profile reload + login bootstrap ─────────────────────────────────────────

ns.RegisterReloadHook(function()
    inCombat = InCombatLockdown() and true or false
    SD.ApplyFont()
    SD.ApplyPosition()
    SD.ApplyEnabled()
end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    inCombat = InCombatLockdown() and true or false
    SD.ApplyFont()
    SD.ApplyPosition()
    SD.ApplyEnabled()
    self:UnregisterEvent("PLAYER_LOGIN")
end)

-- Combat enter/leave: the player's movement speed is a "secret value" in combat,
-- so hide the whole readout (and stop the ticker) for the fight, then restore it.
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entering combat
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leaving combat
combatWatcher:SetScript("OnEvent", function(_, event)
    -- Disabled (and not being positioned): nothing to show/hide on combat transitions, so skip the
    -- ApplyEnabled work entirely. Re-enable is UI-driven (the enable checkbox set handler calls
    -- SD.ApplyEnabled), so this watcher is not the only path back on.
    if not SD.CfgGet("enabled") and not SD.IsUnlocked() then return end
    inCombat = (event == "PLAYER_REGEN_DISABLED")
    SD.ApplyEnabled()
end)
