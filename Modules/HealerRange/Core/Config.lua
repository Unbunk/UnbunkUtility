-- Modules/HealerRange/Core/Config.lua

local _, ns = ...
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

HealerRangeDB = HealerRangeDB or {}

local DEFAULTS = {
    enabled       = true,
    soundPath     = nil,
    soundKey      = "UnbunkUtility: No Heal",
    enableSound   = true,
    fontPath      = nil,
    fontKey       = "2002 Bold",
    fontSize      = 22,
    outline       = "OUTLINE",
    alertMessage  = "No Heal",
    color         = { r = 1.0, g = 0.059, b = 0.0, a = 1.0 },
    posX          = 0,
    posY          = 100,
    alertDuration = 5,
    icon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\NoHeal.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 32,
        height     = 32,
    },
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = false,
    },
}

local FALLBACK_SOUND_ID = 8959
local FALLBACK_SOUND_NAME = "UnbunkUtility: No Heal"

function HR.CfgInit()
    for k, v in pairs(DEFAULTS) do
        if HealerRangeDB[k] == nil then
            if type(v) == "table" then
                HealerRangeDB[k] = {}
                for k2, v2 in pairs(v) do
                    HealerRangeDB[k][k2] = v2
                end
            else
                HealerRangeDB[k] = v
            end
        end
    end
end

function HR.CfgGet(key)
    return HealerRangeDB[key]
end

function HR.CfgSet(key, value)
    HealerRangeDB[key] = value
end

function HR.PlaySound()
    if not HR.CfgGet("enableSound") then return end
    local path = HR.CfgGet("soundPath")
    if path then
        PlaySoundFile(path, "Master")
    else
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local fallbackPath = LSM and LSM:Fetch("sound", FALLBACK_SOUND_NAME)
        if fallbackPath then
            PlaySoundFile(fallbackPath, "Master")
        else
            PlaySound(FALLBACK_SOUND_ID)
        end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    HR.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)