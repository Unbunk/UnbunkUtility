-- Modules/DeathAlert/Core/DeathCheck.lua

local _, ns = ...
ns.DeathAlert = ns.DeathAlert or {}
local DA = ns.DeathAlert

-- DeathAlert only registers events (no polling ticker), so AceEvent is embedded
-- but AceTimer is not — its one-shot auto-hide uses C_Timer.After directly.
local AceEvent = LibStub("AceEvent-3.0")
AceEvent:Embed(DA)

local TANK_ROLES   = { TANK = true }
local HEALER_ROLES = { HEALER = true }
local DPS_ROLES    = { DAMAGER = true }

local function IsDeathAlertActiveInCurrentInstance(prefix)
    return ns.IsActiveInInstance(DA.CfgGet(prefix .. "InstanceFilter"))
end

-- isUnlocked is the widget's own unlock predicate; we drive the auto-hide off
-- it rather than frame:IsMovable() so a real death that fires while the user
-- has that alert unlocked in the config window is still hidden once the user
-- locks it again (IsMovable() was a fragile proxy for "unlocked").
local function ShowAlert(frame, duration, isUnlocked)
    frame:Show()
    -- Stamp the latest scheduled hide time on the frame. If a second, closer death
    -- of the same role re-shows the frame before this timer fires, that re-arm
    -- stamps a newer hideAt — so this (older) callback bows out and only the most
    -- recently armed timer hides the frame, giving the latest death its full
    -- duration instead of being cut short by the first death's timer.
    local hideAt = GetTime() + duration
    frame._uuHideAt = hideAt
    C_Timer.After(duration, function()
        if frame._uuHideAt ~= hideAt then return end  -- a newer death re-armed the hide
        if not (isUnlocked and isUnlocked()) then
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

local function WipeCfg()    return ns.db and ns.db.global.wipe    end
local function DpsSpamCfg() return ns.db and ns.db.global.dpsSpam end

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
local strbyte = string.byte
local function CheckUnitDeath(unit)
    if not unit then return end
    -- UNIT_HEALTH / UNIT_FLAGS are registered globally, so this fires for every
    -- unit whose health/flags change (group members, their pets, target, focus,
    -- nameplates, ...). Cheap first-byte gate before the regex + UnitExists /
    -- UnitGUID work: only "party..." (p) and "raid..." (r) tokens can match, so
    -- everything else (target/focus/nameplate/boss/arena/...) is rejected for
    -- one byte compare instead of two string.match calls. "pet"/"player" pass
    -- the byte gate but are then rejected by the precise %d+ patterns below.
    local b = strbyte(unit)
    if b ~= 112 and b ~= 114 then return end -- 'p' / 'r'
    -- Handle group member tokens (party1-4 / raid1-40) AND "player": in a 5-man
    -- party the player has no partyN token for themselves, so their own
    -- UNIT_HEALTH/UNIT_FLAGS only arrive under "player" and were being dropped,
    -- meaning the user's own death never alerted nor fed the wipe/dps buffers.
    -- In a raid the player is also raidN; the per-GUID dedup below prevents a
    -- double alert when both tokens are seen.
    if unit ~= "player"
        and not string.match(unit, "^party%d+$")
        and not string.match(unit, "^raid%d+$") then
        return
    end
    if not UnitExists(unit) then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    if not UnitIsDeadOrGhost(unit) then
        -- Alive: rearm the alert for a future death. Re-arming is event-driven:
        -- it happens on the first UNIT_HEALTH/UNIT_FLAGS that observes this unit
        -- alive again (a battle-res brings them back at low health, which fires
        -- UNIT_HEALTH), and PLAYER_REGEN_ENABLED clears everything at combat end.
        -- Known edge case: a unit resurrected and killed again within the same
        -- combat with no intervening alive-observation event for that token will
        -- not re-alert the second death. Accepted as a documented limitation.
        alertedGuids[guid] = nil
        return
    end

    if alertedGuids[guid] then return end
    alertedGuids[guid] = true

    local role = UnitGroupRolesAssigned(unit)
    -- role is "NONE" for any member without an assigned group role (common in
    -- manually-formed / outdoor groups). Inferring a real role would need an
    -- async inspect; instead an opt-in setting routes such deaths to the DPS
    -- bucket so they can alert and feed the dpsSpam threshold. Off by default,
    -- so unassigned-role deaths otherwise only feed the all-role wipe buffer.
    if role == "NONE" and DA.CfgGet("dpsAlertUnassigned") then
        role = "DAMAGER"
    end

    -- Record before suppression check so anti-spam thresholds keep counting
    -- even when an alert is silenced.
    RecordDeath(role)

    local now = GetTime()
    local wipeSuppressed = now < wipeSuppressUntil
    local dpsSuppressed  = now < dpsSpamSuppressUntil

    if TANK_ROLES[role] and DA.CfgGet("tankEnabled") and IsDeathAlertActiveInCurrentInstance("tank") then
        if not wipeSuppressed and not DA.IsTankTesting() then
            ShowAlert(DA.GetTankFrame(), DA.CfgGet("tankAlertDuration"), DA.IsTankUnlocked)
            DA.PlaySound("tank")
        end
    elseif HEALER_ROLES[role] and DA.CfgGet("healerEnabled") and IsDeathAlertActiveInCurrentInstance("healer") then
        if not wipeSuppressed and not DA.IsHealerTesting() then
            ShowAlert(DA.GetHealerFrame(), DA.CfgGet("healerAlertDuration"), DA.IsHealerUnlocked)
            DA.PlaySound("healer")
        end
    elseif DPS_ROLES[role] and DA.CfgGet("dpsEnabled") and IsDeathAlertActiveInCurrentInstance("dps") then
        if not wipeSuppressed and not dpsSuppressed and not DA.IsDpsTesting() then
            ShowAlert(DA.GetDpsFrame(), DA.CfgGet("dpsAlertDuration"), DA.IsDpsUnlocked)
            DA.PlaySound("dps")
        end
    end
end

-- UNIT_HEALTH / UNIT_FLAGS are registered GLOBALLY. RegisterUnitEvent would fire
-- only for the units we care about, but it caps at 8 unit tokens — a 10/20/40
-- player raid blows past that and the call errors — so it isn't usable for an
-- unbounded group. Instead the handler fires for every unit and CheckUnitDeath's
-- cheap first-byte 'p'/'r' gate + ^party%d+$/^raid%d+$ patterns reject the
-- irrelevant churn (nameplates, target, focus, boss, arena, pets) up front.
-- AceEvent has no unit filter (no RegisterUnitEvent equivalent), which suits the
-- unbounded-group need here: register globally and let CheckUnitDeath gate.
-- Cached group state, refreshed from GROUP_ROSTER_UPDATE (which fires on every
-- join/leave/convert), so the high-frequency UNIT_HEALTH/UNIT_FLAGS handler can
-- short-circuit on a boolean instead of two IsInGroup()/IsInRaid() C calls per event.
local inGroup = IsInGroup() or IsInRaid()

local function OnUnitHealthOrFlags(event, unit)
    -- UNIT_HEALTH / UNIT_FLAGS: only evaluate the unit that fired the event.
    -- Reject the dominant nameplate/target churn one step earlier than the group
    -- gate: only "party..." (p) / "raid..." (r) tokens can be group members, so a
    -- single first-byte compare drops everything else before the group check.
    if not unit then return end
    local b = strbyte(unit)
    if b ~= 112 and b ~= 114 then return end -- 'p' / 'r'
    if not inGroup then return end
    CheckUnitDeath(unit)
end
DA:RegisterEvent("UNIT_HEALTH", OnUnitHealthOrFlags)
DA:RegisterEvent("UNIT_FLAGS", OnUnitHealthOrFlags)

DA:RegisterEvent("GROUP_ROSTER_UPDATE", function(event)
    -- Refresh the cached group-membership flag the UNIT_HEALTH/UNIT_FLAGS gate reads.
    inGroup = IsInGroup() or IsInRaid()
    -- Roster changes fire often during combat (disconnects, summons, pets)
    -- and must NOT clear the death buffers, otherwise a real wipe with
    -- simultaneous disconnects could silently bypass the anti-spam
    -- thresholds. Only purge per-GUID alert flags for members who left, so a
    -- future death on that slot can re-alert.
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
end)

DA:RegisterEvent("PLAYER_REGEN_ENABLED", function(event)
    -- Combat ended: clear everything so the next pull starts fresh.
    alertedGuids = {}
    recentDeaths = {}
    wipeSuppressUntil  = 0
    dpsSpamSuppressUntil = 0
end)