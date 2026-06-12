-- Core/Shared.lua
-- Shared namespace across all addon files (the 2nd vararg passed to every
-- chunk). Centralizes common utilities so they don't get duplicated.

local ADDON, ns = ...

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")

-- ── Output ──────────────────────────────────────────────────────────────────
-- Single source for the chat prefix + a print helper, so the coloured tag is
-- defined once instead of being copy-pasted as a literal across files.
ns.PREFIX = "|cffff4444[UnbunkUtility]|r "

function ns.Print(msg)
    print(ns.PREFIX .. tostring(msg))
end

-- mm:ss formatter shared by the trackers (BRes icon + player list). Floors the
-- remaining seconds first so the minutes/seconds split can't disagree.
function ns.FormatMMSS(remain)
    if not remain or remain < 0 then remain = 0 end
    local total = math.floor(remain)
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

-- ── Never-secret auras ───────────────────────────────────────────────────────
-- In combat WoW hides ("secret values") most aura fields from addons, so reading
-- expirationTime/duration/icon off such an aura breaks any timer driven from it.
-- Only the auras in this set stay readable in combat. Beneficial buffs
-- (Bloodlust, combat potions, on-use trinkets) are NOT in it, which is why their
-- green "active" timer can't be derived in combat — the fatigue debuffs
-- (Sated/Exhaustion/Temporal Displacement/Insanity/Fatigued) ARE never-secret,
-- so trackers fall back to them. List provided by the addon author; keep in sync
-- with the in-game source.
do
    local ids = {
        33763, 17, 774, 395152, 462854, 124682, 139, 115175, 1126, 6673, 8936,
        1459, 974, 155777, 381637, 21562, 53563, 360827, 48438, 1217607, 156322,
        413984, 61295, 364343, 369459, 200025, 156910, 382021, 366155, 2823,
        1253593, 439530, 3408, 410089, 26013, 433568, 71041, 194384, 5761,
        457496, 315584, 367364, 381664, 57724, 8679, 119611, 57723, 395296,
        457481, 205473, 382024, 124255, 404468, 462757, 447959, 431381, 433583,
        80354, 381754, 260286, 264689, 77489, 381756, 410686, 450769, 404464,
        418590, 381732, 1225789, 319773, 355941, 383648, 41635, 363502, 381741,
        390435, 447960, 381749, 381753, 1244893, 207400, 410263, 444490, 1292922,
        388367, 409895, 381746, 381758, 382022, 427490, 1227702, 373267, 381750,
        462742, 95809, 377234, 381751, 376788, 381748, 381757, 405189, 319778,
        381752, 474754, 344179, 1283888, 369968, 160455,
    }
    ns.NEVER_SECRET = {}
    for _, id in ipairs(ids) do ns.NEVER_SECRET[id] = true end
end

-- True when an aura's timer fields can be trusted right now to drive a timer:
-- either the aura is flagged never-secret, or we are out of combat (every aura
-- is readable then). Call this before reading expirationTime/duration off an
-- aura you intend to show a timer for, so a secret buff in combat can't break it.
function ns.AuraTimerReadable(spellId)
    if not spellId then return false end
    if ns.NEVER_SECRET[spellId] then return true end
    return not UnitAffectingCombat("player")
end

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

-- ── Brand title colour ───────────────────────────────────────────────────────
-- Every config title/label renders in this blue (the same square the checkboxes
-- use) instead of Blizzard's default gold. Two font objects clone GameFontNormal
-- and GameFontNormalLarge and override ONLY the colour, so the face/size stay
-- identical; config FontStrings inherit one of them (via CreateFontString's 3rd
-- argument, or a BuildMenu `font=` field). Change ns.TITLE_COLOR to recolour
-- every title at once.
ns.TITLE_COLOR = { 0.20, 0.55, 1.0 }   -- #338CFF
-- ── Heading scale (h1..h5) ────────────────────────────────────────────────────
-- A small semantic type scale so the config reads as a hierarchy instead of a flat
-- wall of blue. Each level is a font object (same UI face + shadow) differing only
-- in size / weight / colour; FontStrings inherit one via CreateFontString's 3rd arg.
--   H1  window title             19  bold(OUTLINE)  blue
--   H2  module / main cadre title 16  normal         blue
--   H3  sub-cadre / main label    13  normal         blue
--   H4  secondary label           12  normal         blue
--   H5  body text                 12  normal         white
-- UnbunkUtilityTitle / ...Large are kept as legacy aliases (≈ H4 / H1) so any
-- FontString not yet migrated to a tier still renders sensibly (blue).
do
    local C = ns.TITLE_COLOR
    local basePath = GameFontNormal:GetFont()   -- the active UI font face
    local function Heading(name, size, flags, r, g, b)
        local f = CreateFont(name)
        f:CopyFontObject(GameFontNormal)         -- inherit face + shadow + spacing
        f:SetFont(basePath, size, flags or "")   -- override size / weight
        f:SetTextColor(r, g, b)                  -- override colour
        return f
    end
    Heading("UnbunkUtilityH1", 19, "OUTLINE", C[1], C[2], C[3])
    Heading("UnbunkUtilityH2", 16, nil,       C[1], C[2], C[3])
    Heading("UnbunkUtilityH3", 13, nil,       C[1], C[2], C[3])
    Heading("UnbunkUtilityH4", 12, nil,       C[1], C[2], C[3])
    Heading("UnbunkUtilityH5", 12, nil,       1, 1, 1)
    Heading("UnbunkUtilityTitle",      12, nil, C[1], C[2], C[3])  -- legacy ≈ H4
    Heading("UnbunkUtilityTitleLarge", 16, nil, C[1], C[2], C[3])  -- legacy ≈ H1/H2
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
            ns.Print("reload hook error: " .. tostring(err))
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
            ns.Print("cfgInit hook error: " .. tostring(err))
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

-- A plain deep copy of a value (scalars as-is, tables recursively cloned). Same
-- implementation as CopyDefault; exposed under a neutral name so callers that
-- aren't dealing with config defaults (e.g. the profile snapshotter) can share
-- the single implementation instead of hand-rolling their own.
ns.DeepCopy = ns.CopyDefault

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

-- ── Learned buff durations (persisted) ───────────────────────────────────────
-- In combat Blizzard makes the player's buff aura fields ("secret values")
-- COMPLETELY unreadable: GetPlayerAuraBySpellID returns nil, and even the
-- UNIT_AURA payload's duration/expirationTime are secret — merely COMPARING one
-- errors and taints the addon. So an active-buff timer can't be derived from
-- live data in combat. Instead we remember each buff's duration the first time
-- we see it readable OUT of combat (where it is a normal number) and persist it
-- across sessions in ns.db.global.auraDurations. Combined with the use event, that drives
-- the in-combat green timer. Seeded with known values so common items work on
-- the very first use without any prior out-of-combat observation.
-- IMPORTANT: only ever pass a duration read OUT of combat here — never a secret.
local AURA_DURATION_SEED = {
    [1236994] = 30,  -- Potion of Recklessness
}

-- Session-only cache of durations parsed from a spell's static description
-- (approximate; never persisted, so a later EXACT observation always wins).
local parsedDuration = {}

-- Best-effort: read the spell's STATIC description (readable in combat — it is
-- spell data, not a secret aura value) and pull the "... for N sec/min" duration
-- out of it. This is the "via the item" path: it lets a never-before-seen
-- potion/trinket get a green timer on its very first in-combat use, with zero
-- setup. Localised "sec"/"min" are matched as prefixes (covers enUS/frFR).
local function ParseSpellDuration(spellId)
    local desc
    if C_Spell and C_Spell.GetSpellDescription then
        desc = C_Spell.GetSpellDescription(spellId)
    elseif GetSpellDescription then
        desc = GetSpellDescription(spellId)
    end
    if type(desc) ~= "string" or desc == "" then return nil end
    -- Take the LAST number before a sec/min unit (buff durations are stated last,
    -- e.g. "increases Haste by 1418 for 30 sec").
    local secs
    for n in desc:gmatch("(%d+)%s*[sS]ec") do secs = tonumber(n) end
    if secs and secs > 0 then return secs end
    local mins
    for n in desc:gmatch("(%d+)%s*[mM]in") do mins = tonumber(n) end
    if mins and mins > 0 then return mins * 60 end
    return nil
end

function ns.LearnAuraDuration(spellId, duration)
    if not spellId or type(duration) ~= "number" or duration <= 0 then return end
    if not ns.db then return end
    ns.db.global.auraDurations = ns.db.global.auraDurations or {}
    ns.db.global.auraDurations[spellId] = duration
end

function ns.GetAuraDuration(spellId)
    if not spellId then return nil end
    -- 1) Exact duration observed out of combat (persisted) or seeded.
    local db = ns.db and ns.db.global.auraDurations
    local d = (db and db[spellId]) or AURA_DURATION_SEED[spellId]
    if d then return d end
    -- 2) Best-effort parse from the spell description. Only positive results are
    -- cached, so a description that is still loading (empty) is retried later
    -- rather than permanently failing for the session.
    local p = parsedDuration[spellId]
    if not p then
        p = ParseSpellDuration(spellId)
        if p then parsedDuration[spellId] = p end
    end
    return p
end

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

local zoneGuard = {}
AceEvent:Embed(zoneGuard)
zoneGuard:RegisterEvent("PLAYER_ENTERING_WORLD", function(event)
    lastZoneAt = GetTime()
end)

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
-- trigger (debounce). Config lives in ns.db.global.combo (account-wide).

local COMBO_GAP_SINGLE = 0.5  -- lone trigger: flush quickly
local COMBO_GAP_MULTI  = 1.5  -- 2 categories pending: wait for a possible third
local COMBO_MAX        = 3.0  -- never wait longer than this from the first trigger

ns.combo = ns.combo or {}
AceTimer:Embed(ns.combo)
ns.combo.pending = {}
ns.combo.timer   = nil
ns.combo.firstAt = nil

local function ComboCfg() return ns.db and ns.db.global.combo end

function ns.combo.IsEnabled()
    local c = ComboCfg()
    return c and c.enabled == true
end

local function PlayConfiguredSound(pathKey, soundKey)
    -- Same path > LSM-key > nothing logic as every other sound; reuse the
    -- shared helper instead of duplicating it here.
    ns.PlaySoundFromCfg(ComboCfg(), pathKey, soundKey)
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
    if ns.combo.timer then ns.combo:CancelTimer(ns.combo.timer); ns.combo.timer = nil end

    -- All three categories present: the top combo (BL + the two others) is
    -- already decided and no later trigger can improve it — flush immediately.
    if catCount >= 3 then
        ns.combo.Flush()
        return
    end

    -- One category → likely a lone trigger, flush quickly (plain debounce, no
    -- cap: a lone repeated trigger shouldn't be force-split mid-stream). Two →
    -- a combo is forming, so wait longer for a possible third, but never longer
    -- than COMBO_MAX from the first trigger.
    local wait
    if catCount >= 2 then
        local capRemaining = (ns.combo.firstAt + COMBO_MAX) - now
        wait = math.min(COMBO_GAP_MULTI, math.max(0, capRemaining))
    else
        wait = COMBO_GAP_SINGLE
    end
    ns.combo.timer = ns.combo:ScheduleTimer(ns.combo.Flush, wait)
end

-- ── Sound key migration ─────────────────────────────────────────────────────
-- Media keys used to be unsuffixed ("UnbunkUtility: Bloodlust"). After the
-- High/Medium/Low/Loud restructure, the unsuffixed keys are gone and each
-- variant carries its loudness in the key. This map rewrites any value in a
-- table that matches an old key to its new equivalent, so existing users do
-- not lose their sounds when they update. Recursive so nested config tables
-- (e.g. PotionTracker.health.soundKeyUse) are migrated in one pass. Applied to
-- each active profile via the module CfgInit hooks, to imported blobs, and once
-- to the legacy data during the AceDB migration (Core/DB.lua).
local SOUND_KEY_MIGRATIONS = {
    -- v1 (pre-restructure): unsuffixed keys → new defaults.
    -- Most sounds default to High; BRez Ready/Used default to Medium.
    ["UnbunkUtility: BL"]                    = "UnbunkUtility: BL (High)",
    ["UnbunkUtility: Bloodlust"]             = "UnbunkUtility: Bloodlust (High)",
    ["UnbunkUtility: Bloodlust Combo"]       = "UnbunkUtility: Bloodlust Combo (High)",
    ["UnbunkUtility: BL Ready"]              = "UnbunkUtility: BL Ready (High)",
    ["UnbunkUtility: BRez Ready"]            = "UnbunkUtility: BRez Ready (Medium)",
    ["UnbunkUtility: BRez Used"]             = "UnbunkUtility: BRez Used (Medium)",
    ["UnbunkUtility: Combat Potion"]         = "UnbunkUtility: Combat Potion (High)",
    ["UnbunkUtility: Combat Potion Ready"]   = "UnbunkUtility: Combat Potion Ready (High)",
    ["UnbunkUtility: DPS Died"]              = "UnbunkUtility: DPS Died (High)",
    ["UnbunkUtility: Drink"]                 = "UnbunkUtility: Drink (High)",
    ["UnbunkUtility: Healer Died"]           = "UnbunkUtility: Healer Died (High)",
    ["UnbunkUtility: Health Potion"]         = "UnbunkUtility: Health Potion (High)",
    ["UnbunkUtility: Health Potion Ready"]   = "UnbunkUtility: Health Potion Ready (High)",
    ["UnbunkUtility: Healthstone"]           = "UnbunkUtility: Healthstone (High)",
    ["UnbunkUtility: Healthstone Ready"]     = "UnbunkUtility: Healthstone Ready (High)",
    ["UnbunkUtility: No Heal"]               = "UnbunkUtility: No Heal (High)",
    ["UnbunkUtility: PI"]                    = "UnbunkUtility: PI (High)",
    ["UnbunkUtility: Potion Combo"]          = "UnbunkUtility: Potion Combo (High)",
    ["UnbunkUtility: Potion Ready"]          = "UnbunkUtility: Potion Ready (High)",
    ["UnbunkUtility: Tank Died"]             = "UnbunkUtility: Tank Died (High)",
    ["UnbunkUtility: Trinket"]               = "UnbunkUtility: Trinket (High)",
    ["UnbunkUtility: Trinket Combo"]         = "UnbunkUtility: Trinket Combo (High)",
    ["UnbunkUtility: Trinket Ready"]         = "UnbunkUtility: Trinket Ready (High)",

    -- v2 (intermediate patch): sounds that defaulted to " Loud" but now
    -- have High/Medium/Low variants available — switch to the new default.
    ["UnbunkUtility: BRez Ready Loud"]       = "UnbunkUtility: BRez Ready (Medium)",
    ["UnbunkUtility: BRez Used Loud"]        = "UnbunkUtility: BRez Used (Medium)",
    ["UnbunkUtility: Bloodlust Combo Loud"]  = "UnbunkUtility: Bloodlust Combo (High)",
    ["UnbunkUtility: Drink Loud"]            = "UnbunkUtility: Drink (High)",
    ["UnbunkUtility: Healthstone Loud"]      = "UnbunkUtility: Healthstone (High)",
    ["UnbunkUtility: Healthstone Ready Loud"]= "UnbunkUtility: Healthstone Ready (High)",
    ["UnbunkUtility: Potion Combo Loud"]     = "UnbunkUtility: Potion Combo (High)",
    ["UnbunkUtility: Trinket Combo Loud"]    = "UnbunkUtility: Trinket Combo (High)",
}

function ns.MigrateSoundKeys(tbl)
    if type(tbl) ~= "table" then return end
    for k, v in pairs(tbl) do
        if type(v) == "string" then
            local migrated = SOUND_KEY_MIGRATIONS[v]
            if migrated then
                tbl[k] = migrated
            else
                -- v3 → v4: move a trailing loudness word into parentheses, e.g.
                -- "UnbunkUtility: BL Ready Loud" → "UnbunkUtility: BL Ready (Loud)".
                -- Lua patterns have no alternation, so capture the last word and
                -- check it against the known variants. Keys already in the
                -- parenthesised form end in ")" and never match here.
                local base, vol = v:match("^(UnbunkUtility: .+) (%a+)$")
                if base and (vol == "High" or vol == "Medium"
                          or vol == "Low"  or vol == "Loud") then
                    tbl[k] = base .. " (" .. vol .. ")"
                end
            end
        elseif type(v) == "table" then
            ns.MigrateSoundKeys(v)
        end
    end
end

-- ── Global settings init ────────────────────────────────────────────────────
-- ns.db.global lives across all profiles (account-wide). Bootstraps the global
-- config sub-tables (combo, wipe, dpsSpam, bossReset) when they are missing.
-- Runs as a CfgInit hook so it executes AFTER Core/DB.lua has created ns.db.

local DEFAULTS_COMBO = {
    enabled       = true,   -- master switch for the whole combo feature
    blEnabled     = true,   -- play the BL combo sound when applicable
    blKey         = "UnbunkUtility: Bloodlust Combo (High)",
    blPath        = nil,
    potionEnabled = true,   -- play the Potion combo sound when applicable
    potionKey     = "UnbunkUtility: Potion Combo (High)",
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

local DEFAULTS_BOSS_RESET = {
    enabled   = true,   -- on by default, playing the bundled "Disappear" sound
    soundKey  = "UnbunkUtility: Disappear",
    soundPath = nil,
}

-- Account-wide size of the icons placed in the artificial "below player frame"
-- CDM row (cdmDest = "belowPlayer"). Configured in General Settings; applied to
-- every below-player icon by ns.CDMAnchor (so they share one consistent size).
local DEFAULTS_CDM_BELOW_ROW = {
    width   = 36,
    height  = 36,
    offsetX = 0,    -- manual nudge from PlayerFrame's BOTTOMLEFT (default: flush)
    offsetY = 0,
}

function ns.InitGlobalCfg()
    if not ns.db then return end
    local g = ns.db.global
    -- Walk the global table to rewrite any pre-restructure sound key.
    ns.MigrateSoundKeys(g)
    g.combo       = g.combo       or {}
    g.wipe        = g.wipe        or {}
    g.dpsSpam     = g.dpsSpam     or {}
    g.bossReset   = g.bossReset   or {}
    g.cdmBelowRow = g.cdmBelowRow or {}
    ns.MergeDefaults(g.combo,       DEFAULTS_COMBO)
    ns.MergeDefaults(g.wipe,        DEFAULTS_WIPE)
    ns.MergeDefaults(g.dpsSpam,     DEFAULTS_DPS_SPAM)
    ns.MergeDefaults(g.bossReset,   DEFAULTS_BOSS_RESET)
    ns.MergeDefaults(g.cdmBelowRow, DEFAULTS_CDM_BELOW_ROW)
end

ns.RegisterCfgInitHook(ns.InitGlobalCfg)
