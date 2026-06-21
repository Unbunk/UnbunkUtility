-- Modules/TrinketTracker/Core/Config.lua

local _, ns = ...
ns.TrinketTracker = ns.TrinketTracker or {}
local TT = ns.TrinketTracker

local DEFAULTS = {
    enabled        = true,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
    trinket1 = {
        enabled       = true,
        showIcon      = true,
        slot          = 13,
        includeInCdm  = true,        -- default: shown in the CDM…
        cdmDest       = "essential", -- …at the end of Essential row 2 (after the BL icon)
        cdmAtEnd      = true,
        cdmRow        = 2,
        posX          = 150,
        posY          = -150,
        iconWidth     = 40,
        iconHeight    = 40,
        borderEnabled = true,
        borderColor   = { r = 0, g = 0, b = 0, a = 1 },
        borderSize    = 1,
        timerFontKey  = "Fira Mono",
        timerFontPath = nil,
        timerFontSize = 14,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Trinket (High)",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Trinket Ready (High)",
        soundPathReady= nil,
    },
    trinket2 = {
        enabled       = true,
        showIcon      = true,
        slot          = 14,
        includeInCdm  = true,        -- default: shown in the CDM…
        cdmDest       = "essential", -- …at the end of Essential row 2 (after the BL icon)
        cdmAtEnd      = true,
        cdmRow        = 2,
        posX          = 190,
        posY          = -150,
        iconWidth     = 40,
        iconHeight    = 40,
        borderEnabled = true,
        borderColor   = { r = 0, g = 0, b = 0, a = 1 },
        borderSize    = 1,
        timerFontKey  = "Fira Mono",
        timerFontPath = nil,
        timerFontSize = 14,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Trinket (High)",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Trinket Ready (High)",
        soundPathReady= nil,
    },
}

-- Default urgency tiers (yellow @15s, red @5s — matching custom icons / defensives).
-- Seeded per trinket if missing; never merged so deleting/editing tiers sticks.
local DEFAULT_TIERS = {
    { at = 15, scale = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { at = 5,  scale = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
local function SeedTiers(t)
    if t and t.timerTiers == nil then t.timerTiers = ns.DeepCopy(DEFAULT_TIERS) end
end

function TT.CfgInit()
    ns.db.profile.TrinketTracker = ns.db.profile.TrinketTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.TrinketTracker)
    ns.MergeDefaults(ns.db.profile.TrinketTracker, DEFAULTS)
    SeedTiers(ns.db.profile.TrinketTracker.trinket1)
    SeedTiers(ns.db.profile.TrinketTracker.trinket2)
    ns.SeedTrackerFreeLook(ns.db.profile.TrinketTracker.trinket1)
    ns.SeedTrackerFreeLook(ns.db.profile.TrinketTracker.trinket2)
end

-- Re-apply defaults + sound migration whenever a profile is loaded/imported/reset.
ns.RegisterCfgInitHook(TT.CfgInit)

function TT.CfgGet(key)
    local t = ns.db and ns.db.profile.TrinketTracker
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function TT.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.TrinketTracker = ns.db.profile.TrinketTracker or {}
    ns.db.profile.TrinketTracker[key] = value
end

function TT.PlaySound(prefix, key)
    local cfg = TT.CfgGet(prefix)
    if not cfg then return end
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey     = "soundPathUse"
        soundKeyKey = "soundKeyUse"
    elseif key == "soundReady" then
        pathKey     = "soundPathReady"
        soundKeyKey = "soundKeyReady"
    else
        return
    end
    ns.PlaySoundFromCfg(cfg, pathKey, soundKeyKey)
end