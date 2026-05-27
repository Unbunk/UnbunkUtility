-- Modules/PITracker/Core/PITracker.lua

local _, ns = ...

local PI_SPELL_ID  = 10060
local PI_ICON_ID   = 135960 -- icône native de Power Infusion

local playerHasPI  = false
local playerClass  = nil
local hasBuff      = false

local piIcon = Unbunk_CreateTimerIcon({
    name    = "PITrackerFrame",
    getCfg  = function(key) return PITrackerCfg_Get(key) end,
    onDragStop = function(x, y)
        PITrackerCfg_Set("posX", x)
        PITrackerCfg_Set("posY", y)
        if PITrackerPE then PITrackerPE.Refresh() end
    end,
})

piIcon.onExpire = function() end

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(PITrackerCfg_Get("instanceFilter"))
end

local function CheckPlayerHasPI()
    local _, class = UnitClass("player")
    playerClass = class
    playerHasPI = class == "PRIEST"
end

local function GetPIIcon()
    local spellInfo = C_Spell.GetSpellInfo(PI_SPELL_ID)
    return spellInfo and spellInfo.iconID or PI_ICON_ID
end

function ApplyVisuals_PI()
    if not PITrackerCfg_Get("enabled") or not IsActiveInCurrentInstance() then
        piIcon.Hide()
        return
    end
    if not PITrackerCfg_Get("showIcon") then
        piIcon.Hide()
        return
    end
    piIcon.SetIcon(GetPIIcon())
    piIcon.ApplySize()
    if hasBuff or playerHasPI then
        piIcon.Show()
    else
        piIcon.Hide()
    end
    if not hasBuff and playerHasPI then
        piIcon.ShowCheck()
    else
        piIcon.HideCheck()
    end
end

local function SyncBuff()
    if not PITrackerCfg_Get("enabled") then return end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(PI_SPELL_ID)
    if aura then
        if not hasBuff then
            hasBuff = true
            piIcon.SetGlow(true)
            if PITrackerCfg_Get("soundOnPI") then
                PITracker_PlaySound()
            end
        end
        piIcon.SetTimer(aura.expirationTime, aura.duration, { r=1, g=1, b=0 })
        piIcon.HideCheck()
    elseif hasBuff then
        hasBuff = false
        piIcon.SetGlow(false)
        piIcon.ClearTimer()
    end
    ApplyVisuals_PI()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PITracker_ApplyFont()     piIcon.ApplyFont()     end
function PITracker_ApplyPosition() piIcon.ApplyPosition() end
function PITracker_ApplySize()     piIcon.ApplySize()     end
function PITracker_SetUnlocked(v)  piIcon.SetUnlocked(v)  end
function PITracker_IsUnlocked()    return piIcon.IsUnlocked() end
function PITracker_GetFrame()      return piIcon.GetFrame()   end

-- ── Events ────────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SPELLS_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event)
    CheckPlayerHasPI()
    ApplyVisuals_PI()
end)

C_Timer.NewTicker(0.5, function()
    SyncBuff()
end)

ns.RegisterReloadHook(function()
    PITracker_ApplyPosition()
    PITracker_ApplyFont()
    PITracker_ApplySize()
    ApplyVisuals_PI()
end)

local initPI = CreateFrame("Frame")
initPI:RegisterEvent("PLAYER_LOGIN")
initPI:SetScript("OnEvent", function(self)
    CheckPlayerHasPI()
    PITracker_ApplyPosition()
    PITracker_ApplyFont()
    PITracker_ApplySize()
    ApplyVisuals_PI()
    self:UnregisterEvent("PLAYER_LOGIN")
end)