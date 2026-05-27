-- Modules/PotionTracker/Core/Config.lua

PotionTrackerDB = PotionTrackerDB or {}

local DEFAULTS = {
    enabled         = true,
    instanceFilter  = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = true,
    },
    health = {
        enabled       = true,
        showIcon      = true,
        itemId        = 241304,
        spellId       = 1234768,
        posX          = -400,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Health Potion",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Health Potion Ready",
        soundPathReady= nil,
    },
    combat = {
        enabled       = true,
        showIcon      = true,
        itemId        = 241308,
        spellId       = 1236616,
        posX          = -370,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Combat Potion",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Combat Potion Ready",
        soundPathReady= nil,
    },
}

function PotionTrackerCfg_Init()
    for k, v in pairs(DEFAULTS) do
        if PotionTrackerDB[k] == nil then
            if type(v) == "table" then
                PotionTrackerDB[k] = {}
                for k2, v2 in pairs(v) do
                    if type(v2) == "table" then
                        PotionTrackerDB[k][k2] = {}
                        for k3, v3 in pairs(v2) do
                            PotionTrackerDB[k][k2][k3] = v3
                        end
                    else
                        PotionTrackerDB[k][k2] = v2
                    end
                end
            else
                PotionTrackerDB[k] = v
            end
        end
    end
end

function PotionTrackerCfg_Get(key)
    return PotionTrackerDB[key]
end

function PotionTrackerCfg_Set(key, value)
    PotionTrackerDB[key] = value
end

function PotionTracker_PlaySound(prefix, key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local cfg = PotionTrackerCfg_Get(prefix)
    if not cfg then return end
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey    = "soundPathUse"
        soundKeyKey = "soundKeyUse"
    elseif key == "soundReady" then
        pathKey    = "soundPathReady"
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
    PotionTrackerCfg_Init()
    self:UnregisterEvent("ADDON_LOADED")
end)