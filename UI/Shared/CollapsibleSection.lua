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
    local heading       = config.heading or "UnbunkUtilityH2"   -- header title tier (default H2)
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

    -- Assigned once contentFrame exists (below). Greys + mouse-blocks the body when
    -- the header checkbox is unchecked; the checkbox's onClick (built first) calls it.
    local ApplyEnabledVisual

    local HEADER_HEIGHT = 28

    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(518)

    -- ── Header button ─────────────────────────────────────────────────────────

    -- One bordered box drawn around the WHOLE section, identical to CreateGroupBox,
    -- so a per-item section reads the same as the other group cadres (replacing the
    -- old separate header-bar border + 1px sharp body edges). It sits behind the
    -- clickable header row and the content.
    local box = CreateFrame("Frame", nil, container, "BackdropTemplate")
    box:SetAllPoints(container)
    box:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0.10, 0.10, 0.10, 0.5)
    box:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    result.box = box

    -- Transparent, clickable header row; the box above draws the frame.
    local headerBtn = CreateFrame("Button", nil, container)
    headerBtn:SetHeight(HEADER_HEIGHT)
    headerBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    headerBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    -- Hover lightens the box border (no separate header border anymore).
    headerBtn:SetScript("OnEnter", function()
        box:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    end)
    headerBtn:SetScript("OnLeave", function()
        box:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    end)

    -- Arrow
    local arrow = headerBtn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(8, 8)
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
            onClick = function(val)
                if onCheck then onCheck(val) end
                if ApplyEnabledVisual then ApplyEnabledVisual() end
            end,
        })
        checkbox.frame:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
        checkbox.frame:SetHeight(20)
        -- Shrink the (label-less) checkbox container to just its box, so the section
        -- title sits right beside the checkbox instead of ~300px to its right.
        checkbox.frame:SetWidth(22)
        labelAnchor = checkbox.frame
        result.checkbox = checkbox
    end

    local headerLabel = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerLabel:SetPoint("LEFT", labelAnchor, "RIGHT", 6, 0)
    headerLabel:SetText(label)

    -- ── Content frame ─────────────────────────────────────────────────────────

    -- Transparent host below the header; the surrounding box (created above) draws
    -- the border + background, so the section is framed exactly like a group cadre.
    -- Anchored flush under the header and full-width: the nested BuildMenu insets
    -- its content via originX +8 / originY -8, so content positioning is unchanged.
    local contentFrame = CreateFrame("Frame", nil, container)
    contentFrame:SetPoint("TOPLEFT", headerBtn, "BOTTOMLEFT", 0, 0)
    contentFrame:SetPoint("TOPRIGHT", headerBtn, "BOTTOMRIGHT", 0, 0)

    local contentHeight = 0
    if createContent then
        contentHeight = createContent(contentFrame) or 0
    end
    -- Pad the bottom to match the +8 top inset so the border has even margins.
    local boxedHeight = contentHeight + 16
    contentFrame:SetHeight(boxedHeight)

    -- ── Disable (grey + mouse-block) the body while the header checkbox is off ──
    -- The options inside are non-functional when the feature is unchecked, so dim the
    -- body and swallow mouse + wheel input so clicks/scroll can't reach the now-inert
    -- controls. The header checkbox lives in the header bar (outside contentFrame), so
    -- it stays fully interactive to re-enable the section. No-op for sections without
    -- a header checkbox.
    -- The header checkbox lives OUTSIDE contentFrame, so fading the whole body and
    -- blocking it is enough — no `master` exception needed.
    local applyGate = ns.ui.MakeDisableGate(contentFrame)
    ApplyEnabledVisual = function()
        if not (showCheckbox and isChecked) then return end
        applyGate(isChecked() and true or false, { contentFrame })
    end

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
    ApplyEnabledVisual()

    -- ── Refresh ───────────────────────────────────────────────────────────────

    function result.Refresh()
        if checkbox and isChecked then
            checkbox.SetChecked(isChecked())
        end
        ApplyEnabledVisual()
    end

    result.frame         = container
    result.height        = container:GetHeight()
    result.contentFrame  = contentFrame

    return result
end