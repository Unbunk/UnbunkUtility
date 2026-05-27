-- Modules/PlayerDeathAnimation/Core/Config.lua

PlayerDeathDB = PlayerDeathDB or {}

local DEFAULTS = {
    enabled       = true,
    soundEnabled  = true,
    soundKey      = "UnbunkUtility: FAHH",
    soundPath     = nil,
    animEnabled   = true,
    animDuration  = 3,
    animWidth     = 250,
    animHeight    = 100,
    posX          = 0,
    posY          = 0,
    animIndex = 1,
    animFPS = 16,
    animLoop = true,
}

function PlayerDeathCfg_Init()
    for k, v in pairs(DEFAULTS) do
        if PlayerDeathDB[k] == nil then
            if type(v) == "table" then
                PlayerDeathDB[k] = {}
                for k2, v2 in pairs(v) do
                    PlayerDeathDB[k][k2] = v2
                end
            else
                PlayerDeathDB[k] = v
            end
        end
    end
end

function PlayerDeathCfg_Get(key) return PlayerDeathDB[key] end
function PlayerDeathCfg_Set(key, value) PlayerDeathDB[key] = value end

function PlayerDeath_PlaySound()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = PlayerDeathCfg_Get("soundPath")
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = PlayerDeathCfg_Get("soundKey")
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    PlayerDeathCfg_Init()
    self:UnregisterEvent("ADDON_LOADED")
end)