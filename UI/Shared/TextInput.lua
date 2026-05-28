-- UI/Shared/TextInput.lua
-- Reusable styled text/number input widget.
--
-- Usage:
--   local ti = Unbunk_CreateTextInput({
--       parent    = panel,
--       width     = 200,
--       height    = 22,
--       numeric   = false,
--       maxLetters = 100,
--       text      = "default",
--       onEnter   = function(text) ... end,
--   })
--   ti.frame
--   ti.editBox
--   ti.SetText(text)
--   ti.GetText()

function Unbunk_CreateTextInput(config)
    local parent     = config.parent
    local width      = config.width      or 200
    local height     = config.height     or 22
    local numeric    = config.numeric    or false
    local maxLetters = config.maxLetters or 100
    local text       = config.text       or ""
    local onEnter    = config.onEnter

    local result = {}

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width, height)
    container:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    container:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    container:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -3)
    editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 3)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(maxLetters)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetTextColor(1, 1, 1, 1)

    editBox:SetScript("OnChar", function(self, char)
        if not numeric then return end
        local text = self:GetText()
        -- Allow the minus sign only in the first position.
        if char == "-" and #text > 1 then
            self:SetText(text:gsub("-", ""))
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if onEnter then onEnter(numeric and tonumber(self:GetText()) or self:GetText()) end
        self:ClearFocus()
    end)
    if text ~= "" then
        editBox:SetText(text)
    end

    editBox:SetScript("OnEditFocusGained", function(self)
        container:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        container:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if onEnter then onEnter(numeric and tonumber(self:GetText()) or self:GetText()) end
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    function result.SetText(t)
        editBox:SetText(t or "")
    end

    function result.GetText()
        return editBox:GetText()
    end

    result.frame   = container
    result.editBox = editBox

    return result
end