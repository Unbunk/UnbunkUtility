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

-- How many 0.5s ApplyVisuals ticks GetItemSpell may stay nil (while the item's data IS cached) before we
-- commit the "passive / no on-use" verdict. The item header can cache before the on-use spell field settles
-- at login/zone, so committing on the first nil would hide a REAL on-use trinket for the whole session. ~3s.
local SPELL_GIVEUP_TICKS = 6

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
    -- Consecutive ticks GetItemSpell has returned nil while the item data IS cached; drives the bounded
    -- retry before cachedSpellName is committed to the false "passive" verdict. Reset on an itemId change.
    local spellNilTicks = 0

    -- Last-applied visual state, so the steady-state 0.5s tick is a no-op when
    -- nothing changed (SetIcon/Show/SetTimer all push work to the engine/Cooldown
    -- frame even when the value is identical). One CreateItemTracker closure per
    -- tracker (never re-entrant) → plain upvalues are safe.
    local appliedIconId  = nil   -- last id passed to icon.SetIcon
    local tExpiry, tDuration, tColor = nil, nil, nil  -- last SetTimer args

    -- The TimerIcon is created further down (it needs getCfg / cdmEligible defined first), but the
    -- cache helpers just below close over it. Forward-declare the local here so they capture THIS
    -- upvalue instead of the nil GLOBAL `icon` (they're only ever CALLED after the assignment below).
    local icon

    -- SetTimer is a no-op when (expiry, duration, color) match the last applied
    -- timer; identical args just re-push the same SetCooldown to the engine.
    local function SetTimerCached(expiry, duration, color)
        if expiry == tExpiry and duration == tDuration and color == tColor then return end
        tExpiry, tDuration, tColor = expiry, duration, color
        icon.SetTimer(expiry, duration, color)
    end
    -- Any state that ends/changes the timer outside SetTimerCached (ClearTimer,
    -- the direct-driven healthstone path) must forget the cached args so a later
    -- identical SetTimer re-applies instead of being skipped.
    local function InvalidateTimerCache() tExpiry, tDuration, tColor = nil, nil, nil end
    tracker.InvalidateTimerCache = InvalidateTimerCache
    -- Clear + forget the cached args together, so a later identical SetTimer
    -- (e.g. the same cooldown re-appearing) re-applies instead of being skipped.
    local function ClearTimerCached() InvalidateTimerCache(); icon.ClearTimer() end

    -- Show/Hide only when the REAL frame visibility differs (reading the actual
    -- frame state, not a believed flag, so external direct Show/Hide from the
    -- owning module — healthstone's direct-draw path, SetUnlocked, RunTest — can't
    -- leave a stale cache that swallows a needed flip).
    local function ShowCached()
        if not icon.GetFrame():IsShown() then icon.Show() end
    end
    local function HideCached()
        if icon.GetFrame():IsShown() then icon.Hide() end
    end

    icon = ns.ui.CreateTimerIcon({
        name    = frameName,
        getCfg  = getCfg,
        setCfg  = config.setCfg,   -- optional: forwarded to the CDM descriptor (cdmAtEnd on drag)
        getItemId = getItemId,     -- lets the keybind resolver find the bar binding (bound as an ITEM)
        getCount  = config.getCount,  -- optional: authoritative stack/charge count (e.g. healthstone CHARGES)
        minStack  = config.minStack,  -- optional: minimum count to DISPLAY (trinkets pass 2 to hide a lone "1")
        -- CDM eligibility: only fold this item into a Cooldown-groups group when it has a usable ON-USE
        -- spell. cachedSpellName (set in ApplyVisuals, anti-churn) is a STRING when usable, `false` for a
        -- passive/stat item, nil while unresolved/empty — so a passive or empty trinket slot is excluded
        -- from the group list (no more "?" placeholder). Potions/healthstones are always on-use → eligible.
        cdmEligible = function() return type(cachedSpellName) == "string" end,
        onDragStop = function(x, y)
            if onDragStop then onDragStop(x, y) end
        end,
    })

    icon.onExpire = function() end

    function tracker.ApplyVisuals()
        if not getCfg("enabled") then
            HideCached()
            return
        end

        local itemId = getItemId()
        -- "Show at 0 stacks" keeps the icon visible even with none in bags, as long
        -- as an item id is known to draw (the favourite / configured / default one).
        local itemExists = itemId and (getCfg("showAtZero") or hasItem(itemId))

        if not itemExists or not getCfg("showIcon") then
            HideCached()
            return
        end

        -- The usable-spell and the icon are constant per itemId: resolve each once
        -- and cache, so the steady-state tick allocates nothing here. Reset on change.
        if itemId ~= cachedItemId then
            cachedItemId, cachedIconId, cachedSpellName, spellNilTicks = itemId, nil, nil, 0
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
                -- Data is cached but GetItemSpell returned nil — EITHER a genuinely passive item OR a
                -- transient login/zone window where the item header cached before its on-use spell field
                -- settled (IsItemDataCachedByID flips true first). Committing `false` on the first nil would
                -- mis-verdict a REAL on-use trinket as passive and hide it for the WHOLE session (the verdict
                -- only resets on an itemId change). So retry a few ticks; commit the passive verdict only once
                -- the spell has stayed nil for SPELL_GIVEUP_TICKS. There is NO RequestLoadItemDataByID in this
                -- branch, so the retry never re-arms the GET_ITEM_INFO_RECEIVED → CooldownViewer relayout churn
                -- the sentinel was added to stop.
                spellNilTicks = spellNilTicks + 1
                if spellNilTicks < SPELL_GIVEUP_TICKS then
                    HideCached()
                    return
                end
                cachedSpellName = false        -- stayed nil while loaded → genuinely no on-use, stop retrying
            else
                C_Item.RequestLoadItemDataByID(itemId)  -- not loaded yet → retry next tick
                HideCached()
                return
            end
        end
        if not cachedSpellName then             -- false sentinel: item isn't usable
            HideCached()
            return
        end

        -- GetItemInfoInstant resolves the icon synchronously from the static item
        -- record (no async load, no allocated item link/name) — the same instant
        -- call the potion / healthstone trackers already use for their icons.
        local iconId = cachedIconId
        if not iconId then
            iconId = select(5, C_Item.GetItemInfoInstant(itemId))
            if not iconId then
                HideCached()
                return
            end
            cachedIconId = iconId
        end

        if iconId ~= appliedIconId then
            icon.SetIcon(iconId)
            appliedIconId = iconId
        end
        local wasHidden = not icon.GetFrame():IsShown()
        icon.ApplySize()
        ShowCached()
        -- An item tracker becomes group-ELIGIBLE only once its on-use spell resolves, so the FIRST time it
        -- shows it may not be in the engine's layout snapshot yet — it would then render at its un-sized 64px
        -- birth size instead of the group's slot size. Kick one relayout on the hidden->shown transition (in
        -- the CDM) so the engine folds it in and sizes it. Deferred so we don't relayout mid-tick.
        if wasHidden and icon.CDMActive and icon.CDMActive() and ns.CDMAnchor and ns.CDMAnchor.RefreshAll then
            C_Timer.After(0, function() ns.CDMAnchor.RefreshAll(true) end)
        end

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
                SetTimerCached(aura.expirationTime, aura.duration, GREEN)
                icon.HideCheck()
            elseif lastUseAt and UnitAffectingCombat("player") then
                -- Aura nil: only fall back to the heuristic IN COMBAT (where the
                -- buff is hidden/secret). Out of combat a nil aura means the buff
                -- is genuinely gone — expired OR manually cancelled — so we let
                -- the green disappear instead of trusting the use-time window.
                local dur = ns.GetAuraDuration(spellId)
                if dur and GetTime() < lastUseAt + dur then
                    foundBuff = true
                    SetTimerCached(lastUseAt + dur, dur, GREEN)
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
                SetTimerCached(start + duration, duration)
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
                        ClearTimerCached()
                        icon.BlinkCheck()  -- flash once, then auto-hide
                    else
                        ClearTimerCached()
                        icon.HideCheck()
                    end
                else
                    ClearTimerCached()
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