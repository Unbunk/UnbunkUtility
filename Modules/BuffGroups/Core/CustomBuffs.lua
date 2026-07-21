-- Modules/BuffGroups/Core/CustomBuffs.lua
-- Custom (cast-triggered) buffs for the Buff-groups module — frames DRAWN by the addon
-- (we can't track arbitrary auras in combat). A custom buff has no native CDM frame: on the player's OWN cast
-- of its registered spellId we start a fixed-duration cooldown swipe on our own frame
-- (C_DurationUtil duration + SetCooldownFromDurationObject, SetReverse so it fills like a
-- buff), deactivated on OnCooldownDone / PLAYER_DEAD.
--
-- These frames are 100% ours (CreateFrame('Frame',nil,UIParent) + ARTWORK Texture +
-- CooldownFrameTemplate child + our own Title/Stack FontStrings) — no third-party skinning /
-- secret-value worries, so the ENGINE sizes/styles/positions them with SetSize/SetPoint freely, exactly
-- like a native frame but on a frame it fully controls. They are POOLED: removing a custom
-- buff parks its frame for reuse.
--
-- ENGINE INTEGRATION (BuffGroups.lua RefreshLayout):
--   * BG.CustomActive(spellId)        -> is this custom buff's swipe currently running.
--   * BG.GetCustomFrame(spellId)      -> the drawn Frame for an ACTIVE custom buff (creates
--                                        one from the pool on first use), nil if not active.
--   * BG.EnumActiveCustomFrames()     -> { [spellId] = frame, ... } for every active custom.
--   * BG.HideInactiveCustomFrames()   -> Hide any drawn frame whose buff isn't active (so a
--                                        just-expired custom doesn't linger before relayout).
-- RefreshLayout maps each active custom's frame into its assigned group's container ALONGSIDE
-- the native frames (StyleFrame/SetPoint as for a native; the frame carries .Icon/.Cooldown/
-- .Title/.Stack/.isCustomBuff/.spellID so the engine's StyleFrame treats it uniformly). The
-- module never positions the frame itself — it only owns activation/deactivation + the pool.
--
-- Custom buffs are authored through the shared CustomCDM Buff editor (the Free-icons "+ -> Buff"
-- and the Buff-groups "+" both open it); an in-CDM buff is mirrored here via BG.AddCustom.

local _, ns = ...
ns.BuffGroups = ns.BuffGroups or {}
local BG = ns.BuffGroups

local GetTime = GetTime

-- In combat the player's own cast spellId can come back as a "secret value": reading or
-- comparing one taints + errors. Guard it before any numeric use. The local fallback keeps a
-- client without the system loading (the guard then passes everything through).
local issecretvalue = issecretvalue or function() return false end

-- ── Quick-Add template list (the UI's preset picker — a curated preset of buffs) ─────
-- Each = { spellID, duration }. Name/icon are resolved from the spell at add time (the Data
-- phase's BG.AddCustom fills them when the opts don't carry one). These are cast-triggered:
-- the player's own UNIT_SPELLCAST_SUCCEEDED of the spellId starts the fixed-duration swipe.
BG.CUSTOM_BUFF_TEMPLATES = {
    { spellID = 1236616, duration = 30 },   -- Light's Potential
    { spellID = 1236994, duration = 30 },   -- Potion of Recklessness
    { spellID = 374968,  duration = 10 },   -- Time Spiral
    { spellID = 2825,    duration = 40 },   -- Bloodlust
}

-- ── Drawn-frame pool ────────────────────────────────────────────────────────────
-- iconFrames[spellId] = the live drawn frame for that custom buff (created lazily, reused).
-- framePool        = parked frames reclaimed from removed customs, reused before allocating.
-- active[spellId]  = true while its swipe is running.
local iconFrames = {}
local framePool  = {}
local active     = {}

-- Create (or reclaim from the pool) the drawn frame for a custom buff. The frame mirrors a
-- native CDM buff frame's shape so the engine's StyleFrame can treat it uniformly: an ARTWORK
-- Icon texture, a CooldownFrameTemplate child (the buff-style fill swipe), and our own
-- Title / Stack FontStrings. Size / style / position are imposed by the ENGINE; we only build
-- the frame and own its cooldown lifecycle.
local function CustomFrame(spellId)
    local f = iconFrames[spellId]
    if f then return f end

    f = table.remove(framePool)
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("MEDIUM")

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        f.Icon = icon

        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(false)
        cd:SetDrawSwipe(true)
        cd:SetReverse(true)   -- fill up as time passes (buff-style)
        f.Cooldown = cd

        -- Title / stack live on our own FontStrings (the engine re-fonts / re-anchors them
        -- exactly as it does a native frame's, reading the icon's effective config).
        f.Title = f:CreateFontString(nil, "OVERLAY", nil, 7)
        f.Stack = f:CreateFontString(nil, "OVERLAY", nil, 7)
    end

    f.isCustomBuff = true
    f.spellID = spellId
    f:Hide()
    iconFrames[spellId] = f
    return f
end

local Deactivate
local function Activate(spellId, overrideStartTime)
    local def = BG.GetCustom and BG.GetCustom(spellId)
    if not def then return end
    local dur = tonumber(def.duration) or 0
    if dur <= 0 then return end

    local f = CustomFrame(spellId)
    if f.Icon and BG.SpellTexture then f.Icon:SetTexture(BG.SpellTexture(spellId)) end

    local startTime = overrideStartTime or GetTime()
    if f.Cooldown then
        -- C_DurationUtil drives a buff-style fill swipe; fall back to a plain
        -- SetCooldown on a client without the duration util.
        f.cdDuration = f.cdDuration or (C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration())
        if f.cdDuration then
            f.cdDuration:SetTimeFromStart(startTime, dur)
            f.Cooldown:SetCooldownFromDurationObject(f.cdDuration)
        else
            f.Cooldown:SetCooldown(startTime, dur)
        end
        f.Cooldown:SetScript("OnCooldownDone", function() Deactivate(spellId) end)
    end

    active[spellId] = true
    -- The engine packs the now-active frame into its group's container.
    if BG.RefreshLayout then BG.RefreshLayout() end
end

Deactivate = function(spellId)
    if not active[spellId] then return end
    active[spellId] = nil
    local f = iconFrames[spellId]
    if f then
        if f.Cooldown then f.Cooldown:SetScript("OnCooldownDone", nil) end
        f:Hide()
    end
    if BG.RefreshLayout then BG.RefreshLayout() end
end

-- ── Public API the ENGINE + UI consume ──────────────────────────────────────────
-- Is this custom buff's swipe currently running.
function BG.CustomActive(spellId) return active[spellId] and true or false end

-- The drawn frame for an ACTIVE custom buff (nil otherwise). The engine calls this to fetch
-- the frame it then sizes/styles/positions into the group container.
function BG.GetCustomFrame(spellId)
    if not active[spellId] then return nil end
    return CustomFrame(spellId)
end

-- All active custom frames, keyed by spellId — the engine folds these into its frameOf map
-- alongside the native pool frames. A buff the user has REMOVED (no longer registered) is
-- auto-deactivated here so its drawn frame doesn't linger after BG.RemoveCustom cleared the
-- data without touching this module.
-- `out` (optional): the engine passes its per-pass frameOf scratch so we ADD our frames into it
-- in place (no fresh allocation each RefreshLayout). We do NOT wipe it — it already holds the
-- native frames the caller merged before us. With no `out` we allocate + return a fresh table.
function BG.EnumActiveCustomFrames(out)
    out = out or {}
    for spellId in pairs(active) do
        if BG.IsCustom and not BG.IsCustom(spellId) then
            -- Tear down inline (NOT via Deactivate, which would re-enter RefreshLayout while
            -- this runs inside it): clear state + hide the frame. Clearing a key during pairs
            -- traversal is safe in Lua; the in-progress layout simply won't place it.
            active[spellId] = nil
            local f = iconFrames[spellId]
            if f then
                if f.Cooldown then f.Cooldown:SetScript("OnCooldownDone", nil) end
                f:Hide()
            end
        else
            out[spellId] = CustomFrame(spellId)
        end
    end
    return out
end

-- Hide every drawn frame whose buff is NOT currently active (the module-off / safety path).
function BG.HideInactiveCustomFrames()
    for spellId, f in pairs(iconFrames) do
        if not active[spellId] then f:Hide() end
    end
end

-- Hide EVERY drawn frame, active or not — the Level-2 engine-cede path. These frames are anchored to (not
-- children of) the group container, so the viewer's SetAlpha(0) mask and HideAll's container:Hide never
-- reach them; a still-active buff would linger visible. Active buffs stay TRACKED (not Deactivated), so the
-- next full RefreshLayout on return to native re-Shows them, and CustomCDM renders them via its free icon
-- while BuffGroups is ceded (BuffMirrored flips false). Called from ns.CDMMode on a real mode change.
function BG.HideAllCustomFrames()
    for _, f in pairs(iconFrames) do f:Hide() end
end

-- Activate / deactivate are exposed (the engine's PLAYER_DEAD handler + diagnostics use them).
BG.ActivateCustom   = Activate
BG.DeactivateCustom = Deactivate

-- Deactivate every running custom buff (PLAYER_DEAD handler).
function BG.DeactivateAllCustom()
    if not next(active) then return end
    local list = {}
    for spellId in pairs(active) do list[#list + 1] = spellId end
    for i = 1, #list do Deactivate(list[i]) end
end

-- Drop a removed custom buff's drawn frame back to the pool (called by the UI after
-- BG.RemoveCustom clears the data). Idempotent for a never-seen spellId.
function BG.ReleaseCustomFrame(spellId)
    if active[spellId] then Deactivate(spellId) end
    local f = iconFrames[spellId]
    if not f then return end
    if f.Cooldown then
        f.Cooldown:SetScript("OnCooldownDone", nil)
        if f.Cooldown.Clear then f.Cooldown:Clear() end
    end
    f:Hide()
    f:ClearAllPoints()
    f.spellID = nil
    iconFrames[spellId] = nil
    framePool[#framePool + 1] = f
end

-- Convenience: add one of the Quick-Add templates to a group (resolves name/icon from the
-- spell). Thin wrapper over the Data phase's BG.AddCustom so the UI's preset picker is a
-- one-liner; a raw Spell ID + Duration the user types still goes straight through BG.AddCustom.
-- (BG.AddCustomFromTemplate removed: the quick-add picker is gone — custom buffs are authored
--  through the CustomCDM Buff editor now. BG.CUSTOM_BUFF_TEMPLATES above is currently unused.)

-- ── Cast trigger ─────────────────────────────────────────────────────────────────
-- The player's OWN cast of a registered custom spellId starts its fixed-duration swipe.
-- PLAYER_DEAD ends them all (a buff like Bloodlust drops on death). The engine owns layout;
-- we own only activation, so a refresh after either is enough.
local function OnSpellCastSucceeded(_, unit, _, spellId)
    if unit ~= "player" then return end
    if issecretvalue(spellId) then return end
    if BG.IsCustom and BG.IsCustom(spellId) then Activate(spellId) end
end

local ev = CreateFrame("Frame")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterEvent("PLAYER_DEAD")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_DEAD" then
        BG.DeactivateAllCustom()
    else
        OnSpellCastSucceeded(event, ...)
    end
end)
