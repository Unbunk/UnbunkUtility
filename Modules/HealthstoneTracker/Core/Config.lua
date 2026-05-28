-- Modules/HealthstoneTracker/Core/Config.lua

local _, ns = ...
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

HealthstoneTrackerDB = HealthstoneTrackerDB or {}

local DEFAULTS = {
    enabled        = true,
    showIcon       = true,
    itemId         = 5512,    -- Healthstone (canonical retail item)
    spellId        = 6262,    -- "Healthstone" use spell
    posX           = -340,
    posY           = -300,
    iconWidth      = 30,
    iconHeight     = 30,
    timerFontKey   = "2002 Bold",
    timerFontPath  = nil,
    timerFontSize  = 20,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    soundOnUse     = true,
    soundKeyUse    = "UnbunkUtility: Healthstone High",
    soundPathUse   = nil,
    soundOnReady   = true,
    soundKeyReady  = "UnbunkUtility: Healthstone Ready High",
    soundPathReady = nil,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
}

function HT.CfgInit()
    ns.MigrateSoundKeys(HealthstoneTrackerDB)
    for k, v in pairs(DEFAULTS) do
        if HealthstoneTrackerDB[k] == nil then
            if type(v) == "table" then
                HealthstoneTrackerDB[k] = {}
                for k2, v2 in pairs(v) do
                    HealthstoneTrackerDB[k][k2] = v2
                end
            else
                HealthstoneTrackerDB[k] = v
            end
        end
    end
end

function HT.CfgGet(key) return HealthstoneTrackerDB[key] end
function HT.CfgSet(key, value) HealthstoneTrackerDB[key] = value end

function HT.PlaySound(key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey, soundKeyKey = "soundPathUse", "soundKeyUse"
    elseif key == "soundReady" then
        pathKey, soundKeyKey = "soundPathReady", "soundKeyReady"
    else
        return
    end
    local path = HT.CfgGet(pathKey)
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = HT.CfgGet(soundKeyKey)
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    HT.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)
