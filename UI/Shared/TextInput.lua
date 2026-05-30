-- UI/Shared/TextInput.lua
-- Reusable styled text/number input widget.
--
-- Usage:
--   local ti = ns.ui.CreateTextInput({
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

local _, ns = ...
ns.ui = ns.ui or {}

function ns.ui.CreateTextInput(config)
    local parent     = config.parent
    local width      = config.width      or 200
    local height     = config.height     or 22
    local numeric    = config.numeric    or false
    local maxLetters = config.maxLetters or 100
    local text       = config.text       or ""
    local onEnter    = config.onEnter
    -- Optional clamp range for numeric inputs. When set, an out-of-range entry
    -- is clamped to [min, max] and the clamped value is written back into the box.
    local minVal     = config.min
    local maxVal     = config.max

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
        local cur = self:GetText()
        -- Allow the minus sign only in the first position.
        if char == "-" and #cur > 1 then
            self:SetText(cur:gsub("-", ""))
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if numeric then
            local v = tonumber(self:GetText())  -- nil when the text isn't a number
            if v then
                if minVal and v < minVal then v = minVal end
                if maxVal and v > maxVal then v = maxVal end
                self:SetText(tostring(v))  -- reflect the clamped value in the box
            end
            if onEnter then onEnter(v) end  -- v is nil for garbage; callers guard
        else
            if onEnter then onEnter(self:GetText()) end
        end
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