-- Modules/DecursiveMove/UI/ConfigWindow.lua
-- The owner-only "Decursive special settings" tab (under "Personal utilities", gated in
-- Core.lua by debug-unlock AND IsAccountOwner). Unlock to drag Decursive's Micro-Unit-Frame
-- container, lock when done, or reset it to the default corner — see ns.DecursiveMove.

local _, ns = ...
local L = ns.L
local DM = ns.DecursiveMove

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

local function CreateDecursivePanel(parent)
    local menu
    local function rebuild() if menu then menu.Rebuild() end end

    -- Lock the mover whenever this panel is hidden (config closed / tab switched) so the
    -- drag overlay can never linger over the MUFs and swallow curing clicks.
    parent:HookScript("OnHide", function() if DM and DM.SetUnlocked then DM.SetUnlocked(false) end end)

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Decursive special settings"] },
        { type = "group", title = L["Move Micro Unit Frame"], build = function()
            if not (DM and DM.IsAvailable()) then
                return {
                    { type = "custom", height = 18, build = function(host)
                        local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                        fs:SetPoint("LEFT", host, "LEFT", 0, 0)
                        fs:SetTextColor(1, 0.5, 0.2)
                        fs:SetText(L["Decursive not detected — install / enable it for this to work."])
                        return { frame = host, height = 18 }
                    end },
                }
            end
            return {
                GreyDescription(L["Unlock, then drag the Decursive Micro Unit Frame to reposition it; lock when you are done. (Out of combat only — the MUFs must be visible.)"]),
                -- Unlock / Lock toggle.
                { type = "custom", height = 30, build = function(host)
                    local btn
                    local function refresh() btn.SetText(DM.IsUnlocked() and L["Lock"] or L["Unlock"]) end
                    btn = ns.ui.CreateButton({
                        parent = host, label = L["Unlock"], width = 120, height = 22,
                        onClick = function() DM.SetUnlocked(not DM.IsUnlocked()); refresh() end,
                    })
                    btn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -4)
                    return { frame = host, height = 30, Refresh = refresh }
                end },
                -- Reset to Decursive's default corner.
                { type = "button", label = L["Reset"], width = 120, height = 22, hostHeight = 28,
                  onClick = function() if DM.Reset then DM.Reset() end end },
            }
        end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Decursive special settings"], nil, CreateDecursivePanel)
end)
