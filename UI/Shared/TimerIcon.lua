-- UI/Shared/TimerIcon.lua
-- Reusable icon with countdown timer widget.
--
-- Usage:
--   local ti = ns.ui.CreateTimerIcon({
--       name       = "MyTimerIcon",
--       getCfg     = function(key) return MyCfg_Get(key) end,
--       onDragStop = function(x, y) ... end,
--   })
--   ti.SetIcon(textureId)
--   ti.SetTimer(expiry, duration, color) — duration draws the CD swipe, color overrides timer text color
--   ti.ClearTimer()
--   ti.ShowCheck()  / ti.HideCheck() — persistent green check on/off
--   ti.BlinkCheck() — flash the check briefly then hide (use on CD-ready)
--   ti.SetGlow(bool) — toggle the pixel glow around the icon
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

ns.ui = ns.ui or {}

function ns.ui.CreateTimerIcon(config)
    local name      = config.name
    local getCfg    = config.getCfg
    local onDragStop = config.onDragStop

    local result   = {}
    local unlocked = false
    local expirationTime = nil
    -- Cache of the last whole-second value rendered, so the OnUpdate only
    -- reformats/SetText/SetTextColor when the displayed mm:ss actually changes
    -- (instead of every frame at 60-144 Hz). Reset whenever a timer (re)starts.
    local lastSecs = nil
    -- Urgency colouring + flash for COOLDOWN timers only (NOT active
    -- positive-buff timers, which keep their own colour — green/PI): the text
    -- turns yellow at <=15s and red at <=5s remaining, and flashes briefly each
    -- time it crosses one of those thresholds. A timer set with an explicit
    -- colour (result._timerColor) is an active buff and is left untouched.
    local URGENT_YELLOW  = 15
    local URGENT_RED     = 5
    local FLASH_DURATION = 0.6   -- seconds the text flashes at a threshold
    local flashUntil     = nil   -- GetTime() until which the text is flashing
    -- The text also grows a little at each tier for extra urgency.
    local SIZE_YELLOW    = 1.2   -- font scale at the yellow tier
    local SIZE_RED       = 1.45  -- font scale at the red tier
    local baseFontSize   = nil   -- un-scaled timer font size (set by ApplySize/ApplyFont)
    local sizeScale      = 1     -- current urgency font scale (cooldown timers only)

    -- ── Frame ─────────────────────────────────────────────────────────────────

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(64, 64)
    -- Below HIGH-strata panels (e.g. the talents window) but above Blizzard's
    -- Cooldown Manager. See ns.SetTrackerIconStrata.
    ns.SetTrackerIconStrata(frame)
    frame:Hide()

    -- ── Icon ──────────────────────────────────────────────────────────────────

    local iconTex = frame:CreateTexture(nil, "BACKGROUND")
    iconTex:SetAllPoints(frame)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local checkTex = frame:CreateTexture(nil, "OVERLAY")
    checkTex:SetTexture(ns.GREEN_CHECK_TEXTURE)
    checkTex:SetPoint("CENTER", frame, "CENTER", 0, 0)
    checkTex:Hide()

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawEdge(false)

    -- ── Border (configurable) ───────────────────────────────────────────────────
    -- Independent of the frame backdrop (which SetUnlocked uses for the yellow drag
    -- outline). Four thin edge textures on a dedicated child frame raised above the
    -- cooldown swipe so the border stays visible over it. The edges are anchored to
    -- the corners, so they auto-track icon resizes; ApplyBorder only refreshes their
    -- thickness / colour / visibility from config.
    local borderFrame = CreateFrame("Frame", nil, frame)
    borderFrame:SetAllPoints(frame)
    borderFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    local borderEdges = {}
    for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
        local t = borderFrame:CreateTexture(nil, "OVERLAY")
        t:Hide()
        borderEdges[edge] = t
    end

    -- ── Timer text ──────────────────────────────────────────────────────────────
    -- On a dedicated host frame raised ABOVE the border frame so the countdown is
    -- always readable over BOTH the cooldown swipe and the configurable border
    -- (the border sits at frame+10; this sits one level higher).
    local timerHost = CreateFrame("Frame", nil, frame)
    timerHost:SetAllPoints(frame)
    timerHost:SetFrameLevel(borderFrame:GetFrameLevel() + 1)
    local timerText = timerHost:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    timerText:Hide()

    -- ── Drag ──────────────────────────────────────────────────────────────────

    -- True when this icon is currently managed by the Cooldown Manager integration
    -- (a native-row slot, or the below-player row). When true, ns.CDMAnchor owns the
    -- position/size and the icon is not free-draggable.
    local function CDMActive()
        -- Cooldown Manager disabled in the game options -> the integration is inert,
        -- so the icon is always free (draggable, positioned by posX/posY).
        if ns.IsCDMEnabled and not ns.IsCDMEnabled() then return false end
        if not getCfg("includeInCdm") then return false end
        local dest = getCfg("cdmDest")
        if dest == "belowPlayer" then return true end
        -- Require the viewer to be present AND shown: a hidden-but-present viewer
        -- (e.g. disabled in EditMode) would otherwise strand our icon at its last
        -- pinned offset; treating it as inactive reverts the icon to free placement.
        local v = ns.GetCDMViewer and ns.GetCDMViewer(dest)
        return v ~= nil and v:IsShown()
    end
    result.CDMActive = CDMActive

    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if CDMActive() then return end  -- CDM-managed: not free-draggable
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- CDM-managed icons are positioned by ns.CDMAnchor and aren't free-draggable
        -- (OnDragStart bails too); never re-anchor one onto a free CENTER point here.
        if CDMActive() then return end
        -- Don't read GetPoint() here: StartMoving can leave the frame on a
        -- different anchor/relativePoint than the CENTER/UIParent/CENTER that
        -- ApplyPosition re-applies, so its xOfs/yOfs would be in that other anchor's
        -- space and the icon would teleport on the next locked tick. Compute the
        -- centre offset from UIParent directly (scale-normalised) and re-anchor to a
        -- single CENTER point so the saved offset and the live frame stay in sync.
        local es, ues = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local fx, fy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not (fx and ux and es > 0) then return end
        local x = math.floor((fx * es - ux * ues) / es)
        local y = math.floor((fy * es - uy * ues) / es)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", x, y)
        if onDragStop then onDragStop(x, y) end
    end)

    -- Applies the timer font at the current urgency size scale. Both ApplySize
    -- (which runs every tick) and the OnUpdate go through this, so the scaled
    -- size stays consistent — otherwise ApplySize would reset the grown text to
    -- base every tick and it would flicker.
    local function SetTimerFont()
        if not baseFontSize then return end
        local path    = ns.ResolveFontPath(getCfg("timerFontPath"), getCfg("timerFontKey"))
        local outline = getCfg("timerOutline") or ""
        timerText:SetFont(path, math.max(8, math.floor(baseFontSize * sizeScale)), outline)
    end

    -- ── OnUpdate ──────────────────────────────────────────────────────────────

    frame:SetScript("OnUpdate", function(self)
        if not expirationTime then
            timerText:Hide()
            return
        end
        local remaining = expirationTime - GetTime()
        if remaining <= 0 then
            timerText:Hide()
            timerText:SetAlpha(1)
            expirationTime = nil
            lastSecs = nil
            flashUntil = nil
            sizeScale = 1  -- next timer starts at base size, not a stale grown one
            if result.onExpire then result.onExpire() end
        else
            -- Only the whole-second value drives the displayed mm:ss, so skip
            -- the format/SetText/SetTextColor work on frames where it is unchanged.
            local total = math.floor(remaining)
            if total ~= lastSecs then
                local prev = lastSecs
                lastSecs = total
                local mins = math.floor(total / 60)
                local secs = total % 60
                timerText:SetText(string.format("%d:%02d", mins, secs))
                if result._timerColor then
                    -- Active positive buff (green / PI yellow): keep its colour
                    -- as-is — never urgency-recolour and never flash these.
                    timerText:SetTextColor(result._timerColor.r, result._timerColor.g, result._timerColor.b, 1)
                elseif total <= URGENT_RED then
                    timerText:SetTextColor(1, 0, 0, 1)        -- red <=5s
                elseif total <= URGENT_YELLOW then
                    timerText:SetTextColor(1, 0.82, 0, 1)     -- yellow <=15s
                else
                    local c = getCfg("timerColor")
                    if c then
                        timerText:SetTextColor(c.r, c.g, c.b, c.a or 1)
                    else
                        timerText:SetTextColor(1, 0, 0, 1)
                    end
                end
                -- Grow the text at each urgency tier (cooldown timers only).
                local scale = 1
                if not result._timerColor then
                    if total <= URGENT_RED then
                        scale = SIZE_RED
                    elseif total <= URGENT_YELLOW then
                        scale = SIZE_YELLOW
                    end
                end
                if scale ~= sizeScale then
                    sizeScale = scale
                    SetTimerFont()
                end
                -- Flash on crossing a threshold — cooldown timers only (active
                -- buffs keep their colour and never flash).
                if not result._timerColor and prev then
                    if (prev > URGENT_YELLOW and total <= URGENT_YELLOW)
                        or (prev > URGENT_RED and total <= URGENT_RED) then
                        flashUntil = GetTime() + FLASH_DURATION
                    end
                end
                timerText:Show()
            end
            -- Per-frame: pulse the text alpha during a flash window, then restore.
            if flashUntil then
                if GetTime() < flashUntil then
                    local on = (math.floor(GetTime() / 0.12) % 2) == 0
                    timerText:SetAlpha(on and 1 or 0.15)
                else
                    flashUntil = nil
                    timerText:SetAlpha(1)
                end
            end
        end
    end)

    -- ── API ───────────────────────────────────────────────────────────────────

    function result.SetIcon(texture)
        iconTex:SetTexture(texture)
    end

    function result.SetTimer(expiry, duration, color)
        expirationTime = expiry
        lastSecs = nil  -- force a re-render of text/color on the next OnUpdate
        flashUntil = nil
        timerText:SetAlpha(1)
        checkTex:Hide()
        if expiry and duration then
            cooldown:SetCooldown(expiry - duration, duration)
        end
        if color then
            result._timerColor = color
            sizeScale = 1  -- active buffs are never urgency-grown
            -- A coloured timer marks an *active* state (buff / lust up), so keep
            -- the icon at full colour under the rotating swipe.
            iconTex:SetDesaturated(false)
        else
            result._timerColor = nil
            -- The default (uncoloured) timer is a cooldown / unavailable state:
            -- grey the icon out behind the swipe so it reads as "not ready".
            iconTex:SetDesaturated(true)
        end
    end

    function result.ClearTimer()
        expirationTime = nil
        lastSecs = nil
        timerText:Hide()
        cooldown:Clear()
        iconTex:SetDesaturated(false)  -- restore full colour once the CD/timer ends
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

    -- NOTE: reports the RAW frame state. While unlocked, Show()/Hide() are no-ops
    -- (drag mode force-shows the frame), so this can read true even when the owner
    -- logically wants it hidden. No caller relies on it today; treat with care.
    function result.IsShown()
        return frame:IsShown()
    end

    function result.GetFrame()
        return frame
    end

    function result.ApplyFont()
        baseFontSize = getCfg("timerFontSize") or 20
        SetTimerFont()
    end

    function result.ApplyPosition()
        -- While unlocked the user is dragging the icon to place it. The owning
        -- module's 0.5s layout ticker (and ns.CDMAnchor relayouts) also call this,
        -- and a ClearAllPoints+SetPoint mid-drag fights StartMoving — the icon
        -- teleports back to its saved spot, or lands at a random offset on a short
        -- drag. Leave placement to the user until Lock; OnDragStop saves the drop
        -- position and the next locked tick re-anchors from it.
        if unlocked then return end
        -- When the Cooldown Manager integration is active, ns.CDMAnchor owns this
        -- icon's position AND size (native-row slot or below-player row); just ask
        -- for a refresh. Otherwise it's free — positioned on screen by posX/posY.
        if CDMActive() then
            if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
            return
        end
        -- Free placement: clear any fade alpha the CDM fade-along may have left on
        -- this icon (it only fades icons currently in the CDM).
        frame:SetAlpha(1)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", getCfg("posX") or 0, getCfg("posY") or 200)
    end

    -- Recompute font / check / border from the CURRENT frame size. Shared by
    -- ApplySize (config size) and SetSlotSize (native row size) so the look stays
    -- consistent whatever drives the size.
    local function ApplyDerivedSizing()
        local w, h = frame:GetSize()
        baseFontSize = math.max(10, math.floor(math.min(w, h) * 0.4))
        SetTimerFont()
        local checkSize = math.floor(math.min(w, h) * 0.6)
        checkTex:SetSize(checkSize, checkSize)
        result.ApplyBorder()
    end

    function result.ApplySize()
        -- In any CDM mode the size is owned by ns.CDMAnchor via SetSlotSize:
        -- essential/utility match the native row icons; below-player uses the
        -- account-wide cdmBelowRow size. Only a FREE icon uses its configured size.
        if not CDMActive() then
            local w = math.max(8, math.min(512, getCfg("iconWidth") or 64))
            local h = math.max(8, math.min(512, getCfg("iconHeight") or 64))
            frame:SetSize(w, h)
        end
        ApplyDerivedSizing()
    end

    -- Called by ns.CDMAnchor in slot mode to match the native row's icon size.
    function result.SetSlotSize(w, h)
        w = math.max(8, math.min(512, w or 64))
        h = math.max(8, math.min(512, h or 64))
        frame:SetSize(w, h)
        ApplyDerivedSizing()
    end

    -- Draw / refresh the configurable border from config (borderEnabled,
    -- borderColor, borderSize). Cheap; safe to call on every size / reload pass.
    function result.ApplyBorder()
        if not getCfg("borderEnabled") then
            for _, t in pairs(borderEdges) do t:Hide() end
            return
        end
        local size = math.max(1, math.min(16, getCfg("borderSize") or 1))
        local c = getCfg("borderColor") or { r = 0, g = 0, b = 0, a = 1 }
        local r, g, b, a = c.r or 0, c.g or 0, c.b or 0, c.a or 1
        for _, t in pairs(borderEdges) do t:SetColorTexture(r, g, b, a) end

        borderEdges.top:ClearAllPoints()
        borderEdges.top:SetPoint("TOPLEFT")
        borderEdges.top:SetPoint("TOPRIGHT")
        borderEdges.top:SetHeight(size)

        borderEdges.bottom:ClearAllPoints()
        borderEdges.bottom:SetPoint("BOTTOMLEFT")
        borderEdges.bottom:SetPoint("BOTTOMRIGHT")
        borderEdges.bottom:SetHeight(size)

        borderEdges.left:ClearAllPoints()
        borderEdges.left:SetPoint("TOPLEFT")
        borderEdges.left:SetPoint("BOTTOMLEFT")
        borderEdges.left:SetWidth(size)

        borderEdges.right:ClearAllPoints()
        borderEdges.right:SetPoint("TOPRIGHT")
        borderEdges.right:SetPoint("BOTTOMRIGHT")
        borderEdges.right:SetWidth(size)

        for _, t in pairs(borderEdges) do t:Show() end
    end

    function result.SetUnlocked(val)
        unlocked = val
        if val then
            frame:EnableMouse(true)
            frame:SetBackdrop({
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            frame:SetBackdropBorderColor(0.20, 0.55, 1.0, 0.8)
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

    -- In slot mode, re-pack the row when this icon shows/hides: it occupies a slot
    -- only while visible, and our own visibility changes don't trigger a native
    -- viewer relayout, so nudge ns.CDMAnchor ourselves.
    local function SlotRepack()
        if ns.CDMAnchor and CDMActive() then ns.CDMAnchor.RefreshAll() end
    end
    frame:HookScript("OnShow", SlotRepack)
    frame:HookScript("OnHide", SlotRepack)

    -- Follow the native Cooldown Manager: ns.CDMAnchor re-applies this icon's
    -- position whenever the viewer relayouts / moves; in slot mode it also sizes
    -- the icon to the native row via SetSlotSize.
    if ns.CDMAnchor then
        ns.CDMAnchor.Register({
            apply   = result.ApplyPosition,
            frame   = frame,
            getCfg  = getCfg,
            setSize = result.SetSlotSize,
        })
    end

    return result
end