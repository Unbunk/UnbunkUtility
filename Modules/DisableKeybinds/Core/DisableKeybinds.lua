-- Modules/DisableKeybinds/Core/DisableKeybinds.lua
-- Owner utility: disable chosen keybinds by context using a user-defined list of
-- "profiles". Each profile carries a list of key chords to disable plus three condition
-- cadres — INSTANCE type (dungeon / raid / battleground / outdoor), GROUP type (group /
-- raid group / solo) and COMBAT state (in / out of combat). A condition cadre with no box
-- ticked is "no constraint"; otherwise the current context must match one of its ticked
-- options (OR within a cadre). A profile is active when ALL its constrained cadres match
-- (AND across cadres) — and only while the profile AND the whole module are enabled.
--
-- WHY a secure state driver: changing key bindings is FORBIDDEN to insecure (addon) code
-- in combat — ClearOverrideBindings / SetOverrideBindingClick simply do nothing mid-fight
-- (Bartender4 etc. bail out when InCombatLockdown()). But a feature keyed on COMBAT state
-- must flip bindings exactly at the combat boundary. So a SECURE state-handler frame owns
-- the override bindings: out of combat we precompute the keys to kill in each combat state
-- (instance/group only change out of combat, so they're evaluated in plain Lua) and store
-- them as attributes; a `[combat]` state driver then re-binds them SECURELY on every combat
-- transition (allowed because the secure environment may touch bindings in combat). Each
-- key is bound to "click" an inert button, so the key does nothing while disabled.
--
-- Per-profile config lives in ns.db.profile.disableKeybinds, so a profile reset clears the
-- list; the module is disabled by default and only reachable from the owner-gated
-- "Personal utilities" tab.

local _, ns = ...
ns.DisableKeybinds = ns.DisableKeybinds or {}
local DK = ns.DisableKeybinds

-- Template for a single profile entry. New profiles deep-copy this; existing ones are
-- backfilled key-by-key in InitCfg so older saved profiles gain any new fields.
local PROFILE_DEFAULTS = {
    enabled  = true,                 -- per-profile enable
    instance = {                     -- "Instance type" cadre (no box => no constraint)
        dungeon      = false,        -- 5-player ("party")
        raid         = false,        -- raid instance ("raid")
        battleground = false,        -- ("pvp")
        outdoor      = false,        -- open world ("none")
    },
    group = {                        -- "Group type" cadre
        group = false,               -- party of 2-5
        raid  = false,               -- raid group
        solo  = false,               -- not in a group
    },
    combat = {                       -- "Combat state" cadre
        inCombat    = false,
        outOfCombat = false,
    },
    keys = {},                       -- { "Q", "SHIFT-E", ... } chord strings to disable
}
DK.PROFILE_DEFAULTS = PROFILE_DEFAULTS

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.disableKeybinds end
DK.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    p.disableKeybinds = p.disableKeybinds or {}
    local c = p.disableKeybinds
    if c.enabled == nil then c.enabled = false end
    c.profiles = c.profiles or {}
    for _, prof in ipairs(c.profiles) do
        ns.MergeDefaults(prof, PROFILE_DEFAULTS)
    end
end
ns.RegisterCfgInitHook(InitCfg)

-- ── Profile list mutation (called by the config panel) ────────────────────────
function DK.NewProfile()
    local c = Cfg(); if not c then return nil end
    c.profiles = c.profiles or {}
    local p = ns.DeepCopy(PROFILE_DEFAULTS)
    c.profiles[#c.profiles + 1] = p
    DK.Apply()
    return p
end

function DK.RemoveProfile(p)
    local c = Cfg(); if not c or not c.profiles then return end
    for i, pp in ipairs(c.profiles) do
        if pp == p then table.remove(c.profiles, i); break end
    end
    DK.Apply()
end

-- ── Context evaluation (instance + group; combat is handled securely below) ───
-- Each cadre returns true when it imposes no constraint (nothing ticked) OR the current
-- context matches one of its ticked options. Instance / group only change out of combat,
-- so plain Lua is fine for them.
local function InstanceMet(ins)
    if not ins then return true end
    if not (ins.dungeon or ins.raid or ins.battleground or ins.outdoor) then return true end
    local _, t = IsInInstance()
    if ins.dungeon      and t == "party" then return true end
    if ins.raid         and t == "raid"  then return true end
    if ins.battleground and t == "pvp"   then return true end
    if ins.outdoor      and t == "none"  then return true end
    return false
end

local function GroupMet(g)
    if not g then return true end
    if not (g.group or g.raid or g.solo) then return true end
    local inGroup, inRaid = IsInGroup(), IsInRaid()
    if g.solo  and not inGroup            then return true end
    if g.group and inGroup and not inRaid then return true end
    if g.raid  and inRaid                 then return true end
    return false
end

-- ── Secure binding driver ─────────────────────────────────────────────────────
-- The inert click target: a key bound to "click" this button does nothing (no OnClick),
-- which is what effectively disables it.
local eater = _G["UnbunkDisabledKeyEater"] or CreateFrame("Button", "UnbunkDisabledKeyEater", UIParent)

-- Secure owner of the override bindings. The `apply` snippet (rebuilt in Lua whenever the
-- key sets change — see RebuildSnippet) clears then re-binds the keys for the combat state
-- it's run with; the `[combat]` driver runs it on every transition (combat-safe: it's the
-- secure environment that touches the bindings), and DK.Apply runs it out of combat. The
-- snippet is plain ClearBindings + per-key SetBindingClick calls (no string parsing in the
-- restricted env), and is compiled out of combat so the in-combat run reuses the cache.
local header = CreateFrame("Frame", "UnbunkDisableKeybindsSecure", UIParent, "SecureHandlerStateTemplate")
header:SetAttribute("apply", "self:ClearBindings()")   -- empty default until first rebuild
header:SetAttribute("_onstate-combat", [[ self:RunAttribute("apply", newstate) ]])
RegisterStateDriver(header, "combat", "[combat] in; out")

local function MatchInstanceGroup(p)
    if p.enabled == false then return false end
    return InstanceMet(p.instance) and GroupMet(p.group)
end

local function SetToArray(set)
    local t = {}
    for k in pairs(set) do t[#t + 1] = k end
    return t
end

-- Build the secure `apply` snippet: ClearBindings, then a per-key SetBindingClick under the
-- branch for the matching combat state. Built in plain Lua (out of combat).
local function RebuildSnippet(inKeys, outKeys)
    local b = { "local state = ...", "self:ClearBindings()" }
    local function emit(cond, keys)
        if #keys == 0 then return end
        b[#b + 1] = "if state == " .. cond .. " then"
        for _, k in ipairs(keys) do
            b[#b + 1] = ("self:SetBindingClick(true, %q, %q)"):format(k, "UnbunkDisabledKeyEater")
        end
        b[#b + 1] = "end"
    end
    emit('"in"', inKeys)
    emit('"out"', outKeys)
    header:SetAttribute("apply", table.concat(b, "\n"))
end

-- Recompute (out of combat) the keys to disable in each combat state, rebuild the secure
-- snippet, and apply the current (out-of-combat) state. The state driver takes over for
-- in-combat transitions, re-running the snippet we just compiled.
function DK.Apply()
    if InCombatLockdown() then return end   -- can't touch secure attrs/bindings in combat;
                                            -- the driver keeps flipping with the last snippet
    local inSet, outSet = {}, {}
    local c = Cfg()
    if c and c.enabled then
        for _, p in ipairs(c.profiles or {}) do
            if MatchInstanceGroup(p) then
                local cb = p.combat or {}
                local constrained = cb.inCombat or cb.outOfCombat
                local inOk  = (not constrained) or cb.inCombat       -- disable while IN combat?
                local outOk = (not constrained) or cb.outOfCombat    -- disable while OUT of combat?
                for _, key in ipairs(p.keys or {}) do
                    if key and key ~= "" then
                        if inOk  then inSet[key]  = true end
                        if outOk then outSet[key] = true end
                    end
                end
            end
        end
    end
    RebuildSnippet(SetToArray(inSet), SetToArray(outSet))
    -- Out of combat now: compile + apply the "out" branch immediately. Running it here also
    -- caches the compiled snippet, so the [combat] driver's in-combat run needs no recompile.
    header:Execute([[ self:RunAttribute("apply", "out") ]])
end

-- Keep the precomputed disable-sets fresh on instance / group / login transitions. Note
-- GROUP_ROSTER_UPDATE can fire DURING combat (a member goes offline / dies): DK.Apply then
-- early-outs on InCombatLockdown, so the instance/group predicate is frozen at its last
-- out-of-combat value until combat ends — PLAYER_REGEN_ENABLED re-runs Apply and re-syncs.
-- Entering combat needs no handler: the secure state driver re-runs the last compiled snippet.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function() DK.Apply() end)

ns.RegisterReloadHook(function() DK.Apply() end)
