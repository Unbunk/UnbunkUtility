-- Modules/HealerRange/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
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

    local enableCheckbox = ns.ui.CreateCheckbox({
        parent  = enableFrame,
        label   = L["Enable Healer Range"],
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

    -- ── Test Alert button + test duration input ──────────────────────────────

    local testFrame = CreateFrame("Frame", nil, content)
    testFrame:SetHeight(30)

    local testAlertBtn = ns.ui.CreateButton({
        parent  = testFrame,
        label   = L["Test Alert"],
        width   = 100,
        height  = 22,
        onClick = function()
            -- Cancel any in-flight test so a second click doesn't let the first
            -- timer fire mid-test (which would SetTesting(false)/hide early).
            if HR.testTimer then HR.testTimer:Cancel() end
            HR.SetTesting(true)
            HR.GetFrame():Show()
            HR.PlaySound()
            local duration = HR.CfgGet("alertDuration") or 5
            HR.testTimer = C_Timer.NewTimer(duration, function()
                HR.testTimer = nil
                HR.SetTesting(false)
                if not HR.IsUnlocked() then
                    HR.GetFrame():Hide()
                end
            end)
        end,
    })
    testAlertBtn.frame:SetPoint("TOPLEFT", testFrame, "TOPLEFT", 0, -4)

    local durLbl = testFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    durLbl:SetPoint("LEFT", testAlertBtn.frame, "RIGHT", 16, 0)
    durLbl:SetText(L["Duration"])

    local durMinusBtn = ns.ui.CreateButton({
        parent  = testFrame,
        label   = "-",
        width   = 22,
        height  = 22,
    })
    durMinusBtn.frame:SetPoint("LEFT", durLbl, "RIGHT", 6, 0)

    -- Forward-declared so the onEnter closure below can reflect the clamped
    -- value back into the edit box (assigned just after durInput is created).
    local durBox

    local durInput = ns.ui.CreateTextInput({
        parent     = testFrame,
        width      = 40,
        height     = 22,
        numeric    = true,
        maxLetters = 3,
        text       = tostring(HR.CfgGet("alertDuration") or 5),
        onEnter    = function(val)
            -- Clamp typed input to the same [1,60] range the +/- buttons enforce.
            if val and val > 0 then
                val = math.min(60, math.max(1, val))
                HR.CfgSet("alertDuration", val)
                if durBox then durBox:SetText(tostring(val)) end
            end
        end,
    })
    durInput.frame:SetPoint("LEFT", durMinusBtn.frame, "RIGHT", 4, 0)
    durBox = durInput.editBox

    local durPlusBtn = ns.ui.CreateButton({
        parent  = testFrame,
        label   = "+",
        width   = 22,
        height  = 22,
    })
    durPlusBtn.frame:SetPoint("LEFT", durBox, "RIGHT", 4, 0)

    durMinusBtn.frame:SetScript("OnClick", function()
        local v = tonumber(durBox:GetText()) or HR.CfgGet("alertDuration") or 5
        v = math.max(1, v - 1)
        durBox:SetText(tostring(v))
        HR.CfgSet("alertDuration", v)
    end)
    durPlusBtn.frame:SetScript("OnClick", function()
        local v = tonumber(durBox:GetText()) or HR.CfgGet("alertDuration") or 5
        v = math.min(60, v + 1)
        durBox:SetText(tostring(v))
        HR.CfgSet("alertDuration", v)
    end)

    local durSecLbl = testFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    durSecLbl:SetPoint("LEFT", durPlusBtn.frame, "RIGHT", 6, 0)
    durSecLbl:SetText(L["sec"])

    AddModule(testFrame, 30)

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = ns.ui.CreateInstanceFilter({
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

    local ip = ns.ui.CreateIconPicker({
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

    local soundResult = ns.ui.CreateSoundPicker(content, LSM)
    AddModule(soundResult.frame, soundResult.height)

    -- ── Text editor ───────────────────────────────────────────────────────────

    local te = ns.ui.CreateTextEditor(content, {
        LSM             = LSM,
        label           = L["Alert text"],
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

    -- ── Position editor ───────────────────────────────────────────────────────

    HR.pe = ns.ui.CreatePositionEditor(content, {
        label       = L["Alert position (offset from screen center)"],
        getX        = function() return HR.CfgGet("posX") end,
        getY        = function() return HR.CfgGet("posY") end,
        onApply     = function(x, yv)
            if x  then HR.CfgSet("posX", x)  end
            if yv then HR.CfgSet("posY", yv) end
            if HR.ApplyPosition then HR.ApplyPosition() end
        end,
        onUnlock    = function()
            if HR.SetUnlocked then HR.SetUnlocked(true) end
            print(L["|cffff4444[UnbunkUtility]|r Alert unlocked — drag to reposition, then click Lock to save."])
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
            probeMsg:SetText(L["|cffff4444Combat range detection unavailable — your class has no friendly spell probe usable in combat. The alert will not trigger.|r"])
        else
            probeMsg:SetText(L["|cff00ff00Combat range detection available. Note: Evoker healers are ignored unless other healers are present in the group.|r"])
        end
    end

    parent:HookScript("OnShow", function()
        enableCheckbox.SetChecked(HR.CfgGet("enabled") ~= false)
        soundResult.Refresh()
        te.Refresh()
        durBox:SetText(tostring(HR.CfgGet("alertDuration") or 5))
        if HR.pe then HR.pe.Refresh() end
        iF.Refresh()
        ip.Refresh()
        RefreshProbeStatus()
    end)
end

-- ── Registration ──────────────────────────────────────────────────────────────
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
    openBtn:SetText(L["Open UnbunkUtility"])
    openBtn:SetScript("OnClick", function()
        UnbunkUtility.OpenWindow()
        HideUIPanel(SettingsPanel)
    end)
    local cat = Settings.RegisterCanvasLayoutCategory(blizzPanel, blizzPanel.name)
    Settings.RegisterAddOnCategory(cat)

    UnbunkUtility.RegisterModule(L["Healer Range"], nil, CreateHealerRangePanel)

    self:UnregisterEvent("ADDON_LOADED")
end)