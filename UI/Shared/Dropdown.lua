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

    local toggleBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    toggleBtn:SetSize(width, 22)
    toggleBtn:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
    toggleBtn:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    toggleBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    toggleBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    toggleBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    end)
    toggleBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
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
        arrowTex:SetSize(14, 14)
        arrowTex:SetPoint("RIGHT", toggleBtn, "RIGHT", -4, 0)
        arrowTex:SetTexture(UNBUNK_ICON_DROPDOWN_ARROW)
    end

    -- ── Drop frame ────────────────────────────────────────────────────────────

    local dropFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dropFrame:SetSize(width, itemHeight * visibleItems)
    dropFrame:SetFrameStrata("TOOLTIP")
    dropFrame:SetClipsChildren(true)
    dropFrame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dropFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    dropFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
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
            btn.label:SetText(name)

            if name == currentKey then
                btn.label:SetTextColor(1, 0.82, 0, 1)
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
            local left   = toggleBtn:GetLeft()
            local bottom = toggleBtn:GetBottom()
            dropFrame:ClearAllPoints()
            dropFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                left,
                bottom - 2 - UIParent:GetBottom()
            )
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
    return result
end