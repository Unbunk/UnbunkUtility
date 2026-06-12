-- UI/Dropdown.lua
-- Generic reusable dropdown widget.
--
-- Usage:
--   local dd = ns.ui.CreateDropdown({
--       parent       = panel,
--       anchorFrame  = someFrame,    -- frame the dropdown opens below
--       width        = 240,
--       itemHeight   = 20,
--       visibleItems = 10,
--       getList      = function() return { "Item1", "Item2" } end,
--       getCurrentKey = function() return MyModuleCfg_Get("myKey") end,
--       onSelect     = function(name) ... end,
--   })
--   dd.selectedText  -- FontString on the toggle button
--   dd.bottomY       -- Y just below the widget (anchorFrame:GetBottom() - 40)

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

function ns.ui.CreateDropdown(config)
    local parent       = config.parent
    local anchorFrame  = config.anchorFrame
    local width        = config.width        or 240
    local itemHeight   = config.itemHeight   or 20
    local visibleItems = config.visibleItems or 10
    local getList      = config.getList       or function() return {} end
    local getCurrentKey = config.getCurrentKey or function() return nil end
    local onSelect     = config.onSelect       or function() end

    local result = {}

    -- ── Toggle button ─────────────────────────────────────────────────────────

    local toggleBtn = CreateFrame("Button", nil, parent)
    toggleBtn:SetSize(width, 22)
    toggleBtn:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)

    -- Borderless dark fill with sharp corners, matching the checkbox style.
    local toggleFill = toggleBtn:CreateTexture(nil, "BACKGROUND")
    toggleFill:SetAllPoints(toggleBtn)
    toggleFill:SetColorTexture(0.12, 0.12, 0.12, 0.95)

    toggleBtn:SetScript("OnEnter", function()
        toggleFill:SetColorTexture(0.20, 0.20, 0.20, 0.95)
    end)
    toggleBtn:SetScript("OnLeave", function()
        toggleFill:SetColorTexture(0.12, 0.12, 0.12, 0.95)
    end)

    local selectedText = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedText:SetPoint("LEFT", 6, 0)
    selectedText:SetPoint("RIGHT", -22, 0)
    selectedText:SetJustifyH("LEFT")
    selectedText:SetText(L["(select...)"])
    result.selectedText = selectedText
    result.toggleBtn    = toggleBtn

    -- Initialise the toggle label to the current value. Callers used to have to
    -- do this by hand (dd.selectedText:SetText(...)); the ones that forgot left
    -- "(select...)" showing on an already-set value. In every real caller the
    -- key returned by getCurrentKey is also the display string.
    local function SetCurrent(key)
        selectedText:SetText(key ~= nil and key or L["(select...)"])
    end
    result.SetCurrent = SetCurrent

    do
        local initialKey = getCurrentKey()
        if initialKey ~= nil then selectedText:SetText(initialKey) end
    end

    if UNBUNK_ICON_DROPDOWN_ARROW then
        local arrowTex = toggleBtn:CreateTexture(nil, "OVERLAY")
        arrowTex:SetSize(8, 8)
        arrowTex:SetPoint("RIGHT", toggleBtn, "RIGHT", -6, 0)
        arrowTex:SetTexture(UNBUNK_ICON_DROPDOWN_ARROW)
    end

    -- ── Drop frame ────────────────────────────────────────────────────────────

    local dropFrame = CreateFrame("Frame", nil, UIParent)
    dropFrame:SetSize(width, itemHeight * visibleItems)
    dropFrame:SetFrameStrata("TOOLTIP")
    dropFrame:SetClipsChildren(true)

    -- Borderless dark fill with sharp corners, matching the checkbox style.
    local dropFill = dropFrame:CreateTexture(nil, "BACKGROUND")
    dropFill:SetAllPoints(dropFrame)
    dropFill:SetColorTexture(0.10, 0.10, 0.10, 0.98)
    dropFrame:Hide()
    dropFrame:EnableMouse(false)

    -- ── Scroll frame ──────────────────────────────────────────────────────────

    local scrollFrame = CreateFrame("ScrollFrame", nil, dropFrame)
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -18, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(width - 22)
    scrollFrame:SetScrollChild(scrollChild)

    -- ── Scrollbar ─────────────────────────────────────────────────────────────

    local sb = ns.ui.CreateScrollBar({
        parent       = dropFrame,
        scrollFrame  = scrollFrame,
        itemHeight   = itemHeight,
        visibleItems = visibleItems,
        getListSize  = function() return #getList() end,
    })
    sb.track:SetPoint("TOPRIGHT", dropFrame, "TOPRIGHT", -3, -4)
    sb.track:SetPoint("BOTTOMRIGHT", dropFrame, "BOTTOMRIGHT", -3, 4)

    local scrollTrack = sb.track
    local scrollThumb = sb.thumb
    local UpdateScrollBar = sb.Update

    -- ── List items ────────────────────────────────────────────────────────────

    local buttons = {}

    local function RefreshList()
        local list       = getList()
        local currentKey = getCurrentKey()
        local level      = dropFrame:GetFrameLevel()

        -- Auto-size the menu to the actual item count (capped at visibleItems) so a
        -- short list (e.g. Anchor to / Row) shows a short menu, not a tall empty one.
        -- +8 covers the scroll frame's 4px top/bottom insets.
        local shownRows = math.max(1, math.min(#list, visibleItems))
        dropFrame:SetHeight(shownRows * itemHeight + 8)

        scrollChild:SetHeight(itemHeight * #list)

        for i, name in ipairs(list) do
            local btn = buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, scrollChild)
                btn:SetHeight(itemHeight)
                btn:SetPoint("TOPLEFT", 0, -(i - 1) * itemHeight)
                btn:SetWidth(width - 22)

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.1)
                btn:SetHighlightTexture(hl)

                local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                lbl:SetPoint("LEFT", 4, 0)
                lbl:SetPoint("RIGHT", -4, 0)
                lbl:SetJustifyH("LEFT")
                btn.label = lbl

                btn:SetScript("OnClick", function(self)
                    onSelect(self.name)
                    selectedText:SetText(self.name)
                    dropFrame:Hide()
                    RefreshList()
                end)

                buttons[i] = btn
            end

            btn.name = name
            btn:SetFrameLevel(level + 2)
            btn:Show()   -- re-show a pooled button that was hidden on a shorter pass
            btn.label:SetText(name)

            if name == currentKey then
                btn.label:SetTextColor(0.20, 0.55, 1.0, 1)   -- selected item: brand blue
            else
                btn.label:SetTextColor(1, 1, 1, 1)
            end
        end

        -- Hide the surplus pooled buttons.
        for i = #list + 1, #buttons do
            buttons[i]:Hide()
        end

        UpdateScrollBar()
    end

    -- ── Toggle logic ──────────────────────────────────────────────────────────

    toggleBtn:SetScript("OnClick", function()
        if dropFrame:IsShown() then
            dropFrame:Hide()
        else
            -- Anchor the list to the toggle button itself (not a one-shot snapshot of
            -- its screen position) so it stays glued just below the button. The drop
            -- frame is still a UIParent child on the TOOLTIP strata, so it renders on
            -- top and is never clipped by the scroll frame — but because it now tracks
            -- the button, scrolling the content moves the open list with it instead of
            -- leaving it stranded where it first opened.
            dropFrame:ClearAllPoints()
            dropFrame:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -2)
            dropFrame:SetFrameLevel(1)
            scrollTrack:SetFrameLevel(2)
            scrollThumb:SetFrameLevel(3)
            RefreshList()
            dropFrame:Show()
            dropFrame:EnableMouse(true)
            scrollFrame:EnableMouse(true)
            scrollChild:EnableMouse(true)

            -- Scroll to the current selection. Deferred one frame so the
            -- ScrollFrame has had a layout pass and GetVerticalScrollRange
            -- returns the real range (it is still 0 in the same frame the
            -- scrollChild height changes / the frame is first shown).
            C_Timer.After(0, function()
                if not dropFrame:IsShown() then return end
                local list       = getList()
                local currentKey = getCurrentKey()
                for i, name in ipairs(list) do
                    if name == currentKey then
                        local maxScroll = scrollFrame:GetVerticalScrollRange()
                        local target    = math.max(0, math.min(maxScroll, (i - 1) * itemHeight))
                        scrollFrame:SetVerticalScroll(target)
                        UpdateScrollBar()
                        break
                    end
                end
            end)
        end
    end)

    dropFrame:SetScript("OnHide", function()
        sb.track:Hide()
        dropFrame:EnableMouse(false)
        scrollFrame:EnableMouse(false)
        scrollChild:EnableMouse(false)
    end)

    parent:HookScript("OnHide", function()
        dropFrame:Hide()
    end)

    result.RefreshList = RefreshList
    -- Exposed so BuildMenu.Rebuild can reclaim it: the drop frame is parented to
    -- UIParent (to float on the TOOLTIP strata, escaping scroll-frame clipping), so
    -- it is NOT torn down when its host frame is orphaned — BuildMenu collects it
    -- into its auxFrames list and Hide+SetParent(nil)s it on Rebuild.
    result.dropFrame = dropFrame
    return result
end