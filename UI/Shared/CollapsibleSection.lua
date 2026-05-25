-- UI/Shared/CollapsibleSection.lua
-- Reusable collapsible section widget.
--
-- Usage:
--   local cs = HealerRange_CreateCollapsibleSection({
--       parent        = panel,
--       label         = "My Section",
--       showCheckbox  = true,         -- default true
--       isChecked     = function() return myDB.enabled end,
--       onCheck       = function(val) myDB.enabled = val end,
--       createContent = function(contentFrame) ... return height end,
--   })
--   cs.frame          -- le frame conteneur
--   cs.height         -- hauteur actuelle (header seul ou header + content)
--   cs.checkbox       -- la checkbox (si showCheckbox = true)
--   cs.Refresh()      -- rafraîchit la checkbox

function Unbunk_CreateCollapsibleSection(config)
    local parent        = config.parent
    local label         = config.label or "Section"
    local showCheckbox  = config.showCheckbox ~= false
    local isChecked     = config.isChecked
    local onCheck       = config.onCheck
    local createContent = config.createContent

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
        checkbox = CreateFrame("CheckButton", nil, headerBtn, "UICheckButtonTemplate")
        checkbox:SetSize(20, 20)
        checkbox:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
        if isChecked then checkbox:SetChecked(isChecked()) end
        if onCheck then
            checkbox:SetScript("OnClick", function(self)
                onCheck(self:GetChecked())
            end)
        end
        -- Empêche le click sur la checkbox de toggler la section
        checkbox:SetScript("OnClick", function(self)
            if onCheck then onCheck(self:GetChecked()) end
        end)
        labelAnchor = checkbox
        result.checkbox = checkbox
    end

    local headerLabel = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerLabel:SetPoint("LEFT", labelAnchor, "RIGHT", 6, 0)
    headerLabel:SetText(label)

    -- ── Content frame ─────────────────────────────────────────────────────────

    local contentFrame = CreateFrame("Frame", nil, container)
    contentFrame:SetPoint("TOPLEFT", headerBtn, "BOTTOMLEFT", 0, -4)
    contentFrame:SetPoint("TOPRIGHT", headerBtn, "BOTTOMRIGHT", 0, -4)

    local contentHeight = 0
    if createContent then
        contentHeight = createContent(contentFrame) or 0
    end
    contentFrame:SetHeight(contentHeight)

    -- ── Collapse logic ────────────────────────────────────────────────────────

    local collapsed = false

    local function UpdateHeight()
        if collapsed then
            container:SetHeight(HEADER_HEIGHT)
        else
            container:SetHeight(HEADER_HEIGHT + 4 + contentHeight)
        end
        result.height = container:GetHeight()
    end

    headerBtn:SetScript("OnClick", function(self, btn)
        if btn ~= "LeftButton" then return end
        collapsed = not collapsed
        if collapsed then
            arrow:SetRotation(math.rad(-90))
            contentFrame:Hide()
        else
            arrow:SetRotation(0)
            contentFrame:Show()
        end
        UpdateHeight()
    end)

    UpdateHeight()

    -- ── Refresh ───────────────────────────────────────────────────────────────

    function result.Refresh()
        if checkbox and isChecked then
            checkbox:SetChecked(isChecked())
        end
    end

    result.frame         = container
    result.height        = container:GetHeight()
    result.contentFrame  = contentFrame

    return result
end