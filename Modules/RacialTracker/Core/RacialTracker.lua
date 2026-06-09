-- Modules/RacialTracker/Core/RacialTracker.lua
-- Tracks the player's racial ability the way the trinket / potion trackers track
-- their items: grey cooldown swipe while it recharges, a green "active" timer
-- while its self-buff is up, and a "ready" check + sound when it comes back.
--
-- The racial is auto-detected: the first spellId from RACIAL_SPELLS that the
-- player KNOWS (IsPlayerSpell) is tracked. A manual spellOverride (config) wins
-- when > 0, so a race not yet in the list can still be tracked by hand.

local _, ns = ...
ns.RacialTracker = ns.RacialTracker or {}
local RT = ns.RacialTracker

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(RT)
AceTimer:Embed(RT)

-- In combat the player's own spell cooldown/aura fields come back as "secret
-- values": reading or comparing one taints + errors. Guarded so a client without
-- the secret-values system (where the global is absent) still loads.
local issecretvalue = issecretvalue or function() return false end

-- ── Racial spell data ────────────────────────────────────────────────────────
-- Candidate cast spellIds (the on-use racial with a cooldown), incl. every
-- class-specific variant (Arcane Torrent, Gift of the Naaru). Detection picks the
-- first one IsPlayerSpell reports the player knows; a player only ever knows one.
-- Verified against warcraft.wiki.gg / wowhead.
local RACIAL_SPELLS = {
    59752,  -- Will to Survive (Human)
    20594,  -- Stoneform (Dwarf)
    20589,  -- Escape Artist (Gnome)
    58984,  -- Shadowmeld (Night Elf)
    68992,  -- Darkflight (Worgen)
    107079, -- Quaking Palm (Pandaren)
    7744,   -- Will of the Forsaken (Undead)
    20549,  -- War Stomp (Tauren)
    26297,  -- Berserking (Troll)
    69041,  -- Rocket Barrage (Goblin)
    256948, -- Spatial Rift (Void Elf)
    255647, -- Light's Judgment (Lightforged Draenei)
    265221, -- Fireblood (Dark Iron Dwarf)
    287712, -- Haymaker (Kul Tiran)
    312924, -- Hyper Organic Light Originator / HOLO (Mechagnome)
    260364, -- Arcane Pulse (Nightborne)
    255654, -- Bull Rush (Highmountain Tauren)
    274738, -- Ancestral Call (Mag'har Orc)
    291944, -- Regeneratin' (Zandalari Troll)
    312411, -- Bag of Tricks (Vulpera)
    357214, -- Wing Buffet (Dracthyr)
    436344, -- Azerite Surge (Earthen)
    -- Blood Fury variants (Orc) — by class resource
    20572,  --   attack power (Warrior/Rogue/Hunter/DK)
    33702,  --   spell power (Mage/Warlock)
    33697,  --   AP + SP (Shaman/Monk)
    -- Gift of the Naaru variants (Draenei / Lightforged)
    28880,  --   base / catch-all
    59542, 59543, 59544, 59545, 59547, 59548, 121093,
    -- Arcane Torrent variants (Blood Elf) — by class resource
    28730,  --   Mage/Warlock (mana)
    25046,  --   Rogue
    50613,  --   Death Knight
    69179,  --   Warrior
    80483,  --   Hunter
    129597, --   Monk
    155145, --   Paladin
    202719, --   Demon Hunter
    232633, --   Priest
}

-- castSpellId -> the aura spellId the racial applies while active (for the green
-- "buff up" timer). Only racials that grant a trackable SELF-buff appear here;
-- non-buff racials (stuns, dispels, silences) show only the cooldown. The
-- in-combat heuristic green is gated on membership here so a stun's parsed
-- "for N sec" never paints a phantom green.
-- Racials with a tracked timed self-aura → a green "active" countdown. Each entry
-- is { auras = {aura spellIds to watch — any present = active}, dur = window length
-- (s) for the in-combat estimate }. Includes re-press windows (Spatial Rift's
-- reactivation, Ancestral Call's random secondary-stat buff). No/until-move auras
-- (Shadowmeld, Bull Rush, Will of the Forsaken) are omitted — cooldown only.
local RACIAL_BUFF_AURA = {
    [20594]  = { auras = { 65116 },  dur = 8 },   -- Stoneform (Dwarf)
    [68992]  = { auras = { 68992 },  dur = 10 },  -- Darkflight (Worgen)
    [20572]  = { auras = { 20572 },  dur = 15 },  -- Blood Fury AP (Orc)
    [33702]  = { auras = { 33702 },  dur = 15 },  -- Blood Fury SP (Orc)
    [33697]  = { auras = { 33697 },  dur = 15 },  -- Blood Fury AP+SP (Orc)
    [26297]  = { auras = { 26297 },  dur = 10 },  -- Berserking (Troll)
    [265221] = { auras = { 265221 }, dur = 8 },   -- Fireblood (Dark Iron Dwarf)
    [291944] = { auras = { 291944 }, dur = 6 },   -- Regeneratin' (Zandalari Troll)
    [312924] = { auras = { 312924 }, dur = 15 },  -- HOLO (Mechagnome)
    [256948] = { auras = { 256948, 257040 }, dur = 8 },                  -- Spatial Rift reactivation window (Void Elf)
    [274738] = { auras = { 274739, 274740, 274741, 274742 }, dur = 15 }, -- Ancestral Call random stat buff (Mag'har Orc)
}

-- Known cooldown lengths (s), used ONLY for the in-combat estimate when the live
-- spell cooldown comes back as a secret value. An exact value learned from a
-- readable (out-of-combat) cooldown overrides these, so patch tweaks self-correct.
local RACIAL_COOLDOWN = {
    [59752] = 180, [20594] = 120, [20589] = 60,  [58984] = 120, [68992] = 90,
    [107079] = 120, [7744] = 120, [20549] = 90,  [26297] = 180, [69041] = 90,
    [256948] = 180, [255647] = 150, [265221] = 120, [287712] = 150, [312924] = 180,
    [260364] = 180, [255654] = 120, [274738] = 120, [291944] = 180, [312411] = 90,
    [357214] = 180, [436344] = 120,
    [20572] = 120, [33702] = 120, [33697] = 120,                     -- Blood Fury
    [28880] = 120, [59542] = 120, [59543] = 120, [59544] = 120,      -- Gift of the Naaru
    [59545] = 120, [59547] = 120, [59548] = 120, [121093] = 120,
    [28730] = 90, [25046] = 90, [50613] = 90, [69179] = 90, [80483] = 90,  -- Arcane Torrent
    [129597] = 90, [155145] = 90, [202719] = 90, [232633] = 90,
}

local FALLBACK_ICON = 134400  -- question mark, shown only by Test when no racial is known

-- ── State ────────────────────────────────────────────────────────────────────
local racialSpellId = nil   -- resolved cast spellId being tracked (or nil)
local racialIconId  = nil   -- cached iconID for racialSpellId
local hasCooldown   = false
local lastExpiry    = nil   -- GetTime() at which the tracked cooldown ends
local lastUseAt     = nil   -- GetTime() of the last cast (for the in-combat heuristic)
local learnedCd     = {}    -- castSpellId -> cooldown length seen readable, out of combat

-- Test mode: fabricates a cooldown so the icon / timer / ready cycle previews.
RT.testMode    = false
local testEndsAt = 0
local TEST_DURATION = 8

-- ── TimerIcon ────────────────────────────────────────────────────────────────
local racialIcon = ns.ui.CreateTimerIcon({
    name    = "RacialTrackerFrame",
    getCfg  = function(key) return RT.CfgGet(key) end,
    onDragStop = function(x, y)
        RT.CfgSet("posX", x)
        RT.CfgSet("posY", y)
        if RT.pe then RT.pe.Refresh() end
    end,
})
racialIcon.onExpire = function() end

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(RT.CfgGet("instanceFilter"))
end

local function SpellKnown(id)
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

-- Resolve which spellId to track: the manual override (if > 0), else the first
-- known racial from the list. Re-run on login / SPELLS_CHANGED (spec / race form
-- changes can swap which racial is known, e.g. class-specific Arcane Torrent).
local function ResolveRacial()
    local prev = racialSpellId
    local override = RT.CfgGet("spellOverride")
    if override and override > 0 then
        racialSpellId = override
    else
        racialSpellId = nil
        for _, id in ipairs(RACIAL_SPELLS) do
            if SpellKnown(id) then racialSpellId = id break end
        end
    end
    if racialSpellId ~= prev then racialIconId = nil end  -- re-resolve the icon
end

-- The racial's iconID is invariant once resolved; C_Spell.GetSpellInfo can return
-- nil while data loads, so the nil is not cached.
local function GetRacialIcon()
    if not racialSpellId then return FALLBACK_ICON end
    if not racialIconId then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(racialSpellId)
        racialIconId = info and info.iconID
    end
    return racialIconId or FALLBACK_ICON
end

-- Cross-version spell cooldown: returns start, duration (seconds).
local function GetCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(id)
        if cd then return cd.startTime, cd.duration end
        return 0, 0
    end
    local start, duration = GetSpellCooldown(id)
    return start or 0, duration or 0
end

-- ── Main sync (cooldown + buff + ready), mirrors ItemTracker.ApplyVisuals ──────
function RT.ApplyVisuals()
    -- Auto-stop a finished test before evaluating visibility.
    if RT.testMode and GetTime() >= testEndsAt then
        RT.testMode = false
    end

    if (not RT.testMode and (not RT.CfgGet("enabled") or not IsActiveInCurrentInstance()))
        or not RT.CfgGet("showIcon") then
        racialIcon.Hide()
        return
    end
    if not racialSpellId and not RT.testMode then
        -- The player's race has no trackable racial (or it isn't in the list and no
        -- override is set): nothing to show.
        racialIcon.Hide()
        return
    end

    racialIcon.SetIcon(GetRacialIcon())
    racialIcon.ApplySize()
    racialIcon.Show()

    -- ── Test mode: fabricate a cooldown so the icon / timer / border preview. ──
    -- (testMode is cleared at the top once testEndsAt passes, so here it is always
    -- still counting down.)
    if RT.testMode then
        racialIcon.SetTimer(testEndsAt, TEST_DURATION)
        racialIcon.HideCheck()
        return
    end

    -- ── Green "active" timer while a tracked self-aura is up — incl. re-press
    -- windows (Spatial Rift reactivation) and Ancestral Call's random stat buff. ──
    local foundBuff = false
    local binfo = RACIAL_BUFF_AURA[racialSpellId]
    if binfo then
        -- First of the watched auras that is present drives the green.
        local aura, matchedId
        for _, aid in ipairs(binfo.auras) do
            local a = C_UnitAuras.GetPlayerAuraBySpellID(aid)
            if a then aura, matchedId = a, aid break end
        end
        if aura and ns.AuraTimerReadable(matchedId) then
            foundBuff = true
            racialIcon.SetTimer(aura.expirationTime, aura.duration, { r = 0, g = 1, b = 0 })
            racialIcon.HideCheck()
        elseif lastUseAt and UnitAffectingCombat("player") and GetTime() < lastUseAt + binfo.dur then
            -- In combat the aura is hidden/secret: estimate the window from the
            -- recorded cast time + its known length (the trinket-tracker heuristic).
            foundBuff = true
            racialIcon.SetTimer(lastUseAt + binfo.dur, binfo.dur, { r = 0, g = 1, b = 0 })
            racialIcon.HideCheck()
        end
    end

    if not foundBuff then
        local start, duration = GetCooldown(racialSpellId)
        if issecretvalue(start) or issecretvalue(duration) then
            -- In combat the cooldown timing is a secret value (reading/comparing one
            -- taints + errors). Estimate the recharge from the recorded cast time +
            -- the cooldown length (learned out of combat, else seeded).
            local cdDur = learnedCd[racialSpellId] or RACIAL_COOLDOWN[racialSpellId]
            if lastUseAt and cdDur and GetTime() < lastUseAt + cdDur then
                hasCooldown = true
                lastExpiry = lastUseAt + cdDur
                racialIcon.SetTimer(lastExpiry, cdDur)
                racialIcon.HideCheck()
            end
            -- No usable estimate while secret: leave the icon as-is rather than
            -- firing a false "ready" on data we cannot read.
        elseif start and start > 0 and duration and duration > 2.5 then
            -- Readable (out of combat): the exact cooldown. Remember its length so
            -- the in-combat estimate above tracks the current patch's value.
            learnedCd[racialSpellId] = duration
            hasCooldown = true
            lastExpiry = start + duration
            racialIcon.SetTimer(start + duration, duration)
            racialIcon.HideCheck()
        elseif duration and duration > 0 then
            -- GCD blip or a not-yet-populated cooldown: indeterminate, keep state.
        else
            if hasCooldown then
                hasCooldown = false
                -- Real "ready" only if the cooldown actually reached its recorded
                -- end AND we are not in the post-loading-screen settle window.
                local completed = lastExpiry and (GetTime() >= lastExpiry - ns.READY_EPSILON)
                if completed and not ns.RecentlyZoned() then
                    if RT.CfgGet("soundOnReady") then RT.PlaySound("soundReady") end
                    racialIcon.ClearTimer()
                    racialIcon.BlinkCheck()  -- flash once, then auto-hide
                else
                    racialIcon.ClearTimer()
                    racialIcon.HideCheck()
                end
            else
                racialIcon.ClearTimer()
            end
        end
    end
end

-- ApplyAll is the name the config window + reload hook call.
function RT.ApplyAll() RT.ApplyVisuals() end

-- ── Test ─────────────────────────────────────────────────────────────────────
function RT.RunTest()
    RT.testMode = true
    testEndsAt  = GetTime() + TEST_DURATION
    if RT.CfgGet("soundOnUse") then RT.PlaySound("soundUse") end
    RT.ApplyVisuals()
end
function RT.StopTest()
    RT.testMode = false
    racialIcon.ClearTimer()
    racialIcon.HideCheck()
    RT.ApplyVisuals()
end
function RT.IsTesting() return RT.testMode end

-- ── Public API (single-icon passthroughs, like BL / PI) ──────────────────────
function RT.ApplyFont()          racialIcon.ApplyFont()  end
function RT.ApplyTimerVisuals()  racialIcon.ApplyFont()  end  -- font/size/outline; colour is read live
function RT.ApplyPosition()      racialIcon.ApplyPosition() end
function RT.ApplySize()          racialIcon.ApplySize()  end
function RT.ApplyBorder()        racialIcon.ApplyBorder() end
function RT.SetUnlocked(v)       racialIcon.SetUnlocked(v) end
function RT.IsUnlocked()         return racialIcon.IsUnlocked() end
function RT.GetFrame()           return racialIcon.GetFrame() end
function RT.GetSpellId()         return racialSpellId end
-- Re-detect the tracked racial (e.g. after the config changes the spellId
-- override) and refresh the icon.
function RT.ResolveAndApply()    ResolveRacial(); RT.ApplyVisuals() end

-- ── Events ───────────────────────────────────────────────────────────────────
local function OnSpellsRefresh()
    ResolveRacial()
    RT.ApplyVisuals()
end
RT:RegisterEvent("PLAYER_ENTERING_WORLD", OnSpellsRefresh)
RT:RegisterEvent("SPELLS_CHANGED", OnSpellsRefresh)

-- The player's OWN cast spellId is readable (unlike another unit's, which is a
-- secret value). UNIT_SPELLCAST_SUCCEEDED fires many times/sec in combat, so do
-- the cheap unit/spell test first and only act on the racial.
RT:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(event, unit, _, spellId)
    if unit ~= "player" then return end
    if racialSpellId and spellId == racialSpellId then
        lastUseAt = GetTime()
        if RT.CfgGet("soundOnUse") then RT.PlaySound("soundUse") end
    end
end)

-- Instant buff detection: UNIT_AURA on the player fires the moment the racial's
-- buff is gained/lost, so the green timer reacts without waiting for the ticker.
RT:RegisterEvent("UNIT_AURA", function(event, unit)
    if unit ~= "player" then return end
    if RT.CfgGet("enabled") then RT.ApplyVisuals() end
end)

RT:ScheduleRepeatingTimer(function()
    if not RT.CfgGet("enabled") and not RT.testMode then return end
    RT.ApplyVisuals()
end, 0.5)

ns.RegisterReloadHook(function()
    ResolveRacial()
    RT.ApplyPosition()
    RT.ApplyFont()
    RT.ApplySize()
    RT.ApplyBorder()
    RT.ApplyVisuals()
end)

local initRT = CreateFrame("Frame")
initRT:RegisterEvent("PLAYER_LOGIN")
initRT:SetScript("OnEvent", function(self)
    ResolveRacial()
    RT.ApplyPosition()
    RT.ApplyFont()
    RT.ApplySize()
    RT.ApplyVisuals()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
