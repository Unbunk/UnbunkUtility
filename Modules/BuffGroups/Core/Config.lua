-- Modules/BuffGroups/Core/Config.lua
-- Data model for the custom CDM "Buff groups". We REUSE the native Buff cooldown viewer
-- (BuffIconCooldownViewer) frames — re-sized, re-styled and re-anchored into user-defined
-- GROUPS (movable containers), exactly like the reference addon Ayije_CDM. The native
-- viewer is NOT hidden; we drive its frames. Custom (cast-triggered) buffs are the one
-- exception: those are drawn by the addon and packed alongside the natives.
--
-- Per-profile (ns.db.profile.buffGroups):
--   groups[id] = a GROUP: position + grow direction + geometry + border/glow + the
--                native text restyle (timer / title / stacks). Applies to every icon in it.
--   assign[spellId] = groupId   -- which group a buff belongs to:
--                                --   nil  -> Group 1 (the default, indelible group)
--                                --   0    -> "Unused" (hidden entirely, parked in config)
--                                --   N>=1 -> that group
--   order[groupId]  = { spellId, ... }  -- display + in-game order within the group
--   custom[spellId] = { duration, name, icon }  -- cast-triggered buffs the user "+"-added
--   iconCfg[spellId] = SPARSE per-icon overrides (the pencil): a SUBSET of the group keys
--                      (border*, iconW/H, showTimer/Title/Stack, glow*). Anything unset
--                      inherits the buff's current GROUP, then the defaults.
-- Group 1 always exists and can't be deleted (so native icons always have a home); any
-- group (incl. 1) may hold zero icons. Group 0 ("Unused") has no group row — its icons hide.

local _, ns = ...
ns.BuffGroups = ns.BuffGroups or {}
local BG = ns.BuffGroups

-- Max icons per group: the config strip caps a group here (Unused wraps freely) and the
-- default seeding fills Group 1 up to this before overflowing to Unused. Shared by the
-- engine seed walk and the config UI so both agree.
BG.GROUP_CAP = 12

-- ── Per-group settings (the full set; every icon in the group inherits these) ──
-- A freshly created group is GROUP_TEMPLATE + an id/name/position; Group 1 below is the
-- same template with its own seeded position. GGet falls back to GROUP_TEMPLATE for any
-- key a saved group predates (so adding a key here needs no data migration).
local GROUP_TEMPLATE = {
    -- placement
    anchorTo = "resbar:last",  -- "essential" | "utility" | "belowPlayer" | "screen" | "resbar:<i>" | "resbar:last"
    relPos   = "above",        -- side/corner of the anchor: above|below|left|right|topleft|topright|bottomleft|bottomright
    growDir  = "CENTER_H",     -- "RIGHT" | "LEFT" | "UP" | "DOWN" | "CENTER_H" | "CENTER_V"
    spacing  = 0,
    staticDisplay = false,     -- false: only currently-active buffs take a slot (reflow); true: every member keeps its slot
    -- geometry
    iconW = 36, iconH = 36,
    -- placeholder (PER-ICON only — the pencil editor toggles it via IconSet; no group panel
    -- exposes it). When ON, the icon ALWAYS reserves its slot: its native frame shows when the
    -- buff is active, else a dimmed desaturated placeholder fills the slot. Off by default so the
    -- new key backfills harmlessly via MergeDefaults (no migration). IconGet falls back to here.
    placeholder = false,
    -- border (our own child frame, the native DebuffBorder is hidden)
    borderEnabled = true,
    borderColor   = { r = 0, g = 0, b = 0, a = 1 },
    borderSize    = 1,
    -- "native border": the debuff dispel-type colour carried on OUR inset border (replaces Masque's
    -- outsetting DebuffBorderMBB). Its own toggle + thickness, independent of the regular border above.
    showNativeBorder = true,
    nativeBorderSize = 3,
    -- glow (LibCustomGlow-style highlight around an active icon); colour defaults to F5FF00 even off
    glowEnabled = false,
    glowColor   = { r = 0.96, g = 1, b = 0, a = 1 },   -- F5FF00
    -- timer / countdown text (restyle of the native Cooldown countdown)
    showTimer     = true,
    timerFontKey  = "Fira Mono", timerFontPath = nil, timerFontSize = 12, timerOutline = "OUTLINE",
    timerColor    = { r = 1, g = 1, b = 1, a = 1 },
    timerPos      = "CENTER", timerOffX = 0, timerOffY = 0,
    -- time thresholds: as the countdown drops, scale + recolour it from the most-urgent
    -- matching tier. This scalar backfills safely via MergeDefaults; the LIST itself is
    -- seeded separately (see DEFAULT_TIMER_THRESHOLDS / CfgInit) so MergeDefaults never
    -- re-adds tiers the user deleted. Defaults OFF (the two tiers stay defined, just inactive
    -- until the user opts in); existing groups are force-set false once by classifyResetV8.
    timerThresholdsEnabled = false,
    -- title text (a free label over the icon)
    showTitle     = false, titleText = "",
    titleFontKey  = "Fira Mono", titleFontPath = nil, titleFontSize = 12, titleOutline = "OUTLINE",
    titleColor    = { r = 1, g = 1, b = 1, a = 1 },
    titlePos      = "TOP", titleOffX = 0, titleOffY = 0,
    -- stack count text (native Applications restyle)
    showStack     = true, showAtZero = false,
    stackFontKey  = "Fira Mono", stackFontPath = nil, stackFontSize = 8, stackOutline = "OUTLINE",
    stackColor    = { r = 1, g = 1, b = 1, a = 1 },
    stackPos      = "BOTTOMRIGHT", stackOffX = 0, stackOffY = 0,
    -- sound alert (PER-ICON only — the pencil editor writes these via IconSet; no group
    -- panel exposes them, it's not a group-inherited visual). Both off by default so the
    -- new keys backfill harmlessly via MergeDefaults (no migration). The sound keys are
    -- LSM media names (registered in Media/Media.lua), resolved to a file at play time.
    soundStartEnabled = false, soundStartSound = nil, soundStartPath = nil,   -- nil sound key = "None"
    soundStopEnabled  = false, soundStopSound  = nil, soundStopPath  = nil,   -- (custom buffs inherit this via IconGet)
    -- runtime
    unlocked      = false,
}
BG.GROUP_TEMPLATE = GROUP_TEMPLATE

-- Default time-threshold tiers (yellow @15s, red @5s). `time` = remaining seconds at/below
-- which the tier applies; `size` = MULTIPLIER of the base timerFontSize; `color` = countdown
-- colour. Kept OUT of GROUP_TEMPLATE on purpose: MergeDefaults recurses into tables and would
-- re-add tiers a user deleted. Each group's list is seeded once in CfgInit (only when absent),
-- and GGet/IconGet fall back to THIS table for "timerThresholds" (which is not a template key).
-- DeepCopy-d into every group so groups never share the table.
local DEFAULT_TIMER_THRESHOLDS = {
    { time = 15, size = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { time = 5,  size = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
BG.DEFAULT_TIMER_THRESHOLDS = DEFAULT_TIMER_THRESHOLDS

-- Group 1: the indelible default. Same template + its own id/name/position.
local DEFAULT_GROUP1 = ns.DeepCopy(GROUP_TEMPLATE)
DEFAULT_GROUP1.id   = 1
DEFAULT_GROUP1.name = "Group 1"
DEFAULT_GROUP1.posX = 0
DEFAULT_GROUP1.posY = 0   -- flush at the anchor (default anchor = last bar)

local DEFAULTS = {
    enabled = true,
    nextId  = 2,
    groups  = { [1] = nil },  -- seeded below (deep-copied) so the shared table isn't mutated
    assign  = {},
    custom  = {},             -- custom[spellId] = { duration, name, icon }
    order   = {},             -- order[groupId] = { spellId, ... } (display + in-game order)
    iconCfg = {},             -- iconCfg[spellId] = sparse per-icon overrides (the pencil)
}

local function Store()
    if not (ns.db and ns.db.profile) then return nil end
    return ns.db.profile.buffGroups
end
BG.Store = Store

function BG.CfgInit()
    if not ns.db then return end
    ns.db.profile.buffGroups = ns.db.profile.buffGroups or {}
    local s = ns.db.profile.buffGroups
    ns.MergeDefaults(s, DEFAULTS)
    -- Group 1 is indelible: (re)seed it if missing, but never overwrite a saved one.
    s.groups = s.groups or {}
    if not s.groups[1] then s.groups[1] = ns.DeepCopy(DEFAULT_GROUP1) end
    -- Backfill every group with any newly-added GROUP_TEMPLATE key (no per-key migration).
    for _, g in pairs(s.groups) do ns.MergeDefaults(g, GROUP_TEMPLATE) end
    -- Seed the time-threshold LIST per group only when absent. Kept out of MergeDefaults
    -- (which would re-add deleted tiers); DeepCopy so no two groups share the table.
    for _, g in pairs(s.groups) do
        if g.timerThresholds == nil then g.timerThresholds = ns.DeepCopy(DEFAULT_TIMER_THRESHOLDS) end
    end
    if not s.nextId or s.nextId < 2 then s.nextId = 2 end
    -- One-shot reset: the model changed shape for the native-reuse rewrite — buffs are now
    -- keyed by the native FRAME spell id (the displayed set), customs carry a definition
    -- table (was a boolean), and per-icon overrides moved buffCfg -> iconCfg with a smaller
    -- subset of keys. Old assignment/order/customs/overrides are stale; clear them once
    -- (group definitions are kept and backfilled above). Bumped from the prior reset key.
    if not s.classifyResetV4 then
        s.classifyResetV4 = true
        s.assign  = {}
        s.order   = {}
        s.custom  = {}
        s.iconCfg = {}
    end
    -- One-shot reseed: the displayed / not-displayed split had been read from the wrong source
    -- (the category-set flag returns far more than the user shows; the real displayed set is the
    -- native viewer's frame pool). That polluted the auto-seeded assignments/order, leaving
    -- "Not Displayed" buffs stuck in Group 1 and some displayed buffs stuck in Unused. Clear
    -- assignments + order ONCE so the corrected pool-based seeding rebuilds the default placement
    -- cleanly. User custom buffs and per-icon overrides are kept (still keyed by spell id).
    if not s.classifyResetV5 then
        s.classifyResetV5 = true
        s.assign = {}
        s.order  = {}
    end
    -- One-shot: apply the revised default placement/geometry (Essential + Above + centred + 36px +
    -- the smaller timer/stack fonts) to EXISTING groups, which predate these defaults and would
    -- otherwise keep the old values (MergeDefaults only fills MISSING keys). Sets only these keys, so
    -- border / glow / title and per-icon overrides are left intact.
    if not s.classifyResetV6 then
        s.classifyResetV6 = true
        for _, g in pairs(s.groups) do
            g.anchorTo = "essential"
            g.relPos   = "above"
            g.growDir  = "CENTER_H"
            g.spacing  = 1
            g.iconW    = 36
            g.iconH    = 36
            g.timerFontSize = 15
            g.stackFontSize = 15
            g.staticDisplay = false
            g.posX = 0
            g.posY = 0
        end
    end
    -- One-time: the default group spacing is now 0 (icons flush). Apply to EXISTING groups once (the V6
    -- reset above set the old spacing=1; MergeDefaults won't change a saved value). A later manual change sticks.
    if not s.spacingZeroV1 then
        s.spacingZeroV1 = true
        for _, g in pairs(s.groups) do g.spacing = 0 end
    end
    -- One-shot: smaller default timer (12) / stacks (8) fonts and the stacks offset (2,-2), applied
    -- to existing groups (changed defaults don't retro-fill). Timer thresholds are NEW keys, so they
    -- backfill onto existing groups via MergeDefaults above — no migration needed for those.
    if not s.classifyResetV7 then
        s.classifyResetV7 = true
        for _, g in pairs(s.groups) do
            g.timerFontSize = 12
            g.stackFontSize = 8
            g.stackOffX = 2
            g.stackOffY = -2
        end
    end
    -- One-time: stack/charge count offsets default to 0 (centred on stackPos). Apply to EXISTING groups
    -- once (the V7 reset above set 2/-2); a later manual change sticks.
    if not s.stackOffsetZeroV1 then
        s.stackOffsetZeroV1 = true
        for _, g in pairs(s.groups) do g.stackOffX = 0; g.stackOffY = 0 end
    end
    -- One-shot: time thresholds now default OFF. The scalar backfilled onto existing groups as
    -- TRUE (via MergeDefaults, when its default was true) and a changed default won't retro-apply,
    -- so force it false ONCE on every existing group. The threshold LIST/tiers are left intact —
    -- only the enable flag flips; per-icon overrides inherit the group via IconGet (no migration).
    if not s.classifyResetV8 then
        s.classifyResetV8 = true
        for _, g in pairs(s.groups) do
            g.timerThresholdsEnabled = false
        end
    end
    -- One-shot: default the buff start/stop sounds to "None" (nil key) with their enable checkboxes
    -- unchecked, on every existing group (the old default seeded a trinket sound via MergeDefaults).
    -- Native + custom buff icons inherit this via IconGet; explicit per-icon sound overrides are kept.
    if not s.classifyResetV9 then
        s.classifyResetV9 = true
        for _, g in pairs(s.groups) do
            g.soundStartEnabled = false
            g.soundStartSound   = nil
            g.soundStartPath    = nil
            g.soundStopEnabled  = false
            g.soundStopSound    = nil
            g.soundStopPath     = nil
        end
    end
    -- One-shot: glow now defaults ON. The scalar default (glowEnabled) changed, which won't retro-apply
    -- to existing groups, so flip it true ONCE on every existing group (per-icon overrides still inherit
    -- via IconGet; an icon that explicitly overrode glow keeps its own value). Mirrors the V8 flag flip.
    if not s.classifyGlowV11 then
        s.classifyGlowV11 = true
        for _, g in pairs(s.groups) do
            g.glowEnabled = true
        end
    end
    -- One-shot: glow now defaults OFF again (the V11 flip to ON is reversed). The changed scalar
    -- default won't retro-apply to existing groups, so flip it false ONCE on every existing group.
    -- Per-icon overrides keep their own value (iconCfg untouched); a group's icons that inherit then
    -- re-read false via IconGet — so "Show glow" is unchecked by default in both the group settings
    -- and the per-icon override editor.
    if not s.classifyGlowOffV12 then
        s.classifyGlowOffV12 = true
        for _, g in pairs(s.groups) do
            g.glowEnabled = false
        end
    end
    -- One-shot: Group 1's default Y is now 0 (flush at the anchor). A NEW flag (V2) re-runs this on profiles
    -- that took the earlier posY=2 default (g1DefaultYV1), so Group 1 sits at the anchor by default again.
    if not s.g1DefaultYV2 then
        s.g1DefaultYV2 = true
        if s.groups[1] then s.groups[1].posY = 0 end
    end
    -- One-shot: re-sort every EXISTING group's saved order so its NATIVE buffs follow the native
    -- on-screen order (the EditMode "Tracked Buffs" arrangement, read via BG.NativeOrder), with the
    -- CUSTOM buffs kept in their current relative order AFTER the natives. Earlier seeds ordered the
    -- natives by the category-set, which is NOT the on-screen order. This only REORDERS within each
    -- group (no buff moves between groups, none added/removed). The native order isn't readable yet
    -- at CfgInit (the viewer's pool fills after its first layout), so the FLAG flips here and the
    -- engine runs BG.MigrateNativeOrder once the pool is ready (then clears classifyNativeOrderV10).
    if not s.classifyNativeOrderV10 then
        s.classifyNativeOrderPending = true
    end
    -- One-shot: clear the polluted STICKY Unused assignments. The old seed wrote assign[sid] = 0
    -- for every buff not in the viewer's pool at a single instant — but the pool fills incrementally
    -- after the first layout, so procs (Brain Freeze / Fingers of Frost, etc.) whose frame hadn't
    -- loaded yet got parked in Unused permanently. GroupOf now defaults UNASSIGNED buffs dynamically
    -- from the live displayed set, so wiping these zero-assignments lets the wrongly-parked displayed
    -- buffs re-derive to Group 1 and the genuinely not-displayed ones re-derive to Unused — without
    -- storing anything. Preserve every NON-zero (manual) assignment; a user can still park a displayed
    -- buff in Unused with a drag (explicit 0), which GroupOf keeps respecting. Also wipe order[0]
    -- (Unused has no on-screen order; it was only ever written by the old seed).
    if not s.classifyResetV11 then
        s.classifyResetV11 = true
        s.assign = s.assign or {}
        for sid, gid in pairs(s.assign) do
            if gid == 0 then s.assign[sid] = nil end
        end
        if s.order then s.order[0] = nil end
    end
    -- One-shot: "Buffs" now default-anchor to the LAST class-resource bar (buff group sits under the resource
    -- bars). Flip groups still on the OLD default ("essential", set by the V6 reset) to "resbar:last"; groups
    -- the user set to anything else (utility / belowPlayer / screen) are preserved. A spec with no resource
    -- bars resolves the anchor to Essential as a graceful fallback (see ContainerAnchor / Layout).
    if not s.buffAnchorLastBarV1 then
        s.buffAnchorLastBarV1 = true
        for _, g in pairs(s.groups) do
            if (g.anchorTo or "essential") == "essential" then g.anchorTo = "resbar:last" end
        end
    end
end
ns.RegisterCfgInitHook(BG.CfgInit)

-- ── Enable ─────────────────────────────────────────────────────────────────────
-- Level 2: the standalone CDM engine (ns.CDMMode "engine") masks BuffIconCooldownViewer and draws its own
-- TrackedBuff group, so report DISABLED in engine mode — every driver here (the 0.2s RefreshLayout ticker,
-- UNIT_AURA, the native-viewer relayout hook) gates on Enabled(), so this stops BuffGroups re-styling the
-- (masked) native buff frames and fighting the engine. Flips back the instant the user returns to native
-- (the always-running ticker re-pins within a pass; the mode-switch StyleEpoch bump busts its early-out).
function BG.Enabled()
    if ns.CDMMode and ns.CDMMode.IsEngine and ns.CDMMode.IsEngine() then return false end
    local s = Store(); return not s or s.enabled ~= false
end
function BG.SetEnabled(v) local s = Store(); if s then s.enabled = v and true or false end end

-- ── Group accessors ─────────────────────────────────────────────────────────────
function BG.Groups() local s = Store(); return s and s.groups or {} end

-- Groups as an ordered array: Group 1 first, then created groups by ascending id.
function BG.GroupList()
    local s = Store(); if not s then return {} end
    local list = {}
    for _, g in pairs(s.groups) do list[#list + 1] = g end
    table.sort(list, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return list
end

function BG.GetGroup(id) local s = Store(); return s and s.groups and s.groups[id] end

function BG.NewGroup()
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

-- Delete a group (never group 1). Its buffs fall back to "Unused" (assign = 0).
function BG.RemoveGroup(id)
    if id == 1 then return end
    local s = Store(); if not s then return end
    s.groups[id] = nil
    for spellId, gid in pairs(s.assign) do
        if gid == id then s.assign[spellId] = 0 end
    end
    s.order[id] = nil
end

-- Resolve a group key: the saved group value, else the template default. The threshold
-- LIST is not a template key (it's seeded separately), so it falls back to the shared
-- DEFAULT_TIMER_THRESHOLDS — callers must treat the returned list as read-only / clone it
-- before editing (the engine reads it; the UI clones on write).
function BG.GGet(id, key)
    local g = BG.GetGroup(id)
    if g and g[key] ~= nil then return g[key] end
    if key == "timerThresholds" then return DEFAULT_TIMER_THRESHOLDS end
    return GROUP_TEMPLATE[key]
end
function BG.GSet(id, key, val)
    local g = BG.GetGroup(id)
    if g then g[key] = val end
end

-- ── Buff → group assignment ───────────────────────────────────────────────────
-- An EXPLICIT assignment is authoritative: 0 -> Unused; N -> group N (a group that no longer
-- exists -> Unused). An UNASSIGNED buff (assign[sid] == nil) defaults DYNAMICALLY, with no
-- stored value: if the native CDM currently DISPLAYS it (BG.IsDisplayed, kept fresh by the
-- 0.2s ticker's RefreshDisplayedCache) -> Group 1; otherwise -> Unused (0). So a displayed
-- buff is never stranded in Unused and a not-displayed one never floods Group 1 — both
-- self-heal as the displayed set changes (EditMode "Tracked Buffs" edits, spec change).
-- Custom buffs always carry an explicit assign (AddCustom), so this default never sees them.
function BG.GroupOf(spellId)
    local s = Store(); if not s then return 1 end
    local g = s.assign[spellId]
    if g == nil then
        -- Dynamic default. Guard: if IsDisplayed is unavailable (engine not loaded yet),
        -- fall back to the old default of Group 1.
        if BG.IsDisplayed then return BG.IsDisplayed(spellId) and 1 or 0 end
        return 1
    end
    if g ~= 0 and not s.groups[g] then return 0 end
    return g
end

function BG.SetGroup(spellId, groupId)
    local s = Store(); if not s then return end
    s.assign[spellId] = groupId
end

-- Raw assignment (nil = never classified yet); the engine's default classifier uses this.
function BG.RawAssign(spellId)
    local s = Store(); return s and s.assign[spellId]
end

-- ── Per-group ordering ─────────────────────────────────────────────────────────
function BG.GroupOrder(groupId)
    local s = Store(); if not s then return {} end
    s.order = s.order or {}
    s.order[groupId] = s.order[groupId] or {}
    return s.order[groupId]
end

-- Append a buff to a group's order if not already present (preserves discovery/CDM order).
function BG.AppendOrder(groupId, spellId)
    local o = BG.GroupOrder(groupId)
    for _, v in ipairs(o) do if v == spellId then return end end
    o[#o + 1] = spellId
end

-- Move a buff to targetGroupId, inserting at insertIdx (0-based slot among the existing
-- members). Drives both intra-group reorder and cross-group moves.
function BG.MoveBuff(spellId, targetGroupId, insertIdx)
    local s = Store(); if not s then return end
    -- Drop from the source group's order.
    local old = BG.GroupOf(spellId)
    local oo = BG.GroupOrder(old)
    for i = #oo, 1, -1 do if oo[i] == spellId then table.remove(oo, i) end end
    -- Assign first, so GetGroupBuffs(targetGroupId) below includes spellId in the SAME index
    -- space the config strip measured insertIdx against (the visible, filtered list).
    s.assign[spellId] = targetGroupId
    -- Rebuild the target order FROM that visible sequence: the committed index space then
    -- equals slotAt's (which counts visible tiles), so the icon lands exactly where the gap
    -- opened. Also collapses order[] to the displayed set.
    local vis = BG.GetGroupBuffs(targetGroupId)
    for i = #vis, 1, -1 do if vis[i] == spellId then table.remove(vis, i) end end
    local pos = math.max(1, math.min(#vis + 1, (insertIdx or #vis) + 1))
    table.insert(vis, pos, spellId)
    s.order[targetGroupId] = vis
end

-- Buffs assigned to a group (groupId 0 = Unused), in saved order; any assigned buff not yet
-- in the order is appended (stable by spellId) so nothing is lost.
-- Hoisted intermediate scratch (GetGroupBuffs is not re-entrant — AllBuffs/GroupOf/GroupOrder never
-- call back into it), wiped per call so a full pass's G+1 GetGroupBuffs calls don't allocate 3 tables
-- each. Only `out` stays freshly allocated (it escapes to the caller).
local ggb_assigned, ggb_seen, ggb_rest = {}, {}, {}
function BG.GetGroupBuffs(groupId)
    local assigned = ggb_assigned; wipe(assigned)
    for _, spellId in ipairs(BG.AllBuffs()) do
        if BG.GroupOf(spellId) == groupId then assigned[spellId] = true end
    end
    local out = {}
    local seen = ggb_seen; wipe(seen)
    for _, sid in ipairs(BG.GroupOrder(groupId)) do
        if assigned[sid] and not seen[sid] then out[#out + 1] = sid; seen[sid] = true end
    end
    local rest = ggb_rest; wipe(rest)
    for sid in pairs(assigned) do if not seen[sid] then rest[#rest + 1] = sid end end
    table.sort(rest)
    for _, sid in ipairs(rest) do out[#out + 1] = sid end
    return out
end

-- ── Custom (cast-triggered) buffs ───────────────────────────────────────────────
-- custom[spellId] = { duration, name, icon }: the addon DRAWS these (a cooldown swipe
-- started by UNIT_SPELLCAST_SUCCEEDED on spellId, running for `duration` seconds), so they
-- need no native frame. name/icon are display hints (resolved from the spell when nil).
function BG.AddCustom(spellId, groupId, opts)
    local s = Store(); if not s or not spellId then return end
    opts = opts or {}
    s.custom[spellId] = {
        duration = tonumber(opts.duration) or 0,
        name     = opts.name,
        icon     = opts.icon,
        owner    = opts.owner,   -- "customcdm" when mirrored from a CustomCDM buff icon (not user-made)
    }
    s.assign[spellId] = groupId or 1
    BG.AppendOrder(groupId or 1, spellId)
end

function BG.RemoveCustom(spellId)
    local s = Store(); if not s then return end
    s.custom[spellId] = nil
    local gid = s.assign[spellId]
    s.assign[spellId] = nil
    if gid then
        local o = BG.GroupOrder(gid)
        for i = #o, 1, -1 do if o[i] == spellId then table.remove(o, i) end end
    end
    s.iconCfg[spellId] = nil
end

function BG.IsCustom(spellId)
    local s = Store(); return s and s.custom[spellId] ~= nil or false
end

-- The custom definition table { duration, name, icon } (nil for a non-custom buff).
function BG.GetCustom(spellId)
    local s = Store(); return s and s.custom and s.custom[spellId] or nil
end

function BG.CustomList()
    local s = Store(); if not s then return {} end
    local out = {}
    for spellId in pairs(s.custom) do out[#out + 1] = spellId end
    return out
end

-- ── Per-icon overrides (the pencil editor) ──────────────────────────────────────
-- iconCfg[spellId] holds SPARSE overrides for the SUBSET of group keys a single icon may
-- diverge on. IconGet resolves: per-icon override -> the buff's current GROUP -> default.
-- Because it falls through to the group, IconGet is safe to call for ANY group key (the
-- engine uses it as the single read for an icon's effective config); the editor only ever
-- WRITES the subset below.
local ICON_OVERRIDE_KEYS = {
    borderEnabled = true, borderColor = true, borderSize = true,
    iconW = true, iconH = true,
    showTimer = true, showTitle = true, showStack = true,
    glowEnabled = true, glowColor = true,
}
BG.ICON_OVERRIDE_KEYS = ICON_OVERRIDE_KEYS

function BG.IconGet(spellId, key)
    local s = Store()
    local ic = s and s.iconCfg and s.iconCfg[spellId]
    if ic and ic[key] ~= nil then return ic[key] end
    return BG.GGet(BG.GroupOf(spellId), key)
end

function BG.IconSet(spellId, key, val)
    local s = Store(); if not s then return end
    s.iconCfg = s.iconCfg or {}
    s.iconCfg[spellId] = s.iconCfg[spellId] or {}
    s.iconCfg[spellId][key] = val
end

-- True if the icon has a per-icon override. With no `key`, reports ANY override (so the
-- strip can tint a diverging icon's pencil). With a `key`, reports whether THAT specific key
-- is overridden (so the editor's per-section "Override group settings" checkbox can reflect
-- the real override state without IconGet's group fallback making everything look "set").
function BG.IconHasOverride(spellId, key)
    local s = Store()
    local ic = s and s.iconCfg and s.iconCfg[spellId]
    if not ic then return false end
    if key ~= nil then return ic[key] ~= nil end
    return next(ic) ~= nil
end

-- Drop a single override key (val nil) or all of them (key nil) → back to group/defaults.
function BG.IconReset(spellId, key)
    local s = Store(); if not (s and s.iconCfg and s.iconCfg[spellId]) then return end
    if key == nil then
        s.iconCfg[spellId] = nil
    else
        s.iconCfg[spellId][key] = nil
        if next(s.iconCfg[spellId]) == nil then s.iconCfg[spellId] = nil end
    end
end
