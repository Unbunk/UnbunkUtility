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
    -- Only meaningful with numeric=true: permits a single leading minus sign (used by
    -- the x/y offset fields). Every other numeric field stays digits-only.
    local allowNegative = config.allowNegative or false
    local maxLetters = config.maxLetters or 100
    local text       = config.text       or ""
    local onEnter    = config.onEnter
    -- Optional clamp range for numeric inputs. When set, an out-of-range entry
    -- is clamped to [min, max] and the clamped value is written back into the box.
    local minVal     = config.min
    local maxVal     = config.max
    -- Optional `disabled` (boolean | function -> boolean): greys the box + text and blocks input. Re-evaluated
    -- by result.Refresh() (which a panel calls on menu.Refresh), so a live toggle reflects immediately.
    local getDisabled = config.disabled
    local function IsDisabled()
        if type(getDisabled) == "function" then return getDisabled() and true or false end
        return getDisabled == true
    end

    local result = {}

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)

    -- Borderless dark fill with sharp corners, matching the checkbox style.
    local fill = container:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(container)
    fill:SetColorTexture(0.12, 0.12, 0.12, 0.95)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -3)
    editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 3)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(maxLetters)
    editBox:SetFontObject("UnbunkUtilityBody")
    editBox:SetTextColor(1, 1, 1, 1)

    editBox:SetScript("OnChar", function(self, char)
        if not numeric then return end
        -- Reject anything that isn't a digit the instant it's typed; keep a single
        -- leading minus only when negatives are allowed (x/y offsets). %D strips the
        -- minus too, so re-prepend it from the captured sign.
        local cur = self:GetText()
        local cleaned
        if allowNegative then
            local sign = cur:sub(1, 1) == "-" and "-" or ""
            cleaned = sign .. cur:gsub("%D", "")
        else
            cleaned = cur:gsub("%D", "")
        end
        if cleaned ~= cur then
            self:SetText(cleaned)
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
        fill:SetColorTexture(0.20, 0.20, 0.20, 0.95)   -- lighten on focus (no border to highlight)
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        fill:SetColorTexture(0.12, 0.12, 0.12, 0.95)
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

    -- Apply the (possibly live) disabled state: grey + block input, or restore. Call after a config change.
    function result.Refresh()
        if IsDisabled() then
            editBox:Disable(); editBox:ClearFocus()
            editBox:SetTextColor(0.5, 0.5, 0.5, 1)
            fill:SetColorTexture(0.08, 0.08, 0.08, 0.95)
        else
            editBox:Enable()
            editBox:SetTextColor(1, 1, 1, 1)
            fill:SetColorTexture(0.12, 0.12, 0.12, 0.95)
        end
    end
    result.Refresh()

    result.frame   = container
    result.editBox = editBox

    return result
end