-- Core/Core.lua
-- Main UnbunkUtility window with navigation bar.

UnbunkUtility = {}
local registeredModules = {}
local window
local navbar
local contentArea
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

local function ShowModule(index)
    local mod = registeredModules[index]
    if not mod then return end

    for _, m in ipairs(registeredModules) do
        if m.frame then m.frame:Hide() end
    end

    if not mod.frame then
        mod.frame = CreateFrame("Frame", nil, contentArea)
        mod.frame:SetAllPoints(contentArea)
        mod.createFn(mod.frame)
    end

    mod.frame:Show()
    activeTab = index

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

local function BuildNavbar()
    for _, btn in ipairs(tabButtons) do btn:Hide() end
    tabButtons = {}

    local TAB_WIDTH  = 120
    local TAB_HEIGHT = 28
    local TAB_GAP    = 4
    local x = 0

    for i, mod in ipairs(registeredModules) do
        local btn = CreateFrame("Button", nil, navbar, "BackdropTemplate")
        btn:SetSize(TAB_WIDTH, TAB_HEIGHT)
        btn:SetPoint("LEFT", navbar, "LEFT", x, 0)
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
        x = x + TAB_WIDTH + TAB_GAP
    end
end

local function CreateMainWindow()
    window = CreateFrame("Frame", "UnbunkUtilityWindow", UIParent, "BackdropTemplate")
    window:SetSize(600, 500)
    window:SetPoint("CENTER")
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

    navbar = CreateFrame("Frame", nil, window)
    navbar:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -40)
    navbar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -40)
    navbar:SetHeight(28)

    local sep = window:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    sep:SetPoint("TOPLEFT", navbar, "BOTTOMLEFT", 0, -4)
    sep:SetPoint("TOPRIGHT", navbar, "BOTTOMRIGHT", 0, -4)
    sep:SetHeight(1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, window)
    scrollFrame:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -28, 16)

    contentArea = CreateFrame("Frame", nil, scrollFrame)
    contentArea:SetWidth(scrollFrame:GetWidth() or 550)
    contentArea:SetHeight(1000)
    scrollFrame:SetScrollChild(contentArea)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local max     = self:GetVerticalScrollRange()
        local new     = math.max(0, math.min(max, current - delta * 30))
        self:SetVerticalScroll(new)
    end)

    -- Scrollbar
    local sb = Unbunk_CreateScrollBar({
        parent       = window,
        scrollFrame  = scrollFrame,
        itemHeight   = 30,
        visibleItems = 10,
        getListSize  = function() return 20 end,
    })
    sb.track:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -80)
    sb.track:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, 16)
    sb.track:Show()

    window:HookScript("OnShow", function()
        C_Timer.After(0.1, function()
            sb.Update()
        end)
    end)

    BuildNavbar()

    if #registeredModules > 0 then
        ShowModule(1)
    end
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
    self:UnregisterEvent("PLAYER_LOGIN")
end)