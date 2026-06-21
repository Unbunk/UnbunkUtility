-- Modules/PotionTracker/Core/Config.lua

local _, ns = ...
ns.PotionTracker = ns.PotionTracker or {}
local PT = ns.PotionTracker

local DEFAULTS = {
    enabled         = true,
    instanceFilter  = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = true,
    },
    health = {
        enabled         = true,
        showIcon        = true,
        showAtZero      = false,  -- keep the icon visible even with 0 potions in bags
        -- Default: in the Cooldown Manager's artificial below-player row, in the
        -- FRONT (left) bucket (cdmAtEnd=false), beside the racial. Falls back to the
        -- free position below (posX/posY) when the Cooldown Manager is disabled.
        includeInCdm    = true,
        cdmDest         = "belowPlayer",
        cdmAtEnd        = false,
        cdmRow          = 1,
        -- itemId/spellId left unset on a fresh install: the main dropdown
        -- shows "None" until the player picks a potion or the resolver
        -- auto-fills via fallback / favorite.
        favoriteEnabled = true,
        favoriteId      = 241304,  -- Silvermoon Health Potion
        posX          = -400,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        timerFontKey  = "Fira Mono",
        timerFontPath = nil,
        timerFontSize = 14,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        showStack       = true,
        stackAnchor     = "BOTTOM",   -- potions keep their stack count below the icon
        stackOffsetX    = 0,
        stackOffsetY    = 0,
        stackFontKey    = "Fira Mono",
        stackFontPath   = nil,
        stackFontSize   = 12,
        stackOutline    = "OUTLINE",
        stackColor      = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Health Potion (High)",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Health Potion Ready (High)",
        soundPathReady= nil,
    },
    combat = {
        enabled         = true,
        showIcon        = true,
        showAtZero      = false,  -- keep the icon visible even with 0 potions in bags
        -- Default: below-player row, FRONT (left) bucket — see the health section.
        includeInCdm    = true,
        cdmDest         = "belowPlayer",
        cdmAtEnd        = false,
        cdmRow          = 1,
        -- itemId/spellId left unset on a fresh install (see health section).
        favoriteEnabled = true,
        favoriteId      = 241308,  -- Light's Potential
        showStack       = true,
        stackAnchor     = "BOTTOM",   -- potions keep their stack count below the icon
        stackOffsetX    = 0,
        stackOffsetY    = 0,
        stackFontKey    = "Fira Mono",
        stackFontPath   = nil,
        stackFontSize   = 12,
        stackOutline    = "OUTLINE",
        stackColor      = { r=1, g=1, b=1, a=1 },
        posX          = -370,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        timerFontKey  = "Fira Mono",
        timerFontPath = nil,
        timerFontSize = 14,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Combat Potion (High)",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Combat Potion Ready (High)",
        soundPathReady= nil,
    },
}

-- Default urgency tiers (match the custom-icon / defensive behaviour: yellow @15s,
-- red @5s). Seeded per category if missing — never merged, so deleting/editing
-- tiers sticks (ns.MergeDefaults recurses into sub-tables and would re-add them).
local DEFAULT_TIERS = {
    { at = 15, scale = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { at = 5,  scale = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
local function SeedTiers(t)
    if t and t.timerTiers == nil then t.timerTiers = ns.DeepCopy(DEFAULT_TIERS) end
end

-- One-shot legacy fold. Until this version PotionTracker stored its config in
-- the account-wide global PotionTrackerDB instead of the AceDB profile (the only
-- module that hadn't migrated). Core/DB.lua's one-shot snapshot migration copied
-- PotionTrackerDB → ns.db.profile.PotionTracker, but the old code kept WRITING to
-- the global afterwards, so that snapshot can be stale relative to the user's
-- latest potion settings. On the first CfgInit after this change we therefore
-- fold the live PotionTrackerDB into the active profile (preferring it as the
-- freshest truth), then mark it done so it never runs again. PotionTrackerDB is
-- left untouched on disk as a frozen backup (still listed in the .toc).
local function FoldLegacyPotionDB()
    if ns.db.global.potionTrackerMigrated then return end
    ns.db.global.potionTrackerMigrated = true
    if type(PotionTrackerDB) == "table" and next(PotionTrackerDB) ~= nil then
        ns.db.profile.PotionTracker = ns.DeepCopy(PotionTrackerDB)
    end
end

function PT.CfgInit()
    if not ns.db then return end
    FoldLegacyPotionDB()
    ns.db.profile.PotionTracker = ns.db.profile.PotionTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.PotionTracker)
    ns.MergeDefaults(ns.db.profile.PotionTracker, DEFAULTS)
    SeedTiers(ns.db.profile.PotionTracker.health)
    SeedTiers(ns.db.profile.PotionTracker.combat)
    ns.SeedTrackerFreeLook(ns.db.profile.PotionTracker.health)
    ns.SeedTrackerFreeLook(ns.db.profile.PotionTracker.combat)
    -- Default below-player FRONT order: Racial (0) < Potions (1,2) < Healthstone (3+).
    -- Seed the potion frames' order ONCE if absent so they sort after the racial and
    -- before the healthstone; the "Move in row" arrows can still reorder afterwards.
    ns.db.profile.cdmOrder = ns.db.profile.cdmOrder or {}
    if ns.db.profile.cdmOrder["PotionTrackerHealth"] == nil then
        ns.db.profile.cdmOrder["PotionTrackerHealth"] = 1
    end
    if ns.db.profile.cdmOrder["PotionTrackerCombat"] == nil then
        ns.db.profile.cdmOrder["PotionTrackerCombat"] = 2
    end
end
ns.RegisterCfgInitHook(PT.CfgInit)

function PT.CfgGet(key)
    local t = ns.db and ns.db.profile.PotionTracker
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function PT.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.PotionTracker = ns.db.profile.PotionTracker or {}
    ns.db.profile.PotionTracker[key] = value
    -- Config drives which potion the resolver picks; invalidate the cache
    -- so the next GetActiveItemId() reflects the change.
    if PT.InvalidateActiveCache then PT.InvalidateActiveCache() end
end

function PT.PlaySound(prefix, key)
    local cfg = PT.CfgGet(prefix)
    if type(cfg) ~= "table" then return end
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey, soundKeyKey = "soundPathUse", "soundKeyUse"
    elseif key == "soundReady" then
        pathKey, soundKeyKey = "soundPathReady", "soundKeyReady"
    else
        return
    end
    ns.PlaySoundFromCfg(cfg, pathKey, soundKeyKey)
end