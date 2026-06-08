-- UI/Shared/CollapsibleSection.lua
-- Reusable collapsible section widget.
--
-- Usage:
--   local cs = ns.ui.CreateCollapsibleSection({
--       parent        = panel,
--       label         = "My Section",
--       showCheckbox  = true,         -- default true
--       isChecked     = function() return myDB.enabled end,
--       onCheck       = function(val) myDB.enabled = val end,
--       createContent = function(contentFrame) ... return height end,
--   })
--   cs.frame          -- container frame
--   cs.height         -- current height (header only, or header + content)
--   cs.checkbox       -- the checkbox (when showCheckbox = true)
--   cs.Refresh()      -- re-syncs the checkbox state from isChecked()

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

function ns.ui.CreateCollapsibleSection(config)
    local parent        = config.parent
    local label         = config.label or L["Section"]
    local showCheckbox  = config.showCheckbox ~= false
    local isChecked     = config.isChecked
    local onCheck       = config.onCheck
    local createContent = config.createContent
    -- Optional collapse-state persistence: when the panel is rebuilt (e.g. a
    -- reactive option toggle), getCollapsed restores whether this section was
    -- collapsed, and onCollapse stores the new state. Without them the section
    -- always starts expanded (the previous behaviour).
    local getCollapsed  = config.getCollapsed
    local onCollapse    = config.onCollapse

    local result = {}

    local HEADER_HEIGHT = 28

    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(518)

    -- ── Header button ─────────────────────────────────────────────────────────

    local headerBtn = CreateFrame("Button", nil, container, "BackdropTemplate")
    headerBtn:SetHeight(HEADER_HEIGHT)
    headerBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    headerBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    headerBtn:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    headerBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    headerBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    headerBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    end)
    headerBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    -- Arrow
    local arrow = headerBtn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", headerBtn, "LEFT", 8, 0)
    if UNBUNK_ICON_DROPDOWN_ARROW then
        arrow:SetTexture(UNBUNK_ICON_DROPDOWN_ARROW)
    end

    -- Checkbox
    local checkbox = nil
    local labelAnchor = arrow

    if showCheckbox then
        checkbox = ns.ui.CreateCheckbox({
            parent  = headerBtn,
            label   = "",
            checked = isChecked and isChecked() or false,
            onClick = function(val) if onCheck then onCheck(val) end end,
        })
        checkbox.frame:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
        checkbox.frame:SetHeight(20)
        labelAnchor = checkbox.frame
        result.checkbox = checkbox
    end

    local headerLabel = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerLabel:SetPoint("LEFT", labelAnchor, "RIGHT", 6, 0)
    headerLabel:SetText(label)

    -- ── Content frame ─────────────────────────────────────────────────────────

    -- Bordered content box: when expanded the whole section reads as a framed
    -- block (a header bar + a bordered body), not just a header. The nested
    -- BuildMenu lays its content at originX +8 / originY -8 inside this frame, so
    -- the border frames it with even margins.
    -- Flush against the header (no gap) so the collapse bar + its bordered body read
    -- as one connected, foldable block. The body is drawn with a 3-sided border
    -- (left / right / bottom, OPEN at the top) so it doesn't paint a redundant top
    -- edge under the header — the header bar visually closes it off.
    local contentFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    contentFrame:SetPoint("TOPLEFT", headerBtn, "BOTTOMLEFT", 0, 0)
    contentFrame:SetPoint("TOPRIGHT", headerBtn, "BOTTOMRIGHT", 0, 0)
    contentFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    contentFrame:SetBackdropColor(0.10, 0.10, 0.10, 0.5)

    -- Manual left / right / bottom edges (no top), so the box opens upward into the
    -- header bar instead of doubling its bottom border.
    local function ContentEdge()
        local t = contentFrame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.45, 0.45, 0.45, 1)
        return t
    end
    local edgeL = ContentEdge(); edgeL:SetPoint("TOPLEFT");     edgeL:SetPoint("BOTTOMLEFT");  edgeL:SetWidth(1)
    local edgeR = ContentEdge(); edgeR:SetPoint("TOPRIGHT");    edgeR:SetPoint("BOTTOMRIGHT"); edgeR:SetWidth(1)
    local edgeB = ContentEdge(); edgeB:SetPoint("BOTTOMLEFT");  edgeB:SetPoint("BOTTOMRIGHT"); edgeB:SetHeight(1)

    local contentHeight = 0
    if createContent then
        contentHeight = createContent(contentFrame) or 0
    end
    -- Pad the bottom to match the +8 top inset so the border has even margins.
    local boxedHeight = contentHeight + 16
    contentFrame:SetHeight(boxedHeight)

    -- ── Collapse logic ────────────────────────────────────────────────────────

    local collapsed = getCollapsed and getCollapsed() or false

    local function ApplyCollapsedVisual()
        if collapsed then
            arrow:SetRotation(math.rad(-90))
            contentFrame:Hide()
        else
            arrow:SetRotation(0)
            contentFrame:Show()
        end
    end

    local function UpdateHeight()
        if collapsed then
            container:SetHeight(HEADER_HEIGHT)
        else
            container:SetHeight(HEADER_HEIGHT + boxedHeight)
        end
        result.height = container:GetHeight()
    end

    headerBtn:SetScript("OnClick", function(self, btn)
        if btn ~= "LeftButton" then return end
        collapsed = not collapsed
        if onCollapse then onCollapse(collapsed) end
        ApplyCollapsedVisual()
        UpdateHeight()
    end)

    ApplyCollapsedVisual()
    UpdateHeight()

    -- ── Refresh ───────────────────────────────────────────────────────────────

    function result.Refresh()
        if checkbox and isChecked then
            checkbox.SetChecked(isChecked())
        end
    end

    result.frame         = container
    result.height        = container:GetHeight()
    result.contentFrame  = contentFrame

    return result
end