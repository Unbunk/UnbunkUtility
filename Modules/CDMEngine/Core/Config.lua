-- Modules/CDMEngine/Core/Config.lua
--
-- Phase 3 of the standalone CDM engine (ns.CDMEngine): the persistence layer for the designer. It
-- follows the addon's canonical config idiom (BResTracker/Core/Config.lua): a DEFAULTS table merged
-- into ns.db.profile.CDMEngine by a CfgInit hook, plus small guarded accessors. Everything lives in
-- the PROFILE table, so it round-trips across /reload and travels with the active profile on
-- switch/export/import (the reload + CfgInit hooks re-run then). No native-frame contact here.
--
-- A group's on-screen position is keyed by its STABLE string catKey ("Essential" / "Utility" /
-- "TrackedBuff"), never the numeric enum (which is a client-local id). ABSENCE of a saved position
-- for a catKey means "auto-stack" — the Phase 2 behaviour, which is also what "reset" restores.

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
local Cfg = {}
E.Cfg = Cfg

local DEFAULTS = {
    mode       = "engine",            -- CDM display mode (Core/Mode.lua): "engine" (default) | "native"
    -- P4 icon extras (Display/IconExtras.lua):
    procGlow   = true,                -- glow the icon while its spell has an activation proc
    glowType   = "pixel",             -- "pixel" | "autocast" | "button" | "proc" (LibCustomGlow)
    glowColor  = { 0.96, 1, 0, 1 },   -- {r,g,b,a} for pixel/autocast (F5FF00) ; button/proc ignore it
    rangeCheck = true,                -- tint the icon red while the spell's target is out of range
    showGcdSwipe = true,              -- default ON: draw the global cooldown as a radial spin (no number) on cooldown icons
    -- P4c class resources (Display/ClassResource.lua). Per-SPEC, per-BAR config lives under .bars
    -- (bars[specKey][barIndex] = sparse overrides of BAR_DEFAULTS below); .enable is the master toggle.
    resource = {
        enable = true,
        bars   = {},
    },
}
Cfg.DEFAULTS = DEFAULTS

-- Per-bar defaults (one resource bar). Config is keyed per SPEC: each spec's ORDERED resources
-- (R.Detect()) get their own bar settings, indexed 1..N. anchorTo is index-dependent (bar 1 -> Essential,
-- bar N -> the previous bar) so it's resolved in Cfg.GetBar, not stored here.
Cfg.BAR_DEFAULTS = {
    enable    = true,
    barWidth  = 200, barHeight = 16,
    pipSize   = 22,  pipSpacing = 3,
    showEmpty = true,
    adaptTo   = "essential",
    placement = "above",
    posX = 0, posY = 0,
    unlocked = false,
}

-- 'CDMEngine' is a BRAND-NEW profile key (never persisted before this branch), so its casing is free
-- to choose; we fix it here and never rename it (cf. the profile-key-casing rule for the old keys).
local function Root()
    return ns.db and ns.db.profile and ns.db.profile.CDMEngine
end

function Cfg.Init()
    if not (ns.db and ns.db.profile) then return end
    ns.db.profile.CDMEngine = ns.db.profile.CDMEngine or {}
    local cfg = ns.db.profile.CDMEngine
    ns.MergeDefaults(cfg, DEFAULTS)
    -- One-time migration: the standalone engine is now the DEFAULT display mode. MergeDefaults already wrote
    -- "native" into every profile created under the old default, so flip those to "engine" ONCE. The marker
    -- lets a later DELIBERATE switch back to native stick (we never re-flip); new profiles merged "engine"
    -- and skip the flip.
    if (cfg._modeDefaultV or 0) < 1 then
        if cfg.mode == "native" then cfg.mode = "engine" end
        cfg._modeDefaultV = 1
    end
end
ns.RegisterCfgInitHook(Cfg.Init)

-- Generic scalar/table getter for the flat config keys (the P4 icon-extra flags). Falls back to a
-- FRESH COPY of the default so a caller can't mutate the shared DEFAULTS table.
function Cfg.Get(key)
    local r = Root()
    local v = r and r[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function Cfg.Set(key, value)
    local r = Root()
    if not r then return end
    r[key] = value
end

-- ── P4c class-resource config (dedicated sub-table so /uucdmdesign reset can't wipe it) ─────────
function Cfg.GetResource(key)
    local r = Root()
    local res = r and r.resource
    local v = res and res[key]
    if v == nil then
        local d = DEFAULTS.resource
        return ns.CopyDefault(d and d[key])
    end
    return v
end

function Cfg.SetResource(key, value)
    local r = Root()
    if not r then return end
    r.resource = r.resource or {}
    r.resource[key] = value
end

-- Per-spec, per-bar resource config. specKey = R.GetSpecKey() (numeric specID or CLASSFILE string),
-- normalised to a string table key so it round-trips. i = the resource's 1-based position in R.Detect().
-- Falls back to BAR_DEFAULTS; anchorTo defaults to Essential for bar 1, the previous bar otherwise.
function Cfg.GetBar(specKey, i, key)
    local r = Root()
    local bars = r and r.resource and r.resource.bars
    local sb = bars and specKey and bars[tostring(specKey)]
    local b  = sb and i and sb[i]
    local v  = b and b[key]
    if v ~= nil then return v end
    if key == "anchorTo" then return (i and i > 1) and ("bar" .. (i - 1)) or "essential" end
    return Cfg.BAR_DEFAULTS[key]
end

function Cfg.SetBar(specKey, i, key, val)
    local r = Root()
    if not (r and specKey and i and key) then return end
    r.resource = r.resource or {}
    r.resource.bars = r.resource.bars or {}
    local sk = tostring(specKey)
    r.resource.bars[sk] = r.resource.bars[sk] or {}
    r.resource.bars[sk][i] = r.resource.bars[sk][i] or {}
    r.resource.bars[sk][i][key] = val
end
