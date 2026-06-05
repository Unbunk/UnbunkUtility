-- Modules/TrinketTracker/Core/TrinketTracker.lua

local _, ns = ...
ns.TrinketTracker = ns.TrinketTracker or {}
local TT = ns.TrinketTracker

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(TT)
AceTimer:Embed(TT)

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(TT.CfgGet("instanceFilter"))
end

-- Per-slot cache of the equipped trinket id + its use spellId. The equipped
-- item only changes on PLAYER_EQUIPMENT_CHANGED, so resolve it once instead of
-- calling GetInventoryItemID + C_Item.GetItemSpell on every 0.5s tick AND on
-- every UNIT_SPELLCAST_SUCCEEDED (which fires many times per second in combat).
-- spellId can be nil while item data loads, so it is re-resolved until it
-- resolves (never caching the transient nil).
local slotCache = {}

local function GetSlotInfo(slot)
    if not slot then return nil, nil end
    local c = slotCache[slot]
    if not c then
        c = { itemId = GetInventoryItemID("player", slot) }
        slotCache[slot] = c
    end
    if c.itemId and c.spellId == nil then
        c.spellId = select(2, C_Item.GetItemSpell(c.itemId))
    end
    return c.itemId, c.spellId
end

local function InvalidateSlotCache()
    slotCache = {}
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

    local tracker = ns.ui.CreateItemTracker({
        frameName = frameName,
        getCfg    = function(key)
            if key == "enabled" then
                return TT.CfgGet("enabled") and GetCfg("enabled") and IsActiveInCurrentInstance()
            end
            if key == "spellId" then
                -- Derive the trinket's use spell from the currently equipped
                -- item so the shared ItemTracker can try to detect the buff and
                -- show a green timer while it is active. NOTE: for on-use
                -- trinkets whose applied aura carries a *different* spellId than
                -- the use spell, GetPlayerAuraBySpellID won't match and only the
                -- grey cooldown shows — a best-effort that works for trinkets
                -- whose aura id equals the use spell (like potions).
                local _, spellId = GetSlotInfo(GetCfg("slot"))
                return spellId
            end
            return GetCfg(key)
        end,
        getItemId = function()
            local itemId = GetSlotInfo(GetCfg("slot"))
            return itemId
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

-- PLAYER_ENTERING_WORLD / PLAYER_EQUIPMENT_CHANGED: a new trinket may be
-- equipped, so drop the per-slot id/spell cache and relayout/refresh visuals.
local function OnEquipmentRefresh(event)
    -- A new trinket may be equipped: drop the per-slot id/spell cache.
    InvalidateSlotCache()
    TT.ApplyAll()
end
TT:RegisterEvent("PLAYER_ENTERING_WORLD", OnEquipmentRefresh)
TT:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", OnEquipmentRefresh)

-- UNIT_SPELLCAST_SUCCEEDED fires many times/sec in combat. AceEvent has no unit
-- filter (no RegisterUnitEvent equivalent), so register unfiltered and discard
-- every fire whose unit token isn't "player".
TT:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(event, unit, _, spellId)
    if unit ~= "player" then return end
    -- Detect a trinket use via its spell (configured slot), reading the
    -- cached id/spell so this hot path doesn't re-query the item API.
    local t1Cfg = TT.CfgGet("trinket1")
    local t2Cfg = TT.CfgGet("trinket2")
    local _, t1Spell = GetSlotInfo(t1Cfg and t1Cfg.slot)
    local _, t2Spell = GetSlotInfo(t2Cfg and t2Cfg.slot)
    -- Note: if both slots hold the SAME (non-unique) on-use trinket then
    -- t1Spell == t2Spell and only trinket1's sound fires (the elseif can't
    -- match). Accepted limitation; most on-use trinkets are Unique-Equipped.
    if t1Spell and spellId == t1Spell then
        -- Start the icon's in-combat heuristic green timer now (independent of
        -- the sound toggle); the live buff aura is unreadable in combat.
        if trinket1Tracker then trinket1Tracker.NotifyUsed() end
        if TT.CfgGet("trinket1").soundOnUse then
            ns.combo.Notify("trinket", function() TT.PlaySound("trinket1", "soundUse") end)
        end
    elseif t2Spell and spellId == t2Spell then
        if trinket2Tracker then trinket2Tracker.NotifyUsed() end
        if TT.CfgGet("trinket2").soundOnUse then
            ns.combo.Notify("trinket", function() TT.PlaySound("trinket2", "soundUse") end)
        end
    end
    -- The 0.5s ticker keeps visuals in sync; no need to relayout on every
    -- player cast (UNIT_SPELLCAST_SUCCEEDED fires many times/sec in combat).
end)

TT:ScheduleRepeatingTimer(function()
    -- Steady state: when the module is disabled the frames are already hidden.
    if not TT.CfgGet("enabled") then return end
    TT.ApplyAll()
end, 0.5)

ns.RegisterReloadHook(function() TT.ApplyAll() end)

local initTT = CreateFrame("Frame")
initTT:RegisterEvent("PLAYER_LOGIN")
initTT:SetScript("OnEvent", function(self)
    C_Timer.After(0.5, function()
        TT.ApplyAll()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)