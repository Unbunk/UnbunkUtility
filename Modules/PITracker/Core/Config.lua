-- Modules/PITracker/Core/Config.lua

local _, ns = ...
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

local DEFAULTS = {
    enabled        = true,
    showIcon       = true,
    iconWidth      = 40,
    iconHeight     = 40,
    posX           = -180,
    posY           = -150,
    timerFontKey   = "2002 Bold",
    timerFontPath  = nil,
    timerFontSize  = 20,
    timerOutline   = "OUTLINE",
    timerColor     = { r=1, g=1, b=1, a=1 },
    soundOnPI      = true,
    soundKeyPI     = "UnbunkUtility: PI High",
    soundPathPI    = nil,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
}

function PI.CfgInit()
    ns.db.profile.PITracker = ns.db.profile.PITracker or {}
    ns.MigrateSoundKeys(ns.db.profile.PITracker)
    ns.MergeDefaults(ns.db.profile.PITracker, DEFAULTS)
end
ns.RegisterCfgInitHook(PI.CfgInit)

function PI.CfgGet(key)
    local t = ns.db and ns.db.profile.PITracker
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function PI.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.PITracker = ns.db.profile.PITracker or {}
    ns.db.profile.PITracker[key] = value
end

function PI.PlaySound()
    ns.PlaySoundFromCfg(ns.db.profile.PITracker, "soundPathPI", "soundKeyPI")
end
