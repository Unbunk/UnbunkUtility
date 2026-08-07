-- UI/Shared/InstanceFilter.lua
-- Reusable instance type filter widget.
--
-- Usage:
--   local iF = ns.ui.CreateInstanceFilter({
--       parent   = panel,
--       getConfig = function() return MyCfg_Get("instanceFilter") end,
--       setConfig = function(key, val) MyCfg_Set("instanceFilter."..key, val) end,
--   })
--   iF.frame
--   iF.height
--   iF.Refresh()

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

function ns.ui.CreateInstanceFilter(config)
    local parent    = config.parent
    local getConfig = config.getConfig
    local setConfig = config.setConfig

    local result = {}
    local height = 0

    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(518)

    local sectionLabel = container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
    sectionLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    sectionLabel:SetText(L["Active in"])
    height = height + 20

    local filters = {
        { key = "dungeon",     label = L["Dungeon"]     },
        { key = "raid",        label = L["Raid"]        },
        { key = "battleground",label = L["Battleground"]},
        { key = "outdoor",     label = L["Outdoor"]     },
    }

    local checkboxes = {}
    local x = 0
    local rowHeight = 24
    local perRow = 4

    for i, filter in ipairs(filters) do
        local cfg = getConfig() or {}
        local cb = ns.ui.CreateCheckbox({
            parent  = container,
            label   = filter.label,
            checked = cfg[filter.key] ~= false,
            onClick = function(val)
                setConfig(filter.key, val)
            end,
        })
        cb.frame:SetPoint("TOPLEFT", container, "TOPLEFT", x, -height)
        cb.frame:SetWidth(120)
        checkboxes[filter.key] = cb

        x = x + 130
        -- Wrap to a new row only when another checkbox follows, so the last
        -- (possibly partial) row does not reserve an extra empty row of height.
        if i % perRow == 0 and i < #filters then
            x = 0
            height = height + rowHeight
        end
    end

    -- Account for the height of the final row.
    height = height + rowHeight

    container:SetHeight(height)
    result.frame  = container
    result.height = height

    function result.Refresh()
        local cfg = getConfig() or {}
        for key, cb in pairs(checkboxes) do
            cb.SetChecked(cfg[key] ~= false)
        end
    end

    return result
end