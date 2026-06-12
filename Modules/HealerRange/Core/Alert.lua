-- Modules/HealerRange/Core/Alert.lua

local _, ns = ...
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

local alertFrame = ns.ui.CreateAlertFrame({
    name   = "HealerRangeAlert",
    getCfg = function(key) return HR.CfgGet(key) end,
    onDragStop = function(x, y)
        HR.CfgSet("posX", x)
        HR.CfgSet("posY", y)
        if HR.pe then HR.pe.Refresh() end
    end,
})

function HR.ApplyColor()    alertFrame.ApplyColor()    end
function HR.ApplyPosition() alertFrame.ApplyPosition() end
function HR.ApplyMessage()  alertFrame.ApplyMessage()  end
function HR.ApplyFont()     alertFrame.ApplyFont()     end
function HR.ApplyIcon()     alertFrame.ApplyIcon()     end

function HR.SetVisible(visible)
    if visible then alertFrame.Show() else alertFrame.Hide() end
end

function HR.SetUnlocked(val) alertFrame.SetUnlocked(val) end
function HR.IsUnlocked()     return alertFrame.IsUnlocked() end
function HR.SetTesting(val)  alertFrame.SetTesting(val) end
function HR.IsTesting()      return alertFrame.IsTesting() end
function HR.GetFrame()       return alertFrame.GetFrame() end

local function ApplyAll()
    HR.ApplyColor()
    HR.ApplyPosition()
    HR.ApplyFont()
    HR.ApplyMessage()
    HR.ApplyIcon()
end

ns.RegisterReloadHook(ApplyAll)

local initAlert = CreateFrame("Frame")
initAlert:RegisterEvent("PLAYER_LOGIN")
initAlert:SetScript("OnEvent", function(self)
    ApplyAll()
    self:UnregisterEvent("PLAYER_LOGIN")
end)