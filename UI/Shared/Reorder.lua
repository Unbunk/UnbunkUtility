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
--       getIcons  = function() return { { id = "...", texture = 12345 }, ... } end,
--       setOrder  = function(idList) ... end,
--       emptyText = L["No icons"],
--       width     = 230,   -- optional: fixed width (else auto-sizes to the icons)
--       iconSize  = 32,    -- optional
--   })
--   s.frame        -- the strip frame (position it / size handled by caller for fixed)
--   s.Refresh()    -- re-read getIcons() and rebuild
function ns.ui.CreateIconReorderStrip(opts)
    local parent   = opts.parent
    local getIcons = opts.getIcons or function() return {} end
    local setOrder = opts.setOrder or function() end
    local ICON     = opts.iconSize or 32
    local GAP, PAD = 6, 4
    local fixedW   = opts.width

    local result      = {}
    local pool, items = {}, {}

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(ICON + 2 * PAD)
    strip:SetClipsChildren(true)
    if fixedW then strip:SetWidth(fixedW) end

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

    -- Reuses a button pool (never creates/destroys per refresh) so icons can't pile up.
    local function rebuild()
        items = getIcons() or {}
        emptyFs:SetShown(#items == 0)
        for _, b in ipairs(pool) do b:Hide(); b.item = nil end
        for i, it in ipairs(items) do
            local b = pool[i]
            if not b then
                b = CreateFrame("Button", nil, strip)
                b:SetSize(ICON, ICON)
                b:RegisterForDrag("LeftButton")
                local border = b:CreateTexture(nil, "BACKGROUND")
                border:SetPoint("TOPLEFT", -1, 1)
                border:SetPoint("BOTTOMRIGHT", 1, -1)
                border:SetColorTexture(0.4, 0.4, 0.4, 1)
                local tex = b:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints(b)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                b.tex = tex
                b:SetScript("OnDragStart", function(self) startDrag(self) end)
                b:SetScript("OnDragStop",  function(self) stopDrag(self) end)
                pool[i] = b
            end
            b.item = it
            b.tex:SetTexture(it.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:SetFrameLevel(strip:GetFrameLevel() + 1)
            b:ClearAllPoints()
            b:SetPoint("LEFT", strip, "LEFT", slotX(i), 0)
            b:Show()
        end
        if not fixedW then
            strip:SetWidth(math.max(1, PAD * 2 + #items * ICON + math.max(0, #items - 1) * GAP))
        end
    end
    rebuild()

    result.frame   = strip
    result.Refresh = rebuild
    return result
end
