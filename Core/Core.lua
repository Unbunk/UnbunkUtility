-- Core/Core.lua
-- Main UnbunkUtility window: a top row of MAIN tabs + a collapsible LEFT sub-tab
-- menu + a scrollable content area. Each config panel registers a builder under
-- its (localised) name; the NAV_TREE below places those panels into main tabs,
-- categories and sub-tabs. Clicking a main tab opens its default (first) sub-tab.

local ADDON, ns = ...

UnbunkUtility = UnbunkUtility or {}

-- Panel registry: name -> { name, icon, createFn, frame, menu }. Modules call
-- RegisterModule with the SAME localised name the NAV_TREE references.
local panels = {}
UnbunkUtility.panels = panels

function UnbunkUtility.RegisterModule(name, icon, createFn)
    panels[name] = { name = name, icon = icon, createFn = createFn }
end

local window, mainBar, leftMenu, contentArea, scrollFrame, scrollBar
local activeMain          -- index into navTree
local activeSub           -- active panel name
local mainButtons = {}
local menuRows = {}       -- left-menu row frames (rebuilt per main tab)
local collapsed = {}      -- category name -> true when folded (session-persistent)

local BR, BG, BB = 0.20, 0.55, 1.0   -- brand blue

-- ── Footer links ───────────────────────────────────────────────────────────────
local GITHUB_URL     = "https://github.com/Unbunk/UnbunkUtility"
local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/unbunkutility"

-- WoW can't open a browser, so a clicked link pops a small dialog with the URL in a
-- pre-selected EditBox the user copies with Ctrl+C. A custom frame (not a Blizzard
-- StaticPopup) so it matches the addon's square style AND reliably shows the URL —
-- the StaticPopup `data` path stopped populating the edit box after Midnight's popup
-- rework, which is why the link looked empty.
local urlDialog
local function ShowURL(url)
    if not urlDialog then
        local f = CreateFrame("Frame", "UnbunkUtilityURLDialog", UIParent, "BackdropTemplate")
        f:SetSize(440, 118)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        f:Hide()

        local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
        title:SetPoint("TOP", f, "TOP", 0, -14)
        title:SetText("Copy the link (Ctrl+C)")

        -- Selectable EditBox holding the URL, with the inputs' dark sharp fill.
        local eb = CreateFrame("EditBox", nil, f)
        eb:SetSize(400, 24)
        eb:SetPoint("TOP", f, "TOP", 0, -46)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetTextInsets(6, 6, 0, 0)
        local ebFill = eb:CreateTexture(nil, "BACKGROUND")
        ebFill:SetAllPoints(eb)
        ebFill:SetColorTexture(0.12, 0.12, 0.12, 0.95)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnEnterPressed",  function() f:Hide() end)
        -- Auto-close right after the link is copied (Ctrl+C). The client performs the
        -- copy on this keypress, so defer the hide one frame so the clipboard write
        -- finishes before the dialog goes away.
        eb:SetScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0, function() f:Hide() end)
            end
        end)
        -- Effectively read-only: snap back to the URL if edited, so it stays correct.
        eb:SetScript("OnTextChanged", function(self)
            if self.url and self:GetText() ~= self.url then
                self:SetText(self.url)
                self:HighlightText()
            end
        end)
        f.editBox = eb

        local close = ns.ui.CreateButton({ parent = f, label = CLOSE or "Close", width = 110, height = 24 })
        close.frame:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
        close.frame:SetScript("OnClick", function() f:Hide() end)

        urlDialog = f
    end
    local eb = urlDialog.editBox
    eb.url = url
    eb:SetText(url)
    urlDialog:Show()
    urlDialog:Raise()
    eb:SetFocus()
    eb:HighlightText()
end

-- ── Nav tree ──────────────────────────────────────────────────────────────────
-- Built lazily (needs ns.L at runtime). A `panel` entry references a registered
-- panel by name; a `cat` entry is a collapsible grouping (its `subs` are panels).
local function BuildNavTree()
    local L = ns.L
    return {
        { name = L["General Settings"], subs = {
            { panel = L["Addon settings"] },
            { panel = L["Player speed display"] },
            { panel = L["Multi-alert / anti-spam"] },
            { cat = L["Cooldown Manager"], subs = {
                { panel = L["Below player frame"] },
            } },
            { panel = L["Profiles"] },
        } },
        { name = L["Combat Utilities"], subs = {
            { panel = L["Combat settings"] },
            { panel = L["Healer Range"] },
            { panel = L["BRez Tracker"] },
            { cat = L["Death Alerts"], subs = {
                { panel = L["Tank Death Alert"] },
                { panel = L["Healer Death Alert"] },
                { panel = L["DPS Death Alert"] },
            } },
            { cat = L["Item/Spell Trackers"], subs = {
                { panel = L["Trinket Tracker"] },
                { panel = L["Potion Tracker"] },
                { panel = L["Healthstone Tracker"] },
                { panel = L["Racial Tracker"] },
            } },
            { cat = L["Aura Trackers"], subs = {
                { panel = L["BL Tracker"] },
                { panel = L["PI Tracker"] },
            } },
        } },
        { name = L["Extra Utilities"], subs = {
            { panel = L["Death Anim"] },
        } },
        { name = L["Debug Utilities"], subs = {
            { panel = L["Debug"] },
        } },
    }
end
local navTree

-- ── Content height measurement (unchanged) ─────────────────────────────────────
-- Compute the actual vertical extent of a panel by the bottom edge of its deepest
-- element, so contentArea fits the active panel instead of a fixed ceiling.
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

    local function walk(frame, depth)
        if depth > 8 then return end
        for i = 1, frame:GetNumChildren() do
            local child = select(i, frame:GetChildren())
            if child then
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

local function ResizeContentArea(modFrame)
    if not contentArea or not scrollFrame then return end
    local vw = scrollFrame:GetWidth() or 0
    if vw > 0 and math.abs((contentArea:GetWidth() or 0) - vw) > 0.5 then
        contentArea:SetWidth(vw)
    end
    local viewport = scrollFrame:GetHeight() or 0
    local needed   = ComputeModuleHeight(modFrame) or 0
    local overflow = needed > viewport
    contentArea:SetHeight(overflow and (needed + 8) or needed)
    if scrollBar and scrollBar.track then
        if overflow then
            scrollBar.track:Show()
            if scrollBar.Update then C_Timer.After(0, scrollBar.Update) end
        else
            scrollBar.track:Hide()
        end
    end
end

-- ── Sub-tab content ─────────────────────────────────────────────────────────
local function HighlightMenu()
    for _, row in ipairs(menuRows) do
        if row.panelName then
            local on = (row.panelName == activeSub)
            if row.label then row.label:SetTextColor(on and BR or 1, on and BG or 1, on and BB or 1) end
            if row.accent then
                if on then row.accent:Show() else row.accent:Hide() end
            end
        end
    end
end

local function ShowSubTab(name)
    if not name then return end
    for _, p in pairs(panels) do
        if p.frame then p.frame:Hide() end
    end

    local p = panels[name]
    if not p then
        -- Registered panel missing (module not loaded): show a one-off placeholder
        -- so the sub-tab is still selectable instead of blanking the window.
        p = { name = name }
        panels[name] = p
        p.createFn = function(parent)
            local h = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
            h:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
            h:SetText(name)
            local fs = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -50)
            fs:SetText(ns.L["(nothing here yet)"])
            return nil
        end
    end

    if not p.frame then
        p.frame = CreateFrame("Frame", nil, contentArea)
        p.frame:SetAllPoints(contentArea)
        p.menu = p.createFn(p.frame)
    end
    p.frame:Show()
    activeSub = name

    if scrollFrame then scrollFrame:SetVerticalScroll(0) end
    C_Timer.After(0, function()
        if activeSub == name and p.frame:IsShown() then ResizeContentArea(p.frame) end
    end)

    HighlightMenu()
end

-- First (default) panel name of a main tab — the one shown when its main tab is
-- clicked. Recurses into the first category if the tab leads with one.
local function FirstPanelOf(tab)
    if not tab then return nil end
    for _, item in ipairs(tab.subs) do
        if item.panel then return item.panel end
        if item.subs then
            for _, s in ipairs(item.subs) do
                if s.panel then return s.panel end
            end
        end
    end
end

-- ── Left sub-tab menu ──────────────────────────────────────────────────────────
local MENU_W   = 150
local ROW_H    = 24
local ROW_GAP  = 2

local function LayoutLeftMenu()
    local y = 0
    for _, row in ipairs(menuRows) do
        local hide = row.catName and collapsed[row.catName]   -- sub under a folded category
        if hide then
            row:Hide()
        else
            row:Show()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  leftMenu, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", leftMenu, "TOPRIGHT", 0, -y)
            y = y + ROW_H + ROW_GAP
        end
    end
end

local function MakeRow()
    -- Fully transparent (no border, no background): selection + hover are shown by
    -- the label colour alone.
    local btn = CreateFrame("Button", nil, leftMenu)
    btn:SetHeight(ROW_H)
    return btn
end

local function MakeSubRow(panelName, catName)
    local btn = MakeRow()
    btn.panelName = panelName
    btn.catName   = catName

    -- Left accent bar: shown ONLY on the active sub-tab, so the selection stays
    -- distinct from a mere hover (which only recolours the label).
    local accent = btn:CreateTexture(nil, "OVERLAY")
    accent:SetColorTexture(BR, BG, BB, 1)
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT",    btn, "TOPLEFT",    0, 0)
    accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    accent:Hide()
    btn.accent = accent

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", btn, "LEFT", catName and 34 or 20, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(panelName)
    btn.label = lbl

    btn:SetScript("OnEnter", function() lbl:SetTextColor(BR, BG, BB) end)
    btn:SetScript("OnLeave", function()
        if activeSub == panelName then
            lbl:SetTextColor(BR, BG, BB)
        else
            lbl:SetTextColor(1, 1, 1)
        end
    end)
    btn:SetScript("OnClick", function() ShowSubTab(panelName) end)
    return btn
end

local function MakeCatRow(catName)
    local btn = MakeRow()
    btn.catName = nil    -- a category header is never hidden by collapse

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(8, 8)
    arrow:SetPoint("LEFT", btn, "LEFT", 6, 0)
    if UNBUNK_ICON_DROPDOWN_ARROW then arrow:SetTexture(UNBUNK_ICON_DROPDOWN_ARROW) end

    local lbl = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH4")
    lbl:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    lbl:SetText(catName)

    local function ApplyArrow()
        arrow:SetRotation(collapsed[catName] and math.rad(-90) or 0)
    end
    ApplyArrow()

    btn:SetScript("OnClick", function()
        collapsed[catName] = not collapsed[catName]
        ApplyArrow()
        LayoutLeftMenu()
    end)
    btn:SetScript("OnEnter", function() lbl:SetTextColor(0.5, 0.75, 1.0) end)
    btn:SetScript("OnLeave", function() lbl:SetTextColor(BR, BG, BB) end)
    return btn
end

local menuCache = {}   -- mainIndex -> { row frames }, built once per main tab

local function BuildLeftMenu(mainIndex)
    for _, r in ipairs(menuRows) do r:Hide() end

    if menuCache[mainIndex] then
        menuRows = menuCache[mainIndex]
        for _, r in ipairs(menuRows) do r:Show() end
    else
        menuRows = {}
        local tab = navTree[mainIndex]
        if tab then
            for _, item in ipairs(tab.subs) do
                if item.cat then
                    table.insert(menuRows, MakeCatRow(item.cat))
                    for _, sub in ipairs(item.subs) do
                        table.insert(menuRows, MakeSubRow(sub.panel, item.cat))
                    end
                else
                    table.insert(menuRows, MakeSubRow(item.panel, nil))
                end
            end
        end
        menuCache[mainIndex] = menuRows
    end
    LayoutLeftMenu()
end

-- ── Main tabs ──────────────────────────────────────────────────────────────────
local function ShowMainTab(index)
    activeMain = index
    BuildLeftMenu(index)
    ShowSubTab(FirstPanelOf(navTree[index]))

    for i, btn in ipairs(mainButtons) do
        local on = (i == index)
        btn:SetBackdropColor(on and 0.12 or 0.1, on and 0.15 or 0.1, on and 0.22 or 0.1, on and 1 or 0.8)
        btn:SetBackdropBorderColor(on and BR or 0.4, on and BG or 0.4, on and BB or 0.4, 1)
        if btn.label then btn.label:SetTextColor(on and BR or 1, on and BG or 1, on and BB or 1) end
    end
end

local function BuildMainTabs()
    local TAB_W, TAB_H, GAP = 150, 28, 4
    for i, tab in ipairs(navTree) do
        local btn = CreateFrame("Button", nil, mainBar, "BackdropTemplate")
        btn:SetSize(TAB_W, TAB_H)
        btn:SetPoint("TOPLEFT", mainBar, "TOPLEFT", (i - 1) * (TAB_W + GAP), 0)
        btn:SetBackdrop({
            bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(tab.name)
        btn.label = lbl

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(BR, BG, BB, 1)
            lbl:SetTextColor(BR, BG, BB)
        end)
        btn:SetScript("OnLeave", function(self)
            if activeMain == i then
                self:SetBackdropBorderColor(BR, BG, BB, 1)
                lbl:SetTextColor(BR, BG, BB)
            else
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
                lbl:SetTextColor(1, 1, 1)
            end
        end)
        btn:SetScript("OnClick", function() ShowMainTab(i) end)
        mainButtons[i] = btn
    end
end

-- ── Public hooks (used by BuildMenu / profile reload) ──────────────────────────
function ns.ResizeActiveModule()
    local name = activeSub
    if not name then return end
    C_Timer.After(0, function()
        if activeSub ~= name then return end
        local p = panels[name]
        if p and p.frame and p.frame:IsShown() then ResizeContentArea(p.frame) end
    end)
end

function UnbunkUtility.ShowActiveModule()
    if activeSub then ShowSubTab(activeSub) end
end

function ns.RebuildActiveModule()
    local p = activeSub and panels[activeSub]
    if p and p.frame and p.frame:IsShown() and p.menu and p.menu.Rebuild then
        p.menu.Rebuild()
    end
end

-- ── Window ─────────────────────────────────────────────────────────────────────
local function CreateMainWindow()
    window = CreateFrame("Frame", "UnbunkUtilityWindow", UIParent, "BackdropTemplate")
    window:SetSize(760, 800)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    window:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    window:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    window:Hide()

    local titleBar = window:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH1")
    titleBar:SetPoint("TOP", 0, -14)
    titleBar:SetText("UnbunkUtility")

    -- Close button: grey square, sharp 1px border -> blue on hover, white cross ->
    -- blue on hover (both crosses preloaded so the swap is instant).
    local closeBtn = CreateFrame("Button", nil, window)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)

    local closeBorder = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBorder:SetAllPoints(closeBtn)
    closeBorder:SetColorTexture(0.4, 0.4, 0.4, 1)

    local closeFill = closeBtn:CreateTexture(nil, "BACKGROUND", nil, 1)
    closeFill:SetPoint("TOPLEFT",     closeBtn, "TOPLEFT",      1, -1)
    closeFill:SetPoint("BOTTOMRIGHT", closeBtn, "BOTTOMRIGHT", -1,  1)
    closeFill:SetColorTexture(0.15, 0.15, 0.15, 0.9)

    local crossWhite = closeBtn:CreateTexture(nil, "OVERLAY")
    crossWhite:SetSize(12, 12)
    crossWhite:SetPoint("CENTER")
    crossWhite:SetTexture(UNBUNK_ICON_CROSS_WHITE)

    local crossBlue = closeBtn:CreateTexture(nil, "OVERLAY")
    crossBlue:SetSize(12, 12)
    crossBlue:SetPoint("CENTER")
    crossBlue:SetTexture(UNBUNK_ICON_CROSS_BLUE)
    crossBlue:Hide()

    closeBtn:SetScript("OnEnter", function()
        closeBorder:SetColorTexture(BR, BG, BB, 1)
        closeFill:SetColorTexture(0.22, 0.22, 0.22, 0.9)
        crossWhite:Hide()
        crossBlue:Show()
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBorder:SetColorTexture(0.4, 0.4, 0.4, 1)
        closeFill:SetColorTexture(0.15, 0.15, 0.15, 0.9)
        crossBlue:Hide()
        crossWhite:Show()
    end)
    closeBtn:SetScript("OnClick", function() window:Hide() end)

    table.insert(UISpecialFrames, "UnbunkUtilityWindow")

    -- Main tab bar (top row).
    mainBar = CreateFrame("Frame", nil, window)
    mainBar:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -40)
    mainBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -40)
    mainBar:SetHeight(28)

    local sep = window:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    sep:SetPoint("TOPLEFT", mainBar, "BOTTOMLEFT", 0, -4)
    sep:SetPoint("TOPRIGHT", mainBar, "BOTTOMRIGHT", 0, -4)
    sep:SetHeight(1)

    -- Left sub-tab menu.
    leftMenu = CreateFrame("Frame", nil, window)
    leftMenu:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -8)
    leftMenu:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 30)
    leftMenu:SetWidth(MENU_W)

    -- Vertical separator between the menu and the content.
    local vsep = window:CreateTexture(nil, "ARTWORK")
    vsep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    vsep:SetPoint("TOPLEFT", leftMenu, "TOPRIGHT", 8, 0)
    vsep:SetPoint("BOTTOMLEFT", leftMenu, "BOTTOMRIGHT", 8, 0)
    vsep:SetWidth(1)

    -- Content (scrollable) to the right of the menu.
    scrollFrame = CreateFrame("ScrollFrame", nil, window)
    scrollFrame:SetPoint("TOPLEFT", vsep, "TOPRIGHT", 8, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -28, 30)

    contentArea = CreateFrame("Frame", nil, scrollFrame)
    local w = scrollFrame:GetWidth()
    if not w or w <= 0 then w = 560 end
    contentArea:SetWidth(w)
    contentArea:SetHeight(1000)
    scrollFrame:SetScrollChild(contentArea)

    scrollFrame:EnableMouseWheel(true)

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
    sb.track:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 22, 0)
    sb.track:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 22, 0)
    sb.track:Show()

    window:HookScript("OnShow", function()
        -- Re-measure the active panel now the window is actually laid out (it was
        -- first built while hidden, where widths/positions can read back as 0).
        ns.ResizeActiveModule()
        C_Timer.After(0.1, function() sb.Update() end)
    end)

    -- ── Footer: links (left) + version (right) ────────────────────────────────
    local footerSep = window:CreateTexture(nil, "ARTWORK")
    footerSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    footerSep:SetPoint("BOTTOMLEFT",  window, "BOTTOMLEFT",  16, 26)
    footerSep:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 26)
    footerSep:SetHeight(1)

    local meta    = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = (meta and meta(ADDON, "Version")) or "?"
    local verFS = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    verFS:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 8)
    verFS:SetText("v" .. version)

    local function MakeLink(label, url)
        local btn = CreateFrame("Button", nil, window)
        local fs  = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints(btn)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        fs:SetTextColor(BR, BG, BB)
        btn:SetSize(math.max(24, fs:GetStringWidth() + 2), 14)
        btn:SetScript("OnEnter", function() fs:SetTextColor(0.5, 0.75, 1.0) end)
        btn:SetScript("OnLeave", function() fs:SetTextColor(BR, BG, BB) end)
        btn:SetScript("OnClick", function() ShowURL(url) end)
        return btn
    end
    local ghBtn = MakeLink("GitHub", GITHUB_URL)
    ghBtn:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 8)
    local cfBtn = MakeLink("CurseForge", CURSEFORGE_URL)
    cfBtn:SetPoint("LEFT", ghBtn, "RIGHT", 14, 0)
end

function UnbunkUtility.OpenWindow()
    if not window then return end
    if window:IsShown() then window:Hide() else window:Show() end
end

local initCore = CreateFrame("Frame")
initCore:RegisterEvent("PLAYER_LOGIN")
initCore:SetScript("OnEvent", function(self)
    CreateMainWindow()
    -- Built after all modules have registered their panels.
    C_Timer.After(0, function()
        navTree = BuildNavTree()
        BuildMainTabs()
        ShowMainTab(1)
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
