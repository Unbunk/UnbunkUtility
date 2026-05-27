-- Modules/TrinketTracker/Core/TrinketTracker.lua

local _, ns = ...
ns.TrinketTracker = ns.TrinketTracker or {}
local TT = ns.TrinketTracker

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(TT.CfgGet("instanceFilter"))
end

local function CreateTrinketTracker(prefix, frameName)
    local function GetCfg(key)
        local cfg = TT.CfgGet(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = TT.CfgGet(prefix)
        if cfg then
            cfg[key] = val
            TT.CfgSet(prefix, cfg)
        end
    end

    local tracker = Unbunk_CreateItemTracker({
        frameName = frameName,
        getCfg    = function(key)
            if key == "enabled" then
                return TT.CfgGet("enabled") and GetCfg("enabled") and IsActiveInCurrentInstance()
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
                TT.PlaySound(prefix, "soundReady")
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
    local t1Cfg = TT.CfgGet("trinket1")
    local t2Cfg = TT.CfgGet("trinket2")
    if not t1Cfg or not t2Cfg then return end
    trinket1Tracker.GetFrame():ClearAllPoints()
    trinket1Tracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", t1Cfg.posX, t1Cfg.posY)
    trinket2Tracker.GetFrame():ClearAllPoints()
    trinket2Tracker.GetFrame():SetPoint("CENTER", UIParent, "CENTER", t2Cfg.posX, t2Cfg.posY)
end

function TT.ApplyAll()
    if not trinket1Tracker or not trinket2Tracker then return end
    ApplyLayout()
    trinket1Tracker.ApplyVisuals()
    trinket2Tracker.ApplyVisuals()
end

function TT.GetTracker1() return trinket1Tracker end
function TT.GetTracker2() return trinket2Tracker end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit ~= "player" then return end
        -- Détecte l'utilisation d'un trinket par son spell (slot configuré).
        local t1Cfg = TT.CfgGet("trinket1")
        local t2Cfg = TT.CfgGet("trinket2")
        local t1Id = t1Cfg and t1Cfg.slot and GetInventoryItemID("player", t1Cfg.slot)
        local t2Id = t2Cfg and t2Cfg.slot and GetInventoryItemID("player", t2Cfg.slot)
        local t1Spell = t1Id and select(2, C_Item.GetItemSpell(t1Id))
        local t2Spell = t2Id and select(2, C_Item.GetItemSpell(t2Id))
        if t1Spell and spellId == t1Spell then
            if TT.CfgGet("trinket1").soundOnUse then
                TT.PlaySound("trinket1", "soundUse")
            end
        elseif t2Spell and spellId == t2Spell then
            if TT.CfgGet("trinket2").soundOnUse then
                TT.PlaySound("trinket2", "soundUse")
            end
        end
    end
    TT.ApplyAll()
end)

C_Timer.NewTicker(0.5, function()
    -- État stable : si le module est désactivé, les frames sont déjà cachés.
    if not TT.CfgGet("enabled") then return end
    TT.ApplyAll()
end)

ns.RegisterReloadHook(function() TT.ApplyAll() end)

local initTT = CreateFrame("Frame")
initTT:RegisterEvent("PLAYER_LOGIN")
initTT:SetScript("OnEvent", function(self)
    C_Timer.After(0.5, function()
        TT.ApplyAll()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)