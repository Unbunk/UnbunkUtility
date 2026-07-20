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

-- Hardcoded layout: icon groups + hosted native buff/bar rows, stacked vertically. This covers ALL FOUR real
-- CDM display categories. 12.1.0 has NO 5th display category: Enum.CooldownViewerCategory is only
-- {Essential=0, Utility=1, TrackedBuff=2, TrackedBar=3} plus the internal hidden buckets HiddenSpell=-1 /
-- HiddenAura=-2 (not viewers). "GroupBuff" does NOT exist on the client (verified in-game) — the engine is
-- category-complete.
local function Cat(key) return Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[key] end
local SPEC = {
    container = { direction = "column", spacing = 8 },
    groups = {
        { key = "Essential",   category = Cat("Essential"),   direction = "row", size = 40, spacing = 4, trackerDest = "essential" },
        { key = "Utility",     category = Cat("Utility"),     direction = "row", size = 34, spacing = 4, trackerDest = "utility"   },
        { key = "TrackedBuff", category = Cat("TrackedBuff"), direction = "row", size = 30, spacing = 4, isBuff = true },
        { key = "TrackedBar",  category = Cat("TrackedBar"),  direction = "column", size = 20, spacing = 4, isBar = true },
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
    container:SetSize(1, 1)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)   -- auto-stack block base = screen centre
end

-- ── Tracked buffs: HOST the native BuffIcon frames ──────────────────────────────────────────────
-- A buff's aura STACKS / DURATION are SECRET in combat, so the engine cannot redraw a buff faithfully (its
-- own icons would show spell data — charges/cooldown — not aura data). Blizzard renders the buff C-side in
-- the native BuffIcon viewer, which keeps one pool frame per tracked buff and toggles its IsShown() as the
-- aura comes/goes. So the engine HOSTS the SHOWN native frames — re-anchored into our group via the shared
-- CDMAnchor.PinNativeTo (raw re-anchor + re-impose hooks; taint-safe, the same primitive BuffGroups uses).
-- BuffIcon is left VISIBLE (not alpha-masked — see Mode.lua) so the hosted frames render. Secret-safe: we
-- read only the frame's structural shown-state + spell id, never the secret aura duration.
local nativeBuffEnum = {}
local function InEditMode()
    return (EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown()) or false
end
-- A per-frame identity that SURVIVES combat: a buff's DISPLAY spell id is SECRET in combat (nil), so fall
-- back to the base id, then to the frame's own identity (the pool keeps one frame per displayed buff). The
-- rebuild signature keys on this — else two secret-id buffs would both fold to one token and a same-tick
-- 1-for-1 swap (count unchanged) would slip past the no-change early-out, ghost-pinning the expired frame.
local function BuffFrameKey(nf)
    local A = ns.CDMAnchor
    local sid = A and (A.NativeFrameSpellId(nf) or (A.NativeFrameBaseSpellId and A.NativeFrameBaseSpellId(nf)))
    return sid and tostring(sid) or ("F" .. tostring(nf))
end
local function BuffFrameOrder(a, b)
    local A = ns.CDMAnchor
    local ka = (A and (A.NativeFrameSpellId(a) or (A.NativeFrameBaseSpellId and A.NativeFrameBaseSpellId(a)))) or 0
    local kb = (A and (A.NativeFrameSpellId(b) or (A.NativeFrameBaseSpellId and A.NativeFrameBaseSpellId(b)))) or 0
    if ka ~= kb then return ka < kb end
    return tostring(a) < tostring(b)   -- stable tiebreak when both ids are secret (combat -> both 0)
end
local function CollectShownBuffFrames(out)
    wipe(out)
    -- Only HOST native frames when the viewer is actually alpha-masked (engine mode). In native mode
    -- BuffGroups still owns/pins these pool frames, so adopting them too would double-own (SetPoint/SetParent
    -- ping-pong) if the engine widgets are shown in native mode. Mirrors the trackerDest gate.
    if not (ns.CDMMode and ns.CDMMode.IsEngine()) then return out end
    if InEditMode() then return out end   -- don't host Blizzard EditMode preview sample frames (shown, no live aura)
    local A = ns.CDMAnchor
    if not (A and A.EnumBuffIcons) then return out end
    for _, nf in ipairs(A.EnumBuffIcons(nativeBuffEnum)) do
        if nf.IsShown and nf:IsShown() then out[#out + 1] = nf end   -- shown pool frame == aura currently up
    end
    table.sort(out, BuffFrameOrder)
    return out
end

-- ── Tracked bars: HOST the native BuffBar frames (same rationale as buffs) ───────────────────────
-- A bar renders an aura's DURATION / fill, both SECRET in combat (BuffBar:SetValue + its min/max ARE
-- secret — reading them taints), so the engine cannot redraw a bar; it HOSTS the native BuffBar pool
-- frames exactly like TrackedBuff. Enumerate via ns.BarGroups.EnumBarFrames (the shared bar-pool reader)
-- and keep only the SHOWN ones (a shown pool frame == the buff is up). BuffBarCooldownViewer is alpha-
-- masked (Mode.lua) and the frames are ADOPTED out onto our group, so they render from us. Bars are wide
-- rows (not square icons), so ArrangeGroup hosts them at their NATIVE size and flows them by direction.
local nativeBarEnum = {}
local function CollectShownBarFrames(out)
    wipe(out)
    if not (ns.CDMMode and ns.CDMMode.IsEngine()) then return out end   -- only host when masked (engine); else BarGroups owns the frames
    if InEditMode() then return out end   -- don't host Blizzard EditMode preview sample bars
    local BG = ns.BarGroups
    if not (BG and BG.EnumBarFrames) then return out end
    for _, nf in ipairs(BG.EnumBarFrames(nativeBarEnum)) do
        if nf.IsShown and nf:IsShown() then out[#out + 1] = nf end   -- shown pool frame == aura up
    end
    table.sort(out, BuffFrameOrder)   -- shared identity comparator (works on any cooldownInfo frame)
    return out
end

-- The on-screen size of a native bar. Frame geometry is NOT secret (unlike its fill value), so this is a
-- safe read; fall back to sane defaults if the pool frame hasn't been laid out yet.
local BAR_FALLBACK_W, BAR_FALLBACK_H = 200, 20
local function BarSize(nf)
    local w = (nf.GetWidth and nf:GetWidth()) or 0
    local h = (nf.GetHeight and nf:GetHeight()) or 0
    if not (type(w) == "number" and w > 1) then w = BAR_FALLBACK_W end
    if not (type(h) == "number" and h > 1) then h = BAR_FALLBACK_H end
    return w, h
end

-- ── Materialisation ───────────────────────────────────────────────────────────────────────────
-- Populate a group: an E.Icon per known cooldownID (Essential / Utility) OR the hosted native buff frames
-- (TrackedBuff). ApplySize(size) is MANDATORY after Setup, which hardcodes ICON_SIZE.
local function PopulateGroup(g, gs)
    if gs.isBuff then
        CollectShownBuffFrames(g.nativeBuffs)   -- host the native BuffIcon frames; ArrangeGroup pins them
        return
    end
    if gs.isBar then
        CollectShownBarFrames(g.nativeBars)     -- host the native BuffBar frames; ArrangeGroup adopts them
        return
    end
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
    -- Cross-axis alignment from the group's placement (g._relPos): "above" (default) shares the BOTTOM edge so
    -- a SHORTER icon sits flush at the bottom of the row; "below"/bottom-corners share the TOP edge.
    local alignTop = (g._relPos == "below" or g._relPos == "bottomleft" or g._relPos == "bottomright")
    local spacing = g._spacing or gs.spacing   -- honour the host group's own spacing; fall back to the SPEC default
    local main, cross = 0, 0
    -- w = main-axis extent, h = cross-axis extent. Square callers pass one value (h defaults to w); the
    -- own icons pass their CONFIG size (iconW/iconH may differ) so a non-square icon lays out correctly.
    local function Place(f, w, h)
        w = w or gs.size; h = h or w
        if main > 0 then main = main + spacing end   -- gap only BETWEEN elements (no leading/trailing)
        f:ClearAllPoints()
        if horizontal then
            f:SetPoint("LEFT", g, "LEFT", main, 0)
            main = main + w; cross = math.max(cross, h)
        else
            f:SetPoint("TOP", g, "TOP", 0, -main)
            main = main + h; cross = math.max(cross, w)
        end
    end
    for _, f in ipairs(g.children) do Place(f, f:GetWidth(), f:GetHeight()) end
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
    -- Hosted native buff frames (TrackedBuff): Blizzard's OWN pool frames — ADOPT them (SetParent onto our
    -- group + raw re-impose) so the BuffIcon viewer can be alpha-0-masked and they still render (they inherit
    -- our group's alpha, not the masked viewer's). AdoptNativeTo anchors TOPLEFT->g TOPLEFT; a buff group
    -- holds only these, so the row is self-consistent. Blizzard keeps rendering their aura stacks / duration
    -- swipe C-side (secret in combat, unredrawable — hence hosting the native frame).
    -- Pre-pass: the TALLEST hosted buff sets the row's cross extent, so a shorter icon can share a common edge —
    -- the BOTTOM edge for "above" placement (default), the TOP edge for "below". Without this every buff was
    -- adopted at y=0 (top-aligned), leaving a shorter icon floating with a gap at the bottom of the row.
    local A, BGm = ns.CDMAnchor, ns.BuffGroups
    local maxBuffH = 0
    for _, nf in ipairs(g.nativeBuffs) do
        local s = nf.ph and nf.sid or (A and A.NativeFrameSpellId and A.NativeFrameSpellId(nf))
        maxBuffH = math.max(maxBuffH, (s and BGm and BGm.IconGet and BGm.IconGet(s, "iconH")) or gs.size)
        -- Cache each buff's border OUTSET so the pack can line up the OUTER border edges (a thicker native/
        -- dispel border must not stick out past the others). Icons stay full-size; only their y shifts.
        nf._uuBO = (not nf.ph) and BGm and BGm.BorderOutset and BGm.BorderOutset(nf, s) or 0
    end
    for _, nf in ipairs(g.nativeBuffs) do
        if main > 0 then main = main + spacing end
        if nf.ph then   -- Static Display: reserve an inactive buff's slot (size from its config), adopt nothing
            local bw = (nf.sid and BGm and BGm.IconGet and BGm.IconGet(nf.sid, "iconW")) or gs.size
            main = main + bw
        else
        local sid = A and A.NativeFrameSpellId and A.NativeFrameSpellId(nf)   -- nil (secret) in combat -> keep last style
        local bw = (sid and BGm and BGm.IconGet and BGm.IconGet(sid, "iconW")) or gs.size
        local bh = (sid and BGm and BGm.IconGet and BGm.IconGet(sid, "iconH")) or gs.size
        -- Line up the OUTER border edges (not the icon edges): shift each frame by its own border outset so
        -- the border edge sits on the row line — thicker-bordered icons move IN (their icon body offsets), the
        -- borders align, and nothing spills past the row. "above" -> bottom edge; "below" -> top edge.
        local ob = nf._uuBO or 0
        local yoff = alignTop and (-ob) or (-(maxBuffH - bh) + ob)
        if A and A.AdoptNativeTo then A.AdoptNativeTo(nf, g, main, yoff, bw, bh) end
        -- PARITY: restyle the hosted native buff frame with BuffGroups' own recipe (font/border/stack/colour;
        -- its SetSize matches the adopt size). Runs in the deferred layout pass, never inside Blizzard's secure
        -- refresh, so it is taint-safe (same as BuffGroups' own pass; ReanchorStack uses ns.AnchorFSRaw).
        if sid and BGm and BGm.StyleFrame then BGm.StyleFrame(nf, sid) end
        -- Blizzard runs a per-FRAME alpha fade on the buff pool frames (aura in/out); the reparent doesn't
        -- reset it and the viewer mask only guards the viewer, so clear a lingering sub-1 alpha. Taint-safe.
        if nf.GetAlpha and nf:GetAlpha() ~= 1 then nf:SetAlpha(1) end
        main = main + bw
        end
    end
    cross = math.max(cross, maxBuffH)
    -- Hosted native bar frames (TrackedBar): same model as buffs — ADOPT the native BuffBar pool frames so
    -- the masked BuffBarCooldownViewer's frames still render (Blizzard fills their secret value/duration
    -- C-side). Bars are WIDE rows, so host them at their NATIVE size (pass no w,h -> AdoptNativeTo won't
    -- resize) and flow per the group direction (column by default -> a vertical stack of bars).
    for _, nf in ipairs(g.nativeBars) do
        if main > 0 then main = main + spacing end
        local BRm = ns.BarGroups
        if nf.ph then   -- Static Display: reserve an inactive bar's slot (size from its config), adopt nothing
            local bw = (nf.sid and BRm and BRm.IconGet and BRm.IconGet(nf.sid, "barWidth"))  or BAR_FALLBACK_W
            local bh = (nf.sid and BRm and BRm.IconGet and BRm.IconGet(nf.sid, "barHeight")) or BAR_FALLBACK_H
            main = main + (horizontal and bw or bh)
            cross = math.max(cross, horizontal and bh or bw)
        else
        local A = ns.CDMAnchor
        local sid = A and A.NativeFrameSpellId and A.NativeFrameSpellId(nf)
        local dw, dh = BarSize(nf)
        local bw = (sid and BRm and BRm.IconGet and BRm.IconGet(sid, "barWidth"))  or dw
        local bh = (sid and BRm and BRm.IconGet and BRm.IconGet(sid, "barHeight")) or dh
        if A and A.AdoptNativeTo then
            local x = horizontal and main or 0
            local y = horizontal and 0 or -main
            A.AdoptNativeTo(nf, g, x, y, bw, bh)   -- re-impose the styled bar size
        end
        -- PARITY: restyle the hosted native bar (texture/colour/fill/icon side + size) with BarGroups' recipe,
        -- in the deferred pass (taint-safe). StyleBarFrame's SetSize matches the adopt size above.
        if sid and BRm and BRm.StyleBarFrame then BRm.StyleBarFrame(nf, sid) end
        if nf.GetAlpha and nf:GetAlpha() ~= 1 then nf:SetAlpha(1) end
        main  = main + (horizontal and bw or bh)
        cross = math.max(cross, horizontal and bh or bw)
        end
    end
    local w = horizontal and main or cross
    local h = horizontal and cross or main
    E.Group.SetDefaultSize(g, math.max(w, 1), math.max(h, 1))
end

-- The per-group screen-centre position configured in the group's OWN tab (CDMGroups / BuffGroups /
-- BarGroups — the "Position (offset from screen center)" X/Y = posX/posY). The engine reuses that native
-- config as its single source of truth (no separate designer store): it treats posX/posY as a screen-
-- centre offset and ignores the native anchorTo (whose viewers are masked in engine mode). catKey is
-- "dest:groupId" (essential:1 / utility:2 / buff:1 / bar:1). Both axes must be set for a group to be
-- "positioned"; otherwise it auto-stacks.
local function GroupTabInstance(dest)
    if dest == "essential" or dest == "utility" then return ns.CDMGroups and ns.CDMGroups[dest] end
    if dest == "buff" then return ns.BuffGroups end
    if dest == "bar"  then return ns.BarGroups end
    return nil
end
local function GroupTabGet(g, key)
    local dest, gid = tostring(g.catKey or ""):match("^(%a+):(%d+)$")
    local I = dest and GroupTabInstance(dest)
    if not (I and I.GGet and gid) then return nil end
    return I.GGet(tonumber(gid), key)
end
local function GroupTabPos(g)
    local x, y = GroupTabGet(g, "posX"), GroupTabGet(g, "posY")
    if type(x) == "number" and type(y) == "number" then return x, y end
    return nil
end
-- placement key -> { group point, anchor point } (mirrors BuffGroups/BarGroups RELPOS_POINTS). Used only
-- when a group rides a resource bar (below).
local RELPOS_POINTS = {
    above       = { "BOTTOM",      "TOP"         },
    below       = { "TOP",         "BOTTOM"      },
    left        = { "RIGHT",       "LEFT"        },
    right       = { "LEFT",        "RIGHT"       },
    topleft     = { "BOTTOMRIGHT", "TOPLEFT"     },
    topright    = { "BOTTOMLEFT",  "TOPRIGHT"    },
    bottomleft  = { "TOPRIGHT",    "BOTTOMLEFT"  },
    bottomright = { "TOPLEFT",     "BOTTOMRIGHT" },
}

-- The engine group frame for a catKey ("essential:1"/"utility:1"/…), or nil.
local function GroupFrameByKey(catKey)
    for _, gf in ipairs(groupFrames) do if gf.catKey == catKey then return gf end end
    return nil
end
local function GroupDest(g) return tostring(g.catKey or ""):match("^(%a+):") end
-- Resolve an anchorTo key to a LIVE frame for absolute-pin positioning, mirroring the native ContainerAnchor
-- targets so a Buff/Bar group anchors the SAME way in engine mode:
--   resbar:*           -> the shared resource-bar proxy handle,
--   essential/utility  -> the engine's OWN block for that dest (Group 1's frame; own-drawn in engine mode),
--   belowPlayer        -> the player frame.
-- The essential/utility/belowPlayer targets are honoured ONLY for the HOST groups (Buffs/Bars), whose anchorTo
-- the USER sets. The engine's own essential/utility blocks keep their tab posX/posY — their native
-- anchorTo (default "essential"/"screen") is a NATIVE-mode layout concept, not an engine position, so honouring
-- it here would move them. (resbar is buff/bar-only in practice, so it needs no such gate.)
local function EngineAnchorFrame(g, a)
    if not a then return nil end
    if ns.IsResourceBarAnchorKey and ns.IsResourceBarAnchorKey(a) then
        return (ns.ResolveResourceBarFrame and ns.ResolveResourceBarFrame(a)) or nil
    end
    local dest = GroupDest(g)
    if dest ~= "buff" and dest ~= "bar" then return nil end
    if ns.ParseCDMGroupKey then
        local d, gid = ns.ParseCDMGroupKey(a)   -- "essential:2"/"utility:1"/"buff:1"/"bar:1" (or legacy plain -> :1)
        if d then
            local target = GroupFrameByKey(d .. ":" .. gid)
            if target == g then return nil end   -- a group must NEVER anchor to itself
            if target then return target end
            if d == "essential" or d == "utility" then   -- engine frame not up yet -> native Group-1 fallback
                return (ns.CDMGroups and ns.CDMGroups.AnchorFrame and ns.CDMGroups.AnchorFrame(d)) or nil
            end
            return nil
        end
    end
    if ns.IsBelowAnchorKey and ns.IsBelowAnchorKey(a) then   -- belowPlayer (middle) / belowFront / belowEnd
        return (ns.ResolveBelowFrame and ns.ResolveBelowFrame(a)) or nil
    end
    return nil
end
-- A group is "free" (absolute-pinned) when its tab sets posX/posY OR anchors it to an HONOURED target
-- (resbar for any; essential / utility / belowPlayer for host groups); absence of both = auto-stack. Keyed on
-- the KEY (not live resolution) so an anchored group never flickers to auto-stack while its target is absent.
local function IsAnchoredKey(g, a)
    if not a then return false end
    if ns.IsResourceBarAnchorKey and ns.IsResourceBarAnchorKey(a) then return true end
    local dest = GroupDest(g)
    if dest ~= "buff" and dest ~= "bar" then return false end
    return (ns.IsCDMGroupAnchorKey and ns.IsCDMGroupAnchorKey(a))
        or (ns.IsBelowAnchorKey and ns.IsBelowAnchorKey(a)) or false
end
local function IsFree(g)
    if GroupTabPos(g) ~= nil then return true end
    return IsAnchoredKey(g, GroupTabGet(g, "anchorTo"))
end

-- A frame's named-point coordinates in SCREEN pixels (effective scale folded in), or nil if unpositioned.
local function ScreenPoint(f, point)
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    local s = f:GetEffectiveScale()
    if not (l and b and w and h and s) then return nil end
    local x = point:find("LEFT") and l or (point:find("RIGHT") and (l + w) or (l + w / 2))
    local y = point:find("BOTTOM") and b or (point:find("TOP") and (b + h) or (b + h / 2))
    return x * s, y * s
end

-- Re-impose each positioned group's anchor. A tab anchorTo of resbar:* / essential / utility / belowPlayer
-- resolves (EngineAnchorFrame) to a live frame the group rides (relPos side + posX/posY offset) — e.g. Buffs
-- under the last resource bar, or above the Utility block. Anything unresolved is a plain screen-centre offset
-- from the tab posX/posY. Idempotent; called last in a build + the cheap refresh path.
local function ApplyFreePositions()
    for _, g in ipairs(groupFrames) do
        local a  = GroupTabGet(g, "anchorTo")
        local rf = EngineAnchorFrame(g, a)
        if rf then
            local x, y = GroupTabPos(g)
            local pts  = RELPOS_POINTS[GroupTabGet(g, "relPos") or "above"] or RELPOS_POINTS.above
            local bx, by
            if rf then bx, by = ScreenPoint(rf, pts[2]) end   -- NB: keep as an if, not `rf and ScreenPoint(...)` (that `and` truncates the 2nd return)
            local gs   = g:GetEffectiveScale()
            g:ClearAllPoints()
            if bx and gs and gs > 0 then
                -- Pin at the target's edge in ABSOLUTE UIParent coords, NOT a live SetPoint into rf: the engine
                -- groups are children of `container` and the target (a resource bar / essential block) can anchor
                -- back into that chain, so a live SetPoint trips WoW's circular-dependency guard. The deferred
                -- ReapplyPositions poke (on every (re)build) keeps it tracking the target.
                g:SetPoint(pts[1], UIParent, "BOTTOMLEFT", bx / gs + (x or 0), by / gs + (y or 0))
            else
                g:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0)   -- target absent -> screen centre
            end
        else
            local x, y = GroupTabPos(g)
            if x then
                g:ClearAllPoints()
                g:SetPoint("CENTER", UIParent, "CENTER", x, y)
            end
        end
    end
end

-- Stack the AUTO groups in the container, reading each group's cached size (measured above). Free
-- (tab-positioned) groups are skipped here and pinned to UIParent by ApplyFreePositions instead.
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

-- ── Multi-group materialisation (own-draw cooldowns) ────────────────────────────────────────────
-- The engine reuses the NATIVE CDMGroups group model as its layout source: ONE engine group per configured
-- display group (Group 1, 2, … ; "Unused" = 0 is not rendered). The engine renders by cdmID, so we keep a
-- PERSISTENT spellId->cdmID cache per dest. The cache is deliberately BROAD:
--   * keyed by BOTH the DISPLAY spellId AND the STABLE BASE spellId — CDMGroups members (I.GroupRows) are
--     BASE-keyed, so a transformed/override cooldown (base ~= display) must resolve via the base key;
--   * built from BOTH own-draw categories (Essential AND Utility) and the AVAILABLE superset, NOT just
--     gs.category's configured set — CDMGroups lets you assign a cooldown ACROSS categories into a group
--     (e.g. a Utility cooldown like Invisibility placed in the Essential group), so a cross-category member
--     resolves only if the map spans both. Otherwise that member (and its whole row) silently vanishes.
-- GroupRows is the gate on WHICH members render, so a broad map adds no spurious icons. Refreshed whenever
-- spellIds resolve (out of combat) and never dropped, so a rebuild triggered IN COMBAT (an aura change flips
-- the buff/bar sig and re-buckets every category) still resolves members from the cache.
local cdmMaps = {}   -- dest -> { [spellId] = cdmID }
local ownDrawCats    -- the Essential + Utility category enums, harvested from SPEC (own-draw = has trackerDest)
local function OwnDrawCategories()
    if not ownDrawCats then
        ownDrawCats = {}
        for _, g in ipairs(SPEC.groups) do
            if g.trackerDest and g.category ~= nil then ownDrawCats[#ownDrawCats + 1] = g.category end
        end
    end
    return ownDrawCats
end
local function RefreshCdmMap(gs)
    local dest = gs.trackerDest
    local map = cdmMaps[dest]
    -- Out of combat REBUILD FRESH: display spellIds resolve now, so a talent/spec rebind (spellId -> a NEW
    -- cdmID) is reflected and orphan sids are pruned (no unbounded growth). In combat KEEP the cache: the
    -- display ids are secret then, so a rebuild triggered by an aura change still resolves members from it.
    if (not map) or (not InCombatLockdown()) then
        map = {}; cdmMaps[dest] = map
        local A = ns.CDMAnchor
        for _, cat in ipairs(OwnDrawCategories()) do
            for _, cdmID in ipairs(E.Blob.GetTracked(cat, true)) do   -- available superset, across BOTH own-draw cats
                local info = E.Blob.GetInfo(cdmID)
                if info and info.isKnown ~= false then
                    local sid  = A and A.NativeFrameSpellId     and A.NativeFrameSpellId({ cooldownInfo = info })
                    local base = A and A.NativeFrameBaseSpellId and A.NativeFrameBaseSpellId({ cooldownInfo = info })
                    if sid  and map[sid]  == nil then map[sid]  = cdmID end   -- first category wins on any collision
                    if base and map[base] == nil then map[base] = cdmID end
                end
            end
        end
    end
    return map
end

-- name -> tracker descriptor for a dest (engine mode only): lets a group host the CDM trackers assigned to
-- it alongside its cooldowns, matching how the native CDMGroups renders cooldowns + trackers together.
local function TrackerMapFor(dest)
    if not (ns.CDMMode and ns.CDMMode.IsEngine() and dest
        and ns.CDMAnchor and ns.CDMAnchor.GetIconDescriptors) then return nil end
    local m = {}
    for _, td in ipairs(ns.CDMAnchor.GetIconDescriptors(dest)) do
        if td.name then m[td.name] = td end
    end
    return m
end

-- Grow-direction GRID packer for an own-icon group, mirroring the native CDMGroups layout (Engine.lua:1698):
-- per-group growDir/spacing, multi-ROW via I.GroupRows; LEFT/UP reverse the pack axis; horizontal grows stack
-- rows DOWN, vertical grows stack RIGHT; relPos drives the per-row cross alignment. Positions each member
-- relative to g's TOPLEFT and sizes g to the whole block (the container then places g).
local HORIZONTAL_GROW = { RIGHT = true, LEFT = true, CENTER_H = true }
local function ArrangeIconGroup(g)
    local I, groupId = g._I, g._groupId
    local grow       = (I and I.GGet(groupId, "growDir")) or "CENTER_H"
    local spacing    = (I and I.GGet(groupId, "spacing")) or 4
    local rp         = (I and I.GGet(groupId, "relPos"))  or "above"
    local horizontal = HORIZONTAL_GROW[grow] == true
    local reverse    = (grow == "LEFT" or grow == "UP")
    local alignTop   = (rp == "below" or rp == "bottomleft" or rp == "bottomright")
    -- An entry is either a live frame OR a Static-Display PLACEHOLDER ({ ph = true, w, h }) reserving a slot
    -- for an absent member — measured like a frame, but positioned as nothing.
    local function EntrySize(f) if f.ph then return f.w or 44, f.h or 44 end return f:GetWidth(), f:GetHeight() end
    -- Measure each row: MAIN extent (packed along the grow axis) + CROSS extent (max thickness).
    local laid, maxMain, sumCross = {}, 0, 0
    for _, row in ipairs(g._iconRows or {}) do
        local mainExt, crossExt = 0, 0
        for i, f in ipairs(row) do
            local w, h  = EntrySize(f)
            local main  = horizontal and w or h
            local cross = horizontal and h or w
            mainExt = mainExt + main + (i > 1 and spacing or 0)
            if cross > crossExt then crossExt = cross end
        end
        laid[#laid + 1] = { row = row, mainExt = mainExt, crossExt = crossExt }
        if mainExt > maxMain then maxMain = mainExt end
        sumCross = sumCross + crossExt + (#laid > 1 and spacing or 0)
    end
    -- Place: pack along MAIN (reversed for LEFT/UP), stack rows along CROSS, per-row cross alignment.
    local crossCursor = 0
    for _, lr in ipairs(laid) do
        local mainCursor = reverse and lr.mainExt or 0
        for _, f in ipairs(lr.row) do
            local w, h = EntrySize(f)
            local main = horizontal and w or h
            if reverse then mainCursor = mainCursor - main end
            local x, y
            if horizontal then
                x = mainCursor
                y = -crossCursor - (alignTop and 0 or (lr.crossExt - h))
            else
                x = crossCursor + (alignTop and 0 or (lr.crossExt - w))
                y = -mainCursor
            end
            if not f.ph then                              -- placeholder reserves the slot but pins nothing
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", g, "TOPLEFT", x, y)
            end
            if reverse then mainCursor = mainCursor - spacing else mainCursor = mainCursor + main + spacing end
        end
        crossCursor = crossCursor + lr.crossExt + spacing
    end
    local boxW = horizontal and maxMain or sumCross
    local boxH = horizontal and sumCross or maxMain
    E.Group.SetDefaultSize(g, math.max(boxW, 1), math.max(boxH, 1))
end

-- Materialise ONE engine group for a configured display group, laid out as a GRID (I.GroupRows). Each member
-- is a cooldown E.Icon (cdmID via the cache) or a hosted CDM tracker (by name, sized to the group).
local function MaterializeIconGroup(gs, dest, I, groupId, sidMap, trackerMap)
    local g = E.Group.Acquire()
    E.Group.Setup(g, gs)
    g.catKey = dest .. ":" .. groupId   -- per-group key (tab-driven posX/posY are keyed by this)
    g._groupId, g._I = groupId, I        -- so ArrangeIconGroup reads this group's growDir/spacing/relPos
    g:SetParent(container)
    local iconW = I.GGet(groupId, "iconW") or 44
    local iconH = I.GGet(groupId, "iconH") or 44
    local staticDisplay = I.GGet(groupId, "staticDisplay") == true   -- reserve a slot for absent/hidden members
    local rows, placeholders = {}, 0
    for _, srcRow in ipairs(I.GroupRows(groupId)) do
        local row = {}
        for _, member in ipairs(srcRow) do
            local cdmID = sidMap[member]
            local td    = trackerMap and trackerMap[member]
            if cdmID then
                local f = E.Icon.Acquire()
                f._dest = dest
                E.Icon.Setup(f, cdmID)
                f:SetParent(g)
                g.children[#g.children + 1] = f
                row[#row + 1] = f
            elseif td and td.frame and td.frame:IsShown() then
                if td.setSize then td.setSize(iconW, iconH) else td.frame:SetSize(iconW, iconH) end
                td.frame:SetAlpha(1)
                td.frame:SetParent(g)
                g.trackers[#g.trackers + 1] = td
                row[#row + 1] = td.frame
            elseif staticDisplay then
                row[#row + 1] = { ph = true, w = iconW, h = iconH }   -- absent cooldown / hidden tracker: reserve slot
                placeholders = placeholders + 1
            end
        end
        if #row > 0 then rows[#rows + 1] = row end
    end
    g._iconRows = rows
    if #g.children > 0 or #g.trackers > 0 or placeholders > 0 then
        ArrangeIconGroup(g)
        groupFrames[#groupFrames + 1] = g
    else
        E.Group.Release(g)
    end
end

-- ── Multi-group hosting (buffs / bars) ──────────────────────────────────────────────────────────
-- Buffs/Bars HOST the native pool frames. To split them into the configured groups we key each SHOWN frame
-- by its display spellId (NativeFrameSpellId — readable in combat for buff/bar frames, unlike the aura's
-- secret duration/stacks; this mirrors BuffGroups.RefreshLayout's frameOf map) and assign it to its group.
local shownBuffScratch, shownBarScratch = {}, {}
local function ShownFrameMap(gs)
    local map = {}
    if not (ns.CDMMode and ns.CDMMode.IsEngine()) or InEditMode() then return map end
    local A = ns.CDMAnchor
    local mod     = gs.isBuff and ns.BuffGroups or ns.BarGroups
    local enum    = gs.isBuff and (A and A.EnumBuffIcons) or (mod and mod.EnumBarFrames)
    local scratch = gs.isBuff and shownBuffScratch or shownBarScratch
    -- Key each frame with the SAME resolver the module uses to classify members (FrameSpellId: display id ->
    -- GetSpellID -> cooldownInfo/linkedSpellIDs), PLUS the transform-stable base id — so a member frozen in the
    -- config under any of those keys resolves, and a combat-secret / transform buff isn't dropped (it would
    -- otherwise be sig-folded via the base id yet missing here, going invisible until combat ends).
    local resolve = (mod and mod.FrameSpellId) or (A and A.NativeFrameSpellId)
    if not (enum and resolve) then return map end
    for _, nf in ipairs(enum(scratch)) do
        if nf.IsShown and nf:IsShown() then
            local sid  = resolve(nf)
            local base = A and A.NativeFrameBaseSpellId and A.NativeFrameBaseSpellId(nf)
            if sid  then map[sid]  = nf end
            if base then map[base] = nf end
        end
    end
    return map
end

-- Materialise ONE engine group for a configured buff/bar display group: its SHOWN members in config order
-- (GetGroupBuffs). ArrangeGroup then adopts + styles the hosted frames. Kept only if it has a shown member.
local function MaterializeHostGroup(gs, dest, groupId, mod, frameOf)
    local g = E.Group.Acquire()
    E.Group.Setup(g, gs)
    g.catKey = dest .. ":" .. groupId
    g._relPos = (mod.GGet and mod.GGet(groupId, "relPos")) or "above"   -- drives row cross-alignment in ArrangeGroup
    g._spacing = mod.GGet and mod.GGet(groupId, "spacing")              -- honour the group's own spacing (not the SPEC default)
    g:SetParent(container)
    local staticDisplay = mod.GGet and mod.GGet(groupId, "staticDisplay") == true   -- reserve inactive slots
    local bucket = gs.isBuff and g.nativeBuffs or g.nativeBars
    local shown = 0
    for _, member in ipairs(mod.GetGroupBuffs(groupId)) do
        local nf = frameOf[member]
        if nf then bucket[#bucket + 1] = nf; shown = shown + 1
        elseif staticDisplay then bucket[#bucket + 1] = { ph = true, sid = member } end   -- inactive: reserve slot
    end
    -- Keep the group if it hosts a shown member OR (static) reserves any slot; but not a purely-empty group.
    if shown > 0 or (staticDisplay and #bucket > 0) then
        ArrangeGroup(g)
        groupFrames[#groupFrames + 1] = g
    else
        E.Group.Release(g)
    end
end

-- Full teardown + rebuild, bottom-up: each group is populated + arranged (so its size is final) BEFORE
-- the container stacks them. E.Icon.ReleaseAll is the single owner of icon teardown.
local function BuildLayout()
    if not (container and E.Blob and E.Icon and E.Group) then return end
    E.Icon.ReleaseAll()
    ReleaseGroups()
    for _, gs in ipairs(SPEC.groups) do
        if gs.category ~= nil then
            if gs.isBuff or gs.isBar then
                -- Hosted native frames: ONE engine group per configured buff/bar display group.
                local mod  = gs.isBuff and ns.BuffGroups or ns.BarGroups
                local dest = gs.isBuff and "buff" or "bar"
                if mod and mod.GroupList and mod.GetGroupBuffs then
                    -- Classify the CURRENT displayed set BEFORE reading GroupOf: an unassigned member lands in
                    -- Group 1 only if the module reports it displayed (mod.IsDisplayed / displayedCache). While the
                    -- module is disabled (engine mode owns it) its own ticker only refreshes that cache when its
                    -- config panel is open, so without this the bars/buffs default to Unused and never get hosted.
                    -- On a real change, forward it to the config strip (onDisplayedChanged) — the engine pre-empts
                    -- the module's ticker, so it must notify. DEFERRED so we never rebuild the config UI mid-layout.
                    if mod.RefreshDisplayedCache and mod.RefreshDisplayedCache() and mod.onDisplayedChanged then
                        local cb = mod.onDisplayedChanged
                        C_Timer.After(0, function() if type(cb) == "function" then cb() end end)
                    end
                    local frameOf = ShownFrameMap(gs)
                    for _, grp in ipairs(mod.GroupList()) do
                        if grp.id and grp.id ~= 0 then
                            MaterializeHostGroup(gs, dest, grp.id, mod, frameOf)
                        end
                    end
                else
                    -- Fallback (module not ready): the single-group hosting of every shown frame.
                    local g = E.Group.Acquire()
                    E.Group.Setup(g, gs)
                    g:SetParent(container)
                    PopulateGroup(g, gs)
                    if #g.nativeBuffs > 0 or #g.nativeBars > 0 then
                        ArrangeGroup(g)
                        groupFrames[#groupFrames + 1] = g
                    else
                        E.Group.Release(g)
                    end
                end
            else
                -- Own-draw cooldowns: ONE engine group per configured CDMGroups display group (multi-group).
                local I = gs.trackerDest and ns.CDMGroups and ns.CDMGroups[gs.trackerDest]
                if I and I.GroupList and I.GetGroupBuffs then
                    local sidMap     = RefreshCdmMap(gs)
                    local trackerMap = TrackerMapFor(gs.trackerDest)
                    for _, grp in ipairs(I.GroupList()) do
                        if grp.id and grp.id ~= 0 then
                            MaterializeIconGroup(gs, gs.trackerDest, I, grp.id, sidMap, trackerMap)
                        end
                    end
                else
                    -- Fallback (no CDMGroups instance): single-group render of the whole category.
                    local g = E.Group.Acquire()
                    E.Group.Setup(g, gs)
                    g:SetParent(container)
                    PopulateGroup(g, gs)
                    if #g.children > 0 or #g.trackers > 0 then
                        ArrangeGroup(g)
                        groupFrames[#groupFrames + 1] = g
                    else
                        E.Group.Release(g)
                    end
                end
            end
        end
    end
    ArrangeContainer()
    ApplyFreePositions()                   -- positioned groups: pinned to UIParent, the last word on position
    if E.Icon.RefreshPressPoll then E.Icon.RefreshPressPoll() end   -- (dis)arm the press-overlay poller
    if E.Icon.RefreshTierPoll  then E.Icon.RefreshTierPoll()  end   -- (dis)arm the timer-threshold size poller
    if ns.CastBar and ns.CastBar.NotifyAnchorChanged then ns.CastBar.NotifyAnchorChanged() end   -- cast bar re-adapts to the engine group
    if E.Resource and E.Resource.Reposition then E.Resource.Reposition() end   -- resource bars re-anchor to the (pooled) group frames
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
            if gs.isBuff then
                -- Fold the SHOWN native buff frames (by combat-stable identity) so a buff coming/going flips
                -- the sig and re-hosts. AuraDispatch (below) triggers this; the fixed event list doesn't cover
                -- auras. Gated on EditMode to match CollectShownBuffFrames (no preview sample frames).
                local A = ns.CDMAnchor
                if A and A.EnumBuffIcons and A.NativeFrameSpellId and not InEditMode()
                   and ns.CDMMode and ns.CDMMode.IsEngine() then   -- only fold hosted frames (engine mode)
                    for _, nf in ipairs(A.EnumBuffIcons(nativeBuffEnum)) do
                        if nf.IsShown and nf:IsShown() then
                            sigParts[#sigParts + 1] = "B" .. BuffFrameKey(nf)
                        end
                    end
                end
            elseif gs.isBar then
                -- Fold the SHOWN native bar frames (combat-stable identity, prefix "R" so bar keys can never
                -- collide with a buff "B" key) so a bar coming/going flips the sig and re-hosts. Same aura
                -- trigger as buffs (AuraDispatch below); gated on EditMode to match CollectShownBarFrames.
                local BG, A = ns.BarGroups, ns.CDMAnchor
                if BG and BG.EnumBarFrames and A and A.NativeFrameSpellId and not InEditMode()
                   and ns.CDMMode and ns.CDMMode.IsEngine() then   -- only fold hosted frames (engine mode)
                    for _, nf in ipairs(BG.EnumBarFrames(nativeBarEnum)) do
                        if nf.IsShown and nf:IsShown() then
                            sigParts[#sigParts + 1] = "R" .. BuffFrameKey(nf)
                        end
                    end
                end
            else
                for _, cdmID in ipairs(E.Blob.GetTracked(gs.category, false)) do
                    local info = E.Blob.GetInfo(cdmID)
                    sigParts[#sigParts + 1] = cdmID .. ((info and info.isKnown ~= false) and "+" or "-")
                end
                -- Fold each cooldown's GROUP so re-assigning it (or creating a group) forces a rebuild.
                -- GroupOf is a pure read (no order-freeze mutation, unlike GetGroupBuffs); it uses the cached
                -- spellId (unresolved in combat -> folds nothing, but assignments don't change in combat).
                local I = gs.trackerDest and ns.CDMGroups and ns.CDMGroups[gs.trackerDest]
                local map = cdmMaps[gs.trackerDest]
                if I and I.GroupOf and map then
                    for sid, cdmID in pairs(map) do
                        sigParts[#sigParts + 1] = "G" .. cdmID .. ":" .. tostring(I.GroupOf(sid))
                    end
                end
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
    -- Fold the shared style epoch: a config EDIT bumps it (ns.BumpStyleEpoch, which also pokes our
    -- ScheduleRebuild), so folding it here flips the sig on any edit -> a FULL BuildLayout (re-style +
    -- re-arrange), not just the cheap RefreshAll path. Without this, per-icon/per-group style + layout edits
    -- (border, timer/stack font, growDir, spacing, group re-assignment…) only apply on a membership change or
    -- /reload — the phase-5b live-refresh would be inert. Mirrors the native modules (Engine/BuffGroups sigs).
    sigParts[#sigParts + 1] = "E" .. (ns.StyleEpoch or 0)
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

-- Tracked buffs come/go via aura changes, which the fixed event list above doesn't cover. Route the SHARED
-- coalesced player-aura broadcaster to a REBUILD — ComputeSig folds the active-buff set, so a buff up/down
-- flips the sig and re-collects. SECRET-SAFE: the callback only schedules; it never reads aura data. Acts
-- only while the engine is shown (native mode = no-op) — and in engine mode the ceded CDMGroups/BuffGroups
-- aura callbacks no-op, so this adds no net aura fan-out.
if ns.AuraDispatch and ns.AuraDispatch.Register then
    ns.AuraDispatch.Register("player", function() if shown then ScheduleRebuild() end end)
end

-- ── Show / hide (driven by the engine's mode-driven auto-show) ───────────────────────────────────
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
    if E.Icon.RefreshPressPoll then E.Icon.RefreshPressPoll() end   -- no active icons now -> stop the poller
    if E.Icon.RefreshTierPoll  then E.Icon.RefreshTierPoll()  end
    ReleaseGroups()   -- Group.Release re-parents every hosted tracker back to UIParent (single owner of that handoff)
    if container then container:Hide() end
    if E.Resource and E.Resource.HideWidgets then E.Resource.HideWidgets() end   -- P4c class resources
end

-- ── Public surface (Core/Mode.lua drives Show/Hide) ──────────────────────────────────────────────
E.Layout = E.Layout or {}
function E.Layout.IsShown()         return shown end
function E.Layout.GetSpec()         return SPEC end
function E.Layout.ScheduleRebuild() ScheduleRebuild() end
function E.Layout.HideWidgets()     HideWidgets() end
-- Cheap re-pin of the positioned groups (no rebuild). The resource module pokes this after a bar (re)build
-- so a group anchored to "resbar:*" re-resolves once its bar appears / disappears.
function E.Layout.ReapplyPositions() if shown then ApplyFreePositions() end end
-- The live engine group frame for a catKey ("essential:1" / "utility:1" / …), or nil — the cast bar uses it
-- to anchor to / adapt its width from the engine's OWN group in engine mode (the native viewer it would
-- otherwise use is alpha-masked and sits at the native layout position, not where the engine draws).
function E.Layout.GroupFrame(catKey)
    for _, g in ipairs(groupFrames) do
        if g.catKey == catKey then return g end
    end
    return nil
end
-- Append every live engine group frame belonging to `dest` ("essential"/"utility"/"buff"/"bar") to `out`.
-- The Fader uses this to fade the engine's OWN CDM frames in engine mode: fading a group frame cascades alpha
-- to its icons + hosted trackers + adopted native frames (WoW alpha is multiplicative and nothing sets
-- SetIgnoreParentAlpha), and the engine never re-forces a group frame's alpha, so the Fader wins. Groups are
-- pooled — always enumerate live (call this every tick), never cache the result.
function E.Layout.CollectGroupFrames(dest, out, fg)
    out = out or {}
    if not dest then return out end
    local prefix = dest .. ":"
    local plen = #prefix
    for _, g in ipairs(groupFrames) do
        local ck = g.catKey
        if ck and ck:sub(1, plen) == prefix then
            -- fg (optional per-group fade-scope table): a group id set to false is EXCLUDED from the fade.
            if not fg or fg[ck:sub(plen + 1)] ~= false then out[#out + 1] = g end
        end
    end
    return out
end

-- Show/hide entry point for the engine widgets (driven by Core/Mode.lua on the mode switch).
function E.Layout.SetShown(v)
    if v then
        EnsureShown()
    else
        HideWidgets()
    end
end

-- A profile switch / import wholesale-replaces the saved config: force a full rebuild so the NEW
-- profile's group positions are read (lastSig = nil guarantees BuildLayout, not the cheap path). The
-- deferred rebuild runs after ns.db.profile is repointed + CfgInit re-merged, so ApplyFreePositions
-- reads the right profile.
ns.RegisterReloadHook(function()
    if shown then lastSig = nil; ScheduleRebuild() end
end)
