-- Modules/BResTracker/Core/Config.lua

local _, ns = ...
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

local DEFAULTS = {
    enabled        = true,
    showIcon       = true,
    iconWidth      = 45,
    iconHeight     = 45,
    borderEnabled  = true,
    borderColor    = { r = 0, g = 0, b = 0, a = 1 },
    borderSize     = 1,
    includeInCdm   = false,
    cdmDest        = "essential",
    cdmAtEnd       = true,
    cdmRow         = 1,
    posX           = -610,
    posY           = -290,
    timerFontKey   = "Fira Mono",
    timerFontPath  = nil,
    timerFontSize  = 14,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    countFontSize  = 16,
    soundOnReady   = true,
    soundKeyReady  = "UnbunkUtility: BRez Ready (Medium)",
    soundPathReady = nil,
    soundOnUsed    = true,
    soundKeyUsed   = "UnbunkUtility: BRez Used (Medium)",
    soundPathUsed  = nil,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        -- Intentionally false (unlike the other trackers, which default true):
        -- battle res does not exist in battlegrounds / arenas.
        battleground = false,
        outdoor      = true,
    },
    -- Optional player list submodule
    listEnabled       = false,
    listSide          = "Left",    -- "Left" / "Right" / "Above" / "Below"
    listOffset        = 8,         -- pixel gap between icon and list
    rowStatusSide     = "Left",    -- "Left" / "Right" / "Above" / "Below"
    listRowHeight     = 18,        -- cell height (per text line)
    listFontSize      = 14,
    listFontPath      = nil,
    listFontKey       = "Fira Mono",
    listOutline       = "OUTLINE",
    -- Estimated per-player BRes cooldown (seconds) used for the list timers. An
    -- addon can't read another player's real cooldown, so this is a single
    -- heuristic value; the real spell CDs (Rebirth / Raise Ally / Intercession)
    -- are all 600s (10 min). Lower it if you'd rather the list approximate the
    -- shared raid-charge recharge instead.
    listCooldownEstimate = 600,
}

function BR.CfgInit()
    ns.db.profile.BResTracker = ns.db.profile.BResTracker or {}
    local cfg = ns.db.profile.BResTracker
    ns.MigrateSoundKeys(cfg)
    -- Migrate older boolean keys to the new "side" string keys.
    if cfg.listOnRight ~= nil and cfg.listSide == nil then
        cfg.listSide = cfg.listOnRight and "Right" or "Left"
        cfg.listOnRight = nil
    end
    if cfg.rowStatusOnRight ~= nil and cfg.rowStatusSide == nil then
        cfg.rowStatusSide = cfg.rowStatusOnRight and "Right" or "Left"
        cfg.rowStatusOnRight = nil
    end

    -- Recursive backfill (also fills newly-added nested keys, e.g. a future
    -- instanceFilter sub-key) so upgraders are not left with nil defaults.
    ns.MergeDefaults(cfg, DEFAULTS)
end

ns.RegisterCfgInitHook(BR.CfgInit)

function BR.CfgGet(key)
    local t = ns.db and ns.db.profile.BResTracker
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function BR.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.BResTracker = ns.db.profile.BResTracker or {}
    ns.db.profile.BResTracker[key] = value
end

function BR.PlaySound()
    ns.PlaySoundFromCfg(ns.db.profile.BResTracker, "soundPathReady", "soundKeyReady")
end

function BR.PlaySoundUsed()
    ns.PlaySoundFromCfg(ns.db.profile.BResTracker, "soundPathUsed", "soundKeyUsed")
end
