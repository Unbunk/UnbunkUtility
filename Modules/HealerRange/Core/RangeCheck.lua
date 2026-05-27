-- Modules/HealerRange/Core/RangeCheck.lua

local _, ns = ...

local CHECK_INTERVAL = 0.1
local timer          = 0
local isOutOfRange   = false
local inCombat       = false
local HEALER_ROLES   = { HEALER = true }
local mainFrame      = CreateFrame("Frame")

local RangeCheck = LibStub("LibRangeCheck-3.0")

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(HealerRangeCfg_Get("instanceFilter"))
end

function HealerRange_HasCombatProbe()
    for _ in RangeCheck:GetFriendCheckers(true) do
        return true
    end
    return false
end

local EVOKER_SPEC_IDS = {
    [1468] = true, -- Preservation (heal)
}

local function IsEvoker(unit)
    local specID = GetInspectSpecialization(unit)
    if specID and specID > 0 then
        return EVOKER_SPEC_IDS[specID] == true
    end
    local _, class = UnitClass(unit)
    return class == "EVOKER"
end

local function IsHealerInRange()
    if not IsInGroup() and not IsInRaid() then return nil end
    if not HealerRange_HasCombatProbe() then return nil end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()

    -- Vérifie s'il y a au moins un healer non-Evoker
    local hasNonEvokerHealer = false
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            if HEALER_ROLES[UnitGroupRolesAssigned(unit)] then
                if not IsEvoker(unit) then
                    hasNonEvokerHealer = true
                    break
                end
            end
        end
    end

    -- Pas de healer non-Evoker → pas de détection
    if not hasNonEvokerHealer then return nil end

    -- Détecte uniquement sur les healers non-Evoker
    for i = 1, count do
        local unit = prefix .. i
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

local function StartChecking()
    timer = 0
    mainFrame:SetScript("OnUpdate", function(self, elapsed)
        if not HealerRangeCfg_Get("enabled") then return end
        if not IsActiveInCurrentInstance() then return end
        if HealerRangeAlert_IsUnlocked() or HealerRangeAlert_IsTesting() then return end

        timer = timer + elapsed
        if timer < CHECK_INTERVAL then return end
        timer = 0

        local alertFrame = HealerRangeAlert_GetFrame()
        local result = IsHealerInRange()

        if result == nil then
            if alertFrame:IsShown() then alertFrame:Hide() end
            isOutOfRange = false
            return
        end

        if result == false and not isOutOfRange then
            isOutOfRange = true
            alertFrame:Show()
            HealerRangePlaySound()
            local duration = HealerRangeCfg_Get("alertDuration") or 5
            C_Timer.After(duration, function()
                if not HealerRangeAlert_IsUnlocked() and not HealerRangeAlert_IsTesting() then
                    alertFrame:Hide()
                    isOutOfRange = false
                end
            end)
        elseif result == true and isOutOfRange then
            isOutOfRange = false
            alertFrame:Hide()
        end
    end)
end

local function StopChecking()
    mainFrame:SetScript("OnUpdate", nil)
    isOutOfRange = false
    if not HealerRangeAlert_IsUnlocked() then
        HealerRangeAlert_GetFrame():Hide()
    end
end

local function RefreshChecking()
    if inCombat and IsInGroup() then
        StartChecking()
    else
        StopChecking()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        RefreshChecking()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        RefreshChecking()
    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshChecking()
    elseif event == "PLAYER_DEAD" then
        StopChecking()
    elseif event == "PLAYER_UNGHOST" then
        RefreshChecking()
    end
end)