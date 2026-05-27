-- Modules/PITracker/Core/Config.lua

PITrackerDB = PITrackerDB or {}

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
    soundKeyPI     = "UnbunkUtility: PI",
    soundPathPI    = nil,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
}

function PITrackerCfg_Init()
    for k, v in pairs(DEFAULTS) do
        if PITrackerDB[k] == nil then
            if type(v) == "table" then
                PITrackerDB[k] = {}
                for k2, v2 in pairs(v) do
                    PITrackerDB[k][k2] = v2
                end
            else
                PITrackerDB[k] = v
            end
        end
    end
end

function PITrackerCfg_Get(key) return PITrackerDB[key] end
function PITrackerCfg_Set(key, value) PITrackerDB[key] = value end

function PITracker_PlaySound()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = PITrackerCfg_Get("soundPathPI")
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = PITrackerCfg_Get("soundKeyPI")
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    PITrackerCfg_Init()
    self:UnregisterEvent("ADDON_LOADED")
end)