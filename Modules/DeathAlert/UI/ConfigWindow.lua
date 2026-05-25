-- Modules/DeathAlert/UI/ConfigWindow.lua

local function CreateAlertSection(parent, prefix)
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

    -- ── Test button ───────────────────────────────────────────────────────────

    local testFrame = CreateFrame("Frame", nil, parent)
    testFrame:SetHeight(26)

    local testBtnWidget = Unbunk_CreateButton({
        parent  = testFrame,
        label   = "Test Alert",
        width   = 100,
        height  = 22,
        onClick = function()
            local getFrame = prefix == "tank" and DeathAlert_GetTankFrame or DeathAlert_GetHealerFrame
            local setTest  = prefix == "tank" and DeathAlert_SetTankTesting or DeathAlert_SetHealerTesting
            setTest(true)
            getFrame():Show()
            DeathAlertPlaySound(prefix)
            C_Timer.After(5, function()
                setTest(false)
                getFrame():Hide()
            end)
        end,
    })
    testBtnWidget.frame:SetPoint("TOPLEFT", testFrame, "TOPLEFT", 0, -2)
    AddWidget(testFrame, 26)

    -- ── Sound picker ──────────────────────────────────────────────────────────

    local soundResult = HealerRange_CreateSoundPicker(parent, LSM, {
        getSoundKey    = function() return DeathAlertCfg_Get(prefix .. "SoundKey") end,
        getSoundEnable = function() return DeathAlertCfg_Get(prefix .. "EnableSound") end,
        onSoundSelect  = function(key, path)
            DeathAlertCfg_Set(prefix .. "SoundKey", key)
            DeathAlertCfg_Set(prefix .. "SoundPath", path)
        end,
        onEnableToggle = function(val)
            DeathAlertCfg_Set(prefix .. "EnableSound", val)
        end,
        onTest = function()
            DeathAlertPlaySound(prefix)
        end,
    })
    soundResult.frame:ClearAllPoints()
    AddWidget(soundResult.frame, soundResult.height)

    -- ── Text editor ───────────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(parent, {
        LSM             = LSM,
        label           = "Alert text",
        getText         = function() return DeathAlertCfg_Get(prefix .. "Message") end,
        getFontKey      = function() return DeathAlertCfg_Get(prefix .. "FontKey") end,
        getFontPath     = function() return DeathAlertCfg_Get(prefix .. "FontPath") end,
        getFontSize     = function() return DeathAlertCfg_Get(prefix .. "FontSize") end,
        getColor        = function() return DeathAlertCfg_Get(prefix .. "Color") end,
        getOutline      = function() return DeathAlertCfg_Get(prefix .. "Outline") end,
        onTextChange    = function(txt)
            DeathAlertCfg_Set(prefix .. "Message", txt)
            if prefix == "tank" then DeathAlert_ApplyTankMessage()
            else DeathAlert_ApplyHealerMessage() end
        end,
        onFontChange    = function(key, path)
            DeathAlertCfg_Set(prefix .. "FontKey", key)
            DeathAlertCfg_Set(prefix .. "FontPath", path)
            if prefix == "tank" then DeathAlert_ApplyTankFont()
            else DeathAlert_ApplyHealerFont() end
        end,
        onSizeChange    = function(size)
            DeathAlertCfg_Set(prefix .. "FontSize", size)
            if prefix == "tank" then DeathAlert_ApplyTankFont()
            else DeathAlert_ApplyHealerFont() end
        end,
        onColorChange   = function(r, g, b, a)
            DeathAlertCfg_Set(prefix .. "Color", { r=r, g=g, b=b, a=a })
            if prefix == "tank" then DeathAlert_ApplyTankColor()
            else DeathAlert_ApplyHealerColor() end
        end,
        onOutlineChange = function(outline)
            DeathAlertCfg_Set(prefix .. "Outline", outline)
            if prefix == "tank" then DeathAlert_ApplyTankFont()
            else DeathAlert_ApplyHealerFont() end
        end,
    })
    te.frame:ClearAllPoints()
    AddWidget(te.frame, te.height)

    -- ── Position editor ───────────────────────────────────────────────────────

    local pe = HealerRange_CreatePositionEditor(parent, {
        label      = "Alert position (offset from screen center)",
        getX       = function() return DeathAlertCfg_Get(prefix .. "PosX") end,
        getY       = function() return DeathAlertCfg_Get(prefix .. "PosY") end,
        onApply    = function(x, yv)
            if x  then DeathAlertCfg_Set(prefix .. "PosX", x)  end
            if yv then DeathAlertCfg_Set(prefix .. "PosY", yv) end
            if prefix == "tank" then DeathAlert_ApplyTankPosition()
            else DeathAlert_ApplyHealerPosition() end
        end,
        onUnlock   = function()
            if prefix == "tank" then DeathAlert_SetTankUnlocked(true)
            else DeathAlert_SetHealerUnlocked(true) end
            print("|cffff4444[UnbunkUtility]|r Alert unlocked — drag to reposition, then /ubu lock to save.")
        end,
        onLock     = function()
            if prefix == "tank" then DeathAlert_SetTankUnlocked(false)
            else DeathAlert_SetHealerUnlocked(false) end
        end,
        isUnlocked = function()
            if prefix == "tank" then return DeathAlert_IsTankUnlocked()
            else return DeathAlert_IsHealerUnlocked() end
        end,
    })
    pe.frame:ClearAllPoints()
    AddWidget(pe.frame, pe.height)

    -- ── Duration editor ───────────────────────────────────────────────────────

    local de = Unbunk_CreateDurationEditor({
        parent           = parent,
        getDuration      = function() return DeathAlertCfg_Get(prefix .. "AlertDuration") end,
        onDurationChange = function(val) DeathAlertCfg_Set(prefix .. "AlertDuration", val) end,
    })
    de.frame:ClearAllPoints()
    AddWidget(de.frame, de.height)

    height = height + 16

    return height, {
        sound = soundResult.Refresh,
        te    = te.Refresh,
        pe    = pe.Refresh,
        de    = de.Refresh,
    }
end

local function CreateDeathAlertPanel(parent)
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

    -- ── Tank section ──────────────────────────────────────────────────────────

    local tankCS = Unbunk_CreateCollapsibleSection({
        parent        = content,
        label         = "Tank Death Alert",
        isChecked     = function() return DeathAlertCfg_Get("tankEnabled") end,
        onCheck       = function(val) DeathAlertCfg_Set("tankEnabled", val) end,
        createContent = function(sectionParent)
            local h, fns = CreateAlertSection(sectionParent, "tank")
            allRefreshFns.tank = fns
            return h
        end,
    })
    AddSection(tankCS.frame)

    -- ── Healer section ────────────────────────────────────────────────────────

    local healerCS = Unbunk_CreateCollapsibleSection({
        parent        = content,
        label         = "Healer Death Alert",
        isChecked     = function() return DeathAlertCfg_Get("healerEnabled") end,
        onCheck       = function(val) DeathAlertCfg_Set("healerEnabled", val) end,
        createContent = function(sectionParent)
            local h, fns = CreateAlertSection(sectionParent, "healer")
            allRefreshFns.healer = fns
            return h
        end,
    })
    AddSection(healerCS.frame)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        if allRefreshFns.tank then
            allRefreshFns.tank.sound()
            allRefreshFns.tank.te()
            allRefreshFns.tank.pe()
            if allRefreshFns.tank.de then allRefreshFns.tank.de() end
        end
        if allRefreshFns.healer then
            allRefreshFns.healer.sound()
            allRefreshFns.healer.te()
            allRefreshFns.healer.pe()
            if allRefreshFns.healer.de then allRefreshFns.healer.de() end
        end
        tankCS.Refresh()
        healerCS.Refresh()
    end)
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initDA = CreateFrame("Frame")
initDA:RegisterEvent("ADDON_LOADED")
initDA:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule("Death Alert", nil, CreateDeathAlertPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)