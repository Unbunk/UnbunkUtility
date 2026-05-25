-- Modules/DeathAlert/Core/Config.lua

DeathAlertDB = {}

local DEFAULTS = {
    -- Tank alert
    tankEnabled      = true,
    tankSoundKey     = "UnbunkUtility: Tank Died",
    tankSoundPath    = nil,
    tankEnableSound  = true,
    tankFontKey      = "2002 Bold",
    tankFontPath     = nil,
    tankFontSize     = 22,
    tankOutline      = "",
    tankMessage      = "Tank died!",
    tankColor        = { r = 1.0, g = 0.5, b = 0.0, a = 1.0 },
    tankPosX         = 0,
    tankPosY         = 150,
    -- Healer alert
    healerEnabled     = true,
    healerSoundKey    = "UnbunkUtility: Healer Died",
    healerSoundPath   = nil,
    healerEnableSound = true,
    healerFontKey     = "2002 Bold",
    healerFontPath    = nil,
    healerFontSize    = 22,
    healerOutline     = "",
    healerMessage     = "Healer died!",
    healerColor       = { r = 0.0, g = 0.5, b = 1.0, a = 1.0 },
    healerPosX        = 0,
    healerPosY        = 200,
    tankAlertDuration   = 5,
    healerAlertDuration = 5,
}

local function InitDB()
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
    InitDB()
    self:UnregisterEvent("ADDON_LOADED")
end)