-- Modules/PITracker/Core/PITracker.lua

local _, ns = ...
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

local PI_SPELL_ID  = 10060
local PI_ICON_ID   = 135960 -- icône native de Power Infusion

local playerHasPI  = false
local playerClass  = nil
local hasBuff      = false

local piIcon = Unbunk_CreateTimerIcon({
    name    = "PITrackerFrame",
    getCfg  = function(key) return PI.CfgGet(key) end,
    onDragStop = function(x, y)
        PI.CfgSet("posX", x)
        PI.CfgSet("posY", y)
        if PI.pe then PI.pe.Refresh() end
    end,
})

piIcon.onExpire = function() end

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(PI.CfgGet("instanceFilter"))
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

function PI.ApplyVisuals()
    if not PI.CfgGet("enabled") or not IsActiveInCurrentInstance() then
        piIcon.Hide()
        return
    end
    if not PI.CfgGet("showIcon") then
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
    if not PI.CfgGet("enabled") then return end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(PI_SPELL_ID)
    if aura then
        if not hasBuff then
            hasBuff = true
            piIcon.SetGlow(true)
            if PI.CfgGet("soundOnPI") then
                PI.PlaySound()
            end
        end
        piIcon.SetTimer(aura.expirationTime, aura.duration, { r=1, g=1, b=0 })
        piIcon.HideCheck()
    elseif hasBuff then
        hasBuff = false
        piIcon.SetGlow(false)
        piIcon.ClearTimer()
    end
    PI.ApplyVisuals()
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PI.ApplyFont()     piIcon.ApplyFont()     end
function PI.ApplyPosition() piIcon.ApplyPosition() end
function PI.ApplySize()     piIcon.ApplySize()     end
function PI.SetUnlocked(v)  piIcon.SetUnlocked(v)  end
function PI.IsUnlocked()    return piIcon.IsUnlocked() end
function PI.GetFrame()      return piIcon.GetFrame()   end

-- ── Events ────────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SPELLS_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event)
    CheckPlayerHasPI()
    PI.ApplyVisuals()
end)

C_Timer.NewTicker(0.5, function()
    SyncBuff()
end)

ns.RegisterReloadHook(function()
    PI.ApplyPosition()
    PI.ApplyFont()
    PI.ApplySize()
    PI.ApplyVisuals()
end)

local initPI = CreateFrame("Frame")
initPI:RegisterEvent("PLAYER_LOGIN")
initPI:SetScript("OnEvent", function(self)
    CheckPlayerHasPI()
    PI.ApplyPosition()
    PI.ApplyFont()
    PI.ApplySize()
    PI.ApplyVisuals()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
