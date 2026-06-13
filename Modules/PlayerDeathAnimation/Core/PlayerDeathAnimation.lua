-- Modules/PlayerDeathAnimation/Core/PlayerDeathAnimation.lua

local _, ns = ...
ns.PlayerDeath = ns.PlayerDeath or {}
local PD = ns.PlayerDeath

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(PD)
AceTimer:Embed(PD)

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
    currentFrame = 0
    if PD.IsUnlocked() then
        -- Keep the positioning preview up (static frame 0) rather than hiding the
        -- frame the user is still placing (e.g. a death/revive mid-config).
        local anim = GetCurrentAnim()
        if anim then animTex:SetTexture(anim.path .. "0.tga") end
        animFrame:Show()
    else
        animFrame:Hide()
    end
end

local function ApplySize()
    -- CfgGet already falls back to DEFAULTS (250 / 100); the `or` is just a
    -- belt-and-suspenders kept in sync with those defaults.
    local w = PD.CfgGet("animWidth") or 250
    local h = PD.CfgGet("animHeight") or 100
    animFrame:SetSize(w, h)
    -- Don't re-anchor while the user is dragging the frame (unlocked): SetSize keeps
    -- the CENTER anchor, so the size still updates without fighting the drag.
    if PD.IsUnlocked() then return end
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
    local fps         = PD.CfgGet("animFPS") or 16
    -- `or 1` guards against a future UNBUNK_ANIMATIONS entry lacking frameCount
    -- (currentFrame >= nil would error every frame).
    local totalFrames = anim.frameCount or 1
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
    -- end-of-animation timer (via StopAnimation) instead of being cut short. When
    -- NOT looping, the timer lasts at least one full play-through (totalFrames/fps)
    -- so a short animDuration never cuts off the final frames.
    local stopAfter = loop and duration or math.max(duration, totalFrames / fps)
    stopTimer = C_Timer.NewTimer(stopAfter, function()
        stopTimer = nil
        if animActive then StopAnimation() end
    end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PD.Play()     PlayAnimation()  end
function PD.Stop()     StopAnimation()  end
function PD.IsActive() return animActive end

function PD.ApplyPosition()
    if PD.IsUnlocked() then return end  -- the drag owns placement while unlocked
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
            -- Compute the centre offset from UIParent directly + re-anchor to a single
            -- CENTER point: StartMoving can leave the frame on a different anchor, so
            -- GetPoint()'s offsets wouldn't match ApplyPosition's CENTER re-anchor and
            -- it would jump on the next reapply (death / reload / size edit).
            local es, ues = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local fx, fy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if not (fx and ux and es > 0) then return end
            local x = math.floor((fx * es - ux * ues) / es)
            local y = math.floor((fy * es - uy * ues) / es)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
            PD.CfgSet("posX", x)
            PD.CfgSet("posY", y)
            if PD.pe then PD.pe.Refresh() end
        end)
        animFrame:SetBackdrop({
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        animFrame:SetBackdropBorderColor(0.20, 0.55, 1.0, 0.8)
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

PD:RegisterEvent("PLAYER_DEAD", function(event)
    if not PD.CfgGet("enabled") then return end
    if PD.CfgGet("soundEnabled") then
        PD.PlaySound()
    end
    PlayAnimation()
end)

local function OnPlayerRevive(event)
    -- PLAYER_ALIVE also fires when the player Releases Spirit (corpse -> ghost), not
    -- only on a real resurrection. Skip that case (still a ghost) so a release does
    -- not cut the animation short — the stopTimer ends it at its configured duration.
    if event == "PLAYER_ALIVE" and UnitIsGhost("player") then return end
    StopAnimation()
end
PD:RegisterEvent("PLAYER_ALIVE", OnPlayerRevive)
PD:RegisterEvent("PLAYER_UNGHOST", OnPlayerRevive)

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
