-- Modules/HealthstoneTracker/Core/Config.lua

local _, ns = ...
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

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
    borderEnabled  = true,
    borderColor    = { r = 0, g = 0, b = 0, a = 1 },
    borderSize     = 1,
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
    ns.db.profile.HealthstoneTracker = ns.db.profile.HealthstoneTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.HealthstoneTracker)
    ns.MergeDefaults(ns.db.profile.HealthstoneTracker, DEFAULTS)
end
ns.RegisterCfgInitHook(HT.CfgInit)

function HT.CfgGet(key)
    local t = ns.db and ns.db.profile.HealthstoneTracker
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function HT.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.HealthstoneTracker = ns.db.profile.HealthstoneTracker or {}
    ns.db.profile.HealthstoneTracker[key] = value
end

function HT.PlaySound(key)
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey, soundKeyKey = "soundPathUse", "soundKeyUse"
    elseif key == "soundReady" then
        pathKey, soundKeyKey = "soundPathReady", "soundKeyReady"
    else
        return
    end
    ns.PlaySoundFromCfg(ns.db and ns.db.profile.HealthstoneTracker, pathKey, soundKeyKey)
end
