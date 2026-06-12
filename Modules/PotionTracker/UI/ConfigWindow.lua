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

    -- ── Potion picker (scans the player's bags) ───────────────────────────────

    local potionFrame = CreateFrame("Frame", nil, parent)
    potionFrame:SetHeight(74)

    local potionLbl = potionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    potionLbl:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 0, 0)
    potionLbl:SetText("Potion")

    local potionAnchor = potionFrame:CreateFontString(nil, "ARTWORK")
    potionAnchor:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 0, -20)

    -- Build "|T<icon>:16|t Name" so each dropdown row shows its potion icon
    -- next to the name. The same markup is used as the unique identifier for
    -- both the displayed list and the current-selection comparison.
    local function FormatDisplay(itemID, name)
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return string.format("|T%d:16|t %s", icon, name)
        end
        return name
    end

    -- Displays the potion actually being tracked right now (the resolver's
    -- pick, which falls back when the configured one is out of bags).
    local function ActivePotionDisplay()
        local id = PT.GetActiveItemId(prefix)
        if not id then return "None" end
        local name = C_Item.GetItemNameByID(id) or tostring(id)
        return FormatDisplay(id, name)
    end

    -- displayString -> itemID, rebuilt on every getList() so onSelect can
    -- recover the item ID without re-scanning.
    local displayToId = {}

    local potionDD
    potionDD = HealerRange_CreateDropdown({
        parent        = potionFrame,
        anchorFrame   = potionAnchor,
        width         = 240,
        itemHeight    = 20,
        visibleItems  = 8,
        getList = function()
            -- Only show what is actually in the bags for this category; no
            -- phantom entry for a configured potion that has run out.
            displayToId = {}
            local list = {}
            for _, p in ipairs(PT.GetBagPotions(prefix)) do
                local display = FormatDisplay(p.id, p.name)
                table.insert(list, display)
                displayToId[display] = p.id
            end
            return list
        end,
        getCurrentKey = ActivePotionDisplay,
        onSelect = function(display)
            local id = displayToId[display]
            if not id then return end
            SetCfg("itemId", id)
            local _, spellID = C_Item.GetItemSpell(id)
            SetCfg("spellId", spellID)
            potionDD.selectedText:SetText(display)
            PT.ApplyAll()
        end,
    })
    potionDD.selectedText:SetText(ActivePotionDisplay())

    -- ── Favorite potion picker (curated list) ─────────────────────────────────

    local favLbl = potionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    favLbl:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 260, 0)
    favLbl:SetText("Favorite potion")

    local favAnchor = potionFrame:CreateFontString(nil, "ARTWORK")
    favAnchor:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 260, -20)

    local function FavoriteDisplay()
        local id = GetCfg("favoriteId")
        if not id then return "None" end
        local name = C_Item.GetItemNameByID(id) or ("[" .. id .. "]")
        return FormatDisplay(id, name)
    end

    local favDisplayToId = {}

    local favoriteDD
    favoriteDD = HealerRange_CreateDropdown({
        parent        = potionFrame,
        anchorFrame   = favAnchor,
        width         = 200,
        itemHeight    = 20,
        visibleItems  = 8,
        getList = function()
            favDisplayToId = {}
            local list = {}
            for _, p in ipairs(PT.GetFavoritePotions(prefix)) do
                local display = FormatDisplay(p.id, p.name)
                table.insert(list, display)
                favDisplayToId[display] = p.id
            end
            return list
        end,
        getCurrentKey = FavoriteDisplay,
        onSelect = function(display)
            local id = favDisplayToId[display]
            if not id then return end
            SetCfg("favoriteId", id)
            favoriteDD.selectedText:SetText(display)
            PT.ApplyAll()
        end,
    })
    favoriteDD.selectedText:SetText(FavoriteDisplay())

    -- Favorite enable checkbox, sitting below the dropdown.
    local favCb = ns.ui.CreateCheckbox({
        parent  = potionFrame,
        label   = "Use favorite when in bag",
        checked = GetCfg("favoriteEnabled") == true,
        onClick = function(val)
            SetCfg("favoriteEnabled", val)
            PT.ApplyAll()
        end,
    })
    favCb.frame:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 260, -46)

    AddWidget(potionFrame, 74)

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
    local showIconCb = ns.ui.CreateCheckbox({
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

    local wInput = ns.ui.CreateTextInput({
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

    local hInput = ns.ui.CreateTextInput({
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

    -- ── Show stack count checkbox ────────────────────────────────────────────

    local showStackFrame = CreateFrame("Frame", nil, parent)
    showStackFrame:SetHeight(24)
    local showStackCb = ns.ui.CreateCheckbox({
        parent  = showStackFrame,
        label   = "Show stack count below icon",
        checked = GetCfg("showStack") ~= false,
        onClick = function(val)
            SetCfg("showStack", val)
            PT.ApplyStackVisuals(prefix, tracker)
        end,
    })
    showStackCb.frame:SetPoint("TOPLEFT", showStackFrame, "TOPLEFT", 0, 0)
    showStackFrame:ClearAllPoints()
    AddWidget(showStackFrame, 24)

    -- ── Stack text ────────────────────────────────────────────────────────────

    local ste = HealerRange_CreateTextEditor(parent, {
        LSM          = LSM,
        label        = "Stack text",
        showText     = false,
        showFont     = true,
        showSize     = true,
        showColor    = true,
        showOutline  = true,
        getFontKey   = function() return GetCfg("stackFontKey") end,
        getFontPath  = function() return GetCfg("stackFontPath") end,
        getFontSize  = function() return GetCfg("stackFontSize") end,
        getColor     = function() return GetCfg("stackColor") end,
        getOutline   = function() return GetCfg("stackOutline") end,
        onFontChange = function(key, path)
            SetCfg("stackFontKey", key)
            SetCfg("stackFontPath", path)
            PT.ApplyStackVisuals(prefix, tracker)
        end,
        onSizeChange = function(size)
            SetCfg("stackFontSize", size)
            PT.ApplyStackVisuals(prefix, tracker)
        end,
        onColorChange = function(r, g, b, a)
            SetCfg("stackColor", { r=r, g=g, b=b, a=a })
            PT.ApplyStackVisuals(prefix, tracker)
        end,
        onOutlineChange = function(outline)
            SetCfg("stackOutline", outline)
            PT.ApplyStackVisuals(prefix, tracker)
        end,
    })
    ste.frame:ClearAllPoints()
    AddWidget(ste.frame, ste.height)

    height = height + 16

    return height, {
        soundUse   = soundUseResult.Refresh,
        soundReady = soundReadyResult.Refresh,
        te         = te.Refresh,
        ste        = ste.Refresh,
        pe         = _G[peName].Refresh,
        showIcon   = function() showIconCb.SetChecked(GetCfg("showIcon") ~= false) end,
        showStack  = function() showStackCb.SetChecked(GetCfg("showStack") ~= false) end,
        size       = function()
            wInput.SetText(tostring(GetCfg("iconWidth") or 64))
            hInput.SetText(tostring(GetCfg("iconHeight") or 64))
        end,
        potion     = function()
            potionDD.selectedText:SetText(ActivePotionDisplay())
            favoriteDD.selectedText:SetText(FavoriteDisplay())
            favCb.SetChecked(GetCfg("favoriteEnabled") == true)
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
    local enableCb = ns.ui.CreateCheckbox({
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

    local iF = ns.ui.CreateInstanceFilter({
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

    local healthCS = ns.ui.CreateCollapsibleSection({
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

    local combatCS = ns.ui.CreateCollapsibleSection({
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
            allRefreshFns.health.showStack()
            allRefreshFns.health.size()
            allRefreshFns.health.pe()
            allRefreshFns.health.te()
            allRefreshFns.health.ste()
            allRefreshFns.health.potion()
        end
        if allRefreshFns.combat then
            allRefreshFns.combat.soundUse()
            allRefreshFns.combat.soundReady()
            allRefreshFns.combat.showIcon()
            allRefreshFns.combat.showStack()
            allRefreshFns.combat.size()
            allRefreshFns.combat.pe()
            allRefreshFns.combat.te()
            allRefreshFns.combat.ste()
            allRefreshFns.combat.potion()
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