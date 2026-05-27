-- Modules/DeathAlert/Core/Config.lua

DeathAlertDB = DeathAlertDB or {}

local DEFAULTS = {
    -- Tank alert
    tankEnabled      = true,
    tankSoundKey     = "UnbunkUtility: Tank Died",
    tankSoundPath    = nil,
    tankEnableSound  = true,
    tankFontKey      = "2002 Bold",
    tankFontPath     = nil,
    tankFontSize     = 26,
    tankOutline      = "OUTLINE",
    tankMessage      = "Tank died",
    tankColor        = { r = 1.0, g = 0.5, b = 0.0, a = 1.0 },
    tankPosX         = 0,
    tankPosY         = 350,
    tankAlertDuration   = 3,
    -- Healer alert
    healerEnabled     = true,
    healerSoundKey    = "UnbunkUtility: Healer Died",
    healerSoundPath   = nil,
    healerEnableSound = true,
    healerFontKey     = "2002 Bold",
    healerFontPath    = nil,
    healerFontSize    = 22,
    healerOutline     = "OUTLINE",
    healerMessage     = "Healer died",
    healerColor       = { r = 0.0, g = 0.5, b = 1.0, a = 1.0 },
    healerPosX        = 0,
    healerPosY        = 275,
    healerAlertDuration = 3,
    -- DPS alert
    dpsEnabled     = false,
    dpsSoundKey    = "UnbunkUtility: DPS Died",
    dpsSoundPath   = nil,
    dpsEnableSound = true,
    dpsFontKey     = "2002 Bold",
    dpsFontPath    = nil,
    dpsFontSize    = 18,
    dpsOutline     = "OUTLINE",
    dpsMessage     = "DPS died",
    dpsColor       = { r = 0.4, g = 0.8, b = 1.0, a = 1.0 },
    dpsPosX        = 0,
    dpsPosY        = 215,
    dpsAlertDuration = 2,
    tankIcon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\TankDied.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 45,
        height     = 60,
    },
    healerIcon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\HealerDied.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 40,
        height     = 50,
    },
    dpsIcon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\DPSDied.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 25,
        height     = 35,
    },
    tankInstanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = false,
    },
    healerInstanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = false,
    },
    dpsInstanceFilter = {
        dungeon      = true,
        raid         = false,
        battleground = false,
        outdoor      = false,
    },
}

function DeathAlertCfg_Init()
    for k, v in pairs(DEFAULTS) do
        if DeathAlertDB[k] == nil then
            if type(v) == "table" then
                DeathAlertDB[k] = {}
                for k2, v2 in pairs(v) do
                    DeathAlertDB[k][k2] = v2
                end
            else
                DeathAlertDB[k] = v
            end
        end
    end
end

function DeathAlertCfg_Get(key)
    return DeathAlertDB[key]
end

function DeathAlertCfg_Set(key, value)
    DeathAlertDB[key] = value
end

function DeathAlertPlaySound(prefix)
    if not DeathAlertCfg_Get(prefix .. "EnableSound") then return end
    local path = DeathAlertCfg_Get(prefix .. "SoundPath")
    local key  = DeathAlertCfg_Get(prefix .. "SoundKey")
    if path then
        PlaySoundFile(path, "Master")
    else
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local fallback = LSM and key and LSM:Fetch("sound", key)
        if fallback then
            PlaySoundFile(fallback, "Master")
        else
            PlaySound(8959)
        end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    DeathAlertCfg_Init()
    self:UnregisterEvent("ADDON_LOADED")
end)