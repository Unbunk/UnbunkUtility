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
    soundKeyBL      = "UnbunkUtility: Bloodlust",
    soundPathBL     = nil,
    soundOnReady    = true,
    soundKeyReady   = "UnbunkUtility: BL Ready",
    soundPathReady  = nil,
    instanceFilter  = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
}

function BL.CfgInit()
    for k, v in pairs(DEFAULTS) do
        if BLTrackerDB[k] == nil then
            if type(v) == "table" then
                BLTrackerDB[k] = {}
                for k2, v2 in pairs(v) do
                    BLTrackerDB[k][k2] = v2
                end
            else
                BLTrackerDB[k] = v
            end
        end
    end
end

function BL.CfgGet(key)
    return BLTrackerDB[key]
end

function BL.CfgSet(key, value)
    BLTrackerDB[key] = value
end

function BL.PlaySound(key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = BL.CfgGet(key)
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = BL.CfgGet(key:gsub("Path", "Key"))
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    BL.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)