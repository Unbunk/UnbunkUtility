-- Modules/PlayerDeathAnimation/Core/PlayerDeathAnimation.lua

local _, ns = ...

local animFrame = CreateFrame("Frame", "PlayerDeathAnimFrame", UIParent, "BackdropTemplate")
animFrame:SetFrameStrata("TOOLTIP")
animFrame:Hide()

local animTex = animFrame:CreateTexture(nil, "ARTWORK")
animTex:SetAllPoints(animFrame)

local currentFrame = 0
local animTimer    = nil
local animActive   = false

local function GetCurrentAnim()
    local idx = PlayerDeathCfg_Get("animIndex") or 1
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
    animActive = false
    animFrame:Hide()
    currentFrame = 0
end

local function ApplySize()
    local w = PlayerDeathCfg_Get("animWidth") or 300
    local h = PlayerDeathCfg_Get("animHeight") or 300
    animFrame:SetSize(w, h)
    animFrame:ClearAllPoints()
    animFrame:SetPoint("CENTER", UIParent, "CENTER",
        PlayerDeathCfg_Get("posX") or 0,
        PlayerDeathCfg_Get("posY") or 0)
end

local function PlayAnimation()
    if not PlayerDeathCfg_Get("enabled") then return end
    if not PlayerDeathCfg_Get("animEnabled") then return end

    local anim = GetCurrentAnim()
    if not anim then return end

    StopAnimation()
    ApplySize()

    currentFrame = 0
    animActive = true
    animFrame:Show()

    local duration    = PlayerDeathCfg_Get("animDuration") or 3
    local fps         = PlayerDeathCfg_Get("animFPS") or 24
    local totalFrames = anim.frameCount
    local frameTime   = 1 / fps

    local loop = PlayerDeathCfg_Get("animLoop")

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

    C_Timer.After(duration, function()
        if animActive then StopAnimation() end
    end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PlayerDeathAnim_Play()     PlayAnimation()  end
function PlayerDeathAnim_Stop()     StopAnimation()  end
function PlayerDeathAnim_IsActive() return animActive end

function PlayerDeathAnim_ApplyPosition()
    animFrame:ClearAllPoints()
    animFrame:SetPoint("CENTER", UIParent, "CENTER",
        PlayerDeathCfg_Get("posX") or 0,
        PlayerDeathCfg_Get("posY") or 0)
end

function PlayerDeathAnim_ApplySize()
    ApplySize()
end

function PlayerDeathAnim_SetUnlocked(val)
    if val then
        animFrame:SetMovable(true)
        animFrame:EnableMouse(true)
        animFrame:RegisterForDrag("LeftButton")
        animFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        animFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local _, _, _, x, y = self:GetPoint()
            PlayerDeathCfg_Set("posX", math.floor(x))
            PlayerDeathCfg_Set("posY", math.floor(y))
            if PlayerDeathPE then PlayerDeathPE.Refresh() end
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

function PlayerDeathAnim_IsUnlocked()
    return animFrame:IsMovable() and animFrame:IsMouseEnabled()
end

-- ── Events ────────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_UNGHOST")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_DEAD" then
        if not PlayerDeathCfg_Get("enabled") then return end
        if PlayerDeathCfg_Get("soundEnabled") then
            PlayerDeath_PlaySound()
        end
        PlayAnimation()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        StopAnimation()
    end
end)

ns.RegisterReloadHook(function()
    PlayerDeathAnim_ApplyPosition()
    PlayerDeathAnim_ApplySize()
end)

local initAnim = CreateFrame("Frame")
initAnim:RegisterEvent("PLAYER_LOGIN")
initAnim:SetScript("OnEvent", function(self)
    PlayerDeathAnim_ApplyPosition()
    PlayerDeathAnim_ApplySize()
    self:UnregisterEvent("PLAYER_LOGIN")
end)