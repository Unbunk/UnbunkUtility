-- Modules/BLTracker/Core/BLTracker.lua

local _, ns = ...
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

local BL_SPELLS = {
    [2825]   = { name = "Bloodlust",          icon = 136012,  debuff = 57724  },
    [32182]  = { name = "Heroism",             icon = 135413,  debuff = 57723  },
    [80353]  = { name = "Time Warp",           icon = 606545,  debuff = 80354  },
    [90355]  = { name = "Ancient Hysteria",    icon = 237589,  debuff = 95809  },
    [264667] = { name = "Primal Rage",         icon = 132276,  debuff = 264689 },
    [390386] = { name = "Fury of the Aspects", icon = 4622460, debuff = 390527 },
}

local BL_BUFFS = {
    [2825]   = true, -- Bloodlust
    [32182]  = true, -- Heroism
    [80353]  = true, -- Time Warp
    [90355]  = true, -- Ancient Hysteria
    [264667] = true, -- Primal Rage
    [390386] = true, -- Fury of the Aspects
}

local BL_DEBUFFS = {}
for _, data in pairs(BL_SPELLS) do
    BL_DEBUFFS[data.debuff] = data
end

local BL_CLASSES = {
    SHAMAN = true,
    MAGE   = true,
    EVOKER = true,
}
local BL_PET_CLASSES = {
    HUNTER = true,
}

local DEFAULT_CLASS_SPELLS = {
    SHAMAN = 2825,   -- Bloodlust
    MAGE   = 80353,  -- Time Warp
    EVOKER = 390386, -- Fury of the Aspects
    HUNTER = 264667, -- Primal Rage
}

local function GetDefaultClassIcon(class)
    local spellId = DEFAULT_CLASS_SPELLS[class]
    if not spellId then return nil end
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    return spellInfo and spellInfo.iconID or nil
end

local playerHasBL  = false
local playerClass  = nil
local currentIcon  = nil
local hasDebuff    = false

-- ── TimerIcon ─────────────────────────────────────────────────────────────────

local blIcon = Unbunk_CreateTimerIcon({
    name    = "BLTrackerFrame",
    getCfg  = function(key) return BL.CfgGet(key) end,
    onDragStop = function(x, y)
        BL.CfgSet("posX", x)
        BL.CfgSet("posY", y)
        if BL.pe then BL.pe.Refresh() end
    end,
})

blIcon.onExpire = function() end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(BL.CfgGet("instanceFilter"))
end

local function CheckPlayerHasBL()
    local _, class = UnitClass("player")
    playerClass = class
    playerHasBL = BL_CLASSES[class] or BL_PET_CLASSES[class] or false
end

function BL.ApplyVisuals()
    if not BL.CfgGet("enabled") or not IsActiveInCurrentInstance() then
        blIcon.Hide()
        return
    end
    if not BL.CfgGet("showIcon") then
        blIcon.Hide()
    else
        local icon = currentIcon or (playerClass and GetDefaultClassIcon(playerClass))
        if icon then blIcon.SetIcon(icon) end
        blIcon.ApplySize()
        if hasDebuff or playerHasBL then
            blIcon.Show()
        else
            blIcon.Hide()
        end
    end
    -- Affiche le check seulement si pas de debuff
    if not hasDebuff and playerHasBL then
        blIcon.ShowCheck()
    else
        blIcon.HideCheck()
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function BL.ApplyFont()     blIcon.ApplyFont()     end
function BL.ApplyPosition() blIcon.ApplyPosition() end
function BL.ApplySize()     blIcon.ApplySize()     end
function BL.SetUnlocked(v)  blIcon.SetUnlocked(v)  end
function BL.IsUnlocked()    return blIcon.IsUnlocked() end
function BL.GetFrame()      return blIcon.GetFrame() end

function BL.PlaySound(key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = BL.CfgGet(key)
    if path then
        PlaySoundFile(path, "Master")
    elseif LSM then
        local soundKey = BL.CfgGet(key:gsub("Path", "Key"))
        local soundPath = soundKey and LSM:Fetch("sound", soundKey)
        if soundPath then PlaySoundFile(soundPath, "Master") end
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────

-- Note : on n'écoute plus UNIT_SPELLCAST_SUCCEEDED des autres unités. Le spellId
-- d'un sort lancé par un autre joueur est une "secret value" (protection Blizzard)
-- qui ne peut pas servir de clé de table. La détection se fait via les auras du
-- joueur (SyncDebuff), qui couvre tous les lanceurs et joue le son à l'acquisition.

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SPELLS_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event)
    CheckPlayerHasBL()
    if not hasDebuff and playerClass then
        currentIcon = GetDefaultClassIcon(playerClass)
    end
    BL.ApplyVisuals()
end)

local hasBuff = false

-- Cherche sur le joueur la première aura présente parmi un ensemble de spellIds.
local function FindPlayerAura(idSet)
    for spellId in pairs(idSet) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura then return aura end
    end
    return nil
end

local function SyncDebuff()
    if not BL.CfgGet("enabled") then return end

    -- Buff positif (Bloodlust/Heroism/... actif) en priorité.
    local buff = FindPlayerAura(BL_BUFFS)
    if buff then
        currentIcon = buff.icon
        if not hasBuff then
            hasBuff = true
            -- Son joué à l'acquisition du buff (peu importe qui l'a lancé).
            if BL.CfgGet("soundOnBL") then
                BL.PlaySound("soundPathBL")
            end
        end
        hasDebuff = false
        blIcon.SetTimer(buff.expirationTime, buff.duration, { r=0, g=1, b=0 })
        BL.ApplyVisuals()
        return
    end
    hasBuff = false

    -- Sinon, debuff de fatigue (Sated/Exhaustion/...).
    local debuff = FindPlayerAura(BL_DEBUFFS)
    if debuff then
        currentIcon = debuff.icon
        hasDebuff   = true
        blIcon.SetTimer(debuff.expirationTime, debuff.duration)
    else
        if hasDebuff then
            hasDebuff   = false
            currentIcon = GetDefaultClassIcon(playerClass)
            if BL.CfgGet("soundOnReady") then
                BL.PlaySound("soundPathReady")
            end
        end
        blIcon.ClearTimer()
    end

    BL.ApplyVisuals()
end

C_Timer.NewTicker(0.5, function()
    SyncDebuff()
end)

ns.RegisterReloadHook(function()
    BL.ApplyPosition()
    BL.ApplyFont()
    BL.ApplySize()
    BL.ApplyVisuals()
end)

local initBL = CreateFrame("Frame")
initBL:RegisterEvent("PLAYER_LOGIN")
initBL:SetScript("OnEvent", function(self)
    CheckPlayerHasBL()
    currentIcon = GetDefaultClassIcon(playerClass)
    BL.ApplyPosition()
    BL.ApplyFont()
    BL.ApplySize()
    BL.ApplyVisuals()
    self:UnregisterEvent("PLAYER_LOGIN")
end)