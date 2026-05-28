-- Modules/HealthstoneTracker/UI/ConfigWindow.lua

local _, ns = ...
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

local function CreateHealthstoneTrackerPanel(parent)
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
        label   = "Enable Healthstone Tracker",
        checked = HT.CfgGet("enabled") ~= false,
        onClick = function(val)
            HT.CfgSet("enabled", val)
            HT.ApplyAll()
        end,
    })
    enableCb.frame:SetPoint("TOPLEFT", enableFrame, "TOPLEFT", 0, 0)
    AddModule(enableFrame, 24)

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = Unbunk_CreateInstanceFilter({
        parent    = content,
        getConfig = function() return HT.CfgGet("instanceFilter") end,
        setConfig = function(key, val)
            local filter = HT.CfgGet("instanceFilter")
            filter[key] = val
            HT.CfgSet("instanceFilter", filter)
        end,
    })
    AddModule(iF.frame, iF.height)

    -- ── Sound on use ──────────────────────────────────────────────────────────

    local soundUseResult = HealerRange_CreateSoundPicker(content, LSM, {
        label          = "Sound on use",
        getSoundKey    = function() return HT.CfgGet("soundKeyUse") end,
        getSoundEnable = function() return HT.CfgGet("soundOnUse") end,
        onSoundSelect  = function(key, path)
            HT.CfgSet("soundKeyUse", key)
            HT.CfgSet("soundPathUse", path)
        end,
        onEnableToggle = function(val) HT.CfgSet("soundOnUse", val) end,
        onTest         = function() HT.PlaySound("soundUse") end,
    })
    AddModule(soundUseResult.frame, soundUseResult.height)

    -- ── Sound when ready ──────────────────────────────────────────────────────

    local soundReadyResult = HealerRange_CreateSoundPicker(content, LSM, {
        label          = "Sound when ready",
        getSoundKey    = function() return HT.CfgGet("soundKeyReady") end,
        getSoundEnable = function() return HT.CfgGet("soundOnReady") end,
        onSoundSelect  = function(key, path)
            HT.CfgSet("soundKeyReady", key)
            HT.CfgSet("soundPathReady", path)
        end,
        onEnableToggle = function(val) HT.CfgSet("soundOnReady", val) end,
        onTest         = function() HT.PlaySound("soundReady") end,
    })
    AddModule(soundReadyResult.frame, soundReadyResult.height)

    -- ── Show icon checkbox ────────────────────────────────────────────────────

    local showIconFrame = CreateFrame("Frame", nil, content)
    showIconFrame:SetHeight(24)
    local showIconCb = Unbunk_CreateCheckbox({
        parent  = showIconFrame,
        label   = "Show icon",
        checked = HT.CfgGet("showIcon") ~= false,
        onClick = function(val)
            HT.CfgSet("showIcon", val)
            HT.ApplyAll()
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
        text       = tostring(HT.CfgGet("iconWidth") or 30),
        onEnter    = function(val)
            if val and val > 0 then
                HT.CfgSet("iconWidth", val)
                if tracker and tracker.ApplySize then tracker.ApplySize() end
                HT.ApplyAll()
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
        text       = tostring(HT.CfgGet("iconHeight") or 30),
        onEnter    = function(val)
            if val and val > 0 then
                HT.CfgSet("iconHeight", val)
                if tracker and tracker.ApplySize then tracker.ApplySize() end
                HT.ApplyAll()
            end
        end,
    })
    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

    AddModule(sizeFrame, 46)

    -- ── Position editor ───────────────────────────────────────────────────────

    HT.pe = HealerRange_CreatePositionEditor(content, {
        label      = "Icon position (offset from screen center)",
        getX       = function() return HT.CfgGet("posX") end,
        getY       = function() return HT.CfgGet("posY") end,
        onApply    = function(x, yv)
            if x  then HT.CfgSet("posX", x)  end
            if yv then HT.CfgSet("posY", yv) end
            HT.ApplyAll()
        end,
        onUnlock   = function() HT.SetUnlocked(true)  end,
        onLock     = function()
            HT.SetUnlocked(false)
            if HT.pe then HT.pe.Refresh() end
        end,
        isUnlocked = function() return HT.IsUnlocked() end,
    })
    AddModule(HT.pe.frame, HT.pe.height)

    -- ── Timer text editor ─────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(content, {
        LSM             = LSM,
        label           = "Timer text",
        showText        = false,
        showFont        = true,
        showSize        = true,
        showColor       = true,
        showOutline     = true,
        getFontKey      = function() return HT.CfgGet("timerFontKey") end,
        getFontPath     = function() return HT.CfgGet("timerFontPath") end,
        getFontSize     = function() return HT.CfgGet("timerFontSize") end,
        getColor        = function() return HT.CfgGet("timerColor") end,
        getOutline      = function() return HT.CfgGet("timerOutline") end,
        onFontChange    = function(key, path)
            HT.CfgSet("timerFontKey", key)
            HT.CfgSet("timerFontPath", path)
            local t = HT.GetTracker()
            if t and t.ApplyFont then t.ApplyFont() end
        end,
        onSizeChange    = function(size)
            HT.CfgSet("timerFontSize", size)
            local t = HT.GetTracker()
            if t and t.ApplyFont then t.ApplyFont() end
        end,
        onColorChange   = function(r, g, b, a)
            HT.CfgSet("timerColor", { r = r, g = g, b = b, a = a })
            local t = HT.GetTracker()
            if t and t.ApplyFont then t.ApplyFont() end
        end,
        onOutlineChange = function(outline)
            HT.CfgSet("timerOutline", outline)
            local t = HT.GetTracker()
            if t and t.ApplyFont then t.ApplyFont() end
        end,
    })
    AddModule(te.frame, te.height)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        enableCb.SetChecked(HT.CfgGet("enabled") ~= false)
        showIconCb.SetChecked(HT.CfgGet("showIcon") ~= false)
        iF.Refresh()
        soundUseResult.Refresh()
        soundReadyResult.Refresh()
        wInput.SetText(tostring(HT.CfgGet("iconWidth") or 30))
        hInput.SetText(tostring(HT.CfgGet("iconHeight") or 30))
        HT.pe.Refresh()
        te.Refresh()
    end)
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initHTUI = CreateFrame("Frame")
initHTUI:RegisterEvent("ADDON_LOADED")
initHTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule("Healthstone Tracker", nil, CreateHealthstoneTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
