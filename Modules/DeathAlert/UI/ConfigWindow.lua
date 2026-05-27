-- Modules/DeathAlert/UI/ConfigWindow.lua

local _, ns = ...
ns.DeathAlert = ns.DeathAlert or {}
local DA = ns.DeathAlert

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
            local getFrame = prefix == "tank" and DA.GetTankFrame or
                         prefix == "healer" and DA.GetHealerFrame or
                         DA.GetDpsFrame
            local setTest  = prefix == "tank" and DA.SetTankTesting or
                         prefix == "healer" and DA.SetHealerTesting or
                         DA.SetDpsTesting
            setTest(true)
            getFrame():Show()
            DA.PlaySound(prefix)
            C_Timer.After(5, function()
                setTest(false)
                getFrame():Hide()
            end)
        end,
    })
    testBtnWidget.frame:SetPoint("TOPLEFT", testFrame, "TOPLEFT", 0, -2)
    AddWidget(testFrame, 26) 

    -- ── Instance filter ───────────────────────────────────────────────────────

    local iF = Unbunk_CreateInstanceFilter({
        parent    = parent,
        getConfig = function() return DA.CfgGet(prefix .. "InstanceFilter") end,
        setConfig = function(key, val)
            local filter = DA.CfgGet(prefix .. "InstanceFilter")
            filter[key] = val
            DA.CfgSet(prefix .. "InstanceFilter", filter)
        end,
    })
    iF.frame:ClearAllPoints()
    AddWidget(iF.frame, iF.height)

    -- ── Icon picker ───────────────────────────────────────────────────────────

    local ip = Unbunk_CreateIconPicker({
        parent    = parent,
        getConfig = function() return DA.CfgGet(prefix .. "Icon") end,
        setConfig = function(key, val)
            local cfg = DA.CfgGet(prefix .. "Icon")
            cfg[key] = val
            DA.CfgSet(prefix .. "Icon", cfg)
            if prefix == "tank" then DA.ApplyTankIcon()
            elseif prefix == "healer" then DA.ApplyHealerIcon()
            else DA.ApplyDpsIcon() end
        end,
        icons = UNBUNK_ICONS or {},
    })
    ip.frame:ClearAllPoints()
    AddWidget(ip.frame, ip.height)

    -- ── Sound picker ──────────────────────────────────────────────────────────

    local soundResult = HealerRange_CreateSoundPicker(parent, LSM, {
        getSoundKey    = function() return DA.CfgGet(prefix .. "SoundKey") end,
        getSoundEnable = function() return DA.CfgGet(prefix .. "EnableSound") end,
        onSoundSelect  = function(key, path)
            DA.CfgSet(prefix .. "SoundKey", key)
            DA.CfgSet(prefix .. "SoundPath", path)
        end,
        onEnableToggle = function(val)
            DA.CfgSet(prefix .. "EnableSound", val)
        end,
        onTest = function()
            DA.PlaySound(prefix)
        end,
    })
    soundResult.frame:ClearAllPoints()
    AddWidget(soundResult.frame, soundResult.height)

    -- ── Text editor ───────────────────────────────────────────────────────────

    local te = HealerRange_CreateTextEditor(parent, {
        LSM             = LSM,
        label           = "Alert text",
        getText         = function() return DA.CfgGet(prefix .. "Message") end,
        getFontKey      = function() return DA.CfgGet(prefix .. "FontKey") end,
        getFontPath     = function() return DA.CfgGet(prefix .. "FontPath") end,
        getFontSize     = function() return DA.CfgGet(prefix .. "FontSize") end,
        getColor        = function() return DA.CfgGet(prefix .. "Color") end,
        getOutline      = function() return DA.CfgGet(prefix .. "Outline") end,
        onTextChange    = function(txt)
            DA.CfgSet(prefix .. "Message", txt)
            if prefix == "tank" then DA.ApplyTankMessage()
            elseif prefix == "healer" then DA.ApplyHealerMessage()
            else DA.ApplyDpsMessage() end
        end,
        onFontChange    = function(key, path)
            DA.CfgSet(prefix .. "FontKey", key)
            DA.CfgSet(prefix .. "FontPath", path)
            if prefix == "tank" then DA.ApplyTankFont()
            elseif prefix == "healer" then DA.ApplyHealerFont()
            else DA.ApplyDpsFont() end
        end,
        onSizeChange    = function(size)
            DA.CfgSet(prefix .. "FontSize", size)
            if prefix == "tank" then DA.ApplyTankFont()
            elseif prefix == "healer" then DA.ApplyHealerFont()
            else DA.ApplyDpsFont() end
        end,
        onColorChange   = function(r, g, b, a)
            DA.CfgSet(prefix .. "Color", { r=r, g=g, b=b, a=a })
            if prefix == "tank" then DA.ApplyTankColor()
            elseif prefix == "healer" then DA.ApplyHealerColor()
            else DA.ApplyDpsColor() end
        end,
        onOutlineChange = function(outline)
            DA.CfgSet(prefix .. "Outline", outline)
            if prefix == "tank" then DA.ApplyTankFont()
            elseif prefix == "healer" then DA.ApplyHealerFont()
            else DA.ApplyDpsFont() end
        end,
    })
    te.frame:ClearAllPoints()
    AddWidget(te.frame, te.height)

    -- ── Position editor ───────────────────────────────────────────────────────

    local peName = "DeathAlert_PE_" .. prefix
    _G[peName] = HealerRange_CreatePositionEditor(parent, {
        label      = "Alert position (offset from screen center)",
        getX       = function() return DA.CfgGet(prefix .. "PosX") end,
        getY       = function() return DA.CfgGet(prefix .. "PosY") end,
        onApply    = function(x, yv)
            if x  then DA.CfgSet(prefix .. "PosX", x)  end
            if yv then DA.CfgSet(prefix .. "PosY", yv) end
            if prefix == "tank" then DA.ApplyTankPosition()
            elseif prefix == "healer" then DA.ApplyHealerPosition()
            else DA.ApplyDpsPosition() end
        end,
        onUnlock   = function()
            if prefix == "tank" then DA.SetTankUnlocked(true)
            elseif prefix == "healer" then DA.SetHealerUnlocked(true)
            else DA.SetDpsUnlocked(true) end
        end,
        onLock     = function()
            if prefix == "tank" then DA.SetTankUnlocked(false)
            elseif prefix == "healer" then DA.SetHealerUnlocked(false)
            else DA.SetDpsUnlocked(false) end
        end,
        isUnlocked = function()
            if prefix == "tank" then return DA.IsTankUnlocked()
            elseif prefix == "healer" then return DA.IsHealerUnlocked()
            else return DA.IsDpsUnlocked() end
        end,
    })
    _G[peName].frame:ClearAllPoints()
    AddWidget(_G[peName].frame, _G[peName].height)

    -- ── Duration editor ───────────────────────────────────────────────────────

    local de = Unbunk_CreateDurationEditor({
        parent           = parent,
        getDuration      = function() return DA.CfgGet(prefix .. "AlertDuration") end,
        onDurationChange = function(val) DA.CfgSet(prefix .. "AlertDuration", val) end,
    })
    de.frame:ClearAllPoints()
    AddWidget(de.frame, de.height)

    height = height + 16

    return height, {
        sound = soundResult.Refresh,
        te    = te.Refresh,
        pe    = _G[peName].Refresh,
        de    = de.Refresh,
        iF    = iF.Refresh,
        ip    = ip.Refresh,
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
        isChecked     = function() return DA.CfgGet("tankEnabled") end,
        onCheck       = function(val) DA.CfgSet("tankEnabled", val) end,
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
        isChecked     = function() return DA.CfgGet("healerEnabled") end,
        onCheck       = function(val) DA.CfgSet("healerEnabled", val) end,
        createContent = function(sectionParent)
            local h, fns = CreateAlertSection(sectionParent, "healer")
            allRefreshFns.healer = fns
            return h
        end,
    })
    AddSection(healerCS.frame)

    -- ── DPS section ────────────────────────────────────────────────────────

    local dpsCS = Unbunk_CreateCollapsibleSection({
        parent        = content,
        label         = "DPS Death Alert",
        isChecked     = function() return DA.CfgGet("dpsEnabled") end,
        onCheck       = function(val) DA.CfgSet("dpsEnabled", val) end,
        createContent = function(sectionParent)
            local h, fns = CreateAlertSection(sectionParent, "dps")
            allRefreshFns.dps = fns
            return h
        end,
    })
    AddSection(dpsCS.frame)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        if allRefreshFns.tank then
            allRefreshFns.tank.sound()
            allRefreshFns.tank.te()
            allRefreshFns.tank.pe()
            if allRefreshFns.tank.de then allRefreshFns.tank.de() end
            if allRefreshFns.tank.iF then allRefreshFns.tank.iF() end
        end
        if allRefreshFns.healer then
            allRefreshFns.healer.sound()
            allRefreshFns.healer.te()
            allRefreshFns.healer.pe()
            if allRefreshFns.healer.de then allRefreshFns.healer.de() end
            if allRefreshFns.healer.iF then allRefreshFns.healer.iF() end
        end
        if allRefreshFns.dps then
            allRefreshFns.dps.sound()
            allRefreshFns.dps.te()
            allRefreshFns.dps.pe()
            if allRefreshFns.dps.de then allRefreshFns.dps.de() end
            if allRefreshFns.dps.iF then allRefreshFns.dps.iF() end
            if allRefreshFns.dps.ip then allRefreshFns.dps.ip() end
        end
        tankCS.Refresh()
        healerCS.Refresh()
        dpsCS.Refresh()
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