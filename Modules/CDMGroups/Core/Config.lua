-- Modules/CDMGroups/Core/Config.lua
-- Data model for the custom "Cooldown groups" — a GENERALIZED, dest-parameterized clone of
-- Modules/BuffGroups/Core/Config.lua. Where BuffGroups is hard-wired to the native Buff viewer
-- (BuffIconCooldownViewer + Enum.CooldownViewerCategory.TrackedBuff), THIS module is a factory:
-- ns.CDMGroups.Make(dest) builds one self-contained INSTANCE (all the same accessors) bound to a
-- destination ("essential" + "utility" are both instantiated). Each instance reads/writes
-- ns.db.profile.cdmGroups[dest], so two dests never share state.
--
-- We REUSE the native cooldown viewer frames — re-sized, re-styled and re-anchored into user-defined
-- GROUPS (movable containers), exactly like BuffGroups / Ayije_CDM. The native viewer is NOT hidden;
-- we drive its frames so Blizzard keeps rendering the cooldown swipe / charges / combat-safe state.
--
-- Per-profile (ns.db.profile.cdmGroups[dest]):
--   groups[id] = a GROUP: position + grow direction + geometry + border/glow + the native text
--                restyle (timer / title / stacks). Applies to every icon in it.
--   assign[spellId] = groupId  -- which group a cooldown belongs to:
--                               --   nil  -> Group 1 (the default, indelible group)
--                               --   0    -> "Unused" (hidden entirely, parked in config)
--                               --   N>=1 -> that group
--   order[groupId]  = { {sid,sid,...}, {sid,...}, ... }  -- EXPLICIT ROWS: an array of rows,
--                               -- each an array of spellIds (the multi-row layout). Legacy flat
--                               -- order[groupId]={sid,...} is migrated to rows of maxPerRow.
--   custom[spellId] = { duration, name, icon }  -- cast-triggered customs the user "+"-added
--   iconCfg[spellId] = SPARSE per-icon overrides (the pencil): a SUBSET of the group keys.
--   enabled         -- gates the engine + the OwnsDest takeover (default OFF so nothing breaks).
-- Group 1 always exists and can't be deleted; group 0 ("Unused") hides its icons.
--
-- The runtime model (confirmed by a live diagnostic — the category set is the WRONG source):
--   * The viewer's itemFramePool is the SOURCE OF TRUTH, exactly like BuffGroups. Its active frames
--     ARE the cooldowns the viewer displays; GetCooldownViewerCategorySet does NOT match them (it
--     misses the defensives and leaks not-displayed spells), so the engine DROPS the category set.
--   * UNIVERSE of groupable cooldowns = the engine's I.AllBuffs() = the DISPLAYED (pool) set UNION any
--     explicitly-assigned spellId in the store (so a manual assignment survives a cooldown momentarily
--     leaving the pool). Mirrors BuffGroups' "displayed ∪ assigned ∪ custom".
--   * DISPLAYED set = the spellIds currently in the pool (I.IsDisplayed, kept fresh by the engine's
--     ticker / viewer hook). An UNASSIGNED cooldown defaults to Group 1 only if it's DISPLAYED; a
--     not-displayed one defaults to Unused. Like BuffGroups.
--   * The Essential viewer's itemFramePool is DYNAMIC: it holds frames for the displayed cooldowns and
--     toggles IsShown() per cooldown state. The live pool is also what we POSITION.

local _, ns = ...
ns.CDMGroups = ns.CDMGroups or {}
local CDG = ns.CDMGroups

-- Max icons per group: the config strip caps a group here; the default seeding fills Group 1 freely
-- (Essential has few cooldowns), Unused wraps. Shared by the engine + the config UI.
CDG.GROUP_CAP = 14

-- ── Per-group settings (the full set; every icon in the group inherits these) ──
-- A freshly created group is GROUP_TEMPLATE + an id/name/position. Identical key set to BuffGroups'
-- GROUP_TEMPLATE so the SHARED UI sub-cadres (Timer/Title/Stacks) and the per-icon override editor
-- work unchanged. GGet falls back to GROUP_TEMPLATE for any key a saved group predates.
local GROUP_TEMPLATE = {
    -- placement
    anchorTo = "essential",    -- "essential" | "utility" | "belowPlayer" | "screen"
    relPos   = "above",        -- side/corner of the anchor: above|below|left|right|topleft|topright|bottomleft|bottomright
    growDir  = "CENTER_H",     -- "RIGHT" | "LEFT" | "UP" | "DOWN" | "CENTER_H" | "CENTER_V"
    spacing  = 1,
    -- multi-row layout: a group's icons are laid out in EXPLICIT ROWS (see order[groupId]); a new
    -- row auto-starts after maxPerRow icons, and the config strip wraps here. The in-game layout
    -- stacks successive rows along the cross axis.
    maxPerRow = 6,
    staticDisplay = false,     -- false: only currently-shown cooldowns take a slot (reflow); true: every member keeps its slot
    -- geometry
    iconW = 44, iconH = 44,
    -- placeholder (PER-ICON only; the pencil toggles it). When ON the icon ALWAYS reserves its slot.
    placeholder = false,
    -- border (our own child frame, the native debuff/charge border is left alone)
    borderEnabled = true,
    borderColor   = { r = 0, g = 0, b = 0, a = 1 },
    borderSize    = 1,
    -- glow (LibCustomGlow around an active icon) — shown only while the spell is procced
    glowEnabled = true,
    glowType    = "pixel",                          -- "pixel" | "autocast" | "button" | "proc"
    glowColor   = { r = 0.96, g = 1, b = 0, a = 1 },   -- F5FF00
    -- CDM bar integration: flash the icon while its action-bar keybind is physically HELD (press overlay);
    -- draw that keybind's text on the icon (show keybinds). Both default OFF (opt-in; resolves keybinds
    -- from the standard bars, and the overlay runs a light poll). Both are per-icon overridable.
    showPressOverlay  = false,
    showKeybinds      = false,
    pressOverlayColor = { r = 1, g = 1, b = 1, a = 0.35 },
    -- keybind text styling (mirrors the title text pattern); legible top-left by default
    keybindFontKey = "Fira Mono", keybindFontPath = nil, keybindFontSize = 12, keybindOutline = "OUTLINE",
    keybindColor   = { r = 1, g = 1, b = 1, a = 1 },
    keybindPos     = "TOPLEFT", keybindOffX = 2, keybindOffY = -2,
    -- timer / countdown text (restyle of the native Cooldown countdown)
    showTimer     = true,
    timerFontKey  = "Fira Mono", timerFontPath = nil, timerFontSize = 14, timerOutline = "OUTLINE",
    timerColor    = { r = 1, g = 1, b = 1, a = 1 },
    timerPos      = "CENTER", timerOffX = 0, timerOffY = 0,
    timerThresholdsEnabled = true,
    -- title text (a free label over the icon)
    showTitle     = false, titleText = "",
    titleFontKey  = "Fira Mono", titleFontPath = nil, titleFontSize = 12, titleOutline = "OUTLINE",
    titleColor    = { r = 1, g = 1, b = 1, a = 1 },
    titlePos      = "TOP", titleOffX = 0, titleOffY = 0,
    -- stack / charge count text (native Applications restyle)
    showStack     = true, showAtZero = false,
    stackFontKey  = "Fira Mono", stackFontPath = nil, stackFontSize = 10, stackOutline = "OUTLINE",
    stackColor    = { r = 1, g = 1, b = 1, a = 1 },
    stackPos      = "BOTTOMRIGHT", stackOffX = 2, stackOffY = -2,
    -- sound alert (PER-ICON only; the pencil writes these). Both off by default.
    soundStartEnabled = false, soundStartSound = nil, soundStartPath = nil,
    soundStopEnabled  = false, soundStopSound  = nil, soundStopPath  = nil,
    -- runtime
    unlocked      = false,
}
CDG.GROUP_TEMPLATE = GROUP_TEMPLATE

-- Default time-threshold tiers (yellow @10s, red @3s). Same intent + structure as BuffGroups: kept
-- OUT of GROUP_TEMPLATE so MergeDefaults can't re-add a deleted tier; seeded once per group in CfgInit.
local DEFAULT_TIMER_THRESHOLDS = {
    { time = 10, size = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { time = 3,  size = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
CDG.DEFAULT_TIMER_THRESHOLDS = DEFAULT_TIMER_THRESHOLDS

-- Per-icon override subset (the pencil writes only these via IconSet; IconGet still resolves ANY key
-- by falling through to the group). Identical to BuffGroups.ICON_OVERRIDE_KEYS.
local ICON_OVERRIDE_KEYS = {
    borderEnabled = true, borderColor = true, borderSize = true,
    iconW = true, iconH = true,
    showTimer = true, showTitle = true, showStack = true,
    glowEnabled = true, glowType = true, glowColor = true,
    showPressOverlay = true, showKeybinds = true,
}
CDG.ICON_OVERRIDE_KEYS = ICON_OVERRIDE_KEYS

-- Group 1 defaults: the indelible default group. Dest-aware: the ESSENTIAL Group 1 lives at
-- SCREEN-CENTER (CENTER-to-CENTER of UIParent, posX/posY offset from center) since it's the primary
-- block; the UTILITY Group 1 instead defaults to sitting flush BELOW the Essential block (anchorTo
-- "essential", relPos "below", 0/0) so the two stack vertically out of the box. The GROUP_TEMPLATE
-- itself stays generic.
local function MakeGroup1(dest)
    local g = ns.DeepCopy(GROUP_TEMPLATE)
    g.id   = 1
    g.name = "Group 1"
    if dest == "utility" then
        g.anchorTo = "essential"
        g.relPos   = "below"
        g.posX     = 0
        g.posY     = 0
    else
        g.posX = 0
        g.posY = -220   -- sits below screen center (where the Essential CDM normally lives); other groups default to 0
        g.anchorTo = "screen"
    end
    return g
end

local function MakeDefaults(dest)
    return {
        enabled = true,           -- DEFAULT ON: the engine takes over the native Essential viewer
        nextId  = 2,
        groups  = {},             -- seeded with Group 1 in CfgInit
        assign  = {},
        custom  = {},             -- custom[spellId] = { duration, name, icon } (cast-triggered customs)
        order   = {},             -- order[groupId] = { {spellId,...}, {spellId,...} } (explicit rows)
        iconCfg = {},             -- iconCfg[spellId] = sparse per-icon overrides (the pencil)
    }
end

-- ════════════════════════════════════════════════════════════════════════════════
-- The per-dest INSTANCE factory. Returns a table whose method shape mirrors ns.BuffGroups
-- (so the cloned engine + UI can use it verbatim, just bound to a different store). The
-- engine attaches its own runtime methods (RefreshLayout, AllCooldowns, NativeOrder, …) onto
-- the SAME instance table later — Config only owns the data model here.
-- ════════════════════════════════════════════════════════════════════════════════
CDG.instances = CDG.instances or {}

local function Store(dest)
    if not (ns.db and ns.db.profile) then return nil end
    ns.db.profile.cdmGroups = ns.db.profile.cdmGroups or {}
    return ns.db.profile.cdmGroups[dest]
end

function CDG.Make(dest)
    if CDG.instances[dest] then return CDG.instances[dest] end
    local I = { dest = dest, GROUP_CAP = CDG.GROUP_CAP,
                GROUP_TEMPLATE = GROUP_TEMPLATE,
                DEFAULT_TIMER_THRESHOLDS = DEFAULT_TIMER_THRESHOLDS,
                ICON_OVERRIDE_KEYS = ICON_OVERRIDE_KEYS }
    CDG.instances[dest] = I

    function I.Store() return Store(dest) end

    function I.CfgInit()
        if not ns.db then return end
        ns.db.profile.cdmGroups = ns.db.profile.cdmGroups or {}
        ns.db.profile.cdmGroups[dest] = ns.db.profile.cdmGroups[dest] or {}
        local s = ns.db.profile.cdmGroups[dest]
        ns.MergeDefaults(s, MakeDefaults(dest))
        s.groups = s.groups or {}
        if not s.groups[1] then s.groups[1] = MakeGroup1(dest) end
        -- Backfill every group with newly-added GROUP_TEMPLATE keys (no per-key migration).
        for _, g in pairs(s.groups) do ns.MergeDefaults(g, GROUP_TEMPLATE) end
        -- Seed the threshold LIST per group only when absent (kept out of MergeDefaults).
        for _, g in pairs(s.groups) do
            if g.timerThresholds == nil then g.timerThresholds = ns.DeepCopy(DEFAULT_TIMER_THRESHOLDS) end
        end
        if not s.nextId or s.nextId < 2 then s.nextId = 2 end
        -- One-time, DEFENSIVE migration of order[] from the FLAT model (order[gid]={sid,...}) to the
        -- EXPLICIT ROW model (order[gid]={{sid,...}, {sid,...}}). A flat list is chunked into rows of
        -- the group's maxPerRow. NormalizeOrder (below) also handles both shapes lazily, so a
        -- half-migrated / never-migrated profile never errors; this pass just rewrites it once so the
        -- stored data matches the new shape. Detected by the first element's type: a number = flat.
        s.order = s.order or {}
        for gid, o in pairs(s.order) do
            if type(o) == "table" and type(o[1]) == "number" then
                local per = (s.groups[gid] and s.groups[gid].maxPerRow) or GROUP_TEMPLATE.maxPerRow
                if not (type(per) == "number" and per >= 1) then per = GROUP_TEMPLATE.maxPerRow end
                local rows, row = {}, {}
                for _, sid in ipairs(o) do
                    row[#row + 1] = sid
                    if #row >= per then rows[#rows + 1] = row; row = {} end
                end
                if #row > 0 then rows[#rows + 1] = row end
                s.order[gid] = rows
            end
        end
        -- One-time: the ESSENTIAL Group 1's default Y becomes -222 (below screen center, where the
        -- Essential CDM normally sits). Applied once to a profile whose Group 1 predates this default (it
        -- was 0). ESSENTIAL-ONLY: utility's Group 1 anchors flush BELOW Essential (posY 0 from MakeGroup1)
        -- and never predates anything, so this -222 screen-center offset must not touch it.
        if dest == "essential" and not s.g1DefaultYApplied then
            s.g1DefaultYApplied = true
            if s.groups[1] then s.groups[1].posY = -222 end
        end
        -- One-time: the engine is now ON by default (it replaces the old bucket placement). Flip a
        -- profile that predates this default ON once; the user can still toggle it off afterward. Each
        -- dest carries its OWN migration flag (enabledDefaultV1 for "essential", a dest-named flag for
        -- every other dest, e.g. utilityEnabledDefaultV1) so enabling one dest's default never marks the
        -- other's done — an EXISTING profile that had only "essential" gets "utility" flipped on once too.
        local enabledFlag = (dest == "essential") and "enabledDefaultV1" or (dest .. "EnabledDefaultV1")
        if not s[enabledFlag] then
            s[enabledFlag] = true
            s.enabled = true
        end
        -- One-time UTILITY cleanup: during the early Utility builds the engine's displayed-set
        -- accumulation grabbed frames REGARDLESS of IsShown (incl. the empty-pool fallback's full-category
        -- children + cross-viewer / "Not Displayed" pool frames), polluting the universe with essential/
        -- hidden cooldowns; if the user then dragged any of those they got baked into s.assign/s.order, and
        -- an old build also PERSISTED the polluted set in s.seenDisplayed. The engine now gates accumulation
        -- on nf:IsShown() and keeps the set RUNTIME-ONLY, so it self-heals each session — but persisted
        -- contamination from those builds must be cleared once. Wipe this dest's order/assign + the dead
        -- s.seenDisplayed so Group 1 re-seeds clean (GroupOf/GroupRows default displayed -> Group 1
        -- dynamically; a legit-but-uncast cooldown is NOT lost — it reappears the moment it's shown on CD).
        -- UTILITY-ONLY: essential's data is correct and must not be reset.
        if dest == "utility" and not s.utilityReseedV1 then
            s.utilityReseedV1 = true
            s.order = {}
            s.assign = {}
            s.seenDisplayed = nil
        end
        -- Stale-profile normalization (idempotent, every load — handles switching to an OLD profile):
        -- ESSENTIAL's Group 1 is the primary SCREEN-centered block, but an old profile may carry the
        -- GROUP_TEMPLATE default anchorTo=="essential". Group 1 IS essential's anchor frame, so that
        -- self-anchors ("Cannot anchor to itself"); force "screen". (Utility's Group 1 anchors flush below
        -- Essential by design, so this is essential-only and only rewrites the self-referential value.)
        if dest == "essential" and s.groups[1] and s.groups[1].anchorTo == "essential" then
            s.groups[1].anchorTo = "screen"
        end
    end
    ns.RegisterCfgInitHook(I.CfgInit)

    -- ── Enable ─────────────────────────────────────────────────────────────────
    -- Default OFF (the OLD bucket system keeps driving the viewer until the user opts in).
    function I.Enabled() local s = Store(dest); return s and s.enabled == true or false end
    function I.SetEnabled(v) local s = Store(dest); if s then s.enabled = v and true or false end end

    -- ── Group accessors ─────────────────────────────────────────────────────────
    function I.Groups() local s = Store(dest); return s and s.groups or {} end

    function I.GroupList()
        local s = Store(dest); if not s then return {} end
        local list = {}
        for _, g in pairs(s.groups) do list[#list + 1] = g end
        table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
        return list
    end

    function I.GetGroup(id) local s = Store(dest); return s and s.groups and s.groups[id] end

    function I.NewGroup()
        local s = Store(dest); if not s then return nil end
        local id = s.nextId or 2
        s.nextId = id + 1
        local g = ns.DeepCopy(GROUP_TEMPLATE)
        g.id   = id
        g.name = "Group " .. id
        g.posX = 0
        g.posY = 0
        -- A brand-new (id>=2) group defaults to SCREEN-CENTER for every dest — only the indelible
        -- Group 1 carries the dest-specific default (utility's Group 1 sits below Essential, see
        -- MakeGroup1); extra groups are standalone blocks the user re-anchors as wanted.
        g.anchorTo = "screen"
        s.groups[id] = g
        return id
    end

    -- Delete a group (never group 1). Its cooldowns fall back to "Unused" (assign = 0).
    function I.RemoveGroup(id)
        if id == 1 then return end
        local s = Store(dest); if not s then return end
        s.groups[id] = nil
        for spellId, gid in pairs(s.assign) do
            if gid == id then s.assign[spellId] = 0 end
        end
        s.order[id] = nil
    end

    function I.GGet(id, key)
        local g = I.GetGroup(id)
        if g and g[key] ~= nil then return g[key] end
        if key == "timerThresholds" then return DEFAULT_TIMER_THRESHOLDS end
        return GROUP_TEMPLATE[key]
    end
    function I.GSet(id, key, val)
        local g = I.GetGroup(id)
        if g then g[key] = val end
    end

    -- ── Cooldown → group assignment ─────────────────────────────────────────────
    -- An EXPLICIT assignment is authoritative: 0 -> Unused; N -> group N (a group that no longer
    -- exists -> Unused). An UNASSIGNED cooldown (assign[sid] == nil) defaults DYNAMICALLY, with no
    -- stored value: if the native CDM currently DISPLAYS it (I.IsDisplayed = the viewer's frame POOL,
    -- kept fresh by the engine's ticker / viewer hook) -> Group 1; otherwise -> Unused (0). This stops
    -- a NOT-displayed cooldown from flooding Group 1. Since every unassigned cooldown in I.AllBuffs() is
    -- by definition in the pool (displayed), this puts all the displayed Essential cooldowns in Group 1
    -- by default. IsDisplayed is attached by the engine, so reference it defensively: if the cache isn't
    -- known yet (engine not loaded / first refresh pending) treat as displayed (return 1) so nothing
    -- vanishes before the first refresh — matches BuffGroups' guard.
    function I.GroupOf(spellId)
        local s = Store(dest); if not s then return 1 end
        local g = s.assign[spellId]
        if g == nil then
            -- A tracker MEMBER key is an addon-drawn frame (a string frame name); it's always
            -- placeable, so an unassigned tracker defaults to Group 1, never the not-displayed Unused
            -- flag (mirrors IsDisplayed/IsDisplayable, which the engine makes true for tracker keys).
            if I.IsTracker and I.IsTracker(spellId) then return 1 end
            if I.DisplayedKnown and I.DisplayedKnown() then
                return (I.IsDisplayed and I.IsDisplayed(spellId)) and 1 or 0
            end
            return 1
        end
        if g ~= 0 and not s.groups[g] then return 0 end
        return g
    end

    function I.SetGroup(spellId, groupId)
        local s = Store(dest); if not s then return end
        s.assign[spellId] = groupId
    end

    function I.RawAssign(spellId)
        local s = Store(dest); return s and s.assign[spellId]
    end

    -- ── Per-group ordering (EXPLICIT ROWS) ────────────────────────────────────────
    -- A group's stored order is now an ARRAY OF ROWS: order[gid] = { {sid,...}, {sid,...} }. The
    -- raw accessor returns that nested table, lazily normalizing a legacy FLAT list (order[gid]=
    -- {sid,...}, written before the multi-row migration) into a single row so a never-/half-migrated
    -- profile never errors. The Unused strip (groupId 0) also uses rows but only the UI flattens it.
    function I.RawOrder(groupId)
        local s = Store(dest); if not s then return {} end
        s.order = s.order or {}
        local o = s.order[groupId]
        if type(o) ~= "table" then o = {}; s.order[groupId] = o end
        -- Legacy flat list: first element is a spellId number -> wrap into one row IN PLACE.
        if type(o[1]) == "number" then
            local wrapped = { o }
            s.order[groupId] = wrapped
            return wrapped
        end
        return o
    end

    -- Effective max-icons-per-row for a group (the new-row auto-wrap point + the config strip cap).
    function I.MaxPerRow(groupId)
        local v = I.GGet(groupId, "maxPerRow")
        v = tonumber(v)
        if not v or v < 1 then v = GROUP_TEMPLATE.maxPerRow end
        return math.floor(v)
    end

    -- The group's members laid out in EXPLICIT ROWS, normalized to the live assigned set: each stored
    -- row is filtered to members still assigned here (in stored order), then any assigned member not
    -- yet placed is appended in NATIVE DISPLAY order (NativeOrder() first, then AllBuffs()), chunked
    -- into rows of maxPerRow. Empty trailing rows are pruned (a single empty row is allowed so an
    -- empty group still has row 1). So an UNSEEDED Group 1 yields rows of maxPerRow in native order.
    -- Returns { {sid,...}, {sid,...} }.
    function I.GroupRows(groupId)
        local assigned = {}
        for _, spellId in ipairs(I.AllBuffs()) do
            if I.GroupOf(spellId) == groupId then assigned[spellId] = true end
        end
        local rows, seen = {}, {}
        for _, srcRow in ipairs(I.RawOrder(groupId)) do
            if type(srcRow) == "table" then
                local row = {}
                for _, sid in ipairs(srcRow) do
                    if assigned[sid] and not seen[sid] then row[#row + 1] = sid; seen[sid] = true end
                end
                rows[#rows + 1] = row
            end
        end
        -- Native-display rank for unseen members: NativeOrder() (active frames, by layoutIndex) first,
        -- then AllBuffs() (the universe), lower rank = earlier. Mirrors the old GetGroupBuffs ranking.
        local rank, r = {}, 0
        local nativeOrder = I.NativeOrder and I.NativeOrder()
        if nativeOrder then
            for _, sid in ipairs(nativeOrder) do
                if rank[sid] == nil then r = r + 1; rank[sid] = r end
            end
        end
        for _, sid in ipairs(I.AllBuffs()) do
            if rank[sid] == nil then r = r + 1; rank[sid] = r end
        end
        local rest = {}
        for sid in pairs(assigned) do if not seen[sid] then rest[#rest + 1] = sid end end
        table.sort(rest, function(a, b)
            local ra, rb = rank[a] or math.huge, rank[b] or math.huge
            if ra ~= rb then return ra < rb end
            -- A member KEY is a native spellId (number) OR a tracker frame name (string); a raw
            -- `a < b` would ERROR on a mixed string/number compare. Tiebreak type-aware: numbers
            -- before strings, then within a type by value. (Both inputs are usually numbers.)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta == "number" end
            if ta == "number" then return a < b end
            return tostring(a) < tostring(b)
        end)
        -- Append the unseen members, chunking into rows of maxPerRow: fill the LAST row up to the cap,
        -- then start fresh rows. So a freshly-installed user's Group 1 chunks into rows of maxPerRow.
        local per = I.MaxPerRow(groupId)
        if #rest > 0 then
            local row = rows[#rows]
            if not row then row = {}; rows[#rows + 1] = row end
            for _, sid in ipairs(rest) do
                if #row >= per then row = {}; rows[#rows + 1] = row end
                row[#row + 1] = sid
            end
        end
        -- Prune empty trailing rows, but always keep at least one row.
        while #rows > 1 and #rows[#rows] == 0 do rows[#rows] = nil end
        if #rows == 0 then rows[1] = {} end
        return rows
    end

    -- The FLAT member list (rows flattened top-to-bottom, left-to-right). Classification / the engine's
    -- reflow / SortGroupNativeOrder consume this, so existing flat-list readers keep working.
    function I.GetGroupBuffs(groupId)
        local out = {}
        for _, row in ipairs(I.GroupRows(groupId)) do
            for _, sid in ipairs(row) do out[#out + 1] = sid end
        end
        return out
    end

    -- Append a spellId to a group's order (the END of its last row, a new row if the last is full),
    -- skipping if already present. Writes the explicit-row store directly.
    function I.AppendOrder(groupId, spellId)
        local rows = I.RawOrder(groupId)
        for _, row in ipairs(rows) do
            if type(row) == "table" then
                for _, v in ipairs(row) do if v == spellId then return end end
            end
        end
        local per = I.MaxPerRow(groupId)
        local row = rows[#rows]
        if (not row) or (#row >= per) then row = {}; rows[#rows + 1] = row end
        row[#row + 1] = spellId
    end

    -- Append a brand-new EMPTY row to a group's order and return its 1-based index. The "new row" drop
    -- target / "+" below-the-rows tile uses this; GroupRows prunes it again if it stays empty.
    function I.NewRow(groupId)
        local rows = I.RawOrder(groupId)
        rows[#rows + 1] = {}
        return #rows
    end

    -- Strip spellId out of every row of a group's stored order (in place); drop rows left empty,
    -- keeping at least one row. Used by MoveBuff before re-inserting at the destination.
    local function RemoveFromOrder(groupId, spellId)
        local rows = I.RawOrder(groupId)
        for ri = #rows, 1, -1 do
            local row = rows[ri]
            if type(row) == "table" then
                for ci = #row, 1, -1 do if row[ci] == spellId then table.remove(row, ci) end end
                if #row == 0 and #rows > 1 then table.remove(rows, ri) end
            end
        end
    end

    -- Move a cooldown to targetGroupId at (rowIndex, colIndex): the destination ROW (1-based; a value
    -- past the last row, or nil, starts a NEW row) and the 0-based slot WITHIN that row (nil = end).
    -- Drives intra-row reorder, cross-row moves and cross-group moves. Rebuilds the destination rows
    -- from the live GroupRows sequence (so committed indices match the strip's measured ones), drops
    -- the cooldown from its old group, then inserts at the resolved (row,col).
    function I.MoveBuff(spellId, targetGroupId, rowIndex, colIndex)
        local s = Store(dest); if not s then return end
        local old = I.GroupOf(spellId)
        RemoveFromOrder(old, spellId)
        s.assign[spellId] = targetGroupId
        -- Snapshot the destination's CURRENT rows (already excluding spellId after the assign + the
        -- removal above), then re-insert. GroupRows reflects the live assigned set in stored order.
        local rows = I.GroupRows(targetGroupId)
        for _, row in ipairs(rows) do
            for ci = #row, 1, -1 do if row[ci] == spellId then table.remove(row, ci) end end
        end
        local ri = rowIndex
        if not ri or ri < 1 or ri > #rows then
            rows[#rows + 1] = {}
            ri = #rows
        end
        local row = rows[ri]
        local pos = math.max(1, math.min(#row + 1, (colIndex or #row) + 1))
        table.insert(row, pos, spellId)
        -- Prune any rows left empty (except the first), then commit the explicit-row store.
        for i = #rows, 1, -1 do
            if #rows[i] == 0 and #rows > 1 then table.remove(rows, i) end
        end
        s.order[targetGroupId] = rows
    end

    -- ── Custom (cast-triggered) cooldowns ─────────────────────────────────────────
    -- custom[spellId] = { duration, name, icon }: the addon DRAWS these (a cooldown swipe started by
    -- UNIT_SPELLCAST_SUCCEEDED on spellId, running for `duration` seconds — see Core/CustomCooldowns.lua),
    -- so they need no native frame. name/icon are display hints (resolved from the spell when nil).
    -- Ported verbatim from BuffGroups, plus row-aware placement: opts.rowIndex / opts.colIndex place the
    -- new custom at a precise (row,col) via MoveBuff; otherwise it appends to the group's last row.
    function I.AddCustom(spellId, groupId, opts)
        local s = Store(dest); if not s or not spellId then return end
        opts = opts or {}
        s.custom = s.custom or {}
        s.custom[spellId] = {
            duration = tonumber(opts.duration) or 0,
            name     = opts.name,
            icon     = opts.icon,
        }
        local gid = groupId or 1
        if opts.rowIndex ~= nil or opts.colIndex ~= nil then
            I.MoveBuff(spellId, gid, opts.rowIndex, opts.colIndex)
        else
            s.assign[spellId] = gid
            I.AppendOrder(gid, spellId)
        end
    end

    function I.RemoveCustom(spellId)
        local s = Store(dest); if not s then return end
        if s.custom then s.custom[spellId] = nil end
        local gid = s.assign[spellId]
        s.assign[spellId] = nil
        if gid then
            local rows = I.RawOrder(gid)
            for _, row in ipairs(rows) do
                if type(row) == "table" then
                    for i = #row, 1, -1 do if row[i] == spellId then table.remove(row, i) end end
                end
            end
        end
        if s.iconCfg then s.iconCfg[spellId] = nil end
    end

    -- Tracker MEMBER placement: a string-keyed twin of AddCustom with NO s.custom entry. A CustomCDM
    -- icon folded into a group is a tracker member keyed by its frame name ("UnbunkUtilityCustomCDM<id>");
    -- this only records its group assignment + order slot (assign/order accept any key generically), so the
    -- engine's tracker fold picks it up on the next refresh. opts.rowIndex / opts.colIndex place it precisely
    -- via MoveBuff (math.huge -> new row / end of row); otherwise it appends to the group's last row.
    function I.AddTrackerMember(name, groupId, opts)
        local s = Store(dest); if not s or not name then return end
        opts = opts or {}
        local gid = groupId or 1
        if opts.rowIndex ~= nil or opts.colIndex ~= nil then
            I.MoveBuff(name, gid, opts.rowIndex, opts.colIndex)
        else
            s.assign[name] = gid
            I.AppendOrder(gid, name)
        end
    end

    -- Drop a tracker member's group assignment + order slot + any per-icon override (the inverse of
    -- AddTrackerMember). Called when a CustomCDM icon that was folded into a group is deleted, so no
    -- orphan string key lingers in assign/order (which would otherwise render a broken strip tile).
    function I.RemoveTrackerMember(name)
        local s = Store(dest); if not s or not name then return end
        local gid = s.assign[name]
        s.assign[name] = nil
        if gid then
            local rows = I.RawOrder(gid)
            for _, row in ipairs(rows) do
                if type(row) == "table" then
                    for i = #row, 1, -1 do if row[i] == name then table.remove(row, i) end end
                end
            end
        end
        if s.iconCfg then s.iconCfg[name] = nil end
    end

    function I.IsCustom(spellId)
        local s = Store(dest); return s and s.custom and s.custom[spellId] ~= nil or false
    end
    function I.GetCustom(spellId)
        local s = Store(dest); return s and s.custom and s.custom[spellId] or nil
    end
    function I.CustomList()
        local s = Store(dest); if not s or not s.custom then return {} end
        local out = {}
        for spellId in pairs(s.custom) do out[#out + 1] = spellId end
        return out
    end

    -- ── Per-icon overrides (the pencil editor) ────────────────────────────────────
    function I.IconGet(spellId, key)
        local s = Store(dest)
        local ic = s and s.iconCfg and s.iconCfg[spellId]
        if ic and ic[key] ~= nil then return ic[key] end
        return I.GGet(I.GroupOf(spellId), key)
    end

    function I.IconSet(spellId, key, val)
        local s = Store(dest); if not s then return end
        s.iconCfg = s.iconCfg or {}
        s.iconCfg[spellId] = s.iconCfg[spellId] or {}
        s.iconCfg[spellId][key] = val
    end

    function I.IconHasOverride(spellId, key)
        local s = Store(dest)
        local ic = s and s.iconCfg and s.iconCfg[spellId]
        if not ic then return false end
        if key ~= nil then return ic[key] ~= nil end
        -- "Any REAL override?" — the reserved markers (seed version, disabled-stash, legacy migrate flag)
        -- don't count, so a fully-inherited migrated icon isn't shown as customised (e.g. the pencil glyph).
        for k in pairs(ic) do
            if k ~= "__ovSeedV" and k ~= "__ovStash" and k ~= "__ovMigrated" then return true end
        end
        return false
    end

    function I.IconReset(spellId, key)
        local s = Store(dest); if not (s and s.iconCfg and s.iconCfg[spellId]) then return end
        if key == nil then
            s.iconCfg[spellId] = nil
        else
            s.iconCfg[spellId][key] = nil
            -- Keep the override table alive while it still carries the migration marker (an icon with all
            -- sections inherited still reads from the override store → group default, not its Free config).
            if next(s.iconCfg[spellId]) == nil then s.iconCfg[spellId] = nil end
        end
    end

    -- True once an icon (essential/utility tracker member) has been migrated to the per-icon override
    -- system: its in-CDM appearance then comes from the override store (override → group default), never
    -- its module's own "Free" config. The marker is a reserved key in the icon's override table.
    function I.IconOverrideMigrated(spellId)
        local s = Store(dest)
        local ic = s and s.iconCfg and s.iconCfg[spellId]
        -- Migrated = seeded at any version (new __ovSeedV, or the legacy __ovMigrated marker). It stays true
        -- across a default-version bump so the icon keeps rendering its override until the re-seed lands.
        return (ic and (ic.__ovSeedV ~= nil or ic.__ovMigrated == true)) or false
    end

    -- Seed an icon's per-icon override from a {key=value} table (the tracker's default override-set, mapped
    -- to the GROUP key schema), turning the override ON for those keys. Versioned: skipped once the icon is
    -- seeded at the CURRENT version; otherwise the override is WIPED and re-seeded so a changed default-set
    -- fully replaces a stale one (and the legacy full seed). Keys not in `values` inherit the group.
    function I.SeedIconOverride(spellId, values)
        local s = Store(dest); if not s or not spellId then return end
        s.iconCfg = s.iconCfg or {}
        local ver = ns.OVERRIDE_SEED_VERSION or 1
        local ic = s.iconCfg[spellId]
        if ic and ic.__ovSeedV == ver then return end
        ic = {}
        for k, v in pairs(values or {}) do
            ic[k] = (type(v) == "table") and ns.DeepCopy(v) or v
        end
        ic.__ovSeedV = ver
        s.iconCfg[spellId] = ic
    end

    -- True once the icon is seeded at the CURRENT default version (used to skip a re-seed cheaply).
    function I.IconSeededCurrent(spellId)
        local s = Store(dest)
        local ic = s and s.iconCfg and s.iconCfg[spellId]
        return (ic and ic.__ovSeedV == (ns.OVERRIDE_SEED_VERSION or 1)) or false
    end

    -- Per-section "remembered while disabled" stash (persisted on the icon's override table, under
    -- __ovStash). The cadre shows these values greyed when a section's override is OFF, and re-enabling
    -- restores them; the RENDER ignores __ovStash (a disabled section inherits the group). Survives /reload.
    function I.IconStashGet(spellId, key)
        local s = Store(dest)
        local ic = s and s.iconCfg and s.iconCfg[spellId]
        local st = ic and ic.__ovStash
        return st and st[key]
    end
    function I.IconStashSet(spellId, key, val)
        local s = Store(dest); if not s or not spellId then return end
        s.iconCfg = s.iconCfg or {}
        local ic = s.iconCfg[spellId] or {}
        ic.__ovStash = ic.__ovStash or {}
        ic.__ovStash[key] = val
        s.iconCfg[spellId] = ic
    end

    return I
end

-- Instantiate the dests. "essential" (the primary, screen-anchored block) and "utility" (anchored
-- flush below Essential; its viewer HIDES ready cooldowns, so the engine flags this instance to
-- ACCUMULATE the cooldowns seen in its pool into the tracked universe — see Engine.lua's poolAccumulates).
CDG.essential = CDG.Make("essential")
CDG.utility   = CDG.Make("utility")

-- Ownership guard: true when the NEW engine for `dest` is enabled, so the OLD CDMAnchor bucket
-- system must NOT also drive that viewer. Safe before instances exist (returns false).
function CDG.OwnsDest(dest)
    local I = CDG.instances and CDG.instances[dest]
    return (I and I.Enabled and I.Enabled()) or false
end

-- Anchor target for things that anchor TO this dest (e.g. a Buff group placed "above essential").
-- When the engine owns the dest, return its PRIMARY group's container (Group 1) — the real, resized
-- block the user sees — so anchored UIs follow ITS bounds (and adapt to the icon size) instead of the
-- native viewer husk, whose size never grew. nil when not owned / not yet laid out → caller falls back.
function CDG.AnchorFrame(dest)
    local I = CDG.instances and CDG.instances[dest]
    if not (I and I.Enabled and I.Enabled() and I.GetContainer) then return nil end
    local c = I.GetContainer(1)
    local w = c and c.GetWidth and c:GetWidth()
    if w and w > 1 then return c end   -- only once Group 1 has been laid out (has real bounds)
    return nil
end
