-- Modules/TrinketTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.TrinketTracker = ns.TrinketTracker or {}
local TT = ns.TrinketTracker

local function CreateTrinketSection(parent, prefix)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local height = 0
    local lastFrame = nil
    local GAP = 10

    local function AddWidget(frame, frameHeight)
        frame:SetWidth(500)
        if lastFrame then
            frame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -GAP)
        else
            frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
        end
        height = height + frameHeight + GAP
        lastFrame = frame
    end

    local function GetCfg(key)
        local cfg = TT.CfgGet(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = TT.CfgGet(prefix)
        if cfg then
            cfg[key] = val
            TT.CfgSet(prefix, cfg)
        end
    end

    local tracker = prefix == "trinket1" and TT.GetTracker1() or TT.GetTracker2()

    -- ── Sound use ─────────────────────────────────────────────────────────────

    local soundUseResult = ns.ui.CreateSoundPicker(parent, LSM, {
        label          = L["Sound on use"],
        getSoundKey    = function() return GetCfg("soundKeyUse") end,
        getSoundEnable = function() return GetCfg("soundOnUse") end,
        onSoundSelect  = function(key, path)
            SetCfg("soundKeyUse", key)
            SetCfg("soundPathUse", path)
        end,
        onEnableToggle = function(val) SetCfg("soundOnUse", val) end,
        onTest         = function() TT.PlaySound(prefix, "soundUse") end,
    })
    soundUseResult.frame:ClearAllPoints()
    AddWidget(soundUseResult.frame, soundUseResult.height)

    -- ── Sound ready ───────────────────────────────────────────────────────────

    local soundReadyResult = ns.ui.CreateSoundPicker(parent, LSM, {
        label          = L["Sound when ready"],
        getSoundKey    = function() return GetCfg("soundKeyReady") end,
        getSoundEnable = function() return GetCfg("soundOnReady") end,
        onSoundSelect  = function(key, path)
            SetCfg("soundKeyReady", key)
            SetCfg("soundPathReady", path)
        end,
        onEnableToggle = function(val) SetCfg("soundOnReady", val) end,
        onTest         = function() TT.PlaySound(prefix, "soundReady") end,
    })
    soundReadyResult.frame:ClearAllPoints()
    AddWidget(soundReadyResult.frame, soundReadyResult.height)

    -- ── Show icon checkbox ────────────────────────────────────────────────────

    local showIconFrame = CreateFrame("Frame", nil, parent)
    showIconFrame:SetHeight(24)
    local showIconCb = ns.ui.CreateCheckbox({
        parent  = showIconFrame,
        label   = L["Show icon"],
        checked = GetCfg("showIcon") ~= false,
        onClick = function(val)
            SetCfg("showIcon", val)
            TT.ApplyAll()
        end,
    })
    showIconCb.frame:SetPoint("TOPLEFT", showIconFrame, "TOPLEFT", 0, 0)
    showIconFrame:ClearAllPoints()
    AddWidget(showIconFrame, 24)

    -- ── Icon size ─────────────────────────────────────────────────────────────

    local sizeFrame = CreateFrame("Frame", nil, parent)
    sizeFrame:SetHeight(46)

    local sizeLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sizeLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, 0)
    sizeLbl:SetText(L["Icon size"])

    local wLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, -20)
    wLbl:SetText("W")

    local wInput = ns.ui.CreateTextInput({
        parent     = sizeFrame,
        width      = 46,
        height     = 22,
        numeric    = true,
        min        = 8,
        max        = 512,
        maxLetters = 3,
        text       = tostring(GetCfg("iconWidth") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                SetCfg("iconWidth", val)
                if tracker then tracker.ApplySize() end
            end
        end,
    })
    wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

    local hLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
    hLbl:SetText("H")

    local hInput = ns.ui.CreateTextInput({
        parent     = sizeFrame,
        width      = 46,
        height     = 22,
        numeric    = true,
        min        = 8,
        max        = 512,
        maxLetters = 3,
        text       = tostring(GetCfg("iconHeight") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                SetCfg("iconHeight", val)
                if tracker then tracker.ApplySize() end
            end
        end,
    })
    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

    sizeFrame:ClearAllPoints()
    AddWidget(sizeFrame, 46)

    -- ── Position editor ───────────────────────────────────────────────────────

    local pe
    pe = ns.ui.CreatePositionEditor(parent, {
        label      = L["Icon position (offset from screen center)"],
        getX       = function() return GetCfg("posX") end,
        getY       = function() return GetCfg("posY") end,
        onApply    = function(x, yv)
            if x  then SetCfg("posX", x)  end
            if yv then SetCfg("posY", yv) end
            TT.ApplyAll()
        end,
        onUnlock   = function() if tracker then tracker.SetUnlocked(true) end end,
        onLock     = function()
            if tracker then tracker.SetUnlocked(false) end
            if pe then pe.Refresh() end
        end,
        isUnlocked = function() return tracker and tracker.IsUnlocked() end,
    })
    pe.frame:ClearAllPoints()
    AddWidget(pe.frame, pe.height)

    if tracker then tracker.pe = pe end

    -- ── Timer text ────────────────────────────────────────────────────────────

    local te = ns.ui.CreateTextEditor(parent, {
        LSM          = LSM,
        label        = L["Timer text"],
        showText     = false,
        showFont     = true,
        showSize     = true,
        showColor    = true,
        showOutline  = true,
        getFontKey   = function() return GetCfg("timerFontKey") end,
        getFontPath  = function() return GetCfg("timerFontPath") end,
        getFontSize  = function() return GetCfg("timerFontSize") end,
        getColor     = function() return GetCfg("timerColor") end,
        getOutline   = function() return GetCfg("timerOutline") end,
        onFontChange = function(key, path)
            SetCfg("timerFontKey", key)
            SetCfg("timerFontPath", path)
            if tracker then tracker.ApplyFont() end
        end,
        onSizeChange = function(size)
            SetCfg("timerFontSize", size)
            if tracker then tracker.ApplyFont() end
        end,
        onColorChange = function(r, g, b, a)
            SetCfg("timerColor", { r=r, g=g, b=b, a=a })
            if tracker then tracker.ApplyFont() end
        end,
        onOutlineChange = function(outline)
            SetCfg("timerOutline", outline)
            if tracker then tracker.ApplyFont() end
        end,
    })
    te.frame:ClearAllPoints()
    AddWidget(te.frame, te.height)

    height = height + 16

    return height, {
        soundUse   = soundUseResult.Refresh,
        soundReady = soundReadyResult.Refresh,
        te         = te.Refresh,
        pe         = pe.Refresh,
        showIcon   = function() showIconCb.SetChecked(GetCfg("showIcon") ~= false) end,
        size       = function()
            wInput.SetText(tostring(GetCfg("iconWidth") or 64))
            hInput.SetText(tostring(GetCfg("iconHeight") or 64))
        end,
    }
end

local function CreateTrinketTrackerPanel(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints(parent)

    local GAP = 8
    local lastFrame = nil
    local allRefreshFns = {}

    local function AddSection(frame)
        frame:SetWidth(518)
        if lastFrame then
            frame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -GAP)
        else
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        lastFrame = frame
    end

    -- ── Enable checkbox ───────────────────────────────────────────────────────

    local enableFrame = CreateFrame("Frame", nil, content)
    enableFrame:SetHeight(24)
    local enableCb = ns.ui.CreateCheckbox({
        parent  = enableFrame,
        label   = L["Enable Trinket Tracker"],
        checked = TT.CfgGet("enabled") ~= false,
        onClick = function(val)
            TT.CfgSet("enabled", val)
            TT.ApplyAll()
        end,
    })
    enableCb.frame:SetPoint("TOPLEFT", enableFrame, "TOPLEFT", 0, 0)
    AddSection(enableFrame)

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = ns.ui.CreateInstanceFilter({
        parent    = content,
        getConfig = function() return TT.CfgGet("instanceFilter") end,
        setConfig = function(key, val)
            local filter = TT.CfgGet("instanceFilter")
            filter[key] = val
            TT.CfgSet("instanceFilter", filter)
        end,
    })
    AddSection(iF.frame)

    -- ── Trinket 1 section ─────────────────────────────────────────────────────

    local trinket1CS = ns.ui.CreateCollapsibleSection({
        parent        = content,
        label         = L["Trinket 1 (slot 1)"],
        isChecked     = function() return TT.CfgGet("trinket1") and TT.CfgGet("trinket1").enabled end,
        onCheck       = function(val)
            local cfg = TT.CfgGet("trinket1")
            cfg.enabled = val
            TT.CfgSet("trinket1", cfg)
            TT.ApplyAll()
        end,
        createContent = function(sectionParent)
            local h, fns = CreateTrinketSection(sectionParent, "trinket1")
            allRefreshFns.trinket1 = fns
            return h
        end,
    })
    AddSection(trinket1CS.frame)

    -- ── Trinket 2 section ─────────────────────────────────────────────────────

    local trinket2CS = ns.ui.CreateCollapsibleSection({
        parent        = content,
        label         = L["Trinket 2 (slot 2)"],
        isChecked     = function() return TT.CfgGet("trinket2") and TT.CfgGet("trinket2").enabled end,
        onCheck       = function(val)
            local cfg = TT.CfgGet("trinket2")
            cfg.enabled = val
            TT.CfgSet("trinket2", cfg)
            TT.ApplyAll()
        end,
        createContent = function(sectionParent)
            local h, fns = CreateTrinketSection(sectionParent, "trinket2")
            allRefreshFns.trinket2 = fns
            return h
        end,
    })
    AddSection(trinket2CS.frame)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        enableCb.SetChecked(TT.CfgGet("enabled") ~= false)
        iF.Refresh()
        trinket1CS.Refresh()
        trinket2CS.Refresh()
        for _, prefix in ipairs({"trinket1", "trinket2"}) do
            local fns = allRefreshFns[prefix]
            if fns then
                fns.soundUse()
                fns.soundReady()
                fns.showIcon()
                fns.size()
                fns.pe()
                fns.te()
            end
        end
    end)
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initTTUI = CreateFrame("Frame")
initTTUI:RegisterEvent("ADDON_LOADED")
initTTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Trinket Tracker"], nil, CreateTrinketTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)