-- UI/Shared/Button.lua
-- Reusable styled button widget.
--
-- Usage:
--   local btn = ns.ui.CreateButton({
--       parent  = panel,
--       label   = "Test Alert",
--       width   = 100,
--       height  = 22,
--       onClick = function() ... end,
--   })
--   btn.frame  -- button frame
--   btn.SetText(text)
--   btn.SetEnabled(bool)

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

function ns.ui.CreateButton(config)
    local parent  = config.parent
    local label   = config.label   or L["Button"]
    local width   = config.width   or 100
    local height  = config.height  or 22
    local onClick = config.onClick

    local result = {}

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)

    -- Sharp-cornered button: a border-coloured texture fills the frame, with a darker
    -- fill laid 1px inside it — so exactly 1px of the border shows as a crisp edge.
    -- The border (and the label) turn brand blue on hover.
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(btn)
    border:SetColorTexture(0.4, 0.4, 0.4, 1)

    local fill = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetPoint("TOPLEFT",     btn, "TOPLEFT",      1, -1)
    fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1,  1)
    fill:SetColorTexture(0.15, 0.15, 0.15, 0.9)

    local function SetBorder(r, g, b) border:SetColorTexture(r, g, b, 1) end
    local function SetFill(v)         fill:SetColorTexture(v, v, v, 0.9) end

    local lbl = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
    lbl:SetPoint("CENTER")
    lbl:SetText(label)

    btn:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        local r, g, b = ns.GetBrandColor()           -- live brand blue
        SetBorder(r, g, b)                            -- blue border on hover
        SetFill(0.22)
        lbl:SetTextColor(r, g, b, 1)                  -- blue text on hover
    end)

    btn:SetScript("OnLeave", function(self)
        if not self:IsEnabled() then return end
        SetBorder(0.4, 0.4, 0.4)
        SetFill(0.15)
        lbl:SetTextColor(1, 1, 1, 1)
    end)

    btn:SetScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        SetFill(0.1)
    end)

    btn:SetScript("OnMouseUp", function(self)
        if not self:IsEnabled() then return end
        SetFill(0.22)
    end)

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    result.frame = btn

    function result.SetText(text)
        lbl:SetText(text)
    end

    function result.SetEnabled(enabled)
        if enabled then
            btn:Enable()
            lbl:SetTextColor(1, 1, 1, 1)
            SetBorder(0.4, 0.4, 0.4)
            SetFill(0.15)
        else
            btn:Disable()
            lbl:SetTextColor(0.5, 0.5, 0.5, 1)
            SetBorder(0.3, 0.3, 0.3)
            SetFill(0.1)
        end
    end

    return result
end