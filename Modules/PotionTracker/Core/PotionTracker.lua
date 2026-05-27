-- Modules/PotionTracker/Core/PotionTracker.lua

local _, ns = ...

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(PotionTrackerCfg_Get("instanceFilter"))
end

local function CreatePotionTracker(prefix, frameName)
    local function GetCfg(key)
        local cfg = PotionTrackerCfg_Get(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = PotionTrackerCfg_Get(prefix)
        if cfg then
            cfg[key] = val
            PotionTrackerCfg_Set(prefix, cfg)
        end
    end

    local tracker = Unbunk_CreateItemTracker({
        frameName = frameName,
        getCfg    = function(key)
            if key == "enabled" then
                return PotionTrackerCfg_Get("enabled") and GetCfg("enabled") and IsActiveInCurrentInstance()
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
                PotionTracker_PlaySound(prefix, "soundReady")
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
    local healthCfg = PotionTrackerCfg_Get("health")
    local combatCfg = PotionTrackerCfg_Get("combat")
    if not healthCfg or not combatCfg then return end
    healthTracker.GetFrame():ClearAllPoints()
    healthTracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", healthCfg.posX, healthCfg.posY)
    combatTracker.GetFrame():ClearAllPoints()
    combatTracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", combatCfg.posX, combatCfg.posY)
end

function PotionTracker_ApplyAll()
    if not healthTracker or not combatTracker then return end
    ApplyLayout()
    healthTracker.ApplyVisuals()
    combatTracker.ApplyVisuals()
end

function PotionTracker_GetHealthTracker() return healthTracker end
function PotionTracker_GetCombatTracker() return combatTracker end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit ~= "player" then return end
        local healthSpellId = PotionTrackerCfg_Get("health") and PotionTrackerCfg_Get("health").spellId
        local combatSpellId = PotionTrackerCfg_Get("combat") and PotionTrackerCfg_Get("combat").spellId
        if healthSpellId and spellId == healthSpellId then
            if PotionTrackerCfg_Get("health").soundOnUse then
                PotionTracker_PlaySound("health", "soundUse")
            end
        elseif combatSpellId and spellId == combatSpellId then
            if PotionTrackerCfg_Get("combat").soundOnUse then
                PotionTracker_PlaySound("combat", "soundUse")
            end
        end
    end
    PotionTracker_ApplyAll()
end)

C_Timer.NewTicker(0.5, function()
    -- État stable : si le module est désactivé, les frames sont déjà cachés,
    -- inutile de refaire le travail à chaque tick.
    if not PotionTrackerCfg_Get("enabled") then return end
    PotionTracker_ApplyAll()
end)

ns.RegisterReloadHook(function() PotionTracker_ApplyAll() end)

local initPT = CreateFrame("Frame")
initPT:RegisterEvent("PLAYER_LOGIN")
initPT:SetScript("OnEvent", function(self)
    local healthId = PotionTrackerCfg_Get("health") and PotionTrackerCfg_Get("health").itemId
    local combatId = PotionTrackerCfg_Get("combat") and PotionTrackerCfg_Get("combat").itemId
    if healthId then C_Item.RequestLoadItemDataByID(healthId) end
    if combatId then C_Item.RequestLoadItemDataByID(combatId) end
    C_Timer.After(0.5, function()
        PotionTracker_ApplyAll()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)