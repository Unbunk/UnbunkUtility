-- Modules/Fader/Core/Fader.lua
-- BETA: customizable fade for the Cooldown Manager and the Player Frame.
--
-- Each group (cdm / player) fades to a configurable opacity, and "reveals" (snaps back
-- to full alpha) under chosen conditions: in combat, while a target is selected, or while
-- the mouse is over it. An "Active in" instance filter decides WHERE the fade operates at
-- all (e.g. only fade in raids) — outside those instances the frames stay fully opaque.
--
-- Fading is done with frame:SetAlpha, which is NOT a protected action, so this is safe in
-- combat and never taints the (protected) PlayerFrame / CooldownViewer. The opacity is
-- driven from a single throttled OnUpdate that lerps toward the target and re-applies it
-- every tick, so a Blizzard relayout that resets alpha can't leave a frame un-faded.

local ADDON, ns = ...
ns.Fader = ns.Fader or {}
local F = ns.Fader
local L = ns.L

-- Per-group defaults (see file header). enabled defaults OFF — this is opt-in (Beta).
-- `hover` is a per-component map: hovering an ENABLED component reveals the whole group.
-- The CDM group has one entry per CDM sub-component; the player group has just itself.
local DEFAULTS = {
    link = false,   -- link the two groups: if either reveals, both reveal
    cdm = {
        enabled        = false,
        fadedAlpha     = 0.3,
        revealCombat   = true,
        revealTarget   = false,
        hover          = { essentials = true, utility = true, belowPlayer = true, buffs = true, bars = true, resources = true },
        hoverGroups    = {},   -- [category] = { [groupKey] = false }; a group unset here defaults to ON
        hoverEnabled   = true, -- master toggle for the whole "Hovering with mouse" cadre (under "Reveal when")
        fade           = {},   -- [category] = false EXCLUDES that category from the fade (unset = faded)
        fadeGroups     = {},   -- [category] = { [groupKey] = false }; a group unset here is faded (default ON)
        instanceFilter = { dungeon = true, raid = true, battleground = true, outdoor = true },
    },
    player = {
        enabled        = false,
        fadedAlpha     = 0.3,
        revealCombat   = true,
        revealTarget   = false,
        hover          = { player = true },
        instanceFilter = { dungeon = true, raid = true, battleground = true, outdoor = true },
    },
}

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.fader end
F.Cfg = Cfg                                    -- exposed for the "Link" checkbox in the panel
function F.GroupCfg(key) local c = Cfg(); return c and c[key] end

-- ── Per-group hover-reveal (CDM group only) ──────────────────────────────────────
-- Each CDM component (Essential/Utility/Below player/Buffs/Bars/Class resources) reveals per GROUP: hovering
-- an ENABLED group of an enabled category un-fades the whole CDM. HoverGroups(compKey) lists that component's
-- groups as { key, label, resolve } — label for the config checkbox, resolve() for the live frame to hit-test.
-- Frames resolve through the shared anchor resolvers, so hover works in BOTH native and engine mode.
-- Evaluate calls HoverGroups every driver tick (~10-20 Hz) for each enabled category, so it must NOT allocate
-- per tick (the driver hoists scratch tables for the same reason). A persistent per-component store reuses its
-- `out` list + entry tables + resolve closures across calls; only the (rarely-changing) label is refreshed.
-- The config UI iterates the returned list IMMEDIATELY and copies out key/label into its checkboxes, so a reused
-- table is safe there too.
local hgStore = {}
local function StoreFor(compKey)
    local s = hgStore[compKey]
    if not s then s = { out = {}, byKey = {} }; hgStore[compKey] = s end
    return s
end
local function CDMGroupList(inst, dest, compKey)
    local s = StoreFor(compKey)
    local out, byKey = s.out, s.byKey
    wipe(out)
    local list = inst and inst.GroupList and inst.GroupList()
    if type(list) ~= "table" then return out end
    for _, grp in ipairs(list) do
        local id = grp.id
        if id and id ~= 0 then
            local key = tostring(id)
            local e = byKey[key]
            if not e then
                local ck = dest .. ":" .. id
                e = { key = key, resolve = function() return ns.ResolveCDMGroupFrame and ns.ResolveCDMGroupFrame(ck) end }
                byKey[key] = e
            end
            e.label = grp.name or ("Group " .. id)
            out[#out + 1] = e
        end
    end
    return out
end
function F.HoverGroups(compKey)
    if compKey == "essentials" then return CDMGroupList(ns.CDMGroups and ns.CDMGroups.essential, "essential", compKey) end
    if compKey == "utility"    then return CDMGroupList(ns.CDMGroups and ns.CDMGroups.utility,   "utility",   compKey) end
    if compKey == "buffs"      then return CDMGroupList(ns.BuffGroups, "buff", compKey) end
    if compKey == "bars"       then return CDMGroupList(ns.BarGroups,  "bar",  compKey) end
    if compKey == "belowPlayer" then
        local s = StoreFor(compKey)
        if not s.built then   -- static two entries: build once, reuse forever
            s.out[1] = { key = "belowFront", label = L["Below player frame (front)"], resolve = function() return ns.ResolveBelowFrame and ns.ResolveBelowFrame("belowFront") end }
            s.out[2] = { key = "belowEnd",   label = L["Below player frame (end)"],   resolve = function() return ns.ResolveBelowFrame and ns.ResolveBelowFrame("belowEnd") end }
            s.built = true
        end
        return s.out
    end
    if compKey == "resources" then
        local s = StoreFor(compKey)
        local out, byKey = s.out, s.byKey
        wipe(out)
        for _, t in ipairs((ns.ResourceBarAnchorTargets and ns.ResourceBarAnchorTargets()) or {}) do
            if t.key ~= "resbar:last" then   -- skip the "Last bar" alias (it duplicates a real bar)
                local k = t.key
                local e = byKey[k]
                if not e then
                    e = { key = k, resolve = function() return ns.ResolveResourceBarFrame and ns.ResolveResourceBarFrame(k) end }
                    byKey[k] = e
                end
                e.label = t.label
                out[#out + 1] = e
            end
        end
        return out
    end
    return nil   -- "player" (and anything without a group model) -> component-level hover
end
-- Generic CDM-group config flags, DEFAULT ON when unset. store = "hover"/"fade" (per-category) or
-- "hoverGroups"/"fadeGroups" (per-group). Shared by the "Reveal when hovering" + "Fade applies to" cadres.
function F.GetCatFlag(store, compKey)
    local c = F.GroupCfg("cdm")
    return not (c and c[store] and c[store][compKey] == false)
end
function F.SetCatFlag(store, compKey, v)
    local c = F.GroupCfg("cdm"); if not c then return end
    c[store] = c[store] or {}
    c[store][compKey] = v and true or false
end
function F.GetGroupFlag(store, compKey, groupKey)
    local c = F.GroupCfg("cdm")
    local m = c and c[store] and c[store][compKey]
    return not (m and m[groupKey] == false)
end
function F.SetGroupFlag(store, compKey, groupKey, v)
    local c = F.GroupCfg("cdm"); if not c then return end
    c[store] = c[store] or {}
    c[store][compKey] = c[store][compKey] or {}
    c[store][compKey][groupKey] = v and true or false
end

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    p.fader = p.fader or {}
    ns.MergeDefaults(p.fader, DEFAULTS)
end
ns.RegisterCfgInitHook(InitCfg)

-- ── Frame groups + components ────────────────────────────────────────────────
-- A group fades as ONE unit (one alpha over the union of all its component frames),
-- but each component has its own hover flag: hovering an enabled component reveals the
-- whole group. CDM components combine the native CooldownViewer (when present) with OUR
-- tracker icons placed in that destination (anchored to the viewer, not children of it,
-- so they need fading directly). All frames are resolved live; absent ones are skipped.
local GROUPS = {
    cdm = {
        components = {
            { key = "essentials",  native = "EssentialCooldownViewer", dest = "essential",   engineDest = "essential" },
            { key = "utility",     native = "UtilityCooldownViewer",   dest = "utility",     engineDest = "utility"   },
            { key = "belowPlayer",                                     dest = "belowPlayer" },
            { key = "buffs",       native = "BuffIconCooldownViewer",  engineDest = "buff" },
            { key = "bars",        native = "BuffBarCooldownViewer",   engineDest = "bar"  },
            { key = "resources", resourceFrames = true },   -- faded via R.CollectBars + per-bar hover via F.HoverGroups
        },
    },
    player = {
        components = {
            { key = "player", playerFrame = true },
        },
    },
}

-- Append a component's live frames to `out`. fadeFilter (optional) filters the PER-GROUP paths (engine group
-- frames + resource bars) so a deselected group in "Fade applies to" isn't faded; nil = every frame (restore).
local function ComponentFrames(comp, out, fadeFilter)
    if comp.playerFrame then
        -- Custom unit-frame addons (ElvUI / Unhalted / …) replace Blizzard's PlayerFrame,
        -- so fade whichever player frame(s) actually exist, not just the Blizzard one.
        if ns.CDMAnchor and ns.CDMAnchor.GetPlayerFrames then
            for _, f in ipairs(ns.CDMAnchor.GetPlayerFrames()) do out[#out + 1] = f end
        elseif PlayerFrame then
            out[#out + 1] = PlayerFrame
        end
        return out
    end
    if comp.native then
        local f = _G[comp.native]
        -- Level 2: in engine mode the CDM engine masks ALL FOUR native viewers (SetAlpha(0) + a re-force hook)
        -- and draws its OWN group frames, so don't fade the native viewer here — we'd fight the hook (and
        -- F.Apply's restore would too). The engine's own frames are faded instead, below (comp.engineDest).
        if f and not (ns.CDMMode and ns.CDMMode.IsViewerMasked and ns.CDMMode.IsViewerMasked(comp.native)) then
            out[#out + 1] = f
        end
    end
    if comp.dest and ns.CDMAnchor and ns.CDMAnchor.GetIconFrames then
        -- Level 2: in engine mode the CDM engine HOSTS the essential/utility trackers and OWNS their alpha
        -- (ArrangeGroup keeps them at 1). Fading them here would fight that — and, worse, leave them stuck
        -- at the faded alpha on the switch back to native (LayoutCDMRow re-pins them but never rewrites
        -- alpha), so they'd read as "gone". Skip a dest whose native viewer the engine masks; belowPlayer
        -- has no viewer (not engine-hosted) so it keeps fading normally.
        local vn = ns.CDM_VIEWER and ns.CDM_VIEWER[comp.dest]
        if not (vn and ns.CDMMode and ns.CDMMode.IsViewerMasked and ns.CDMMode.IsViewerMasked(vn)) then
            for _, f in ipairs(ns.CDMAnchor.GetIconFrames(comp.dest)) do out[#out + 1] = f end
        end
    end
    -- Level 2: in ENGINE mode the native viewer above is masked and the standalone engine draws this component
    -- as its OWN pooled group frames — fade THOSE. Fading a group frame cascades alpha to its icons, hosted
    -- trackers and adopted native buff/bar frames (multiplicative parent alpha); the engine never re-forces a
    -- group frame's alpha, so we don't fight it. Native mode has no engine groups, so this is a no-op there.
    if comp.engineDest and ns.CDMMode and ns.CDMMode.IsEngine and ns.CDMMode.IsEngine()
       and ns.CDMEngine and ns.CDMEngine.Layout and ns.CDMEngine.Layout.CollectGroupFrames then
        ns.CDMEngine.Layout.CollectGroupFrames(comp.engineDest, out, fadeFilter)
    end
    -- Class resources: fade the live resource bars WITH the CDM (both modes; the widget is the engine's own).
    if comp.resourceFrames and ns.CDMEngine and ns.CDMEngine.Resource and ns.CDMEngine.Resource.CollectBars then
        ns.CDMEngine.Resource.CollectBars(out, fadeFilter)
    end
    return out
end

-- One pass over a group: build the union of all its frames AND decide whether it is
-- revealed (1 alpha) by its own conditions (combat / target / a hovered enabled component)
-- and whether the fade is active here at all. Fills the caller-owned `all` list with the
-- union of the group's live frames and returns reveal, active. The final target alpha is
-- decided by the driver (so the optional link can OR reveals across groups).
local function Evaluate(g, c, all, isCDM)
    local active = ns.IsActiveInInstance(c.instanceFilter)
    local reveal = active and (
        (c.revealCombat and InCombatLockdown()) or
        (c.revealTarget and UnitExists("target"))
    ) or false
    local hoverOn = active and (c.hoverEnabled ~= false)   -- the "Hovering with mouse" master toggle
    for _, comp in ipairs(g.components) do
        local n0 = #all
        -- Fade scope (CDM only): a category EXCLUDED from the fade contributes no frames; otherwise fade only its
        -- ENABLED groups (per-group in engine mode; native / below-player have no per-group frames, so the
        -- fadeGroups filter never matches them and they fade at category level). Passing the fadeGroups[cat]
        -- TABLE (not a closure) keeps the driver allocation-free in the default all-faded state.
        if isCDM then
            if not (c.fade and c.fade[comp.key] == false) then
                ComponentFrames(comp, all, c.fadeGroups and c.fadeGroups[comp.key])
            end
        else
            ComponentFrames(comp, all)
        end
        if hoverOn and not reveal and (not c.hover or c.hover[comp.key] ~= false) then   -- category default ON (nil -> on)
            local groups = F.HoverGroups(comp.key)
            if groups then
                -- CDM: only an ENABLED group of the enabled category triggers the reveal (per-group frames).
                local hg = c.hoverGroups and c.hoverGroups[comp.key]
                for _, grp in ipairs(groups) do
                    if not (hg and hg[grp.key] == false) then
                        local f = grp.resolve()
                        if f and f:IsShown() and f:IsMouseOver() then reveal = true; break end
                    end
                end
            else
                -- No per-group model (the player frame): hover the component's own frames.
                for i = n0 + 1, #all do
                    local f = all[i]
                    if f:IsShown() and f:IsMouseOver() then reveal = true; break end
                end
            end
        end
    end
    return reveal, active
end

-- ── Smooth fade driver ──────────────────────────────────────────────────────────
local cur = { cdm = 1, player = 1 }   -- current (lerped) alpha per group
local FADE_SPEED = 3.5                -- alpha units / second (~0.3s for a full fade)

local driver = CreateFrame("Frame")
driver:Hide()
local accum = 0
-- Scratch tables reused every tick to avoid per-tick allocations (the driver runs
-- at ~10-20Hz). The driver's OnUpdate is the only writer and never re-enters
-- itself, so plain hoisted upvalues are safe. `info`/`records`/`frameLists` are
-- keyed by group key (cdm/player), so each group keeps its OWN frame list — a
-- single shared `all` would let the two groups clobber each other in Pass 2.
local info       = {}
local records    = {}
local frameLists = {}
driver:SetScript("OnUpdate", function(_, dt)
    accum = accum + dt
    if accum < 0.05 then return end
    local step = FADE_SPEED * accum
    accum = 0
    -- Pass 1: evaluate each enabled group's reveal/active state + frames.
    local anyEnabled, anyReveal = false, false
    wipe(info)
    for key, g in pairs(GROUPS) do
        local c = F.GroupCfg(key)
        if c and c.enabled then
            anyEnabled = true
            local frames = frameLists[key] or {}
            frameLists[key] = frames
            wipe(frames)
            local reveal, active = Evaluate(g, c, frames, key == "cdm")
            local rec = records[key] or {}
            records[key] = rec
            rec.c, rec.reveal, rec.active, rec.frames = c, reveal, active, frames
            info[key] = rec
            if reveal then anyReveal = true end
        end
    end
    -- Pass 2: pick the target (with optional link — any reveal reveals all) and lerp.
    local fc = Cfg(); local linked = (fc and fc.link) and true or false
    for key, d in pairs(info) do
        local target
        if not d.active then
            target = 1                                       -- fade not active here -> full
        elseif d.reveal or (linked and anyReveal) then
            target = 1                                       -- revealed (own conditions or linked)
        else
            target = d.c.fadedAlpha or 0.3
        end
        local a = cur[key]
        if a < target then a = math.min(target, a + step)
        elseif a > target then a = math.max(target, a - step) end
        cur[key] = a
        for _, f in ipairs(d.frames) do f:SetAlpha(a) end    -- re-applied each tick (wins over relayouts)
    end
    if not anyEnabled then driver:Hide() end
end)

-- The alpha an engine CDM group frame should carry RIGHT NOW. The engine's group frames are pooled and
-- Group.Setup re-inits one on every rebuild (rebuilds fire on each cast); it uses this to snap the fresh
-- group straight to the live fade instead of resetting to 1 and flashing for a Fader tick. Returns 1 when
-- the cdm fade is disabled / inactive here / this group is excluded from the fade (per category or group);
-- else the current (lerped, reveal-aware) cdm alpha. `g.catKey` is "<dest>:<id>" (e.g. "essential:1").
local DEST_TO_COMP = { essential = "essentials", utility = "utility", buff = "buffs", bar = "bars" }
function F.CDMGroupAlpha(g)
    local c = F.GroupCfg("cdm")
    if not (c and c.enabled) then return 1 end
    local activeFn = ns.IsActiveInInstance
    if activeFn and not activeFn(c.instanceFilter) then return 1 end
    -- g.catKey is "essential:1" once a group is materialized, but the SPEC key ("Essential", no id) at the
    -- Group.Setup snap — tolerate BOTH (lower-cased dest) so a category EXCLUDED from the fade is honoured even
    -- on that snap; the per-group id check just no-ops until the full key is set (the driver corrects next tick).
    local catKey = g and g.catKey
    if catKey then
        local dest, id = catKey:match("^(%a+):(%d+)$")
        if not dest then dest = catKey:match("^(%a+)") end
        local compKey = dest and DEST_TO_COMP[dest:lower()]
        if compKey then
            if c.fade and c.fade[compKey] == false then return 1 end        -- category excluded from the fade
            local fg = c.fadeGroups and c.fadeGroups[compKey]
            if fg and id and fg[id] == false then return 1 end              -- this specific group excluded
        end
    end
    return cur.cdm or 1
end

-- (Re)evaluate which groups are enabled: start the driver for enabled ones, restore full
-- opacity for disabled ones. Called on config change, reload-hook (profile switch) + login.
function F.Apply()
    local anyEnabled = false
    for key, g in pairs(GROUPS) do
        local c = F.GroupCfg(key)
        if c and c.enabled then
            anyEnabled = true
        else
            cur[key] = 1
            local frames = {}
            for _, comp in ipairs(g.components) do ComponentFrames(comp, frames) end
            for _, f in ipairs(frames) do f:SetAlpha(1) end
        end
    end
    if anyEnabled then driver:Show() else driver:Hide() end
end

-- A "Fade applies to" edit (category/group toggled): restore EVERY cdm frame to full, so a just-DESELECTED
-- category/group stops fading immediately; the driver re-fades only the still-selected frames on its next tick.
function F.RefreshFadeScope()
    local frames = {}
    for _, comp in ipairs(GROUPS.cdm.components) do ComponentFrames(comp, frames) end   -- no filter -> ALL cdm frames
    for _, f in ipairs(frames) do f:SetAlpha(1) end
end

ns.RegisterReloadHook(F.Apply)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_ENTERING_WORLD")   -- frames exist + instance type settled
init:SetScript("OnEvent", function() F.Apply() end)
