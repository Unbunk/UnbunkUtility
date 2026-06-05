-- Modules/DeathAlert/Core/Config.lua

local _, ns = ...
local L = ns.L
ns.DeathAlert = ns.DeathAlert or {}
local DA = ns.DeathAlert

local DEFAULTS = {
    -- Tank alert
    tankEnabled      = true,
    tankSoundKey     = "UnbunkUtility: Tank Died High",
    tankSoundPath    = nil,
    tankEnableSound  = true,
    tankFontKey      = "2002 Bold",
    tankFontPath     = nil,
    tankFontSize     = 26,
    tankOutline      = "OUTLINE",
    tankMessage      = L["Tank died"],
    tankColor        = { r = 1.0, g = 0.5, b = 0.0, a = 1.0 },
    tankPosX         = 0,
    tankPosY         = 350,
    tankAlertDuration   = 3,
    -- Healer alert
    healerEnabled     = true,
    healerSoundKey    = "UnbunkUtility: Healer Died High",
    healerSoundPath   = nil,
    healerEnableSound = true,
    healerFontKey     = "2002 Bold",
    healerFontPath    = nil,
    healerFontSize    = 22,
    healerOutline     = "OUTLINE",
    healerMessage     = L["Healer died"],
    healerColor       = { r = 0.0, g = 0.5, b = 1.0, a = 1.0 },
    healerPosX        = 0,
    healerPosY        = 275,
    healerAlertDuration = 3,
    -- DPS alert
    dpsEnabled     = false,
    dpsSoundKey    = "UnbunkUtility: DPS Died High",
    dpsSoundPath   = nil,
    dpsEnableSound = true,
    dpsFontKey     = "2002 Bold",
    dpsFontPath    = nil,
    dpsFontSize    = 18,
    dpsOutline     = "OUTLINE",
    dpsMessage     = L["DPS died"],
    dpsColor       = { r = 0.4, g = 0.8, b = 1.0, a = 1.0 },
    dpsPosX        = 0,
    dpsPosY        = 215,
    dpsAlertDuration = 2,
    -- When on, deaths of members with no assigned group role (UnitGroupRolesAssigned
    -- == "NONE", common in manually-formed / world groups) are treated as DPS:
    -- they fire the DPS alert and count toward the dpsSpam threshold. Off by
    -- default so behaviour is unchanged unless explicitly enabled.
    dpsAlertUnassigned = false,
    tankIcon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\TankDied.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 45,
        height     = 60,
    },
    healerIcon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\HealerDied.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 40,
        height     = 50,
    },
    dpsIcon = {
        enabled    = true,
        iconPath   = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\DPSDied.tga",
        useCustom  = false,
        customId   = nil,
        position   = "TOP_CENTER",
        width      = 25,
        height     = 35,
    },
    tankInstanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = false,
    },
    healerInstanceFilter = {
        dungeon      = true,
        raid         = true,
        battleground = false,
        outdoor      = false,
    },
    dpsInstanceFilter = {
        dungeon      = true,
        raid         = false,
        battleground = false,
        outdoor      = false,
    },
}

function DA.CfgInit()
    ns.db.profile.DeathAlert = ns.db.profile.DeathAlert or {}
    ns.MigrateSoundKeys(ns.db.profile.DeathAlert)
    ns.MergeDefaults(ns.db.profile.DeathAlert, DEFAULTS)
end

ns.RegisterCfgInitHook(DA.CfgInit)

function DA.CfgGet(key)
    local t = ns.db and ns.db.profile.DeathAlert
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function DA.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.DeathAlert = ns.db.profile.DeathAlert or {}
    ns.db.profile.DeathAlert[key] = value
end

function DA.PlaySound(prefix)
    if not DA.CfgGet(prefix .. "EnableSound") then return end
    -- Delegates to the shared resolver (explicit path > migrated LSM key >
    -- nothing). Plays nothing when neither resolves, matching the other
    -- trackers and avoiding a surprise default chime on a missing sound.
    ns.PlaySoundFromCfg(ns.db and ns.db.profile.DeathAlert, prefix .. "SoundPath", prefix .. "SoundKey")
end