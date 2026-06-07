-- UI/Shared/Reorder.lua
-- Two arrow buttons ( < > ) to move an item left/right within a row. A direction
-- is greyed out (disabled, dimmed) when the move is unavailable.
--
-- Usage:
--   local r = ns.ui.CreateReorder({
--       parent   = panel,
--       label    = "Move in row",
--       getState = function() return canLeft, canRight end,  -- booleans
--       onMove   = function(dir) ... end,                    -- dir = -1 / +1
--   })
--   r.frame
--   r.Refresh()   -- re-reads getState() to update the enabled/dimmed state

local _, ns = ...
ns.ui = ns.ui or {}

function ns.ui.CreateReorder(config)
    local parent   = config.parent
    local label    = config.label
    local getState = config.getState or function() return false, false end
    local onMove   = config.onMove   or function() end

    local result    = {}
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 24)

    local anchorRight = container
    local anchorPoint, gap = "LEFT", 0
    if label then
        local fs = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fs:SetPoint("LEFT", container, "LEFT", 0, 0)
        fs:SetText(label)
        anchorRight, anchorPoint, gap = fs, "RIGHT", 10
    end

    local function Refresh()
        local canL, canR = getState()
        result.left.frame:SetEnabled(canL and true or false)
        result.left.frame:SetAlpha(canL and 1 or 0.4)
        result.right.frame:SetEnabled(canR and true or false)
        result.right.frame:SetAlpha(canR and 1 or 0.4)
    end
    result.Refresh = Refresh

    result.left = ns.ui.CreateButton({
        parent = container, label = "<", width = 26, height = 22,
        onClick = function() onMove(-1); Refresh() end,
    })
    result.right = ns.ui.CreateButton({
        parent = container, label = ">", width = 26, height = 22,
        onClick = function() onMove(1); Refresh() end,
    })
    result.left.frame:SetPoint("LEFT", anchorRight, anchorPoint, gap, 0)
    result.right.frame:SetPoint("LEFT", result.left.frame, "RIGHT", 6, 0)

    Refresh()
    result.frame = container
    return result
end
