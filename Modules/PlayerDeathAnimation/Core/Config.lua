-- Modules/PlayerDeathAnimation/Core/Config.lua

local _, ns = ...
ns.PlayerDeath = ns.PlayerDeath or {}
local PD = ns.PlayerDeath

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
    ns.db.profile.PlayerDeath = ns.db.profile.PlayerDeath or {}
    ns.MigrateSoundKeys(ns.db.profile.PlayerDeath)
    ns.MergeDefaults(ns.db.profile.PlayerDeath, DEFAULTS)
end

ns.RegisterCfgInitHook(PD.CfgInit)

function PD.CfgGet(key)
    local t = ns.db and ns.db.profile.PlayerDeath
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function PD.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.PlayerDeath = ns.db.profile.PlayerDeath or {}
    ns.db.profile.PlayerDeath[key] = value
end

function PD.PlaySound()
    ns.PlaySoundFromCfg(ns.db.profile.PlayerDeath, "soundPath", "soundKey")
end
