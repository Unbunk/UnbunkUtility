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
    ns.MergeDefaults(PlayerDeathDB, DEFAULTS)
end

ns.RegisterCfgInitHook(PD.CfgInit)

function PD.CfgGet(key)
    local v = PlayerDeathDB[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function PD.CfgSet(key, value) PlayerDeathDB[key] = value end

function PD.PlaySound()
    ns.PlaySoundFromCfg(PlayerDeathDB, "soundPath", "soundKey")
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    PD.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)
