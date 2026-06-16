-- Modules/CastBar/Core/Config.lua
-- Per-profile config for the custom player cast bar (ns.db.profile.CastBar). The whole
-- module is enabled by default, and by default it also hides Blizzard's native player
-- cast bar (hideBlizzard) so the two don't overlap.

local _, ns = ...
ns.CastBar = ns.CastBar or {}
local CB = ns.CastBar

local DEFAULTS = {
    enabled       = true,    -- whole module on by default
    hideBlizzard  = true,    -- hide Blizzard's PlayerCastingBarFrame (checked by default)
    -- Placement: offset from the screen centre (like every other movable display).
    posX          = 0,
    posY          = -220,
    width         = 260,
    height        = 24,
    -- What to show.
    showIcon      = true,
    showSpellName = true,
    showTimer     = true,
    showSpark     = true,
    -- Text style.
    fontKey       = "Fira Mono",
    fontPath      = nil,
    fontSize      = 12,
    outline       = "OUTLINE",
    textColor     = { r = 1, g = 1, b = 1, a = 1 },
    -- Bar fill colours per cast state.
    castColor          = { r = 1.0, g = 0.7,  b = 0.0,  a = 1 },  -- normal cast (gold)
    channelColor       = { r = 0.0, g = 0.9,  b = 0.3,  a = 1 },  -- channelled (green)
    uninterruptibleColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 },  -- not interruptible (grey)
}

function CB.CfgInit()
    if not ns.db then return end
    ns.db.profile.CastBar = ns.db.profile.CastBar or {}
    ns.MergeDefaults(ns.db.profile.CastBar, DEFAULTS)
end
ns.RegisterCfgInitHook(CB.CfgInit)

function CB.CfgGet(key)
    local t = ns.db and ns.db.profile.CastBar
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function CB.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.CastBar = ns.db.profile.CastBar or {}
    ns.db.profile.CastBar[key] = value
end
