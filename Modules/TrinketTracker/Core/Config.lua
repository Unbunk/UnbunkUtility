-- Modules/TrinketTracker/Core/Config.lua

local _, ns = ...
ns.TrinketTracker = ns.TrinketTracker or {}
local TT = ns.TrinketTracker

TrinketTrackerDB = TrinketTrackerDB or {}

local DEFAULTS = {
    enabled        = true,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
    trinket1 = {
        enabled       = true,
        showIcon      = true,
        slot          = 13,
        posX          = 150,
        posY          = -150,
        iconWidth     = 40,
        iconHeight    = 40,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Trinket High",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Trinket Ready High",
        soundPathReady= nil,
    },
    trinket2 = {
        enabled       = true,
        showIcon      = true,
        slot          = 14,
        posX          = 190,
        posY          = -150,
        iconWidth     = 40,
        iconHeight    = 40,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Trinket High",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Trinket Ready High",
        soundPathReady= nil,
    },
}

function TT.CfgInit()
    ns.MigrateSoundKeys(TrinketTrackerDB)
    ns.MergeDefaults(TrinketTrackerDB, DEFAULTS)
end

-- Re-apply defaults + sound migration whenever a profile is loaded/imported/reset.
ns.RegisterCfgInitHook(TT.CfgInit)

function TT.CfgGet(key)
    local v = TrinketTrackerDB[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function TT.CfgSet(key, value)
    TrinketTrackerDB[key] = value
end

function TT.PlaySound(prefix, key)
    local cfg = TT.CfgGet(prefix)
    if not cfg then return end
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey     = "soundPathUse"
        soundKeyKey = "soundKeyUse"
    elseif key == "soundReady" then
        pathKey     = "soundPathReady"
        soundKeyKey = "soundKeyReady"
    else
        return
    end
    ns.PlaySoundFromCfg(cfg, pathKey, soundKeyKey)
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    TT.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)