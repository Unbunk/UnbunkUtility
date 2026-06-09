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
    -- Optional `disabled` (boolean | function -> boolean): when true the box is
    -- greyed, always reads as unchecked, and ignores clicks/hover. Re-evaluated on
    -- every UpdateVisual, so a SetChecked from a panel refresh reflects a live change.
    local getDisabled = config.disabled
    local function IsDisabled()
        if type(getDisabled) == "function" then return getDisabled() and true or false end
        return getDisabled == true
    end

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
        if IsDisabled() then return end
        self:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    end)
    box:SetScript("OnLeave", function(self)
        if IsDisabled() then return end
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
        local disabled = IsDisabled()
        -- Disabled always reads as unchecked + greyed (regardless of isChecked) so a
        -- stored includeInCdm=true never shows ticked while the Cooldown Manager is off.
        if isChecked and not disabled then
            checkTex:Show()
        else
            checkTex:Hide()
        end
        if disabled then
            box:SetBackdropColor(0.06, 0.06, 0.06, 0.7)
            box:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
            lbl:SetTextColor(0.5, 0.5, 0.5)
        else
            local shade = isChecked and 0.2 or 0.1
            box:SetBackdropColor(shade, shade, shade, 0.9)
            box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            lbl:SetTextColor(1, 1, 1)
        end
    end

    UpdateVisual()

    box:SetScript("OnClick", function()
        if IsDisabled() then return end
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