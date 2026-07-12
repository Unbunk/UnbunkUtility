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

-- Modules register their config panel(s) via OnAddonLoaded instead of each spinning up its own
-- ADDON_LOADED frame. A SINGLE shared frame runs the queued callbacks once, on this addon's
-- ADDON_LOADED — i.e. AFTER Core/DB.lua's bootstrap has run ns.ApplyLocale (DB loads before Core),
-- so each RegisterModule inside a callback resolves its panel name in the SAVED language, exactly
-- as BuildNavTree (PLAYER_LOGIN) does — the two must agree for the nav to find the panel by name.
local onLoadedCallbacks = {}
function UnbunkUtility.OnAddonLoaded(fn)
    onLoadedCallbacks[#onLoadedCallbacks + 1] = fn
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, addon)
        if addon ~= "UnbunkUtility" then return end
        for _, fn in ipairs(onLoadedCallbacks) do fn() end
        self:UnregisterEvent("ADDON_LOADED")
    end)
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
        title:SetText(ns.L["Copy the link (Ctrl+C)"])

        -- Selectable EditBox holding the URL, with the inputs' dark sharp fill.
        local eb = CreateFrame("EditBox", nil, f)
        eb:SetSize(400, 24)
        eb:SetPoint("TOP", f, "TOP", 0, -46)
        eb:SetAutoFocus(false)
        eb:SetFontObject("UnbunkUtilityBody")
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
            { panel = L["Profiles"] },
            { cat = L["Cooldown Manager"], subs = (function()
                -- "CDM Settings (beta)" is the hub, always at the TOP: it picks which CDM engine is active.
                -- The per-category tabs (Essential / Utility / Buffs / Bars) now show in BOTH modes: the same
                -- config drives the native render AND the standalone engine (which reuses the native group
                -- model as its layout source), so a single set of panels configures either engine. L["Utility"]
                -- resolves to the NEW CDMGroups Utility panel (its RegisterModule supersedes the old bucket).
                local subs = {
                    { panel = L["CDM Settings (beta)"] },
                    { panel = L["Essential"] },
                    { panel = L["Utility"] },
                    { panel = L["Buffs"] },
                    { panel = L["Bars"] },
                    { panel = L["Below player frame"] },
                    { panel = L["Free icons"] },
                }
                return subs
            end)() },
        } },
        { name = L["Combat Utilities"], subs = {
            { panel = L["Combat settings"] },
            { panel = L["Healer Range"] },
            { panel = L["BRez Tracker"] },
            { cat = L["Death Alerts"], subs = {
                { panel = L["Tank Death Alert"] },
                { panel = L["Healer Death Alert"] },
                { panel = L["DPS Death Alert"] },
                { panel = L["Death alert anti-spam"] },
            } },
            { cat = L["Item/Spell Trackers"], subs = {
                { panel = L["Defensive Tracker"] },
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
            { panel = L["Cast bar"] },
            { panel = L["Multi-alert combo"] },
            { panel = L["Player speed display"] },
            { panel = L["Death Anim"] },
            { panel = L["Boss reset sound"] },
            { panel = L["Reloading announcement"] },
            { panel = L["Show IDs"] },
        } },
        { name = L["Debug Utilities"], subs = (function()
            -- The "Debug" sub-tab is always present (it hosts the "I know what I'm
            -- doing" unlock checkbox). Any further debug sub-tabs are GATED: they only
            -- appear once unlocked. ns.RefreshNav() rebuilds this when the flag toggles.
            local subs = { { panel = L["Debug"] } }
            if ns.IsDebugUnlocked and ns.IsDebugUnlocked() then
                subs[#subs + 1] = { panel = L["Secret settings"] }
                subs[#subs + 1] = { panel = L["Beta"] }
                subs[#subs + 1] = { cat = L["Addon usage"], subs = {
                    { panel = L["List"] },
                    { panel = L["Graph"] },
                    { panel = L["Print"] },
                } }
                -- Owner-only secret category: requires BOTH the unlock above AND the
                -- developer's Battle.net account.
                if ns.IsAccountOwner and ns.IsAccountOwner() then
                    subs[#subs + 1] = { cat = L["Unbunk"], subs = {
                        { cat = L["Personal utilities"], subs = {
                            { panel = L["Restore my profile"] },
                            { panel = L["Details! special settings"] },
                            { panel = L["Disable keybinds"] },
                            { panel = L["Focus buffs"] },
                            { panel = L["Decursive special settings"] },
                        } },
                    } }
                end
            end
            return subs
        end)() },
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
                if row.accent.SetColorTexture then row.accent:SetColorTexture(BR, BG, BB, 1) end
            end
        end
    end
end

-- Re-tint the config window's brand-blue chrome live when the brand colour changes:
-- reassign the shared BR/BG/BB upvalues (so every hover/highlight handler picks up the
-- new colour on its next call) and re-apply the current selection immediately.
if ns.RegisterBrandColorHook then
    ns.RegisterBrandColorHook(function(r, g, b)
        BR, BG, BB = r, g, b
        HighlightMenu()                          -- selected sub-tab row labels + accent
        for i, btn in ipairs(mainButtons) do     -- selected main tab border + label
            local on = (i == activeMain)
            btn:SetBackdropBorderColor(on and BR or 0.4, on and BG or 0.4, on and BB or 0.4, 1)
            if btn.label then btn.label:SetTextColor(on and BR or 1, on and BG or 1, on and BB or 1) end
        end
    end)
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

-- X where the content column begins: window left margin (16) + the sub-tab menu
-- (MENU_W) + the vsep gutter (8px gap + 1px line + 8px gap = 17). The main tab bar
-- AND the scroll content both align to this, so the tabs sit to the RIGHT of the
-- sub-tab menu (not above it). BuildMainTabs also uses it to size the tabs.
local CONTENT_X = 16 + MENU_W + 17

-- A row is hidden when ANY of its ancestor categories is folded. `row.ancestors`
-- is the ordered list of enclosing category names (outermost first); a top-level
-- row has none. This supports categories nested inside categories.
local function RowHidden(row)
    if not row.ancestors then return false end
    for _, c in ipairs(row.ancestors) do
        if collapsed[c] then return true end
    end
    return false
end

local function LayoutLeftMenu()
    local y = 0
    for _, row in ipairs(menuRows) do
        local hide = RowHidden(row)
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

-- Each nesting level (an enclosing category) indents a row by this many px.
local NEST_INDENT = 14

local function MakeSubRow(panelName, ancestors)
    local btn = MakeRow()
    btn.panelName = panelName
    btn.ancestors = ancestors            -- enclosing categories (folded => row hidden)
    local depth   = ancestors and #ancestors or 0

    -- Left accent bar: shown ONLY on the active sub-tab, so the selection stays
    -- distinct from a mere hover (which only recolours the label).
    local accent = btn:CreateTexture(nil, "OVERLAY")
    accent:SetColorTexture(BR, BG, BB, 1)
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT",    btn, "TOPLEFT",    0, 0)
    accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    accent:Hide()
    btn.accent = accent

    local indent = 20 + depth * NEST_INDENT
    local lbl = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
    lbl:SetPoint("LEFT", btn, "LEFT", indent, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)                       -- keep the row a single line (deep nesting => narrow)
    lbl:SetText(panelName)
    -- Shrink a too-long label to fit the remaining menu width (deeply nested sub-tabs
    -- have little room), the way the main tabs do — down to an 8px floor.
    local avail = MENU_W - indent - 6
    local fp, fsz, ffl = lbl:GetFont()
    local fs = fsz or 11
    while fs > 8 and lbl:GetStringWidth() > avail do
        fs = fs - 1
        lbl:SetFont(fp, fs, ffl)
    end
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

local function MakeCatRow(catName, ancestors)
    local btn = MakeRow()
    -- A category header is itself hidden only when an ENCLOSING category is folded
    -- (nested categories); folding the header's own category hides its children, not it.
    btn.ancestors = ancestors
    local depth   = ancestors and #ancestors or 0

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(8, 8)
    arrow:SetPoint("LEFT", btn, "LEFT", 6 + depth * NEST_INDENT, 0)
    if UNBUNK_ICON_DROPDOWN_ARROW then
        arrow:SetTexture(UNBUNK_ICON_DROPDOWN_ARROW)
        ns.SetBrandVertex(arrow)   -- white glyph -> brand blue (re-tinted live)
    end

    local lbl = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH4")
    lbl:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    lbl:SetText(catName)

    -- Brand-blue at rest, a lighter brand tint on hover. Both read ns.GetBrandColor()
    -- (the live colour, updated before the _brandTargets run) — NOT the BR/BG/BB
    -- upvalues, which the Core hook only reassigns later in the same apply pass.
    local function restColor() lbl:SetTextColor(ns.GetBrandColor()) end
    local function hoverColor()
        local r, g, b = ns.GetBrandColor()
        lbl:SetTextColor(r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45)
    end
    restColor()
    if ns.RegisterBrandRefresh then ns.RegisterBrandRefresh(btn, restColor) end

    local function ApplyArrow()
        arrow:SetRotation(collapsed[catName] and math.rad(-90) or 0)
    end
    ApplyArrow()

    btn:SetScript("OnClick", function()
        collapsed[catName] = not collapsed[catName]
        ApplyArrow()
        LayoutLeftMenu()
    end)
    btn:SetScript("OnEnter", hoverColor)
    btn:SetScript("OnLeave", restColor)
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
        -- Walk the subs recursively so a category can itself hold sub-categories.
        -- `ancestors` is the ordered list of enclosing category names (nil at the top).
        local function addItems(items, ancestors)
            for _, item in ipairs(items) do
                if item.cat then
                    table.insert(menuRows, MakeCatRow(item.cat, ancestors))
                    local childAncestors = {}
                    if ancestors then
                        for _, a in ipairs(ancestors) do childAncestors[#childAncestors + 1] = a end
                    end
                    childAncestors[#childAncestors + 1] = item.cat
                    addItems(item.subs, childAncestors)
                else
                    table.insert(menuRows, MakeSubRow(item.panel, ancestors))
                end
            end
        end
        if tab then addItems(tab.subs, nil) end
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

-- Public: jump to a registered sub-tab by name, switching the main tab and expanding
-- its category if needed. Used by the Free-icons tab to click through to a tracker.
function ns.NavigateToPanel(panelName)
    if not (navTree and panelName) then return end
    -- Find the panel anywhere in the (possibly nested) tree, collecting the chain of
    -- enclosing categories so they can all be revealed.
    local function search(items, cats)
        for _, item in ipairs(items) do
            if item.panel == panelName then
                return cats
            elseif item.subs then
                local nc = {}
                for _, c in ipairs(cats) do nc[#nc + 1] = c end
                nc[#nc + 1] = item.cat
                local found = search(item.subs, nc)
                if found then return found end
            end
        end
    end
    for mi, tab in ipairs(navTree) do
        local cats = search(tab.subs, {})
        if cats then
            if activeMain ~= mi then ShowMainTab(mi) end
            for _, c in ipairs(cats) do collapsed[c] = false end   -- reveal every enclosing category
            LayoutLeftMenu()
            ShowSubTab(panelName)
            return true
        end
    end
end

-- Public: drop a panel's cached frame so its createFn re-runs next time it is shown
-- (e.g. the Defensive Tracker's per-spell section list after a spec change). If it is
-- the active panel, recreate + show it now.
function ns.InvalidatePanel(name)
    local p = panels[name]
    if not p or not p.frame then return end
    local wasActive = (activeSub == name and p.frame:IsShown())
    p.frame:Hide()
    p.frame:SetParent(nil)
    p.frame = nil
    p.menu  = nil
    if wasActive then ShowSubTab(name) end
end

local function BuildMainTabs()
    local n = #navTree
    if n == 0 then return end
    local TAB_H, GAP = 28, 4
    -- The tab bar spans from the content column (CONTENT_X) to the right margin and
    -- is split evenly among the main tabs, so the tab width tracks the window width.
    local avail = mainBar:GetWidth()
    if not avail or avail <= 0 then
        avail = (window:GetWidth() or 745) - 16 - CONTENT_X
    end
    local TAB_W = math.max(60, math.floor((avail - (n - 1) * GAP) / n))
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

        local lbl = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        lbl:SetPoint("CENTER")
        lbl:SetText(tab.name)
        -- Shrink the label to fit a narrower tab so longer localized names (e.g. the
        -- French "Utilitaires de débogage") aren't clipped when the window is small.
        local fp, fsz, ffl = lbl:GetFont()
        local fs = fsz or 11
        while fs > 8 and lbl:GetStringWidth() > (TAB_W - 8) do
            fs = fs - 1
            lbl:SetFont(fp, fs, ffl)
        end
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

-- Rebuild the nav tree + left sub-tab menu after something changes which sub-tabs
-- are visible (e.g. the Debug "I know what I'm doing" toggle). Cached menu rows are
-- orphaned so they rebuild from the new tree; the current sub-tab is kept if it
-- survived, else the active main tab's default opens.
function ns.RefreshNav()
    if not navTree then return end
    navTree = BuildNavTree()
    for _, rows in pairs(menuCache) do
        for _, r in ipairs(rows) do r:Hide(); r:ClearAllPoints(); r:SetParent(nil) end
    end
    wipe(menuCache)
    menuRows = {}
    if not activeMain then return end
    BuildLeftMenu(activeMain)
    local tab = navTree[activeMain]
    local stillThere = false
    if tab then
        for _, item in ipairs(tab.subs) do
            if item.panel == activeSub then stillThere = true break end
            if item.subs then
                for _, s in ipairs(item.subs) do
                    if s.panel == activeSub then stillThere = true break end
                end
            end
        end
    end
    ShowSubTab(stillThere and activeSub or FirstPanelOf(tab))
end

-- Called by Core/DB.lua right after AceDB applies a new profile. The per-profile debug,
-- console, appearance and addon-usage settings have just been re-merged (CfgInit) and the
-- appearance hooks (brand colour / font) have already re-applied. Here we re-apply the
-- debug-suite BEHAVIOUR for the new profile and shut its windows if the new profile
-- re-locks the suite (else let open graphs adopt the new size). The config-panel rebuild
-- + nav refresh are done by ns.profiles.ReloadAll (called by the profile UI after the
-- switch), so they are intentionally NOT duplicated here.
function ns.OnProfileApplied()
    if ns.Debug_ApplyConsoleOptions then ns.Debug_ApplyConsoleOptions() end
    if ns.Debug_ApplyUsageOptions  then ns.Debug_ApplyUsageOptions()  end
    if ns.IsDebugUnlocked and not ns.IsDebugUnlocked() then
        if ns.Debug_CloseConsole then ns.Debug_CloseConsole() end
        if ns.Debug_CloseGraphs  then ns.Debug_CloseGraphs()  end
    elseif ns.Debug_ReapplyGraphSizes then
        ns.Debug_ReapplyGraphSizes()
    end
end

-- ── Window ─────────────────────────────────────────────────────────────────────
local function CreateMainWindow()
    window = CreateFrame("Frame", "UnbunkUtilityWindow", UIParent, "BackdropTemplate")
    -- Width sized so the content panels (518px) sit with roughly equal gaps on the
    -- left (sub-tab menu) and right (window edge / scrollbar) — no big empty band on
    -- the right. The main tabs adapt to the remaining width (see BuildMainTabs).
    window:SetSize(745, 800)
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

    -- Close button: grey square, sharp 1px border -> blue on hover. A SINGLE white
    -- cross texture is tinted to the brand blue on hover via SetVertexColor (white
    -- × colour = that colour), so it uses the EXACT same blue as the rest of the
    -- addon and needs no second pre-coloured image.
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

    local crossTex = closeBtn:CreateTexture(nil, "OVERLAY")
    crossTex:SetSize(12, 12)
    crossTex:SetPoint("CENTER")
    crossTex:SetTexture(UNBUNK_ICON_CROSS_WHITE)

    closeBtn:SetScript("OnEnter", function()
        closeBorder:SetColorTexture(BR, BG, BB, 1)
        closeFill:SetColorTexture(0.22, 0.22, 0.22, 0.9)
        crossTex:SetVertexColor(BR, BG, BB)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBorder:SetColorTexture(0.4, 0.4, 0.4, 1)
        closeFill:SetColorTexture(0.15, 0.15, 0.15, 0.9)
        crossTex:SetVertexColor(1, 1, 1)
    end)
    closeBtn:SetScript("OnClick", function() window:Hide() end)

    table.insert(UISpecialFrames, "UnbunkUtilityWindow")

    -- ── Top row: language selector (left column) + main tabs (right) ────────────
    -- The main tabs start at the content column (CONTENT_X, right of the sub-tab
    -- menu) instead of above it; the freed top-left corner holds the language
    -- dropdown, directly above the sub-tab menu it shares a column with.

    -- Language selector (account-wide ns.db.global.locale). The default is simply the
    -- game client locale (no "Auto" entry); picking a language overrides it. Built
    -- strings are captured when widgets are created, so the change applies on reload.
    local langLabel = window:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
    langLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -40)
    langLabel:SetText(ns.L["Language :"])
    langLabel:SetTextColor(0.67, 0.67, 0.67)   -- grey (0xaa), matching the other H6 hints

    -- Languages shown in the dropdown (no "Auto" entry): the default is simply the
    -- game client locale, resolved by ns.GetEffectiveLocale when nothing is saved.
    local LANG_ORDER = {}
    for _, code in ipairs(ns.LOCALE_ORDER or {}) do LANG_ORDER[#LANG_ORDER + 1] = code end
    local function LangLabelFor(code)
        return (ns.LOCALE_NAMES and ns.LOCALE_NAMES[code]) or code
    end
    -- The currently active language (saved override, else the game locale) so the
    -- dropdown highlights what's really in use even before any explicit choice.
    local function CurrentLangCode()
        return ns.GetEffectiveLocale and ns.GetEffectiveLocale() or "enUS"
    end

    local langDD = ns.ui.CreateDropdown({
        parent        = window,
        anchorFrame   = langLabel,
        width         = MENU_W,
        itemHeight    = 20,
        visibleItems  = #LANG_ORDER,
        getList       = function()
            local t = {}
            for _, code in ipairs(LANG_ORDER) do t[#t + 1] = LangLabelFor(code) end
            return t
        end,
        getCurrentKey = function() return LangLabelFor(CurrentLangCode()) end,
        onSelect      = function(label)
            local chosen
            for _, code in ipairs(LANG_ORDER) do
                if LangLabelFor(code) == label then chosen = code break end
            end
            if not chosen then return end
            if ns.db then ns.db.global.locale = chosen end
            if ns.ApplyLocale then ns.ApplyLocale() end
            -- A full reload re-translates everything (tabs/menu/panels capture their
            -- strings at build time). Don't reload in combat — the saved value will
            -- apply on the next manual /reload or relog.
            if InCombatLockdown() then
                ns.Print(ns.L["Language set — type /reload to apply."])
            elseif C_UI and C_UI.Reload then
                C_UI.Reload()
            else
                ReloadUI()
            end
        end,
    })
    langDD.selectedText:SetText(LangLabelFor(CurrentLangCode()))

    -- Main tab bar (top row, right of the language column / aligned with content).
    mainBar = CreateFrame("Frame", nil, window)
    mainBar:SetPoint("TOPLEFT", window, "TOPLEFT", CONTENT_X, -52)
    mainBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -52)
    mainBar:SetHeight(28)

    -- Full-width divider below the whole top row (language column + tabs).
    local sep = window:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    sep:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -86)
    sep:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -86)
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
        -- The heavier panels (Essential / Utility / Buffs / Bars) rebuild AND re-measure
        -- their content from their OWN frame's OnShow hook, which fires on a tab switch but
        -- NOT reliably when the WINDOW itself is re-opened (the panel's shown state never
        -- changed, and the rebuild that does run races the window's layout). The result: the
        -- panel that was active when the window closed can come back empty until you switch
        -- tabs and back. Re-show the active panel on the next frame — once the window is laid
        -- out — to run the exact same rebuild + re-measure path a tab switch uses. This also
        -- covers the plain "re-measure after first built while hidden" case.
        C_Timer.After(0, function()
            if window:IsShown() then UnbunkUtility.ShowActiveModule() end
        end)
        C_Timer.After(0.1, function() sb.Update() end)
    end)

    -- Re-lock any session "unlock for repositioning" modes when the config window
    -- closes. Otherwise the below-player CDM row in particular lingers: it stays in
    -- DIALOG strata with a mouse-capturing translucent blue drag overlay until the
    -- user re-clicks Lock, and there is no other way to clear it without reopening
    -- that exact sub-tab. The Unlock/Lock buttons read these states on (re)build, so
    -- they show "Unlock" again next time the panel opens.
    window:HookScript("OnHide", function()
        if ns.CDMAnchor and ns.CDMAnchor.IsBelowUnlocked and ns.CDMAnchor.IsBelowUnlocked() then
            ns.CDMAnchor.SetBelowUnlocked(false)
        end
        if ns.SpeedDisplay and ns.SpeedDisplay.IsUnlocked and ns.SpeedDisplay.IsUnlocked()
            and ns.SpeedDisplay.SetUnlocked then
            ns.SpeedDisplay.SetUnlocked(false)
        end
    end)

    -- ── Footer: links (left) + version (right) ────────────────────────────────
    local footerSep = window:CreateTexture(nil, "ARTWORK")
    footerSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    footerSep:SetPoint("BOTTOMLEFT",  window, "BOTTOMLEFT",  16, 26)
    footerSep:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 26)
    footerSep:SetHeight(1)

    local meta    = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = (meta and meta(ADDON, "Version")) or "?"
    local verFS = window:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
    verFS:SetTextColor(0.6, 0.6, 0.6)   -- small grey descriptive text (H6 convention)
    verFS:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 8)
    verFS:SetText("v" .. version)

    local function MakeLink(label, url)
        local btn = CreateFrame("Button", nil, window)
        local fs  = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        fs:SetAllPoints(btn)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        -- Brand-blue at rest (re-tinted live), lighter brand tint on hover. Read the
        -- live colour, not the BR/BG/BB upvalues (reassigned later in the apply pass).
        local function restColor() fs:SetTextColor(ns.GetBrandColor()) end
        local function hoverColor()
            local r, g, b = ns.GetBrandColor()
            fs:SetTextColor(r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45)
        end
        restColor()
        if ns.RegisterBrandRefresh then ns.RegisterBrandRefresh(btn, restColor) end
        btn:SetSize(math.max(24, fs:GetStringWidth() + 2), 14)
        btn:SetScript("OnEnter", hoverColor)
        btn:SetScript("OnLeave", restColor)
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
