-- Modules/BLTracker/Core/Config.lua

local _, ns = ...
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

local DEFAULTS = {
    enabled         = true,
    showIcon        = true,
    alwaysShow      = true,   -- show the icon at all times, even with no lust active / no BL class
    iconWidth       = 40,
    iconHeight      = 40,
    borderEnabled   = true,
    borderColor     = { r = 0, g = 0, b = 0, a = 1 },
    borderSize      = 1,
    includeInCdm    = true,        -- default: shown in the CDM…
    cdmDest         = "essential", -- …at the end of Essential row 2 (trinkets sit after it)
    cdmAtEnd        = true,
    cdmRow          = 2,
    posX            = -140,
    posY            = -150,
    timerFontKey    = "Fira Mono",
    timerFontPath   = nil,
    timerFontSize   = 14,
    timerOutline    = "OUTLINE",
    timerColor      = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    soundOnBL       = true,
    soundKeyBL      = "UnbunkUtility: Bloodlust (High)",
    soundPathBL     = nil,
    soundOnReady    = true,
    soundKeyReady   = "UnbunkUtility: BL Ready (High)",
    soundPathReady  = nil,
    instanceFilter  = {
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

function BL.CfgInit()
    ns.db.profile.BLTracker = ns.db.profile.BLTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.BLTracker)
    ns.MergeDefaults(ns.db.profile.BLTracker, DEFAULTS)
    if ns.db.profile.BLTracker.timerTiers == nil then
        ns.db.profile.BLTracker.timerTiers = ns.DeepCopy(DEFAULT_TIERS)
    end
    ns.SeedTrackerFreeLook(ns.db.profile.BLTracker)
end
ns.RegisterCfgInitHook(BL.CfgInit)

function BL.CfgGet(key)
    local t = ns.db and ns.db.profile.BLTracker
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function BL.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.BLTracker = ns.db.profile.BLTracker or {}
    ns.db.profile.BLTracker[key] = value
end

function BL.PlaySound(key)
    if not ns.db then return end
    ns.PlaySoundFromCfg(ns.db.profile.BLTracker, key, key:gsub("Path", "Key"))
end