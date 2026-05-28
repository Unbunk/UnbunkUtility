-- Modules/DeathAlert/Core/DeathCheck.lua

local _, ns = ...
ns.DeathAlert = ns.DeathAlert or {}
local DA = ns.DeathAlert

local TANK_ROLES   = { TANK = true }
local HEALER_ROLES = { HEALER = true }
local DPS_ROLES    = { DAMAGER = true }

local function IsDeathAlertActiveInCurrentInstance(prefix)
    return ns.IsActiveInInstance(DA.CfgGet(prefix .. "InstanceFilter"))
end

local function ShowAlert(frame, duration)
    frame:Show()
    C_Timer.After(duration, function()
        if not frame:IsMovable() then
            frame:Hide()
        end
    end)
end

local alertedGuids = {}

-- Recent deaths buffer for wipe / dps-spam anti-flood detection.
-- Each entry: { time = GetTime(), role = "DAMAGER"/... }
local recentDeaths       = {}
local wipeSuppressUntil  = 0
local dpsSpamSuppressUntil = 0

local function WipeCfg()    return UnbunkUtilityDB and UnbunkUtilityDB.wipe    end
local function DpsSpamCfg() return UnbunkUtilityDB and UnbunkUtilityDB.dpsSpam end

local function PruneDeaths(now)
    local w = WipeCfg() and WipeCfg().timeWindow or 3
    local d = DpsSpamCfg() and DpsSpamCfg().timeWindow or 3
    local maxWindow = math.max(w, d)
    for i = #recentDeaths, 1, -1 do
        if now - recentDeaths[i].time > maxWindow then
            table.remove(recentDeaths, i)
        end
    end
end

local function RecordDeath(role)
    local now = GetTime()
    table.insert(recentDeaths, { time = now, role = role })
    PruneDeaths(now)

    -- Wipe detection: any-role deaths in the window.
    local w = WipeCfg()
    if w and w.enabled then
        local count = 0
        for _, d in ipairs(recentDeaths) do
            if now - d.time <= (w.timeWindow or 3) then count = count + 1 end
        end
        if count >= (w.deathThreshold or 8) then
            wipeSuppressUntil = now + (w.suppressDuration or 15)
        end
    end

    -- DPS spam detection: DPS-only deaths in the window.
    local s = DpsSpamCfg()
    if s and s.enabled and DPS_ROLES[role] then
        local count = 0
        for _, d in ipairs(recentDeaths) do
            if now - d.time <= (s.timeWindow or 3) and DPS_ROLES[d.role] then
                count = count + 1
            end
        end
        if count >= (s.deathThreshold or 3) then
            dpsSpamSuppressUntil = now + (s.suppressDuration or 6)
        end
    end
end

-- Evaluate a single group member: trigger the death alert if needed. Called
-- with the unit token provided by the event (no loop over the whole group).
local function CheckUnitDeath(unit)
    if not unit then return end
    -- Only handle group member unit tokens (party1-4 / raid1-40).
    if not string.match(unit, "^party%d+$") and not string.match(unit, "^raid%d+$") then return end
    if not UnitExists(unit) then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    if not UnitIsDeadOrGhost(unit) then
        -- Alive: rearm the alert for a future death.
        alertedGuids[guid] = nil
        return
    end

    if alertedGuids[guid] then return end
    alertedGuids[guid] = true

    local role = UnitGroupRolesAssigned(unit)

    -- Record before suppression check so anti-spam thresholds keep counting
    -- even when an alert is silenced.
    RecordDeath(role)

    local now = GetTime()
    local wipeSuppressed = now < wipeSuppressUntil
    local dpsSuppressed  = now < dpsSpamSuppressUntil

    if TANK_ROLES[role] and DA.CfgGet("tankEnabled") and IsDeathAlertActiveInCurrentInstance("tank") then
        if not wipeSuppressed and not DA.IsTankTesting() then
            ShowAlert(DA.GetTankFrame(), DA.CfgGet("tankAlertDuration") or 5)
            DA.PlaySound("tank")
        end
    elseif HEALER_ROLES[role] and DA.CfgGet("healerEnabled") and IsDeathAlertActiveInCurrentInstance("healer") then
        if not wipeSuppressed and not DA.IsHealerTesting() then
            ShowAlert(DA.GetHealerFrame(), DA.CfgGet("healerAlertDuration") or 5)
            DA.PlaySound("healer")
        end
    elseif DPS_ROLES[role] and DA.CfgGet("dpsEnabled") and IsDeathAlertActiveInCurrentInstance("dps") then
        if not wipeSuppressed and not dpsSuppressed and not DA.IsDpsTesting() then
            ShowAlert(DA.GetDpsFrame(), DA.CfgGet("dpsAlertDuration") or 5)
            DA.PlaySound("dps")
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: clear everything so the next pull starts fresh.
        alertedGuids = {}
        recentDeaths = {}
        wipeSuppressUntil  = 0
        dpsSpamSuppressUntil = 0
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        -- Roster changes fire often during combat (disconnects, summons,
        -- pets) and must NOT clear the death buffers, otherwise a real
        -- wipe with simultaneous disconnects could silently bypass the
        -- anti-spam thresholds. We only purge per-GUID alert flags for
        -- members who left, so a future death on that slot can re-alert.
        local present = {}
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local g = UnitGUID("raid" .. i)
                if g then present[g] = true end
            end
        elseif IsInGroup() then
            local g = UnitGUID("player")
            if g then present[g] = true end
            for i = 1, GetNumSubgroupMembers() do
                g = UnitGUID("party" .. i)
                if g then present[g] = true end
            end
        end
        for guid in pairs(alertedGuids) do
            if not present[guid] then alertedGuids[guid] = nil end
        end
        return
    end

    -- UNIT_HEALTH / UNIT_FLAGS: only evaluate the unit that fired the event.
    if not IsInGroup() and not IsInRaid() then return end
    CheckUnitDeath(unit)
end)