-- UI/Shared/AlertFrame.lua
-- Reusable alert frame widget.
--
-- Usage:
--   local af = Unbunk_CreateAlertFrame({
--       name       = "MyAlert",
--       getCfg     = function(key) return MyCfg_Get(key) end,
--   })
--   af.Show()
--   af.Hide()
--   af.IsShown()
--   af.ApplyFont()
--   af.ApplyColor()
--   af.ApplyPosition()
--   af.ApplyMessage()
--   af.ApplyIcon()
--   af.SetUnlocked(bool)
--   af.IsUnlocked()
--   af.SetTesting(bool)
--   af.IsTesting()
--   af.GetFrame()

local _, ns = ...

local ICON_ANCHORS = {
    TOP_LEFT      = { point = "BOTTOMLEFT",  relPoint = "TOPLEFT",     x = 0, y = 0 },
    TOP_CENTER    = { point = "BOTTOM",       relPoint = "TOP",         x = 0, y = 0 },
    TOP_RIGHT     = { point = "BOTTOMRIGHT",  relPoint = "TOPRIGHT",    x = 0, y = 0 },
    LEFT          = { point = "RIGHT",        relPoint = "LEFT",        x = 0, y = 0 },
    RIGHT         = { point = "LEFT",         relPoint = "RIGHT",       x = 0, y = 0 },
    BOTTOM_LEFT   = { point = "TOPLEFT",      relPoint = "BOTTOMLEFT",  x = 0, y = 0 },
    BOTTOM_CENTER = { point = "TOP",          relPoint = "BOTTOM",      x = 0, y = 0 },
    BOTTOM_RIGHT  = { point = "TOPRIGHT",     relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
}

function Unbunk_CreateAlertFrame(config)
    local name   = config.name
    local getCfg = config.getCfg

    local result   = {}
    local unlocked = false
    local testing  = false

    -- ── Frame ─────────────────────────────────────────────────────────────────

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(260, 60)
    frame:Hide()

    -- ── Text ──────────────────────────────────────────────────────────────────

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1)

    -- ── Animation ─────────────────────────────────────────────────────────────

    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local alphaAnim = ag:CreateAnimation("Alpha")
    alphaAnim:SetFromAlpha(1)
    alphaAnim:SetToAlpha(0.3)
    alphaAnim:SetDuration(0.5)
    ag:Play()

    -- ── Auto resize ───────────────────────────────────────────────────────────
    -- Resize to the text only when content/font changes, instead of every
    -- frame via OnUpdate.

    local function Resize()
        local w = text:GetStringWidth()
        local h = text:GetStringHeight()
        if w > 0 and h > 0 then
            frame:SetSize(w + 10, h + 10)
        end
    end

    -- ── Icon ──────────────────────────────────────────────────────────────────

    local iconTex = frame:CreateTexture(nil, "OVERLAY")
    iconTex:Hide()

    -- ── Apply functions ───────────────────────────────────────────────────────

    function result.ApplyFont()
        local fontPath = getCfg("fontPath")
        local fontSize = getCfg("fontSize") or 22
        local outline  = getCfg("outline") or ""
        text:SetFont(ns.ResolveFontPath(fontPath, getCfg("fontKey")), fontSize, outline)
        Resize()
    end

    function result.ApplyColor()
        local c = getCfg("color")
        text:SetTextColor(c.r, c.g, c.b, c.a)
    end

    function result.ApplyMessage()
        text:SetText(getCfg("alertMessage") or "Alert!")
        Resize()
    end

    function result.ApplyPosition()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER",
            getCfg("posX") or 0,
            getCfg("posY") or 100)
    end

    function result.ApplyIcon()
        local cfg = getCfg("icon")
        if not cfg or not cfg.enabled then
            iconTex:Hide()
            return
        end
        local w = cfg.width or 32
        local h = cfg.height or 32
        iconTex:SetSize(w, h)
        if cfg.useCustom and cfg.customId and tonumber(cfg.customId) then
            iconTex:SetTexture(tonumber(cfg.customId))
        elseif cfg.iconPath then
            iconTex:SetTexture(cfg.iconPath)
        else
            iconTex:Hide()
            return
        end
        local anchor = ICON_ANCHORS[cfg.position or "TOP_CENTER"]
        iconTex:ClearAllPoints()
        iconTex:SetPoint(anchor.point, frame, anchor.relPoint, anchor.x, anchor.y)
        iconTex:Show()
    end

    -- ── Unlock / drag ─────────────────────────────────────────────────────────

    function result.SetUnlocked(val)
        unlocked = val
        if val then
            frame:SetMovable(true)
            frame:EnableMouse(true)
            frame:RegisterForDrag("LeftButton")
            frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
            frame:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                local _, _, _, x, y = self:GetPoint()
                -- Persist the new position via the optional callback.
                if config.onDragStop then config.onDragStop(math.floor(x), math.floor(y)) end
            end)
            frame:SetBackdrop({
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 10,
            })
            frame:SetBackdropBorderColor(1, 1, 0, 0.8)
            frame:Show()
        else
            frame:SetMovable(false)
            frame:EnableMouse(false)
            frame:SetScript("OnDragStart", nil)
            frame:SetScript("OnDragStop", nil)
            frame:SetBackdrop(nil)
            frame:Hide()
        end
    end

    function result.IsUnlocked() return unlocked end

    function result.SetTesting(val) testing = val end
    function result.IsTesting()    return testing end

    function result.Show()
        if not unlocked then frame:Show() end
    end

    function result.Hide()
        if not unlocked then frame:Hide() end
    end

    function result.IsShown() return frame:IsShown() end
    function result.GetFrame() return frame end

    return result
end