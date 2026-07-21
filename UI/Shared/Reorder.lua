-- UI/Shared/Reorder.lua
-- Two arrow buttons ( < > ) to move an item left/right within a row. A direction
-- is greyed out (disabled, dimmed) when the move is unavailable.
--
-- Usage:
--   local r = ns.ui.CreateReorder({
--       parent   = panel,
--       label    = "Move in row",
--       getState = function() return canLeft, canRight end,  -- booleans
--       onMove   = function(dir) ... end,                    -- dir = -1 / +1
--   })
--   r.frame
--   r.Refresh()   -- re-reads getState() to update the enabled/dimmed state

local _, ns = ...
ns.ui = ns.ui or {}

function ns.ui.CreateReorder(config)
    local parent   = config.parent
    local label    = config.label
    local getState = config.getState or function() return false, false end
    local onMove   = config.onMove   or function() end

    local result    = {}
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 24)

    local anchorRight = container
    local anchorPoint, gap = "LEFT", 0
    if label then
        local fs = container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
        fs:SetPoint("LEFT", container, "LEFT", 0, 0)
        fs:SetText(label)
        anchorRight, anchorPoint, gap = fs, "RIGHT", 10
    end

    local function Refresh()
        local canL, canR = getState()
        result.left.frame:SetEnabled(canL and true or false)
        result.left.frame:SetAlpha(canL and 1 or 0.4)
        result.right.frame:SetEnabled(canR and true or false)
        result.right.frame:SetAlpha(canR and 1 or 0.4)
    end
    result.Refresh = Refresh

    result.left = ns.ui.CreateButton({
        parent = container, label = "<", width = 26, height = 22,
        onClick = function() onMove(-1); Refresh() end,
    })
    result.right = ns.ui.CreateButton({
        parent = container, label = ">", width = 26, height = 22,
        onClick = function() onMove(1); Refresh() end,
    })
    result.left.frame:SetPoint("LEFT", anchorRight, anchorPoint, gap, 0)
    result.right.frame:SetPoint("LEFT", result.left.frame, "RIGHT", 6, 0)

    Refresh()
    result.frame = container
    return result
end

-- ── Shared inter-strip drag controller ────────────────────────────────────────
-- The BuffGroups-style drag (see Modules/BuffGroups/UI/ConfigWindow.lua), distilled into a
-- self-contained controller so a SET of reorder strips can hand tiles BETWEEN each other —
-- not just reorder within one strip. Strips that should accept each other's tiles share one
-- "drag group" (a plain table passed as opts.dragGroup); each registers itself into it.
--
-- While dragging, the lifted tile is reparented onto a top-level layer and follows the cursor
-- (one real moving icon — the others visibly slide); release is found by POLLING the mouse
-- button (not OnDragStop, which is flaky once a frame is reparented). The hovered strip opens
-- a one-slot gap at the insertion index; the others close theirs. On release the drop is
-- reported through the group: a move (same-strip reorder OR cross-strip) calls the source
-- strip's onMove(itemId, fromStrip, toStrip, holeIndex) when set, else its setOrder(idList)
-- (the within-strip fallback, e.g. the Free-icons grid which has no cross-strip target).
--
-- Each strip publishes a small interface into the group (strip._drag): cursorOver(), slotAt(),
-- relayout(dragId, hole), orderIds(). The controller is created lazily on the group and is the
-- ONLY owner of the shared drag layer + poll driver, so any number of groups coexist cleanly.
-- The drag layer + poll driver are MODULE-LEVEL singletons (created once, reused by every group).
-- The per-group controllers are recreated on each panel rebuild, so they must NOT own WoW frames
-- (frames are never GC'd → that leaked one driver+layer per row per rebuild). activeDragCtrl is the
-- controller currently dragging (only one drag at a time); the shared driver dispatches to it.
local sharedDragLayer, sharedDragDriver, activeDragCtrl

-- Top-level layer the lifted tile rides on (no scroll/strip clip). No mouse: the hover tests are
-- geometric, computed from the cursor position.
local function ensureDragLayer()
    if sharedDragLayer then return sharedDragLayer end
    sharedDragLayer = CreateFrame("Frame", nil, UIParent)
    sharedDragLayer:SetFrameStrata("TOOLTIP")
    sharedDragLayer:SetAllPoints(UIParent)
    return sharedDragLayer
end

-- The poll driver body: keeps firing even though the dragged tile is reparented. Moves the lifted
-- tile to the cursor, finds the hovered strip across the active group, reflows every strip (gap on
-- the hovered one only). Releasing the mouse ends the drag.
local function dragOnUpdate()
    local ctrl = activeDragCtrl
    if not (ctrl and ctrl.tile) then return end
    if not IsMouseButtonDown("LeftButton") then ctrl.stop(); return end
    local scale = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    if scale and scale > 0 and mx then
        ctrl.tile:ClearAllPoints()
        ctrl.tile:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / scale, my / scale)
    end
    local hovered, hole
    for _, s in ipairs(ctrl.group.strips) do
        local d = s._drag
        if d and s.frame:IsVisible() and d.cursorOver() then
            hovered = s; hole = d.slotAt(ctrl.dragId); break
        end
    end
    ctrl.hovered, ctrl.hole = hovered, hole
    for _, s in ipairs(ctrl.group.strips) do
        local d = s._drag
        if d then d.relayout(ctrl.dragId, (s == hovered) and hole or nil) end
    end
end

local function ensureDragDriver()
    if sharedDragDriver then return sharedDragDriver end
    sharedDragDriver = CreateFrame("Frame")
    sharedDragDriver:Hide()
    sharedDragDriver:SetScript("OnUpdate", dragOnUpdate)
    return sharedDragDriver
end

-- A drag group's controller: a cheap (GC-able) table that binds the SHARED layer/driver to THIS
-- group's strips, so recreating it per panel rebuild leaks nothing.
local function EnsureDragController(group)
    if group._ctrl then return group._ctrl end
    local ctrl = { group = group }
    group._ctrl = ctrl

    -- Begin a drag: lift `tile` (belonging to `strip`, item id `dragId`) onto the shared layer so
    -- it floats above every panel and is never clipped.
    function ctrl.start(strip, tile, dragId)
        ctrl.tile, ctrl.dragId, ctrl.fromStrip, ctrl.hovered, ctrl.hole = tile, dragId, strip, nil, nil
        tile._dragOrigParent = tile:GetParent()
        tile._dragOrigStrata = tile:GetFrameStrata()   -- restore on drop (else it sticks at MEDIUM, behind the DIALOG window)
        tile:SetParent(ensureDragLayer())
        tile:SetFrameStrata("TOOLTIP")
        tile:Raise()
        activeDragCtrl = ctrl
        ensureDragDriver():Show()
    end

    -- End a drag (idempotent — the poll can fire after a stray OnDragStop). Put the tile back under
    -- its strip (restoring its original strata) so the rebuild reclaims it, then report the drop:
    --   * dropped on a strip in the group  -> a cross-strip move (onMove) or a same-strip reorder
    --                                          (setOrder) at the hovered slot;
    --   * dropped into empty space          -> nothing moves (the rebuilds snap it home).
    function ctrl.stop()
        local tile = ctrl.tile
        if not tile then return end
        if sharedDragDriver then sharedDragDriver:Hide() end
        tile:SetParent(tile._dragOrigParent or UIParent)
        tile:SetFrameStrata(tile._dragOrigStrata or "MEDIUM")
        local fromStrip, dragId, hovered, hole = ctrl.fromStrip, ctrl.dragId, ctrl.hovered, ctrl.hole
        ctrl.tile, ctrl.dragId, ctrl.fromStrip, ctrl.hovered, ctrl.hole = nil, nil, nil, nil, nil
        if activeDragCtrl == ctrl then activeDragCtrl = nil end
        if dragId and hovered then
            if hovered == fromStrip then
                -- Same strip: prefer the drop callback; else reorder the id list ourselves.
                if fromStrip._onMove then
                    fromStrip._onMove(dragId, fromStrip, hovered, hole or 0)
                elseif fromStrip._setOrder then
                    local d = fromStrip._drag
                    local ids, cur = d.orderIds(), nil
                    for i, v in ipairs(ids) do if v == dragId then cur = i break end end
                    if cur then
                        table.remove(ids, cur)
                        local at = math.max(1, math.min(#ids + 1, (hole or 0) + 1))
                        table.insert(ids, at, dragId)
                        fromStrip._setOrder(ids)
                    end
                end
            else
                -- Cross-strip: ask the SOURCE strip to move its tile into the target at the hole.
                if fromStrip._onMove then
                    fromStrip._onMove(dragId, fromStrip, hovered, hole or 0)
                end
            end
        end
        -- Rebuild every strip in the group so they re-read their (possibly changed) order.
        for _, s in ipairs(group.strips) do if s.RebuildStrip then s.RebuildStrip() end end
    end

    return ctrl
end

-- ── Drag-to-reorder icon strip ────────────────────────────────────────────────
-- A horizontal strip of icon tiles the user drags to reorder — and, when several strips share
-- a `dragGroup`, to move tiles BETWEEN strips. While dragging, the held tile follows the cursor
-- on a top-level layer and the others slide over live; release commits the order. Empty -> a
-- centred grey "no icons" hint (when a fixed width is given) or a left-aligned one (auto width).
--
-- Usage:
--   local s = ns.ui.CreateIconReorderStrip({
--       parent    = host,
--       getIcons  = function() return { { id = "...", texture = 12345, custom = true }, -- pen edits + X deletes
--                                        { id = "...", texture = 99, nav = "Potion Tracker" }, ... } end, -- pen navigates
--       setOrder  = function(idList) ... end,
--       emptyText = L["No icons"],
--       width     = 230,   -- optional: fixed width (else auto-sizes to the icons)
--       iconSize  = 32,    -- optional
--       onAdd          = function() ... end,        -- optional: shows a trailing "+" tile
--       canAdd         = function() return bool end, -- optional: hide "+" when false (row full)
--       noDrag         = true,                       -- optional: tiles are fixed (no reorder drag)
--       wrap           = true,                        -- optional: wrap tiles into a grid (needs width)
--       rows           = 10,                          -- optional: strip is this many rows tall
--       onRemoveCustom = function(id) ... end,       -- optional: an X on custom items
--       onEditCustom   = function(id) ... end,       -- optional: a pen on custom items
--       onNavigate     = function(navTarget) ... end, -- optional: the pen on `nav` (addon) items
--       dragGroup      = <table>,                     -- optional: shared by strips that may swap tiles
--       onMove         = function(itemId, fromStrip, toStrip, holeIndex) ... end, -- the drop callback
--   })
--   s.frame        -- the strip frame (position it / size handled by caller for fixed)
--   s.Refresh()    -- re-read getIcons() and rebuild
--
-- A `custom = true` item gets a pen (edit, top-left) + X (delete, top-right); an item
-- with a `nav` target gets just the pen (navigate to its tab). Both glyphs are white,
-- tinting to the brand colour on hover like the main close button. When onAdd is set a
-- "+" tile (GreenPlus) trails the icons to add a new one.
--
-- DRAG GROUPS: pass the SAME `dragGroup` table to every strip that should accept each other's
-- tiles (e.g. a tab's Front + End strips). A tile dropped on a sibling strip is moved via this
-- strip's `onMove(itemId, fromStrip, toStrip, holeIndex)` callback; a tile dropped on its own
-- strip reorders via `onMove` (if given) else `setOrder`. With no dragGroup the strip is its
-- own group of one — the classic within-strip reorder, unchanged for existing callers.
function ns.ui.CreateIconReorderStrip(opts)
    local parent   = opts.parent
    local getIcons = opts.getIcons or function() return {} end
    local setOrder = opts.setOrder or function() end
    local ICON     = opts.iconSize or 32
    local GAP, PAD = 6, 4
    local fixedW   = opts.width

    local result      = {}
    local pool, items = {}, {}

    -- Strip height: one row by default, or `rows` tall (for the wrapping Free-icons grid).
    local nRows   = (opts.rows and opts.rows > 1) and opts.rows or 1
    local STRIP_H = 2 * PAD + nRows * ICON + math.max(0, nRows - 1) * GAP

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(STRIP_H)
    strip:SetClipsChildren(true)
    if fixedW then strip:SetWidth(fixedW) end
    result.height = STRIP_H

    local emptyFs = strip:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
    emptyFs:SetTextColor(0.67, 0.67, 0.67)
    if fixedW then
        emptyFs:SetPoint("CENTER", strip, "CENTER", 0, 0)
    else
        emptyFs:SetPoint("LEFT", strip, "LEFT", PAD, 0)
    end
    emptyFs:SetText(opts.emptyText or "")
    emptyFs:Hide()

    -- Transient "full" caption: shown on this strip ONLY while a FOREIGN icon is dragged over it and the
    -- bucket is full (opts.canAdd() is false). On a high overlay so it sits above the tiles. Opt-in via
    -- opts.fullText (e.g. the below-player front/end buckets); strips without it never show a message.
    local fullOverlay = CreateFrame("Frame", nil, strip)
    fullOverlay:SetAllPoints(strip)
    fullOverlay:SetFrameLevel(strip:GetFrameLevel() + 5)
    fullOverlay:Hide()
    local fullFs = fullOverlay:CreateFontString(nil, "OVERLAY")
    fullFs:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fullFs:SetTextColor(1, 0.45, 0.45)
    fullFs:SetText(opts.fullText or "")
    fullFs:SetPoint("CENTER", fullOverlay, "CENTER", 0, 0)

    local function slotX(i) return PAD + (i - 1) * (ICON + GAP) end

    -- Tile placement: a wrapping grid (Free-icons list) when opts.wrap + a fixed width,
    -- else a single row by slotX. Index 1-based (tiles and the trailing "+").
    local function perRow()
        if not (opts.wrap and fixedW) then return nil end
        return math.max(1, math.floor((fixedW - PAD + GAP) / (ICON + GAP)))
    end
    local function placeTile(i, b)
        b:ClearAllPoints()
        local pr = perRow()
        if pr then
            local col, rw = (i - 1) % pr, math.floor((i - 1) / pr)
            b:SetPoint("TOPLEFT", strip, "TOPLEFT", PAD + col * (ICON + GAP), -(PAD + rw * (ICON + GAP)))
        else
            b:SetPoint("LEFT", strip, "LEFT", slotX(i), 0)
        end
    end

    -- The trailing "+" tile (declared up here so the drag reflow can keep it past the gapped
    -- tiles); built lazily by ensureAddBtn below.
    local addBtn

    -- ── Inter-strip drag wiring (shared controller, BuffGroups-style) ───────────
    -- Every strip is in a drag group: its own `opts.dragGroup` when given, else a private
    -- one-strip group (the classic within-strip reorder). The group owns the lifted-tile
    -- layer + poll driver; the strip publishes the geometry/reflow hooks the driver calls.
    local dragGroup = opts.dragGroup or { strips = {} }
    dragGroup.strips = dragGroup.strips or {}
    if not opts.noDrag then dragGroup.strips[#dragGroup.strips + 1] = result end
    local dragCtrl = (not opts.noDrag) and EnsureDragController(dragGroup) or nil

    result._setOrder = setOrder
    result._onMove   = opts.onMove

    -- The id list this strip currently shows, in order (the drop reorders a copy of it).
    function result._dragOrderIds()
        local ids = {}
        for i, v in ipairs(items) do ids[i] = v.id end
        return ids
    end

    -- Geometric "is the cursor inside this strip" (GetCursorPosition vs the strip rect) — the
    -- same unit math slotAt uses; reliable while a drag has the mouse captured (unlike IsMouseOver).
    local function cursorOver()
        local l, b, w, h = strip:GetRect()
        if not l then return false end
        local s = strip:GetEffectiveScale()
        if not (s and s > 0) then return false end
        local mx, my = GetCursorPosition()
        mx, my = mx / s, my / s
        return mx >= l and mx < l + w and my >= b and my < b + h
    end

    -- Insertion index under the cursor (0 .. #non-dragged tiles), read from where the tiles
    -- ACTUALLY sit (absolute coords) rather than a synthetic grid, so it is robust to the strip
    -- being wider than its icons, to scroll offset, and to the wrap grid. Mirrors BuffGroups.slotAt.
    local function slotAt(dragId)
        local scale = strip:GetEffectiveScale()
        if not (scale and scale > 0) then return 0 end
        local mx, my = GetCursorPosition()
        mx, my = mx / scale, my / scale
        local pr = perRow()
        local idx = 0
        for _, it in ipairs(items) do
            if it.id ~= dragId then
                local b = it._tile
                local tl, tb = b and b:GetLeft(), b and b:GetBottom()
                if tl then
                    local before
                    if pr and tb then
                        local tcy  = tb + ICON / 2
                        local band = (ICON + GAP) / 2
                        if tcy > my + band then        -- tile sits a row above the cursor
                            before = true
                        elseif tcy < my - band then    -- a row below the cursor
                            before = false
                        else                            -- same row: compare X
                            before = (tl + ICON / 2) < mx
                        end
                    else
                        before = (tl + ICON / 2) < mx
                    end
                    if not before then return idx end
                end
                idx = idx + 1
            end
        end
        return idx
    end

    -- Reflow: skip the lifted tile (it follows the cursor), place the rest in order, leaving a
    -- one-slot gap at holeIndex (the hovered strip only; others pass nil → no gap). Index 1-based
    -- for placeTile (tiles + trailing "+"); holeIndex is 0-based (count of tiles before the cursor).
    local function relayout(dragId, holeIndex)
        local seq = {}
        for _, it in ipairs(items) do if it.id ~= dragId and it._tile then seq[#seq + 1] = it end end
        local slot = 0
        for i, it in ipairs(seq) do
            if holeIndex and (i - 1) == holeIndex then slot = slot + 1 end
            placeTile(slot + 1, it._tile); it._tile:Show()
            slot = slot + 1
        end
        if holeIndex and holeIndex >= #seq then slot = slot + 1 end
        -- Keep the trailing "+" past the (possibly gapped) tiles while dragging.
        if addBtn and addBtn:IsShown() then placeTile(slot + 1, addBtn) end

        -- Transient full hint: this strip is hovered (holeIndex set) by a FOREIGN icon (not already here
        -- → not a reorder) and its bucket is full (canAdd false). Suppressed for a within-strip reorder so
        -- a full bucket can still be re-ordered.
        if fullOverlay and opts.fullText then
            local show = (holeIndex ~= nil) and dragId and opts.canAdd and (not opts.canAdd())
            if show then
                for _, v in ipairs(items) do if v.id == dragId then show = false; break end end
            end
            fullOverlay:SetShown(show and true or false)
        end
    end

    result._drag = {
        cursorOver = cursorOver,
        slotAt     = slotAt,
        relayout   = relayout,
        orderIds   = result._dragOrderIds,
    }

    -- A small corner control (X / pen) on a tile. White at rest; tints to the brand
    -- colour on hover (white texture × colour = that colour), like the main window's
    -- close cross. onClick reads b.item live so the pooled button can be reused.
    local function makeOverlay(b, side, texture, onClick)
        local btn = CreateFrame("Button", nil, b)
        btn:SetSize(14, 14)
        btn:SetFrameLevel(b:GetFrameLevel() + 5)
        -- Inset fully inside the tile's own top corner: half the control (7px) in from
        -- the edge so two adjacent tiles' controls never overlap in the inter-tile gap
        -- (which would make the seam click ambiguous), and 3px down so the top edge
        -- clears the strip's clip rect.
        if side == "right" then
            btn:SetPoint("CENTER", b, "TOPRIGHT", -7, -3)
        else
            btn:SetPoint("CENTER", b, "TOPLEFT", 7, -3)
        end
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetColorTexture(0, 0, 0, 0.6)
        local glyph = btn:CreateTexture(nil, "OVERLAY")
        glyph:SetPoint("CENTER")
        glyph:SetSize(10, 10)
        glyph:SetTexture(texture)
        btn:SetScript("OnEnter", function() glyph:SetVertexColor(ns.GetBrandColor()) end)
        btn:SetScript("OnLeave", function() glyph:SetVertexColor(1, 1, 1) end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- The trailing "+" tile (GreenPlus) that opens the add-a-custom-icon flow. (`addBtn` is
    -- declared above, near the drag wiring, so the reflow can keep it past the gapped tiles.)
    local function ensureAddBtn()
        if addBtn then return addBtn end
        addBtn = CreateFrame("Button", nil, strip)
        addBtn:SetSize(ICON, ICON)
        local border = addBtn:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.4, 0.4, 0.4, 1)
        local fill = addBtn:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetAllPoints(addBtn)
        fill:SetColorTexture(0.12, 0.12, 0.12, 0.9)
        local plus = addBtn:CreateTexture(nil, "ARTWORK")
        plus:SetPoint("CENTER")
        plus:SetSize(ICON - 12, ICON - 12)
        plus:SetTexture(UNBUNK_ICON_PLUS_GREEN)
        addBtn:SetScript("OnEnter", function() fill:SetColorTexture(0.2, 0.2, 0.2, 0.95) end)
        addBtn:SetScript("OnLeave", function() fill:SetColorTexture(0.12, 0.12, 0.12, 0.9) end)
        addBtn:SetScript("OnClick", function() if opts.onAdd then opts.onAdd() end end)
        return addBtn
    end

    -- Reuses a button pool (never creates/destroys per refresh) so icons can't pile up.
    local function rebuild()
        items = getIcons() or {}
        if fullOverlay then fullOverlay:Hide() end   -- transient; only the drag reflow shows it
        -- Show the "+" only when adding is enabled AND the row isn't full (canAdd).
        local showAdd = false
        if opts.onAdd and (not opts.canAdd or opts.canAdd()) then showAdd = true end
        emptyFs:SetShown(#items == 0 and not showAdd)
        for _, b in ipairs(pool) do b:Hide(); b.item = nil end
        for i, it in ipairs(items) do
            local b = pool[i]
            if not b then
                b = CreateFrame("Button", nil, strip)
                b:SetSize(ICON, ICON)
                local border = b:CreateTexture(nil, "BACKGROUND")
                border:SetPoint("TOPLEFT", -1, 1)
                border:SetPoint("BOTTOMRIGHT", 1, -1)
                border:SetColorTexture(0.4, 0.4, 0.4, 1)
                local tex = b:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints(b)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                b.tex = tex
                if not opts.noDrag and dragCtrl then
                    -- Lift the pooled tile onto the shared layer; the poll driver then drives
                    -- the move + release. Reads b.item live (the pool is reused across rebuilds),
                    -- so a tile always drags the item it currently shows.
                    b:RegisterForDrag("LeftButton")
                    b:SetScript("OnDragStart", function(self)
                        if self.item then dragCtrl.start(result, self, self.item.id) end
                    end)
                    -- OnDragStop is a backup release path (the driver's IsMouseButtonDown poll is
                    -- the primary one — it stays reliable after the tile is reparented).
                    b:SetScript("OnDragStop", function() dragCtrl.stop() end)
                end
                pool[i] = b
            end
            b.item = it
            it._tile = b                       -- back-link for slotAt / relayout
            b.tex:SetTexture(it.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:SetFrameLevel(strip:GetFrameLevel() + 1)
            placeTile(i, b)
            b:Show()

            -- Pen (top-left): edits a CUSTOM icon, or navigates an ADDON icon (it.nav =
            -- its panel name) to its own tab. X (top-right): deletes a custom icon only.
            -- Both read b.item live (pooled). Created once per tile, shown per item.
            if not b.editBtn then
                b.editBtn = makeOverlay(b, "left", UNBUNK_ICON_PEN_WHITE, function()
                    local it2 = b.item
                    if not it2 then return end
                    if it2.custom and opts.onEditCustom then opts.onEditCustom(it2.id)
                    elseif it2.nav and opts.onNavigate then opts.onNavigate(it2.nav) end
                end)
                b.delBtn = makeOverlay(b, "right", UNBUNK_ICON_CROSS_WHITE, function()
                    local it2 = b.item
                    if it2 and it2.custom and opts.onRemoveCustom then opts.onRemoveCustom(it2.id) end
                end)
            end
            local showPen = (it.custom and opts.onEditCustom ~= nil) or (it.nav and opts.onNavigate ~= nil)
            local showX   = it.custom and opts.onRemoveCustom ~= nil
            b.editBtn:SetShown(showPen and true or false)
            b.delBtn:SetShown(showX and true or false)
        end

        -- Trailing "+" tile (one slot past the last icon) when adding is enabled and
        -- the row still has room.
        if showAdd then
            local b = ensureAddBtn()
            b:SetFrameLevel(strip:GetFrameLevel() + 1)
            placeTile(#items + 1, b)
            b:Show()
        elseif addBtn then
            addBtn:Hide()
        end

        if not fixedW then
            local n = #items + (showAdd and 1 or 0)
            strip:SetWidth(math.max(1, PAD * 2 + n * ICON + math.max(0, n - 1) * GAP))
        end
    end
    rebuild()

    result.frame       = strip
    result.Refresh     = rebuild
    -- The drag controller calls this on every group strip after a drop to re-read the new order.
    -- It rebuilds THIS strip; the panel's own onMove/setOrder also fires a full panel rebuild
    -- (which re-runs Refresh) so heights/labels stay correct — this just guarantees a live redraw.
    result.RebuildStrip = rebuild
    return result
end
