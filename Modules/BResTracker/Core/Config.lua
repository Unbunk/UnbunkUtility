-- Modules/BResTracker/Core/Config.lua

local _, ns = ...
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

BResTrackerDB = BResTrackerDB or {}

local DEFAULTS = {
    enabled        = true,
    showIcon       = true,
    iconWidth      = 45,
    iconHeight     = 45,
    posX           = -610,
    posY           = -290,
    timerFontKey   = "2002 Bold",
    timerFontPath  = nil,
    timerFontSize  = 14,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    countFontSize  = 16,
    soundOnReady   = true,
    soundKeyReady  = "UnbunkUtility: BRez Ready Medium",
    soundPathReady = nil,
    soundOnUsed    = true,
    soundKeyUsed   = "UnbunkUtility: BRez Used Medium",
    soundPathUsed  = nil,
    instanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = true,
    },
    -- Optional player list submodule
    listEnabled       = false,
    listSide          = "Left",    -- "Left" / "Right" / "Above" / "Below"
    listOffset        = 8,         -- pixel gap between icon and list
    rowStatusSide     = "Left",    -- "Left" / "Right" / "Above" / "Below"
    listRowHeight     = 18,        -- cell height (per text line)
    listFontSize      = 14,
    listFontPath      = nil,
    listFontKey       = "2002 Bold",
    listOutline       = "OUTLINE",
}

function BR.CfgInit()
    ns.MigrateSoundKeys(BResTrackerDB)
    -- Migrate older boolean keys to the new "side" string keys.
    if BResTrackerDB.listOnRight ~= nil and BResTrackerDB.listSide == nil then
        BResTrackerDB.listSide = BResTrackerDB.listOnRight and "Right" or "Left"
        BResTrackerDB.listOnRight = nil
    end
    if BResTrackerDB.rowStatusOnRight ~= nil and BResTrackerDB.rowStatusSide == nil then
        BResTrackerDB.rowStatusSide = BResTrackerDB.rowStatusOnRight and "Right" or "Left"
        BResTrackerDB.rowStatusOnRight = nil
    end

    for k, v in pairs(DEFAULTS) do
        if BResTrackerDB[k] == nil then
            if type(v) == "table" then
                BResTrackerDB[k] = {}
                for k2, v2 in pairs(v) do
                    BResTrackerDB[k][k2] = v2
                end
            else
                BResTrackerDB[k] = v
            end
        end
    end
end

function BR.CfgGet(key) return BResTrackerDB[key] end
function BR.CfgSet(key, value) BResTrackerDB[key] = value end

function BR.PlaySound()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = BR.CfgGet("soundPathReady")
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = BR.CfgGet("soundKeyReady")
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

function BR.PlaySoundUsed()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = BR.CfgGet("soundPathUsed")
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = BR.CfgGet("soundKeyUsed")
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    BR.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)
