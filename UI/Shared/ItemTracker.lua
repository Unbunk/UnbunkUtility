-- UI/Shared/ItemTracker.lua
-- Reusable item tracker widget (potion, trinket, etc.)
--
-- Usage:
--   local tracker = Unbunk_CreateItemTracker({
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

function Unbunk_CreateItemTracker(config)
    local frameName  = config.frameName
    local getCfg     = config.getCfg
    local getItemId  = config.getItemId
    local hasItem    = config.hasItem
    local onDragStop = config.onDragStop

    local tracker    = {}
    local hasCooldown = false
    local hadItem     = false

    local icon = Unbunk_CreateTimerIcon({
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
            hadItem = false
            return
        end

        -- Skip items that have no spell (not usable).
        local spellName = itemId and C_Item.GetItemSpell and select(1, C_Item.GetItemSpell(itemId))
        if not spellName then
            icon.Hide()
            return
        end

        local _, _, _, _, _, _, _, _, _, iconId = GetItemInfo(itemId)
        if not iconId then
            C_Item.RequestLoadItemDataByID(itemId)
            icon.Hide()
            return
        end

        icon.SetIcon(iconId)
        icon.ApplySize()
        icon.Show()
        hadItem = true

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
            if start and duration and duration > 0 then
                if not hasCooldown then
                    hasCooldown = true
                end
                icon.SetTimer(start + duration, duration)
                icon.HideCheck()
            else
                if hasCooldown then
                    hasCooldown = false
                    if config.onReady then config.onReady() end
                    icon.ClearTimer()
                    icon.BlinkCheck()  -- flash once, then auto-hide
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