-- Modules/PITracker/Core/Config.lua

local _, ns = ...
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

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
    ns.MigrateSoundKeys(PITrackerDB)
    ns.MergeDefaults(PITrackerDB, DEFAULTS)
end
ns.RegisterCfgInitHook(PI.CfgInit)

function PI.CfgGet(key)
    local v = PITrackerDB[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function PI.CfgSet(key, value) PITrackerDB[key] = value end

function PI.PlaySound()
    ns.PlaySoundFromCfg(PITrackerDB, "soundPathPI", "soundKeyPI")
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    PI.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)
