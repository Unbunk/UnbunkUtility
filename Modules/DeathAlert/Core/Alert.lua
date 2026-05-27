-- Modules/DeathAlert/Core/Alert.lua

local _, ns = ...
ns.DeathAlert = ns.DeathAlert or {}
local DA = ns.DeathAlert

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
    getCfg = function(key) return DA.CfgGet(TANK_KEY_MAP[key] or key) end,
    onDragStop = function(x, y)
        DA.CfgSet("tankPosX", x)
        DA.CfgSet("tankPosY", y)
        if _G["DeathAlert_PE_tank"] then _G["DeathAlert_PE_tank"].Refresh() end
    end,
})

local healerAlert = Unbunk_CreateAlertFrame({
    name   = "DeathAlertHealerFrame",
    getCfg = function(key) return DA.CfgGet(HEALER_KEY_MAP[key] or key) end,
    onDragStop = function(x, y)
        DA.CfgSet("healerPosX", x)
        DA.CfgSet("healerPosY", y)
        if _G["DeathAlert_PE_healer"] then _G["DeathAlert_PE_healer"].Refresh() end
    end,
})

local dpsAlert = Unbunk_CreateAlertFrame({
    name   = "DeathAlertDpsFrame",
    getCfg = function(key) return DA.CfgGet(DPS_KEY_MAP[key] or key) end,
    onDragStop = function(x, y)
        DA.CfgSet("dpsPosX", x)
        DA.CfgSet("dpsPosY", y)
        if _G["DeathAlert_PE_dps"] then _G["DeathAlert_PE_dps"].Refresh() end
    end,
})

-- Tank
function DA.ApplyTankFont()     tankAlert.ApplyFont()     end
function DA.ApplyTankColor()    tankAlert.ApplyColor()    end
function DA.ApplyTankMessage()  tankAlert.ApplyMessage()  end
function DA.ApplyTankPosition() tankAlert.ApplyPosition() end
function DA.ApplyTankIcon()     tankAlert.ApplyIcon()     end
function DA.SetTankUnlocked(v)  tankAlert.SetUnlocked(v)  end
function DA.IsTankUnlocked()    return tankAlert.IsUnlocked() end
function DA.SetTankTesting(v)   tankAlert.SetTesting(v)   end
function DA.IsTankTesting()     return tankAlert.IsTesting()  end
function DA.GetTankFrame()      return tankAlert.GetFrame()   end

-- Healer
function DA.ApplyHealerFont()     healerAlert.ApplyFont()     end
function DA.ApplyHealerColor()    healerAlert.ApplyColor()    end
function DA.ApplyHealerMessage()  healerAlert.ApplyMessage()  end
function DA.ApplyHealerPosition() healerAlert.ApplyPosition() end
function DA.ApplyHealerIcon()     healerAlert.ApplyIcon()     end
function DA.SetHealerUnlocked(v)  healerAlert.SetUnlocked(v)  end
function DA.IsHealerUnlocked()    return healerAlert.IsUnlocked() end
function DA.SetHealerTesting(v)   healerAlert.SetTesting(v)   end
function DA.IsHealerTesting()     return healerAlert.IsTesting()  end
function DA.GetHealerFrame()      return healerAlert.GetFrame()   end

-- DPS
function DA.ApplyDpsFont()     dpsAlert.ApplyFont()     end
function DA.ApplyDpsColor()    dpsAlert.ApplyColor()    end
function DA.ApplyDpsMessage()  dpsAlert.ApplyMessage()  end
function DA.ApplyDpsPosition() dpsAlert.ApplyPosition() end
function DA.ApplyDpsIcon()     dpsAlert.ApplyIcon()     end
function DA.SetDpsUnlocked(v)  dpsAlert.SetUnlocked(v)  end
function DA.IsDpsUnlocked()    return dpsAlert.IsUnlocked() end
function DA.SetDpsTesting(v)   dpsAlert.SetTesting(v)   end
function DA.IsDpsTesting()     return dpsAlert.IsTesting()  end
function DA.GetDpsFrame()      return dpsAlert.GetFrame()   end

local function ApplyAll()
    DA.ApplyTankFont()
    DA.ApplyTankColor()
    DA.ApplyTankMessage()
    DA.ApplyTankPosition()
    DA.ApplyTankIcon()
    DA.ApplyHealerFont()
    DA.ApplyHealerColor()
    DA.ApplyHealerMessage()
    DA.ApplyHealerPosition()
    DA.ApplyHealerIcon()
    DA.ApplyDpsFont()
    DA.ApplyDpsColor()
    DA.ApplyDpsMessage()
    DA.ApplyDpsPosition()
    DA.ApplyDpsIcon()
end

ns.RegisterReloadHook(ApplyAll)

local initAlert = CreateFrame("Frame")
initAlert:RegisterEvent("PLAYER_LOGIN")
initAlert:SetScript("OnEvent", function(self)
    ApplyAll()
    self:UnregisterEvent("PLAYER_LOGIN")
end)