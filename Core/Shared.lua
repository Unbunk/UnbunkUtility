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
    elseif instanceType == "raid" then
        return filter.raid ~= false
    elseif instanceType == "pvp" or instanceType == "arena" then
        return filter.battleground ~= false
    end

    -- The "dungeon" filter governs every remaining instance type: 5-man dungeons
    -- ("party") plus scenarios, delves, and any other instance that is not a raid,
    -- battleground, or arena. In other words, "Dungeon" means "any instanced PvE
    -- content other than raids".
    return filter.dungeon ~= false
end

-- ── Fonts ───────────────────────────────────────────────────────────────────
-- Resolves a usable font path: explicit path > LSM key > FRIZQT fallback.
-- Prevents the default font (stored as an LSM key like "2002 Bold") from
-- silently falling back to FRIZQT until the user reopens the font picker.
-- Per-key memo: LSM font registration is static once a key is registered and
-- SetAddonFont re-faces the font objects directly, so caching each key's resolved
-- path avoids an uncached LibStub + LSM:Fetch on every call. We only cache a
-- SUCCESSFUL Fetch: a key that doesn't resolve yet (queried before its registering
-- addon's ADDON_LOADED, or before LSM loaded) is left uncached so a later call can
-- still pick it up once it's registered — caching `false` would pin it to the
-- FRIZQT fallback for the whole session. A failed Fetch is cheap and rare.
local fontPathCache = {}
function ns.ResolveFontPath(path, key)
    if path then return path end
    if key then
        local c = fontPathCache[key]
        if c then return c end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local resolved = LSM and LSM:Fetch("font", key)
        if resolved then
            fontPathCache[key] = resolved
            return resolved
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- Tracker per-icon override seed version. Bump this when the DEFAULT override-set a tracker seeds changes;
-- an icon seeded at an older version is wiped and re-seeded with the new defaults on its next config-open /
-- render (it stays "migrated" meanwhile, so it keeps rendering until the re-seed lands — no flash).
ns.OVERRIDE_SEED_VERSION = 3

-- The default urgency thresholds every tracker's Timer override seeds: yellow x1.2 at 15s, red x1.45 at 5s.
-- Fresh table per call so the seed never aliases a shared one.
function ns.DefaultTrackerTimerThresholds()
    return {
        { time = 15, size = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
        { time = 5,  size = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
    }
end

-- The default override-set for a timer-only tracker (Trinket / Racial / PI / BL): Timer size 14 + the
-- urgency thresholds, nothing else. Fresh table per call.
function ns.DefaultTrackerTimerSeed()
    return {
        timerFontSize = 14,
        timerThresholdsEnabled = true,
        timerThresholds = ns.DefaultTrackerTimerThresholds(),
    }
end

-- Seed a tracker icon's FREE-look schema (missing-only) so it can use the shared free cadres
-- (ns.CDMGroups.TrackerFreeCadres): CDM settings (press overlay / keybinds), Glow (on-proc, F5FF00), and
-- the shared Timer/Title/Stacks sections. `freeExtras=true` tells TimerIcon to draw the title/stacks from
-- this config in free placement. Also migrates the legacy timerTiers -> the shared timerThresholds once.
function ns.SeedTrackerFreeLook(t)
    if not t then return end
    if t.timerThresholds == nil and type(t.timerTiers) == "table" then
        local th = {}
        for _, x in ipairs(t.timerTiers) do th[#th + 1] = { time = x.at, size = x.scale, color = x.color } end
        t.timerThresholds = th
        if t.timerThresholdsEnabled == nil then t.timerThresholdsEnabled = true end
    end
    -- Carry any legacy own-draw anchors (Defensive/Healthstone) into the shared schema so an upgraded
    -- icon keeps its title/stack position when its render switches to the shared free path.
    if t.titlePos == nil and t.titleAnchor ~= nil then
        t.titlePos = t.titleAnchor; t.titleOffX = t.titleOffsetX; t.titleOffY = t.titleOffsetY
    end
    if t.stackPos == nil and t.stackAnchor ~= nil then
        t.stackPos = t.stackAnchor; t.stackOffX = t.stackOffsetX; t.stackOffY = t.stackOffsetY
    end
    local defs = {
        freeExtras = true,
        showTimer = true, timerPos = "CENTER", timerThresholdsEnabled = true,
        showTitle = false, titleText = "", titleFontKey = "Fira Mono", titleFontSize = 12,
        titleOutline = "OUTLINE", titleColor = { r = 1, g = 1, b = 1, a = 1 },
        titlePos = "TOP", titleOffX = 0, titleOffY = 0,
        showStack = true, showAtZero = false, stackFontKey = "Fira Mono", stackFontSize = 10,
        stackOutline = "OUTLINE", stackColor = { r = 1, g = 1, b = 1, a = 1 },
        stackPos = "BOTTOMRIGHT", stackOffX = 2, stackOffY = -2,
        glowEnabled = true, glowType = "pixel", glowColor = { r = 0.96, g = 1, b = 0, a = 1 },  -- F5FF00
        showPressOverlay = false, showKeybinds = false,
    }
    for k, v in pairs(defs) do
        if t[k] == nil then t[k] = (type(v) == "table") and ns.DeepCopy(v) or v end
    end
    if t.timerThresholds == nil then t.timerThresholds = ns.DefaultTrackerTimerThresholds() end
end

-- ── Text anchors (title / stack around an icon) ───────────────────────────────
-- Single source of truth shared by every icon editor + core. The edge modes
-- (TOP/BOTTOM/LEFT/RIGHT) sit just OUTSIDE the icon; the four corner modes sit
-- INSIDE the icon (2px inset); CENTER is dead centre. Each entry is
-- { fontStringPoint, frameRelativePoint, x, y }.
ns.ANCHOR_MODES = {
    "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT",
    "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT",
}
ns.ANCHOR_POINTS = {
    CENTER      = { "CENTER",      "CENTER",       0,  0 },
    TOP         = { "BOTTOM",      "TOP",          0,  2 },
    BOTTOM      = { "TOP",         "BOTTOM",       0, -2 },
    LEFT        = { "RIGHT",       "LEFT",        -2,  0 },
    RIGHT       = { "LEFT",        "RIGHT",        2,  0 },
    TOPLEFT     = { "TOPLEFT",     "TOPLEFT",      2, -2 },
    TOPRIGHT    = { "TOPRIGHT",    "TOPRIGHT",    -2, -2 },
    BOTTOMLEFT  = { "BOTTOMLEFT",  "BOTTOMLEFT",   2,  2 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -2,  2 },
}
-- Place a FontString around `frame` per anchor mode, plus an optional nudge (ox, oy).
function ns.AnchorFS(fs, frame, mode, ox, oy)
    local a = ns.ANCHOR_POINTS[mode] or ns.ANCHOR_POINTS.CENTER
    fs:ClearAllPoints()
    fs:SetPoint(a[1], frame, a[2], a[3] + (ox or 0), a[4] + (oy or 0))
end

-- ── Raw (taint-safe) setters for re-imposing geometry from inside Blizzard's secure CDM refresh ────
-- WoW widget setters are type-bound C closures. When one runs from a hooksecurefunc that re-imposes OUR
-- geometry on a NATIVE frame/region while Blizzard is mid-secure-refresh, a NORMAL SetPoint/SetScale taints
-- that execution and blows up Blizzard's later secret aura/totem/charge comparisons (cf. the CDM taint notes;
-- CDMAnchor's PinNative already uses this trick). A raw C method captured off a throwaway proxy bypasses BOTH
-- the taint AND our own hooks. A FontString needs its OWN proxy (its SetPoint is a different C closure than a
-- Frame's), so CDMAnchor's Frame-proxy setters can't be reused for a FontString.
local _fsProxy            = UIParent:CreateFontString(nil, "ARTWORK")
local RawFSSetPoint       = _fsProxy.SetPoint
local RawFSClearAllPoints = _fsProxy.ClearAllPoints
-- Raw twin of ns.AnchorFS for the ONE tainted caller (BuffGroups ReanchorStack, which re-anchors the native
-- stack-count FontString from inside Blizzard's secure RefreshData). ns.AnchorFS itself STAYS non-raw — it is
-- shared with many safe deferred/config callers and must not change.
function ns.AnchorFSRaw(fs, frame, mode, ox, oy)
    local a = ns.ANCHOR_POINTS[mode] or ns.ANCHOR_POINTS.CENTER
    RawFSClearAllPoints(fs)
    RawFSSetPoint(fs, a[1], frame, a[2], a[3] + (ox or 0), a[4] + (oy or 0))
end
-- Raw SetScale for re-imposing scale=1 on a native VIEWER frame from its SetScale hook (BuffGroups /
-- BarGroups / CDMGroups all lock the viewer scale). Frame-typed, so a Frame proxy is correct.
ns.RawSetScale = CreateFrame("Frame").SetScale

-- Localised dropdown label for an anchor mode (ns.L looked up lazily — the locale
-- engine loads after this file, but these run only when a menu is built).
function ns.AnchorLabel(mode)
    local L = ns.L or {}
    if mode == "TOP"         then return L["Above"]                or "Above"  end
    if mode == "BOTTOM"      then return L["Below"]                or "Below"  end
    if mode == "LEFT"        then return L["Left"]                 or "Left"   end
    if mode == "RIGHT"       then return L["Right"]                or "Right"  end
    if mode == "TOPLEFT"     then return L["Top-left (inside)"]     or "Top-left (inside)"     end
    if mode == "TOPRIGHT"    then return L["Top-right (inside)"]    or "Top-right (inside)"    end
    if mode == "BOTTOMLEFT"  then return L["Bottom-left (inside)"]  or "Bottom-left (inside)"  end
    if mode == "BOTTOMRIGHT" then return L["Bottom-right (inside)"] or "Bottom-right (inside)" end
    return L["Center"] or "Center"
end
function ns.AnchorFromLabel(label)
    for _, m in ipairs(ns.ANCHOR_MODES) do
        if ns.AnchorLabel(m) == label then return m end
    end
    return "CENTER"
end
function ns.AnchorList()
    local t = {}
    for _, m in ipairs(ns.ANCHOR_MODES) do t[#t + 1] = ns.AnchorLabel(m) end
    return t
end

-- ── Brand title colour ───────────────────────────────────────────────────────
-- Every config title/label renders in this blue (the same square the checkboxes
-- use) instead of Blizzard's default gold. Two font objects clone GameFontNormal
-- and GameFontNormalLarge and override ONLY the colour, so the face/size stay
-- identical; config FontStrings inherit one of them (via CreateFontString's 3rd
-- argument, or a BuildMenu `font=` field). Change ns.TITLE_COLOR to recolour
-- every title at once.
ns.BRAND_DEFAULT = { 0.20, 0.55, 1.0 }   -- #338CFF — the base brand blue (Reset target)
-- Live brand colour: a STABLE table, mutated in place by ns.ApplyBrandColor, so every
-- reference that reads it (ns.GetBrandColor / direct C[1..3]) keeps resolving the
-- current colour without re-capturing.
ns.TITLE_COLOR = { ns.BRAND_DEFAULT[1], ns.BRAND_DEFAULT[2], ns.BRAND_DEFAULT[3] }
-- ── Heading scale (h1..h6) ────────────────────────────────────────────────────
-- A small semantic type scale so the config reads as a hierarchy instead of a flat
-- wall of blue. Each level is a font object (same UI face + shadow) differing only
-- in size / weight / colour; FontStrings inherit one via CreateFontString's 3rd arg.
--   H1  window title             19  bold(OUTLINE)  blue
--   H2  module / main cadre title 16  normal         blue
--   H3  sub-cadre / main label    13  normal         blue
--   H4  secondary label           12  normal         blue
--   H5  body text                 12  normal         white
--   H6  small descriptive text     9  normal         white  (colour is overridable:
--       its default is white, but an inline |cRRGGBB..|r colour code in the text
--       wins, e.g. the green Healer-Range probe note / the grey anti-spam hints)
-- UnbunkUtilityTitle / ...Large are kept as legacy aliases (≈ H4 / H1) so any
-- FontString not yet migrated to a tier still renders sensibly (blue).
do
    local C = ns.TITLE_COLOR
    local basePath = GameFontNormal:GetFont()   -- the active UI font face
    ns._fontBasePath = basePath                  -- default face for ns.GetAddonFontPath
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
    Heading("UnbunkUtilityH6", 9,  nil,       1, 1, 1)   -- small descriptive text, white (inline |c..|r overrides)
    Heading("UnbunkUtilityTitle",      12, nil, C[1], C[2], C[3])  -- legacy ≈ H4
    Heading("UnbunkUtilityTitleLarge", 16, nil, C[1], C[2], C[3])  -- legacy ≈ H1/H2
    -- Body text — all the addon's small body labels (buttons, checkboxes, nav rows,
    -- dropdowns, …) inherit this instead of GameFontHighlightSmall. Cloned EXACTLY so
    -- the default look is unchanged; ns.ApplyAddonFont re-faces it like the H tiers.
    local body = CreateFont("UnbunkUtilityBody")
    body:CopyFontObject(GameFontHighlightSmall)
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

-- Real-cooldown DURATION OBJECT for a precise, secret-safe cooldown SWIPE. The engine renders it
-- (Cooldown:SetCooldownFromDurationObject), so the swipe stays accurate in INSTANCED COMBAT where the raw
-- start/duration are SECRET and our heuristic has no data for a spell not cast this session (the old code
-- then drew NO swipe -> the icon looked falsely "ready"). Returns nil when the spell is NOT on a real
-- cooldown (idle, or just the GCD): cd.isActive / cd.isOnGCD are STRUCTURAL booleans that stay readable in
-- combat (unlike the secret timing). Mirrors Ayije_CDM's IsOnRealCooldown + GetSpellCooldownDuration(id, true).
function ns.SpellRealCooldownSwipe(spellId)
    if not (spellId and spellId ~= 0 and C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local cd = C_Spell.GetSpellCooldown(spellId)
    if not (cd and cd.isActive) then return nil end
    -- MULTI-CHARGE spell: the recharging charge's arc is its OWN duration (GetSpellChargeDuration), NOT the
    -- spell cooldown — exactly how the native CDM draws it (we previously drew no recharge arc in combat
    -- because the charge branch nil-drops the secret cdStart and is skipped). maxCharges is a structural
    -- field readable in combat. Ayije gates the charge swipe on isOnGCD == false (strict).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellId)
    local maxc = ci and ci.maxCharges
    if maxc and not (issecretvalue and issecretvalue(maxc)) and maxc > 1 then
        if cd.isOnGCD ~= false then return nil end
        return C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spellId)
    end
    -- Non-charge (or fully-charged): real cooldown only, GCD-only suppressed.
    if cd.isOnGCD == true then return nil end
    return C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellId, true)
end

-- Charge RECHARGE swipe: the recharging-charge arc for a MULTI-charge spell EVEN while a charge is still
-- usable. GetSpellCooldown().isActive is FALSE whenever any charge remains (verified via runtime dump: a
-- Shimmer at 1/2 reports isActive=false), so SpellRealCooldownSwipe draws nothing and the engine's own-draw
-- icon shows no recharge — unlike Blizzard's native CooldownViewer, which always draws it. Returns the charge
-- DURATION OBJECT (secret-safe; consumed C-side by Cooldown:SetCooldownFromDurationObject). At FULL charges the
-- object is already elapsed, so the widget draws nothing. Powers the "Show cd with 1 stacks or more" option.
-- maxCharges is a STRUCTURAL field (readable in combat); currentCharges is never read here (it is secret).
function ns.SpellChargeRechargeSwipe(spellId)
    if not (spellId and spellId ~= 0 and C_Spell and C_Spell.GetSpellCharges) then return nil end
    local ci = C_Spell.GetSpellCharges(spellId)
    local maxc = ci and ci.maxCharges
    if not (maxc and not (issecretvalue and issecretvalue(maxc)) and maxc > 1) then return nil end
    return (C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spellId)) or nil
end

-- OPTIONAL global-cooldown SWIPE (opt-in; SpellRealCooldownSwipe deliberately suppresses it so an idle spell
-- looks ready). Returns the GCD's duration object ONLY when the spell's ACTIVE cooldown IS the GCD (a spell
-- with no real cooldown, on the global). Lets the standalone engine draw a Coolinator-style GCD spin (no
-- number). Secret-safe: isActive/isOnGCD are STRUCTURAL; GetSpellCooldownDuration(id, false) INCLUDES the GCD
-- and returns a duration OBJECT (never the secret raw start/duration).
function ns.SpellGcdSwipe(spellId)
    if not (spellId and spellId ~= 0 and C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local cd = C_Spell.GetSpellCooldown(spellId)
    if not (cd and cd.isActive and cd.isOnGCD == true) then return nil end
    return C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellId, false)
end

-- The CURRENT global cooldown as a duration OBJECT (secret-safe), for a Coolinator-style GCD spin on EVERY
-- idle icon when you cast — including OFF-GCD spells (Counterspell / Alter Time / Mirror Image) and charge
-- spells, which a per-spell GetSpellCooldown never reports "on GCD" (off-GCD spells answer isOnGCD~=true; a
-- charge spell answers isActive=false while a charge remains). Spell 61304 is Blizzard's hidden "Global
-- Cooldown" whose cooldown IS the live GCD. Returns nil when no GCD is running (idle) → the spin clears.
local GCD_SPELL = 61304
function ns.GlobalGcdSwipe()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local cd = C_Spell.GetSpellCooldown(GCD_SPELL)
    if not (cd and cd.isActive) then return nil end
    return C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(GCD_SPELL, false)
end

-- Size of one physical screen pixel in UIParent-local units, for crisp 1px borders on fractional UI scale
-- (768 = UIParent's reference height; divided by the effective scale). Returns nil if the values aren't
-- ready yet, so callers fall back to the raw size. Mirrors Ayije_CDM's Pixel.GetSize formula. NOTE: a UI
-- scale change is only picked up on the next border re-apply (relayout) — a /reload re-crisps everything.
function ns.PixelSize()
    local _, physH = GetPhysicalScreenSize()
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if physH and physH > 0 and scale and scale > 0 then
        return 768 / (physH * scale)
    end
    return nil
end

-- ── Taint scrub (de-taint one table key via forced rehash) ───────────────────
-- Force a Lua table to drop the taint carried on ONE key. Setting t[k]=nil leaves a "dead"
-- hash node that STILL holds the taint, so issecurevariable(t,k) keeps reporting insecure; we
-- then poke absent integer keys until WoW's Lua 5.1 rehashes the table and abandons every dead
-- node (the tainted k included), after which the key reads clean. This is the only way to scrub
-- a key that a secret/forbidden value tainted short of a /reload (see the Coolinator analysis
-- and the CooldownViewer:901 wall — a secret spellID key turning wasOnGCDLookup forbidden).
--
-- Guards vs Coolinator's original: we ONLY ever touch keys that are already nil (never a live
-- value), bail immediately if the key is already clean, and cap the loop so a key that can never
-- come clean cannot hang the client (a rehash happens within a few dozen pokes; the cap is a
-- safety net). Returns true when the key ends up secure, false if it gave up.
--
-- ⚠ Call ONLY on a key you may legitimately nil out (a regenerable cache field) AND whose taint
-- source you understand — this scrubs one key, not the table's or the execution's taint, and it
-- MUTATES the table. Do not sweep blindly. There is currently no wired caller: it's a tool kept
-- ready for a confirmed taint-key site (901 is NOT on our hook stack, so it does not apply there).
function ns.PurgeTaintedKey(t, k)
    if type(t) ~= "table" or type(issecurevariable) ~= "function" then return false end
    t[k] = nil
    if issecurevariable(t, k) then return true end   -- already clean: nothing to rehash
    local c = 42                                      -- start high so we skip small live int keys
    for _ = 1, 100000 do
        if t[c] == nil then t[c] = nil end            -- creating+clearing an absent key forces a rehash
        c = c + 1
        if issecurevariable(t, k) then return true end
    end
    return false                                      -- gave up; caller should fall back (e.g. prompt /reload)
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
    width   = 36,   -- default icon size; copied into each bucket (front/end) by the per-bucket
    height  = 36,   -- migration, after which each bucket carries its OWN width/height
    -- Manual mode: OFF -> both buckets stay flush under the PlayerFrame (front at the
    -- bottom-LEFT, end at the bottom-RIGHT) at offset 0,0 (offsets ignored, dragging
    -- disabled). ON -> the per-bucket offsets / drag take effect so each bucket can be
    -- placed independently.
    -- Master toggle for the WHOLE below-player row. ON by default (like the sibling
    -- Essential/Utility/Buffs engines). OFF -> the row's icons simply don't render (you can still
    -- assign icons to the row; they just won't show while it's off — NOT reverted to free placement).
    enabled = true,
    manualEnabled = false,
    offsetX = 0,    -- FRONT bucket nudge from PlayerFrame's BOTTOMLEFT  (manual only)
    offsetY = 0,
    endOffsetX = 0, -- END  bucket nudge from PlayerFrame's BOTTOMRIGHT (manual only)
    endOffsetY = 0,
    -- Shared border for every below-player icon (the panel's "Border" cadre).
    borderEnabled = true,
    borderColor   = { r = 0, g = 0, b = 0, a = 1 },
    borderSize    = 1,
}

-- Debug "Console mode" options (account-wide). textEditor on by default (bottom
-- input box shown); the chat-capture buckets are all OFF by default, so the console
-- starts mirroring only print() output.
local DEFAULTS_CONSOLE = {
    textEditor     = true,
    allowSelection = false,
    chPlayers      = false,
    chChannels     = false,
    chOthers       = false,
}

-- Debug "Print" panel: per-addon CPU/Memory usage printed to chat every `interval`
-- seconds. cpu/mem map an addon folder name -> true when selected (account-wide).
local DEFAULTS_PRINT_USAGE = {
    interval = 5,
    active   = false,   -- printing is OFF until Start (button or /ubu debug print start)
    showDiff = true,    -- show the coloured ± change vs the previous tick
    cpu      = {},
    mem      = {},
}

-- Debug "Graph" panel: per-addon CPU/Memory plotted in graph windows. Own selection
-- (independent of the Print panel). cpu/mem map an addon folder name -> true.
local DEFAULTS_GRAPH_USAGE = {
    interval = 5,
    showDiff = true,
    cpu      = {},
    mem      = {},
    win      = {},   -- per-metric saved window size: win.cpu / win.mem = { w = , h = }
}

-- Seed ONE below-player bucket sub-table (cdmBelowRow.front / .end) with essential's
-- Timer/Title/Stacks defaults (missing keys only, additive) so the REUSED essential
-- sections + TimerIcon read correct values even on a fresh install that never opened the
-- panel: Stacks on/10/Bottom-right, Title off/12/Above, Timer on/14/Center + the 10s×1.2 /
-- 3s×1.45 thresholds. Sourced from CDMGroups' GROUP_TEMPLATE (resolved at call time, so load
-- order is irrelevant); a no-op until CDMGroups is present.
local BELOW_SEED_KEYS = {
    "showTimer","timerFontKey","timerFontPath","timerFontSize","timerOutline","timerColor","timerPos","timerOffX","timerOffY","timerThresholdsEnabled",
    "showTitle","titleText","titleFontKey","titleFontPath","titleFontSize","titleOutline","titleColor","titlePos","titleOffX","titleOffY",
    "showStack","showAtZero","stackFontKey","stackFontPath","stackFontSize","stackOutline","stackColor","stackPos","stackOffX","stackOffY",
}
function ns.SeedBelowBucketDefaults(tbl)
    if not tbl then return end
    local GT = ns.CDMGroups and ns.CDMGroups.GROUP_TEMPLATE
    if not GT then return end
    for _, k in ipairs(BELOW_SEED_KEYS) do
        if tbl[k] == nil and GT[k] ~= nil then
            tbl[k] = (type(GT[k]) == "table") and ns.DeepCopy(GT[k]) or GT[k]
        end
    end
    if tbl.timerThresholds == nil and ns.CDMGroups.DEFAULT_TIMER_THRESHOLDS then
        tbl.timerThresholds = ns.DeepCopy(ns.CDMGroups.DEFAULT_TIMER_THRESHOLDS)
    end
end

function ns.InitGlobalCfg()
    if not ns.db then return end
    local g = ns.db.global
    local p = ns.db.profile
    -- Walk the global table to rewrite any pre-restructure sound key.
    ns.MigrateSoundKeys(g)
    g.combo       = g.combo       or {}
    g.wipe        = g.wipe        or {}
    g.dpsSpam     = g.dpsSpam     or {}
    g.bossReset   = g.bossReset   or {}
    g.cdmBelowRow = g.cdmBelowRow or {}   -- legacy account-wide source for the migration below

    -- One-time migration: the debug-suite + appearance settings below used to be
    -- account-wide (db.global); they are now PER-PROFILE (db.profile). Fold the old
    -- global values into whichever profile is active at upgrade, once; other profiles
    -- start from defaults. The old globals are left untouched as a harmless backup.
    if p and not g.__profileSettingsMigrated then
        for _, k in ipairs({ "console", "printUsage", "graphUsage", "brandColor", "fontKey", "debugUnlocked" }) do
            if g[k] ~= nil and p[k] == nil then p[k] = ns.DeepCopy(g[k]) end
        end
        g.__profileSettingsMigrated = true
    end

    -- Per-profile (merged into the ACTIVE profile, so switching profiles applies its own).
    p.console     = p.console     or {}
    p.printUsage  = p.printUsage  or {}
    p.graphUsage  = p.graphUsage  or {}

    -- CDM layout (below-player row + per-viewer placement/size) lives in the PROFILE so the
    -- whole CDM setup travels with profile export/import/switch, alongside the icon data
    -- (cdmCustom / cdmOrder / per-icon dest+row+atEnd) already kept per-profile.
    p.cdmBelowRow = p.cdmBelowRow or {}
    -- Migrate the old account-wide below-player config into the active profile ONCE (own
    -- flag, so it runs even for accounts that passed the appearance migration above). The
    -- global copy is left as a harmless backup.
    if not g.__cdmBelowRowMigrated then
        g.__cdmBelowRowMigrated = true
        for k, v in pairs(g.cdmBelowRow) do
            if p.cdmBelowRow[k] == nil then p.cdmBelowRow[k] = ns.DeepCopy(v) end
        end
    end
    -- Per-viewer placement/size, seeded ONCE per profile with the default layout
    -- (Essentials 0,-275 / Utility 0,-260; per-row icon size defaults to 44 in CDMAnchor).
    -- The seed never re-applies, so a Reset (clearing x/y) persists across reloads.
    p.cdmViewer = p.cdmViewer or {}
    if not p.cdmViewer.__seeded then
        p.cdmViewer.__seeded  = true
        p.cdmViewer.essential = p.cdmViewer.essential or {}
        p.cdmViewer.utility   = p.cdmViewer.utility   or {}
        if p.cdmViewer.essential.x == nil then p.cdmViewer.essential.x, p.cdmViewer.essential.y = 0, -175 end
        if p.cdmViewer.utility.x   == nil then p.cdmViewer.utility.x,   p.cdmViewer.utility.y   = 0, -260 end
    end
    -- Correct the earlier Essentials default (0,-275) -> (0,-175); a value the user
    -- actually changed is left alone.
    local ess = p.cdmViewer.essential
    if ess and ess.x == 0 and ess.y == -275 then ess.y = -175 end

    ns.MergeDefaults(g.combo,       DEFAULTS_COMBO)
    ns.MergeDefaults(g.wipe,        DEFAULTS_WIPE)
    ns.MergeDefaults(g.dpsSpam,     DEFAULTS_DPS_SPAM)
    ns.MergeDefaults(g.bossReset,   DEFAULTS_BOSS_RESET)
    ns.MergeDefaults(p.cdmBelowRow, DEFAULTS_CDM_BELOW_ROW)

    -- ── Below-player per-bucket split (front / end) ──────────────────────────────
    -- The below-player row is two buckets ("front of the row" / "end of the row"); their
    -- appearance + layout settings (CDM flags, grow/static/spacing, border, glow, icon size,
    -- Timer/Title/Stacks) are PER-BUCKET, stored on cdmBelowRow.front and cdmBelowRow.end.
    -- The flat keys on cdmBelowRow are kept untouched as a harmless backup and still hold the
    -- bucket-agnostic ones (manualEnabled / offsets / settingsCollapsed).
    do
        local r = p.cdmBelowRow
        r.front  = r.front  or {}
        r["end"] = r["end"] or {}
        -- One-time: copy the pre-split flat per-bucket keys into BOTH buckets so an existing
        -- setup keeps its look on both halves. Runs after the flat MergeDefaults above, so a
        -- fresh install seeds the bucket width/height/border from the flat defaults too.
        if not r.__perBucketV1 then
            r.__perBucketV1 = true
            local FLAT_KEEP = {
                manualEnabled = true, offsetX = true, offsetY = true,
                endOffsetX = true, endOffsetY = true, settingsCollapsed = true,
                front = true, ["end"] = true, __perBucketV1 = true,
            }
            for _, bucket in ipairs({ "front", "end" }) do
                local b = r[bucket]
                for k, v in pairs(r) do
                    if not FLAT_KEEP[k] and b[k] == nil then
                        b[k] = ns.DeepCopy(v)
                    end
                end
            end
        end
        -- Backfill each bucket's Timer/Title/Stacks defaults (missing keys only) for fresh
        -- installs that never opened the panel.
        ns.SeedBelowBucketDefaults(r.front)
        ns.SeedBelowBucketDefaults(r["end"])
    end

    ns.MergeDefaults(p.console,     DEFAULTS_CONSOLE)
    ns.MergeDefaults(p.printUsage,  DEFAULTS_PRINT_USAGE)
    ns.MergeDefaults(p.graphUsage,  DEFAULTS_GRAPH_USAGE)
end

ns.RegisterCfgInitHook(ns.InitGlobalCfg)

-- ── Brand colour: single source of truth + live re-apply ──────────────────────
-- The blue is read live from ns.TITLE_COLOR everywhere (ns.GetBrandColor). A stored
-- override lives account-wide in ns.db.global.brandColor; ns.ApplyBrandColor pushes
-- it to the H1..H4 font objects (recolouring ALL brand-blue TEXT instantly) and runs
-- registered hooks so persistent non-text elements (window chrome, module borders)
-- re-tint live too. Reset clears the override back to ns.BRAND_DEFAULT.
ns.brandColorHooks = ns.brandColorHooks or {}
-- Weak-keyed registry of brand-tinted targets, re-applied live by ns.ApplyBrandColor.
-- Each entry is [key] = function(r,g,b) that re-tints that widget (border, vertex glyph,
-- or a checkbox's UpdateVisual). WEAK keys → orphaned widgets (rebuilt config rows,
-- pooled icons) are GC'd instead of leaking, so this is safe even for transient widgets.
ns._brandTargets = ns._brandTargets or setmetatable({}, { __mode = "k" })

function ns.GetBrandColor()
    local c = ns.TITLE_COLOR
    return c[1], c[2], c[3]
end

function ns.RegisterBrandColorHook(fn)
    if type(fn) == "function" then ns.brandColorHooks[#ns.brandColorHooks + 1] = fn end
end

function ns.ApplyBrandColor()
    local col = (ns.db and ns.db.profile and ns.db.profile.brandColor) or ns.BRAND_DEFAULT
    local r, g, b = col[1], col[2], col[3]
    ns.TITLE_COLOR[1], ns.TITLE_COLOR[2], ns.TITLE_COLOR[3] = r, g, b
    for _, name in ipairs({
        "UnbunkUtilityH1", "UnbunkUtilityH2", "UnbunkUtilityH3", "UnbunkUtilityH4",
        "UnbunkUtilityTitle", "UnbunkUtilityTitleLarge",
    }) do
        local fo = _G[name]
        if fo and fo.SetTextColor then fo:SetTextColor(r, g, b) end
    end
    for _, fn in pairs(ns._brandTargets) do pcall(fn, r, g, b) end
    for _, fn in ipairs(ns.brandColorHooks) do pcall(fn, r, g, b) end
end

function ns.SetBrandColor(r, g, b)
    if ns.db and ns.db.profile then ns.db.profile.brandColor = { r, g, b } end
    ns.ApplyBrandColor()
end

function ns.ResetBrandColor()
    if ns.db and ns.db.profile then ns.db.profile.brandColor = nil end
    ns.ApplyBrandColor()
end

-- Register a frame's backdrop border as brand-tinted (set now + re-applied live).
-- Safe for any frame, transient or not (weak registry GCs orphans).
function ns.SetBrandBorder(frame, a)
    if not frame then return end
    a = a or 1
    local fn = function(r, g, b)
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(r, g, b, a) end
    end
    ns._brandTargets[frame] = fn
    fn(ns.GetBrandColor())
end

-- Register a texture as brand-tinted (white glyph -> brand blue; re-tinted live).
function ns.SetBrandVertex(tex)
    if not tex then return end
    local fn = function(r, g, b)
        if tex.SetVertexColor then tex:SetVertexColor(r, g, b) end
    end
    ns._brandTargets[tex] = fn
    fn(ns.GetBrandColor())
end

-- Register an arbitrary live re-tint callback, weakly keyed by a frame (e.g. a
-- checkbox's UpdateVisual, which re-reads ns.GetBrandColor itself). Called on change.
function ns.RegisterBrandRefresh(key, fn)
    if key and type(fn) == "function" then ns._brandTargets[key] = fn end
end

-- Apply the stored brand colour once ns.db is ready (registered AFTER InitGlobalCfg so
-- the global table exists). Module hooks created later re-read GetBrandColor() anyway.
ns.RegisterCfgInitHook(ns.ApplyBrandColor)

-- ── Style epoch: the CDM group engines' per-frame StyleFrame cache key ─────────
-- The group engines (CDMGroups essential/utility + BuffGroups) re-run their heavy
-- per-icon StyleFrame (≈50 config reads + ~20 SetFont/SetTexCoord/border/glow calls
-- per icon) ONLY when this counter changes OR a frame's spellId in its slot changes —
-- NOT on every RefreshLayout pass. Anything that alters how an icon should look bumps
-- it: a config edit (each module's ApplyAll), a profile/spec rebuild, a brand-colour
-- change, a keybind rebind. Combat (the hot path) never bumps it, so the gate holds and
-- the per-frame combat cost collapses to geometry + the cheap timer-tier refresh. This
-- is the fix for "the CDM tabs cost far more CPU than every other addon": we were paying
-- a full restyle of every icon 5-20x/second when nothing about the styling had changed.
ns.StyleEpoch = ns.StyleEpoch or 1
function ns.BumpStyleEpoch()
    ns.StyleEpoch = (ns.StyleEpoch or 0) + 1
    -- LIVE-REFRESH the standalone CDM engine on any config edit. The native CDM modules bump this shared
    -- epoch from their ApplyAll (which every config touch() routes through) + on a mode switch, and NEVER
    -- per-frame. In engine mode the same native config drives the engine's render, so re-derive its layout.
    -- Coalesced via ScheduleRebuild; the engine's own rebuild never bumps the epoch, so no loop.
    if ns.CDMMode and ns.CDMMode.IsEngine and ns.CDMMode.IsEngine()
       and ns.CDMEngine and ns.CDMEngine.Layout and ns.CDMEngine.Layout.ScheduleRebuild then
        ns.CDMEngine.Layout.ScheduleRebuild()
    end
end
-- A live brand-colour change can alter brand-derived icon defaults → invalidate the cache.
ns.RegisterBrandColorHook(ns.BumpStyleEpoch)
-- A native (Blizzard keybinding UI) rebind fires UPDATE_BINDINGS but never passes through a
-- module's config path, so it wouldn't otherwise invalidate the per-icon style gate (which
-- caches the displayed keybind text). Bump the epoch so the next pass re-reads GetBindingKey.
do
    local bindWatch = CreateFrame("Frame")
    bindWatch:RegisterEvent("UPDATE_BINDINGS")
    bindWatch:SetScript("OnEvent", function() ns.BumpStyleEpoch() end)
end

-- ── Shared 0.5s poll driver ───────────────────────────────────────────────────
-- The trackers each used to own a 0.5s repeating timer (~9 independent AceTimer/C_Timer
-- wakeups, most early-outing immediately). They now share ONE driver: a module registers a
-- named callback via ns.SharedTick.Register and a single ticker fans them all out per tick —
-- one scheduler wakeup instead of N. The driver exists only while ≥1 callback is registered
-- (created on the first Register, cancelled when the last unregisters), so "all trackers off"
-- costs nothing. Iteration walks a reused snapshot array, so a callback may (un)register mid-
-- tick (effective next tick), and each runs under the game's error handler — preserving the
-- independent-timer property that one module's error can't stop the others or the driver.
do
    local cbs  = {}    -- [name] = fn
    local snap = {}    -- reused scratch (re-entrancy-safe iteration)
    local driver
    local function tick()
        local n = 0
        for _, fn in pairs(cbs) do n = n + 1; snap[n] = fn end
        for i = 1, n do
            local fn = snap[i]; snap[i] = nil
            xpcall(fn, geterrorhandler())
        end
    end
    ns.SharedTick = {}
    function ns.SharedTick.Register(name, fn)
        cbs[name] = fn
        if not driver then driver = C_Timer.NewTicker(0.5, tick) end
    end
    function ns.SharedTick.Unregister(name)
        if cbs[name] == nil then return end
        cbs[name] = nil
        if driver and next(cbs) == nil then driver:Cancel(); driver = nil end
    end
end

-- ── Addon font: single source of truth + live re-face ─────────────────────────
-- ns.SetAddonFont(lsmKey) stores an account-wide font override; ns.ApplyAddonFont
-- re-faces EVERY addon-owned font object (H1..H6 / Title / Body), preserving each
-- tier's size + flags — so ALL addon text that uses them changes face instantly, no
-- reload. nil key = the default UI face (ns._fontBasePath), i.e. the original look.
ns.ADDON_FONTS = {
    "UnbunkUtilityH1", "UnbunkUtilityH2", "UnbunkUtilityH3", "UnbunkUtilityH4",
    "UnbunkUtilityH5", "UnbunkUtilityH6", "UnbunkUtilityTitle", "UnbunkUtilityTitleLarge",
    "UnbunkUtilityBody",
}

function ns.GetAddonFontPath()
    local key = ns.db and ns.db.profile and ns.db.profile.fontKey
    if key then return ns.ResolveFontPath(nil, key) end
    return ns._fontBasePath or "Fonts\\FRIZQT__.TTF"
end

-- The LSM font NAME in effect: the stored override, else the name matching the default
-- face — so the picker can show/select the REAL default font instead of "Default font".
function ns.GetAddonFontKey()
    local key = ns.db and ns.db.profile and ns.db.profile.fontKey
    if key then return key end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and ns._fontBasePath then
        for name, path in pairs(LSM:HashTable("font")) do
            if path == ns._fontBasePath then return name end
        end
    end
    return nil
end

function ns.ApplyAddonFont()
    local path = ns.GetAddonFontPath()
    if not path then return end
    for _, name in ipairs(ns.ADDON_FONTS) do
        local fo = _G[name]
        if fo and fo.GetFont then
            local _, size, flags = fo:GetFont()
            if size then fo:SetFont(path, size, flags) end
        end
    end
end

function ns.SetAddonFont(key)
    if ns.db and ns.db.profile then ns.db.profile.fontKey = key end
    ns.ApplyAddonFont()
end

ns.RegisterCfgInitHook(ns.ApplyAddonFont)
