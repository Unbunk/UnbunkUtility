-- Media/Media.lua
-- Registers all UnbunkUtility media into LibSharedMedia.

local initMedia = CreateFrame("Frame")
initMedia:RegisterEvent("ADDON_LOADED")
initMedia:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ADDON_PATH = "Interface\\AddOns\\UnbunkUtility\\Media\\"

        -- Bundled font (OFL): the addon-wide default. Registered here so the
        -- "Fira Mono" default resolves to a real face without any external media
        -- addon (ns.ResolveFontPath only falls back to FRIZQT when LSM is absent).
        LSM:Register("font", "Fira Mono", ADDON_PATH .. "Fonts\\FiraMono-Regular.ttf")

        -- Bundled statusbar texture so the cast bar's "Better Blizzard" default resolves
        -- without any external media pack. (Skips re-registering if another addon already
        -- provided it, so we never stomp a user's existing copy.)
        if not LSM:IsValid("statusbar", "Better Blizzard") then
            LSM:Register("statusbar", "Better Blizzard", ADDON_PATH .. "Textures\\BetterBlizzard.blp")
        end

        -- Sounds available in every loudness variant (High / Medium / Low /
        -- Loud). Every LSM key carries its loudness in parentheses so the
        -- picker reads e.g. "BL Ready (Loud)"; module defaults explicitly
        -- select the High variant. (The legacy un-parenthesised keys are
        -- rewritten to this form by ns.MigrateSoundKeys.)
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
            { key = "Trinket Combo",       file = "TrinketCombo" },
            { key = "Trinket Ready",       file = "TrinketReady" },
        }
        local VARIANTS = { "High", "Medium", "Low", "Loud" }
        for _, s in ipairs(BASE_SOUNDS) do
            for _, v in ipairs(VARIANTS) do
                LSM:Register("sound", "UnbunkUtility: " .. s.key .. " (" .. v .. ")",
                    ADDON_PATH .. "Sounds\\" .. v .. "\\" .. s.file .. v .. ".mp3")
            end
        end

        -- Racial / Racial Ready: same High/Medium/Low/Loud variants, but the
        -- source files were added with a SPACE before the loudness
        -- ("Racial High.mp3", "Racial Ready High.mp3") rather than the
        -- concatenated "<file><variant>.mp3" the loop above expects — so register
        -- them with their own space-separated path.
        local RACIAL_SOUNDS = {
            { key = "Racial",       base = "Racial" },
            { key = "Racial Ready", base = "Racial Ready" },
        }
        for _, s in ipairs(RACIAL_SOUNDS) do
            for _, v in ipairs(VARIANTS) do
                LSM:Register("sound", "UnbunkUtility: " .. s.key .. " (" .. v .. ")",
                    ADDON_PATH .. "Sounds\\" .. v .. "\\" .. s.base .. " " .. v .. ".mp3")
            end
        end

        -- FAHH lives at the Sounds root, no loudness variants.
        LSM:Register("sound", "UnbunkUtility: FAHH",
            ADDON_PATH .. "Sounds\\FAHH.mp3")

        -- Disappear: single-file "boss reset / wipe" sound, no loudness variants.
        LSM:Register("sound", "UnbunkUtility: Disappear",
            ADDON_PATH .. "Sounds\\Disappear.mp3")
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

-- Textures
local ICON_PATH = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\"
-- White glyphs tinted to the brand blue at use-time via SetVertexColor (same
-- approach as the close cross), so the blue matches the rest of the addon and no
-- pre-coloured image is needed. Tinted by: the dropdown arrow in Dropdown.lua /
-- CollapsibleSection.lua / Core.lua, and the speaker in SoundPicker.lua.
UNBUNK_ICON_DROPDOWN_ARROW = ICON_PATH .. "DownArrowWhite.tga"
UNBUNK_ICON_SPEAKER_ON     = ICON_PATH .. "WhiteSpeakerOn.tga"
UNBUNK_ICON_SPEAKER_OFF    = ICON_PATH .. "WhiteSpeakerOff.tga"
UNBUNK_ICON_CROSS_WHITE    = ICON_PATH .. "WhiteCross.tga"
UNBUNK_ICON_CROSS_BLUE     = ICON_PATH .. "BlueCross.tga"
UNBUNK_ICON_PEPE_EZ        = ICON_PATH .. "PepeEz.tga"
UNBUNK_ICON_PLUS_GREEN     = ICON_PATH .. "GreenPlus.tga"
UNBUNK_ICON_PEN_WHITE      = ICON_PATH .. "WhitePen.tga"

-- Icon list for the icon pickers. These are plain .tga files and do not
-- depend on LibSharedMedia, so populate them unconditionally at load time
-- (previously this lived inside the LSM-gated ADDON_LOADED block, which made
-- the icon list silently disappear when LSM was absent).
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