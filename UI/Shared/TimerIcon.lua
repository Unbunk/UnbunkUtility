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
--   ti.ShowCheck()  / ti.HideCheck() — persistent green check on/off
--   ti.BlinkCheck() — flash the check briefly then hide (use on CD-ready)
--   ti.Show()
--   ti.Hide()
--   ti.IsShown()
--   ti.SetUnlocked(bool)
--   ti.IsUnlocked()
--   ti.ApplySize()
--   ti.ApplyPosition()
--   ti.ApplyFont()
--   ti.GetFrame()
--   ti.onExpire = function() ... end  -- optional callback fired when the timer expires

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
    -- Render above Blizzard's Cooldown Manager (which sits at MEDIUM strata).
    frame:SetFrameStrata("HIGH")
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
        -- The check is now driven separately (Show / Hide / Blink) by
        -- consumers, so they can flash it on CD-completion instead of
        -- leaving it permanently visible.
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

    -- Blink animation: flash the check briefly on CD-completion, then hide.
    local BLINK_TOTAL    = 1.5
    local BLINK_INTERVAL = 0.2
    local function StopBlink()
        if frame.blinkFrame then
            frame.blinkFrame:SetScript("OnUpdate", nil)
        end
        checkTex:SetAlpha(1)
    end

    function result.ShowCheck()
        StopBlink()
        checkTex:Show()
    end

    function result.HideCheck()
        StopBlink()
        checkTex:Hide()
    end

    function result.BlinkCheck()
        StopBlink()
        checkTex:Show()
        checkTex:SetAlpha(1)
        if not frame.blinkFrame then
            frame.blinkFrame = CreateFrame("Frame", nil, frame)
        end
        local elapsed = 0
        frame.blinkFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= BLINK_TOTAL then
                self:SetScript("OnUpdate", nil)
                checkTex:Hide()
                checkTex:SetAlpha(1)
                return
            end
            local phase = math.floor(elapsed / BLINK_INTERVAL) % 2
            checkTex:SetAlpha(phase == 0 and 1 or 0)
        end)
    end

    -- Pixel glow: a handful of small bright dots marching around the icon
    -- perimeter on a loop. Created lazily and reused across show/hide.
    local function EnsurePixelGlow()
        if frame.pixelGlow then return frame.pixelGlow end

        local DOT_COUNT = 8
        local DOT_SIZE  = 3
        local CYCLE     = 1.5  -- seconds for one full lap

        local glow = CreateFrame("Frame", nil, frame)
        glow:SetAllPoints(frame)
        glow:Hide()

        local dots = {}
        for i = 1, DOT_COUNT do
            local dot = glow:CreateTexture(nil, "OVERLAY")
            dot:SetSize(DOT_SIZE, DOT_SIZE)
            dot:SetColorTexture(1, 1, 0, 1)  -- yellow
            dots[i] = dot
        end

        local elapsed = 0
        glow:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            local progress = (elapsed % CYCLE) / CYCLE
            local w, h = frame:GetSize()
            if w == 0 or h == 0 then return end
            local perimeter = 2 * (w + h)
            for i, dot in ipairs(dots) do
                local p = (progress + (i - 1) / DOT_COUNT) % 1
                local d = p * perimeter
                local x, y
                if d < w then
                    x, y = d, 0
                elseif d < w + h then
                    x, y = w, -(d - w)
                elseif d < 2 * w + h then
                    x, y = w - (d - w - h), -h
                else
                    x, y = 0, -(perimeter - d)
                end
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", frame, "TOPLEFT", x, y)
            end
        end)

        frame.pixelGlow = glow
        return glow
    end

    function result.SetGlow(enabled)
        if enabled then
            EnsurePixelGlow():Show()
        elseif frame.pixelGlow then
            frame.pixelGlow:Hide()
        end
    end

    return result
end