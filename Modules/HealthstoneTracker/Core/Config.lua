-- Modules/HealthstoneTracker/Core/Config.lua

local _, ns = ...
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

local DEFAULTS = {
    enabled        = true,
    showIcon       = true,
    showAtZero     = false,  -- keep the icon visible even with 0 healthstones in bags
    -- itemId / spellId are now resolved dynamically by HT.GetActiveItemId
    -- so every known healthstone (5512, 224464, legacy ranks, etc.) works
    -- as long as one is in the player's bag.
    includeInCdm   = true,           -- default: shown in the CDM…
    cdmDest        = "belowPlayer",  -- …in the artificial row below the PlayerFrame, in the
    cdmAtEnd       = false,          --    FRONT (left) bucket, after the racial + potions
    cdmRow         = 1,
    posX           = -340,
    posY           = -300,
    iconWidth      = 30,
    iconHeight     = 30,
    borderEnabled  = true,
    borderColor    = { r = 0, g = 0, b = 0, a = 1 },
    borderSize     = 1,
    timerFontKey   = "Fira Mono",
    timerFontPath  = nil,
    timerFontSize  = 14,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    -- Stack count text — always shown (no toggle), anchored bottom-right inside by default.
    stackAnchor    = "BOTTOMRIGHT",
    stackOffsetX   = 0,
    stackOffsetY   = 0,
    stackFontKey   = "Fira Mono",
    stackFontPath  = nil,
    stackFontSize  = 12,
    stackOutline   = "OUTLINE",
    stackColor     = { r = 1, g = 1, b = 1, a = 1 },
    soundOnUse     = true,
    soundKeyUse    = "UnbunkUtility: Healthstone (High)",
    soundPathUse   = nil,
    soundOnReady   = true,
    soundKeyReady  = "UnbunkUtility: Healthstone Ready (High)",
    soundPathReady = nil,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
}

-- Default urgency tiers (yellow @15s, red @5s — matching custom icons / defensives).
-- Seeded if missing; never merged so deleting/editing tiers sticks.
local DEFAULT_TIERS = {
    { at = 15, scale = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { at = 5,  scale = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}

function HT.CfgInit()
    ns.db.profile.HealthstoneTracker = ns.db.profile.HealthstoneTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.HealthstoneTracker)
    ns.MergeDefaults(ns.db.profile.HealthstoneTracker, DEFAULTS)
    local t = ns.db.profile.HealthstoneTracker
    if t.timerTiers == nil then t.timerTiers = ns.DeepCopy(DEFAULT_TIERS) end
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
