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

function ns.ui.CreateItemTracker(config)
    local frameName  = config.frameName
    local getCfg     = config.getCfg
    local getItemId  = config.getItemId
    local hasItem    = config.hasItem
    local onDragStop = config.onDragStop

    local tracker    = {}
    local hasCooldown = false
    local lastExpiry  = nil  -- GetTime() at which the tracked cooldown ends

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
        local itemExists = itemId and hasItem(itemId)

        if not itemExists or not getCfg("showIcon") then
            icon.Hide()
            return
        end

        -- Skip items that have no spell (not usable).
        local spellName = itemId and C_Item.GetItemSpell and select(1, C_Item.GetItemSpell(itemId))
        if not spellName then
            -- Spell data is async; request a load so the next refresh can resolve
            -- it even if nothing else preloaded the item (mirrors the iconId branch).
            C_Item.RequestLoadItemDataByID(itemId)
            icon.Hide()
            return
        end

        local _, _, _, _, _, _, _, _, _, iconId = C_Item.GetItemInfo(itemId)
        if not iconId then
            C_Item.RequestLoadItemDataByID(itemId)
            icon.Hide()
            return
        end

        icon.SetIcon(iconId)
        icon.ApplySize()
        icon.Show()

        -- Check buff actif d'abord
        local foundBuff = false
        local spellId = getCfg("spellId")
        if spellId then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
            if aura then
                foundBuff = true
                icon.SetTimer(aura.expirationTime, aura.duration, { r=0, g=1, b=0 })
                icon.HideCheck()
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

    function tracker.ApplyPosition() icon.ApplyPosition() end
    function tracker.ApplyFont()     icon.ApplyFont()     end
    function tracker.ApplySize()     icon.ApplySize()     end
    function tracker.SetUnlocked(v)  icon.SetUnlocked(v)  end
    function tracker.IsUnlocked()    return icon.IsUnlocked() end
    function tracker.GetFrame()      return icon.GetFrame()   end

    tracker.icon = icon
    return tracker
end