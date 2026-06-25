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
        c = {}
        slotCache[slot] = c
    end
    -- Re-resolve the equipped item id until it is KNOWN. A cold-login call can run before the equipment is
    -- populated, so GetInventoryItemID returns nil; the old one-shot `{ itemId = GetInventoryItemID(...) }`
    -- CACHED that nil and never re-queried it (only spellId was re-resolved), stranding the trinket with "no
    -- item" for the whole session — no on-use spell → never cdmEligible → missing from the CDM + list until a
    -- /reload. Once the id resolves it sticks (no more GetInventoryItemID calls on the steady-state tick).
    if c.itemId == nil then c.itemId = GetInventoryItemID("player", slot) end
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

    -- Forward-declared so the onDragStop closure below captures `tracker` as an
    -- upvalue. With `local tracker = ns.ui.CreateItemTracker({...})` the name is
    -- not yet in scope inside the table, so `tracker.pe` would resolve to the nil
    -- global and error on drag-stop (matches PotionTracker's idiom).
    local tracker
    tracker = ns.ui.CreateItemTracker({
        frameName = frameName,
        -- A lone charge/count of 1 is not real "charges" for a trinket (a single on-use), so only draw the
        -- stack number when it is 2+. Hides the spurious "1" the user saw on a one-charge trinket.
        minStack  = 2,
        -- A trinket is EQUIPPED, so its bag item-count must NOT be read as usable charges — otherwise an
        -- on-cooldown trinket stays lit (un-greyed) because a stray bag copy reads as a "charge available".
        equipped  = true,
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
        setCfg = SetCfg,   -- cdmAtEnd flip on a cross-strip drag (Front <-> End bucket)
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
    -- Delegate to each sub-icon's anchor-aware ApplyPosition (when includeInCdm is
    -- set, ns.CDMAnchor owns position+size; otherwise positioned freely on screen).
    -- Runs on the 0.5s ticker too, so the chosen anchor is kept, not clobbered.
    trinket1Tracker.ApplyPosition()
    trinket2Tracker.ApplyPosition()
end

function TT.ApplyAll()
    if not trinket1Tracker or not trinket2Tracker then return end
    ApplyLayout()
    trinket1Tracker.ApplyVisuals()
    trinket2Tracker.ApplyVisuals()
end

-- Passthrough to refresh the configurable icon border on both sub-icons
-- (calqué sur ApplySize via ApplyVisuals); each tracker reads its own
-- sub-config (border* keys) through its prefixed getCfg closure.
function TT.ApplyBorder()
    if trinket1Tracker then trinket1Tracker.ApplyBorder() end
    if trinket2Tracker then trinket2Tracker.ApplyBorder() end
end

function TT.GetTracker1() return trinket1Tracker end
function TT.GetTracker2() return trinket2Tracker end

-- PLAYER_ENTERING_WORLD / PLAYER_EQUIPMENT_CHANGED: a new trinket may be
-- equipped, so drop the per-slot id/spell cache and relayout/refresh visuals.
local function OnEquipmentRefresh(event)
    -- Disabled module: nothing to relayout (frames already hidden). Cheap early-out
    -- so a gear swap costs ~zero while the tracker is off.
    if not TT.CfgGet("enabled") then return end
    -- A new trinket may be equipped: drop the per-slot id/spell cache.
    InvalidateSlotCache()
    TT.ApplyAll()
    -- If the config panel is open, refresh it so each slot's header (trinket icon +
    -- usable/passive status) reflects the newly equipped trinket right away.
    if TT.configMenu and TT.configMenu.content and TT.configMenu.content:IsVisible()
        and TT.configMenu.Refresh then
        TT.configMenu.Refresh()
    end
end
TT:RegisterEvent("PLAYER_ENTERING_WORLD", OnEquipmentRefresh)
TT:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", OnEquipmentRefresh)

-- UNIT_SPELLCAST_SUCCEEDED fires many times/sec in combat. AceEvent has no unit
-- filter (no RegisterUnitEvent equivalent), so register unfiltered and discard
-- every fire whose unit token isn't "player".
TT:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(event, unit, _, spellId)
    if unit ~= "player" then return end
    -- Disabled module: skip the hot path entirely (this fires many times/sec in
    -- combat). First line after the unit filter so the work below never runs while off.
    if not TT.CfgGet("enabled") then return end
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
        if t1Cfg and t1Cfg.soundOnUse then
            ns.combo.Notify("trinket", function() TT.PlaySound("trinket1", "soundUse") end)
        end
    elseif t2Spell and spellId == t2Spell then
        if trinket2Tracker then trinket2Tracker.NotifyUsed() end
        if t2Cfg and t2Cfg.soundOnUse then
            ns.combo.Notify("trinket", function() TT.PlaySound("trinket2", "soundUse") end)
        end
    end
    -- The 0.5s ticker keeps visuals in sync; no need to relayout on every
    -- player cast (UNIT_SPELLCAST_SUCCEEDED fires many times/sec in combat).
end)

-- True when `prefix` could draw something this pass: a trinket is equipped in the
-- configured slot, or show-at-zero keeps an icon up.
local function PrefixHasWork(prefix)
    local cfg = TT.CfgGet(prefix)
    if not cfg then return false end
    if cfg.showAtZero then return true end
    return (GetSlotInfo(cfg.slot)) ~= nil
end

local function TickerPass()
    -- Steady state: when the module is disabled the frames are already hidden.
    if not TT.CfgGet("enabled") then return end
    -- Short-circuit a pass that can produce no visible change: outside an active
    -- instance, OR neither configured slot has an equipped trinket to draw (and
    -- show-at-zero off). An equipment/zone event re-runs ApplyAll to flush any
    -- pending hide, so skipping the steady-state empty pass is safe.
    if not IsActiveInCurrentInstance() then return end
    if not PrefixHasWork("trinket1") and not PrefixHasWork("trinket2") then return end
    TT.ApplyAll()
end

-- The 0.5s visual-sync ticker only runs while the module is enabled, so a disabled
-- tracker costs zero CPU (no firing timer at all). Start/Stop are idempotent and
-- driven by the enable toggle's set handler for a live transition (no /reload).
function TT.Start()
    if TT.tickerHandle then return end
    ns.SharedTick.Register("trinket", TickerPass)
    TT.tickerHandle = true
end

function TT.Stop()
    if TT.tickerHandle then
        ns.SharedTick.Unregister("trinket")
        TT.tickerHandle = nil
    end
    -- Flush any visible icons to hidden now that we're off (ApplyVisuals early-outs
    -- on the disabled getCfg and hides), so the frames don't linger until a reload.
    TT.ApplyAll()
end

-- React to the enable toggle: start the ticker when turned on, stop it when off.
-- Called from the config set handler (TT.SetEnabled) and at login.
function TT.SetEnabled(on)
    if on then TT.Start() else TT.Stop() end
end

ns.RegisterReloadHook(function()
    if ns.ReseedTrackerOverride then
        for _, p in ipairs({ "trinket1", "trinket2" }) do
            local c = TT.CfgGet(p)
            ns.ReseedTrackerOverride("TrinketTracker" .. (p == "trinket1" and "1" or "2"),
                (c and c.cdmDest) or "essential", ns.DefaultTrackerTimerSeed)
        end
    end
    TT.ApplyAll(); TT.ApplyBorder()
end)

local initTT = CreateFrame("Frame")
initTT:RegisterEvent("PLAYER_LOGIN")
initTT:SetScript("OnEvent", function(self)
    C_Timer.After(0.5, function()
        if ns.ReseedTrackerOverride then
            for _, p in ipairs({ "trinket1", "trinket2" }) do
                local c = TT.CfgGet(p)
                ns.ReseedTrackerOverride("TrinketTracker" .. (p == "trinket1" and "1" or "2"),
                    (c and c.cdmDest) or "essential", ns.DefaultTrackerTimerSeed)
            end
        end
        TT.ApplyAll()
        -- Start the 0.5s ticker only if enabled, so a disabled tracker never schedules it.
        TT.SetEnabled(TT.CfgGet("enabled"))
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)