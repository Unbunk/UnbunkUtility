-- Modules/HealthstoneTracker/Core/HealthstoneTracker.lua

local _, ns = ...
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(HT.CfgGet("instanceFilter"))
end

local tracker

local initTracker = CreateFrame("Frame")
initTracker:RegisterEvent("ADDON_LOADED")
initTracker:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    tracker = Unbunk_CreateItemTracker({
        frameName = "HealthstoneTrackerFrame",
        getCfg    = function(key)
            if key == "enabled" then
                return HT.CfgGet("enabled") and IsActiveInCurrentInstance()
            end
            return HT.CfgGet(key)
        end,
        getItemId = function() return HT.CfgGet("itemId") end,
        hasItem   = function(itemId)
            return itemId ~= nil and (GetItemCount(itemId) or 0) > 0
        end,
        onDragStop = function(x, y)
            HT.CfgSet("posX", x)
            HT.CfgSet("posY", y)
            if HT.pe then HT.pe.Refresh() end
        end,
        onReady = function()
            if HT.CfgGet("soundOnReady") then
                HT.PlaySound("soundReady")
            end
        end,
    })
    self:UnregisterEvent("ADDON_LOADED")
end)

local function ApplyLayout()
    if not tracker then return end
    local x = HT.CfgGet("posX") or 0
    local y = HT.CfgGet("posY") or 0
    tracker.GetFrame():ClearAllPoints()
    tracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function HT.ApplyAll()
    if not tracker then return end
    ApplyLayout()
    tracker.ApplyVisuals()
end

function HT.GetTracker() return tracker end

-- Unlock with a "ready" preview (icon + green check, no cooldown) so the
-- user can position the frame even when no healthstone is in the bag.
function HT.SetUnlocked(val)
    if not tracker then return end
    if val then
        local id = HT.CfgGet("itemId")
        if id and tracker.icon then
            local _, _, _, _, iconID = C_Item.GetItemInfoInstant(id)
            if iconID then tracker.icon.SetIcon(iconID) end
            tracker.icon.ApplySize()
            tracker.icon.ClearTimer()
            tracker.icon.ShowCheck()
        end
        tracker.SetUnlocked(true)
        tracker.GetFrame():Show()
    else
        tracker.SetUnlocked(false)
        HT.ApplyAll()
    end
end

function HT.IsUnlocked()
    return tracker and tracker.IsUnlocked() or false
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit ~= "player" then return end
        local healthstoneSpellId = HT.CfgGet("spellId")
        if healthstoneSpellId and spellId == healthstoneSpellId
            and HT.CfgGet("soundOnUse") then
            HT.PlaySound("soundUse")
        end
    end
    HT.ApplyAll()
end)

C_Timer.NewTicker(0.5, function()
    -- Steady state: skip work when disabled.
    if not HT.CfgGet("enabled") then return end
    HT.ApplyAll()
end)

ns.RegisterReloadHook(function() HT.ApplyAll() end)

local initHT = CreateFrame("Frame")
initHT:RegisterEvent("PLAYER_LOGIN")
initHT:SetScript("OnEvent", function(self)
    local id = HT.CfgGet("itemId")
    if id then C_Item.RequestLoadItemDataByID(id) end
    C_Timer.After(0.5, function() HT.ApplyAll() end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
