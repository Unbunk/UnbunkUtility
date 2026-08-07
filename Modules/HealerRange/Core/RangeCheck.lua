-- Modules/HealerRange/Core/RangeCheck.lua

local _, ns = ...
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(HR)
AceTimer:Embed(HR)

local CHECK_INTERVAL = 0.1
local timer          = 0
local isOutOfRange   = false
local inCombat       = false
local HEALER_ROLES   = { HEALER = true }
local mainFrame      = CreateFrame("Frame")

local RangeCheck = LibStub("LibRangeCheck-3.0")

-- Precomputed unit tokens (raid1..40 / party1..4) so the range tick indexes a
-- table by i instead of building "raid"..i / "party"..i strings every iteration.
local RAID_UNITS  = {}
local PARTY_UNITS = {}
for i = 1, 40 do RAID_UNITS[i]  = "raid"  .. i end
for i = 1, 4  do PARTY_UNITS[i] = "party" .. i end

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(HR.CfgGet("instanceFilter"))
end

-- Whether the player's class has any friendly spell probe usable in combat.
-- This only changes on spec/talent changes, not 10x/sec, so it is cached and
-- refreshed on the relevant events (see RefreshCombatProbe below) instead of
-- being recomputed inside the 0.1s range tick.
local hasCombatProbe = false

local function RefreshCombatProbe()
    for _ in RangeCheck:GetFriendCheckers(true) do
        hasCombatProbe = true
        return
    end
    hasCombatProbe = false
end

-- LibRangeCheck builds its checker lists lazily (~0.5s after load) and rebuilds
-- them on spec/talent changes. Refresh the cached probe flag whenever the lib
-- reports them changed, so it never latches a stale `false` from a login-time
-- read (e.g. the config window's probe-status label) before the lib is ready.
if RangeCheck.RegisterCallback then
    RangeCheck.RegisterCallback(HR, RangeCheck.CHECKERS_CHANGED, function()
        RefreshCombatProbe()
    end)
end

function HR.HasCombatProbe()
    return hasCombatProbe
end

-- IsEvoker is only ever called on units that already passed the HEALER role
-- gate (see IsHealerInRange), so a plain class check is the correct and reliable
-- discriminator: among healers, the Evoker is by definition Preservation. We
-- deliberately do NOT use GetInspectSpecialization here — it needs an async
-- NotifyInspect/INSPECT_READY round-trip and returns 0 for un-inspected group
-- members, so it was dead weight (DPS Evokers never reach here; they fail the
-- HEALER role gate).
local function IsEvoker(unit)
    local _, class = UnitClass(unit)
    return class == "EVOKER"
end

local function IsHealerInRange()
    if not IsInGroup() and not IsInRaid() then return nil end
    if not HR.HasCombatProbe() then return nil end

    local inRaid = IsInRaid()
    local units  = inRaid and RAID_UNITS or PARTY_UNITS
    local count  = inRaid and GetNumGroupMembers() or GetNumSubgroupMembers()

    -- Check whether there is at least one non-Evoker healer.
    local hasNonEvokerHealer = false
    for i = 1, count do
        local unit = units[i]
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            if HEALER_ROLES[UnitGroupRolesAssigned(unit)] then
                if not IsEvoker(unit) then
                    hasNonEvokerHealer = true
                    break
                end
            end
        end
    end

    -- No non-Evoker healer present → skip detection entirely.
    if not hasNonEvokerHealer then return nil end

    -- Only run range checks against the non-Evoker healers.
    for i = 1, count do
        local unit = units[i]
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            if HEALER_ROLES[UnitGroupRolesAssigned(unit)] and not IsEvoker(unit) then
                local minRange, maxRange = RangeCheck:GetRange(unit, false, true)
                if maxRange and maxRange <= 40 then
                    return true
                end
            end
        end
    end

    return false
end

-- Hide a currently-shown alert and reset the out-of-range latch. Used before
-- the OnUpdate early-return guards so the "No Heal" alert never stays frozen on
-- screen after the player leaves the filtered instance, disables the module, or
-- unlocks/tests the frame mid-alert. Respects IsUnlocked/IsTesting so the unlock
-- outline and the Test Alert frame (both deliberately-shown frames) are not
-- hidden out from under the user.
local function ForceClearAlert()
    if not HR.IsUnlocked() and not HR.IsTesting() then
        local frame = HR.GetFrame()
        if frame:IsShown() then frame:Hide() end
    end
    isOutOfRange = false
end

-- The 10Hz range poll. Hoisted to a single module-level function (captures only
-- file-level upvalues) so StartChecking installs the SAME reference every time
-- instead of allocating a fresh closure on each combat/roster refresh.
local function RangeOnUpdate(self, elapsed)
    -- Throttle FIRST so the per-tick guards below (CfgGet + IsActiveInCurrentInstance's
    -- IsInInstance C call + IsUnlocked/IsTesting) run at ~10Hz, not full framerate.
    timer = timer + elapsed
    if timer < CHECK_INTERVAL then return end
    timer = 0

    -- Clear any stuck alert BEFORE the early-return guards below, otherwise a
    -- shown alert would freeze on screen when one of these conditions trips.
    if not HR.CfgGet("enabled")
        or not IsActiveInCurrentInstance()
        or HR.IsUnlocked() or HR.IsTesting() then
        ForceClearAlert()
        return
    end

    local alertFrame = HR.GetFrame()
    local result = IsHealerInRange()

    if result == nil then
        if alertFrame:IsShown() then alertFrame:Hide() end
        isOutOfRange = false
        return
    end

    if result == false and not isOutOfRange then
        isOutOfRange = true
        alertFrame:Show()
        HR.PlaySound()
    elseif result == true and isOutOfRange then
        isOutOfRange = false
        alertFrame:Hide()
    end
end

local function StartChecking()
    timer = 0
    mainFrame:SetScript("OnUpdate", RangeOnUpdate)
end

local function StopChecking()
    mainFrame:SetScript("OnUpdate", nil)
    isOutOfRange = false
    -- Respect IsTesting too (symmetry with ForceClearAlert): otherwise leaving
    -- combat / dying while a Test Alert is on screen would hide the test frame
    -- out from under the user before its timer ends.
    if not HR.IsUnlocked() and not HR.IsTesting() then
        HR.GetFrame():Hide()
    end
end

local function RefreshChecking()
    -- Module disabled => fully stop: no OnUpdate, no range work. The driving events stay registered
    -- (their handlers all funnel through here and become cheap no-ops), and the enable toggle's set
    -- handler calls HR.RefreshChecking so re-enabling restarts the loop live without a /reload.
    if HR.CfgGet("enabled") == false then
        StopChecking()
        return
    end
    RefreshCombatProbe()
    if inCombat and IsInGroup() then
        StartChecking()
    else
        StopChecking()
    end
end

-- Exposed so the enable checkbox in the config UI can drive the start/stop transition live.
function HR.RefreshChecking()
    RefreshChecking()
end

HR:RegisterEvent("PLAYER_REGEN_DISABLED", function(event)
    inCombat = true
    RefreshChecking()
end)
HR:RegisterEvent("PLAYER_REGEN_ENABLED", function(event)
    inCombat = false
    RefreshChecking()
end)
HR:RegisterEvent("GROUP_ROSTER_UPDATE", function(event)
    RefreshChecking()
end)
HR:RegisterEvent("PLAYER_DEAD", function(event)
    StopChecking()
end)
-- PLAYER_ALIVE fires on an in-place resurrect (battle-res / Reincarnation), where
-- PLAYER_UNGHOST never fires because the player never became a ghost; route it to
-- RefreshChecking so range alerts resume after a combat res.
local function OnPlayerAlive(event)
    RefreshChecking()
end
HR:RegisterEvent("PLAYER_UNGHOST", OnPlayerAlive)
HR:RegisterEvent("PLAYER_ALIVE", OnPlayerAlive)
-- The combat-probe availability only changes on spec/talent changes; refresh the
-- cached boolean on those (and login) rather than per range tick.
local function OnProbeRefresh(event)
    RefreshCombatProbe()
end
HR:RegisterEvent("PLAYER_LOGIN", OnProbeRefresh)
HR:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", OnProbeRefresh)
HR:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", OnProbeRefresh)