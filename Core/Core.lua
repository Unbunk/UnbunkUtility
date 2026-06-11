-- Core/Core.lua
-- Main UnbunkUtility window with navigation bar.

local _, ns = ...

-- Use `or {}` so any module that loaded before Core (and stashed callbacks
-- on the table) keeps its data; previously we overwrote the table outright.
UnbunkUtility = UnbunkUtility or {}
local registeredModules = {}
UnbunkUtility.registeredModules = registeredModules
local window
local navbar
local contentArea
local scrollFrame
local activeTab = nil
local tabButtons = {}

function UnbunkUtility.RegisterModule(name, icon, createFn)
    table.insert(registeredModules, {
        name     = name,
        icon     = icon,
        createFn = createFn,
        frame    = nil,
    })
end

-- Compute the actual vertical extent of a module's content by looking at
-- the bottom edge of its deepest element. Lets us size contentArea to fit
-- the active module instead of leaving it at a fixed 1000px ceiling.
-- We walk both child frames (recursing one level so content nested inside a
-- child frame is measured) and the frame's own regions (FontStrings/Textures
-- created directly on it are regions, not children, and were being missed).
local function ComputeModuleHeight(modFrame)
    local pTop = modFrame:GetTop()
    if not pTop then return nil end
    local maxDepth = 0

    local function consider(element)
        if not element then return end
        local bottom = element.GetBottom and element:GetBottom()
        if bottom then
            local depth = pTop - bottom
            if depth > maxDepth then maxDepth = depth end
        end
    end

    -- Walk the whole subtree (every child frame + every frame's own regions) so
    -- deeply-nested content — e.g. controls inside a CollapsibleSection's
    -- content frame — is measured too, not just the first two levels. Depth-
    -- capped as a cheap guard against a pathological frame tree.
    local function walk(frame, depth)
        if depth > 8 then return end
        for i = 1, frame:GetNumChildren() do
            local child = select(i, frame:GetChildren())
            if child then
                -- Skip BuildMenu's full-bleed content wrapper (it SetAllPoints its
                -- parent, so its bottom is the stale contentArea bottom and would
                -- peg every tab to the tallest tab's height). Still recurse so the
                -- real stacked widgets inside it ARE measured.
                if not child._uuMenuContent then consider(child) end
                walk(child, depth + 1)
            end
        end
        for i = 1, frame:GetNumRegions() do
            consider(select(i, frame:GetRegions()))
        end
    end

    walk(modFrame, 0)
    return maxDepth
end

local scrollBar  -- forward declaration; set in CreateMainWindow.

local function ResizeContentArea(modFrame)
    if not contentArea or not scrollFrame then return end
    -- Re-sync width to the real viewport: CreateMainWindow ran while the window was
    -- hidden (scrollFrame:GetWidth()==0) and fell back to 550; once laid out the
    -- viewport is a few px wider, so track it here (this runs deferred, post-layout).
    local vw = scrollFrame:GetWidth() or 0
    if vw > 0 and math.abs((contentArea:GetWidth() or 0) - vw) > 0.5 then
        contentArea:SetWidth(vw)
    end
    local viewport = scrollFrame:GetHeight() or 0
    local needed   = ComputeModuleHeight(modFrame) or 0
    -- Only make the content scrollable when it GENUINELY overflows the viewport (the +8
    -- is bottom padding, applied only when actually scrolling — adding it unconditionally
    -- used to push tabs that fit within ~8px of the viewport just over the edge).
    -- When it FITS, size contentArea to the content (NOT the viewport): a content frame
    -- exactly == the viewport can read back a sub-pixel scroll range, which the mouse-wheel
    -- handler's sb_Update would treat as "scrollable" and re-show the track. Sizing it to
    -- `needed` (strictly < viewport) keeps GetVerticalScrollRange a hard 0, so the wheel
    -- can never bring the track back on a tab that fits.
    local overflow = needed > viewport
    contentArea:SetHeight(overflow and (needed + 8) or needed)
    -- Drive the track's VISIBILITY from the overflow we just measured, NOT from
    -- scrollFrame:GetVerticalScrollRange(): that range only refreshes a frame (or more)
    -- after SetHeight, so reading it here (even deferred) shows/hides the track based on
    -- the previous tab. The show/hide decision is immediate and correct; we still defer
    -- sb.Update to size + place the thumb once the range catches up.
    if scrollBar and scrollBar.track then
        if overflow then
            scrollBar.track:Show()
            if scrollBar.Update then C_Timer.After(0, scrollBar.Update) end
        else
            scrollBar.track:Hide()
        end
    end
end

local function ShowModule(index)
    local mod = registeredModules[index]
    if not mod then return end

    for _, m in ipairs(registeredModules) do
        if m.frame then m.frame:Hide() end
    end

    if not mod.frame then
        mod.frame = CreateFrame("Frame", nil, contentArea)
        mod.frame:SetAllPoints(contentArea)
        -- Capture the BuildMenu result so ns.profiles.ReloadAll can reclaim its
        -- UIParent-parented dropdown drop-frames (auxFrames) on a profile switch.
        mod.menu = mod.createFn(mod.frame)
    end

    mod.frame:Show()
    activeTab = index

    -- Reset scroll to the top whenever the user switches tabs.
    if scrollFrame then scrollFrame:SetVerticalScroll(0) end

    -- Resize contentArea to fit the new module. Deferred a frame so child
    -- positions are realized before we measure them.
    C_Timer.After(0, function()
        if activeTab == index and mod.frame:IsShown() then
            ResizeContentArea(mod.frame)
        end
    end)

    for i, btn in ipairs(tabButtons) do
        if i == index then
            btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            btn:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
        else
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end
end

-- Re-measure the active module's content height and resize the scroll area.
-- Called by BuildMenu.Rebuild after a reactive panel relayout (e.g. toggling the
-- "Include in cdm" checkbox swaps the CDM controls for the position editor, which
-- changes the panel height). Deferred a frame so the rebuilt frames have realized
-- positions before we measure them.
function ns.ResizeActiveModule()
    local idx = activeTab
    if not idx then return end
    C_Timer.After(0, function()
        if activeTab ~= idx then return end
        local mod = registeredModules[idx]
        if mod and mod.frame and mod.frame:IsShown() then
            ResizeContentArea(mod.frame)
        end
    end)
end

function UnbunkUtility.ShowActiveModule()
    if activeTab then
        ShowModule(activeTab)
    end
end

-- Rebuild the active module's config menu, re-evaluating every `when`/`shown`
-- predicate (Refresh alone only re-syncs widget values). Used when an external
-- state change must swap which controls a panel shows while it is already open —
-- e.g. toggling the game's Cooldown Manager greys the "Include in cdm" checkbox
-- and swaps the CDM controls for the free position editor. No-op if nothing is
-- open or the active module has no rebuildable menu.
function ns.RebuildActiveModule()
    if not activeTab then return end
    local mod = registeredModules[activeTab]
    if mod and mod.frame and mod.frame:IsShown() and mod.menu and mod.menu.Rebuild then
        mod.menu.Rebuild()
    end
end

local function BuildNavbar()
    for _, btn in ipairs(tabButtons) do btn:Hide() end
    tabButtons = {}

    local TAB_WIDTH   = 130
    local TAB_HEIGHT  = 28
    local TAB_GAP     = 4
    local TABS_PER_ROW = 4
    local navbarHeight = 0

    for i, mod in ipairs(registeredModules) do
        local row = math.floor((i - 1) / TABS_PER_ROW)
        local col = (i - 1) % TABS_PER_ROW
        local x   = col * (TAB_WIDTH + TAB_GAP)
        local y   = -(row * (TAB_HEIGHT + TAB_GAP))

        local btn = CreateFrame("Button", nil, navbar, "BackdropTemplate")
        btn:SetSize(TAB_WIDTH, TAB_HEIGHT)
        btn:SetPoint("TOPLEFT", navbar, "TOPLEFT", x, y)
        btn:SetBackdrop({
            bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

        btn:SetScript("OnEnter", function(self)
            if activeTab ~= i then
                self:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if activeTab ~= i then
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        if mod.icon then
            lbl:SetText("|T" .. mod.icon .. ":14:14:0:0|t " .. mod.name)
        else
            lbl:SetText(mod.name)
        end

        btn:SetScript("OnClick", function() ShowModule(i) end)
        tabButtons[i] = btn
    end

    -- Computed once after the loop (was recomputed every iteration).
    local rows = math.ceil(#registeredModules / TABS_PER_ROW)
    navbarHeight = rows * (TAB_HEIGHT + TAB_GAP)
    navbar:SetHeight(navbarHeight)
end

local function CreateMainWindow()
    window = CreateFrame("Frame", "UnbunkUtilityWindow", UIParent, "BackdropTemplate")
    window:SetSize(600, 800)
    window:SetPoint("CENTER")
    -- DIALOG sits above HIGH (where our tracker icons are) so the config
    -- window is always on top of them when opened.
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    window:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    window:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    window:Hide()

    local titleBar = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleBar:SetPoint("TOP", 0, -14)
    titleBar:SetText("UnbunkUtility")

    local closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() window:Hide() end)

    table.insert(UISpecialFrames, "UnbunkUtilityWindow")    

    navbar = CreateFrame("Frame", nil, window)
    navbar:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -40)
    navbar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -40)
    navbar:SetHeight(64) -- updated by BuildNavbar once modules are known

    local sep = window:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    sep:SetPoint("TOPLEFT", navbar, "BOTTOMLEFT", 0, -4)
    sep:SetPoint("TOPRIGHT", navbar, "BOTTOMRIGHT", 0, -4)
    sep:SetHeight(1)

    scrollFrame = CreateFrame("ScrollFrame", nil, window)
    scrollFrame:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -28, 16)

    contentArea = CreateFrame("Frame", nil, scrollFrame)
    -- A both-sides-anchored ScrollFrame has not had a layout pass yet at
    -- PLAYER_LOGIN (the window is still Hide()), so GetWidth() returns 0 — which
    -- is truthy, so a plain `or 550` fallback never triggers. Guard explicitly.
    local w = scrollFrame:GetWidth()
    if not w or w <= 0 then w = 550 end
    contentArea:SetWidth(w)
    contentArea:SetHeight(1000)
    scrollFrame:SetScrollChild(contentArea)

    scrollFrame:EnableMouseWheel(true)
    -- NOTE: the OnMouseWheel handler + OnVerticalScroll are installed by
    -- ns.ui.CreateScrollBar below (it owns the scroll step); don't set one here or
    -- it would just be overwritten (last-write-wins).

    -- Scrollbar — the thumb size is proportional to visibleItems / listSize.
    -- We want it to match (viewport / contentArea), so derive listSize from
    -- the actual content height instead of hard-coding 20.
    local SB_ITEM_HEIGHT = 30
    local SB_VISIBLE     = 10
    local sb = ns.ui.CreateScrollBar({
        parent       = window,
        scrollFrame  = scrollFrame,
        itemHeight   = SB_ITEM_HEIGHT,
        visibleItems = SB_VISIBLE,
        getListSize  = function()
            local h = contentArea and contentArea:GetHeight() or (SB_ITEM_HEIGHT * SB_VISIBLE * 2)
            return math.max(SB_VISIBLE, math.ceil(h / SB_ITEM_HEIGHT))
        end,
    })
    scrollBar = sb
    sb.track:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -110)
    sb.track:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, 16)
    sb.track:Show()

    window:HookScript("OnShow", function()
        C_Timer.After(0.1, function()
            sb.Update()
        end)
    end)
end

function UnbunkUtility.OpenWindow()
    if not window then return end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

local initCore = CreateFrame("Frame")
initCore:RegisterEvent("PLAYER_LOGIN")
initCore:SetScript("OnEvent", function(self)
    CreateMainWindow()
    -- Rebuild navbar after all modules have registered themselves.
    C_Timer.After(0, function()
        BuildNavbar()
        if #registeredModules > 0 then
            ShowModule(1)
        end
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)