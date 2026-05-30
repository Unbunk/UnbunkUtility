-- UI/Shared/Checkbox.lua
-- Reusable styled checkbox widget.
--
-- Usage:
--   local cb = ns.ui.CreateCheckbox({
--       parent    = panel,
--       label     = "Enable sound",
--       checked   = true,
--       onClick   = function(checked) ... end,
--   })
--   cb.frame        -- container frame
--   cb.SetChecked(bool)
--   cb.GetChecked()

local _, ns = ...
ns.ui = ns.ui or {}

function ns.ui.CreateCheckbox(config)
    local parent  = config.parent
    local label   = config.label   or ""
    local checked = config.checked or false
    local onClick = config.onClick

    local result = {}

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(24)
    container:SetWidth(300)

    -- ── Box ───────────────────────────────────────────────────────────────────

    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(22, 22)
    box:SetPoint("LEFT", container, "LEFT", 0, 0)
    box:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    box:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    end)
    box:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    -- ── Check mark ────────────────────────────────────────────────────────────

    local checkTex = box:CreateTexture(nil, "OVERLAY")
    checkTex:SetSize(20, 20)
    checkTex:SetPoint("CENTER", box, "CENTER", 0, 0)
    checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkTex:Hide()

    -- ── Label ─────────────────────────────────────────────────────────────────

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
    lbl:SetText(label)

    -- ── State ─────────────────────────────────────────────────────────────────

    local isChecked = checked

    local function UpdateVisual()
        if isChecked then
            checkTex:Show()
            box:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
        else
            checkTex:Hide()
            box:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        end
    end

    UpdateVisual()

    box:SetScript("OnClick", function()
        isChecked = not isChecked
        UpdateVisual()
        if onClick then onClick(isChecked) end
    end)

    -- ── API ───────────────────────────────────────────────────────────────────

    function result.SetChecked(val)
        isChecked = val
        UpdateVisual()
    end

    function result.GetChecked()
        return isChecked
    end

    result.frame = container

    return result
end