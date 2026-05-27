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

-- Évalue un seul membre de groupe : déclenche l'alerte de mort si nécessaire.
-- Appelé avec l'unit fourni par l'événement (pas de boucle sur tout le groupe).
local function CheckUnitDeath(unit)
    if not unit then return end
    -- On ne traite que les membres de groupe (party1-4 / raid1-40).
    if not string.match(unit, "^party%d+$") and not string.match(unit, "^raid%d+$") then return end
    if not UnitExists(unit) then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    if not UnitIsDeadOrGhost(unit) then
        -- En vie : réarme l'alerte pour une future mort.
        alertedGuids[guid] = nil
        return
    end

    if alertedGuids[guid] then return end
    alertedGuids[guid] = true

    local role = UnitGroupRolesAssigned(unit)

    if TANK_ROLES[role] and DA.CfgGet("tankEnabled") and IsDeathAlertActiveInCurrentInstance("tank") then
        if not DA.IsTankTesting() then
            ShowAlert(DA.GetTankFrame(), DA.CfgGet("tankAlertDuration") or 5)
            DA.PlaySound("tank")
        end
    elseif HEALER_ROLES[role] and DA.CfgGet("healerEnabled") and IsDeathAlertActiveInCurrentInstance("healer") then
        if not DA.IsHealerTesting() then
            ShowAlert(DA.GetHealerFrame(), DA.CfgGet("healerAlertDuration") or 5)
            DA.PlaySound("healer")
        end
    elseif DPS_ROLES[role] and DA.CfgGet("dpsEnabled") and IsDeathAlertActiveInCurrentInstance("dps") then
        if not DA.IsDpsTesting() then
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
    if event == "PLAYER_REGEN_ENABLED" or event == "GROUP_ROSTER_UPDATE" then
        alertedGuids = {}
        return
    end

    -- UNIT_HEALTH / UNIT_FLAGS : on n'évalue que l'unité concernée.
    if not IsInGroup() and not IsInRaid() then return end
    CheckUnitDeath(unit)
end)