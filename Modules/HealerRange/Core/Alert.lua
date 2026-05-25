-- Modules/HealerRange/Core/Alert.lua

local isUnlocked = false
local isTesting  = false

local alertFrame = CreateFrame("Frame", "HealerRangeAlert", UIParent, "BackdropTemplate")
alertFrame:SetSize(260, 60)
alertFrame:Hide()

local alertText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
alertText:SetPoint("CENTER")
alertText:SetText("Out of healer range!")
alertText:SetTextColor(1, 1, 1)

local ag = alertFrame:CreateAnimationGroup()
ag:SetLooping("BOUNCE")
local alphaAnim = ag:CreateAnimation("Alpha")
alphaAnim:SetFromAlpha(1)
alphaAnim:SetToAlpha(0.3)
alphaAnim:SetDuration(0.5)
ag:Play()

function HealerRangeAlert_ApplyColor()
    local c = HealerRangeCfg_Get("color")
    alertText:SetTextColor(c.r, c.g, c.b, c.a)
end

function HealerRangeAlert_ApplyPosition()
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint("CENTER", UIParent, "CENTER",
        HealerRangeCfg_Get("posX"),
        HealerRangeCfg_Get("posY"))
end

function HealerRangeAlert_ApplyMessage()
    local msg = HealerRangeCfg_Get("alertMessage") or "Out of healer range!"
    alertText:SetText(msg)
end

function HealerRangeAlert_ApplyFont()
    local fontPath = HealerRangeCfg_Get("fontPath")
    local fontSize = HealerRangeCfg_Get("fontSize") or 22
    local outline  = HealerRangeCfg_Get("outline") or ""
    if fontPath then
        alertText:SetFont(fontPath, fontSize, outline)
    else
        alertText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, outline)
    end
end

function HealerRangeAlert_SetVisible(visible)
    if isUnlocked then return end
    if visible then alertFrame:Show() else alertFrame:Hide() end
end

function HealerRangeAlert_SetUnlocked(unlocked)
    isUnlocked = unlocked
    if unlocked then
        alertFrame:SetMovable(true)
        alertFrame:EnableMouse(true)
        alertFrame:RegisterForDrag("LeftButton")
        alertFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        alertFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local _, _, _, x, y = self:GetPoint()
            HealerRangeCfg_Set("posX", math.floor(x))
            HealerRangeCfg_Set("posY", math.floor(y))
        end)
        alertFrame:SetBackdrop({
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 10,
        })
        alertFrame:SetBackdropBorderColor(1, 1, 0, 0.8)
        alertFrame:Show()
    else
        alertFrame:SetMovable(false)
        alertFrame:EnableMouse(false)
        alertFrame:SetScript("OnDragStart", nil)
        alertFrame:SetScript("OnDragStop", nil)
        alertFrame:SetBackdrop(nil)
        alertFrame:Hide()
    end
end

function HealerRangeAlert_IsUnlocked()
    return isUnlocked
end

function HealerRangeAlert_IsTesting()
    return isTesting
end

function HealerRangeAlert_SetTesting(val)
    isTesting = val
end

function HealerRangeAlert_GetFrame()
    return alertFrame
end

local initAlert = CreateFrame("Frame")
initAlert:RegisterEvent("PLAYER_LOGIN")
initAlert:SetScript("OnEvent", function(self)
    HealerRangeAlert_ApplyColor()
    HealerRangeAlert_ApplyPosition()
    HealerRangeAlert_ApplyFont()
    HealerRangeAlert_ApplyMessage()
    self:UnregisterEvent("PLAYER_LOGIN")
end)