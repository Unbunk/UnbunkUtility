-- Modules/CDMEngine/Core/Design.lua
--
-- Phase 3 of the standalone CDM engine (ns.CDMEngine): the DESIGNER. A design mode (/uucdmdesign)
-- that lets the user drag each CDM group (Essential / Utility / TrackedBuff) INDEPENDENTLY to a free
-- position, saved per profile (E.Cfg). A group with no saved position stays in the Phase 2 auto-stack;
-- "reset" simply drops the saved position, so the auto-stack IS the default and the reset.
--
-- 100% TAINT-SAFE: the designer only ever creates/moves OUR OWN frames (a pool of brand-blue overlays)
-- and READS EditModeManagerFrame:IsShown() / InCombatLockdown(). It never touches, hooks or moves a
-- native CDM frame (which would taint Blizzard's secure refresh — the reason the whole engine draws
-- BESIDE the natives). It never adds a CDM read to any event handler either: the only cross-talk with
-- the layout is E.Layout.ScheduleRebuild() (already the deferred/coalesced firewall) + a designHook
-- that re-attaches overlays AFTER a build has run (in the deferred pass).
--
-- Two drag targets per group:
--   * a LIVE group   -> the overlay is glued over the group frame (SetAllPoints) and drags the GROUP.
--   * an EMPTY group -> no group frame exists, so the overlay is a fixed-size PLACEHOLDER that drags
--                       ITSELF; the position it saves is picked up the moment a cooldown makes the
--                       category non-empty (BuildLayout -> ApplyFreePositions).

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
local Design = {}
E.Design = Design

Design.active     = false
Design.dragging   = nil   -- key being dragged right now (catKey or "__moveAll__"); read by Layout's drag guard
Design.dragTarget = nil   -- the frame currently being moved (a group, a placeholder, or the move-all handle)

local designForcedShown = false   -- true when Enter() had to auto-show the widgets (so Exit() re-hides)

local function Say(msg)
    if ns.Print then ns.Print(msg) else print("|cff338cff[UnbunkUtility]|r " .. tostring(msg)) end
end

-- ── Overlay pool (our frames only) ───────────────────────────────────────────────────────────────
local pool = {}
local active = {}   -- [catKey] = overlay currently shown

-- Scale-normalised CENTRE offset of a frame vs UIParent's centre (BResTracker OnDragStop idiom,
-- verbatim). Anchoring by the CENTRE is invariant to the group's size: when the icon count changes
-- the group grows/shrinks symmetrically, so a saved position never teleports.
local function ScaleOffset(target)
    local es, ues = target:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local fx, fy = target:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (fx and ux and es and es > 0) then return nil end
    return math.floor((fx * es - ux * ues) / es), math.floor((fy * es - uy * ues) / es)
end

-- End an in-flight drag WITHOUT committing (interrupted move = abandoned): stop the move and clear
-- movable on whatever frame is held, then drop the marker. Used by the combat guard and by Exit so a
-- drag caught mid-flight by a profile switch / widgets-off never leaks a movable/moving group frame.
local function AbortDrag()
    local t = Design.dragTarget
    Design.dragging, Design.dragTarget = nil, nil
    if t then
        if t.StopMovingOrSizing then t:StopMovingOrSizing() end
        if t.SetMovable then t:SetMovable(false) end
    end
end

local function OnDragStart(o)
    if InCombatLockdown() then Say("Can't move a group in combat.") return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return end
    local t = o.target
    if not t then return end
    Design.dragging, Design.dragTarget = o.catKey, t
    t:SetMovable(true)
    t:StartMoving()
end

local function OnDragStop(o)
    local started = (Design.dragging == o.catKey)   -- false if OnDragStart bailed (combat / EditMode / no target)
    Design.dragging, Design.dragTarget = nil, nil
    local t = o.target
    if not t then return end
    t:StopMovingOrSizing()
    if not started then t:SetMovable(false); return end   -- gesture began under a guard: abandon, never commit
    local x, y = ScaleOffset(t)
    t:SetMovable(false)
    if not x then return end
    if o.catKey == "__resource__" then   -- the resource widget owns its ApplyPosition, not the group path
        if E.Cfg then E.Cfg.SetResourcePos(x, y) end
        if E.Resource then E.Resource.ApplyPosition() end
        return
    end
    if t == o then   -- placeholder drags itself: re-anchor cleanly (a live group is re-pinned by ApplyFreePositions)
        o:ClearAllPoints()
        o:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    if E.Cfg then E.Cfg.SetGroupPos(o.catKey, x, y) end
    if E.Layout then E.Layout.ScheduleRebuild() end   -- deferred/coalesced re-pin via ApplyFreePositions
end

-- Right-click an overlay = reset THIS group to auto-stack. Reattach re-parks a placeholder / re-glues
-- a live overlay onto the (about-to-be) re-stacked frame.
local function OnMouseUp(o, button)
    if button ~= "RightButton" then return end
    if o.catKey == "__resource__" then   -- reset the resource widget to its default anchor
        if E.Cfg then E.Cfg.ClearResourcePos() end
        if E.Resource then E.Resource.ApplyPosition() end
        Design.Reattach()
        return
    end
    if E.Cfg then E.Cfg.ClearGroupPos(o.catKey) end
    if E.Layout then E.Layout.ScheduleRebuild() end
    Design.Reattach()
end

local function BuildOverlay()
    local o = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    o:SetFrameStrata("FULLSCREEN_DIALOG")
    o:SetToplevel(true)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    o:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    o.label = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    o.label:SetPoint("CENTER")
    o:SetScript("OnDragStart", function(self) OnDragStart(self) end)
    o:SetScript("OnDragStop",  function(self) OnDragStop(self) end)
    o:SetScript("OnMouseUp",   function(self, button) OnMouseUp(self, button) end)
    return o
end

local function AcquireOverlay(catKey)
    local o = table.remove(pool) or BuildOverlay()
    o.catKey = catKey
    active[catKey] = o
    local r, g, b = 0.20, 0.55, 1
    if ns.GetBrandColor then r, g, b = ns.GetBrandColor() end
    o:SetBackdropColor(r, g, b, 0.30)
    o:SetBackdropBorderColor(r, g, b, 1)
    o:EnableMouse(true)
    o:Show()
    return o
end

-- Return every overlay to the pool WITHOUT mutating `active` mid-iteration (release then wipe).
local function DetachAll()
    for _, o in pairs(active) do
        o.catKey, o.target = nil, nil
        o:EnableMouse(false)
        o:Hide()
        o:ClearAllPoints()
        pool[#pool + 1] = o
    end
    wipe(active)
end

local function AttachLive(catKey, g)
    local o = AcquireOverlay(catKey)
    o.target = g                 -- dragging moves the TARGET frame; the overlay follows it (SetAllPoints)
    o:ClearAllPoints()
    o:SetAllPoints(g)
    o.label:SetText(catKey == "__resource__" and "Resources"
        or (catKey:gsub("^(%a+):(%d+)$", function(d, n)   -- "essential:1" -> "Essential 1"
            return d:sub(1, 1):upper() .. d:sub(2) .. " " .. n
        end)))
    o:Raise()
end

local function AttachPlaceholder(catKey, gs, idx)
    local o = AcquireOverlay(catKey)
    o.target = o                 -- no group frame yet: the placeholder drags itself
    local unit = (gs and gs.size) or 30
    o:SetSize(unit * 3, unit)
    o:ClearAllPoints()
    local p = E.Cfg and E.Cfg.GetGroupPos(catKey)
    if p then
        o:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    else                         -- never placed: park below centre, stacked so multiple empties don't overlap
        o:SetPoint("CENTER", UIParent, "CENTER", 0, -100 - (idx or 0) * (unit + 8))
    end
    o.label:SetText(catKey .. " (empty)")
    o:Raise()
end

-- ── Move-all handle: drag the WHOLE layout (auto stack + every free group) by one delta ──────────
-- A dedicated handle (distinct orange) that, on drop, translates the container base (containerX/Y) AND
-- every free group's saved position by the SAME offset — so "move all" moves everything together, not
-- just the auto-stacked block. It is tracked by DISPLACEMENT (how far the handle moved), so it can sit
-- above the layout without affecting the maths.
local MOVEALL_LIFT = 90       -- px above the container base, to sit clear of the stack
local moveAll

local function MoveAllBy(dx, dy)
    if not (E.Cfg and E.Layout) then return end
    if dx == 0 and dy == 0 then return end
    local ox, oy = E.Cfg.GetContainerPos()
    E.Cfg.SetContainerPos(ox + dx, oy + dy)
    E.Layout.ApplyContainerPosition()          -- container + auto groups move now
    for _, g in ipairs(E.Layout.GetLiveGroups()) do   -- shift every FREE group by the same delta (per-group catKeys)
        if g.catKey then
            local p = E.Cfg.GetGroupPos(g.catKey)
            if p then E.Cfg.SetGroupPos(g.catKey, p.x + dx, p.y + dy) end
        end
    end
    if E.Resource then   -- shift the resource widget too, but ONLY if it was actually placed (mirror the group loop)
        local rp = E.Cfg.GetResourcePos()
        if rp then
            E.Cfg.SetResourcePos(rp.x + dx, rp.y + dy)
            E.Resource.ApplyPosition()
        end
    end
    E.Layout.ScheduleRebuild()                 -- ApplyFreePositions re-pins the shifted free groups
    Design.Reattach()                          -- re-place the handle + group overlays
end

local function EnsureMoveAll()
    if moveAll then return moveAll end
    local o = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    o:SetFrameStrata("FULLSCREEN_DIALOG")
    o:SetToplevel(true)
    o:SetSize(150, 22)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    o:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    o:SetBackdropColor(1, 0.6, 0.1, 0.55)          -- orange: distinct from the blue per-group overlays
    o:SetBackdropBorderColor(1, 0.6, 0.1, 1)
    o.label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.label:SetPoint("CENTER")
    o.label:SetText("Move ALL")
    o:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then Say("Can't move in combat.") return end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return end
        self._startX, self._startY = ScaleOffset(self)
        Design.dragging, Design.dragTarget = "__moveAll__", self
        self:SetMovable(true)
        self:StartMoving()
    end)
    o:SetScript("OnDragStop", function(self)
        local started = (Design.dragging == "__moveAll__")
        Design.dragging, Design.dragTarget = nil, nil
        self:StopMovingOrSizing()
        self:SetMovable(false)
        if not (started and self._startX) then return end
        local ex, ey = ScaleOffset(self)
        if not ex then return end
        MoveAllBy(ex - self._startX, ey - self._startY)
    end)
    moveAll = o
    return o
end

local function AttachMoveAll()
    local o = EnsureMoveAll()
    local cx, cy = 0, 0
    if E.Cfg then cx, cy = E.Cfg.GetContainerPos() end
    o:ClearAllPoints()
    o:SetPoint("CENTER", UIParent, "CENTER", cx, cy + MOVEALL_LIFT)
    o:EnableMouse(true)
    o:Show()
    o:Raise()
end

local function HideMoveAll()
    if moveAll then
        moveAll:EnableMouse(false)
        moveAll:Hide()
    end
end

-- Re-attach overlays after a build (frames were re-pooled) or a reset. DetachAll first, then decide
-- live-vs-placeholder for EVERY catKey in the spec, so each is grabbable exactly once and no overlay
-- is left orphaned on a released frame.
function Design.Reattach()
    if not Design.active then return end
    DetachAll()
    -- One draggable overlay per LIVE group. Multi-group own-icon groups carry per-group catKeys
    -- ("dest:groupId"); buff/bar groups carry the category key. Attach to whatever the layout actually built.
    local liveByKey = {}
    if E.Layout then
        for _, g in ipairs(E.Layout.GetLiveGroups()) do
            if g.catKey then AttachLive(g.catKey, g); liveByKey[g.catKey] = g end
        end
    end
    -- No category placeholders: with multi-group every rendered group is a LIVE per-group catKey
    -- ("dest:groupId"), positioned when it has a shown member. The old empty-category placeholder was keyed by
    -- the SPEC category key ("TrackedBuff"/"TrackedBar"), which never matches a live "buff:N" group — it drew a
    -- stray overlay and saved a dead position. A hosted group with no active member simply has no overlay until
    -- one of its buffs/bars is up (then it becomes grabbable).
    if E.Resource and E.Resource.IsShown() then   -- the class-resource widget is draggable too
        local rc = E.Resource.GetContainer()
        if rc then AttachLive("__resource__", rc) end
    end
    AttachMoveAll()   -- the whole-layout handle, on top, at the container base
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────────────────────────
function Design.Enter()
    if Design.active then return end
    if not (E.Layout and E.Blob and E.Icon and E.Group and E.Cfg) then Say("CDMEngine not ready."); return end
    if InCombatLockdown() then Say("Can't open the designer in combat."); return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        Say("Close Blizzard Edit Mode first."); return
    end
    Design.active = true
    local wasShown = E.Layout.IsShown()
    E.Layout.SetDesignHook(Design.Reattach)   -- arm BEFORE any (deferred) build so the first build re-attaches
    if wasShown then
        Design.Reattach()                     -- groups already built: attach live overlays immediately
    else                                      -- cold start: auto-show; the deferred build's designHook attaches
        designForcedShown = true              -- LIVE overlays onto real frames (no 1-frame "(empty)" placeholder flash)
        E.Layout.EnsureShown()
    end
    Say("CDM design: ON  —  drag a group · right-click = reset that group · /uucdmdesign to close · /uucdmdesign reset = reset all")
end

function Design.Exit()
    if not Design.active then return end
    AbortDrag()                       -- finish any held drag before the overlays are torn down
    Design.active   = false
    Design.dragging, Design.dragTarget = nil, nil
    if E.Layout then E.Layout.SetDesignHook(nil) end
    DetachAll()
    HideMoveAll()
    if designForcedShown then   -- re-hide only if WE turned the widgets on
        designForcedShown = false
        if E.Layout then E.Layout.HideWidgets() end
    end
    Say("CDM design: OFF")
end

function Design.Toggle()
    if Design.active then Design.Exit() else Design.Enter() end
end

function Design.IsActive() return Design.active end

-- ── Combat guard (idiom: DecursiveMove) ──────────────────────────────────────────────────────────
-- End any in-flight drag cleanly BEFORE the lockdown (interrupted move = abandoned, not committed),
-- and drop out of design mode so the overlays don't eat clicks in combat. The out-of-combat rebuild
-- (PLAYER_REGEN_ENABLED is a REBUILD event in Layout) re-applies saved positions.
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function()
    AbortDrag()
    if Design.active then Design.Exit() end
end)

-- Live brand re-tint of the visible overlays (keyed by the persistent guard frame → a valid weak key).
if ns.RegisterBrandRefresh then
    ns.RegisterBrandRefresh(guard, function(r, g, b)
        for _, o in pairs(active) do
            if o.SetBackdropColor then o:SetBackdropColor(r, g, b, 0.30) end
            if o.SetBackdropBorderColor then o:SetBackdropBorderColor(r, g, b, 1) end
        end
    end)
end

-- A profile switch / import keeps the designer OPEN: Layout's reload hook forces the rebuild, and our
-- still-armed designHook re-attaches the overlays with the new profile's positions. We only defensively
-- end an in-flight drag (a profile switch normally can't happen mid-drag — the mouse is on the profile UI).
ns.RegisterReloadHook(function()
    AbortDrag()
end)

-- ── Slash: /uucdmdesign [reset] ──────────────────────────────────────────────────────────────────
SLASH_UUCDMDESIGN1 = "/uucdmdesign"
SlashCmdList["UUCDMDESIGN"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "reset" then
        if E.Cfg then E.Cfg.ClearAllGroupPos() end
        if E.Layout then E.Layout.ScheduleRebuild() end
        if Design.active then Design.Reattach() end
        Say("CDM design: positions reset (auto-stack).")
        return
    end
    Design.Toggle()
end
