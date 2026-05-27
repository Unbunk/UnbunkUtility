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
        soundKeyUse   = "UnbunkUtility: Trinket",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Trinket Ready",
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
        soundKeyUse   = "UnbunkUtility: Trinket",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Trinket Ready",
        soundPathReady= nil,
    },
}

function TT.CfgInit()
    for k, v in pairs(DEFAULTS) do
        if TrinketTrackerDB[k] == nil then
            if type(v) == "table" then
                TrinketTrackerDB[k] = {}
                for k2, v2 in pairs(v) do
                    if type(v2) == "table" then
                        TrinketTrackerDB[k][k2] = {}
                        for k3, v3 in pairs(v2) do
                            TrinketTrackerDB[k][k2][k3] = v3
                        end
                    else
                        TrinketTrackerDB[k][k2] = v2
                    end
                end
            else
                TrinketTrackerDB[k] = v
            end
        end
    end
end

function TT.CfgGet(key)
    return TrinketTrackerDB[key]
end

function TT.CfgSet(key, value)
    TrinketTrackerDB[key] = value
end

function TT.PlaySound(prefix, key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
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
    local path = cfg[pathKey]
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = cfg[soundKeyKey]
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    TT.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)