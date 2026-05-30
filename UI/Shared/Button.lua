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

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("CENTER")
    lbl:SetText(label)

    btn:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
        self:SetBackdropColor(0.25, 0.25, 0.25, 0.9)
    end)

    btn:SetScript("OnLeave", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end)

    btn:SetScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    end)

    btn:SetScript("OnMouseUp", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropColor(0.25, 0.25, 0.25, 0.9)
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
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        else
            btn:Disable()
            lbl:SetTextColor(0.5, 0.5, 0.5, 1)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        end
    end

    return result
end