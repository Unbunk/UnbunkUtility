-- Modules/TrinketTracker/Core/TrinketTracker.lua

local _, ns = ...

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(TrinketTrackerCfg_Get("instanceFilter"))
end

local function CreateTrinketTracker(prefix, frameName)
    local function GetCfg(key)
        local cfg = TrinketTrackerCfg_Get(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = TrinketTrackerCfg_Get(prefix)
        if cfg then
            cfg[key] = val
            TrinketTrackerCfg_Set(prefix, cfg)
        end
    end

    local tracker = Unbunk_CreateItemTracker({
        frameName = frameName,
        getCfg    = function(key)
            if key == "enabled" then
                return TrinketTrackerCfg_Get("enabled") and GetCfg("enabled") and IsActiveInCurrentInstance()
            end
            return GetCfg(key)
        end,
        getItemId = function()
            local slot = GetCfg("slot")
            return slot and GetInventoryItemID("player", slot)
        end,
        hasItem = function(itemId)
            return itemId ~= nil
        end,
        onDragStop = function(x, y)
            SetCfg("posX", x)
            SetCfg("posY", y)
            if tracker.pe then tracker.pe.Refresh() end
        end,
        onReady = function()
            if GetCfg("soundOnReady") then
                TrinketTracker_PlaySound(prefix, "soundReady")
            end
        end,
    })

    return tracker
end

local trinket1Tracker
local trinket2Tracker

local initTrackers = CreateFrame("Frame")
initTrackers:RegisterEvent("ADDON_LOADED")
initTrackers:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    trinket1Tracker = CreateTrinketTracker("trinket1", "TrinketTracker1")
    trinket2Tracker = CreateTrinketTracker("trinket2", "TrinketTracker2")
    self:UnregisterEvent("ADDON_LOADED")
end)

local function ApplyLayout()
    if not trinket1Tracker or not trinket2Tracker then return end
    local t1Cfg = TrinketTrackerCfg_Get("trinket1")
    local t2Cfg = TrinketTrackerCfg_Get("trinket2")
    if not t1Cfg or not t2Cfg then return end
    trinket1Tracker.GetFrame():ClearAllPoints()
    trinket1Tracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", t1Cfg.posX, t1Cfg.posY)
    trinket2Tracker.GetFrame():ClearAllPoints()
    trinket2Tracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", t2Cfg.posX, t2Cfg.posY)
end

function TrinketTracker_ApplyAll()
    if not trinket1Tracker or not trinket2Tracker then return end
    ApplyLayout()
    trinket1Tracker.ApplyVisuals()
    trinket2Tracker.ApplyVisuals()
end

function TrinketTracker_GetTracker1() return trinket1Tracker end
function TrinketTracker_GetTracker2() return trinket2Tracker end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit ~= "player" then return end
        -- Détecte l'utilisation d'un trinket par son spell (slot configuré).
        local t1Cfg = TrinketTrackerCfg_Get("trinket1")
        local t2Cfg = TrinketTrackerCfg_Get("trinket2")
        local t1Id = t1Cfg and t1Cfg.slot and GetInventoryItemID("player", t1Cfg.slot)
        local t2Id = t2Cfg and t2Cfg.slot and GetInventoryItemID("player", t2Cfg.slot)
        local t1Spell = t1Id and select(2, C_Item.GetItemSpell(t1Id))
        local t2Spell = t2Id and select(2, C_Item.GetItemSpell(t2Id))
        if t1Spell and spellId == t1Spell then
            if TrinketTrackerCfg_Get("trinket1").soundOnUse then
                TrinketTracker_PlaySound("trinket1", "soundUse")
            end
        elseif t2Spell and spellId == t2Spell then
            if TrinketTrackerCfg_Get("trinket2").soundOnUse then
                TrinketTracker_PlaySound("trinket2", "soundUse")
            end
        end
    end
    TrinketTracker_ApplyAll()
end)

C_Timer.NewTicker(0.5, function()
    -- État stable : si le module est désactivé, les frames sont déjà cachés.
    if not TrinketTrackerCfg_Get("enabled") then return end
    TrinketTracker_ApplyAll()
end)

ns.RegisterReloadHook(function() TrinketTracker_ApplyAll() end)

local initTT = CreateFrame("Frame")
initTT:RegisterEvent("PLAYER_LOGIN")
initTT:SetScript("OnEvent", function(self)
    C_Timer.After(0.5, function()
        TrinketTracker_ApplyAll()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)