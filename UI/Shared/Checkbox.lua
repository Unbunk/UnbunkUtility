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

    local box = CreateFrame("Button", nil, container)
    box:SetSize(22, 22)
    box:SetPoint("LEFT", container, "LEFT", 0, 0)

    -- Borderless dark square (no edge); the blue/grey indicator square sits on top of it.
    local boxFill = box:CreateTexture(nil, "BACKGROUND")
    boxFill:SetAllPoints(box)
    boxFill:SetColorTexture(0.12, 0.12, 0.12, 0.95)

    local function SetBoxShade(v)
        boxFill:SetColorTexture(v, v, v, 0.95)
    end

    box:SetScript("OnEnter", function()
        if IsDisabled() then return end
        SetBoxShade(0.22)   -- subtle lighten on hover (no border left to highlight)
    end)
    box:SetScript("OnLeave", function()
        if IsDisabled() then return end
        SetBoxShade(0.12)
    end)

    -- ── Check mark ────────────────────────────────────────────────────────────

    -- A small filled square (blue when active, grey when disabled) instead of the old
    -- yellow check texture. The colour is set per-state in UpdateVisual.
    local checkTex = box:CreateTexture(nil, "OVERLAY")
    checkTex:SetSize(10, 10)
    checkTex:SetPoint("CENTER", box, "CENTER", 0, 0)
    checkTex:SetColorTexture(ns.GetBrandColor())   -- live brand blue (re-read in UpdateVisual)
    checkTex:Hide()

    -- ── Label ─────────────────────────────────────────────────────────────────

    local lbl = container:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
    lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
    lbl:SetText(label)

    -- ── State ─────────────────────────────────────────────────────────────────

    local isChecked = checked

    local function UpdateVisual()
        local disabled = IsDisabled()
        -- The square reflects the checked state; blue when active, grey when disabled
        -- (so a stored includeInCdm=true reads as a greyed square while the Cooldown
        -- Manager is off, instead of vanishing).
        if isChecked then
            if disabled then
                checkTex:SetColorTexture(0.5, 0.5, 0.5, 1)    -- grey
            else
                checkTex:SetColorTexture(ns.GetBrandColor())  -- live brand blue
            end
            checkTex:Show()
        else
            checkTex:Hide()
        end
        if disabled then
            SetBoxShade(0.08)
            lbl:SetTextColor(0.5, 0.5, 0.5)
        else
            SetBoxShade(0.12)
            lbl:SetTextColor(1, 1, 1)
        end
    end

    UpdateVisual()
    -- Re-tint the (checked) square live when the brand colour changes; weak-keyed by the
    -- container so rebuilt checkboxes are GC'd, not leaked. UpdateVisual respects state.
    if ns.RegisterBrandRefresh then ns.RegisterBrandRefresh(container, UpdateVisual) end

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
    result.label = lbl   -- exposed so callers can anchor extra content to the right of the text

    return result
end