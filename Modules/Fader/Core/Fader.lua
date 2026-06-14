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
-- `hover` is a per-component map: hovering an ENABLED component reveals the whole group.
-- The CDM group has one entry per CDM sub-component; the player group has just itself.
local DEFAULTS = {
    cdm = {
        enabled        = false,
        fadedAlpha     = 0.3,
        revealCombat   = true,
        revealTarget   = false,
        hover          = { essentials = true, utility = true, belowPlayer = true, buffs = true, bars = true },
        instanceFilter = { dungeon = true, raid = true, battleground = true, outdoor = true },
    },
    player = {
        enabled        = false,
        fadedAlpha     = 0.3,
        revealCombat   = true,
        revealTarget   = false,
        hover          = { player = true },
        instanceFilter = { dungeon = true, raid = true, battleground = true, outdoor = true },
    },
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

-- ── Frame groups + components ────────────────────────────────────────────────
-- A group fades as ONE unit (one alpha over the union of all its component frames),
-- but each component has its own hover flag: hovering an enabled component reveals the
-- whole group. CDM components combine the native CooldownViewer (when present) with OUR
-- tracker icons placed in that destination (anchored to the viewer, not children of it,
-- so they need fading directly). All frames are resolved live; absent ones are skipped.
local GROUPS = {
    cdm = {
        components = {
            { key = "essentials",  native = "EssentialCooldownViewer", dest = "essential"   },
            { key = "utility",     native = "UtilityCooldownViewer",   dest = "utility"     },
            { key = "belowPlayer",                                     dest = "belowPlayer" },
            { key = "buffs",       native = "BuffIconCooldownViewer"   },
            { key = "bars",        native = "BuffBarCooldownViewer"    },
        },
    },
    player = {
        components = {
            { key = "player", playerFrame = true },
        },
    },
}

-- Append a component's live frames to `out`.
local function ComponentFrames(comp, out)
    if comp.playerFrame then
        -- Custom unit-frame addons (ElvUI / Unhalted / …) replace Blizzard's PlayerFrame,
        -- so fade whichever player frame(s) actually exist, not just the Blizzard one.
        if ns.CDMAnchor and ns.CDMAnchor.GetPlayerFrames then
            for _, f in ipairs(ns.CDMAnchor.GetPlayerFrames()) do out[#out + 1] = f end
        elseif PlayerFrame then
            out[#out + 1] = PlayerFrame
        end
        return out
    end
    if comp.native then
        local f = _G[comp.native]
        if f then out[#out + 1] = f end
    end
    if comp.dest and ns.CDMAnchor and ns.CDMAnchor.GetIconFrames then
        for _, f in ipairs(ns.CDMAnchor.GetIconFrames(comp.dest)) do out[#out + 1] = f end
    end
    return out
end

-- One pass over a group: build the union of all its frames AND decide the target alpha
-- (1 when not active in this instance, or revealed by combat / target / a hovered
-- enabled component; else the faded opacity). Returns target, frameList.
local function Evaluate(g, c)
    local active = ns.IsActiveInInstance(c.instanceFilter)
    local reveal = active and (
        (c.revealCombat and InCombatLockdown()) or
        (c.revealTarget and UnitExists("target"))
    ) or false
    local all = {}
    for _, comp in ipairs(g.components) do
        local hoverOn = active and not reveal and c.hover and c.hover[comp.key]
        local n0 = #all
        ComponentFrames(comp, all)
        if hoverOn then
            for i = n0 + 1, #all do
                local f = all[i]
                if f:IsShown() and f:IsMouseOver() then reveal = true; break end
            end
        end
    end
    local target = (not active or reveal) and 1 or (c.fadedAlpha or 0.3)
    return target, all
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
            local target, frames = Evaluate(g, c)
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
            local frames = {}
            for _, comp in ipairs(g.components) do ComponentFrames(comp, frames) end
            for _, f in ipairs(frames) do f:SetAlpha(1) end
        end
    end
    if anyEnabled then driver:Show() else driver:Hide() end
end

ns.RegisterReloadHook(F.Apply)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_ENTERING_WORLD")   -- frames exist + instance type settled
init:SetScript("OnEvent", function() F.Apply() end)
