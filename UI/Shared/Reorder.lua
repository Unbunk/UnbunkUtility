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

-- ── Drag-to-reorder icon strip ────────────────────────────────────────────────
-- A horizontal strip of icon tiles the user drags to reorder. While dragging, the
-- held tile follows the cursor (clamped inside the strip) and the others slide over
-- live; the order is committed to setOrder() on release. Empty -> a centred grey
-- "no icons" hint (when a fixed width is given) or a left-aligned one (auto width).
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
--   })
--   s.frame        -- the strip frame (position it / size handled by caller for fixed)
--   s.Refresh()    -- re-read getIcons() and rebuild
--
-- A `custom = true` item gets a pen (edit, top-left) + X (delete, top-right); an item
-- with a `nav` target gets just the pen (navigate to its tab). Both glyphs are white,
-- tinting to the brand colour on hover like the main close button. When onAdd is set a
-- "+" tile (GreenPlus) trails the icons to add a new one.
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

    local function slotX(i) return PAD + (i - 1) * (ICON + GAP) end
    local function indexOf(it) for i, v in ipairs(items) do if v == it then return i end end end

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

    local dragBtn
    local function placeButtons()
        for _, b in ipairs(pool) do
            if b:IsShown() and b ~= dragBtn and b.item then
                local i = indexOf(b.item)
                if i then b:ClearAllPoints(); b:SetPoint("LEFT", strip, "LEFT", slotX(i), 0) end
            end
        end
    end
    local function onDragUpdate(b)
        local scale = strip:GetEffectiveScale()
        local left  = strip:GetLeft()
        if not (scale and scale > 0 and left) then return end
        local cx = (GetCursorPosition() / scale) - left - ICON / 2
        cx = math.max(PAD, math.min(slotX(math.max(1, #items)), cx))
        b:ClearAllPoints(); b:SetPoint("LEFT", strip, "LEFT", cx, 0)
        local newIdx = math.max(1, math.min(#items, math.floor((cx - PAD) / (ICON + GAP) + 0.5) + 1))
        local cur = indexOf(b.item)
        if cur and newIdx ~= cur then
            table.remove(items, cur); table.insert(items, newIdx, b.item); placeButtons()
        end
    end
    local function startDrag(b)
        dragBtn = b
        b:SetFrameLevel(strip:GetFrameLevel() + 10)
        b:SetScript("OnUpdate", function(self) onDragUpdate(self) end)
    end
    local function stopDrag(b)
        b:SetScript("OnUpdate", nil)
        b:SetFrameLevel(strip:GetFrameLevel() + 1)
        dragBtn = nil
        placeButtons()
        local i = indexOf(b.item)
        if i then b:ClearAllPoints(); b:SetPoint("LEFT", strip, "LEFT", slotX(i), 0) end
        local ids = {}
        for k, v in ipairs(items) do ids[k] = v.id end
        setOrder(ids)
    end

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

    -- The trailing "+" tile (GreenPlus) that opens the add-a-custom-icon flow.
    local addBtn
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
                if not opts.noDrag then
                    b:RegisterForDrag("LeftButton")
                    b:SetScript("OnDragStart", function(self) startDrag(self) end)
                    b:SetScript("OnDragStop",  function(self) stopDrag(self) end)
                end
                pool[i] = b
            end
            b.item = it
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

    result.frame   = strip
    result.Refresh = rebuild
    return result
end
