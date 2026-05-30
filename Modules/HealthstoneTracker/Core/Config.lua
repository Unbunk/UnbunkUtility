-- Modules/HealthstoneTracker/Core/Config.lua

local _, ns = ...
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

HealthstoneTrackerDB = HealthstoneTrackerDB or {}

local DEFAULTS = {
    enabled        = true,
    showIcon       = true,
    -- itemId / spellId are now resolved dynamically by HT.GetActiveItemId
    -- so every known healthstone (5512, 224464, legacy ranks, etc.) works
    -- as long as one is in the player's bag.
    posX           = -340,
    posY           = -300,
    iconWidth      = 30,
    iconHeight     = 30,
    timerFontKey   = "2002 Bold",
    timerFontPath  = nil,
    timerFontSize  = 20,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    -- Stack count text below the icon — always shown (no toggle).
    stackFontKey   = "2002 Bold",
    stackFontPath  = nil,
    stackFontSize  = 12,
    stackOutline   = "OUTLINE",
    stackColor     = { r = 1, g = 1, b = 1, a = 1 },
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
    ns.MergeDefaults(HealthstoneTrackerDB, DEFAULTS)
end
ns.RegisterCfgInitHook(HT.CfgInit)

function HT.CfgGet(key)
    local v = HealthstoneTrackerDB[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function HT.CfgSet(key, value) HealthstoneTrackerDB[key] = value end

function HT.PlaySound(key)
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey, soundKeyKey = "soundPathUse", "soundKeyUse"
    elseif key == "soundReady" then
        pathKey, soundKeyKey = "soundPathReady", "soundKeyReady"
    else
        return
    end
    ns.PlaySoundFromCfg(HealthstoneTrackerDB, pathKey, soundKeyKey)
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    HT.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)
