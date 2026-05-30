-- Modules/HealerRange/Core/Config.lua

local _, ns = ...
local L = ns.L
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

HealerRangeDB = HealerRangeDB or {}

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
    ns.MigrateSoundKeys(HealerRangeDB)
    ns.MergeDefaults(HealerRangeDB, DEFAULTS)
end

ns.RegisterCfgInitHook(HR.CfgInit)

function HR.CfgGet(key)
    local v = HealerRangeDB[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function HR.CfgSet(key, value)
    HealerRangeDB[key] = value
end

function HR.PlaySound()
    if not HR.CfgGet("enableSound") then return end
    ns.PlaySoundFromCfg(HealerRangeDB, "soundPath", "soundKey")
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    HR.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)