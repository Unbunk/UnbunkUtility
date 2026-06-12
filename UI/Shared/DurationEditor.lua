-- UI/Shared/DurationEditor.lua
-- Reusable alert duration editor widget.
--
-- Usage:
--   local de = ns.ui.CreateDurationEditor({
--       parent       = panel,
--       getDuration  = function() return MyCfg_Get("alertDuration") end,
--       onDurationChange = function(val) MyCfg_Set("alertDuration", val) end,
--   })
--   de.frame   -- container is sized but not self-anchored; the caller positions it
--   de.height
--   de.Refresh()

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

function ns.ui.CreateDurationEditor(config)
    local parent             = config.parent
    local getDuration        = config.getDuration
    local onDurationChange   = config.onDurationChange

    local result = {}
    local height = 0

    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(518)

    -- ── Label ─────────────────────────────────────────────────────────────────

    local sectionLabel = container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
    sectionLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    sectionLabel:SetText(L["Alert duration"])
    height = height + 20

    -- ── Minus button ──────────────────────────────────────────────────────────

    local minusBtn = ns.ui.CreateButton({
        parent  = container,
        label   = "-",
        width   = 22,
        height  = 22,
    })
    minusBtn.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)

    -- ── Value display ─────────────────────────────────────────────────────────

    local valueInput = ns.ui.CreateTextInput({
        parent     = container,
        width      = 46,
        height     = 22,
        numeric    = true,
        min        = 1,
        max        = 60,
        maxLetters = 3,
        text       = tostring(getDuration() or 5),
        onEnter    = function(val)
            if val and val > 0 then onDurationChange(val) end
        end,
    })
    valueInput.frame:SetPoint("LEFT", minusBtn.frame, "RIGHT", 4, 0)
    local valueBox = valueInput.editBox

    -- ── Plus button ───────────────────────────────────────────────────────────

    local plusBtn = ns.ui.CreateButton({
        parent  = container,
        label   = "+",
        width   = 22,
        height  = 22,
    })
    plusBtn.frame:SetPoint("LEFT", valueBox, "RIGHT", 4, 0)

    -- ── Seconds label ─────────────────────────────────────────────────────────

    local secLabel = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    secLabel:SetPoint("LEFT", plusBtn.frame, "RIGHT", 6, 0)
    secLabel:SetText(L["seconds"])

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