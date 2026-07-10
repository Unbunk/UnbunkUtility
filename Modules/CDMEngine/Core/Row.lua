-- Modules/CDMEngine/Core/Row.lua
--
-- Phase 1 driver: a single test row of OUR icons (E.Icon) for the Essential category, at a fixed test
-- anchor (UIParent CENTER), drawn BESIDE the native viewers (we don't hide them yet). Toggled by
-- /uucdmwidgets. Nothing here writes the CDM blob or touches a native frame. Refresh is event-driven:
-- SPELL_UPDATE_COOLDOWN/CHARGES re-drive each icon's swipe/charges (the duration object animates the
-- swipe C-side, so no OnUpdate polling); spec/talent/zone changes rebuild the row (the tracked set
-- changes). Events are registered ONLY while the row is shown (hidden row = zero events).

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine

local ICON_SIZE = 40
local SPACING   = 4

local row
local shown = false
local icons = {}

local function Say(msg)
    if ns.Print then ns.Print(msg) else print("|cff338cff[UnbunkUtility]|r " .. tostring(msg)) end
end

local function EnsureRow()
    if row then return end
    row = CreateFrame("Frame", "UnbunkCDMEngineTestRow", UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(row) end
    row:SetPoint("CENTER", UIParent, "CENTER", 0, 0)   -- fixed test anchor (MVP)
    row:SetSize(1, 1)
end

local function ReleaseIcons()
    for _, f in ipairs(icons) do E.Icon.Release(f) end
    wipe(icons)
end

-- Teardown + rebuild the whole row from the Essential category's configured set (simple + correct for
-- a static row; incremental diffing is a later phase).
local function Rebuild()
    if not (row and E.Blob and E.Icon) then return end
    ReleaseIcons()
    local cat  = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential
    local list = E.Blob.GetTracked(cat, false)   -- false = the configured subset
    local x = 0
    for _, cdmID in ipairs(list) do
        local info = E.Blob.GetInfo(cdmID)
        if info and info.isKnown ~= false then     -- nil isKnown -> include; explicit false -> skip
            local f = E.Icon.Acquire()
            E.Icon.Setup(f, cdmID)
            f:ClearAllPoints()
            f:SetParent(row)
            f:SetPoint("LEFT", row, "LEFT", x, 0)
            f:Show()
            x = x + ICON_SIZE + SPACING
            icons[#icons + 1] = f
        end
    end
    row:SetSize(math.max(x - SPACING, 1), ICON_SIZE)
end

local function RefreshAll()
    for _, f in ipairs(icons) do E.Icon.Update(f) end
end

-- Rebuild = the tracked SET changed (spec / talents / zone). Everything else just re-drives the
-- existing icons. PLAYER_REGEN_ENABLED (combat end) re-drives so an icon set up in combat — whose
-- id couldn't resolve then — self-heals its texture + swipe (see Icon.Update).
local REBUILD = { PLAYER_ENTERING_WORLD = true, PLAYER_SPECIALIZATION_CHANGED = true, TRAIT_CONFIG_UPDATED = true }
local ALL_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
}

-- CRITICAL (CDM taint wall): our SPELL_UPDATE_COOLDOWN handler CO-FIRES with Blizzard's own
-- CooldownViewer handler for that event. Doing the read-heavy work (GetCooldownViewerCooldownInfo /
-- GetSpellCharges / swipe) SYNCHRONOUSLY in the handler taints Blizzard's secure RefreshData, making
-- its secret aura/totem comparisons error ("tainted by UnbunkUtility"). So the handler only flags +
-- schedules a next-frame pass that runs in a clean, untainted execution — the same deferral pattern
-- BuffGroups/BarGroups use for their native-viewer hooks.
local refreshQueued, rebuildQueued = false, false
local function DoDeferredRefresh()
    refreshQueued = false
    if shown and not rebuildQueued then RefreshAll() end
end
local function DoDeferredRebuild()
    rebuildQueued = false
    if shown then Rebuild() end
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

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)   -- trivial: NO CDM/spell reads here (see note above)
    if REBUILD[event] then ScheduleRebuild() else ScheduleRefresh() end
end)

local function RegisterEvents()
    for _, e in ipairs(ALL_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
end
local function UnregisterEvents()
    ev:UnregisterAllEvents()
end

SLASH_UUCDMWIDGETS1 = "/uucdmwidgets"
SlashCmdList["UUCDMWIDGETS"] = function()
    if not (E.Blob and E.Icon) then Say("CDMEngine not ready."); return end
    shown = not shown
    if shown then
        EnsureRow()
        row:Show()
        RegisterEvents()
        ScheduleRebuild()   -- build next frame (deferred, off any co-firing execution)
        Say("CDM widgets test row: ON")
    else
        UnregisterEvents()
        ReleaseIcons()
        if row then row:Hide() end
        Say("CDM widgets test row: OFF")
    end
end
