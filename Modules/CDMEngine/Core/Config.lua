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
    mode       = "native",            -- CDM display mode (Core/Mode.lua): "native" (default) | "engine"
    -- P4 icon extras (Display/IconExtras.lua):
    procGlow   = true,                -- glow the icon while its spell has an activation proc
    glowType   = "pixel",             -- "pixel" | "autocast" | "button" | "proc" (LibCustomGlow)
    glowColor  = { 0.96, 1, 0, 1 },   -- {r,g,b,a} for pixel/autocast (F5FF00) ; button/proc ignore it
    rangeCheck = true,                -- tint the icon red while the spell's target is out of range
    showGcdSwipe = true,              -- default ON: draw the global cooldown as a radial spin (no number) on cooldown icons
    -- P4c class resources (Display/ClassResource.lua) ; .position is set on first drag (nil = default anchor):
    resource = {
        enable     = true,
        showCount  = 0,               -- 0 = draw ALL the spec's resources; N>0 = cap to N (1 = signature only)
        barWidth   = 200, barHeight = 16,
        pipSize    = 22,  pipSpacing = 3,
        rowSpacing = 4,   showEmpty  = true,
    },
}
Cfg.DEFAULTS = DEFAULTS

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
    -- One-time migration: P4c changed the resource showCount default 1 -> 0 (0 = draw ALL the spec's
    -- resources). MergeDefaults never overwrites an existing value, so early testers stayed on the old 1
    -- and saw only their first resource. Reset it once, gated by a per-profile marker.
    if cfg.resource and (cfg.resource._migrated or 0) < 1 then
        cfg.resource.showCount = DEFAULTS.resource.showCount
        cfg.resource._migrated = 1
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

-- The resource widget's saved position, or nil (nil = default anchor). Validates both axes are numbers
-- so a half-written table never yields a partial SetPoint.
function Cfg.GetResourcePos()
    local r = Root()
    local p = r and r.resource and r.resource.position
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then return p end
    return nil
end

function Cfg.SetResourcePos(x, y)
    local r = Root()
    if not (r and type(x) == "number" and type(y) == "number") then return end
    r.resource = r.resource or {}
    r.resource.position = { x = x, y = y }
end

function Cfg.ClearResourcePos()
    local r = Root()
    if r and r.resource then r.resource.position = nil end
end
