-- UI/Shared/ScrollBar.lua
-- Reusable scrollbar widget.
--
-- Usage:
--   local sb = ns.ui.CreateScrollBar({
--       parent      = someFrame,
--       scrollFrame = myScrollFrame,
--       itemHeight  = 20,
--       visibleItems = 10,
--       getListSize = function() return #myList end,
--   })
--   sb.track   -- track frame
--   sb.thumb   -- thumb button
--   sb.Update() -- force a recompute

local _, ns = ...
ns.ui = ns.ui or {}

function ns.ui.CreateScrollBar(config)
    local parent       = config.parent
    local scrollFrame  = config.scrollFrame
    local itemHeight   = config.itemHeight   or 20
    local visibleItems = config.visibleItems or 10
    local getListSize  = config.getListSize

    local result = {}

    -- ── Track ─────────────────────────────────────────────────────────────────

    local track = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    track:SetWidth(8)
    track:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    track:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    track:Hide()
    result.track = track

    -- ── Thumb ─────────────────────────────────────────────────────────────────

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8)
    thumb:SetHeight(8)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    result.thumb = thumb

    thumb:EnableMouse(true)
    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local startY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local startScroll = scrollFrame:GetVerticalScroll()

        thumb:SetScript("OnUpdate", function()
            local trackH    = track:GetHeight()
            local thumbH    = thumb:GetHeight()
            local maxOffset = trackH - thumbH
            local maxScroll = scrollFrame:GetVerticalScrollRange()
            local currentY  = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local delta     = startY - currentY
            local newScroll = math.max(0, math.min(maxScroll, startScroll + (delta / maxOffset) * maxScroll))
            scrollFrame:SetVerticalScroll(newScroll)
            -- Update the thumb position directly, without calling sb_Update.
            if maxScroll > 0 then
                local ratio     = newScroll / maxScroll
                local maxOff    = trackH - thumbH
                thumb:ClearAllPoints()
                thumb:SetPoint("TOP", track, "TOP", 0, -(ratio * maxOff))
            end
        end)
    end)

    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- If the thumb is hidden mid-drag (list collapses / panel closes) OnMouseUp
    -- never fires, so clear the drag OnUpdate here too — else it dangles.
    thumb:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- ── Update ────────────────────────────────────────────────────────────────

    local function sb_Update()
        local max = scrollFrame:GetVerticalScrollRange()
        if max <= 0 then
            track:Hide()
            return
        end
        track:Show()
        local listSize = getListSize and getListSize() or 1
        local ratio    = scrollFrame:GetVerticalScroll() / max
        local trackH   = track:GetHeight()
        local thumbH   = math.max(12, math.min(40, trackH * (itemHeight * visibleItems / (itemHeight * listSize))))
        local maxOffset = trackH - thumbH
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(ratio * maxOffset))
    end
    result.Update = sb_Update

    -- ── Scroll on click ───────────────────────────────────────────────────────

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local _, trackY = track:GetCenter()
        local _, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cursorY = cursorY / scale
        local trackH = track:GetHeight()
        local thumbH = thumb:GetHeight()
        local maxOffset = trackH - thumbH
        local ratio = math.max(0, math.min(1, (trackY + trackH/2 - cursorY) / maxOffset))
        local maxScroll = scrollFrame:GetVerticalScrollRange()
        scrollFrame:SetVerticalScroll(ratio * maxScroll)
        sb_Update()
    end)

    -- ── Hook scroll events ────────────────────────────────────────────────────

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        self:SetVerticalScroll(offset)
        sb_Update()
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local max     = self:GetVerticalScrollRange()
        local new     = math.max(0, math.min(max, current - delta * itemHeight * 2))
        self:SetVerticalScroll(new)
        sb_Update()
    end)

    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0.1, function()
            sb_Update()
        end)
    end)

    return result
end