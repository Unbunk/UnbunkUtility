-- UI/Shared/DurationEditor.lua
-- Reusable alert duration editor widget.
--
-- Usage:
--   local de = Unbunk_CreateDurationEditor({
--       parent       = panel,
--       anchorFrame  = someFrame,
--       getDuration  = function() return MyCfg_Get("alertDuration") end,
--       onDurationChange = function(val) MyCfg_Set("alertDuration", val) end,
--   })
--   de.frame
--   de.height
--   de.Refresh()

function Unbunk_CreateDurationEditor(config)
    local parent             = config.parent
    local anchorFrame        = config.anchorFrame
    local getDuration        = config.getDuration
    local onDurationChange   = config.onDurationChange

    local result = {}
    local height = 0

    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(518)

    -- ── Label ─────────────────────────────────────────────────────────────────

    local sectionLabel = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sectionLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    sectionLabel:SetText("Alert duration")
    height = height + 20

    -- ── Minus button ──────────────────────────────────────────────────────────

    local minusBtn = Unbunk_CreateButton({
        parent  = container,
        label   = "-",
        width   = 22,
        height  = 22,
    })
    minusBtn.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)

    -- ── Value display ─────────────────────────────────────────────────────────

    local valueBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    valueBox:SetSize(46, 20)
    valueBox:SetPoint("LEFT", minusBtn.frame, "RIGHT", 4, 0)
    valueBox:SetAutoFocus(false)
    valueBox:SetNumeric(true)
    valueBox:SetMaxLetters(3)
    valueBox:SetText(tostring(getDuration() or 5))

    valueBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v and v > 0 then
            onDurationChange(v)
        end
        self:ClearFocus()
    end)

    -- ── Plus button ───────────────────────────────────────────────────────────

    local plusBtn = Unbunk_CreateButton({
        parent  = container,
        label   = "+",
        width   = 22,
        height  = 22,
    })
    plusBtn.frame:SetPoint("LEFT", valueBox, "RIGHT", 4, 0)

    -- ── Seconds label ─────────────────────────────────────────────────────────

    local secLabel = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    secLabel:SetPoint("LEFT", plusBtn.frame, "RIGHT", 6, 0)
    secLabel:SetText("seconds")

    -- ── Button logic ──────────────────────────────────────────────────────────

    minusBtn.frame:SetScript("OnClick", function()
        local v = tonumber(valueBox:GetText()) or getDuration() or 5
        v = math.max(1, v - 1)
        valueBox:SetText(tostring(v))
        onDurationChange(v)
    end)

    plusBtn.frame:SetScript("OnClick", function()
        local v = tonumber(valueBox:GetText()) or getDuration() or 5
        v = math.min(60, v + 1)
        valueBox:SetText(tostring(v))
        onDurationChange(v)
    end)

    height = height + 26

    container:SetHeight(height)
    result.frame  = container
    result.height = height

    function result.Refresh()
        valueBox:SetText(tostring(getDuration() or 5))
    end

    return result
end