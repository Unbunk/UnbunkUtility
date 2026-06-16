-- Modules/BuffGroups/Core/Config.lua
-- Data model for the custom CDM "Buff groups": we take the native Buff cooldown viewer
-- (BuffIconCooldownViewer) as the SOURCE of which buffs to track, hide it, and re-draw
-- each tracked buff as our own icon inside a user-defined GROUP (a movable container).
--
-- Per-profile (ns.db.profile.buffGroups):
--   groups[id] = { id, name, posX, posY, iconW, iconH, border*, unlocked }
--   assign[spellId] = groupId   -- which group a buff belongs to:
--                                --   nil  -> Group 1 (the default, indelible group)
--                                --   0    -> "Unused" (hidden, parked in the config)
--                                --   N>=1 -> that group
--   custom[spellId] = true       -- buffs the user added with the "+" (not from the native viewer)
-- Group 1 always exists and can't be deleted; any group (incl. 1) may hold zero icons.

local _, ns = ...
ns.BuffGroups = ns.BuffGroups or {}
local BG = ns.BuffGroups

local DEFAULT_GROUP1 = {
    id = 1, name = "Group 1",
    posX = 0, posY = -120,
    iconW = 32, iconH = 32,
    borderEnabled = true,
    borderColor   = { r = 0, g = 0, b = 0, a = 1 },
    borderSize    = 1,
    unlocked      = false,
}

local DEFAULTS = {
    enabled = true,
    nextId  = 2,
    groups  = { [1] = nil },  -- seeded below (deep-copied) so the shared table isn't mutated
    assign  = {},
    custom  = {},
    order   = {},             -- order[groupId] = { spellId, ... } (display + in-game order)
}

-- Template for a freshly created group (everything but id/name/position).
local GROUP_TEMPLATE = {
    iconW = 32, iconH = 32,
    borderEnabled = true,
    borderColor   = { r = 0, g = 0, b = 0, a = 1 },
    borderSize    = 1,
    unlocked      = false,
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
    if not s.nextId or s.nextId < 2 then s.nextId = 2 end
    -- One-shot: an earlier build PERSISTED a broken default classification (buffs the CDM
    -- hides were forced into Group 1). The default is now derived dynamically from the
    -- HideByDefault flag, so clear the stale assignment + order once (group definitions kept).
    if not s.classifyResetV2 then
        s.classifyResetV2 = true
        s.assign = {}
        s.order  = {}
    end
end
ns.RegisterCfgInitHook(BG.CfgInit)

-- ── Group accessors ───────────────────────────────────────────────────────────
function BG.Enabled() local s = Store(); return not s or s.enabled ~= false end
function BG.SetEnabled(v) local s = Store(); if s then s.enabled = v and true or false end end

function BG.Groups() local s = Store(); return s and s.groups or {} end

-- Groups as an ordered array: Group 1 first, then created groups by ascending id.
function BG.GroupList()
    local s = Store(); if not s then return {} end
    local list = {}
    for id, g in pairs(s.groups) do list[#list + 1] = g end
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
    g.posY = -120 - (id - 1) * 40   -- stagger new groups so they don't stack exactly
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
end

function BG.GGet(id, key)
    local g = BG.GetGroup(id)
    if g and g[key] ~= nil then return g[key] end
    return GROUP_TEMPLATE[key]
end
function BG.GSet(id, key, val)
    local g = BG.GetGroup(id)
    if g then g[key] = val end
end

-- ── Buff → group assignment ───────────────────────────────────────────────────
-- nil -> Group 1 (default); 0 -> Unused; N -> group N. A group that no longer
-- exists is treated as Unused.
function BG.GroupOf(spellId)
    local s = Store(); if not s then return 1 end
    local g = s.assign[spellId]
    if g == nil then
        -- No explicit assignment: the default group follows the CDM's hidden flag — buffs the
        -- CDM hides go to Unused (0), shown ones to Group 1. (Manual drags persist via assign.)
        return (BG.IsHiddenByDefault and BG.IsHiddenByDefault(spellId)) and 0 or 1
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
    local old = BG.GroupOf(spellId)
    local oo = BG.GroupOrder(old)
    for i = #oo, 1, -1 do if oo[i] == spellId then table.remove(oo, i) end end
    s.assign[spellId] = targetGroupId
    local to = BG.GroupOrder(targetGroupId)
    for i = #to, 1, -1 do if to[i] == spellId then table.remove(to, i) end end
    local pos = math.max(1, math.min(#to + 1, (insertIdx or #to) + 1))
    table.insert(to, pos, spellId)
end

-- Buffs assigned to a group (groupId 0 = Unused), in saved order; any assigned buff not yet
-- in the order is appended (stable by spellId) so nothing is lost.
function BG.GetGroupBuffs(groupId)
    local assigned = {}
    for _, spellId in ipairs(BG.AllBuffs()) do
        if BG.GroupOf(spellId) == groupId then assigned[spellId] = true end
    end
    local out, seen = {}, {}
    for _, sid in ipairs(BG.GroupOrder(groupId)) do
        if assigned[sid] and not seen[sid] then out[#out + 1] = sid; seen[sid] = true end
    end
    local rest = {}
    for sid in pairs(assigned) do if not seen[sid] then rest[#rest + 1] = sid end end
    table.sort(rest)
    for _, sid in ipairs(rest) do out[#out + 1] = sid end
    return out
end

-- ── Custom (user-added) buffs ─────────────────────────────────────────────────
function BG.AddCustom(spellId, groupId)
    local s = Store(); if not s or not spellId then return end
    s.custom[spellId] = true
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
end
function BG.IsCustom(spellId)
    local s = Store(); return s and s.custom[spellId] == true or false
end
function BG.CustomList()
    local s = Store(); if not s then return {} end
    local out = {}
    for spellId in pairs(s.custom) do out[#out + 1] = spellId end
    return out
end
