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
        { category = Cat("Essential"),   direction = "row", size = 40, spacing = 4 },
        { category = Cat("Utility"),     direction = "row", size = 34, spacing = 4 },
        { category = Cat("TrackedBuff"), direction = "row", size = 30, spacing = 4 },
    },
}

local container
local shown = false
local groupFrames = {}

local function Say(msg)
    if ns.Print then ns.Print(msg) else print("|cff338cff[UnbunkUtility]|r " .. tostring(msg)) end
end

local function EnsureContainer()
    if container then return end
    container = CreateFrame("Frame", "UnbunkCDMEngineContainer", UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(container) end
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)   -- fixed test anchor (MVP)
    container:SetSize(1, 1)
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
end

-- Arrange a group's icons in a horizontal/vertical flow (px spacing, scale 1 so no /GetScale division);
-- record the group's measured size for the container.
local function ArrangeGroup(g)
    local gs = g.spec
    local horizontal = (gs.direction ~= "column")
    local main, cross, n = 0, 0, #g.children
    for i, f in ipairs(g.children) do
        f:ClearAllPoints()
        if horizontal then f:SetPoint("LEFT", g, "LEFT", main, 0)
        else               f:SetPoint("TOP",  g, "TOP",  0, -main) end
        main  = main + gs.size + (i < n and gs.spacing or 0)
        cross = math.max(cross, gs.size)
    end
    local w = horizontal and main or cross
    local h = horizontal and cross or main
    E.Group.SetDefaultSize(g, math.max(w, 1), math.max(h, 1))
end

-- Stack the groups in the container, reading each group's cached size (measured above).
local function ArrangeContainer()
    local vertical = (SPEC.container.direction ~= "row")
    local main, cross, n = 0, 0, #groupFrames
    for i, g in ipairs(groupFrames) do
        local gw, gh = E.Group.GetDefaultSize(g)
        g:ClearAllPoints()
        if vertical then
            g:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -main)
            main  = main + gh + (i < n and SPEC.container.spacing or 0)
            cross = math.max(cross, gw)
        else
            g:SetPoint("TOPLEFT", container, "TOPLEFT", main, 0)
            main  = main + gw + (i < n and SPEC.container.spacing or 0)
            cross = math.max(cross, gh)
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
            if #g.children > 0 then
                ArrangeGroup(g)
                groupFrames[#groupFrames + 1] = g
            else
                E.Group.Release(g)   -- empty category: no phantom gap in the stack
            end
        end
    end
    ArrangeContainer()
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
        end
    end
    table.sort(sigParts)
    return table.concat(sigParts, ",")
end

local refreshQueued, rebuildQueued = false, false
local function DoDeferredRefresh()
    refreshQueued = false
    if shown and not rebuildQueued then RefreshAll() end
end
local function DoDeferredRebuild()
    rebuildQueued = false
    if not shown then return end
    local sig = ComputeSig()
    if sig == lastSig then RefreshAll(); return end   -- membership unchanged -> just re-drive
    lastSig = sig
    BuildLayout()
end
local function ScheduleRefresh()
    if refreshQueued or rebuildQueued then return end
    refreshQueued = true
    C_Timer.After(0, DoDeferredRefresh)
end
local function ScheduleRebuild()
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

-- ── Toggle ──────────────────────────────────────────────────────────────────────────────────────
SLASH_UUCDMWIDGETS1 = "/uucdmwidgets"
SlashCmdList["UUCDMWIDGETS"] = function()
    if not (E.Blob and E.Icon and E.Group) then Say("CDMEngine not ready."); return end
    shown = not shown
    if shown then
        EnsureContainer()
        container:Show()
        RegisterEvents()
        lastSig = nil            -- force a build on show
        ScheduleRebuild()
        Say("CDM widgets: ON")
    else
        UnregisterEvents()
        E.Icon.ReleaseAll()
        ReleaseGroups()
        if container then container:Hide() end
        Say("CDM widgets: OFF")
    end
end
