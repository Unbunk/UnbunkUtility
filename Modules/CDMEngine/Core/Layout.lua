-- Modules/CDMEngine/Core/Layout.lua
--
-- Phase 2 of the standalone CDM engine (ns.CDMEngine): the data-driven layout engine that replaces the
-- Phase 1 fixed test row (Core/Row.lua is retired). A hardcoded MVP SPEC describes a container + N
-- groups (one per CDM category); each group is populated with E.Icon widgets (E.Blob.GetTracked) and
-- arranged in a horizontal/vertical flow; the groups are stacked in the container. Everything is drawn
-- BESIDE the native viewers — no native-frame contact, no blob writes.
--
-- TAINT FIREWALL (Phase 1 lesson, kept verbatim): the event handler only flags + C_Timer.After(0);
-- ALL CDM reads (GetTracked/GetInfo, Icon.Update) run in the DEFERRED pass, never synchronously in a
-- handler that co-fires with Blizzard's secure CDM refresh. Perf: no per-icon OnUpdate — the swipe
-- animates C-side from a duration object; a membership SIGNATURE turns a no-op rebuild into a refresh.

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine

-- Hardcoded MVP layout: 3 icon groups stacked vertically. TrackedBar (bars) + GroupBuff are P3/P4.
local function Cat(key) return Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[key] end
local SPEC = {
    container = { direction = "column", spacing = 8 },
    groups = {
        { key = "Essential",   category = Cat("Essential"),   direction = "row", size = 40, spacing = 4, trackerDest = "essential" },
        { key = "Utility",     category = Cat("Utility"),     direction = "row", size = 34, spacing = 4, trackerDest = "utility"   },
        { key = "TrackedBuff", category = Cat("TrackedBuff"), direction = "row", size = 30, spacing = 4 },
    },
}

local container
local shown = false
local groupFrames = {}
local designHook          -- set by the designer (E.Design); called after each BuildLayout to re-attach overlays

local function Say(msg)
    if ns.Print then ns.Print(msg) else print("|cff338cff[UnbunkUtility]|r " .. tostring(msg)) end
end

-- Container base position = the whole auto-stack block's offset. Driven live by the P4b move-all handle
-- (Design.MoveAllBy -> Cfg.SetContainerPos); ApplyContainerPosition re-pins the container to
-- CENTER/UIParent at containerX/Y (default 0,0).
local function ApplyContainerPosition()
    if not container then return end
    local x, y = 0, 0
    if E.Cfg then x, y = E.Cfg.GetContainerPos() end
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0)
end

local function EnsureContainer()
    if container then return end
    container = CreateFrame("Frame", "UnbunkCDMEngineContainer", UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(container) end
    container:SetSize(1, 1)
    ApplyContainerPosition()
end

-- ── Materialisation ───────────────────────────────────────────────────────────────────────────
-- Populate a group with an E.Icon per known cooldownID of its category. ApplySize(size) is MANDATORY
-- after Setup, which hardcodes ICON_SIZE.
local function PopulateGroup(g, gs)
    local list = E.Blob.GetTracked(gs.category, false)   -- false = the configured subset
    for _, cdmID in ipairs(list) do
        local info = E.Blob.GetInfo(cdmID)
        if info and info.isKnown ~= false then            -- nil isKnown -> include; explicit false -> skip
            local f = E.Icon.Acquire()
            E.Icon.Setup(f, cdmID)
            E.Icon.ApplySize(f, gs.size)
            f:SetParent(g)
            g.children[#g.children + 1] = f
        end
    end
    -- L2: in engine mode, HOST the CDM trackers (BRes/Potion/…) that opted into this dest, appended after
    -- the cooldown icons. They are OUR frames -> re-parenting/SetPoint is taint-safe. Only the SHOWN ones
    -- reserve a slot (a hidden tracker reserves nothing). CDMAnchor cedes these dests via owned() so it
    -- no longer pins them to the (masked) native viewer.
    if ns.CDMMode and ns.CDMMode.IsEngine() and gs.trackerDest
       and ns.CDMAnchor and ns.CDMAnchor.GetIconDescriptors then
        for _, td in ipairs(ns.CDMAnchor.GetIconDescriptors(gs.trackerDest)) do
            if td.frame and td.frame:IsShown() then
                td.frame:SetParent(g)
                g.trackers[#g.trackers + 1] = td
            end
        end
    end
end

-- Arrange a group's icons in a horizontal/vertical flow (px spacing, scale 1 so no /GetScale division);
-- record the group's measured size for the container.
local function ArrangeGroup(g)
    local gs = g.spec
    local horizontal = (gs.direction ~= "column")
    local main, cross = 0, 0
    local function Place(f, sz)
        if main > 0 then main = main + gs.spacing end   -- gap only BETWEEN elements (no leading/trailing)
        f:ClearAllPoints()
        if horizontal then f:SetPoint("LEFT", g, "LEFT", main, 0)
        else               f:SetPoint("TOP",  g, "TOP",  0, -main) end
        main  = main + sz
        cross = math.max(cross, sz)
    end
    for _, f in ipairs(g.children) do Place(f, gs.size) end
    -- L2: hosted trackers flow AFTER the cooldown icons, sized to the group and forced visible (the
    -- native viewer is masked; our anchored frames don't inherit its alpha, but the fade could touch them).
    for _, td in ipairs(g.trackers) do
        local f = td.frame
        if f then
            if td.setSize then td.setSize(gs.size, gs.size) else f:SetSize(gs.size, gs.size) end
            f:SetAlpha(1)
            Place(f, gs.size)
        end
    end
    local w = horizontal and main or cross
    local h = horizontal and cross or main
    E.Group.SetDefaultSize(g, math.max(w, 1), math.max(h, 1))
end

-- A group is "free" (designer-placed) when it has a saved position; it is anchored directly to
-- UIParent by ApplyFreePositions and is NOT part of the auto-stack. Absence of a saved position =
-- auto-stack (the P2 behaviour, unchanged) — which is also what "reset" restores.
local function IsFree(g)
    return (E.Cfg and E.Cfg.GetGroupPos(g.catKey)) ~= nil
end

-- Re-impose the saved CENTER/UIParent anchor of every free group. Idempotent, called last in a build
-- (and in the cheap refresh path) so the config always has the final word on position.
local function ApplyFreePositions()
    if not E.Cfg then return end
    for _, g in ipairs(groupFrames) do
        local p = E.Cfg.GetGroupPos(g.catKey)
        if p then
            g:ClearAllPoints()
            g:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
        end
    end
end

-- Stack the AUTO groups in the container, reading each group's cached size (measured above). Free
-- (designer-placed) groups are skipped here and pinned to UIParent by ApplyFreePositions instead.
local function ArrangeContainer()
    local vertical = (SPEC.container.direction ~= "row")
    local main, cross, placed = 0, 0, 0
    for _, g in ipairs(groupFrames) do
        if not IsFree(g) then                                          -- free groups are pinned by ApplyFreePositions
            if placed > 0 then main = main + SPEC.container.spacing end -- gap only BETWEEN two stacked groups (no
            local gw, gh = E.Group.GetDefaultSize(g)                   -- leading/trailing phantom when groups are free)
            g:ClearAllPoints()
            if vertical then
                g:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -main)
                main  = main + gh
                cross = math.max(cross, gw)
            else
                g:SetPoint("TOPLEFT", container, "TOPLEFT", main, 0)
                main  = main + gw
                cross = math.max(cross, gh)
            end
            placed = placed + 1
        end
    end
    local w = vertical and cross or main
    local h = vertical and main or cross
    container:SetSize(math.max(w, 1), math.max(h, 1))
end

local function ReleaseGroups()
    for _, g in ipairs(groupFrames) do E.Group.Release(g) end
    wipe(groupFrames)
end

-- Full teardown + rebuild, bottom-up: each group is populated + arranged (so its size is final) BEFORE
-- the container stacks them. E.Icon.ReleaseAll is the single owner of icon teardown.
local function BuildLayout()
    if not (container and E.Blob and E.Icon and E.Group) then return end
    E.Icon.ReleaseAll()
    ReleaseGroups()
    for _, gs in ipairs(SPEC.groups) do
        if gs.category ~= nil then
            local g = E.Group.Acquire()
            E.Group.Setup(g, gs)
            g:SetParent(container)
            PopulateGroup(g, gs)
            if #g.children > 0 or #g.trackers > 0 then   -- a group with ONLY hosted trackers still counts
                ArrangeGroup(g)
                groupFrames[#groupFrames + 1] = g
            else
                E.Group.Release(g)   -- empty category: no phantom gap in the stack
            end
        end
    end
    ArrangeContainer()
    ApplyFreePositions()                   -- free groups: pinned to UIParent, the last word on position
    if designHook then designHook() end    -- designer re-attaches overlays onto the fresh pooled frames
end

-- ── Coalesced, DEFERRED relayout (Phase 1 firewall, generalised) ────────────────────────────────
local function RefreshAll()
    for _, g in ipairs(groupFrames) do
        for _, f in ipairs(g.children) do E.Icon.Update(f) end
    end
end

-- Membership signature: skip a full rebuild when the tracked set is unchanged (a no-op REBUILD event
-- becomes a cheap refresh). MUST sort before concat — the pool order is non-deterministic.
local sigParts = {}
local lastSig
local function ComputeSig()
    wipe(sigParts)
    for _, gs in ipairs(SPEC.groups) do
        if gs.category ~= nil then
            for _, cdmID in ipairs(E.Blob.GetTracked(gs.category, false)) do
                local info = E.Blob.GetInfo(cdmID)
                sigParts[#sigParts + 1] = cdmID .. ((info and info.isKnown ~= false) and "+" or "-")
            end
            -- L2: fold the hosted-tracker membership so a tracker showing/hiding forces a rebuild (not
            -- just a refresh) — the cheap path can't re-collect frames.
            if ns.CDMMode and ns.CDMMode.IsEngine() and gs.trackerDest
               and ns.CDMAnchor and ns.CDMAnchor.GetIconDescriptors then
                for _, td in ipairs(ns.CDMAnchor.GetIconDescriptors(gs.trackerDest)) do
                    sigParts[#sigParts + 1] = "T" .. td.name .. ((td.frame and td.frame:IsShown()) and "+" or "-")
                end
            end
        end
    end
    table.sort(sigParts)
    return table.concat(sigParts, ",")
end

local refreshQueued, rebuildQueued = false, false
local ScheduleRefresh, ScheduleRebuild   -- forward-declared: DoDeferredRebuild re-arms itself under a drag
local function DoDeferredRefresh()
    refreshQueued = false
    if shown and not rebuildQueued then RefreshAll() end
end
local function DoDeferredRebuild()
    rebuildQueued = false
    if not shown then return end
    -- Never tear down / re-pool a group while the user holds it under a drag: re-arm and let the drop
    -- (which clears Design.dragging) run the build. Bounds to one empty timer per frame of an active drag.
    if E.Design and E.Design.dragging then ScheduleRebuild(); return end
    local sig = ComputeSig()
    if sig == lastSig then
        RefreshAll()
        ArrangeContainer()      -- re-stack auto groups (a group reset from free -> auto rejoins the stack)
        ApplyFreePositions()    -- re-pin free groups (idempotent; the config has the last word)
        return
    end
    lastSig = sig
    BuildLayout()
end
function ScheduleRefresh()
    if refreshQueued or rebuildQueued then return end
    refreshQueued = true
    C_Timer.After(0, DoDeferredRefresh)
end
function ScheduleRebuild()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0, DoDeferredRebuild)
end

-- REBUILD = the tracked set may have changed (spec/talents/zone; PLAYER_REGEN_ENABLED so a combat-time
-- build self-heals out of combat). Everything else just re-drives the existing icons.
local REBUILD = { PLAYER_ENTERING_WORLD = true, PLAYER_SPECIALIZATION_CHANGED = true,
                  TRAIT_CONFIG_UPDATED = true, PLAYER_REGEN_ENABLED = true }
local ALL_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
}

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)   -- trivial: NO CDM/spell reads here (co-fires with Blizzard)
    if REBUILD[event] then ScheduleRebuild() else ScheduleRefresh() end
end)
local function RegisterEvents()
    for _, e in ipairs(ALL_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
end
local function UnregisterEvents()
    ev:UnregisterAllEvents()
end

-- ── Show / hide (shared by the slash and by the designer's auto-show) ────────────────────────────
local function EnsureShown()
    if shown then return end
    shown = true
    EnsureContainer()
    container:Show()
    RegisterEvents()
    lastSig = nil            -- force a build on show
    ScheduleRebuild()
    if E.Resource and E.Resource.EnsureShown then E.Resource.EnsureShown() end   -- P4c class resources
end
local function HideWidgets()
    if not shown then return end
    shown = false
    UnregisterEvents()
    E.Icon.ReleaseAll()
    ReleaseGroups()   -- Group.Release re-parents every hosted tracker back to UIParent (single owner of that handoff)
    if container then container:Hide() end
    if E.Resource and E.Resource.HideWidgets then E.Resource.HideWidgets() end   -- P4c class resources
end

-- ── Public surface for the designer (Core/Design.lua) ────────────────────────────────────────────
E.Layout = E.Layout or {}
function E.Layout.IsShown()         return shown end
function E.Layout.GetSpec()         return SPEC end
function E.Layout.GetLiveGroups()   return groupFrames end
function E.Layout.ScheduleRebuild() ScheduleRebuild() end
function E.Layout.SetDesignHook(fn) designHook = fn end
function E.Layout.EnsureShown()     EnsureShown() end
function E.Layout.HideWidgets()     HideWidgets() end
function E.Layout.ApplyContainerPosition() ApplyContainerPosition() end   -- move the whole block (P4b move-all)
-- Config-panel toggle (mirrors the /uucdmwidgets slash: exit the designer before hiding).
function E.Layout.SetShown(v)
    if v then
        EnsureShown()
    else
        if E.Design and E.Design.IsActive() then E.Design.Exit() end
        HideWidgets()
    end
end

-- ── Toggle ──────────────────────────────────────────────────────────────────────────────────────
SLASH_UUCDMWIDGETS1 = "/uucdmwidgets"
SlashCmdList["UUCDMWIDGETS"] = function()
    if not (E.Blob and E.Icon and E.Group) then Say("CDMEngine not ready."); return end
    if shown then
        if E.Design and E.Design.IsActive() then E.Design.Exit() end   -- avoid overlays orphaned on released frames
        HideWidgets()
        Say("CDM widgets: OFF")
    else
        EnsureShown()
        Say("CDM widgets: ON")
    end
end

-- A profile switch / import wholesale-replaces the saved config: force a full rebuild so the NEW
-- profile's group positions are read (lastSig = nil guarantees BuildLayout, not the cheap path). The
-- designer STAYS OPEN — its still-armed designHook re-attaches the overlays onto the rebuilt frames at
-- the new profile's positions. The deferred rebuild runs after ns.db.profile is repointed + CfgInit
-- re-merged, so ApplyFreePositions reads the right profile.
ns.RegisterReloadHook(function()
    if shown then lastSig = nil; ScheduleRebuild() end
end)
