-- Modules/HealerRange/UI/ConfigWindow.lua

local _, ns = ...
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

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

    -- ── Enable checkbox ───────────────────────────────────────────────────────

    local enableFrame = CreateFrame("Frame", nil, content)
    enableFrame:SetHeight(24)

    local enableCheckbox = Unbunk_CreateCheckbox({
        parent  = enableFrame,
        label   = "Enable Healer Range",
        checked = HR.CfgGet("enabled") ~= false,
        onClick = function(val)
            HR.CfgSet("enabled", val)
        end,
    })
    enableCheckbox.frame:SetPoint("TOPLEFT", enableFrame, "TOPLEFT", 0, 0)
    AddModule(enableFrame, 24)

    -- ── Probe status ──────────────────────────────────────────────────────────

    local probeFrame = CreateFrame("Frame", nil, content)
    probeFrame:SetHeight(30)

    local probeMsg = probeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    probeMsg:SetPoint("TOPLEFT", probeFrame, "TOPLEFT", 0, 0)
    probeMsg:SetWidth(500)
    probeMsg:SetJustifyH("LEFT")
    probeMsg:SetWordWrap(true)
    AddModule(probeFrame, 30)

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

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = Unbunk_CreateInstanceFilter({
        parent    = content,
        getConfig = function() return HR.CfgGet("instanceFilter") end,
        setConfig = function(key, val)
            local filter = HR.CfgGet("instanceFilter")
            filter[key] = val
            HR.CfgSet("instanceFilter", filter)
        end,
    })
    AddModule(iF.frame, iF.height)

    -- ── Icon picker ───────────────────────────────────────────────────────────

    local ip = Unbunk_CreateIconPicker({
        parent    = content,
        getConfig = function() return HR.CfgGet("icon") end,
        setConfig = function(key, val)
            local cfg = HR.CfgGet("icon")
            cfg[key] = val
            HR.CfgSet("icon", cfg)
            HR.ApplyIcon()
        end,
        icons = UNBUNK_ICONS or {},
    })
    AddModule(ip.frame, ip.height)

    -- ── Sound picker ──────────────────────────────────────────────────────────

    local soundResult = HealerRange_CreateSoundPicker(content, LSM)
    AddModule(soundResult.frame, soundResult.height)

    -- ── Text editor ───────────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(content, {
        LSM             = LSM,
        label           = "Alert text",
        getText         = function() return HR.CfgGet("alertMessage") end,
        getFontKey      = function() return HR.CfgGet("fontKey") end,
        getFontPath     = function() return HR.CfgGet("fontPath") end,
        getFontSize     = function() return HR.CfgGet("fontSize") end,
        getColor        = function() return HR.CfgGet("color") end,
        getOutline      = function() return HR.CfgGet("outline") end,
        onTextChange    = function(txt)
            HR.CfgSet("alertMessage", txt)
            if HR.ApplyMessage then HR.ApplyMessage() end
        end,
        onFontChange    = function(key, path)
            HR.CfgSet("fontKey", key)
            HR.CfgSet("fontPath", path)
            if HR.ApplyFont then HR.ApplyFont() end
        end,
        onSizeChange    = function(size)
            HR.CfgSet("fontSize", size)
            if HR.ApplyFont then HR.ApplyFont() end
        end,
        onColorChange   = function(r, g, b, a)
            HR.CfgSet("color", { r=r, g=g, b=b, a=a })
            if HR.ApplyColor then HR.ApplyColor() end
        end,
        onOutlineChange = function(outline)
            HR.CfgSet("outline", outline)
            if HR.ApplyFont then HR.ApplyFont() end
        end,
    })
    AddModule(te.frame, te.height)

    -- ── Duration editor ───────────────────────────────────────────────────────

    local de = Unbunk_CreateDurationEditor({
        parent           = content,
        getDuration      = function() return HR.CfgGet("alertDuration") end,
        onDurationChange = function(val) HR.CfgSet("alertDuration", val) end,
    })
    AddModule(de.frame, de.height)

    -- ── Position editor ───────────────────────────────────────────────────────

    HR.pe = HealerRange_CreatePositionEditor(content, {
        label       = "Alert position (offset from screen center)",
        getX        = function() return HR.CfgGet("posX") end,
        getY        = function() return HR.CfgGet("posY") end,
        onApply     = function(x, yv)
            if x  then HR.CfgSet("posX", x)  end
            if yv then HR.CfgSet("posY", yv) end
            if HR.ApplyPosition then HR.ApplyPosition() end
        end,
        onUnlock    = function()
            if HR.SetUnlocked then HR.SetUnlocked(true) end
            print("|cffff4444[UnbunkUtility]|r Alert unlocked — drag to reposition, then /ubu lock to save.")
        end,
        onLock      = function()
            if HR.SetUnlocked then HR.SetUnlocked(false) end
        end,
        isUnlocked  = function()
            return HR.IsUnlocked and HR.IsUnlocked() or false
        end,
    })
    AddModule(HR.pe.frame, HR.pe.height)

    local function RefreshProbeStatus()
        if not HR.HasCombatProbe() then
            probeMsg:SetText("|cffff4444Combat range detection unavailable — your class has no friendly spell probe usable in combat. The alert will not trigger.|r")
        else
            probeMsg:SetText("|cff00ff00Combat range detection available. Note: Evoker healers are ignored unless other healers are present in the group.|r")
        end
    end

    parent:HookScript("OnShow", function()
        enableCheckbox.SetChecked(HR.CfgGet("enabled") ~= false)
        soundResult.Refresh()
        te.Refresh()
        de.Refresh()
        if HR.pe then HR.pe.Refresh() end
        iF.Refresh()
        ip.Refresh()
        RefreshProbeStatus()
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