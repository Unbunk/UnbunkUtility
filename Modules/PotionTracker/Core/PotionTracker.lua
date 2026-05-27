-- Modules/PotionTracker/Core/PotionTracker.lua

local _, ns = ...
ns.PotionTracker = ns.PotionTracker or {}
local PT = ns.PotionTracker

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(PT.CfgGet("instanceFilter"))
end

local function CreatePotionTracker(prefix, frameName)
    local function GetCfg(key)
        local cfg = PT.CfgGet(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = PT.CfgGet(prefix)
        if cfg then
            cfg[key] = val
            PT.CfgSet(prefix, cfg)
        end
    end

    local tracker = Unbunk_CreateItemTracker({
        frameName = frameName,
        getCfg    = function(key)
            if key == "enabled" then
                return PT.CfgGet("enabled") and GetCfg("enabled") and IsActiveInCurrentInstance()
            end
            return GetCfg(key)
        end,
        getItemId = function() return GetCfg("itemId") end,
        hasItem   = function(itemId) return (GetItemCount(itemId) or 0) > 0 end,
        onDragStop = function(x, y)
            SetCfg("posX", x)
            SetCfg("posY", y)
            if tracker.pe then tracker.pe.Refresh() end
        end,
        onReady = function()
            if GetCfg("soundOnReady") then
                PT.PlaySound(prefix, "soundReady")
            end
        end,
    })

    return tracker
end

local healthTracker
local combatTracker

local initTrackers = CreateFrame("Frame")
initTrackers:RegisterEvent("ADDON_LOADED")
initTrackers:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    healthTracker = CreatePotionTracker("health", "PotionTrackerHealth")
    combatTracker = CreatePotionTracker("combat", "PotionTrackerCombat")
    self:UnregisterEvent("ADDON_LOADED")
end)

local function ApplyLayout()
    if not healthTracker or not combatTracker then return end
    local healthCfg = PT.CfgGet("health")
    local combatCfg = PT.CfgGet("combat")
    if not healthCfg or not combatCfg then return end
    healthTracker.GetFrame():ClearAllPoints()
    healthTracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", healthCfg.posX, healthCfg.posY)
    combatTracker.GetFrame():ClearAllPoints()
    combatTracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", combatCfg.posX, combatCfg.posY)
end

function PT.ApplyAll()
    if not healthTracker or not combatTracker then return end
    ApplyLayout()
    healthTracker.ApplyVisuals()
    combatTracker.ApplyVisuals()
end

function PT.GetHealthTracker() return healthTracker end
function PT.GetCombatTracker() return combatTracker end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit ~= "player" then return end
        local healthSpellId = PT.CfgGet("health") and PT.CfgGet("health").spellId
        local combatSpellId = PT.CfgGet("combat") and PT.CfgGet("combat").spellId
        if healthSpellId and spellId == healthSpellId then
            if PT.CfgGet("health").soundOnUse then
                PT.PlaySound("health", "soundUse")
            end
        elseif combatSpellId and spellId == combatSpellId then
            if PT.CfgGet("combat").soundOnUse then
                PT.PlaySound("combat", "soundUse")
            end
        end
    end
    PT.ApplyAll()
end)

C_Timer.NewTicker(0.5, function()
    -- État stable : si le module est désactivé, les frames sont déjà cachés,
    -- inutile de refaire le travail à chaque tick.
    if not PT.CfgGet("enabled") then return end
    PT.ApplyAll()
end)

ns.RegisterReloadHook(function() PT.ApplyAll() end)

local initPT = CreateFrame("Frame")
initPT:RegisterEvent("PLAYER_LOGIN")
initPT:SetScript("OnEvent", function(self)
    local healthId = PT.CfgGet("health") and PT.CfgGet("health").itemId
    local combatId = PT.CfgGet("combat") and PT.CfgGet("combat").itemId
    if healthId then C_Item.RequestLoadItemDataByID(healthId) end
    if combatId then C_Item.RequestLoadItemDataByID(combatId) end
    C_Timer.After(0.5, function()
        PT.ApplyAll()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)