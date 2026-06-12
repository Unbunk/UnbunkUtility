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

    local tracker
    tracker = ns.ui.CreateItemTracker({
        frameName = frameName,
        getCfg    = function(key)
            if key == "enabled" then
                return PT.CfgGet("enabled") and GetCfg("enabled") and IsActiveInCurrentInstance()
            end
            if key == "spellId" then
                -- Route through the resolver so the buff/aura detection
                -- targets whichever potion is currently active.
                return PT.GetActiveSpellId(prefix)
            end
            return GetCfg(key)
        end,
        getItemId = function() return PT.GetActiveItemId(prefix) end,
        hasItem   = function(itemId) return itemId ~= nil and (GetItemCount(itemId) or 0) > 0 end,
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

    -- Stack count FontString anchored below the icon.
    local trackerFrame = tracker.GetFrame()
    local stackText = trackerFrame:CreateFontString(nil, "OVERLAY")
    stackText:SetPoint("TOP", trackerFrame, "BOTTOM", 0, -2)
    tracker.stackText = stackText

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
    -- Delegate to each sub-icon's anchor-aware ApplyPosition (honours anchorMode +
    -- the Cooldown Manager anchoring, falling back to the screen when "free").
    -- This runs on the 0.5s ticker too, so the chosen anchor is kept, not clobbered.
    healthTracker.ApplyPosition()
    combatTracker.ApplyPosition()
end

-- Refreshes the stack-count FontString (text + font/color) below a tracker.
function PT.ApplyStackVisuals(prefix, tracker)
    if not tracker or not tracker.stackText then return end
    local cfg = PT.CfgGet(prefix)
    if not cfg then return end

    local fs = tracker.stackText
    local fontPath = ns.ResolveFontPath(cfg.stackFontPath, cfg.stackFontKey)
    fs:SetFont(fontPath, cfg.stackFontSize or 14, cfg.stackOutline or "OUTLINE")
    local c = cfg.stackColor or { r=1, g=1, b=1, a=1 }
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)

    if not cfg.showStack then
        fs:Hide()
        return
    end
    local itemId = PT.GetActiveItemId(prefix)
    local count = itemId and (GetItemCount(itemId) or 0) or 0
    if count > 0 then
        fs:SetText(tostring(count))
        fs:Show()
    elseif cfg.showAtZero then
        fs:SetText("0")
        fs:Show()
    else
        fs:Hide()
    end
end

function PT.ApplyAll()
    if not healthTracker or not combatTracker then return end
    ApplyLayout()
    healthTracker.ApplyVisuals()
    combatTracker.ApplyVisuals()
    PT.ApplyStackVisuals("health", healthTracker)
    PT.ApplyStackVisuals("combat", combatTracker)
end

function PT.GetHealthTracker() return healthTracker end
function PT.GetCombatTracker() return combatTracker end

-- Curated set of item IDs that are health/healing potions. Sourced from
-- Wowhead filter "restores health" (filter=115;1;1). Anything not in this set
-- is treated as a combat potion.
local HEALTH_POTION_IDS = {
    [118]    = true, [858]    = true, [929]    = true, [1710]   = true,
    [2456]   = true, [3928]   = true, [4596]   = true, [9144]   = true,
    [13446]  = true, [17348]  = true, [17349]  = true, [18253]  = true,
    [18839]  = true, [22829]  = true, [22837]  = true, [22850]  = true,
    [23822]  = true, [28100]  = true, [31838]  = true, [31839]  = true,
    [31852]  = true, [31853]  = true, [32784]  = true, [32904]  = true,
    [32905]  = true, [32910]  = true, [32947]  = true, [33092]  = true,
    [33447]  = true, [33934]  = true, [34440]  = true, [39327]  = true,
    [39671]  = true, [40077]  = true, [40087]  = true, [41166]  = true,
    [43531]  = true, [43569]  = true, [57099]  = true, [57191]  = true,
    [57193]  = true, [63144]  = true, [63300]  = true, [64994]  = true,
    [67415]  = true, [76094]  = true, [76097]  = true, [92954]  = true,
    [109223] = true, [109226] = true, [113585] = true, [115498] = true,
    [117415] = true, [118916] = true, [118917] = true, [127834] = true,
    [127836] = true, [129196] = true, [136569] = true, [140351] = true,
    [142325] = true, [144396] = true, [152494] = true, [152615] = true,
    [156634] = true, [163082] = true, [167917] = true, [169300] = true,
    [169451] = true, [171267] = true, [171269] = true, [175241] = true,
    [176409] = true, [180317] = true, [187802] = true, [191369] = true,
    [191370] = true, [191371] = true, [191378] = true, [191379] = true,
    [191380] = true, [207021] = true, [207022] = true, [207023] = true,
    [207039] = true, [207040] = true, [207041] = true, [211878] = true,
    [211879] = true, [211880] = true, [212242] = true, [212243] = true,
    [212244] = true, [212318] = true, [212320] = true, [212942] = true,
    [212943] = true, [212944] = true, [212948] = true, [212949] = true,
    [212950] = true, [217905] = true, [241304] = true, [241305] = true,
    [241306] = true, [241307] = true, [244835] = true, [244838] = true,
    [244839] = true, [244849] = true,
}

-- Curated "favorite" subset of healing potions: top-tier modern potions the
-- user is most likely to want as their preferred pick.
local FAVORITE_HEALTH_POTION_IDS = {
    [207021] = true, [207022] = true, [207023] = true, [207039] = true,
    [207040] = true, [207041] = true, [211878] = true, [211879] = true,
    [211880] = true, [212242] = true, [212243] = true, [212244] = true,
    [212318] = true, [212320] = true, [212942] = true, [212943] = true,
    [212944] = true, [212948] = true, [212949] = true, [212950] = true,
    [241304] = true, [241305] = true, [241306] = true, [241307] = true,
    [244835] = true, [244838] = true, [244839] = true, [244849] = true,
}

-- Curated "favorite" subset of combat / utility potions.
local FAVORITE_COMBAT_POTION_IDS = {
    [212263] = true, [212264] = true, [212265] = true, [212327] = true,
    [212969] = true, [212970] = true, [212971] = true, [241288] = true,
    [241289] = true, [241292] = true, [241293] = true, [241308] = true,
    [241309] = true, [245897] = true, [245898] = true,
}

-- Curated set of combat / utility potion IDs. Items in neither set are
-- ignored (won't appear in either dropdown). An item that ends up in both
-- sets is reachable from both dropdowns so the user can pick a slot.
local COMBAT_POTION_IDS = {
    [22828]  = true, [22837]  = true, [58091]  = true, [58145]  = true,
    [58146]  = true, [76089]  = true, [76093]  = true, [76095]  = true,
    [86569]  = true, [92941]  = true, [92942]  = true, [92943]  = true,
    [98061]  = true, [98062]  = true, [98063]  = true, [109217] = true,
    [109218] = true, [109219] = true, [118910] = true, [118911] = true,
    [118912] = true, [118913] = true, [118914] = true, [118915] = true,
    [118922] = true, [122453] = true, [122454] = true, [122455] = true,
    [129192] = true, [142117] = true, [142326] = true, [147707] = true,
    [163222] = true, [163223] = true, [163224] = true, [166750] = true,
    [166751] = true, [167918] = true, [167919] = true, [167920] = true,
    [168489] = true, [168498] = true, [168500] = true, [171270] = true,
    [171273] = true, [171275] = true, [182298] = true, [183857] = true,
    [184227] = true, [191381] = true, [191382] = true, [191383] = true,
    [191387] = true, [191388] = true, [191389] = true, [191905] = true,
    [191906] = true, [191907] = true, [191912] = true, [191913] = true,
    [191914] = true, [212263] = true, [212264] = true, [212265] = true,
    [212327] = true, [212969] = true, [212970] = true, [212971] = true,
    [241288] = true, [241289] = true, [241292] = true, [241293] = true,
    [241308] = true, [241309] = true, [245897] = true, [245898] = true,
    [245902] = true, [245903] = true, [245910] = true, [245911] = true,
}

-- Scan the player's bags (including reagent bag) and return a sorted list of
-- distinct potions found: { { id = itemID, name = localizedName }, ... }.
-- A "potion" is anything with itemClassID = 0 (Consumable) and
-- itemSubclassID = 1 (Potion).
--
-- `category` is optional: "health" returns only IDs in HEALTH_POTION_IDS,
-- "combat" returns only IDs in COMBAT_POTION_IDS, nil returns the full
-- (uncategorized) list.
function PT.GetBagPotions(category)
    local found, seenIds, byName = {}, {}, {}
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            if itemID and not seenIds[itemID] then
                seenIds[itemID] = true
                local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
                if classID == 0 and subclassID == 1 then
                    local include
                    if category == "health" then
                        include = HEALTH_POTION_IDS[itemID] == true
                    elseif category == "combat" then
                        include = COMBAT_POTION_IDS[itemID] == true
                    else
                        include = true
                    end
                    if include then
                        local name = C_Item.GetItemNameByID(itemID) or tostring(itemID)
                        -- Collapse multiple ilvls of the same potion to one
                        -- entry so the dropdown is not cluttered.
                        if not byName[name] then
                            byName[name] = true
                            table.insert(found, { id = itemID, name = name })
                        end
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    return found
end

-- Returns all item IDs in `set` that share the same localized name as `anId`.
-- Used to treat multiple ilvls / qualities of the same potion as one family.
local function FamilyByName(set, anId)
    if not anId then return {} end
    local anName = C_Item.GetItemNameByID(anId)
    if not anName then return { anId } end
    local out = {}
    for id in pairs(set) do
        if C_Item.GetItemNameByID(id) == anName then
            table.insert(out, id)
        end
    end
    return out
end

-- Returns the curated "favorite" list for a category as { {id,name}, ... },
-- deduped by name (multiple ilvls of the same potion collapse to one entry).
function PT.GetFavoritePotions(prefix)
    local favSet = (prefix == "health") and FAVORITE_HEALTH_POTION_IDS or FAVORITE_COMBAT_POTION_IDS
    local byName, out = {}, {}
    for id in pairs(favSet) do
        local name = C_Item.GetItemNameByID(id)
        if not name then
            C_Item.RequestLoadItemDataByID(id)
            name = "[" .. id .. "]"
        end
        if not byName[name] then
            byName[name] = true
            table.insert(out, { id = id, name = name })
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Cache for GetActiveItemId / GetActiveSpellId. The resolver is called many
-- times per tick (getCfg/getItemId/hasItem/ApplyStackVisuals × 2 trackers),
-- and each call scans ~108-id potion sets and up to 120 bag slots. We
-- recompute lazily and invalidate when bag contents or config change.
local activeCache = {
    health = { dirty = true },
    combat = { dirty = true },
}

local function InvalidateActiveCache()
    activeCache.health.dirty = true
    activeCache.combat.dirty = true
end
PT.InvalidateActiveCache = InvalidateActiveCache

local function ResolveActiveItemId(prefix)
    local cfg = PT.CfgGet(prefix)
    if not cfg then return nil end

    local favSet  = (prefix == "health") and FAVORITE_HEALTH_POTION_IDS or FAVORITE_COMBAT_POTION_IDS
    local mainSet = (prefix == "health") and HEALTH_POTION_IDS or COMBAT_POTION_IDS

    -- 1. Favorite (if enabled): any family member in bags overrides.
    if cfg.favoriteEnabled and cfg.favoriteId then
        for _, id in ipairs(FamilyByName(favSet, cfg.favoriteId)) do
            if (GetItemCount(id) or 0) > 0 then return id end
        end
    end

    -- 2. Configured potion or any of its family (different ilvl, same name)
    --    if any is in bags.
    local configuredId = cfg.itemId
    if configuredId then
        for _, id in ipairs(FamilyByName(mainSet, configuredId)) do
            if (GetItemCount(id) or 0) > 0 then return id end
        end
    end

    -- 3. Fallback: first potion of the same category found in bags. Persist
    --    the itemId so the main dropdown reflects what is being tracked.
    --    spellId is derived dynamically by GetActiveSpellId — no need to
    --    store it (was redundant, and stored stale values when the item
    --    data wasn't loaded yet).
    --    NOTE: On a fresh install itemId is intentionally unset and the main
    --    dropdown is resolver-driven, so this writes cfg.itemId from within a
    --    getter path. The PT.CfgSet here re-invalidates the cache mid-resolve,
    --    but GetActiveItemId clears the dirty flag immediately after we return,
    --    so the effect is benign (no infinite re-resolve).
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and mainSet[id] then
                if id ~= configuredId then
                    cfg.itemId = id
                    PT.CfgSet(prefix, cfg)
                end
                return id
            end
        end
    end

    -- Nothing of this category is in bags. Prefer the favourite (if enabled) so
    -- "show at 0 stacks" displays the user's preferred potion icon; otherwise the
    -- last configured one. (When show-at-0 is off the icon is hidden anyway.)
    if cfg.favoriteEnabled and cfg.favoriteId then return cfg.favoriteId end
    return configuredId
end

-- Returns the itemID we should actually track right now for `prefix`. Prefers
-- the user-configured potion when it is in bags; otherwise falls back to the
-- first potion of the same category found in inventory slot order so the
-- tracker keeps working when the favourite runs out.
function PT.GetActiveItemId(prefix)
    local entry = activeCache[prefix]
    if not entry then return ResolveActiveItemId(prefix) end
    if entry.dirty then
        entry.id      = ResolveActiveItemId(prefix)
        entry.spellId = entry.id and (select(2, C_Item.GetItemSpell(entry.id))) or nil
        -- C_Item.GetItemSpell returns nil while the item's data is still
        -- loading from the server. Caching that nil as clean would freeze the
        -- buff/aura timer + use-sound detection until the next bag event, so
        -- stay dirty until the spellId actually resolves (ITEM_DATA_LOAD_RESULT
        -- also invalidates the cache once data arrives).
        entry.dirty   = (entry.id ~= nil and entry.spellId == nil)
    end
    return entry.id
end

function PT.GetActiveSpellId(prefix)
    local entry = activeCache[prefix]
    if not entry then
        local id = ResolveActiveItemId(prefix)
        if not id then return nil end
        return (select(2, C_Item.GetItemSpell(id)))
    end
    if entry.dirty then PT.GetActiveItemId(prefix) end
    return entry.spellId
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
-- Refresh the resolver cache once the server delivers item data, so a freshly
-- resolved potion whose item/spell data loaded late gets its spellId filled in
-- (otherwise a cached nil spellId would persist until the next bag event).
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
-- BAG_UPDATE_COOLDOWN is intentionally NOT registered: it fires on essentially
-- every cooldown tick in combat, and invalidating + full ApplyAll there is
-- redundant — the 0.5s ticker already keeps cooldown visuals in sync and
-- ApplyVisuals reads cooldown state fresh each pass.

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "BAG_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ITEM_DATA_LOAD_RESULT" then
        InvalidateActiveCache()
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit ~= "player" then return end
        local healthSpellId = PT.GetActiveSpellId("health")
        local combatSpellId = PT.GetActiveSpellId("combat")
        if healthSpellId and spellId == healthSpellId then
            -- Start the icon's in-combat heuristic green timer now (independent of
            -- the sound toggle); the live buff aura is unreadable in combat.
            if healthTracker then healthTracker.NotifyUsed() end
            local hc = PT.CfgGet("health")
            if hc and hc.soundOnUse then
                ns.combo.Notify("potion", function() PT.PlaySound("health", "soundUse") end)
            end
        elseif combatSpellId and spellId == combatSpellId then
            if combatTracker then combatTracker.NotifyUsed() end
            local cc = PT.CfgGet("combat")
            if cc and cc.soundOnUse then
                ns.combo.Notify("potion", function() PT.PlaySound("combat", "soundUse") end)
            end
        end
        -- The 0.5s ticker already keeps visuals in sync; no need to relayout
        -- on every player cast (fires many times per second in combat).
        return
    end
    PT.ApplyAll()
end)

C_Timer.NewTicker(0.5, function()
    -- Steady state: when the module is disabled the frames are already
    -- hidden, no need to redo the work every tick.
    if not PT.CfgGet("enabled") then return end
    PT.ApplyAll()
end)

ns.RegisterReloadHook(function()
    InvalidateActiveCache()
    PT.ApplyAll()
end)

local initPT = CreateFrame("Frame")
initPT:RegisterEvent("PLAYER_LOGIN")
initPT:SetScript("OnEvent", function(self)
    local healthId = PT.CfgGet("health") and PT.CfgGet("health").itemId
    local combatId = PT.CfgGet("combat") and PT.CfgGet("combat").itemId
    if healthId then C_Item.RequestLoadItemDataByID(healthId) end
    if combatId then C_Item.RequestLoadItemDataByID(combatId) end
    -- Preload favorite list item data so names appear in the dropdown.
    for id in pairs(FAVORITE_HEALTH_POTION_IDS) do C_Item.RequestLoadItemDataByID(id) end
    for id in pairs(FAVORITE_COMBAT_POTION_IDS) do C_Item.RequestLoadItemDataByID(id) end
    C_Timer.After(0.5, function()
        PT.ApplyAll()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)