-- Modules/PITracker/UI/ConfigWindow.lua

local _, ns = ...
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

local function CreatePITrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints(parent)

    local GAP = 12
    local lastFrame = nil

    local function AddModule(moduleFrame, moduleHeight)
        moduleFrame:SetWidth(518)
        if lastFrame then
            moduleFrame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -GAP)
        else
            moduleFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        lastFrame = moduleFrame
    end

    -- ── Enable checkbox ───────────────────────────────────────────────────────

    local enableFrame = CreateFrame("Frame", nil, content)
    enableFrame:SetHeight(24)
    local enableCb = Unbunk_CreateCheckbox({
        parent  = enableFrame,
        label   = "Enable PI Tracker",
        checked = PI.CfgGet("enabled") ~= false,
        onClick = function(val)
            PI.CfgSet("enabled", val)
            PI.ApplyVisuals()
        end,
    })
    enableCb.frame:SetPoint("TOPLEFT", enableFrame, "TOPLEFT", 0, 0)
    AddModule(enableFrame, 24)

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = Unbunk_CreateInstanceFilter({
        parent    = content,
        getConfig = function() return PI.CfgGet("instanceFilter") end,
        setConfig = function(key, val)
            local filter = PI.CfgGet("instanceFilter")
            filter[key] = val
            PI.CfgSet("instanceFilter", filter)
        end,
    })
    AddModule(iF.frame, iF.height)

    -- ── Sound PI ──────────────────────────────────────────────────────────────

    local soundResult = HealerRange_CreateSoundPicker(content, LSM, {
        label          = "Sound on PI",
        getSoundKey    = function() return PI.CfgGet("soundKeyPI") end,
        getSoundEnable = function() return PI.CfgGet("soundOnPI") end,
        onSoundSelect  = function(key, path)
            PI.CfgSet("soundKeyPI", key)
            PI.CfgSet("soundPathPI", path)
        end,
        onEnableToggle = function(val) PI.CfgSet("soundOnPI", val) end,
        onTest         = function() PI.PlaySound() end,
    })
    AddModule(soundResult.frame, soundResult.height)

    -- ── Show icon checkbox ────────────────────────────────────────────────────

    local showIconFrame = CreateFrame("Frame", nil, content)
    showIconFrame:SetHeight(24)
    local showIconCb = Unbunk_CreateCheckbox({
        parent  = showIconFrame,
        label   = "Show icon",
        checked = PI.CfgGet("showIcon") ~= false,
        onClick = function(val)
            PI.CfgSet("showIcon", val)
            PI.ApplyVisuals()
        end,
    })
    showIconCb.frame:SetPoint("TOPLEFT", showIconFrame, "TOPLEFT", 0, 0)
    AddModule(showIconFrame, 24)

    -- ── Icon size ─────────────────────────────────────────────────────────────

    local sizeFrame = CreateFrame("Frame", nil, content)
    sizeFrame:SetHeight(46)

    local sizeLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sizeLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, 0)
    sizeLbl:SetText("Icon size")

    local wLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, -20)
    wLbl:SetText("W")

    local wInput = Unbunk_CreateTextInput({
        parent     = sizeFrame,
        width      = 46,
        height     = 22,
        numeric    = true,
        maxLetters = 3,
        text       = tostring(PI.CfgGet("iconWidth") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                PI.CfgSet("iconWidth", val)
                PI.ApplySize()
            end
        end,
    })
    wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

    local hLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
    hLbl:SetText("H")

    local hInput = Unbunk_CreateTextInput({
        parent     = sizeFrame,
        width      = 46,
        height     = 22,
        numeric    = true,
        maxLetters = 3,
        text       = tostring(PI.CfgGet("iconHeight") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                PI.CfgSet("iconHeight", val)
                PI.ApplySize()
            end
        end,
    })
    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

    AddModule(sizeFrame, 46)

    -- ── Position editor ───────────────────────────────────────────────────────

    PI.pe = HealerRange_CreatePositionEditor(content, {
        label      = "Icon position (offset from screen center)",
        getX       = function() return PI.CfgGet("posX") end,
        getY       = function() return PI.CfgGet("posY") end,
        onApply    = function(x, yv)
            if x  then PI.CfgSet("posX", x)  end
            if yv then PI.CfgSet("posY", yv) end
            PI.ApplyPosition()
        end,
        onUnlock   = function() PI.SetUnlocked(true) end,
        onLock     = function()
            PI.SetUnlocked(false)
            if PI.pe then PI.pe.Refresh() end
        end,
        isUnlocked = function() return PI.IsUnlocked() end,
    })
    AddModule(PI.pe.frame, PI.pe.height)

    -- ── Timer text ────────────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(content, {
        LSM          = LSM,
        label        = "Timer text",
        showText     = false,
        showFont     = true,
        showSize     = true,
        showColor    = true,
        showOutline  = true,
        getFontKey   = function() return PI.CfgGet("timerFontKey") end,
        getFontPath  = function() return PI.CfgGet("timerFontPath") end,
        getFontSize  = function() return PI.CfgGet("timerFontSize") end,
        getColor     = function() return PI.CfgGet("timerColor") end,
        getOutline   = function() return PI.CfgGet("timerOutline") end,
        onFontChange = function(key, path)
            PI.CfgSet("timerFontKey", key)
            PI.CfgSet("timerFontPath", path)
            PI.ApplyFont()
        end,
        onSizeChange = function(size)
            PI.CfgSet("timerFontSize", size)
            PI.ApplyFont()
        end,
        onColorChange = function(r, g, b, a)
            PI.CfgSet("timerColor", { r=r, g=g, b=b, a=a })
            PI.ApplyFont()
        end,
        onOutlineChange = function(outline)
            PI.CfgSet("timerOutline", outline)
            PI.ApplyFont()
        end,
    })
    AddModule(te.frame, te.height)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        enableCb.SetChecked(PI.CfgGet("enabled") ~= false)
        showIconCb.SetChecked(PI.CfgGet("showIcon") ~= false)
        iF.Refresh()
        soundResult.Refresh()
        wInput.SetText(tostring(PI.CfgGet("iconWidth") or 64))
        hInput.SetText(tostring(PI.CfgGet("iconHeight") or 64))
        PI.pe.Refresh()
        te.Refresh()
    end)
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initPIUI = CreateFrame("Frame")
initPIUI:RegisterEvent("ADDON_LOADED")
initPIUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule("PI Tracker", nil, CreatePITrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)