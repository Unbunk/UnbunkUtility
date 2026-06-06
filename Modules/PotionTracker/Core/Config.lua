-- Modules/PotionTracker/Core/Config.lua

local _, ns = ...
ns.PotionTracker = ns.PotionTracker or {}
local PT = ns.PotionTracker

local DEFAULTS = {
    enabled         = true,
    instanceFilter  = {
        dungeon      = true,
        raid         = true,
        battleground = true,
        outdoor      = true,
    },
    health = {
        enabled         = true,
        showIcon        = true,
        -- itemId/spellId left unset on a fresh install: the main dropdown
        -- shows "None" until the player picks a potion or the resolver
        -- auto-fills via fallback / favorite.
        favoriteEnabled = true,
        favoriteId      = 241304,  -- Silvermoon Health Potion
        posX          = -400,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        borderEnabled = true,
        borderColor   = { r = 0, g = 0, b = 0, a = 1 },
        borderSize    = 1,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        showStack       = true,
        stackFontKey    = "2002 Bold",
        stackFontPath   = nil,
        stackFontSize   = 12,
        stackOutline    = "OUTLINE",
        stackColor      = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Health Potion High",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Health Potion Ready High",
        soundPathReady= nil,
    },
    combat = {
        enabled         = true,
        showIcon        = true,
        -- itemId/spellId left unset on a fresh install (see health section).
        favoriteEnabled = true,
        favoriteId      = 241308,  -- Light's Potential
        showStack       = true,
        stackFontKey    = "2002 Bold",
        stackFontPath   = nil,
        stackFontSize   = 12,
        stackOutline    = "OUTLINE",
        stackColor      = { r=1, g=1, b=1, a=1 },
        posX          = -370,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        borderEnabled = true,
        borderColor   = { r = 0, g = 0, b = 0, a = 1 },
        borderSize    = 1,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Combat Potion High",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Combat Potion Ready High",
        soundPathReady= nil,
    },
}

function PT.CfgInit()
    ns.db.profile.PotionTracker = ns.db.profile.PotionTracker or {}
    ns.MigrateSoundKeys(ns.db.profile.PotionTracker)
    ns.MergeDefaults(ns.db.profile.PotionTracker, DEFAULTS)
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
    if not cfg then return end
    if key == "soundUse" then
        ns.PlaySoundFromCfg(cfg, "soundPathUse", "soundKeyUse")
    elseif key == "soundReady" then
        ns.PlaySoundFromCfg(cfg, "soundPathReady", "soundKeyReady")
    end
end