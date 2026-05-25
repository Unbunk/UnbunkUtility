-- Media/Media.lua
-- Registers all UnbunkUtility media into LibSharedMedia.

local initMedia = CreateFrame("Frame")
initMedia:RegisterEvent("ADDON_LOADED")
initMedia:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ADDON_PATH = "Interface\\AddOns\\UnbunkUtility\\Media\\"
        local sounds = {
            ["UnbunkUtility: No Heal"] = ADDON_PATH .. "Sounds\\NoHeal.mp3",
        }
        for name, path in pairs(sounds) do
            LSM:Register("sound", name, path)
        end
    end
    self:UnregisterEvent("ADDON_LOADED")
end)