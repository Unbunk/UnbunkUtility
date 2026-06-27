-- Modules/RacialTracker/Core/Config.lua

local _, ns = ...
ns.RacialTracker = ns.RacialTracker or {}
local RT = ns.RacialTracker

local DEFAULTS = {
    enabled        = true,
    showIcon       = true,
    -- Default: in the Cooldown Manager's artificial below-player row, all the way
    -- to the LEFT (cdmAtEnd=false; the leftmost slot is enforced by the default
    -- cdmOrder = 0 set in CfgInit below). When the Cooldown Manager is disabled in
    -- the game options it falls back to the free position below (x=-430 y=-300, 30x30).
    includeInCdm   = true,
    cdmDest        = "belowPlayer",
    cdmAtEnd       = false,
    cdmRow         = 1,
    posX           = -430,
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
    timerPositiveEnabled = true,   -- show the green active-racial-buff timer by default
    -- Sounds default to the High variant but are UNCHECKED by default.
    soundOnUse     = false,
    soundKeyUse    = "UnbunkUtility: Racial (High)",
    soundPathUse   = nil,
    soundOnReady   = false,
    soundKeyReady  = "UnbunkUtility: Racial Ready (High)",
    soundPathReady = nil,
    -- Manual racial detection: when enabled, the tracker uses spellOverride instead
    -- of auto-detecting the player's known racial. Off by default (auto).
    manualEnabled  = false,
    spellOverride  = 0,
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

function RT.CfgInit()
    ns.db.profile.RacialTracker = ns.db.profile.RacialTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.RacialTracker)
    ns.MergeDefaults(ns.db.profile.RacialTracker, DEFAULTS)
    if ns.db.profile.RacialTracker.timerTiers == nil then
        ns.db.profile.RacialTracker.timerTiers = ns.DeepCopy(DEFAULT_TIERS)
    end
    ns.SeedTrackerFreeLook(ns.db.profile.RacialTracker)
    -- Pin the icon to the LEFT of the below-player CDM row by default: give it the
    -- lowest order ONCE (0 sorts before any normalized 1-based entry, so it wins
    -- even when potions/healthstone already have a saved order). Only set when
    -- absent, so the "Move in row" arrows can still move it afterwards.
    ns.db.profile.cdmOrder = ns.db.profile.cdmOrder or {}
    if ns.db.profile.cdmOrder["RacialTrackerFrame"] == nil then
        ns.db.profile.cdmOrder["RacialTrackerFrame"] = 0
    end
end
ns.RegisterCfgInitHook(RT.CfgInit)

function RT.CfgGet(key)
    local t = ns.db and ns.db.profile.RacialTracker
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function RT.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.RacialTracker = ns.db.profile.RacialTracker or {}
    ns.db.profile.RacialTracker[key] = value
end

function RT.PlaySound(key)
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey, soundKeyKey = "soundPathUse", "soundKeyUse"
    elseif key == "soundReady" then
        pathKey, soundKeyKey = "soundPathReady", "soundKeyReady"
    else
        return
    end
    ns.PlaySoundFromCfg(ns.db and ns.db.profile.RacialTracker, pathKey, soundKeyKey)
end
