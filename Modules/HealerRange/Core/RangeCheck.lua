-- Modules/HealerRange/Core/RangeCheck.lua

local CHECK_INTERVAL = 0.1
local timer          = 0
local isOutOfRange   = false
local inCombat       = false
local HEALER_ROLES   = { HEALER = true }
local mainFrame      = CreateFrame("Frame")

local function IsHealerInRange()
    if not IsInGroup() and not IsInRaid() then return nil end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()

    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            if HEALER_ROLES[UnitGroupRolesAssigned(unit)] then
                local dist = LibHealerRange:GetRange(unit)
                if dist == nil or dist == 0 then
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