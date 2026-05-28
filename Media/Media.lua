-- Media/Media.lua
-- Registers all UnbunkUtility media into LibSharedMedia.

local initMedia = CreateFrame("Frame")
initMedia:RegisterEvent("ADDON_LOADED")
initMedia:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ADDON_PATH = "Interface\\AddOns\\UnbunkUtility\\Media\\"

        -- Sounds available in every loudness variant (High / Medium / Low /
        -- Loud). Every LSM key carries its loudness suffix so the picker is
        -- unambiguous; module defaults explicitly select the High variant.
        local BASE_SOUNDS = {
            { key = "BL",                  file = "BL" },
            { key = "Bloodlust",           file = "Bloodlust" },
            { key = "Bloodlust Combo",     file = "BloodlustCombo" },
            { key = "BL Ready",            file = "BLReady" },
            { key = "BRez Ready",          file = "BRezReady" },
            { key = "BRez Used",           file = "BRezUsed" },
            { key = "Combat Potion",       file = "CombatPotion" },
            { key = "Combat Potion Ready", file = "CombatPotionReady" },
            { key = "DPS Died",            file = "DPSDied" },
            { key = "Drink",               file = "Drink" },
            { key = "Healer Died",         file = "HealerDied" },
            { key = "Health Potion",       file = "HealthPotion" },
            { key = "Health Potion Ready", file = "HealthPotionReady" },
            { key = "Healthstone",         file = "Healthstone" },
            { key = "Healthstone Ready",   file = "HealthstoneReady" },
            { key = "No Heal",             file = "NoHeal" },
            { key = "PI",                  file = "PI" },
            { key = "Potion Combo",        file = "PotionCombo" },
            { key = "Potion Ready",        file = "PotionReady" },
            { key = "Tank Died",           file = "TankDied" },
            { key = "Trinket",             file = "Trinket" },
            { key = "Trinket Combo",       file = "Trinket Combo" },
            { key = "Trinket Ready",       file = "TrinketReady" },
        }
        local VARIANTS = { "High", "Medium", "Low", "Loud" }
        for _, s in ipairs(BASE_SOUNDS) do
            for _, v in ipairs(VARIANTS) do
                LSM:Register("sound", "UnbunkUtility: " .. s.key .. " " .. v,
                    ADDON_PATH .. "Sounds\\" .. v .. "\\" .. s.file .. v .. ".mp3")
            end
        end

        -- FAHH lives at the Sounds root, no loudness variants.
        LSM:Register("sound", "UnbunkUtility: FAHH",
            ADDON_PATH .. "Sounds\\FAHH.mp3")

        local ICON_PATH = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\"
        UNBUNK_ICONS = {
            { label = "Unbunk",      path = ICON_PATH .. "Unbunk.tga"    },
            { label = "No Heal",     path = ICON_PATH .. "NoHeal.tga"     },
            { label = "Green Check", path = ICON_PATH .. "GreenCheck.tga" },
            { label = "Healer",      path = ICON_PATH .. "Healer.tga"     },
            { label = "Tank",        path = ICON_PATH .. "Tank.tga"       },
            { label = "DPS",         path = ICON_PATH .. "DPS.tga"        },
            { label = "Healer Died", path = ICON_PATH .. "HealerDied.tga" },
            { label = "Tank Died",   path = ICON_PATH .. "TankDied.tga"   },
            { label = "DPS Died",    path = ICON_PATH .. "DPSDied.tga"    },
        }
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

-- Textures
local ICON_PATH = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\"
UNBUNK_ICON_DROPDOWN_ARROW = "Interface\\Buttons\\Arrow-Down-Up"

-- Animations
UNBUNK_ANIMATIONS = {
    {
        label      = "Vinland Saga",
        path       = "Interface\\AddOns\\UnbunkUtility\\Media\\Animations\\Vinland Saga Animation\\Vinland Saga Animation GIF-",
        frameCount = 49,
    },
    {
        label      = "Dance Skeleton",
        path       = "Interface\\AddOns\\UnbunkUtility\\Media\\Animations\\Dance Skeleton Animation\\Dance Skeleton GIF-",
        frameCount = 10,
    },
}