-- UI/Shared/TimerIcon.lua
-- Reusable icon with countdown timer widget.
--
-- Usage:
--   local ti = Unbunk_CreateTimerIcon({
--       name       = "MyTimerIcon",
--       getCfg     = function(key) return MyCfg_Get(key) end,
--       onDragStop = function(x, y) ... end,
--   })
--   ti.SetIcon(textureId)
--   ti.SetTimer(expirationTime)
--   ti.ClearTimer()
--   ti.Show()
--   ti.Hide()
--   ti.IsShown()
--   ti.SetUnlocked(bool)
--   ti.IsUnlocked()
--   ti.ApplySize()
--   ti.ApplyPosition()
--   ti.ApplyFont()
--   ti.GetFrame()
--   ti.onExpire = function() ... end  -- callback optionnel quand le timer expire

local _, ns = ...

function Unbunk_CreateTimerIcon(config)
    local name      = config.name
    local getCfg    = config.getCfg
    local onDragStop = config.onDragStop

    local result   = {}
    local unlocked = false
    local expirationTime = nil

    -- ── Frame ─────────────────────────────────────────────────────────────────

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(64, 64)
    frame:Hide()

    -- ── Icon ──────────────────────────────────────────────────────────────────

    local iconTex = frame:CreateTexture(nil, "BACKGROUND")
    iconTex:SetAllPoints(frame)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local checkTex = frame:CreateTexture(nil, "OVERLAY")
    checkTex:SetTexture("Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\GreenCheck.tga")
    checkTex:SetPoint("CENTER", frame, "CENTER", 0, 0)
    checkTex:Hide()

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawEdge(false)

    local timerText = cooldown:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
    timerText:Hide()

    -- ── Drag ──────────────────────────────────────────────────────────────────

    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        if onDragStop then onDragStop(math.floor(x), math.floor(y)) end
    end)

    -- ── OnUpdate ──────────────────────────────────────────────────────────────

    frame:SetScript("OnUpdate", function(self)
        if not expirationTime then
            timerText:Hide()
            return
        end
        local remaining = expirationTime - GetTime()
        if remaining <= 0 then
            timerText:Hide()
            expirationTime = nil
            if result.onExpire then result.onExpire() end
        else
            local mins = math.floor(remaining / 60)
            local secs = math.floor(remaining % 60)
            timerText:SetText(string.format("%d:%02d", mins, secs))
            if result._timerColor then
                timerText:SetTextColor(result._timerColor.r, result._timerColor.g, result._timerColor.b, 1)
            else
                timerText:SetTextColor(1, 0, 0, 1)
            end
            timerText:Show()
        end
    end)

    -- ── API ───────────────────────────────────────────────────────────────────

    function result.SetIcon(texture)
        iconTex:SetTexture(texture)
    end

    function result.SetTimer(expiry, duration, color)
        expirationTime = expiry
        checkTex:Hide()
        if expiry and duration then
            cooldown:SetCooldown(expiry - duration, duration)
        end
        if color then
            result._timerColor = color
        else
            result._timerColor = nil
        end
    end

    function result.ClearTimer()
        expirationTime = nil
        timerText:Hide()
        cooldown:Clear()
        checkTex:Show()
    end

    function result.Show()
        if not unlocked then frame:Show() end
    end

    function result.Hide()
        if not unlocked then frame:Hide() end
    end

    function result.IsShown()
        return frame:IsShown()
    end

    function result.GetFrame()
        return frame
    end

    function result.ApplyFont()
        local fontPath = getCfg("timerFontPath")
        local fontSize = getCfg("timerFontSize") or 20
        local outline  = getCfg("timerOutline") or ""
        timerText:SetFont(ns.ResolveFontPath(fontPath, getCfg("timerFontKey")), fontSize, outline)
    end

    function result.ApplyPosition()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER",
            getCfg("posX") or 0,
            getCfg("posY") or 200)
    end

    function result.ApplySize()
        local w = getCfg("iconWidth") or 64
        local h = getCfg("iconHeight") or 64
        frame:SetSize(w, h)
        local fontSize = math.max(10, math.floor(math.min(w, h) * 0.4))
        local fontPath = getCfg("timerFontPath")
        local outline  = getCfg("timerOutline") or ""
        timerText:SetFont(ns.ResolveFontPath(fontPath, getCfg("timerFontKey")), fontSize, outline)
        local checkSize = math.floor(math.min(w, h) * 0.6)
        checkTex:SetSize(checkSize, checkSize)
    end

    function result.SetUnlocked(val)
        unlocked = val
        if val then
            frame:EnableMouse(true)
            frame:SetBackdrop({
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 10,
            })
            frame:SetBackdropBorderColor(1, 1, 0, 0.8)
            frame:Show()
        else
            frame:EnableMouse(false)
            frame:SetBackdrop(nil)
        end
    end

    function result.IsUnlocked()
        return unlocked
    end

    function result.ShowCheck() checkTex:Show() end
    function result.HideCheck() checkTex:Hide() end

    function result.SetGlow(enabled)
        if enabled then
            frame:SetBackdrop({
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 10,
            })
            frame:SetBackdropBorderColor(1, 1, 0, 0.9)
        else
            frame:SetBackdrop(nil)
        end
    end

    return result
end