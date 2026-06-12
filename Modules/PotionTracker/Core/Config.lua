-- Modules/PotionTracker/Core/Config.lua

local _, ns = ...
ns.PotionTracker = ns.PotionTracker or {}
local PT = ns.PotionTracker

PotionTrackerDB = PotionTrackerDB or {}

local DEFAULTS = {
    enabled         = true,
    instanceFilter  = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = true,
    },
    health = {
        enabled         = true,
        showIcon        = true,
        showAtZero      = false,  -- keep the icon visible even with 0 potions in bags
        -- itemId/spellId left unset on a fresh install: the main dropdown
        -- shows "None" until the player picks a potion or the resolver
        -- auto-fills via fallback / favorite.
        favoriteEnabled = true,
        favoriteId      = 241304,  -- Silvermoon Health Potion
        posX          = -400,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        showStack       = true,
        stackFontKey    = "2002 Bold",
        stackFontPath   = nil,
        stackFontSize   = 12,
        stackOutline    = "OUTLINE",
        stackColor      = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Health Potion (High)",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Health Potion Ready (High)",
        soundPathReady= nil,
    },
    combat = {
        enabled         = true,
        showIcon        = true,
        showAtZero      = false,  -- keep the icon visible even with 0 potions in bags
        -- itemId/spellId left unset on a fresh install (see health section).
        favoriteEnabled = true,
        favoriteId      = 241308,  -- Light's Potential
        showStack       = true,
        stackFontKey    = "2002 Bold",
        stackFontPath   = nil,
        stackFontSize   = 12,
        stackOutline    = "OUTLINE",
        stackColor      = { r=1, g=1, b=1, a=1 },
        posX          = -370,
        posY          = -300,
        iconWidth     = 30,
        iconHeight    = 30,
        timerFontKey  = "2002 Bold",
        timerFontPath = nil,
        timerFontSize = 20,
        timerOutline  = "OUTLINE",
        timerColor    = { r=1, g=1, b=1, a=1 },
        soundOnUse    = true,
        soundKeyUse   = "UnbunkUtility: Combat Potion (High)",
        soundPathUse  = nil,
        soundOnReady  = true,
        soundKeyReady = "UnbunkUtility: Combat Potion Ready (High)",
        soundPathReady= nil,
    },
}

-- Recursively merge defaults into target: only adds missing keys, never
-- overwrites user-set values. Crucially, recurses into existing sub-tables
-- so newly-introduced keys (e.g. stackColor) are populated for upgraders
-- without forcing a profile Reset.
local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                MergeDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            MergeDefaults(target[k], v)
        end
    end
end

function PT.CfgInit()
    ns.MigrateSoundKeys(PotionTrackerDB)
    MergeDefaults(PotionTrackerDB, DEFAULTS)
end

function PT.CfgGet(key)
    return PotionTrackerDB[key]
end

function PT.CfgSet(key, value)
    PotionTrackerDB[key] = value
    -- Config drives which potion the resolver picks; invalidate the cache
    -- so the next GetActiveItemId() reflects the change.
    if PT.InvalidateActiveCache then PT.InvalidateActiveCache() end
end

function PT.PlaySound(prefix, key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local cfg = PT.CfgGet(prefix)
    if not cfg then return end
    local pathKey, soundKeyKey
    if key == "soundUse" then
        pathKey    = "soundPathUse"
        soundKeyKey = "soundKeyUse"
    elseif key == "soundReady" then
        pathKey    = "soundPathReady"
        soundKeyKey = "soundKeyReady"
    else
        return
    end
    local path = cfg[pathKey]
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = cfg[soundKeyKey]
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    PT.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)