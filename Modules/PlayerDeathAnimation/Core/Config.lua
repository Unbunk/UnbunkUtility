-- Modules/PlayerDeathAnimation/Core/Config.lua

local _, ns = ...
ns.PlayerDeath = ns.PlayerDeath or {}
local PD = ns.PlayerDeath

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

function PD.CfgInit()
    ns.MigrateSoundKeys(PlayerDeathDB)
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

function PD.CfgGet(key) return PlayerDeathDB[key] end
function PD.CfgSet(key, value) PlayerDeathDB[key] = value end

function PD.PlaySound()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = PD.CfgGet("soundPath")
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = PD.CfgGet("soundKey")
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    PD.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)
