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
    -- ping-pong) if the widgets are shown via /uucdmwidgets or the designer. Mirrors the trackerDest gate.
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
    local main, cross = 0, 0
    -- w = main-axis extent, h = cross-axis extent. Square callers pass one value (h defaults to w); the
    -- own icons pass their CONFIG size (iconW/iconH may differ) so a non-square icon lays out correctly.
    local function Place(f, w, h)
        w = w or gs.size; h = h or w
        if main > 0 then main = main + gs.spacing end   -- gap only BETWEEN elements (no leading/trailing)
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
    for _, nf in ipairs(g.nativeBuffs) do
        if main > 0 then main = main + gs.spacing end
        if ns.CDMAnchor and ns.CDMAnchor.AdoptNativeTo then
            ns.CDMAnchor.AdoptNativeTo(nf, g, main, 0, gs.size, gs.size)
        end
        -- Blizzard runs a per-FRAME alpha fade on the buff pool frames (aura in/out); the reparent doesn't
        -- reset it and the viewer mask only guards the viewer, so clear a lingering sub-1 alpha or an adopted
        -- buff could render dim. SetAlpha is taint-safe. Mirrors the hosted-tracker SetAlpha(1) above.
        if nf.GetAlpha and nf:GetAlpha() ~= 1 then nf:SetAlpha(1) end
        main  = main + gs.size
        cross = math.max(cross, gs.size)
    end
    -- Hosted native bar frames (TrackedBar): same model as buffs — ADOPT the native BuffBar pool frames so
    -- the masked BuffBarCooldownViewer's frames still render (Blizzard fills their secret value/duration
    -- C-side). Bars are WIDE rows, so host them at their NATIVE size (pass no w,h -> AdoptNativeTo won't
    -- resize) and flow per the group direction (column by default -> a vertical stack of bars).
    for _, nf in ipairs(g.nativeBars) do
        if main > 0 then main = main + gs.spacing end
        local bw, bh = BarSize(nf)
        if ns.CDMAnchor and ns.CDMAnchor.AdoptNativeTo then
            local x = horizontal and main or 0
            local y = horizontal and 0 or -main
            ns.CDMAnchor.AdoptNativeTo(nf, g, x, y)   -- no w,h: keep Blizzard's native bar geometry
        end
        if nf.GetAlpha and nf:GetAlpha() ~= 1 then nf:SetAlpha(1) end
        main  = main + (horizontal and bw or bh)
        cross = math.max(cross, horizontal and bh or bw)
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

-- ── Multi-group materialisation (own-draw cooldowns) ────────────────────────────────────────────
-- The engine reuses the NATIVE CDMGroups group model as its layout source: ONE engine group per configured
-- display group (Group 1, 2, … ; "Unused" = 0 is not rendered). Members are keyed by DISPLAY spellId (secret
-- in combat) while the engine renders by cdmID — so we keep a PERSISTENT spellId->cdmID cache per dest,
-- refreshed whenever a spellId resolves (out of combat) and never dropped, so a rebuild triggered IN COMBAT
-- (an aura change flips the buff/bar sig and re-buckets every category) still resolves members from the cache.
local cdmMaps = {}   -- dest -> { [spellId] = cdmID }
local function RefreshCdmMap(gs)
    local dest = gs.trackerDest
    local map = cdmMaps[dest]; if not map then map = {}; cdmMaps[dest] = map end
    for _, cdmID in ipairs(E.Blob.GetTracked(gs.category, false)) do
        local info = E.Blob.GetInfo(cdmID)
        if info and info.isKnown ~= false then
            local A = ns.CDMAnchor
            local sid = A and A.NativeFrameSpellId and A.NativeFrameSpellId({ cooldownInfo = info })
            if sid then map[sid] = cdmID end
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
-- relative to g's TOPLEFT and sizes g to the whole block (the container / designer then places g).
local HORIZONTAL_GROW = { RIGHT = true, LEFT = true, CENTER_H = true }
local function ArrangeIconGroup(g)
    local I, groupId = g._I, g._groupId
    local grow       = (I and I.GGet(groupId, "growDir")) or "CENTER_H"
    local spacing    = (I and I.GGet(groupId, "spacing")) or 4
    local rp         = (I and I.GGet(groupId, "relPos"))  or "above"
    local horizontal = HORIZONTAL_GROW[grow] == true
    local reverse    = (grow == "LEFT" or grow == "UP")
    local alignTop   = (rp == "below" or rp == "bottomleft" or rp == "bottomright")
    -- Measure each row: MAIN extent (packed along the grow axis) + CROSS extent (max thickness).
    local laid, maxMain, sumCross = {}, 0, 0
    for _, row in ipairs(g._iconRows or {}) do
        local mainExt, crossExt = 0, 0
        for i, f in ipairs(row) do
            local w, h  = f:GetWidth(), f:GetHeight()
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
            local w, h = f:GetWidth(), f:GetHeight()
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
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", g, "TOPLEFT", x, y)
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
    g.catKey = dest .. ":" .. groupId   -- per-group key (Phase 3 designer positions migrate to this)
    g._groupId, g._I = groupId, I        -- so ArrangeIconGroup reads this group's growDir/spacing/relPos
    g:SetParent(container)
    local iconW = I.GGet(groupId, "iconW") or 44
    local iconH = I.GGet(groupId, "iconH") or 44
    local rows = {}
    for _, srcRow in ipairs(I.GroupRows(groupId)) do
        local row = {}
        for _, member in ipairs(srcRow) do
            local cdmID = sidMap[member]
            if cdmID then
                local f = E.Icon.Acquire()
                f._dest = dest
                E.Icon.Setup(f, cdmID)
                f:SetParent(g)
                g.children[#g.children + 1] = f
                row[#row + 1] = f
            elseif trackerMap and trackerMap[member] then
                local td = trackerMap[member]
                if td.frame and td.frame:IsShown() then
                    if td.setSize then td.setSize(iconW, iconH) else td.frame:SetSize(iconW, iconH) end
                    td.frame:SetAlpha(1)
                    td.frame:SetParent(g)
                    g.trackers[#g.trackers + 1] = td
                    row[#row + 1] = td.frame
                end
            end
        end
        if #row > 0 then rows[#rows + 1] = row end
    end
    g._iconRows = rows
    if #g.children > 0 or #g.trackers > 0 then
        ArrangeIconGroup(g)
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
                -- Hosted native frames: still ONE group per category (buff/bar multi-group is Phase 4).
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

-- Tracked buffs come/go via aura changes, which the fixed event list above doesn't cover. Route the SHARED
-- coalesced player-aura broadcaster to a REBUILD — ComputeSig folds the active-buff set, so a buff up/down
-- flips the sig and re-collects. SECRET-SAFE: the callback only schedules; it never reads aura data. Acts
-- only while the engine is shown (native mode = no-op) — and in engine mode the ceded CDMGroups/BuffGroups
-- aura callbacks no-op, so this adds no net aura fan-out.
if ns.AuraDispatch and ns.AuraDispatch.Register then
    ns.AuraDispatch.Register("player", function() if shown then ScheduleRebuild() end end)
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
