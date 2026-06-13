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
    timerFontSize  = 20,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    -- Sounds default to the High variant but are UNCHECKED by default.
    soundOnUse     = false,
    soundKeyUse    = "UnbunkUtility: Racial (High)",
    soundPathUse   = nil,
    soundOnReady   = false,
    soundKeyReady  = "UnbunkUtility: Racial Ready (High)",
    soundPathReady = nil,
    -- Manual spellId override; 0 = auto-detect the player's known racial.
    spellOverride  = 0,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
}

function RT.CfgInit()
    ns.db.profile.RacialTracker = ns.db.profile.RacialTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.RacialTracker)
    ns.MergeDefaults(ns.db.profile.RacialTracker, DEFAULTS)
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
