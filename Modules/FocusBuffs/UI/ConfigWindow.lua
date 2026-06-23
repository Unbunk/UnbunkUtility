-- Modules/FocusBuffs/UI/ConfigWindow.lua
-- The owner-only "Focus buffs" tab (under "Personal utilities", gated in Core.lua by
-- debug-unlock AND IsAccountOwner). A single toggle that hides the DEBUFF icons on the
-- default Blizzard FocusFrame while keeping their stack count — see ns.FocusBuffs.

local _, ns = ...
local L = ns.L

-- Wrapping grey H6 description that self-sizes (no overflow).
local function GreyDescription(text)
    return { type = "custom", build = function(host)
        local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
        fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        fs:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetTextColor(0.6, 0.6, 0.6)
        fs:SetText(text)
        local h = math.max(16, math.ceil((fs:GetStringHeight() or 14) + 4))
        host:SetHeight(h)
        return { frame = host, height = h }
    end }
end

local function CreateFocusBuffsPanel(parent)
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Focus buffs"] },
        { type = "group", build = function()
            return {
                GreyDescription(L["Hides the debuff icons on the default Blizzard focus frame while keeping their stack count, so only stacking debuffs stay visible (as a number)."]),
                { type = "checkbox", label = L["Disable focus debuffs (keep stacks)"],
                  get = function() return ns.FocusBuffs and ns.FocusBuffs.Get("enabled") end,
                  set = function(v) if ns.FocusBuffs then ns.FocusBuffs.Set("enabled", v) end end },
            }
        end },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Focus buffs"], nil, CreateFocusBuffsPanel)
end)
