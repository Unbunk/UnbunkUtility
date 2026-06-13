-- Core/DB.lua
-- AceDB-3.0 storage + profile engine. Replaces the legacy per-module SavedVariable
-- globals (BLTrackerDB, PITrackerDB, ...) and the hand-rolled snapshot profile
-- system in Core/Profiles.lua.
--
-- DESIGN — AceDB is used as the storage/profile ENGINE only:
--   * Each module keeps its own DEFAULTS + ns.MergeDefaults (run from CfgInit), so
--     the stored tables stay PHYSICALLY merged with defaults — export/import and
--     ns.MigrateSoundKeys behave exactly as before (no metatable-only defaults).
--   * db.profile.<ModuleKey> replaces each per-module XDB global (profiled data).
--   * db.global.<key> replaces the account-wide settings that lived directly in
--     UnbunkUtilityDB (combo, wipe, dpsSpam, bossReset, minimap, auraDurations).
--
-- REVERSIBLE MIGRATION — on first load the legacy SVs are READ (never cleared) to
-- pre-build UnbunkUtilityAceDB, so the old data stays a frozen backup. Reverting
-- to the previous addon version restores the old behaviour with zero data loss.
--
-- ACCOUNT-WIDE PROFILE — the legacy addon shared ONE "current profile" across all
-- characters (UnbunkUtilityDB.currentProfile). AceDB tracks the current profile
-- per character, so we mirror the legacy behaviour: the shared current profile is
-- stored in db.global.sharedProfile and every character is forced onto it at login
-- and whenever it changes.

local ADDON, ns = ...

local AceDB = LibStub("AceDB-3.0")

-- db.profile key  ->  legacy account-wide SavedVariable global name.
-- Keys match the snapshot module keys used by the legacy ns.profiles (ALL_DBS).
local LEGACY_SV = {
    BLTracker          = "BLTrackerDB",
    PITracker          = "PITrackerDB",
    PotionTracker      = "PotionTrackerDB",
    TrinketTracker     = "TrinketTrackerDB",
    HealthstoneTracker = "HealthstoneTrackerDB",
    BResTracker        = "BResTrackerDB",
    DeathAlert         = "DeathAlertDB",
    HealerRange        = "HealerRangeDB",
    PlayerDeath        = "PlayerDeathDB",
}

-- Cross-profile (account-wide) settings that lived directly in UnbunkUtilityDB.
local GLOBAL_KEYS = { "combo", "wipe", "dpsSpam", "bossReset", "minimap", "auraDurations" }

-- ── One-shot legacy migration ───────────────────────────────────────────────
-- Pre-builds the UnbunkUtilityAceDB saved-variable from the legacy data BEFORE
-- AceDB:New reads it. Only READS legacy SVs, so they remain intact as a backup.
local function MigrateLegacy()
    if type(UnbunkUtilityAceDB) == "table" and UnbunkUtilityAceDB.__legacyMigrated then
        return
    end
    UnbunkUtilityAceDB = UnbunkUtilityAceDB or {}

    -- Fresh install (no legacy data at all): nothing to migrate.
    if type(UnbunkUtilityDB) ~= "table" then
        UnbunkUtilityAceDB.__legacyMigrated = true
        return
    end

    UnbunkUtilityAceDB.profiles = UnbunkUtilityAceDB.profiles or {}
    UnbunkUtilityAceDB.global   = UnbunkUtilityAceDB.global   or {}

    -- 1) Account-wide globals (combo/wipe/dpsSpam/bossReset/minimap/auraDurations).
    for _, k in ipairs(GLOBAL_KEYS) do
        if UnbunkUtilityDB[k] ~= nil and UnbunkUtilityAceDB.global[k] == nil then
            UnbunkUtilityAceDB.global[k] = ns.DeepCopy(UnbunkUtilityDB[k])
        end
    end

    -- 2) Saved profile snapshots: { [profileName] = { [moduleKey] = data } }.
    for profName, snapshot in pairs(UnbunkUtilityDB.profiles or {}) do
        local p = UnbunkUtilityAceDB.profiles[profName] or {}
        if type(snapshot) == "table" then
            for moduleKey in pairs(LEGACY_SV) do
                if snapshot[moduleKey] ~= nil then
                    p[moduleKey] = ns.DeepCopy(snapshot[moduleKey])
                end
            end
        end
        UnbunkUtilityAceDB.profiles[profName] = p
    end

    -- 3) The LIVE state sits in the per-module SV globals (possibly newer than the
    --    last snapshot). Fold it into the current profile so nothing live is lost.
    local current = UnbunkUtilityDB.currentProfile or "Default"
    local cur = UnbunkUtilityAceDB.profiles[current] or {}
    for moduleKey, svName in pairs(LEGACY_SV) do
        local live = _G[svName]
        if type(live) == "table" then
            cur[moduleKey] = ns.DeepCopy(live)
        end
    end
    UnbunkUtilityAceDB.profiles[current] = cur

    -- 4) Record the shared current profile so every character adopts it (mirrors
    --    the legacy account-wide single current profile).
    UnbunkUtilityAceDB.global.sharedProfile = current

    UnbunkUtilityAceDB.__legacyMigrated = true
end

-- ── Profile (re)apply ────────────────────────────────────────────────────────
-- Re-merge each module's defaults + sound-key migration into the active profile,
-- then have every module re-apply its settings. Driven off the existing hook
-- registries so no module can be forgotten.
local function ApplyProfileReload()
    ns.RunCfgInitHooks()
    ns.RunReloadHooks()
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────
local function Bootstrap()
    MigrateLegacy()

    -- defaults = nil: modules keep their own DEFAULTS + ns.MergeDefaults, so stored
    -- tables stay physically merged. "Default" keeps fresh characters on a shared
    -- profile name rather than a per-character one.
    ns.db = AceDB:New("UnbunkUtilityAceDB", nil, "Default")

    -- The saved variables (incl. the account-wide language override ns.db.global.locale)
    -- are now loaded: point ns.L at the chosen locale BEFORE any module registers its
    -- localized config panels (their ADDON_LOADED handlers run after this bootstrap).
    if ns.ApplyLocale then ns.ApplyLocale() end

    -- Account-wide current profile: force this character onto the shared profile.
    local shared = ns.db.global.sharedProfile
    if shared and ns.db:GetCurrentProfile() ~= shared then
        ns.db:SetProfile(shared)   -- fires OnProfileChanged (handler below)
    end

    -- Keep the shared profile in sync and re-apply modules on any profile change.
    local function OnProfileChange()
        ns.db.global.sharedProfile = ns.db:GetCurrentProfile()
        ApplyProfileReload()
    end
    ns.db.RegisterCallback(ns, "OnProfileChanged", function() OnProfileChange() end)
    ns.db.RegisterCallback(ns, "OnProfileCopied",  function() OnProfileChange() end)
    ns.db.RegisterCallback(ns, "OnProfileReset",   function() OnProfileChange() end)

    -- Initial defaults merge + module apply for the active profile. (Reload hooks
    -- also run later from the modules' own PLAYER_LOGIN frames; running CfgInit now
    -- guarantees db.profile.* / db.global.* are populated before any CfgGet.)
    ns.RunCfgInitHooks()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, addonName)
    if addonName ~= ADDON then return end
    Bootstrap()
    self:UnregisterEvent("ADDON_LOADED")
end)
