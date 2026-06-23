-- Modules/PITracker/Core/PITracker.lua

local _, ns = ...
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

-- Shared read-only "active buff" colour (PI yellow), hoisted so the 0.5s visuals
-- tick doesn't allocate a fresh table each pass while the timer is shown (SetTimer
-- only stores the reference and reads r/g/b, never mutates it).
local PI_YELLOW = { r = 1, g = 1, b = 0 }

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(PI)
AceTimer:Embed(PI)

local PI_SPELL_ID  = 10060
local PI_ICON_ID   = 135960 -- native Power Infusion icon

local playerHasPI  = false
local hasBuff      = false
-- True until the first buff sync runs, so a Power Infusion that is already up at
-- login / reload is adopted silently instead of replaying the "gained" sound.
local firstSync    = true

local piIcon = ns.ui.CreateTimerIcon({
    name    = "PITrackerFrame",
    getCfg  = function(key) return PI.CfgGet(key) end,
    setCfg  = function(key, val) PI.CfgSet(key, val) end,   -- cdmAtEnd flip on a cross-strip drag
    getSpellId = function() return PI_SPELL_ID end,        -- your own Power Infusion -> keybind (nil-resolved if unbound)
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
    playerHasPI = class == "PRIEST"
end

-- Power Infusion's iconID is constant for the session, so resolve it once and
-- cache it. C_Spell.GetSpellInfo can return nil while spell data is still
-- loading, so keep trying (don't cache the nil) until it resolves.
local piIconID
local function GetPIIcon()
    if not piIconID then
        local spellInfo = C_Spell.GetSpellInfo(PI_SPELL_ID)
        piIconID = spellInfo and spellInfo.iconID
    end
    return piIconID or PI_ICON_ID
end

function PI.ApplyVisuals()
    -- Test mode bypasses the instance filter so the preview always works.
    if (not PI.testMode and (not PI.CfgGet("enabled") or not IsActiveInCurrentInstance()))
        or not PI.CfgGet("showIcon") then
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
    -- The green check is no longer a persistent "PI available" badge — it
    -- only flashes briefly when the buff fades (see SyncBuff). While the
    -- buff is active the timer occupies the icon.
    if hasBuff then
        piIcon.HideCheck()
    end
end

-- Test-mode state: when active, SyncBuff fabricates an aura so the icon,
-- glow, timer and sound react exactly as if the player had just received PI.
PI.testMode      = false
PI.testStartTime = 0
PI.testEndsAt    = 0

local function SyncBuff(opts)
    if not PI.CfgGet("enabled") then return end
    local forceAnnounce = opts and opts.forceAnnounce

    -- Auto-stop the test once its duration elapses.
    if PI.testMode and GetTime() >= PI.testEndsAt then
        PI.testMode = false
    end

    local aura
    if PI.testMode then
        aura = {
            expirationTime = PI.testEndsAt,
            duration       = PI.testEndsAt - PI.testStartTime,
        }
    else
        -- Out-of-combat only: in instanced combat Blizzard flags the Power
        -- Infusion buff as a "secret" aura, so GetPlayerAuraBySpellID returns
        -- nil for it (verified in-game). Unlike BLTracker there is no non-secret
        -- fallback — PI has no fatigue debuff, its cooldown sits on the priest,
        -- and registering COMBAT_LOG_EVENT_UNFILTERED is forbidden to addons
        -- inside instances. The only in-combat signal would be the raw haste
        -- spike (UnitSpellHaste), a heuristic too false-positive-prone to use.
        aura = C_UnitAuras.GetPlayerAuraBySpellID(PI_SPELL_ID)
    end

    if aura then
        if not hasBuff or forceAnnounce then
            local wasNew = not hasBuff
            hasBuff = true
            piIcon.SetGlow(true)
            -- Announce (sound) only for a genuinely new application or an explicit
            -- Test click — NOT when silently adopting a buff already up at the
            -- first sync (login / reload), and NOT during the post-loading-screen
            -- settle window where aura reads are unreliable (matches BLTracker).
            local announce = forceAnnounce or (wasNew and not firstSync and not ns.RecentlyZoned())
            if announce and PI.CfgGet("soundOnPI") then
                PI.PlaySound()
            end
        end
        piIcon.SetTimer(aura.expirationTime, aura.duration, PI_YELLOW)
        piIcon.HideCheck()
    elseif hasBuff then
        hasBuff = false
        piIcon.SetGlow(false)
        piIcon.ClearTimer()
        piIcon.BlinkCheck()  -- flash to signal PI is back up
    end
    firstSync = false
    PI.ApplyVisuals()
end

function PI.RunTest(duration)
    duration = duration or 20
    local now = GetTime()
    PI.testMode      = true
    PI.testStartTime = now
    PI.testEndsAt    = now + duration
    -- Run immediately with forceAnnounce so the glow + sound fire right when the
    -- user clicks Test — even if the real PI buff happens to be active already
    -- (without the force flag the false→true transition would be skipped).
    SyncBuff({ forceAnnounce = true })
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PI.ApplyFont()     piIcon.ApplyFont()     end
function PI.ApplyPosition() piIcon.ApplyPosition() end
function PI.ApplySize()     piIcon.ApplySize()     end
function PI.ApplyBorder()   piIcon.ApplyBorder()   end
function PI.SetUnlocked(v)  piIcon.SetUnlocked(v)  end
function PI.IsUnlocked()    return piIcon.IsUnlocked() end
function PI.GetFrame()      return piIcon.GetFrame()   end

-- ── Events ────────────────────────────────────────────────────────────────────

local function OnPlayerStateRefresh(event)
    CheckPlayerHasPI()
    PI.ApplyVisuals()
end
PI:RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerStateRefresh)
PI:RegisterEvent("SPELLS_CHANGED", OnPlayerStateRefresh)

-- Near-instant detection: a player aura change drives the glow / sound / timer
-- on the next frame instead of waiting up to 0.5s for the next ticker pass. The
-- shared coalescing dispatcher owns the unit-filtered UNIT_AURA frame, so we no
-- longer wake for every raid member's aura change (matches BLTracker).
ns.AuraDispatch.Register("player", function()
    SyncBuff()
end)

-- 0.5s polling ticker. While the module is disabled (which, since the Midnight hard-off, is always)
-- the ticker is NOT scheduled at all, so there are zero per-tick wakeups. Start/Stop are idempotent
-- and drive the live enable transition from the config UI set handler.
local piTicker
function PI.Start()
    if piTicker then return end                 -- already running
    if not PI.CfgGet("enabled") then return end  -- never run while disabled
    piTicker = PI:ScheduleRepeatingTimer(function() SyncBuff() end, 0.5)
end
function PI.Stop()
    if piTicker then PI:CancelTimer(piTicker); piTicker = nil end
end
function PI.SetEnabled(on)
    if on then PI.Start() else PI.Stop() end
end

ns.RegisterReloadHook(function()
    if ns.ReseedTrackerOverride then
        ns.ReseedTrackerOverride("PITrackerFrame", PI.CfgGet("cdmDest") or "essential", ns.DefaultTrackerTimerSeed)
    end
    PI.ApplyPosition()
    PI.ApplyFont()
    PI.ApplySize()
    PI.ApplyBorder()
    PI.ApplyVisuals()
end)

local initPI = CreateFrame("Frame")
initPI:RegisterEvent("PLAYER_LOGIN")
initPI:SetScript("OnEvent", function(self)
    if ns.ReseedTrackerOverride then
        ns.ReseedTrackerOverride("PITrackerFrame", PI.CfgGet("cdmDest") or "essential", ns.DefaultTrackerTimerSeed)
    end
    CheckPlayerHasPI()
    PI.ApplyPosition()
    PI.ApplyFont()
    PI.ApplySize()
    PI.ApplyVisuals()
    PI.Start()  -- no-op while disabled; only schedules the ticker if enabled
    self:UnregisterEvent("PLAYER_LOGIN")
end)
