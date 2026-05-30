-- Modules/BResTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

local SIDES = { "Left", "Right", "Above", "Below" }

local function CreateBResTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints(parent)

    local GAP = 12
    local lastFrame = nil

    -- moduleHeight is intentionally ignored: the scroll child's height is
    -- computed at runtime by Core.lua's ComputeModuleHeight (it measures child
    -- frame bottoms). The arg is kept only for call-site symmetry across modules.
    local function AddModule(moduleFrame, moduleHeight)
        moduleFrame:SetWidth(518)
        if lastFrame then
            moduleFrame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -GAP)
        else
            moduleFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        lastFrame = moduleFrame
    end

    -- ── Enable checkbox + Test button ─────────────────────────────────────────

    local enableFrame = CreateFrame("Frame", nil, content)
    enableFrame:SetHeight(28)
    local enableCb = ns.ui.CreateCheckbox({
        parent  = enableFrame,
        label   = L["Enable BRez Tracker"],
        checked = BR.CfgGet("enabled") ~= false,
        onClick = function(val)
            BR.CfgSet("enabled", val)
            BR.ApplyVisuals()
            if BR.RefreshList then BR.RefreshList() end
        end,
    })
    enableCb.frame:SetPoint("TOPLEFT", enableFrame, "TOPLEFT", 0, 0)

    local testBtn = ns.ui.CreateButton({
        parent  = enableFrame,
        label   = L["Test"],
        width   = 80,
        height  = 22,
        onClick = function() BR.RunTest(15) end,
    })
    testBtn.frame:SetPoint("LEFT", enableCb.frame, "RIGHT", 180, 0)
    AddModule(enableFrame, 28)

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = ns.ui.CreateInstanceFilter({
        parent    = content,
        getConfig = function() return BR.CfgGet("instanceFilter") end,
        setConfig = function(key, val)
            local filter = BR.CfgGet("instanceFilter")
            filter[key] = val
            BR.CfgSet("instanceFilter", filter)
        end,
    })
    AddModule(iF.frame, iF.height)

    -- ── Sound on charge regained ──────────────────────────────────────────────

    local soundResult = ns.ui.CreateSoundPicker(content, LSM, {
        label          = L["Sound on charge regained"],
        getSoundKey    = function() return BR.CfgGet("soundKeyReady") end,
        getSoundEnable = function() return BR.CfgGet("soundOnReady") end,
        onSoundSelect  = function(key, path)
            BR.CfgSet("soundKeyReady", key)
            BR.CfgSet("soundPathReady", path)
        end,
        onEnableToggle = function(val) BR.CfgSet("soundOnReady", val) end,
        onTest         = function() BR.PlaySound() end,
    })
    AddModule(soundResult.frame, soundResult.height)

    -- ── Sound on BRes used ────────────────────────────────────────────────────

    local soundUsedResult = ns.ui.CreateSoundPicker(content, LSM, {
        label          = L["Sound on BRes used"],
        getSoundKey    = function() return BR.CfgGet("soundKeyUsed") end,
        getSoundEnable = function() return BR.CfgGet("soundOnUsed") end,
        onSoundSelect  = function(key, path)
            BR.CfgSet("soundKeyUsed", key)
            BR.CfgSet("soundPathUsed", path)
        end,
        onEnableToggle = function(val) BR.CfgSet("soundOnUsed", val) end,
        onTest         = function() BR.PlaySoundUsed() end,
    })
    AddModule(soundUsedResult.frame, soundUsedResult.height)

    -- ── Show icon checkbox ────────────────────────────────────────────────────

    local showIconFrame = CreateFrame("Frame", nil, content)
    showIconFrame:SetHeight(24)
    local showIconCb = ns.ui.CreateCheckbox({
        parent  = showIconFrame,
        label   = L["Show icon"],
        checked = BR.CfgGet("showIcon") ~= false,
        onClick = function(val)
            BR.CfgSet("showIcon", val)
            BR.ApplyVisuals()
        end,
    })
    showIconCb.frame:SetPoint("TOPLEFT", showIconFrame, "TOPLEFT", 0, 0)
    AddModule(showIconFrame, 24)

    -- ── Icon size ─────────────────────────────────────────────────────────────

    local sizeFrame = CreateFrame("Frame", nil, content)
    sizeFrame:SetHeight(46)

    local sizeLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sizeLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, 0)
    sizeLbl:SetText(L["Icon size"])

    local wLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, -20)
    wLbl:SetText(L["W"])

    local wInput = ns.ui.CreateTextInput({
        parent     = sizeFrame,
        width      = 46,
        height     = 22,
        numeric    = true,
        min        = 8,
        max        = 512,
        maxLetters = 3,
        text       = tostring(BR.CfgGet("iconWidth") or 45),
        onEnter    = function(val)
            if val and val > 0 then
                BR.CfgSet("iconWidth", val)
                BR.ApplySize()
            end
        end,
    })
    wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

    local hLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
    hLbl:SetText(L["H"])

    local hInput = ns.ui.CreateTextInput({
        parent     = sizeFrame,
        width      = 46,
        height     = 22,
        numeric    = true,
        min        = 8,
        max        = 512,
        maxLetters = 3,
        text       = tostring(BR.CfgGet("iconHeight") or 45),
        onEnter    = function(val)
            if val and val > 0 then
                BR.CfgSet("iconHeight", val)
                BR.ApplySize()
            end
        end,
    })
    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

    AddModule(sizeFrame, 46)

    -- ── Position editor ───────────────────────────────────────────────────────

    BR.pe = ns.ui.CreatePositionEditor(content, {
        label      = L["Icon position (offset from screen center)"],
        getX       = function() return BR.CfgGet("posX") end,
        getY       = function() return BR.CfgGet("posY") end,
        onApply    = function(x, yv)
            if x  then BR.CfgSet("posX", x)  end
            if yv then BR.CfgSet("posY", yv) end
            BR.ApplyPosition()
        end,
        onUnlock   = function() BR.SetUnlocked(true) end,
        onLock     = function()
            BR.SetUnlocked(false)
            if BR.pe then BR.pe.Refresh() end
        end,
        isUnlocked = function() return BR.IsUnlocked() end,
    })
    AddModule(BR.pe.frame, BR.pe.height)

    -- ── Player list (optional submodule) ──────────────────────────────────────

    local listHeaderFrame = CreateFrame("Frame", nil, content)
    listHeaderFrame:SetHeight(20)
    local listHeaderLbl = listHeaderFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    listHeaderLbl:SetPoint("TOPLEFT", listHeaderFrame, "TOPLEFT", 0, 0)
    listHeaderLbl:SetText(L["Player list"])
    AddModule(listHeaderFrame, 20)

    local listEnableFrame = CreateFrame("Frame", nil, content)
    listEnableFrame:SetHeight(24)
    local listEnableCb = ns.ui.CreateCheckbox({
        parent  = listEnableFrame,
        label   = L["Enable player list"],
        checked = BR.CfgGet("listEnabled") == true,
        onClick = function(val)
            BR.CfgSet("listEnabled", val)
            if BR.RefreshList then BR.RefreshList() end
        end,
    })
    listEnableCb.frame:SetPoint("TOPLEFT", listEnableFrame, "TOPLEFT", 0, 0)
    AddModule(listEnableFrame, 24)

    -- List side dropdown (Left / Right / Above / Below)
    local listSideFrame = CreateFrame("Frame", nil, content)
    listSideFrame:SetHeight(46)
    local listSideLbl = listSideFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listSideLbl:SetPoint("TOPLEFT", listSideFrame, "TOPLEFT", 0, 0)
    listSideLbl:SetText(L["List position relative to icon"])
    local listSideAnchor = listSideFrame:CreateFontString(nil, "ARTWORK")
    listSideAnchor:SetPoint("TOPLEFT", listSideFrame, "TOPLEFT", 0, -20)
    local listSideDD = ns.ui.CreateDropdown({
        parent        = listSideFrame,
        anchorFrame   = listSideAnchor,
        width         = 120,
        itemHeight    = 20,
        visibleItems  = 4,
        getList       = function() return SIDES end,
        getCurrentKey = function() return BR.CfgGet("listSide") or "Left" end,
        onSelect      = function(name)
            BR.CfgSet("listSide", name)
            if BR.ApplyListPosition then BR.ApplyListPosition() end
            if BR.RefreshList       then BR.RefreshList()       end
        end,
    })
    listSideDD.selectedText:SetText(BR.CfgGet("listSide") or "Left")
    AddModule(listSideFrame, 46)

    -- Status side dropdown (Left / Right / Above / Below)
    local statusSideFrame = CreateFrame("Frame", nil, content)
    statusSideFrame:SetHeight(46)
    local statusSideLbl = statusSideFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statusSideLbl:SetPoint("TOPLEFT", statusSideFrame, "TOPLEFT", 0, 0)
    statusSideLbl:SetText(L["Status icon / timer position relative to name"])
    local statusSideAnchor = statusSideFrame:CreateFontString(nil, "ARTWORK")
    statusSideAnchor:SetPoint("TOPLEFT", statusSideFrame, "TOPLEFT", 0, -20)
    local statusSideDD = ns.ui.CreateDropdown({
        parent        = statusSideFrame,
        anchorFrame   = statusSideAnchor,
        width         = 120,
        itemHeight    = 20,
        visibleItems  = 4,
        getList       = function() return SIDES end,
        getCurrentKey = function() return BR.CfgGet("rowStatusSide") or "Left" end,
        onSelect      = function(name)
            BR.CfgSet("rowStatusSide", name)
            if BR.RefreshList then BR.RefreshList() end
        end,
    })
    statusSideDD.selectedText:SetText(BR.CfgGet("rowStatusSide") or "Left")
    AddModule(statusSideFrame, 46)

    -- Estimated per-player cooldown (seconds) for the list timers. See the
    -- listCooldownEstimate note in Config.lua / PlayerList.lua.
    local cdFrame = CreateFrame("Frame", nil, content)
    cdFrame:SetHeight(46)
    local cdLbl = cdFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cdLbl:SetPoint("TOPLEFT", cdFrame, "TOPLEFT", 0, 0)
    cdLbl:SetText(L["Estimated BRes cooldown (seconds)"])
    local cdInput = ns.ui.CreateTextInput({
        parent     = cdFrame,
        width      = 60,
        height     = 22,
        numeric    = true,
        min        = 1,
        max        = 3600,
        maxLetters = 4,
        text       = tostring(BR.CfgGet("listCooldownEstimate") or 600),
        onEnter    = function(val)
            if val and val > 0 then
                BR.CfgSet("listCooldownEstimate", val)
                if BR.RefreshList then BR.RefreshList() end
            end
        end,
    })
    cdInput.frame:SetPoint("TOPLEFT", cdFrame, "TOPLEFT", 0, -20)
    AddModule(cdFrame, 46)

    -- Name text editor (font / size / outline; color is class-based)
    local nameTextEditor = ns.ui.CreateTextEditor(content, {
        LSM             = LSM,
        label           = L["Player name text"],
        showText        = false,
        showFont        = true,
        showSize        = true,
        showColor       = false,
        showOutline     = true,
        getFontKey      = function() return BR.CfgGet("listFontKey") end,
        getFontPath     = function() return BR.CfgGet("listFontPath") end,
        getFontSize     = function() return BR.CfgGet("listFontSize") end,
        getOutline      = function() return BR.CfgGet("listOutline") end,
        onFontChange    = function(key, path)
            BR.CfgSet("listFontKey", key)
            BR.CfgSet("listFontPath", path)
            if BR.RefreshList then BR.RefreshList() end
        end,
        onSizeChange    = function(size)
            BR.CfgSet("listFontSize", size)
            if BR.RefreshList then BR.RefreshList() end
        end,
        onOutlineChange = function(outline)
            BR.CfgSet("listOutline", outline)
            if BR.RefreshList then BR.RefreshList() end
        end,
    })
    AddModule(nameTextEditor.frame, nameTextEditor.height)

    -- ── Timer text editor ─────────────────────────────────────────────────────

    local te = ns.ui.CreateTextEditor(content, {
        LSM          = LSM,
        label        = L["Timer text"],
        showText     = false,
        showFont     = true,
        showSize     = true,
        showColor    = true,
        showOutline  = true,
        getFontKey   = function() return BR.CfgGet("timerFontKey") end,
        getFontPath  = function() return BR.CfgGet("timerFontPath") end,
        getFontSize  = function() return BR.CfgGet("timerFontSize") end,
        getColor     = function() return BR.CfgGet("timerColor") end,
        getOutline   = function() return BR.CfgGet("timerOutline") end,
        onFontChange = function(key, path)
            BR.CfgSet("timerFontKey", key)
            BR.CfgSet("timerFontPath", path)
            BR.ApplyFont()
        end,
        onSizeChange = function(size)
            BR.CfgSet("timerFontSize", size)
            BR.ApplyFont()
        end,
        onColorChange = function(r, g, b, a)
            BR.CfgSet("timerColor", { r = r, g = g, b = b, a = a })
            BR.ApplyFont()
        end,
        onOutlineChange = function(outline)
            BR.CfgSet("timerOutline", outline)
            BR.ApplyFont()
        end,
    })
    AddModule(te.frame, te.height)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        enableCb.SetChecked(BR.CfgGet("enabled") ~= false)
        showIconCb.SetChecked(BR.CfgGet("showIcon") ~= false)
        iF.Refresh()
        soundResult.Refresh()
        soundUsedResult.Refresh()
        wInput.SetText(tostring(BR.CfgGet("iconWidth") or 45))
        hInput.SetText(tostring(BR.CfgGet("iconHeight") or 45))
        BR.pe.Refresh()
        te.Refresh()
        listEnableCb.SetChecked(BR.CfgGet("listEnabled") == true)
        listSideDD.selectedText:SetText(BR.CfgGet("listSide") or "Left")
        statusSideDD.selectedText:SetText(BR.CfgGet("rowStatusSide") or "Left")
        cdInput.SetText(tostring(BR.CfgGet("listCooldownEstimate") or 600))
        nameTextEditor.Refresh()
    end)
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initBRUI = CreateFrame("Frame")
initBRUI:RegisterEvent("ADDON_LOADED")
initBRUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["BRez Tracker"], nil, CreateBResTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
