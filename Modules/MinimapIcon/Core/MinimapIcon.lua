-- Modules/MinimapIcon/Core/MinimapIcon.lua
-- Minimap button to open the UnbunkUtility config window. Self-contained
-- (no LibDBIcon dependency); position is stored as an angle around the
-- minimap edge in ns.db.global.minimap.

local _, ns = ...
local L = ns.L

-- Dedicated minimap-button artwork (distinct from the larger ## IconTexture asset
-- in the .toc, which uses Media/Icons/UnbunkUtility.tga).
local ICON_TEXTURE = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\UnbunkUtilityMinimapButton.tga"

local DEFAULTS = {
    hide   = false,
    angle  = 200,   -- degrees, 0=East / 90=North / 180=West / 270=South
    -- distance from the minimap center; stored in saved-vars for forward
    -- compatibility but not yet exposed in any UI, so it stays at the default.
    radius = 80,
}

local function CfgInit()
    ns.db.global.minimap = ns.db.global.minimap or {}
    ns.MergeDefaults(ns.db.global.minimap, DEFAULTS)
end

ns.RegisterCfgInitHook(CfgInit)

local button

local function UpdatePosition()
    if not button then return end
    local cfg    = ns.db and ns.db.global.minimap
    if not cfg then return end
    local angle  = math.rad(cfg.angle or 200)
    local radius = cfg.radius or 80
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius,
        math.sin(angle) * radius)
end

local function CreateButton()
    if button then return button end
    button = CreateFrame("Button", "UnbunkUtilityMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    -- Keep the button on screen even when the minimap is dragged near an edge,
    -- so it never ends up off-screen and unclickable.
    button:SetClampedToScreen(true)
    -- Only left-click is handled (matches the tooltip). Right-click is a no-op;
    -- there is no context menu, so it is deliberately not registered.
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Standard minimap-button ring on top. The MiniMap-TrackingBorder art has its
    -- visible ring in the UPPER-LEFT of the texture (the bottom-right portion is drop
    -- shadow), so anchoring the 54px border at the button's TOPLEFT centres the ring on
    -- the 32px button. (The previous -2,2 offset pushed the ring up-left, which made the
    -- centred icon look shifted toward the bottom-right.)
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetSize(54, 54)
    overlay:SetPoint("TOPLEFT", 0, 0)

    -- Dark circular background under the icon, nudged 1px down-right to sit at the ring's
    -- optical centre (the MiniMap-TrackingBorder ring centres slightly off the texture middle).
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER", 1, 0)

    -- Addon icon, centred in the ring (same nudge as the background).
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 1, 0)

    button:SetScript("OnClick", function()
        if UnbunkUtility and UnbunkUtility.OpenWindow then
            UnbunkUtility.OpenWindow()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("UnbunkUtility")
        GameTooltip:AddLine(L["|cff338cffLeft-click|r to open settings"], 1, 1, 1)
        GameTooltip:AddLine(L["|cff338cffDrag|r to reposition"], 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drag — recompute the angle from the cursor's position relative to the
    -- minimap center so the button stays on the minimap edge. Throttled to
    -- ~50 Hz: a repositioning drag doesn't need the per-frame atan2/cos/sin.
    local DRAG_THROTTLE = 0.02
    local dragAccum = 0
    local function UpdateAngleFromCursor(_, elapsed)
        dragAccum = dragAccum + (elapsed or 0)
        if dragAccum < DRAG_THROTTLE then return end
        dragAccum = 0
        local cx, cy = Minimap:GetCenter()
        if not cx then return end
        local scale = Minimap:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        mx, my = mx / scale, my / scale
        local angle = math.deg(math.atan2(my - cy, mx - cx))
        if angle < 0 then angle = angle + 360 end
        if ns.db then ns.db.global.minimap.angle = angle end
        UpdatePosition()
    end
    button:SetScript("OnDragStart", function(self)
        dragAccum = 0
        self:SetScript("OnUpdate", UpdateAngleFromCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return button
end

-- Public API so a future config toggle can hide / show the button.
function ns.MinimapIcon_SetHidden(hide)
    if not ns.db then return end
    CfgInit()
    ns.db.global.minimap.hide = hide and true or false
    if not button then return end
    if hide then button:Hide() else button:Show() end
end

function ns.MinimapIcon_IsHidden()
    return ns.db and ns.db.global.minimap
        and ns.db.global.minimap.hide == true
end

-- Button/visual setup runs on PLAYER_LOGIN, which fires after Core/DB.lua's
-- ADDON_LOADED Bootstrap has created ns.db and run the CfgInit hooks (so
-- ns.db.global.minimap is already merged with DEFAULTS by this point).
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    CreateButton()
    UpdatePosition()
    if ns.db and ns.db.global.minimap and ns.db.global.minimap.hide then button:Hide() end
    self:UnregisterEvent("PLAYER_LOGIN")
end)
