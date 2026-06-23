-- Modules/HealthstoneTracker/Core/HealthstoneTracker.lua
-- Tracks every Healthstone variant present in the player's bags at the same
-- time, side by side in a horizontal row anchored at the configured position.

local _, ns = ...
local L = ns.L
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(HT.CfgGet("instanceFilter"))
end

-- ── Item catalog ──────────────────────────────────────────────────────────────

-- Every Healthstone item ID known across every expansion. Anything in here
-- that is in the bag will be tracked.
local HEALTHSTONE_ITEM_IDS = {
    [5509]   = true, [5510]   = true, [5511]   = true, [5512]   = true,
    [9421]   = true,
    [19004]  = true, [19005]  = true, [19006]  = true, [19007]  = true,
    [19008]  = true, [19009]  = true, [19010]  = true, [19011]  = true,
    [19012]  = true, [19013]  = true,
    [22103]  = true, [22104]  = true, [22105]  = true,
    [36889]  = true, [36890]  = true, [36891]  = true, [36892]  = true,
    [36893]  = true, [36894]  = true,
    [138412] = true, [224464] = true, [228417] = true,
}

-- Display priority for the leftmost slot: regular Healthstone (5512) first,
-- then the Demonic Healthstone (224464). Anything else fills the row to the
-- right in numerical order.
local PRIORITY            = { 5512, 224464 }
local FALLBACK_PREVIEW_ID = 5512
local ICON_GAP            = 4
local MAX_TRACKERS        = 8

-- "Used in combat" state lives per-tracker on `t.usedInCombat`: set by the cast
-- handler when the player uses that variant in combat, and stays sticky (even if
-- that variant's last stone leaves the bag) until PLAYER_REGEN_ENABLED (combat
-- end). The "C" marker is shown on a tracker while that flag is set and the
-- player is still in combat (the healthstone's real cooldown only starts when
-- combat ends, so there is no countdown to show while it is set).

-- ── Resolver + cache ──────────────────────────────────────────────────────────

-- `spellIds` memoizes id -> resolved use spellId so we don't call
-- C_Item.GetItemSpell every tick / cast (mirrors PotionTracker's spellId cache).
local activeCache = { dirty = true, ids = {}, spellIds = {} }

local function InvalidateActiveCache()
    activeCache.dirty = true
end
HT.InvalidateActiveCache = InvalidateActiveCache

-- Resolved use-spell for an item id, cached. A nil result (item data not yet
-- loaded) is left uncached so a later tick can resolve it.
local function GetSpellIdForItem(id)
    if not id then return nil end
    local cached = activeCache.spellIds[id]
    if cached ~= nil then return cached end
    local spellId = (select(2, C_Item.GetItemSpell(id)))
    if spellId then activeCache.spellIds[id] = spellId end
    return spellId
end

local function ResolveActiveItemIds()
    local present = {}
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and HEALTHSTONE_ITEM_IDS[id] then
                present[id] = true
            end
        end
    end
    local list = {}
    for _, pid in ipairs(PRIORITY) do
        if present[pid] then
            table.insert(list, pid)
            present[pid] = nil
        end
    end
    local rest = {}
    for id in pairs(present) do table.insert(rest, id) end
    table.sort(rest)
    for _, id in ipairs(rest) do table.insert(list, id) end
    return list
end

local function GetActiveItemIds()
    if activeCache.dirty then
        activeCache.ids   = ResolveActiveItemIds()
        activeCache.dirty = false
    end
    return activeCache.ids
end
HT.GetActiveItemIds = GetActiveItemIds

-- Backward-compat single-item getter: the first slot's ID.
function HT.GetActiveItemId()
    return GetActiveItemIds()[1]
end

-- ── Tracker pool ──────────────────────────────────────────────────────────────

local trackers = {}  -- pool, lazily grown up to MAX_TRACKERS

-- Variant ids the player consumed in combat (set by UNIT_SPELLCAST_SUCCEEDED,
-- cleared on PLAYER_REGEN_ENABLED). Kept keyed by id — not by tracker index —
-- so the "C" marker still shows after the LAST stone of a variant is consumed
-- and that id has left the bag (and thus the resolved active-id list).
local usedInCombatById = {}

-- Reused scratch tables for the in-combat display-list build in ApplyAll, so a
-- combat tick with a sticky variant doesn't allocate two fresh tables every pass.
local scratchIds  = {}
local scratchSeen = {}

local function PlayReadySoundDebounced()
    -- All variants likely share the GCD on combat exit; debounce so we don't
    -- play the ready sound multiple times in the same tick.
    local now = GetTime()
    if HT._lastReadyAt and (now - HT._lastReadyAt) < 0.5 then return end
    HT._lastReadyAt = now
    if HT.CfgGet("soundOnReady") then
        HT.PlaySound("soundReady")
    end
end

local function CreateTracker(index)
    local t
    t = ns.ui.CreateItemTracker({
        frameName = "HealthstoneTrackerFrame" .. index,
        getCfg    = function(key)
            if key == "enabled" then
                return HT.CfgGet("enabled") and IsActiveInCurrentInstance()
            end
            if key == "spellId" then
                return GetSpellIdForItem(t.assignedId)
            end
            return HT.CfgGet(key)
        end,
        setCfg  = function(key, val) HT.CfgSet(key, val) end,   -- cdmAtEnd flip on a cross-strip drag
        getItemId = function() return t.assignedId end,
        -- The shared icon's in-CDM stacks must count CHARGES (includeUses=true), not plain item stacks,
        -- just like the module's own draw below — otherwise a multi-charge healthstone shows the wrong number.
        getCount  = function()
            if HT.testMode then return 2 end   -- preview shows a 2-charge stone (see HT.RunTest)
            return t.assignedId and (GetItemCount(t.assignedId, false, true) or 0) or 0
        end,
        hasItem   = function(itemId)
            -- includeUses=true: count charges (a healthstone has several).
            return itemId ~= nil and (GetItemCount(itemId, false, true) or 0) > 0
        end,
        onDragStop = function(x, y)
            -- Only the primary slot writes back the configured position;
            -- the rest just snap to it on the next ApplyLayout.
            if index == 1 then
                HT.CfgSet("posX", x)
                HT.CfgSet("posY", y)
                if HT.pe then HT.pe.Refresh() end
            end
        end,
        onReady = function() PlayReadySoundDebounced() end,
    })

    local frame = t.GetFrame()

    -- Stack count below the icon (charges across all stacks for this variant).
    local stackText = frame:CreateFontString(nil, "OVERLAY")
    stackText:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    stackText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    t.stackText = stackText

    -- "C" marker centered on the icon: shown when the variant was used in
    -- combat and the real CD hasn't kicked in yet (post-combat).
    local combatC = frame:CreateFontString(nil, "OVERLAY")
    combatC:SetPoint("CENTER", frame, "CENTER", 0, 0)
    combatC:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    combatC:SetTextColor(1, 0.15, 0.15, 1)
    combatC:SetText(L["C"])
    combatC:Hide()
    t.combatC = combatC

    t.assignedId   = nil
    t.usedInCombat = false
    t.index        = index
    frame:Hide()

    return t
end

local function EnsureTracker(index)
    if not trackers[index] then
        trackers[index] = CreateTracker(index)
    end
    return trackers[index]
end

-- ── Per-tracker visuals ───────────────────────────────────────────────────────

-- Default per-icon override-set for a healthstone: ONLY Timer (size 14 + urgency thresholds) and
-- Stacks/Charges (size 12, thick outline, X+3 Y-2). Everything else inherits the group.
function HT.OverrideSeed()
    return {
        timerFontSize = 14,
        timerThresholdsEnabled = true,
        timerThresholds = ns.DefaultTrackerTimerThresholds(),
        stackFontSize = 12, stackOutline = "THICKOUTLINE", stackOffX = 3, stackOffY = -1,
    }
end

local function ApplyStackVisualsFor(t)
    if not t or not t.stackText then return end
    -- Charges are now drawn by the shared TimerIcon (result.ApplyDestExtras) in every mode — free (the
    -- icon's own config, via freeExtras=true; the count via config.getCount) and in-CDM (the per-icon
    -- override / below-player bucket). We keep this only to lazily seed the below-player override from this
    -- healthstone's look (so the in-CDM look starts right) and to keep our own FontString hidden.
    ns.TrackerSuppressOwnExtras(t.icon, t.GetFrame():GetName(), HT.CfgGet("cdmDest"), HT.OverrideSeed)
    t.stackText:Hide()
end

-- Re-apply stack text visuals to every pooled tracker (config-driven refresh).
function HT.ApplyStackVisuals()
    for _, t in ipairs(trackers) do ApplyStackVisualsFor(t) end
end

-- Re-apply timer text font/size/outline to every pooled tracker.
function HT.ApplyTimerVisuals()
    for _, t in ipairs(trackers) do
        if t.ApplyFont then t.ApplyFont() end
    end
end

-- Size the red "C" marker relative to the icon, using the timer font config.
local function ApplyCombatCFont(t)
    local iconW = HT.CfgGet("iconWidth")  or 30
    local iconH = HT.CfgGet("iconHeight") or 30
    local fontPath = ns.ResolveFontPath(HT.CfgGet("timerFontPath"), HT.CfgGet("timerFontKey"))
    local size = math.max(12, math.floor(math.min(iconW, iconH) * 0.65))
    t.combatC:SetFont(fontPath, size, HT.CfgGet("timerOutline") or "OUTLINE")
end

local function ApplyCombatMarkerFor(t)
    if not t or not t.combatC then return end
    if HT.testMode or not t.usedInCombat then
        t.combatC:Hide()
        return
    end
    -- The healthstone's real 1-min cooldown only STARTS when the player leaves
    -- combat. So once we're out of combat, drop the flag and let ApplyVisuals
    -- show the normal countdown instead of the "C".
    if not UnitAffectingCombat("player") then
        t.usedInCombat = false
        t.combatC:Hide()
        return
    end
    -- Still in the combat where it was used: the CD hasn't begun ticking yet,
    -- so show the red "C" in place of the (deferred / not-yet-running) timer.
    ApplyCombatCFont(t)
    -- Suppress anything ApplyVisuals may have drawn for the deferred cooldown
    -- (swipe / timer text / ready blink) so only the "C" is visible. Forget the
    -- ItemTracker timer cache too so the real countdown re-applies once the "C" clears.
    if t.InvalidateTimerCache then t.InvalidateTimerCache() end
    t.icon.ClearTimer()
    t.icon.HideCheck()
    t.combatC:Show()
end

-- Layout active trackers in a horizontal row to the right of the configured
-- position. Hidden trackers (no assignedId) are skipped.
local function ApplyLayout()
    -- Don't fight the drag: while the row is unlocked for repositioning the user
    -- is moving the primary icon (StartMoving). A ClearAllPoints+SetPoint here
    -- would teleport it; the next locked tick re-anchors from the saved posX/posY.
    -- (Mirrors TimerIcon.ApplyPosition's `if unlocked then return end` guard.)
    if HT.IsUnlocked() then return end
    local x = HT.CfgGet("posX")     or 0
    local y = HT.CfgGet("posY")     or 0
    local w = HT.CfgGet("iconWidth") or 30
    -- freeIndex counts only the FREE (non-CDM) icons so the on-screen row stays
    -- compact when some variants are placed in the Cooldown Manager row instead.
    local freeIndex = 0
    for _, t in ipairs(trackers) do
        if t.assignedId then
            if t.icon and t.icon.CDMActive and t.icon.CDMActive() then
                -- CDM-managed (includeInCdm + a live destination): ns.CDMAnchor owns
                -- this icon's position AND size. Delegate to ApplyPosition (which
                -- asks CDMAnchor to relayout the row) instead of clobbering it with
                -- a free UIParent anchor every tick — that was why includeInCdm had
                -- no effect.
                t.ApplyPosition()
            else
                local frame = t.GetFrame()
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER",
                    x + freeIndex * (w + ICON_GAP), y)
                freeIndex = freeIndex + 1
            end
        end
    end
end

-- ── Main update ───────────────────────────────────────────────────────────────

function HT.ApplyAll()
    if HT.testMode then
        -- Timed preview: auto-stop once the duration elapses (like the BRez test).
        if GetTime() >= HT.testEndsAt then
            HT.StopTest()
            return
        end
        ApplyLayout()
        ApplyStackVisualsFor(trackers[1])
        return
    end

    -- Build the display list: variants currently in bags, plus any variant we
    -- consumed in combat whose last stone has since left the bag (so its red
    -- "C" stays visible until combat ends). The sticky tail only applies while
    -- still in combat — out of combat the per-tracker flag is dropped normally.
    local present = GetActiveItemIds()
    local ids = present
    if next(usedInCombatById) and UnitAffectingCombat("player") then
        wipe(scratchIds)
        wipe(scratchSeen)
        for _, id in ipairs(present) do
            scratchIds[#scratchIds + 1] = id
            scratchSeen[id] = true
        end
        for id in pairs(usedInCombatById) do
            if not scratchSeen[id] then
                scratchIds[#scratchIds + 1] = id
                scratchSeen[id] = true
            end
        end
        ids = scratchIds
    end

    -- Show-at-zero: nothing in bags but the option is on -> display the default
    -- Healthstone icon (with a "0" stack) so the slot stays as a restock reminder.
    -- ItemTracker.ApplyVisuals shows it despite hasItem=false because showAtZero is set.
    if #ids == 0 and HT.CfgGet("showAtZero")
       and HT.CfgGet("enabled") and IsActiveInCurrentInstance() and HT.CfgGet("showIcon") then
        ids = { FALLBACK_PREVIEW_ID }
    end

    local n = math.min(#ids, MAX_TRACKERS)

    for i = 1, n do
        local t = EnsureTracker(i)
        local id = ids[i]
        t.assignedId = id
        -- Stacks first: in the CDM this suppresses our own FS and seeds the per-icon override BEFORE the
        -- icon repaints (ApplyVisuals/direct path → ApplyDestExtras), so there's no first-tick bucket flash.
        ApplyStackVisualsFor(t)
        if usedInCombatById[id] and (GetItemCount(id, false, true) or 0) <= 0 then
            -- Consumed-in-combat variant no longer in bags: drive the icon
            -- directly (ApplyVisuals would hide it since hasItem is false) so
            -- the "C" marker has an icon to sit on — but only when the module
            -- would actually show an icon here. This direct path used to bypass
            -- the enabled / instance-filter / showIcon checks that the
            -- ApplyVisuals branch honours, leaving a ghost icon + "C" even with
            -- the module off or in an excluded instance.
            t.usedInCombat = true
            if HT.CfgGet("enabled") and IsActiveInCurrentInstance() and HT.CfgGet("showIcon") then
                local _, _, _, _, iconID = C_Item.GetItemInfoInstant(id)
                if iconID then t.icon.SetIcon(iconID) end
                t.icon.ApplySize()
                t.icon.Show()
                t.icon.HideCheck()
                -- Direct path bypasses ItemTracker.ApplyVisuals' timer cache, so forget
                -- it here too — otherwise a later identical SetTimer there could be skipped.
                if t.InvalidateTimerCache then t.InvalidateTimerCache() end
                t.icon.ClearTimer()
            else
                t.icon.Hide()
            end
        else
            t.ApplyVisuals()
        end
        ApplyCombatMarkerFor(t)
    end

    -- Hide any pool entries we didn't need this pass.
    for i = n + 1, #trackers do
        trackers[i].assignedId   = nil
        trackers[i].usedInCombat = false
        trackers[i].combatC:Hide()
        trackers[i].GetFrame():Hide()
    end

    ApplyLayout()
end

-- ── Placement / border refresh (called by the config UI) ──────────────────────
-- The config panel's Placement section (Include in cdm, Anchor to, Icon at the
-- end of the row, Row) calls HT.ApplyPosition, and the Border section (Show
-- border / Border color / Border thickness) calls HT.ApplyBorder. Both delegate
-- to the pooled trackers' ItemTracker methods — without these, every such control
-- raised "attempt to call field ApplyPosition/ApplyBorder (a nil value)".

function HT.ApplyBorder()
    for _, t in ipairs(trackers) do
        if t.ApplyBorder then t.ApplyBorder() end
    end
end

function HT.ApplyPosition()
    -- ApplyAll re-applies size (ApplyVisuals → icon.ApplySize, CDM-aware) and ends
    -- with ApplyLayout, which now honours includeInCdm/cdmDest — so a CDM toggle
    -- relocates AND resizes the icons correctly.
    HT.ApplyAll()
end

-- ── Test mode (single-icon preview) ───────────────────────────────────────────

HT.testMode   = false
HT.testEndsAt = 0
local TEST_DURATION = 8   -- seconds: the preview cooldown fully recharges over this, then auto-stops

-- Timed preview (like the BRez test, not a toggle): show the primary healthstone on
-- COOLDOWN — a 2-charge stack with the radial cooldown sweep recharging over `duration`
-- seconds — then auto-stop with the ready flash. The earlier preview showed the in-combat
-- "C" marker; this one shows the real cooldown coming back instead.
function HT.RunTest(duration)
    duration = duration or TEST_DURATION
    local t = EnsureTracker(1)
    HT.testMode   = true
    HT.testEndsAt = GetTime() + duration

    -- Only the primary is visible during preview; hide the rest of the row.
    for i = 2, #trackers do
        trackers[i].combatC:Hide()
        trackers[i].GetFrame():Hide()
    end

    local id = HT.GetActiveItemId() or FALLBACK_PREVIEW_ID
    t.assignedId   = id
    t.usedInCombat = false
    t.combatC:Hide()                              -- this preview shows a real CD, not the "C"
    local _, _, _, _, iconID = C_Item.GetItemInfoInstant(id)
    if iconID then t.icon.SetIcon(iconID) end

    ApplyStackVisualsFor(t)                        -- keep our own FS hidden; the shared stacks draw the "2"
    t.icon.ApplySize()                             -- ApplyDestExtras here draws the forced "2" (getCount → 2 in test)
    t.icon.Show()
    t.icon.HideCheck()
    t.icon.SetTimer(HT.testEndsAt, duration)       -- radial cooldown sweep + countdown text, greys the icon
    ApplyLayout()

    if HT.CfgGet("soundOnUse") then
        HT.PlaySound("soundUse")
    end
end

function HT.StopTest()
    local t = trackers[1]
    if not t or not HT.testMode then return end
    HT.testMode   = false
    HT.testEndsAt = 0
    t.combatC:Hide()
    if t.InvalidateTimerCache then t.InvalidateTimerCache() end  -- preview used SetTimer directly; forget the cache
    t.icon.ClearTimer()        -- the preview cooldown is done; drop the sweep + countdown
    t.icon.BlinkCheck()        -- ready flash, as the recharge completes
    if HT.CfgGet("soundOnReady") then
        HT.PlaySound("soundReady")
    end
    C_Timer.After(1.5, function()
        if not HT.testMode then HT.ApplyAll() end
    end)
end

function HT.IsTesting() return HT.testMode end

-- ── Unlock / repositioning ────────────────────────────────────────────────────

function HT.SetUnlocked(val)
    local t = EnsureTracker(1)
    if val then
        for i = 2, #trackers do
            trackers[i].combatC:Hide()
            trackers[i].GetFrame():Hide()
        end
        local id = HT.GetActiveItemId() or FALLBACK_PREVIEW_ID
        t.assignedId = id
        local _, _, _, _, iconID = C_Item.GetItemInfoInstant(id)
        if iconID then t.icon.SetIcon(iconID) end
        t.icon.ApplySize()
        if t.InvalidateTimerCache then t.InvalidateTimerCache() end  -- unlock preview clears the timer outside ApplyVisuals' cache
        t.icon.ClearTimer()
        t.icon.ShowCheck()
        t.SetUnlocked(true)
        t.GetFrame():Show()
        ApplyLayout()
    else
        t.SetUnlocked(false)
        HT.ApplyAll()
    end
end

function HT.IsUnlocked()
    return trackers[1] and trackers[1].IsUnlocked() or false
end

-- Primary tracker accessor (kept for backward compat with config UI).
function HT.GetTracker() return trackers[1] end

-- ── Events ────────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- BAG_UPDATE_COOLDOWN is intentionally NOT registered (matches PotionTracker):
-- it fires on essentially every cooldown tick in combat, and invalidating the
-- resolver cache + a full ApplyAll there is redundant — the resolver only cares
-- about bag *contents* (BAG_UPDATE) and the 0.5s ticker keeps the cooldown swipe
-- in sync by reading cooldown state fresh each pass.
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "BAG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        InvalidateActiveCache()
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: clear the per-tracker and per-variant "used in combat"
        -- flags so the "C" marker doesn't linger into the next pull.
        wipe(usedInCombatById)
        for _, t in ipairs(trackers) do
            t.usedInCombat = false
            if t.combatC then t.combatC:Hide() end
        end
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- While disabled, do no per-cast work: this branch otherwise loops every
        -- pooled tracker and resolves spellIds on EVERY player cast (many/sec in
        -- combat). Re-enable is UI-driven, so skipping here is safe.
        if not HT.CfgGet("enabled") then return end
        local unit, _, spellId = ...
        if unit == "player" then
            local inCombat = UnitAffectingCombat("player")
            for _, t in ipairs(trackers) do
                local id = t.assignedId
                local itemSpellId = id and GetSpellIdForItem(id)
                if itemSpellId and itemSpellId == spellId then
                    if HT.CfgGet("soundOnUse") then
                        HT.PlaySound("soundUse")
                    end
                    if inCombat then
                        t.usedInCombat = true
                        -- Sticky by variant id: this survives the variant's
                        -- last stone leaving the bag, so the "C" still shows
                        -- after the final healthstone is consumed (until
                        -- PLAYER_REGEN_ENABLED). See ApplyAll.
                        usedInCombatById[id] = true
                    end
                    -- Only relayout when THIS player cast was actually one of our
                    -- healthstones; an unrelated cast leaves the row unchanged and
                    -- the 0.5s ticker keeps it in sync — no need to relayout on
                    -- every player cast (fires many times/sec in combat).
                    if HT.CfgGet("enabled") then HT.ApplyAll() end
                    break
                end
            end
        end
        return
    end
    -- Cache invalidation (BAG_UPDATE / PEW) above must run unconditionally; only
    -- gate the relayout on enabled (the ticker already guards on enabled too).
    if HT.CfgGet("enabled") then HT.ApplyAll() end
end)

-- The 0.5s steady-state ticker. Created only while the module is enabled
-- (HT.Start) and cancelled on disable (HT.Stop) so a disabled module costs zero
-- CPU — no per-tick CfgGet/early-out even runs.
local function TickerPass()
    -- Short-circuit a pass that can produce no visible change: not in an active
    -- instance, OR nothing to draw (no healthstone in bags, no sticky in-combat
    -- variant, and show-at-zero off). Skipping avoids a full relayout when the row
    -- is empty anyway. A bag/cast event flips it back on via the event ApplyAll.
    if not IsActiveInCurrentInstance() then return end
    if not HT.testMode and #GetActiveItemIds() == 0 and not next(usedInCombatById)
       and not HT.CfgGet("showAtZero") then
        return
    end
    HT.ApplyAll()
end

-- Start/Stop the steady-state poll via the shared 0.5s driver. HT._ticker is a truthy
-- sentinel kept while registered, so the disabled module is fully stopped (not just early-
-- returning each tick) and re-enabling fully restarts it. Idempotent: safe to call repeatedly.
function HT.Start()
    if HT._ticker then return end
    ns.SharedTick.Register("healthstone", TickerPass)
    HT._ticker = true
end

function HT.Stop()
    if HT._ticker then
        ns.SharedTick.Unregister("healthstone")
        HT._ticker = nil
    end
end

-- Apply the persisted enabled state to the live ticker (login + enable toggle).
function HT.SetEnabled(on)
    if on then HT.Start() else HT.Stop() end
end

ns.RegisterReloadHook(function()
    InvalidateActiveCache()
    HT.ApplyAll()
    HT.ApplyBorder()
end)

local initHT = CreateFrame("Frame")
initHT:RegisterEvent("PLAYER_LOGIN")
initHT:SetScript("OnEvent", function(self)
    -- Preload every known healthstone so names/icons/spells are resolved
    -- by the time the resolver looks at the bag.
    for id in pairs(HEALTHSTONE_ITEM_IDS) do
        C_Item.RequestLoadItemDataByID(id)
    end
    -- Eagerly create the primary tracker so SetUnlocked / RunTest can run
    -- before the first bag update fires.
    EnsureTracker(1)
    -- Start the steady-state ticker ONLY if currently enabled; a disabled module
    -- spins up no ticker at all (HT.Start on the enable toggle restarts it live).
    HT.SetEnabled(HT.CfgGet("enabled") ~= false)
    C_Timer.After(0.5, function() HT.ApplyAll() end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
