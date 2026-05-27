-- Modules/BLTracker/UI/ConfigWindow.lua

local _, ns = ...
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

local function CreateBLTrackerPanel(parent)
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
        label   = "Enable BL Tracker",
        checked = BL.CfgGet("enabled") ~= false,
        onClick = function(val) BL.CfgSet("enabled", val) end,
    })
    enableCb.frame:SetPoint("TOPLEFT", enableFrame, "TOPLEFT", 0, 0)
    AddModule(enableFrame, 24)

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = Unbunk_CreateInstanceFilter({
        parent    = content,
        getConfig = function() return BL.CfgGet("instanceFilter") end,
        setConfig = function(key, val)
            local filter = BL.CfgGet("instanceFilter")
            filter[key] = val
            BL.CfgSet("instanceFilter", filter)
        end,
    })
    AddModule(iF.frame, iF.height)

    local soundBLResult = HealerRange_CreateSoundPicker(content, LSM, {
        label          = "Sound on Bloodlust",
        getSoundKey    = function() return BL.CfgGet("soundKeyBL") end,
        getSoundEnable = function() return BL.CfgGet("soundOnBL") end,
        onSoundSelect  = function(key, path)
            BL.CfgSet("soundKeyBL", key)
            BL.CfgSet("soundPathBL", path)
        end,
        onEnableToggle = function(val) BL.CfgSet("soundOnBL", val) end,
        onTest         = function() BL.PlaySound("soundPathBL") end,
    })
    AddModule(soundBLResult.frame, soundBLResult.height)

    local soundReadyResult = HealerRange_CreateSoundPicker(content, LSM, {
        label          = "Sound when Bloodlust ready",
        getSoundKey    = function() return BL.CfgGet("soundKeyReady") end,
        getSoundEnable = function() return BL.CfgGet("soundOnReady") end,
        onSoundSelect  = function(key, path)
            BL.CfgSet("soundKeyReady", key)
            BL.CfgSet("soundPathReady", path)
        end,
        onEnableToggle = function(val) BL.CfgSet("soundOnReady", val) end,
        onTest         = function() BL.PlaySound("soundPathReady") end,
    })
    AddModule(soundReadyResult.frame, soundReadyResult.height)

    -- ── Show icon checkbox ────────────────────────────────────────────────────

    local showIconFrame = CreateFrame("Frame", nil, content)
    showIconFrame:SetHeight(24)
    local showIconCb = Unbunk_CreateCheckbox({
        parent  = showIconFrame,
        label   = "Show icon",
        checked = BL.CfgGet("showIcon") ~= false,
        onClick = function(val)
            BL.CfgSet("showIcon", val)
            BL.ApplyVisuals()
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
        text       = tostring(BL.CfgGet("iconWidth") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                BL.CfgSet("iconWidth", val)
                BL.ApplySize()
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
        text       = tostring(BL.CfgGet("iconHeight") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                BL.CfgSet("iconHeight", val)
                BL.ApplySize()
            end
        end,
    })
    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

    AddModule(sizeFrame, 46)

    -- ── Position editor ───────────────────────────────────────────────────────

    BL.pe = HealerRange_CreatePositionEditor(content, {
        label      = "Icon position (offset from screen center)",
        getX       = function() return BL.CfgGet("posX") end,
        getY       = function() return BL.CfgGet("posY") end,
        onApply    = function(x, yv)
            if x  then BL.CfgSet("posX", x)  end
            if yv then BL.CfgSet("posY", yv) end
            BL.ApplyPosition()
        end,
        onUnlock   = function() BL.SetUnlocked(true) end,
        onLock     = function()
            BL.SetUnlocked(false)
            if BL.pe then BL.pe.Refresh() end
        end,
        isUnlocked = function() return BL.IsUnlocked() end,
    })
    AddModule(BL.pe.frame, BL.pe.height)

    -- ── Timer text style ──────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(content, {
        LSM          = LSM,
        label        = "Timer text",
        showText     = false,
        showFont     = true,
        showSize     = true,
        showColor    = true,
        showOutline  = true,
        getFontKey   = function() return BL.CfgGet("timerFontKey") end,
        getFontPath  = function() return BL.CfgGet("timerFontPath") end,
        getFontSize  = function() return BL.CfgGet("timerFontSize") end,
        getColor     = function() return BL.CfgGet("timerColor") end,
        getOutline   = function() return BL.CfgGet("timerOutline") end,
        onFontChange = function(key, path)
            BL.CfgSet("timerFontKey", key)
            BL.CfgSet("timerFontPath", path)
            BL.ApplyFont()
        end,
        onSizeChange = function(size)
            BL.CfgSet("timerFontSize", size)
            BL.ApplyFont()
        end,
        onColorChange = function(r, g, b, a)
            BL.CfgSet("timerColor", { r=r, g=g, b=b, a=a })
            BL.ApplyFont()
        end,
        onOutlineChange = function(outline)
            BL.CfgSet("timerOutline", outline)
            BL.ApplyFont()
        end,
    })
    AddModule(te.frame, te.height)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        enableCb.SetChecked(BL.CfgGet("enabled") ~= false)
        iF.Refresh()
        soundBLResult.Refresh()
        soundReadyResult.Refresh()
        te.Refresh()
        wInput.SetText(tostring(BL.CfgGet("iconWidth") or 64))
        hInput.SetText(tostring(BL.CfgGet("iconHeight") or 64))
        BL.pe.Refresh()
    end)
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initBLUI = CreateFrame("Frame")
initBLUI:RegisterEvent("ADDON_LOADED")
initBLUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule("BL Tracker", nil, CreateBLTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)