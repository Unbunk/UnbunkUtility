-- Modules/PlayerDeathAnimation/Core/PlayerDeathAnimation.lua

local _, ns = ...
ns.PlayerDeath = ns.PlayerDeath or {}
local PD = ns.PlayerDeath

local animFrame = CreateFrame("Frame", "PlayerDeathAnimFrame", UIParent, "BackdropTemplate")
animFrame:SetFrameStrata("TOOLTIP")
animFrame:Hide()

local animTex = animFrame:CreateTexture(nil, "ARTWORK")
animTex:SetAllPoints(animFrame)

local currentFrame = 0
local animTimer    = nil
local stopTimer    = nil
local animActive   = false

local function GetCurrentAnim()
    local idx = PD.CfgGet("animIndex") or 1
    if UNBUNK_ANIMATIONS and UNBUNK_ANIMATIONS[idx] then
        return UNBUNK_ANIMATIONS[idx]
    end
    return UNBUNK_ANIMATIONS and UNBUNK_ANIMATIONS[1]
end

local function StopAnimation()
    if animTimer then
        animTimer:Cancel()
        animTimer = nil
    end
    if stopTimer then
        stopTimer:Cancel()
        stopTimer = nil
    end
    animActive = false
    animFrame:Hide()
    currentFrame = 0
end

local function ApplySize()
    local w = PD.CfgGet("animWidth") or 300
    local h = PD.CfgGet("animHeight") or 300
    animFrame:SetSize(w, h)
    animFrame:ClearAllPoints()
    animFrame:SetPoint("CENTER", UIParent, "CENTER",
        PD.CfgGet("posX") or 0,
        PD.CfgGet("posY") or 0)
end

local function PlayAnimation()
    if not PD.CfgGet("enabled") then return end
    if not PD.CfgGet("animEnabled") then return end

    local anim = GetCurrentAnim()
    if not anim then return end

    StopAnimation()
    ApplySize()

    currentFrame = 0
    animActive = true
    animFrame:Show()

    local duration    = PD.CfgGet("animDuration") or 3
    local fps         = PD.CfgGet("animFPS") or 24
    local totalFrames = anim.frameCount
    local frameTime   = 1 / fps

    local loop = PD.CfgGet("animLoop")

    local function ShowNextFrame()
        if not animActive then return end
        if currentFrame >= totalFrames then
            if loop then
                currentFrame = 0
            else
                animTex:SetTexture(anim.path .. (totalFrames - 1) .. ".tga")
                return
            end
        end
        animTex:SetTexture(anim.path .. currentFrame .. ".tga")
        currentFrame = currentFrame + 1
        animTimer = C_Timer.NewTimer(frameTime, ShowNextFrame)
    end

    ShowNextFrame()

    -- Stored handle so a restarted animation cancels the previous run's
    -- end-of-animation timer (via StopAnimation) instead of being cut short.
    stopTimer = C_Timer.NewTimer(duration, function()
        stopTimer = nil
        if animActive then StopAnimation() end
    end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PD.Play()     PlayAnimation()  end
function PD.Stop()     StopAnimation()  end
function PD.IsActive() return animActive end

function PD.ApplyPosition()
    animFrame:ClearAllPoints()
    animFrame:SetPoint("CENTER", UIParent, "CENTER",
        PD.CfgGet("posX") or 0,
        PD.CfgGet("posY") or 0)
end

function PD.ApplySize()
    ApplySize()
end

function PD.SetUnlocked(val)
    if val then
        animFrame:SetMovable(true)
        animFrame:EnableMouse(true)
        animFrame:RegisterForDrag("LeftButton")
        animFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        animFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local _, _, _, x, y = self:GetPoint()
            PD.CfgSet("posX", math.floor(x))
            PD.CfgSet("posY", math.floor(y))
            if PD.pe then PD.pe.Refresh() end
        end)
        animFrame:SetBackdrop({
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 10,
        })
        animFrame:SetBackdropBorderColor(1, 1, 0, 0.8)
        local anim = GetCurrentAnim()
        if anim then
            animTex:SetTexture(anim.path .. "0.tga")
        end
        animFrame:Show()
    else
        animFrame:SetMovable(false)
        animFrame:EnableMouse(false)
        animFrame:SetScript("OnDragStart", nil)
        animFrame:SetScript("OnDragStop", nil)
        animFrame:SetBackdrop(nil)
        animFrame:Hide()
    end
end

function PD.IsUnlocked()
    return animFrame:IsMovable() and animFrame:IsMouseEnabled()
end

-- ── Events ────────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_UNGHOST")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_DEAD" then
        if not PD.CfgGet("enabled") then return end
        if PD.CfgGet("soundEnabled") then
            PD.PlaySound()
        end
        PlayAnimation()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        StopAnimation()
    end
end)

ns.RegisterReloadHook(function()
    PD.ApplyPosition()
    PD.ApplySize()
end)

local initAnim = CreateFrame("Frame")
initAnim:RegisterEvent("PLAYER_LOGIN")
initAnim:SetScript("OnEvent", function(self)
    PD.ApplyPosition()
    PD.ApplySize()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
