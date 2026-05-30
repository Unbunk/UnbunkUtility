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
        -- Intentionally false (unlike the other trackers, which default true):
        -- battle res does not exist in battlegrounds / arenas.
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
    -- Estimated per-player BRes cooldown (seconds) used for the list timers. An
    -- addon can't read another player's real cooldown, so this is a single
    -- heuristic value; the real spell CDs (Rebirth / Raise Ally / Intercession)
    -- are all 600s (10 min). Lower it if you'd rather the list approximate the
    -- shared raid-charge recharge instead.
    listCooldownEstimate = 600,
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

    -- Recursive backfill (also fills newly-added nested keys, e.g. a future
    -- instanceFilter sub-key) so upgraders are not left with nil defaults.
    ns.MergeDefaults(BResTrackerDB, DEFAULTS)
end

ns.RegisterCfgInitHook(BR.CfgInit)

function BR.CfgGet(key)
    local v = BResTrackerDB[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end
function BR.CfgSet(key, value) BResTrackerDB[key] = value end

function BR.PlaySound()
    ns.PlaySoundFromCfg(BResTrackerDB, "soundPathReady", "soundKeyReady")
end

function BR.PlaySoundUsed()
    ns.PlaySoundFromCfg(BResTrackerDB, "soundPathUsed", "soundKeyUsed")
end

local initDB = CreateFrame("Frame")
initDB:RegisterEvent("ADDON_LOADED")
initDB:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    BR.CfgInit()
    self:UnregisterEvent("ADDON_LOADED")
end)
