-- Core/Shared.lua
-- Shared namespace across all addon files (the 2nd vararg passed to every
-- chunk). Centralizes common utilities so they don't get duplicated.

local ADDON, ns = ...

-- ── Instance filter ─────────────────────────────────────────────────────────
-- Returns true when the module should be active in the current instance,
-- based on the filter table { dungeon, raid, battleground, outdoor }.
-- A nil filter means "always active".
function ns.IsActiveInInstance(filter)
    if not filter then return true end

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return filter.outdoor ~= false
    elseif instanceType == "party" then
        return filter.dungeon ~= false
    elseif instanceType == "raid" then
        return filter.raid ~= false
    elseif instanceType == "pvp" or instanceType == "arena" then
        return filter.battleground ~= false
    end

    return false
end

-- ── Fonts ───────────────────────────────────────────────────────────────────
-- Resolves a usable font path: explicit path > LSM key > FRIZQT fallback.
-- Prevents the default font (stored as an LSM key like "2002 Bold") from
-- silently falling back to FRIZQT until the user reopens the font picker.
function ns.ResolveFontPath(path, key)
    if path then return path end
    if key then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local fetched = LSM:Fetch("font", key)
            if fetched then return fetched end
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- ── Profile reload hooks ────────────────────────────────────────────────────
-- Each module registers a function that re-applies its settings. Avoids the
-- giant manual list that used to live in ns.profiles.ReloadAll.

ns.reloadHooks = {}

function ns.RegisterReloadHook(fn)
    if type(fn) == "function" then
        table.insert(ns.reloadHooks, fn)
    end
end

function ns.RunReloadHooks()
    for _, fn in ipairs(ns.reloadHooks) do
        local ok, err = pcall(fn)
        if not ok then
            print("|cffff4444[UnbunkUtility]|r reload hook error: " .. tostring(err))
        end
    end
end

-- ── Config init hooks ───────────────────────────────────────────────────────
-- Each module registers its CfgInit so the profile system can re-apply every
-- module's defaults + sound-key migration after loading / importing / resetting
-- a profile (which wholesale-replaces the saved-variable tables).

ns.cfgInitHooks = {}

function ns.RegisterCfgInitHook(fn)
    if type(fn) == "function" then
        table.insert(ns.cfgInitHooks, fn)
    end
end

function ns.RunCfgInitHooks()
    for _, fn in ipairs(ns.cfgInitHooks) do
        local ok, err = pcall(fn)
        if not ok then
            print("|cffff4444[UnbunkUtility]|r cfgInit hook error: " .. tostring(err))
        end
    end
end

-- ── Default merge ───────────────────────────────────────────────────────────
-- Recursively backfills missing keys from `defaults` into `target` without
-- overwriting user values, recursing into existing sub-tables so newly-added
-- nested keys reach upgraders. The single shared implementation every module's
-- CfgInit should use (replaces six divergent hand-rolled copies).
function ns.MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                ns.MergeDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            ns.MergeDefaults(target[k], v)
        end
    end
end

-- Returns a value safe to hand out as a config fallback: scalars as-is, tables
-- deep-copied so a caller can't mutate the shared DEFAULTS table. Used by every
-- module's CfgGet to fall back to its DEFAULTS when a saved key is nil (missing
-- after an import / a newly-added key / a read before CfgInit ran).
function ns.CopyDefault(v)
    if type(v) ~= "table" then return v end
    local copy = {}
    for k, val in pairs(v) do copy[k] = ns.CopyDefault(val) end
    return copy
end

-- ── Sound playback ──────────────────────────────────────────────────────────
-- Plays a configured sound: explicit file path > LSM key > nothing. `cfg` is
-- the (sub)table holding the two keys. Replaces the per-module PlaySound copies
-- that had drifted into three incompatible signatures.
function ns.PlaySoundFromCfg(cfg, pathKey, soundKeyKey)
    if type(cfg) ~= "table" then return end
    local path = cfg[pathKey]
    if path then
        PlaySoundFile(path, "Master")
        return
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local key = soundKeyKey and cfg[soundKeyKey]
    local resolved = key and LSM:Fetch("sound", key)
    if resolved then PlaySoundFile(resolved, "Master") end
end

-- Shared texture path for the green "ready" check used by the trackers.
ns.GREEN_CHECK_TEXTURE = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\GreenCheck.tga"

-- ── Tracker icon layering ────────────────────────────────────────────────────
-- Layer a tracker icon BELOW HIGH-strata UI panels (e.g. the talents/spellbook
-- window, so opening it covers the icons) while keeping it ABOVE Blizzard's
-- Cooldown Manager, which sits at MEDIUM strata. Forcing MEDIUM puts us under
-- HIGH panels; the frame level sits just above the cooldown viewer's icons.
-- Bump the +20 here if the cooldown manager ever renders on top.
function ns.SetTrackerIconStrata(frame)
    frame:SetFrameStrata("MEDIUM")
    local cmv = EssentialCooldownViewer or UtilityCooldownViewer
    frame:SetFrameLevel(((cmv and cmv:GetFrameLevel()) or 10) + 20)
end

-- ── Zone-transition guard ────────────────────────────────────────────────────
-- Right after a loading screen (PLAYER_ENTERING_WORLD) the cooldown / aura APIs
-- briefly report stale or empty data, which a tracker can misread as a cooldown
-- *completing* — firing a spurious "ready" sound (e.g. leaving a follower
-- dungeon plays BL/Trinket/Potion "ready" although nothing is actually ready).
-- Trackers check ns.RecentlyZoned() before a ready sound to skip that settle
-- window. Tune ns.ZONE_SETTLE if a real ready right after a load is being eaten.
ns.ZONE_SETTLE = 2.5  -- seconds of "ready" suppression after a load screen
-- Tolerance (s) for "the cooldown actually reached its recorded end". Must
-- comfortably exceed the slowest poll (the 0.5s tracker ticker) yet stay well
-- under the shortest real cooldown so a near-expiry stale read can't slip in.
ns.READY_EPSILON = 1.5
local lastZoneAt = -math.huge

function ns.RecentlyZoned()
    return (GetTime() - lastZoneAt) < ns.ZONE_SETTLE
end

local zoneGuard = CreateFrame("Frame")
zoneGuard:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneGuard:SetScript("OnEvent", function() lastZoneAt = GetTime() end)

-- ── Combo sound coordinator ─────────────────────────────────────────────────
-- Each tracker (BL / Potion / Trinket) routes its on-trigger sound through
-- ns.combo.Notify. The coordinator waits a short, ADAPTIVE window and then:
--   * BL + anything else → play the "bl_combo" sound
--   * Potion + Trinket   → play the "potion_combo" sound
--   * single category    → play that category's normal sound
-- A lone trigger flushes quickly (COMBO_GAP_SINGLE). Once two categories are
-- pending, a combo is forming, so it waits longer (COMBO_GAP_MULTI) for a
-- possible third — a human "full combo" (potion, trinket, THEN BL) is spread
-- over a second or two and the BL is usually last. All three present → flush
-- immediately. COMBO_MAX caps the total wait. The window is re-armed on every
-- trigger (debounce). Config lives in UnbunkUtilityDB.combo (global).

local COMBO_GAP_SINGLE = 0.5  -- lone trigger: flush quickly
local COMBO_GAP_MULTI  = 2.5  -- 2 categories pending: wait for a possible third
local COMBO_MAX        = 5.0  -- never wait longer than this from the first trigger

ns.combo = ns.combo or {}
ns.combo.pending = {}
ns.combo.timer   = nil
ns.combo.firstAt = nil

local function ComboCfg() return UnbunkUtilityDB and UnbunkUtilityDB.combo end

function ns.combo.IsEnabled()
    local c = ComboCfg()
    return c and c.enabled == true
end

local function PlayConfiguredSound(pathKey, soundKey)
    local cfg = ComboCfg()
    if not cfg then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = cfg[pathKey]
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local key = cfg[soundKey]
        local resolved = key and LSM:Fetch("sound", key)
        if resolved then PlaySoundFile(resolved, "Master") end
    end
end

function ns.combo.PlayBLCombo()     PlayConfiguredSound("blPath",     "blKey")     end
function ns.combo.PlayPotionCombo() PlayConfiguredSound("potionPath", "potionKey") end

function ns.combo.Flush()
    local pending = ns.combo.pending
    ns.combo.pending = {}
    ns.combo.timer = nil
    ns.combo.firstAt = nil

    -- pending[category] is a LIST of fallback fns (multiple same-category
    -- sounds can queue within one window, e.g. health + combat potion).
    local function has(cat) local l = pending[cat]; return l and #l > 0 end
    local hasBL, hasPotion, hasTrinket = has("bl"), has("potion"), has("trinket")
    local cfg = ComboCfg() or {}

    if hasBL and (hasPotion or hasTrinket) and cfg.blEnabled then
        ns.combo.PlayBLCombo()
        return
    end
    if hasPotion and hasTrinket and (not hasBL) and cfg.potionEnabled then
        ns.combo.PlayPotionCombo()
        return
    end
    -- No matching combo (or that combo is disabled): play every queued sound
    -- (all categories, all entries) so none is silently dropped.
    for _, list in pairs(pending) do
        for _, fn in ipairs(list) do pcall(fn) end
    end
end

-- Called by trackers in place of playing their sound directly.
function ns.combo.Notify(category, fallbackSoundFn)
    if not ns.combo.IsEnabled() then
        if fallbackSoundFn then fallbackSoundFn() end
        return
    end
    local list = ns.combo.pending[category]
    if not list then
        list = {}
        ns.combo.pending[category] = list
    end
    table.insert(list, fallbackSoundFn)

    local p = ns.combo.pending
    local function has(c) local l = p[c]; return l and #l > 0 end
    local catCount = (has("bl") and 1 or 0) + (has("potion") and 1 or 0)
        + (has("trinket") and 1 or 0)

    local now = GetTime()
    ns.combo.firstAt = ns.combo.firstAt or now

    -- Re-arm the flush timer on every trigger (debounce).
    if ns.combo.timer then ns.combo.timer:Cancel(); ns.combo.timer = nil end

    -- All three categories present: the top combo (BL + the two others) is
    -- already decided and no later trigger can improve it — flush immediately.
    if catCount >= 3 then
        ns.combo.Flush()
        return
    end

    -- One category → likely a lone trigger, flush quickly. Two → a combo is
    -- forming, so wait longer for a possible third. Capped at COMBO_MAX total.
    local gap          = (catCount >= 2) and COMBO_GAP_MULTI or COMBO_GAP_SINGLE
    local capRemaining = (ns.combo.firstAt + COMBO_MAX) - now
    ns.combo.timer = C_Timer.NewTimer(math.min(gap, math.max(0, capRemaining)), ns.combo.Flush)
end

-- ── Sound key migration ─────────────────────────────────────────────────────
-- Media keys used to be unsuffixed ("UnbunkUtility: Bloodlust"). After the
-- High/Medium/Low/Loud restructure, the unsuffixed keys are gone and each
-- variant carries its loudness in the key. This map rewrites any value in a
-- table that matches an old key to its new equivalent, so existing users do
-- not lose their sounds when they update. Recursive so nested config tables
-- (e.g. PotionTracker.health.soundKeyUse) and profile snapshots in
-- UnbunkUtilityDB.profiles are migrated in one pass.
local SOUND_KEY_MIGRATIONS = {
    -- v1 (pre-restructure): unsuffixed keys → new defaults.
    -- Most sounds default to High; BRez Ready/Used default to Medium.
    ["UnbunkUtility: BL"]                    = "UnbunkUtility: BL High",
    ["UnbunkUtility: Bloodlust"]             = "UnbunkUtility: Bloodlust High",
    ["UnbunkUtility: Bloodlust Combo"]       = "UnbunkUtility: Bloodlust Combo High",
    ["UnbunkUtility: BL Ready"]              = "UnbunkUtility: BL Ready High",
    ["UnbunkUtility: BRez Ready"]            = "UnbunkUtility: BRez Ready Medium",
    ["UnbunkUtility: BRez Used"]             = "UnbunkUtility: BRez Used Medium",
    ["UnbunkUtility: Combat Potion"]         = "UnbunkUtility: Combat Potion High",
    ["UnbunkUtility: Combat Potion Ready"]   = "UnbunkUtility: Combat Potion Ready High",
    ["UnbunkUtility: DPS Died"]              = "UnbunkUtility: DPS Died High",
    ["UnbunkUtility: Drink"]                 = "UnbunkUtility: Drink High",
    ["UnbunkUtility: Healer Died"]           = "UnbunkUtility: Healer Died High",
    ["UnbunkUtility: Health Potion"]         = "UnbunkUtility: Health Potion High",
    ["UnbunkUtility: Health Potion Ready"]   = "UnbunkUtility: Health Potion Ready High",
    ["UnbunkUtility: Healthstone"]           = "UnbunkUtility: Healthstone High",
    ["UnbunkUtility: Healthstone Ready"]     = "UnbunkUtility: Healthstone Ready High",
    ["UnbunkUtility: No Heal"]               = "UnbunkUtility: No Heal High",
    ["UnbunkUtility: PI"]                    = "UnbunkUtility: PI High",
    ["UnbunkUtility: Potion Combo"]          = "UnbunkUtility: Potion Combo High",
    ["UnbunkUtility: Potion Ready"]          = "UnbunkUtility: Potion Ready High",
    ["UnbunkUtility: Tank Died"]             = "UnbunkUtility: Tank Died High",
    ["UnbunkUtility: Trinket"]               = "UnbunkUtility: Trinket High",
    ["UnbunkUtility: Trinket Combo"]         = "UnbunkUtility: Trinket Combo High",
    ["UnbunkUtility: Trinket Ready"]         = "UnbunkUtility: Trinket Ready High",

    -- v2 (intermediate patch): sounds that defaulted to " Loud" but now
    -- have High/Medium/Low variants available — switch to the new default.
    ["UnbunkUtility: BRez Ready Loud"]       = "UnbunkUtility: BRez Ready Medium",
    ["UnbunkUtility: BRez Used Loud"]        = "UnbunkUtility: BRez Used Medium",
    ["UnbunkUtility: Bloodlust Combo Loud"]  = "UnbunkUtility: Bloodlust Combo High",
    ["UnbunkUtility: Drink Loud"]            = "UnbunkUtility: Drink High",
    ["UnbunkUtility: Healthstone Loud"]      = "UnbunkUtility: Healthstone High",
    ["UnbunkUtility: Healthstone Ready Loud"]= "UnbunkUtility: Healthstone Ready High",
    ["UnbunkUtility: Potion Combo Loud"]     = "UnbunkUtility: Potion Combo High",
    ["UnbunkUtility: Trinket Combo Loud"]    = "UnbunkUtility: Trinket Combo High",
}

function ns.MigrateSoundKeys(tbl)
    if type(tbl) ~= "table" then return end
    for k, v in pairs(tbl) do
        if type(v) == "string" then
            local migrated = SOUND_KEY_MIGRATIONS[v]
            if migrated then tbl[k] = migrated end
        elseif type(v) == "table" then
            ns.MigrateSoundKeys(v)
        end
    end
end

-- ── General settings init ───────────────────────────────────────────────────
-- UnbunkUtilityDB lives across all profiles. Bootstraps the global config
-- sub-tables (combo, wipe, dpsSpam) when they are missing.

local DEFAULTS_COMBO = {
    enabled       = true,   -- master switch for the whole combo feature
    blEnabled     = true,   -- play the BL combo sound when applicable
    blKey         = "UnbunkUtility: Bloodlust Combo High",
    blPath        = nil,
    potionEnabled = true,   -- play the Potion combo sound when applicable
    potionKey     = "UnbunkUtility: Potion Combo High",
    potionPath    = nil,
}

local DEFAULTS_WIPE = {
    enabled          = true,
    deathThreshold   = 8,
    timeWindow       = 3,
    suppressDuration = 15,
}

local DEFAULTS_DPS_SPAM = {
    enabled          = true,
    deathThreshold   = 3,
    timeWindow       = 3,
    suppressDuration = 6,
}

local function InitGeneralCfg()
    UnbunkUtilityDB = UnbunkUtilityDB or {}
    -- Walk the whole DB (combo keys + profile snapshots in
    -- UnbunkUtilityDB.profiles) to rewrite any pre-restructure sound key.
    ns.MigrateSoundKeys(UnbunkUtilityDB)
    UnbunkUtilityDB.combo   = UnbunkUtilityDB.combo   or {}
    UnbunkUtilityDB.wipe    = UnbunkUtilityDB.wipe    or {}
    UnbunkUtilityDB.dpsSpam = UnbunkUtilityDB.dpsSpam or {}
    ns.MergeDefaults(UnbunkUtilityDB.combo,   DEFAULTS_COMBO)
    ns.MergeDefaults(UnbunkUtilityDB.wipe,    DEFAULTS_WIPE)
    ns.MergeDefaults(UnbunkUtilityDB.dpsSpam, DEFAULTS_DPS_SPAM)
end

local cfgInit = CreateFrame("Frame")
cfgInit:RegisterEvent("ADDON_LOADED")
cfgInit:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= ADDON then return end
    InitGeneralCfg()
    self:UnregisterEvent("ADDON_LOADED")
end)
