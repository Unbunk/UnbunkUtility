-- Modules/ShowIDs/UI/ConfigWindow.lua
-- Extra Utilities > Show IDs. Two toggles that append the spell ID / item ID to tooltips.
-- Backed by ns.db.profile.showIDs via ns.ShowIDs.

local _, ns = ...
local L  = ns.L
local SI = ns.ShowIDs

local function CreateShowIDsPanel(parent)
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Show IDs"] },

        { type = "group", title = L["Show IDs"], build = function() return {
            { type = "checkbox", label = L["Show spell IDs in tooltip"],
              get = function() return SI.Get("spell") end,
              set = function(v) SI.Set("spell", v) end },
            { type = "checkbox", label = L["Show item IDs in tooltip"],
              get = function() return SI.Get("item") end,
              set = function(v) SI.Set("item", v) end },
            { type = "checkbox", label = L["Show icon IDs in tooltip"],
              get = function() return SI.Get("icon") end,
              set = function(v) SI.Set("icon", v) end },
            { type = "checkbox", label = L["Show quest IDs in tooltip"],
              get = function() return SI.Get("quest") end,
              set = function(v) SI.Set("quest", v) end },
            { type = "checkbox", label = L["Show NPC IDs in tooltip"],
              get = function() return SI.Get("npc") end,
              set = function(v) SI.Set("npc", v) end },
        } end },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Show IDs"], nil, CreateShowIDsPanel)
end)
