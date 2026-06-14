-- Modules/Fader/Core/Fader.lua
-- BETA: customizable fade for the Cooldown Manager and the Player Frame.
--
-- Each group (cdm / player) fades to a configurable opacity, and "reveals" (snaps back
-- to full alpha) under chosen conditions: in combat, while a target is selected, or while
-- the mouse is over it. An "Active in" instance filter decides WHERE the fade operates at
-- all (e.g. only fade in raids) — outside those instances the frames stay fully opaque.
--
-- Fading is done with frame:SetAlpha, which is NOT a protected action, so this is safe in
-- combat and never taints the (protected) PlayerFrame / CooldownViewer. The opacity is
-- driven from a single throttled OnUpdate that lerps toward the target and re-applies it
-- every tick, so a Blizzard relayout that resets alpha can't leave a frame un-faded.

local ADDON, ns = ...
ns.Fader = ns.Fader or {}
local F = ns.Fader

-- Per-group defaults (see file header). enabled defaults OFF — this is opt-in (Beta).
local GROUP_DEFAULT = {
    enabled         = false,
    fadedAlpha      = 0.3,
    revealCombat    = true,
    revealTarget    = false,
    revealMouseover = true,
    instanceFilter  = { dungeon = true, raid = true, battleground = true, outdoor = true },
}
local DEFAULTS = {
    cdm    = GROUP_DEFAULT,
    player = GROUP_DEFAULT,
}

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.fader end
function F.GroupCfg(key) local c = Cfg(); return c and c[key] end

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    p.fader = p.fader or {}
    ns.MergeDefaults(p.fader, DEFAULTS)
end
ns.RegisterCfgInitHook(InitCfg)

-- ── Frame groups ──────────────────────────────────────────────────────────────
-- Resolved live (the CooldownViewers only exist when Blizzard's Cooldown Manager is on;
-- absent globals are simply skipped). SetAlpha on a parent fades all of its children.
local CDM_FRAMES = {
    "EssentialCooldownViewer", "UtilityCooldownViewer",
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
}
local function CDMFrames()
    local t = {}
    for _, name in ipairs(CDM_FRAMES) do
        local f = _G[name]
        if f then t[#t + 1] = f end
    end
    return t
end
local function PlayerFrames()
    return PlayerFrame and { PlayerFrame } or {}
end
local GROUPS = {
    cdm    = { frames = CDMFrames },
    player = { frames = PlayerFrames },
}

-- ── Target opacity for a group ──────────────────────────────────────────────────
local function TargetAlpha(key, frames)
    local c = F.GroupCfg(key)
    if not c or not c.enabled then return 1 end
    if not ns.IsActiveInInstance(c.instanceFilter) then return 1 end   -- fade not active here
    if c.revealCombat and InCombatLockdown() then return 1 end
    if c.revealTarget and UnitExists("target") then return 1 end
    if c.revealMouseover then
        for _, f in ipairs(frames) do
            if f:IsShown() and f:IsMouseOver() then return 1 end
        end
    end
    return c.fadedAlpha or 0.3
end

-- ── Smooth fade driver ──────────────────────────────────────────────────────────
local cur = { cdm = 1, player = 1 }   -- current (lerped) alpha per group
local FADE_SPEED = 3.5                -- alpha units / second (~0.3s for a full fade)

local driver = CreateFrame("Frame")
driver:Hide()
local accum = 0
driver:SetScript("OnUpdate", function(_, dt)
    accum = accum + dt
    if accum < 0.03 then return end
    local step = FADE_SPEED * accum
    accum = 0
    local anyActive = false
    for key, g in pairs(GROUPS) do
        local c = F.GroupCfg(key)
        if c and c.enabled then
            anyActive = true
            local frames = g.frames()
            local target = TargetAlpha(key, frames)
            local a = cur[key]
            if a < target then a = math.min(target, a + step)
            elseif a > target then a = math.max(target, a - step) end
            cur[key] = a
            for _, f in ipairs(frames) do f:SetAlpha(a) end   -- re-applied each tick (wins over relayouts)
        end
    end
    if not anyActive then driver:Hide() end
end)

-- (Re)evaluate which groups are enabled: start the driver for enabled ones, restore full
-- opacity for disabled ones. Called on config change, reload-hook (profile switch) + login.
function F.Apply()
    local anyEnabled = false
    for key, g in pairs(GROUPS) do
        local c = F.GroupCfg(key)
        if c and c.enabled then
            anyEnabled = true
        else
            cur[key] = 1
            for _, f in ipairs(g.frames()) do f:SetAlpha(1) end
        end
    end
    if anyEnabled then driver:Show() else driver:Hide() end
end

ns.RegisterReloadHook(F.Apply)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_ENTERING_WORLD")   -- frames exist + instance type settled
init:SetScript("OnEvent", function() F.Apply() end)
