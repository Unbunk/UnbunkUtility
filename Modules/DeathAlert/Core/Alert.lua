-- Modules/DeathAlert/Core/Alert.lua

local _, ns = ...

local TANK_KEY_MAP = {
    alertMessage = "tankMessage",
    fontPath     = "tankFontPath",
    fontKey      = "tankFontKey",
    fontSize     = "tankFontSize",
    outline      = "tankOutline",
    color        = "tankColor",
    posX         = "tankPosX",
    posY         = "tankPosY",
    icon         = "tankIcon",
}

local HEALER_KEY_MAP = {
    alertMessage = "healerMessage",
    fontPath     = "healerFontPath",
    fontKey      = "healerFontKey",
    fontSize     = "healerFontSize",
    outline      = "healerOutline",
    color        = "healerColor",
    posX         = "healerPosX",
    posY         = "healerPosY",
    icon         = "healerIcon",
}

local DPS_KEY_MAP = {
    alertMessage = "dpsMessage",
    fontPath     = "dpsFontPath",
    fontKey      = "dpsFontKey",
    fontSize     = "dpsFontSize",
    outline      = "dpsOutline",
    color        = "dpsColor",
    posX         = "dpsPosX",
    posY         = "dpsPosY",
    icon         = "dpsIcon",
}

local tankAlert = Unbunk_CreateAlertFrame({
    name   = "DeathAlertTankFrame",
    getCfg = function(key) return DeathAlertCfg_Get(TANK_KEY_MAP[key] or key) end,
    onDragStop = function(x, y)
        DeathAlertCfg_Set("tankPosX", x)
        DeathAlertCfg_Set("tankPosY", y)
        if _G["DeathAlert_PE_tank"] then _G["DeathAlert_PE_tank"].Refresh() end
    end,
})

local healerAlert = Unbunk_CreateAlertFrame({
    name   = "DeathAlertHealerFrame",
    getCfg = function(key) return DeathAlertCfg_Get(HEALER_KEY_MAP[key] or key) end,
    onDragStop = function(x, y)
        DeathAlertCfg_Set("healerPosX", x)
        DeathAlertCfg_Set("healerPosY", y)
        if _G["DeathAlert_PE_healer"] then _G["DeathAlert_PE_healer"].Refresh() end
    end,
})

local dpsAlert = Unbunk_CreateAlertFrame({
    name   = "DeathAlertDpsFrame",
    getCfg = function(key) return DeathAlertCfg_Get(DPS_KEY_MAP[key] or key) end,
    onDragStop = function(x, y)
        DeathAlertCfg_Set("dpsPosX", x)
        DeathAlertCfg_Set("dpsPosY", y)
        if _G["DeathAlert_PE_dps"] then _G["DeathAlert_PE_dps"].Refresh() end
    end,
})

-- Tank
function DeathAlert_ApplyTankFont()     tankAlert.ApplyFont()     end
function DeathAlert_ApplyTankColor()    tankAlert.ApplyColor()    end
function DeathAlert_ApplyTankMessage()  tankAlert.ApplyMessage()  end
function DeathAlert_ApplyTankPosition() tankAlert.ApplyPosition() end
function DeathAlert_ApplyTankIcon()     tankAlert.ApplyIcon()     end
function DeathAlert_SetTankUnlocked(v)  tankAlert.SetUnlocked(v)  end
function DeathAlert_IsTankUnlocked()    return tankAlert.IsUnlocked() end
function DeathAlert_SetTankTesting(v)   tankAlert.SetTesting(v)   end
function DeathAlert_IsTankTesting()     return tankAlert.IsTesting()  end
function DeathAlert_GetTankFrame()      return tankAlert.GetFrame()   end

-- Healer
function DeathAlert_ApplyHealerFont()     healerAlert.ApplyFont()     end
function DeathAlert_ApplyHealerColor()    healerAlert.ApplyColor()    end
function DeathAlert_ApplyHealerMessage()  healerAlert.ApplyMessage()  end
function DeathAlert_ApplyHealerPosition() healerAlert.ApplyPosition() end
function DeathAlert_ApplyHealerIcon()     healerAlert.ApplyIcon()     end
function DeathAlert_SetHealerUnlocked(v)  healerAlert.SetUnlocked(v)  end
function DeathAlert_IsHealerUnlocked()    return healerAlert.IsUnlocked() end
function DeathAlert_SetHealerTesting(v)   healerAlert.SetTesting(v)   end
function DeathAlert_IsHealerTesting()     return healerAlert.IsTesting()  end
function DeathAlert_GetHealerFrame()      return healerAlert.GetFrame()   end

-- DPS
function DeathAlert_ApplyDpsFont()     dpsAlert.ApplyFont()     end
function DeathAlert_ApplyDpsColor()    dpsAlert.ApplyColor()    end
function DeathAlert_ApplyDpsMessage()  dpsAlert.ApplyMessage()  end
function DeathAlert_ApplyDpsPosition() dpsAlert.ApplyPosition() end
function DeathAlert_ApplyDpsIcon()     dpsAlert.ApplyIcon()     end
function DeathAlert_SetDpsUnlocked(v)  dpsAlert.SetUnlocked(v)  end
function DeathAlert_IsDpsUnlocked()    return dpsAlert.IsUnlocked() end
function DeathAlert_SetDpsTesting(v)   dpsAlert.SetTesting(v)   end
function DeathAlert_IsDpsTesting()     return dpsAlert.IsTesting()  end
function DeathAlert_GetDpsFrame()      return dpsAlert.GetFrame()   end

local function ApplyAll()
    DeathAlert_ApplyTankFont()
    DeathAlert_ApplyTankColor()
    DeathAlert_ApplyTankMessage()
    DeathAlert_ApplyTankPosition()
    DeathAlert_ApplyTankIcon()
    DeathAlert_ApplyHealerFont()
    DeathAlert_ApplyHealerColor()
    DeathAlert_ApplyHealerMessage()
    DeathAlert_ApplyHealerPosition()
    DeathAlert_ApplyHealerIcon()
    DeathAlert_ApplyDpsFont()
    DeathAlert_ApplyDpsColor()
    DeathAlert_ApplyDpsMessage()
    DeathAlert_ApplyDpsPosition()
    DeathAlert_ApplyDpsIcon()
end

ns.RegisterReloadHook(ApplyAll)

local initAlert = CreateFrame("Frame")
initAlert:RegisterEvent("PLAYER_LOGIN")
initAlert:SetScript("OnEvent", function(self)
    ApplyAll()
    self:UnregisterEvent("PLAYER_LOGIN")
end)