-- Modules/DeathAlert/Core/Alert.lua

local tankTesting   = false
local healerTesting = false

-- ── Tank alert frame ──────────────────────────────────────────────────────────

local tankFrame = CreateFrame("Frame", "DeathAlertTankFrame", UIParent, "BackdropTemplate")
tankFrame:SetSize(260, 60)
tankFrame:Hide()

local tankText = tankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
tankText:SetPoint("CENTER")
tankText:SetText("Tank died!")

local tankAG = tankFrame:CreateAnimationGroup()
tankAG:SetLooping("BOUNCE")
local tankAnim = tankAG:CreateAnimation("Alpha")
tankAnim:SetFromAlpha(1)
tankAnim:SetToAlpha(0.3)
tankAnim:SetDuration(0.5)
tankAG:Play()

-- ── Healer alert frame ────────────────────────────────────────────────────────

local healerFrame = CreateFrame("Frame", "DeathAlertHealerFrame", UIParent, "BackdropTemplate")
healerFrame:SetSize(260, 60)
healerFrame:Hide()

local healerText = healerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
healerText:SetPoint("CENTER")
healerText:SetText("Healer died!")

local healerAG = healerFrame:CreateAnimationGroup()
healerAG:SetLooping("BOUNCE")
local healerAnim = healerAG:CreateAnimation("Alpha")
healerAnim:SetFromAlpha(1)
healerAnim:SetToAlpha(0.3)
healerAnim:SetDuration(0.5)
healerAG:Play()

-- ── Apply functions ───────────────────────────────────────────────────────────

function DeathAlert_ApplyTankFont()
    local path = DeathAlertCfg_Get("tankFontPath")
    local size = DeathAlertCfg_Get("tankFontSize") or 22
    local outline = DeathAlertCfg_Get("tankOutline") or ""
    tankText:SetFont(path or "Fonts\\FRIZQT__.TTF", size, outline)
end

function DeathAlert_ApplyTankColor()
    local c = DeathAlertCfg_Get("tankColor")
    tankText:SetTextColor(c.r, c.g, c.b, c.a)
end

function DeathAlert_ApplyTankMessage()
    tankText:SetText(DeathAlertCfg_Get("tankMessage") or "Tank died!")
end

function DeathAlert_ApplyTankPosition()
    tankFrame:ClearAllPoints()
    tankFrame:SetPoint("CENTER", UIParent, "CENTER",
        DeathAlertCfg_Get("tankPosX"),
        DeathAlertCfg_Get("tankPosY"))
end

function DeathAlert_SetTankUnlocked(unlocked)
    if unlocked then
        tankFrame:SetMovable(true)
        tankFrame:EnableMouse(true)
        tankFrame:RegisterForDrag("LeftButton")
        tankFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        tankFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local _, _, _, x, y = self:GetPoint()
            DeathAlertCfg_Set("tankPosX", math.floor(x))
            DeathAlertCfg_Set("tankPosY", math.floor(y))
        end)
        tankFrame:SetBackdrop({
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 10,
        })
        tankFrame:SetBackdropBorderColor(1, 1, 0, 0.8)
        tankFrame:Show()
    else
        tankFrame:SetMovable(false)
        tankFrame:EnableMouse(false)
        tankFrame:SetScript("OnDragStart", nil)
        tankFrame:SetScript("OnDragStop", nil)
        tankFrame:SetBackdrop(nil)
        tankFrame:Hide()
    end
end

function DeathAlert_IsTankUnlocked()
    return tankFrame:IsMovable()
end

function DeathAlert_SetTankTesting(val)
    tankTesting = val
end

function DeathAlert_IsTankTesting()
    return tankTesting
end

function DeathAlert_GetTankFrame()
    return tankFrame
end

function DeathAlert_ApplyHealerFont()
    local path = DeathAlertCfg_Get("healerFontPath")
    local size = DeathAlertCfg_Get("healerFontSize") or 22
    local outline = DeathAlertCfg_Get("healerOutline") or ""
    healerText:SetFont(path or "Fonts\\FRIZQT__.TTF", size, outline)
end

function DeathAlert_ApplyHealerColor()
    local c = DeathAlertCfg_Get("healerColor")
    healerText:SetTextColor(c.r, c.g, c.b, c.a)
end

function DeathAlert_ApplyHealerMessage()
    healerText:SetText(DeathAlertCfg_Get("healerMessage") or "Healer died!")
end

function DeathAlert_ApplyHealerPosition()
    healerFrame:ClearAllPoints()
    healerFrame:SetPoint("CENTER", UIParent, "CENTER",
        DeathAlertCfg_Get("healerPosX"),
        DeathAlertCfg_Get("healerPosY"))
end

function DeathAlert_SetHealerUnlocked(unlocked)
    if unlocked then
        healerFrame:SetMovable(true)
        healerFrame:EnableMouse(true)
        healerFrame:RegisterForDrag("LeftButton")
        healerFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        healerFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local _, _, _, x, y = self:GetPoint()
            DeathAlertCfg_Set("healerPosX", math.floor(x))
            DeathAlertCfg_Set("healerPosY", math.floor(y))
        end)
        healerFrame:SetBackdrop({
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 10,
        })
        healerFrame:SetBackdropBorderColor(1, 1, 0, 0.8)
        healerFrame:Show()
    else
        healerFrame:SetMovable(false)
        healerFrame:EnableMouse(false)
        healerFrame:SetScript("OnDragStart", nil)
        healerFrame:SetScript("OnDragStop", nil)
        healerFrame:SetBackdrop(nil)
        healerFrame:Hide()
    end
end

function DeathAlert_IsHealerUnlocked()
    return healerFrame:IsMovable()
end

function DeathAlert_SetHealerTesting(val)
    healerTesting = val
end

function DeathAlert_IsHealerTesting()
    return healerTesting
end

function DeathAlert_GetHealerFrame()
    return healerFrame
end

local initAlert = CreateFrame("Frame")
initAlert:RegisterEvent("PLAYER_LOGIN")
initAlert:SetScript("OnEvent", function(self)
    DeathAlert_ApplyTankFont()
    DeathAlert_ApplyTankColor()
    DeathAlert_ApplyTankMessage()
    DeathAlert_ApplyTankPosition()
    DeathAlert_ApplyHealerFont()
    DeathAlert_ApplyHealerColor()
    DeathAlert_ApplyHealerMessage()
    DeathAlert_ApplyHealerPosition()
    self:UnregisterEvent("PLAYER_LOGIN")
end)