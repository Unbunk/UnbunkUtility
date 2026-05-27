-- Modules/PotionTracker/UI/ConfigWindow.lua

local _, ns = ...
ns.PotionTracker = ns.PotionTracker or {}
local PT = ns.PotionTracker

local function CreatePotionSection(parent, prefix)
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
        local cfg = PT.CfgGet(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = PT.CfgGet(prefix)
        if cfg then
            cfg[key] = val
            PT.CfgSet(prefix, cfg)
        end
    end

    local tracker = prefix == "health" and PT.GetHealthTracker() or PT.GetCombatTracker()

    -- ── Sound use ─────────────────────────────────────────────────────────────

    local soundUseResult = HealerRange_CreateSoundPicker(parent, LSM, {
        label          = "Sound on use",
        getSoundKey    = function() return GetCfg("soundKeyUse") end,
        getSoundEnable = function() return GetCfg("soundOnUse") end,
        onSoundSelect  = function(key, path)
            SetCfg("soundKeyUse", key)
            SetCfg("soundPathUse", path)
        end,
        onEnableToggle = function(val) SetCfg("soundOnUse", val) end,
        onTest         = function() PT.PlaySound(prefix, "soundUse") end,
    })
    soundUseResult.frame:ClearAllPoints()
    AddWidget(soundUseResult.frame, soundUseResult.height)

    -- ── Sound ready ───────────────────────────────────────────────────────────

    local soundReadyResult = HealerRange_CreateSoundPicker(parent, LSM, {
        label          = "Sound when ready",
        getSoundKey    = function() return GetCfg("soundKeyReady") end,
        getSoundEnable = function() return GetCfg("soundOnReady") end,
        onSoundSelect  = function(key, path)
            SetCfg("soundKeyReady", key)
            SetCfg("soundPathReady", path)
        end,
        onEnableToggle = function(val) SetCfg("soundOnReady", val) end,
        onTest         = function() PT.PlaySound(prefix, "soundReady") end,
    })
    soundReadyResult.frame:ClearAllPoints()
    AddWidget(soundReadyResult.frame, soundReadyResult.height)

    -- ── Show icon checkbox ────────────────────────────────────────────────────

    local showIconFrame = CreateFrame("Frame", nil, parent)
    showIconFrame:SetHeight(24)
    local showIconCb = Unbunk_CreateCheckbox({
        parent  = showIconFrame,
        label   = "Show icon",
        checked = GetCfg("showIcon") ~= false,
        onClick = function(val)
            SetCfg("showIcon", val)
            tracker.ApplyVisuals()
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
        text       = tostring(GetCfg("iconWidth") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                SetCfg("iconWidth", val)
                tracker.ApplySize()
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
        text       = tostring(GetCfg("iconHeight") or 64),
        onEnter    = function(val)
            if val and val > 0 then
                SetCfg("iconHeight", val)
                tracker.ApplySize()
            end
        end,
    })
    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

    sizeFrame:ClearAllPoints()
    AddWidget(sizeFrame, 46)

    -- ── Position editor ───────────────────────────────────────────────────────

    local peName = "PotionTracker_PE_" .. prefix
    _G[peName] = HealerRange_CreatePositionEditor(parent, {
        label      = "Icon position (offset from screen center)",
        getX       = function() return GetCfg("posX") end,
        getY       = function() return GetCfg("posY") end,
        onApply    = function(x, yv)
            if x  then SetCfg("posX", x)  end
            if yv then SetCfg("posY", yv) end
            PT.ApplyAll()
        end,
        onUnlock   = function() tracker.SetUnlocked(true) end,
        onLock     = function()
            tracker.SetUnlocked(false)
            if _G[peName] then _G[peName].Refresh() end
        end,
        isUnlocked = function() return tracker.IsUnlocked() end,
    })
    _G[peName].frame:ClearAllPoints()
    AddWidget(_G[peName].frame, _G[peName].height)

    tracker.pe = _G[peName]

    -- ── Timer text ────────────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(parent, {
        LSM          = LSM,
        label        = "Timer text",
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
            tracker.ApplyFont()
        end,
        onSizeChange = function(size)
            SetCfg("timerFontSize", size)
            tracker.ApplyFont()
        end,
        onColorChange = function(r, g, b, a)
            SetCfg("timerColor", { r=r, g=g, b=b, a=a })
            tracker.ApplyFont()
        end,
        onOutlineChange = function(outline)
            SetCfg("timerOutline", outline)
            tracker.ApplyFont()
        end,
    })
    te.frame:ClearAllPoints()
    AddWidget(te.frame, te.height)

    height = height + 16

    return height, {
        soundUse   = soundUseResult.Refresh,
        soundReady = soundReadyResult.Refresh,
        te         = te.Refresh,
        pe         = _G[peName].Refresh,
        showIcon   = function() showIconCb.SetChecked(GetCfg("showIcon") ~= false) end,
        size       = function()
            wInput.SetText(tostring(GetCfg("iconWidth") or 64))
            hInput.SetText(tostring(GetCfg("iconHeight") or 64))
        end,
    }
end

local function CreatePotionTrackerPanel(parent)
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
    local enableCb = Unbunk_CreateCheckbox({
        parent  = enableFrame,
        label   = "Enable Potion Tracker",
        checked = PT.CfgGet("enabled") ~= false,
        onClick = function(val)
            PT.CfgSet("enabled", val)
            PT.ApplyAll()
        end,
    })
    enableCb.frame:SetPoint("TOPLEFT", enableFrame, "TOPLEFT", 0, 0)
    AddSection(enableFrame)

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = Unbunk_CreateInstanceFilter({
        parent    = content,
        getConfig = function() return PT.CfgGet("instanceFilter") end,
        setConfig = function(key, val)
            local filter = PT.CfgGet("instanceFilter")
            filter[key] = val
            PT.CfgSet("instanceFilter", filter)
        end,
    })
    AddSection(iF.frame)

    -- ── Health potion section ─────────────────────────────────────────────────

    local healthCS = Unbunk_CreateCollapsibleSection({
        parent        = content,
        label         = "Health Potion",
        isChecked     = function() return PT.CfgGet("health") and PT.CfgGet("health").enabled end,
        onCheck       = function(val)
            local cfg = PT.CfgGet("health")
            cfg.enabled = val
            PT.CfgSet("health", cfg)
            PT.ApplyAll()
        end,
        createContent = function(sectionParent)
            local h, fns = CreatePotionSection(sectionParent, "health")
            allRefreshFns.health = fns
            return h
        end,
    })
    AddSection(healthCS.frame)

    -- ── Combat potion section ─────────────────────────────────────────────────

    local combatCS = Unbunk_CreateCollapsibleSection({
        parent        = content,
        label         = "Combat Potion",
        isChecked     = function() return PT.CfgGet("combat") and PT.CfgGet("combat").enabled end,
        onCheck       = function(val)
            local cfg = PT.CfgGet("combat")
            cfg.enabled = val
            PT.CfgSet("combat", cfg)
            PT.ApplyAll()
        end,
        createContent = function(sectionParent)
            local h, fns = CreatePotionSection(sectionParent, "combat")
            allRefreshFns.combat = fns
            return h
        end,
    })
    AddSection(combatCS.frame)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        enableCb.SetChecked(PT.CfgGet("enabled") ~= false)
        iF.Refresh()
        healthCS.Refresh()
        combatCS.Refresh()
        if allRefreshFns.health then
            allRefreshFns.health.soundUse()
            allRefreshFns.health.soundReady()
            allRefreshFns.health.showIcon()
            allRefreshFns.health.size()
            allRefreshFns.health.pe()
            allRefreshFns.health.te()
        end
        if allRefreshFns.combat then
            allRefreshFns.combat.soundUse()
            allRefreshFns.combat.soundReady()
            allRefreshFns.combat.showIcon()
            allRefreshFns.combat.size()
            allRefreshFns.combat.pe()
            allRefreshFns.combat.te()
        end
    end)
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initPTUI = CreateFrame("Frame")
initPTUI:RegisterEvent("ADDON_LOADED")
initPTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule("Potion Tracker", nil, CreatePotionTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)