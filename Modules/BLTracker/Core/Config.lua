-- Modules/BLTracker/Core/Config.lua

local _, ns = ...
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

BLTrackerDB = BLTrackerDB or {}

local DEFAULTS = {
    enabled         = true,
    showIcon        = true,
    iconWidth       = 40,
    iconHeight      = 40,
    posX            = -140,
    posY            = -150,
    timerFontKey    = "2002 Bold",
    timerFontPath   = nil,
    timerFontSize   = 20,
    timerOutline    = "OUTLINE",
    timerColor      = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    soundOnBL       = true,
    soundKeyBL      = "UnbunkUtility: Bloodlust High",
    soundPathBL     = nil,
    soundOnReady    = true,
    soundKeyReady   = "UnbunkUtility: BL Ready High",
    soundPathReady  = nil,
    instanceFilter  = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
}

function BL.CfgInit()
    ns.MigrateSoundKeys(BLTrackerDB)
    ns.MergeDefaults(BLTrackerDB, DEFAULTS)
end
ns.RegisterCfgInitHook(BL.CfgInit)

function BL.CfgGet(key)
    local v = BLTrackerDB[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function BL.CfgSet(key, value)
    BLTrackerDB[key] = value
end

function BL.PlaySound(key)
    ns.PlaySoundFromCfg(BLTrackerDB, key, key:gsub("Path", "Key"))
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    BL.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)