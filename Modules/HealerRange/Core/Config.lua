-- Modules/HealerRange/Core/Config.lua

local _, ns = ...
local L = ns.L
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

local DEFAULTS = {
    enabled       = true,
    soundPath     = nil,
    soundKey      = "UnbunkUtility: No Heal High",
    enableSound   = true,
    fontPath      = nil,
    fontKey       = "2002 Bold",
    fontSize      = 22,
    outline       = "OUTLINE",
    alertMessage  = L["No Heal"],
    color         = { r = 1.0, g = 0.059, b = 0.0, a = 1.0 },
    posX          = 0,
    posY          = 100,
    alertDuration = 5,
    icon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\NoHeal.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 32,
        height     = 32,
    },
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = false,
    },
}

function HR.CfgInit()
    ns.db.profile.HealerRange = ns.db.profile.HealerRange or {}
    ns.MigrateSoundKeys(ns.db.profile.HealerRange)
    ns.MergeDefaults(ns.db.profile.HealerRange, DEFAULTS)
end

ns.RegisterCfgInitHook(HR.CfgInit)

function HR.CfgGet(key)
    local t = ns.db and ns.db.profile.HealerRange
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function HR.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.HealerRange = ns.db.profile.HealerRange or {}
    ns.db.profile.HealerRange[key] = value
end

function HR.PlaySound()
    if not HR.CfgGet("enableSound") then return end
    ns.PlaySoundFromCfg(ns.db.profile.HealerRange, "soundPath", "soundKey")
end