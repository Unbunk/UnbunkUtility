-- UI/Shared/ItemTracker.lua
-- Reusable item tracker widget (potion, trinket, etc.)
--
-- Usage:
--   local tracker = ns.ui.CreateItemTracker({
--       frameName  = "MyTrackerFrame",
--       getCfg     = function(key) return MyCfg_Get(key) end,
--       getItemId  = function() return itemId end,
--       hasItem    = function(itemId) return true/false end,
--       onDragStop = function(x, y) ... end,
--   })
--   tracker.ApplyVisuals()
--   tracker.ApplyPosition()
--   tracker.ApplyFont()
--   tracker.ApplySize()
--   tracker.SetUnlocked(bool)
--   tracker.IsUnlocked()
--   tracker.GetFrame()

local _, ns = ...
ns.ui = ns.ui or {}

-- Shared read-only "active buff" colour. Hoisted to a module constant so the
-- 0.5s ApplyVisuals tick doesn't allocate a fresh table every pass while a green
-- timer is shown (SetTimer only stores the reference and reads r/g/b, never
-- mutates it — so a single shared table is safe across all tracker instances).
local GREEN = { r = 0, g = 1, b = 0 }

function ns.ui.CreateItemTracker(config)
    local frameName  = config.frameName
    local getCfg     = config.getCfg
    local getItemId  = config.getItemId
    local hasItem    = config.hasItem
    local onDragStop = config.onDragStop

    local tracker    = {}
    local hasCooldown = false
    local lastExpiry  = nil  -- GetTime() at which the tracked cooldown ends
    local lastUseAt   = nil  -- GetTime() of the last use (set by NotifyUsed), for
                             -- the in-combat heuristic green timer
    -- Per-item cache of the (constant) icon id + usable-spell name. The 0.5s
    -- ApplyVisuals tick would otherwise re-query C_Item every pass, and each call
    -- allocates the returned strings (GetItemInfo also builds the item link/name).
    -- Invalidated when the tracked itemId changes.
    local cachedItemId, cachedIconId, cachedSpellName = nil, nil, nil

    local icon = ns.ui.CreateTimerIcon({
        name    = frameName,
        getCfg  = getCfg,
        onDragStop = function(x, y)
            if onDragStop then onDragStop(x, y) end
        end,
    })

    icon.onExpire = function() end

    function tracker.ApplyVisuals()
        if not getCfg("enabled") then
            icon.Hide()
            return
        end

        local itemId = getItemId()
        -- "Show at 0 stacks" keeps the icon visible even with none in bags, as long
        -- as an item id is known to draw (the favourite / configured / default one).
        local itemExists = itemId and (getCfg("showAtZero") or hasItem(itemId))

        if not itemExists or not getCfg("showIcon") then
            icon.Hide()
            return
        end

        -- The usable-spell and the icon are constant per itemId: resolve each once
        -- and cache, so the steady-state tick allocates nothing here. Reset on change.
        if itemId ~= cachedItemId then
            cachedItemId, cachedIconId, cachedSpellName = itemId, nil, nil
        end

        -- Resolve the item's on-use spell once and cache the verdict, because
        -- GetItemSpell returns nil for TWO different reasons:
        --   (a) the item data isn't loaded yet (transient — retry next tick), or
        --   (b) the item genuinely has no on-use spell (a passive/stat trinket).
        -- We must tell them apart: caching nil for (b) made the tick re-query AND
        -- re-RequestLoadItemDataByID forever on a passive trinket, which spammed
        -- GET_ITEM_INFO_RECEIVED → the native CooldownViewer relayouts → a ~250 KB/s
        -- churn storm. cachedSpellName: nil = unresolved, false = loaded/no-use, string = spell.
        if cachedSpellName == nil then
            local nm = C_Item.GetItemSpell and select(1, C_Item.GetItemSpell(itemId))
            if nm then
                cachedSpellName = nm
            elseif C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(itemId) then
                cachedSpellName = false        -- loaded, genuinely no on-use → stop retrying
            else
                C_Item.RequestLoadItemDataByID(itemId)  -- not loaded yet → retry next tick
                icon.Hide()
                return
            end
        end
        if not cachedSpellName then             -- false sentinel: item isn't usable
            icon.Hide()
            return
        end

        -- GetItemInfoInstant resolves the icon synchronously from the static item
        -- record (no async load, no allocated item link/name) — the same instant
        -- call the potion / healthstone trackers already use for their icons.
        local iconId = cachedIconId
        if not iconId then
            iconId = select(5, C_Item.GetItemInfoInstant(itemId))
            if not iconId then
                icon.Hide()
                return
            end
            cachedIconId = iconId
        end

        icon.SetIcon(iconId)
        icon.ApplySize()
        icon.Show()

        -- Green "active" timer, in priority order:
        --   1) the LIVE aura, but only when its fields are safe to read — out of
        --      combat, OR a never-secret aura (ns.AuraTimerReadable). This gives
        --      the EXACT remaining (and learns the duration), and crucially never
        --      reads a SECRET aura's fields (which would taint the addon). A buff
        --      that IS never-secret therefore gets its exact timer even in combat.
        --   2) the HEURISTIC fallback — in combat, when the buff is hidden/secret:
        --      the recorded use time (NotifyUsed) + the learned/seeded/parsed
        --      duration (ns.GetAuraDuration). Dynamic green in combat, no pre-pot.
        local foundBuff = false
        local spellId = getCfg("spellId")
        if spellId then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
            if aura and ns.AuraTimerReadable(spellId) then
                foundBuff = true
                ns.LearnAuraDuration(spellId, aura.duration)
                icon.SetTimer(aura.expirationTime, aura.duration, GREEN)
                icon.HideCheck()
            elseif lastUseAt and UnitAffectingCombat("player") then
                -- Aura nil: only fall back to the heuristic IN COMBAT (where the
                -- buff is hidden/secret). Out of combat a nil aura means the buff
                -- is genuinely gone — expired OR manually cancelled — so we let
                -- the green disappear instead of trusting the use-time window.
                local dur = ns.GetAuraDuration(spellId)
                if dur and GetTime() < lastUseAt + dur then
                    foundBuff = true
                    icon.SetTimer(lastUseAt + dur, dur, GREEN)
                    icon.HideCheck()
                end
            end
        end

        if not foundBuff then
            local start, duration = C_Item.GetItemCooldown(itemId)
            if start and start > 0 and duration and duration > 0 then
                if not hasCooldown then
                    hasCooldown = true
                end
                lastExpiry = start + duration
                icon.SetTimer(start + duration, duration)
                icon.HideCheck()
            elseif duration and duration > 0 then
                -- start == 0 with a duration = an unstarted / not-yet-populated
                -- cooldown (typically mid loading screen). Indeterminate: keep
                -- the previous state and timer. Recording start+duration here
                -- would store a tiny past value and falsely "complete" next tick.
            else
                if hasCooldown then
                    hasCooldown = false
                    -- Real "ready" only if the cooldown actually reached its
                    -- recorded end AND we're not in the post-load settle window.
                    -- A loading screen / instance reset can report the CD as gone
                    -- before its real expiry (leaving a follower dungeon) — that's
                    -- a stale read, not a completion, so stay silent.
                    local completed = lastExpiry and (GetTime() >= lastExpiry - ns.READY_EPSILON)
                    if completed and not ns.RecentlyZoned() then
                        if config.onReady then config.onReady() end
                        icon.ClearTimer()
                        icon.BlinkCheck()  -- flash once, then auto-hide
                    else
                        icon.ClearTimer()
                        icon.HideCheck()
                    end
                else
                    icon.ClearTimer()
                end
            end
        end
    end

    -- Called by the owning module when it detects this item's use spell was cast
    -- (it already watches UNIT_SPELLCAST_SUCCEEDED for the use sound). Starts the
    -- in-combat heuristic green timer from the actual use moment.
    function tracker.NotifyUsed() lastUseAt = GetTime() end

    function tracker.ApplyPosition() icon.ApplyPosition() end
    function tracker.ApplyFont()     icon.ApplyFont()     end
    function tracker.ApplySize()     icon.ApplySize()     end
    function tracker.ApplyBorder()   icon.ApplyBorder()   end
    function tracker.SetUnlocked(v)  icon.SetUnlocked(v)  end
    function tracker.IsUnlocked()    return icon.IsUnlocked() end
    function tracker.GetFrame()      return icon.GetFrame()   end

    tracker.icon = icon
    return tracker
end