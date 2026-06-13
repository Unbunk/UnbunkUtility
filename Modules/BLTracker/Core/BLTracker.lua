-- Modules/BLTracker/Core/BLTracker.lua

local _, ns = ...
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

-- Shared read-only "active buff" colour, hoisted so the 0.5s visuals tick doesn't
-- allocate a fresh table each pass while the green timer is shown (SetTimer only
-- stores the reference and reads r/g/b, never mutates it).
local GREEN = { r = 0, g = 1, b = 0 }

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(BL)
AceTimer:Embed(BL)

local BL_SPELLS = {
    [2825]   = { name = "Bloodlust",          icon = 136012,  debuff = 57724  },
    [32182]  = { name = "Heroism",             icon = 135413,  debuff = 57723  },
    [80353]  = { name = "Time Warp",           icon = 606545,  debuff = 80354  },
    [90355]  = { name = "Ancient Hysteria",    icon = 237589,  debuff = 95809  },
    [264667] = { name = "Primal Rage",         icon = 132276,  debuff = 264689 },
    [390386] = { name = "Fury of the Aspects", icon = 4622460, debuff = 390435 },
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

-- Active lust window. Bloodlust / Heroism / Time Warp / Primal Rage / Fury of
-- the Aspects / Ancient Hysteria are all 40s. Used to derive a heuristic green
-- "active" timer in combat, where the beneficial buff is secret — see SyncDebuff.
local BL_ACTIVE_DURATION = 40

-- Generic placeholder shown by the "Always show" option for classes that have no
-- lust spell of their own (GetDefaultClassIcon returns nil for them): the classic
-- Bloodlust iconID, so the tracker stays recognisable when nothing is active.
local FALLBACK_BL_ICON = 136012

-- A class's default lust iconID is invariant for the session, so resolve it
-- once per class and cache it (this is recomputed whenever the lust drops and on
-- PLAYER_ENTERING_WORLD/SPELLS_CHANGED). C_Spell.GetSpellInfo can return nil
-- while spell data loads, so the nil is not cached — a later call retries.
local classIconCache = {}
local function GetDefaultClassIcon(class)
    if not class then return nil end
    local cached = classIconCache[class]
    if cached ~= nil then return cached end
    local spellId = DEFAULT_CLASS_SPELLS[class]
    if not spellId then return nil end
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    local iconID = spellInfo and spellInfo.iconID
    if iconID then classIconCache[class] = iconID end
    return iconID
end

local playerHasBL  = false
local playerClass  = nil
local currentIcon  = nil
local hasDebuff    = false
local hasBuff      = false
local lastDebuffEnd = 0  -- GetTime() at which the fatigue (Sated) debuff ends
local lustAnnounced = false  -- the "gained" sound has fired for the current lust cycle
local moduleActive  = false  -- false until the first tracking pass (login / re-enable)

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
        -- "Always show" (default on): keep the icon up even with no lust active
        -- and even on classes that never get a lust — falling back to the generic
        -- Bloodlust icon when no real one is known yet.
        local alwaysShow = BL.CfgGet("alwaysShow") ~= false
        -- Always resolve to *some* texture so the frame is never shown blank (e.g.
        -- a BL class during the early-login window before C_Spell data resolves).
        local icon = currentIcon or (playerClass and GetDefaultClassIcon(playerClass)) or FALLBACK_BL_ICON
        blIcon.SetIcon(icon)
        blIcon.ApplySize()
        -- When "Always show" is off the icon appears ONLY while a lust is actually
        -- active (buff OR fatigue debuff present) — never just because the player's
        -- class happens to own a lust spell. The "ready" sound still fires on
        -- completion (SyncDebuff) even though the brief check flash stays hidden.
        if alwaysShow or hasBuff or hasDebuff then
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
function BL.ApplyBorder()   blIcon.ApplyBorder()   end
function BL.SetUnlocked(v)  blIcon.SetUnlocked(v)  end
function BL.IsUnlocked()    return blIcon.IsUnlocked() end
function BL.GetFrame()      return blIcon.GetFrame() end

-- BL.PlaySound is defined in Core/Config.lua alongside CfgGet/CfgSet.

-- ── Events ────────────────────────────────────────────────────────────────────

-- Note: we no longer listen to UNIT_SPELLCAST_SUCCEEDED from other units. A
-- spellId from another player's cast is a "secret value" (Blizzard protection)
-- that cannot be used as a table key. Detection runs through the player's own
-- auras (SyncDebuff), which covers any caster and plays the sound on gain.
--
-- Important: in instanced combat Blizzard hides the *beneficial* lust buff from
-- C_UnitAuras.GetPlayerAuraBySpellID (it returns nil), while the matching
-- fatigue debuff (Sated/Exhaustion) stays readable. SyncDebuff therefore treats
-- "buff OR debuff present" as the lust being active, so the gain sound still
-- fires in combat where buff-only detection used to go silent.

local function OnPlayerStateRefresh(event)
    CheckPlayerHasBL()
    if not hasDebuff and playerClass then
        currentIcon = GetDefaultClassIcon(playerClass)
    end
    BL.ApplyVisuals()
end
BL:RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerStateRefresh)
BL:RegisterEvent("SPELLS_CHANGED", OnPlayerStateRefresh)

-- Returns the first player aura present from a set of spellIds, plus the spellId
-- it matched (needed to decide whether its timer fields are readable in combat).
local function FindPlayerAura(idSet)
    for spellId in pairs(idSet) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura then return aura, spellId end
    end
    return nil
end

local function SyncDebuff()
    if not BL.CfgGet("enabled") then
        moduleActive = false  -- re-enabling re-adopts the current lust silently
        return
    end

    local buff,   buffId = FindPlayerAura(BL_BUFFS)
    local debuff         = FindPlayerAura(BL_DEBUFFS)

    -- Track the real aura presence for ApplyVisuals. Note: in instanced combat
    -- Blizzard restricts the *beneficial* lust buff (GetPlayerAuraBySpellID
    -- returns nil for it), so `buff` is reliably visible only out of combat.
    -- The fatigue debuff (Sated/Exhaustion/Temporal Displacement) is flagged
    -- "never secret" and stays queryable in combat.
    hasBuff   = (buff ~= nil)
    hasDebuff = (debuff ~= nil)

    -- First pass after login or after the module was re-enabled: adopt whatever
    -- lust is already present WITHOUT announcing it, so a lingering buff / Sated
    -- never self-fires a "gained" or, once it expires, a false "ready".
    if not moduleActive then
        moduleActive  = true
        lustAnnounced = (buff ~= nil) or (debuff ~= nil)
        lastDebuffEnd = (debuff and debuff.expirationTime) or 0
    end

    if buff or debuff then
        -- A lust applies the buff and the fatigue debuff together, so the
        -- presence of EITHER means "lust active". Detecting via the debuff is
        -- what keeps the sound working in combat, where the buff is hidden.
        if not lustAnnounced then
            lustAnnounced = true
            -- Suppress the sound when we merely zoned into a lingering lust
            -- (stale-read window): a residual Sated shouldn't announce itself
            -- once the zone-settle delay lapses. Routed through the combo
            -- coordinator so nearly-simultaneous alerts collapse into one sound.
            if not ns.RecentlyZoned() and BL.CfgGet("soundOnBL") then
                ns.combo.Notify("bl", function() BL.PlaySound("soundPathBL") end)
            end
        end

        -- Pick the timer source. The lust BUFF gives the exact haste remaining
        -- but is "secret" (unreadable) in combat (it is not a never-secret aura);
        -- the fatigue DEBUFF is never-secret (readable in combat) and, being
        -- applied together with the lust, lets us estimate the active window in
        -- combat then show the cooldown after it.
        if buff and ns.AuraTimerReadable(buffId) then
            currentIcon = buff.icon
            blIcon.SetTimer(buff.expirationTime, buff.duration, GREEN)
        elseif debuff then
            currentIcon = debuff.icon
            -- Heuristic green: the debuff's start (expirationTime - duration) is
            -- when the lust was applied, so + the standard lust window is the
            -- active end. Green until then, the default (grey) cooldown after.
            -- Gate the green on being IN COMBAT: out of combat the readable buff
            -- is used above, so reaching here out of combat means the buff is nil
            -- = the lust ended or was cancelled → show grey, not a phantom green.
            local lustStart = (debuff.expirationTime or 0) - (debuff.duration or 0)
            local activeEnd = lustStart + BL_ACTIVE_DURATION
            if GetTime() < activeEnd and UnitAffectingCombat("player") then
                blIcon.SetTimer(activeEnd, BL_ACTIVE_DURATION, GREEN)
            else
                blIcon.SetTimer(debuff.expirationTime, debuff.duration)
            end
        elseif buff then
            -- Buff present but unreadable and no debuff (shouldn't happen — a
            -- lust always applies both). Show the class icon with no timer rather
            -- than read the buff's secret fields.
            currentIcon = GetDefaultClassIcon(playerClass) or currentIcon
            blIcon.ClearTimer()
        end
        -- Keep the fatigue end fresh whenever the debuff is visible (even while
        -- the green buff timer is showing), so the "ready" completion check
        -- below always validates against THIS cycle's Sated, never a stale one.
        if debuff then
            lastDebuffEnd = debuff.expirationTime or 0
        end
    else
        -- Neither aura present.
        if lustAnnounced then
            lustAnnounced = false
            currentIcon   = GetDefaultClassIcon(playerClass)
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
        -- Consume the recorded end so a stale value can never validate a future
        -- "ready" once we are back to the idle (no-lust) state.
        lastDebuffEnd = 0
    end

    BL.ApplyVisuals()
end

BL:ScheduleRepeatingTimer(function()
    -- Do ~zero work per tick while the module is disabled (S3 guard). Still flag
    -- the module inactive so a later re-enable re-adopts the lust state silently.
    if not BL.CfgGet("enabled") then
        moduleActive = false
        return
    end
    SyncDebuff()
end, 0.5)

-- Instant aura detection: UNIT_AURA fires the moment the player gains/loses an
-- aura, so SyncDebuff runs (and ns.combo.Notify("bl", ...) fires) without
-- waiting up to 500ms for the next ticker. Without this, a near-simultaneous
-- potion cast would flush as "potion combo" before BL is even detected.
-- AceEvent has no unit filter (no RegisterUnitEvent equivalent), so register
-- UNIT_AURA unfiltered and discard every fire whose unit token isn't "player".
BL:RegisterEvent("UNIT_AURA", function(event, unit)
    if unit ~= "player" then return end
    SyncDebuff()
end)

ns.RegisterReloadHook(function()
    BL.ApplyPosition()
    BL.ApplyFont()
    BL.ApplySize()
    BL.ApplyBorder()
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