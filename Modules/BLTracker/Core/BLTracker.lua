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

-- Only the keys (debuff spellIds) are consumed by FindPlayerAura's pairs() loop,
-- so this is a plain set mirroring BL_BUFFS (the per-entry data is never read).
local BL_DEBUFFS = {}
for _, data in pairs(BL_SPELLS) do
    BL_DEBUFFS[data.debuff] = true
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
local hasBuff      = false
local lastDebuffEnd = 0  -- GetTime() at which the fatigue (Sated) debuff ends

-- ── TimerIcon ─────────────────────────────────────────────────────────────────

local blIcon = ns.ui.CreateTimerIcon({
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
    -- The green check is no longer a persistent "BL available" badge — it
    -- only flashes briefly when the exhaustion debuff fades (see SyncDebuff).
    if hasBuff or hasDebuff then
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

-- BL.PlaySound is defined in Core/Config.lua alongside CfgGet/CfgSet.

-- ── Events ────────────────────────────────────────────────────────────────────

-- Note: we no longer listen to UNIT_SPELLCAST_SUCCEEDED from other units. A
-- spellId from another player's cast is a "secret value" (Blizzard protection)
-- that cannot be used as a table key. Detection runs through the player's own
-- auras (SyncDebuff), which covers any caster and plays the sound on gain.

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

-- Returns the first player aura present from a set of spellIds.
local function FindPlayerAura(idSet)
    for spellId in pairs(idSet) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura then return aura end
    end
    return nil
end

local function SyncDebuff()
    if not BL.CfgGet("enabled") then return end

    -- Active beneficial buff (Bloodlust/Heroism/...) takes priority.
    local buff = FindPlayerAura(BL_BUFFS)
    if buff then
        currentIcon = buff.icon
        if not hasBuff then
            hasBuff = true
            -- Play the sound when the buff is gained (any caster), routed
            -- through the combo coordinator so nearly-simultaneous tracker
            -- alerts can collapse into a single combo sound.
            if BL.CfgGet("soundOnBL") then
                ns.combo.Notify("bl", function() BL.PlaySound("soundPathBL") end)
            end
        end
        hasDebuff = false
        blIcon.SetTimer(buff.expirationTime, buff.duration, { r=0, g=1, b=0 })
        BL.ApplyVisuals()
        return
    end
    hasBuff = false

    -- Otherwise, fatigue debuff (Sated/Exhaustion/...).
    local debuff = FindPlayerAura(BL_DEBUFFS)
    if debuff then
        currentIcon = debuff.icon
        hasDebuff   = true
        lastDebuffEnd = debuff.expirationTime or 0
        blIcon.SetTimer(debuff.expirationTime, debuff.duration)
    else
        if hasDebuff then
            hasDebuff   = false
            currentIcon = GetDefaultClassIcon(playerClass)
            -- Only "ready" if the fatigue debuff actually expired. A loading
            -- screen can report it as gone before its real end (e.g. leaving a
            -- follower dungeon) — stale read, not BL coming back up.
            local completed = lastDebuffEnd > 0 and (GetTime() >= lastDebuffEnd - ns.READY_EPSILON)
            if completed and not ns.RecentlyZoned() then
                if BL.CfgGet("soundOnReady") then BL.PlaySound("soundPathReady") end
                blIcon.ClearTimer()
                blIcon.BlinkCheck()  -- flash to signal BL is back up
            else
                blIcon.ClearTimer()
            end
        else
            blIcon.ClearTimer()
        end
    end

    BL.ApplyVisuals()
end

C_Timer.NewTicker(0.5, function()
    -- Do ~zero work per tick while the module is disabled (S3 guard).
    if not BL.CfgGet("enabled") then return end
    SyncDebuff()
end)

-- Instant aura detection: UNIT_AURA fires the moment the player gains/loses an
-- aura, so SyncDebuff runs (and ns.combo.Notify("bl", ...) fires) without
-- waiting up to 500ms for the next ticker. Without this, a near-simultaneous
-- potion cast would flush as "potion combo" before BL is even detected.
local auraFrame = CreateFrame("Frame")
auraFrame:RegisterUnitEvent("UNIT_AURA", "player")
auraFrame:SetScript("OnEvent", function() SyncDebuff() end)

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