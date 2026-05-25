-- Modules/HealerRange/UI/ConfigWindow.lua

local function CreateHealerRangePanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints(parent)

    local GAP = 12
    local totalHeight = 0
    local lastFrame = nil

    local function AddModule(moduleFrame, moduleHeight)
        moduleFrame:SetWidth(518)
        if lastFrame then
            moduleFrame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -GAP)
        else
            moduleFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        totalHeight = totalHeight + moduleHeight + GAP
        lastFrame = moduleFrame
    end

    -- ── Test Alert ────────────────────────────────────────────────────────────

    local testFrame = CreateFrame("Frame", nil, content)
    testFrame:SetHeight(30)
    local testAlertBtn = Unbunk_CreateButton({
        parent  = testFrame,
        label   = "Test Alert",
        width   = 100,
        height  = 22,
        onClick = function()
            if SlashCmdList["UNBUNKUTILITY"] then
                SlashCmdList["UNBUNKUTILITY"]("test")
            end
        end,
    })
    testAlertBtn.frame:SetPoint("TOPLEFT", testFrame, "TOPLEFT", 0, -4)
    AddModule(testFrame, 30)

    -- ── Sound picker ──────────────────────────────────────────────────────────

    local soundResult = HealerRange_CreateSoundPicker(content, LSM)
    AddModule(soundResult.frame, soundResult.height)

    -- ── Text editor ───────────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(content, {
        LSM             = LSM,
        label           = "Alert text",
        getText         = function() return HealerRangeCfg_Get("alertMessage") end,
        getFontKey      = function() return HealerRangeCfg_Get("fontKey") end,
        getFontPath     = function() return HealerRangeCfg_Get("fontPath") end,
        getFontSize     = function() return HealerRangeCfg_Get("fontSize") end,
        getColor        = function() return HealerRangeCfg_Get("color") end,
        getOutline      = function() return HealerRangeCfg_Get("outline") end,
        onTextChange    = function(txt)
            HealerRangeCfg_Set("alertMessage", txt)
            if HealerRangeAlert_ApplyMessage then HealerRangeAlert_ApplyMessage() end
        end,
        onFontChange    = function(key, path)
            HealerRangeCfg_Set("fontKey", key)
            HealerRangeCfg_Set("fontPath", path)
            if HealerRangeAlert_ApplyFont then HealerRangeAlert_ApplyFont() end
        end,
        onSizeChange    = function(size)
            HealerRangeCfg_Set("fontSize", size)
            if HealerRangeAlert_ApplyFont then HealerRangeAlert_ApplyFont() end
        end,
        onColorChange   = function(r, g, b, a)
            HealerRangeCfg_Set("color", { r=r, g=g, b=b, a=a })
            if HealerRangeAlert_ApplyColor then HealerRangeAlert_ApplyColor() end
        end,
        onOutlineChange = function(outline)
            HealerRangeCfg_Set("outline", outline)
            if HealerRangeAlert_ApplyFont then HealerRangeAlert_ApplyFont() end
        end,
    })
    AddModule(te.frame, te.height)

    -- ── Duration editor ───────────────────────────────────────────────────────

    local de = Unbunk_CreateDurationEditor({
        parent           = content,
        getDuration      = function() return HealerRangeCfg_Get("alertDuration") end,
        onDurationChange = function(val) HealerRangeCfg_Set("alertDuration", val) end,
    })
    AddModule(de.frame, de.height)

    -- ── Position editor ───────────────────────────────────────────────────────

    local pe = HealerRange_CreatePositionEditor(content, {
        label       = "Alert position (offset from screen center)",
        getX        = function() return HealerRangeCfg_Get("posX") end,
        getY        = function() return HealerRangeCfg_Get("posY") end,
        onApply     = function(x, yv)
            if x  then HealerRangeCfg_Set("posX", x)  end
            if yv then HealerRangeCfg_Set("posY", yv) end
            if HealerRangeAlert_ApplyPosition then HealerRangeAlert_ApplyPosition() end
        end,
        onUnlock    = function()
            if HealerRangeAlert_SetUnlocked then HealerRangeAlert_SetUnlocked(true) end
            print("|cffff4444[UnbunkUtility]|r Alert unlocked — drag to reposition, then /ubu lock to save.")
        end,
        onLock      = function()
            if HealerRangeAlert_SetUnlocked then HealerRangeAlert_SetUnlocked(false) end
        end,
        isUnlocked  = function()
            return HealerRangeAlert_IsUnlocked and HealerRangeAlert_IsUnlocked() or false
        end,
    })
    AddModule(pe.frame, pe.height)

    -- ── Probe status ──────────────────────────────────────────────────────────

    local probeFrame = CreateFrame("Frame", nil, content)
    probeFrame:SetHeight(50)

    local probe40Msg = probeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    probe40Msg:SetPoint("TOPLEFT", probeFrame, "TOPLEFT", 0, 0)
    probe40Msg:SetWidth(500)
    probe40Msg:SetJustifyH("LEFT")

    local probe25Msg = probeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    probe25Msg:SetPoint("TOPLEFT", probeFrame, "TOPLEFT", 0, -20)
    probe25Msg:SetWidth(500)
    probe25Msg:SetJustifyH("LEFT")

    AddModule(probeFrame, 50)

    local function RefreshProbeStatus()
        local hasSpells = LibHealerRange and LibHealerRange.availableSpellProbeCount
                          and LibHealerRange.availableSpellProbeCount > 0
        if hasSpells then
            probe40Msg:SetText("|cff00ff00Combat 40y (Druid, Monk, Paladin, Priest, Shaman) detection available via class spells.|r")
        elseif LibHealerRange and LibHealerRange.availableItemProbe40y then
            local itemId = LibHealerRange.availableItemProbe40y
            local name = C_Item.GetItemInfo(itemId) or "unknown item"
            local icon = select(10, C_Item.GetItemInfo(itemId))
            local iconStr = icon and ("|T" .. icon .. ":14:14:2:0|t ") or ""
            probe40Msg:SetText("|cff00ff00Combat 40y (Druid, Monk, Paladin, Priest, Shaman) detection available with " .. iconStr .. name .. ".|r")
        else
            probe40Msg:SetText("|cffff4444Combat 40y (Druid, Monk, Paladin, Priest, Shaman) detection unavailable — buy any Scroll on the Auction House.|r")
        end
        if LibHealerRange and LibHealerRange.availableItemProbe25y then
            local itemId = LibHealerRange.availableItemProbe25y
            local name = C_Item.GetItemInfo(itemId) or "unknown item"
            local icon = select(10, C_Item.GetItemInfo(itemId))
            local iconStr = icon and ("|T" .. icon .. ":14:14:2:0|t ") or ""
            probe25Msg:SetText("|cff00ff00Combat 25y (Evoker) detection available with " .. iconStr .. name .. ".|r")
        else
            probe25Msg:SetText("|cffff4444Combat 25y (Evoker) detection unavailable — buy any bandage on the Auction House.|r")
        end
    end

    parent:HookScript("OnShow", function()
        soundResult.Refresh()
        te.Refresh()
        pe.Refresh()
        de.Refresh()
        RefreshProbeStatus()
    end)

    local bagUpdateFrame = CreateFrame("Frame")
    bagUpdateFrame:RegisterEvent("BAG_UPDATE")
    bagUpdateFrame:SetScript("OnEvent", function()
        if parent:IsShown() then RefreshProbeStatus() end
    end)
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initHR = CreateFrame("Frame")
initHR:RegisterEvent("ADDON_LOADED")
initHR:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end

    local blizzPanel = CreateFrame("Frame")
    blizzPanel.name = "UnbunkUtility"
    local blizzTitle = blizzPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    blizzTitle:SetPoint("TOPLEFT", 16, -16)
    blizzTitle:SetText("UnbunkUtility")
    local openBtn = CreateFrame("Button", nil, blizzPanel, "UIPanelButtonTemplate")
    openBtn:SetSize(160, 22)
    openBtn:SetPoint("TOPLEFT", 16, -80)
    openBtn:SetText("Open UnbunkUtility")
    openBtn:SetScript("OnClick", function()
        UnbunkUtility.OpenWindow()
        HideUIPanel(SettingsPanel)
    end)
    local cat = Settings.RegisterCanvasLayoutCategory(blizzPanel, blizzPanel.name)
    Settings.RegisterAddOnCategory(cat)

    UnbunkUtility.RegisterModule("Healer Range", nil, CreateHealerRangePanel)

    self:UnregisterEvent("ADDON_LOADED")
end)