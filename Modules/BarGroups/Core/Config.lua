-- Modules/BarGroups/Core/Config.lua
-- Data model for the custom CDM "Bar groups". We REUSE the native BAR cooldown viewer
-- (BuffBarCooldownViewer) frames — re-sized, re-styled and re-anchored into user-defined
-- GROUPS (movable containers), exactly like the Buff-groups module does for the buff ICON
-- viewer and like the reference addon Ayije_CDM does for its bar groups. The native viewer is
-- NOT hidden; we drive its frames (so Blizzard keeps filling the bar value / name / duration).
--
-- The bar viewer shows the SAME tracked-buff set as the buff icon viewer (the CDM's
-- TrackedBuff category), just rendered as horizontal bars instead of icons — so this module's
-- buff universe (AllBuffs) is the TrackedBuff category, like Buff-groups.
--
-- Per-profile (ns.db.profile.barGroups):
--   groups[id] = a GROUP: position + grow direction + the BAR style (colour / background /
--                icon side / fill direction / height / width). Applies to every bar in it.
--   assign[spellId] = groupId   -- which group a bar belongs to:
--                                --   nil  -> Group 1 (the default, indelible group)
--                                --   0    -> "Unused" (hidden entirely, parked in config)
--                                --   N>=1 -> that group
--   order[groupId]  = { spellId, ... }  -- display + in-game order within the group
--   iconCfg[spellId] = SPARSE per-bar overrides (the pencil): the SUBSET of group bar keys
--                      a single bar may diverge on, PLUS a per-bar custom name. Anything unset
--                      inherits the bar's current GROUP, then the defaults.
-- Group 1 always exists and can't be deleted (so native bars always have a home); any group
-- (incl. 1) may hold zero bars. Group 0 ("Unused") has no group row — its bars hide.

local _, ns = ...
ns.BarGroups = ns.BarGroups or {}
local BR = ns.BarGroups

-- Max bars per group: the config strip caps a group here (Unused wraps freely). Shared by the
-- config UI and the drag-drop guard so both agree.
BR.GROUP_CAP = 12

-- ── Per-group settings (the full set; every bar in the group inherits these) ──
-- A freshly created group is GROUP_TEMPLATE + an id/name/position; Group 1 below is the same
-- template with its own seeded position. GGet falls back to GROUP_TEMPLATE for any key a saved
-- group predates (so adding a key here needs no data migration).
local GROUP_TEMPLATE = {
    -- placement
    anchorTo = "screen",       -- "essential" | "utility" | "belowPlayer" | "screen" (default: centred on screen)
    relPos   = "below",        -- side/corner of the anchor (ignored when anchorTo == "screen")
    growDir  = "DOWN",         -- bars stack vertically: "DOWN" | "UP" (only these two are exposed)
    spacing  = 0,
    staticDisplay = false,     -- false: only currently-active bars take a slot (reflow); true: every member keeps its slot
    -- bar geometry + style (the user-facing parameters)
    barWidth  = 220,           -- total row width (icon + gauge), like Ayije's barWidth
    barHeight = 20,
    barTexture = "Better Blizzard",                       -- LSM "statusbar" key (bundled in Media.lua)
    barColor  = { r = 0.2, g = 0.549, b = 1, a = 1 },     -- the filled gauge (default #338CFF, brand colour)
    bgColor   = { r = 0.102, g = 0.102, b = 0.102, a = 1 },-- the bar background (default #1A1A1A)
    iconPosition  = "LEFT",    -- "LEFT" | "RIGHT" | "HIDDEN" — the spell icon's side of the bar
    fillDirection = "RIGHT",   -- "LEFT" | "RIGHT" — side the gauge is anchored on (SetReverseFill)
    invertFill = false,        -- true: the gauge DRAINS over time (mirror the native value) instead of filling up
    iconGap   = 1,             -- px gap between the icon and the gauge
    -- text: the native name + duration are kept (Blizzard fills them); only their visibility is
    -- a group flag here, and the per-bar custom-name OVERRIDE lives in iconCfg (see below).
    showName     = true,
    showDuration = true,
    -- runtime
    unlocked = false,
}
BR.GROUP_TEMPLATE = GROUP_TEMPLATE

-- Group 1: the indelible default. Same template + its own id/name/position.
local DEFAULT_GROUP1 = ns.DeepCopy(GROUP_TEMPLATE)
DEFAULT_GROUP1.id   = 1
DEFAULT_GROUP1.name = "Group 1"
DEFAULT_GROUP1.posX = 350   -- offset from screen centre (default anchor = screen)
DEFAULT_GROUP1.posY = 0

local DEFAULTS = {
    enabled = true,
    nextId  = 2,
    groups  = { [1] = nil },  -- seeded below (deep-copied) so the shared table isn't mutated
    assign  = {},
    order   = {},             -- order[groupId] = { spellId, ... } (display + in-game order)
    iconCfg = {},             -- iconCfg[spellId] = sparse per-bar overrides (the pencil)
}

local function Store()
    if not (ns.db and ns.db.profile) then return nil end
    return ns.db.profile.barGroups
end
BR.Store = Store

function BR.CfgInit()
    if not ns.db then return end
    ns.db.profile.barGroups = ns.db.profile.barGroups or {}
    local s = ns.db.profile.barGroups
    ns.MergeDefaults(s, DEFAULTS)
    -- Group 1 is indelible: (re)seed it if missing, but never overwrite a saved one.
    s.groups = s.groups or {}
    if not s.groups[1] then s.groups[1] = ns.DeepCopy(DEFAULT_GROUP1) end
    -- Backfill every group with any newly-added GROUP_TEMPLATE key (no per-key migration).
    for _, g in pairs(s.groups) do ns.MergeDefaults(g, GROUP_TEMPLATE) end
    if not s.nextId or s.nextId < 2 then s.nextId = 2 end
    -- One-shot: apply the revised bar-style defaults (Better Blizzard texture, #6699E6 / #1A1A1A
    -- colours, 220x20 size) to EXISTING groups, which predate these defaults and would otherwise
    -- keep the old values (MergeDefaults only fills MISSING keys — barTexture is new so it backfills,
    -- but the colours + size already exist). Sets only these keys.
    if not s.barStyleDefaultsV1 then
        s.barStyleDefaultsV1 = true
        for _, g in pairs(s.groups) do
            g.barTexture = "Better Blizzard"
            g.barColor   = { r = 0.2, g = 0.549, b = 1, a = 1 }
            g.bgColor    = { r = 0.102, g = 0.102, b = 0.102, a = 1 }
            g.barWidth   = 220
            g.barHeight  = 20
        end
    end
    -- One-shot: default the placement to screen-centred, X = 350. Existing groups predate these
    -- defaults; MergeDefaults won't change an already-set anchorTo/posX, so force them once. Isolated
    -- from the style one-shot above so it runs regardless of that flag's state.
    if not s.anchorScreenDefaultV1 then
        s.anchorScreenDefaultV1 = true
        for _, g in pairs(s.groups) do g.anchorTo = "screen"; g.posX = 350 end
    end
    -- One-shot: fill + spacing defaults — gauge anchored RIGHT, NOT inverted, no spacing between bars.
    -- These keys may already exist on saved groups (predating these defaults), so MergeDefaults won't
    -- change them — force them once.
    if not s.fillDefaultsV1 then
        s.fillDefaultsV1 = true
        for _, g in pairs(s.groups) do g.fillDirection = "RIGHT"; g.invertFill = false; g.spacing = 0 end
    end
    -- The native bar order isn't readable until the viewer lays out its pool (after its first
    -- layout); flag the one-time native-order seed and let the engine run it once the pool is up.
    if not s.nativeOrderV1 then s.nativeOrderPending = true end
end
ns.RegisterCfgInitHook(BR.CfgInit)

-- ── Style version (engine restyle gate) ──────────────────────────────────────────
-- A monotonic counter bumped on EVERY write that can change a bar's resolved style (the pencil
-- per-bar overrides + the group settings). The engine stamps each native frame with the version it
-- was last styled at, so RefreshLayout re-runs the (cheap but non-trivial) StyleBarFrame only when
-- the config actually changed (or Blizzard re-filled the bar, tracked separately by _uuBarStyled) —
-- not on every aura tick. Note: not all bumped keys are visual (e.g. spacing/growDir), but
-- over-bumping only costs one extra restyle, never a stale style.
local styleVersion = 1
function BR.StyleVersion() return styleVersion end
local function BumpStyleVersion() styleVersion = styleVersion + 1 end

-- ── Enable ─────────────────────────────────────────────────────────────────────
function BR.Enabled()
    -- In engine mode the standalone CDM engine HOSTS the native bar frames (adopts them out of the masked
    -- BuffBarCooldownViewer), so BarGroups must cede: return false here and every driver early-outs +
    -- RefreshLayout self-routes to HideAll (un-pins the bars for the engine to adopt). Mirrors BG.Enabled().
    if ns.CDMMode and ns.CDMMode.IsEngine and ns.CDMMode.IsEngine() then return false end
    local s = Store(); return not s or s.enabled ~= false
end
function BR.SetEnabled(v) local s = Store(); if s then s.enabled = v and true or false end end

-- ── Group accessors ─────────────────────────────────────────────────────────────
function BR.Groups() local s = Store(); return s and s.groups or {} end

-- Groups as an ordered array: Group 1 first, then created groups by ascending id.
function BR.GroupList()
    local s = Store(); if not s then return {} end
    local list = {}
    for _, g in pairs(s.groups) do list[#list + 1] = g end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return list
end

function BR.GetGroup(id) local s = Store(); return s and s.groups and s.groups[id] end

function BR.NewGroup()
    local s = Store(); if not s then return nil end
    local id = s.nextId or 2
    s.nextId = id + 1
    local g = ns.DeepCopy(GROUP_TEMPLATE)
    g.id   = id
    g.name = "Group " .. id
    g.posX = 0
    g.posY = 0   -- default at the anchor (relPos side); drag to reposition a new group
    s.groups[id] = g
    return id
end

-- Delete a group (never group 1). Its bars fall back to "Unused" (assign = 0).
function BR.RemoveGroup(id)
    if id == 1 then return end
    local s = Store(); if not s then return end
    s.groups[id] = nil
    for spellId, gid in pairs(s.assign) do
        if gid == id then s.assign[spellId] = 0 end
    end
    s.order[id] = nil
end

-- Resolve a group key: the saved group value, else the template default.
function BR.GGet(id, key)
    local g = BR.GetGroup(id)
    if g and g[key] ~= nil then return g[key] end
    return GROUP_TEMPLATE[key]
end
function BR.GSet(id, key, val)
    local g = BR.GetGroup(id)
    if g then g[key] = val; BumpStyleVersion() end
end

-- ── Bar → group assignment ──────────────────────────────────────────────────────
-- An EXPLICIT assignment is authoritative: 0 -> Unused; N -> group N (a group that no longer
-- exists -> Unused). An UNASSIGNED bar (assign[sid] == nil) defaults DYNAMICALLY, with no
-- stored value: if the native CDM currently DISPLAYS it as a bar (BR.IsDisplayed, kept fresh by
-- the ticker) -> Group 1; otherwise -> Unused (0). So a displayed bar is never stranded in
-- Unused and a not-displayed one never floods Group 1 — both self-heal as the displayed set
-- changes (EditMode "Tracked Buffs" edits, spec change).
function BR.GroupOf(spellId)
    local s = Store(); if not s then return 1 end
    local g = s.assign[spellId]
    if g == nil then
        if BR.IsDisplayed then return BR.IsDisplayed(spellId) and 1 or 0 end
        return 1
    end
    if g ~= 0 and not s.groups[g] then return 0 end
    return g
end

function BR.SetGroup(spellId, groupId)
    local s = Store(); if not s then return end
    s.assign[spellId] = groupId
    BumpStyleVersion()  -- a bar's resolved style inherits its group, so a move can change it
end

-- Raw assignment (nil = never classified yet); the engine's default seed uses this.
function BR.RawAssign(spellId)
    local s = Store(); return s and s.assign[spellId]
end

-- ── Per-group ordering ─────────────────────────────────────────────────────────
function BR.GroupOrder(groupId)
    local s = Store(); if not s then return {} end
    s.order = s.order or {}
    s.order[groupId] = s.order[groupId] or {}
    return s.order[groupId]
end

-- Append a bar to a group's order if not already present (preserves discovery/CDM order).
function BR.AppendOrder(groupId, spellId)
    local o = BR.GroupOrder(groupId)
    for _, v in ipairs(o) do if v == spellId then return end end
    o[#o + 1] = spellId
end

-- Move a bar to targetGroupId, inserting at insertIdx (0-based slot among the existing
-- members). Drives both intra-group reorder and cross-group moves. Mirrors BG.MoveBuff.
function BR.MoveBuff(spellId, targetGroupId, insertIdx)
    local s = Store(); if not s then return end
    local old = BR.GroupOf(spellId)
    local oo = BR.GroupOrder(old)
    for i = #oo, 1, -1 do if oo[i] == spellId then table.remove(oo, i) end end
    s.assign[spellId] = targetGroupId
    local vis = BR.GetGroupBuffs(targetGroupId)
    for i = #vis, 1, -1 do if vis[i] == spellId then table.remove(vis, i) end end
    local pos = math.max(1, math.min(#vis + 1, (insertIdx or #vis) + 1))
    table.insert(vis, pos, spellId)
    s.order[targetGroupId] = vis
    BumpStyleVersion()  -- moved across groups -> resolved style may change (group inheritance)
end

-- Bars assigned to a group (groupId 0 = Unused), in saved order; any assigned bar not yet in
-- the order is appended (stable by spellId) so nothing is lost.
function BR.GetGroupBuffs(groupId)
    local assigned = {}
    for _, spellId in ipairs(BR.AllBuffs()) do
        if BR.GroupOf(spellId) == groupId then assigned[spellId] = true end
    end
    local out, seen = {}, {}
    for _, sid in ipairs(BR.GroupOrder(groupId)) do
        if assigned[sid] and not seen[sid] then out[#out + 1] = sid; seen[sid] = true end
    end
    local rest = {}
    for sid in pairs(assigned) do if not seen[sid] then rest[#rest + 1] = sid end end
    if #rest > 0 then
        -- Order the not-yet-saved members by the NATIVE on-screen order (the EditMode arrangement), matching
        -- the RefreshTracked seed + BuffGroups. So a fresh / just-reset profile lists them in native order, not
        -- by raw spellId. (NativeOrder is only computed when there's actually something to place.)
        local rank, r = {}, 0
        for _, sid in ipairs(BR.NativeOrder() or {}) do if rank[sid] == nil then r = r + 1; rank[sid] = r end end
        table.sort(rest, function(a, b)
            local ra, rb = rank[a] or math.huge, rank[b] or math.huge
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        for _, sid in ipairs(rest) do out[#out + 1] = sid end
    end
    return out
end

-- ── Per-bar overrides (the pencil editor) ────────────────────────────────────────
-- iconCfg[spellId] holds SPARSE overrides for the SUBSET of group bar keys a single bar may
-- diverge on, PLUS the per-bar custom name (nameOverride gates customName). IconGet resolves:
-- per-bar override -> the bar's current GROUP -> default. Because it falls through to the group,
-- IconGet is safe to call for ANY group key (the engine reads an effective bar config through
-- it); the editor only ever WRITES the subset below.
local ICON_OVERRIDE_KEYS = {
    barWidth = true, barHeight = true,
    barTexture = true, barColor = true, bgColor = true,
    iconPosition = true, fillDirection = true, invertFill = true,
    nameOverride = true, customName = true,
}
BR.ICON_OVERRIDE_KEYS = ICON_OVERRIDE_KEYS

function BR.IconGet(spellId, key)
    local s = Store()
    local ic = s and s.iconCfg and s.iconCfg[spellId]
    if ic and ic[key] ~= nil then return ic[key] end
    return BR.GGet(BR.GroupOf(spellId), key)
end

function BR.IconSet(spellId, key, val)
    local s = Store(); if not s then return end
    s.iconCfg = s.iconCfg or {}
    s.iconCfg[spellId] = s.iconCfg[spellId] or {}
    s.iconCfg[spellId][key] = val
    BumpStyleVersion()
end

-- True if the bar has a per-bar override. With no `key`, reports ANY override (so the strip can
-- tint a diverging bar's pencil). With a `key`, reports whether THAT specific key is overridden
-- (so the editor's per-section "Override group settings" checkbox reflects the real state).
function BR.IconHasOverride(spellId, key)
    local s = Store()
    local ic = s and s.iconCfg and s.iconCfg[spellId]
    if not ic then return false end
    if key ~= nil then return ic[key] ~= nil end
    return next(ic) ~= nil
end

-- Drop a single override key (key given) or all of them (key nil) → back to group/defaults.
function BR.IconReset(spellId, key)
    local s = Store(); if not (s and s.iconCfg and s.iconCfg[spellId]) then return end
    if key == nil then
        s.iconCfg[spellId] = nil
    else
        s.iconCfg[spellId][key] = nil
        if next(s.iconCfg[spellId]) == nil then s.iconCfg[spellId] = nil end
    end
    BumpStyleVersion()
end
