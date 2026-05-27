-- Modules/HealerRange/Core/Alert.lua

local _, ns = ...

local alertFrame = Unbunk_CreateAlertFrame({
    name   = "HealerRangeAlert",
    getCfg = function(key) return HealerRangeCfg_Get(key) end,
    onDragStop = function(x, y)
        HealerRangeCfg_Set("posX", x)
        HealerRangeCfg_Set("posY", y)
        if HealerRangePE then HealerRangePE.Refresh() end
    end,
})

function HealerRangeAlert_ApplyColor()    alertFrame.ApplyColor()    end
function HealerRangeAlert_ApplyPosition() alertFrame.ApplyPosition() end
function HealerRangeAlert_ApplyMessage()  alertFrame.ApplyMessage()  end
function HealerRangeAlert_ApplyFont()     alertFrame.ApplyFont()     end
function HealerRangeAlert_ApplyIcon()     alertFrame.ApplyIcon()     end

function HealerRangeAlert_SetVisible(visible)
    if visible then alertFrame.Show() else alertFrame.Hide() end
end

function HealerRangeAlert_SetUnlocked(val) alertFrame.SetUnlocked(val) end
function HealerRangeAlert_IsUnlocked()     return alertFrame.IsUnlocked() end
function HealerRangeAlert_SetTesting(val)  alertFrame.SetTesting(val) end
function HealerRangeAlert_IsTesting()      return alertFrame.IsTesting() end
function HealerRangeAlert_GetFrame()       return alertFrame.GetFrame() end

local function ApplyAll()
    HealerRangeAlert_ApplyColor()
    HealerRangeAlert_ApplyPosition()
    HealerRangeAlert_ApplyFont()
    HealerRangeAlert_ApplyMessage()
    HealerRangeAlert_ApplyIcon()
end

ns.RegisterReloadHook(ApplyAll)

local initAlert = CreateFrame("Frame")
initAlert:RegisterEvent("PLAYER_LOGIN")
initAlert:SetScript("OnEvent", function(self)
    ApplyAll()
    self:UnregisterEvent("PLAYER_LOGIN")
end)