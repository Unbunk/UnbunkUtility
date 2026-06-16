-- Modules/DetailsProfile/Core/DetailsProfile.lua
-- Owner utility: drive the Details! damage-meter by context using a user-defined list
-- of "profiles". Each profile names a Details! profile to apply and carries two
-- independent criteria cadres — one keyed on the GROUP composition (solo / party /
-- raid / custom member-count ranges) and one on the INSTANCE type (outdoor / dungeon /
-- raid / battleground). When a criterion matches the current context the profile can
-- (a) apply its named Details! profile and/or (b) FADE the Details! window(s) to a low
-- alpha so the meter dims without fully disappearing. Leaving the matching context
-- restores full opacity.
--
-- Profile switching is skipped in combat (it would reset the meter windows mid-fight)
-- and deferred to PLAYER_REGEN_ENABLED; fading is a plain frame-alpha change so it is
-- applied immediately. Per-profile config (ns.db.profile.detailsSwitch) so a profile
-- reset clears the list; the module is disabled by default and only reachable from the
-- owner-gated "Personal utilities" panel.

local ADDON, ns = ...
ns.DetailsProfile = ns.DetailsProfile or {}
local DP = ns.DetailsProfile

-- A profile with "Fade Details!" on dims the meter to its configured opacity (a
-- percentage) instead of hiding it; new profiles default to 30% (matching ns.Fader).
local DEFAULT_FADE_OPACITY = 30

local function PctToAlpha(pct)
    local a = (tonumber(pct) or DEFAULT_FADE_OPACITY) / 100
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

-- Template for a single profile entry. New profiles deep-copy this; existing ones are
-- backfilled key-by-key in InitCfg so older saved profiles gain any new fields.
local PROFILE_DEFAULTS = {
    changeProfile = false,                 -- "Change Details! profile" master for this entry
    profileName   = "",                    -- Details! profile to apply when a criterion matches
    fadeDetails   = false,                 -- fade the meter (instead of hide) when a criterion matches
    fadeOpacity   = DEFAULT_FADE_OPACITY,  -- % opacity to fade to
    group = {                              -- "Change with group" cadre
        enabled = false,
        solo    = false,                   -- not in a group
        group   = false,                   -- party of 2-5
        raid    = false,                   -- raid group
        custom  = {},                      -- { { enabled = true, min = 1, max = 5 }, ... }
    },
    instance = {                           -- "Change with instance" cadre
        enabled      = false,
        outdoor      = false,              -- open world (instType "none")
        dungeon      = false,              -- 5-player ("party")
        raid         = false,              -- raid instance ("raid")
        battleground = false,              -- ("pvp")
    },
    combat = {                             -- "Change only in combat state :" gate
        enabled = false,
        state   = "in",                    -- "in" | "out": restrict matching to this state
    },
}
DP.PROFILE_DEFAULTS = PROFILE_DEFAULTS

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.detailsSwitch end
DP.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    -- One-shot migration: detailsSwitch used to live in ns.db.global (account-wide), so a
    -- profile reset never cleared the user's created profiles. Fold the legacy global blob
    -- into the CURRENT profile once, then drop it + flag done so a later reset truly wipes
    -- the list. Only the active profile inherits the old shared data; others start empty.
    if ns.db.global.detailsSwitch and not ns.db.global.detailsSwitchMigrated then
        if p.detailsSwitch == nil then
            p.detailsSwitch = ns.DeepCopy(ns.db.global.detailsSwitch)
        end
        ns.db.global.detailsSwitch = nil
        ns.db.global.detailsSwitchMigrated = true
    end
    p.detailsSwitch = p.detailsSwitch or {}
    local c = p.detailsSwitch
    -- Drop the pre-redesign single-context keys (mode / raidProfile / dungeonProfile).
    c.mode = nil; c.raidProfile = nil; c.dungeonProfile = nil
    if c.enabled == nil then c.enabled = false end
    c.profiles = c.profiles or {}
    for _, prof in ipairs(c.profiles) do
        ns.MergeDefaults(prof, PROFILE_DEFAULTS)
    end
end
ns.RegisterCfgInitHook(InitCfg)

-- ── Profile list mutation (called by the config panel) ────────────────────────
function DP.NewProfile()
    local c = Cfg(); if not c then return nil end
    c.profiles = c.profiles or {}
    local p = ns.DeepCopy(PROFILE_DEFAULTS)
    c.profiles[#c.profiles + 1] = p
    DP.Apply()
    return p
end

function DP.RemoveProfile(p)
    local c = Cfg(); if not c or not c.profiles then return end
    for i, pp in ipairs(c.profiles) do
        if pp == p then table.remove(c.profiles, i); break end
    end
    DP.Apply()
end

-- Details! + its profile API present?
function DP.DetailsReady()
    return Details ~= nil and Details.GetCurrentProfileName and Details.ApplyProfile and true or false
end

-- ── Details! window fade ──────────────────────────────────────────────────────
-- Details! exposes each meter window as an "instance" whose frame is instance.baseframe.
-- We tweak that frame's alpha so the whole window (bars + text) dims together; this is a
-- plain frame-alpha change Details! does not overwrite on its refresh tick. Guarded so a
-- missing / older API never errors. NOTE: verify in-game against your Details! version.
local function EachWindow(fn)
    if not Details then return end
    local n = 0
    if Details.GetNumInstances then n = Details:GetNumInstances() or 0 end
    if (not n or n == 0) and Details.GetNumRunningInstances then n = Details:GetNumRunningInstances() or 0 end
    if not n or n == 0 then n = 4 end   -- probe the first few even if no count API exists
    for i = 1, n do
        local inst = Details.GetInstance and Details:GetInstance(i)
        if inst then fn(inst, inst.baseframe) end
    end
end

function DP.SetDetailsAlpha(a)
    if not Details then return end
    EachWindow(function(inst, frame)
        if frame and frame.SetAlpha then
            frame:SetAlpha(a)
        elseif inst.SetBackgroundAlpha then
            inst:SetBackgroundAlpha(a)
        end
    end)
end

-- ── Context evaluation ────────────────────────────────────────────────────────
local function GroupMet(g)
    if not g or not g.enabled then return false end
    local inGroup = IsInGroup()
    local inRaid  = IsInRaid()
    if g.solo  and not inGroup            then return true end
    if g.group and inGroup and not inRaid then return true end
    if g.raid  and inRaid                 then return true end
    if g.custom then
        local count = inGroup and (GetNumGroupMembers() or 1) or 1
        for _, fdef in ipairs(g.custom) do
            if fdef.enabled ~= false and fdef.min and fdef.max
                and count >= fdef.min and count <= fdef.max then
                return true
            end
        end
    end
    return false
end

local function InstanceMet(ins)
    if not ins or not ins.enabled then return false end
    local _, t = IsInInstance()
    if ins.outdoor      and t == "none"  then return true end
    if ins.dungeon      and t == "party" then return true end
    if ins.raid         and t == "raid"  then return true end
    if ins.battleground and t == "pvp"   then return true end
    return false
end

-- A gate (NOT a trigger): when enabled, the profile may only apply in the chosen combat
-- state; disabled = no restriction. Returns whether the profile is allowed right now.
local function CombatGateOk(cb)
    if not cb or not cb.enabled then return true end
    if cb.state == "out" then return not InCombatLockdown() end
    return InCombatLockdown()   -- "in" (default)
end

local fadedByUs = false   -- we are currently holding Details! at the faded alpha

-- Evaluate every profile against the current context and apply the winning actions.
-- Re-armed on config change, the relevant events, and the reload hook.
function DP.Apply()
    local c = Cfg()
    if not c or not c.enabled then
        -- Module off: undo any fade we are still holding.
        if fadedByUs and DP.DetailsReady() then DP.SetDetailsAlpha(1); fadedByUs = false end
        return
    end
    if not DP.DetailsReady() then return end

    local wantFade, fadeAlpha, wantProfile = false, 1, nil
    for _, p in ipairs(c.profiles or {}) do
        -- Group/instance decide WHAT matches; the combat gate (if on) restricts WHEN.
        if (GroupMet(p.group) or InstanceMet(p.instance)) and CombatGateOk(p.combat) then
            if p.fadeDetails then
                wantFade  = true
                fadeAlpha = PctToAlpha(p.fadeOpacity)   -- later matching profiles win
            end
            if p.changeProfile and p.profileName and p.profileName ~= "" then
                wantProfile = p.profileName             -- later matching profiles win
            end
        end
    end

    -- Profile switch: only when it differs, and never mid-combat (it would reset the meter
    -- windows). In combat we just skip it; PLAYER_REGEN_ENABLED re-runs Apply afterwards.
    if wantProfile and not InCombatLockdown()
        and Details:GetCurrentProfileName() ~= wantProfile then
        Details:ApplyProfile(wantProfile)
    end

    -- Fade: dim to the matching profile's opacity, else restore full opacity once we
    -- leave the fade context (only if we were the one holding it faded).
    if wantFade then
        DP.SetDetailsAlpha(fadeAlpha); fadedByUs = true
    elseif fadedByUs then
        DP.SetDetailsAlpha(1);         fadedByUs = false
    end
end

-- Combat enter/leave are registered so the "only in combat state" gate (and any
-- combat-gated fade) re-evaluate; the rest cover zone/instance/roster transitions.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function() DP.Apply() end)

ns.RegisterReloadHook(function() DP.Apply() end)
