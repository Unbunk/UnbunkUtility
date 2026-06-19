-- Modules/CDMGroups/Core/CustomCooldowns.lua
-- Custom (cast-triggered) cooldowns for the Cooldown-groups module — a GENERALIZED, dest-parameterized
-- port of Modules/BuffGroups/Core/CustomBuffs.lua. Where BuffGroups attaches its custom API onto the
-- ns.BuffGroups table, THIS module attaches per-INSTANCE (CustomFor(I)) onto the SAME instance `I` the
-- Config + Engine use, exactly like EngineFor — so a second dest ("utility", later) is one CustomFor
-- call. Only "essential" is wired this phase.
--
-- A custom cooldown has no native CDM frame: on the player's OWN cast of its registered spellId we
-- start a fixed-duration cooldown swipe on our OWN frame (C_DurationUtil duration +
-- SetCooldownFromDurationObject, SetReverse so it fills like a buff), deactivated on OnCooldownDone /
-- PLAYER_DEAD. These frames are 100% ours (CreateFrame('Frame',nil,UIParent) + ARTWORK Texture +
-- CooldownFrameTemplate child + our own Title/Stack FontStrings) — no Masque / secret-value worries,
-- so the ENGINE sizes/styles/positions them with SetSize/SetPoint freely. They are POOLED.
--
-- ENGINE INTEGRATION (Engine.lua RefreshLayout):
--   * I.CustomActive(spellId)        -> is this custom cooldown's swipe currently running.
--   * I.GetCustomFrame(spellId)      -> the drawn Frame for an ACTIVE custom (creates one from the
--                                       pool on first use), nil if not active.
--   * I.EnumActiveCustomFrames()     -> { [spellId] = frame, ... } for every active custom.
--   * I.HideInactiveCustomFrames()   -> Hide any drawn frame whose custom isn't active.
-- RefreshLayout folds each active custom's frame into its frameOf map ALONGSIDE the native frames; the
-- frame carries .isCustomBuff/.spellID/.Icon/.Cooldown/.Title/.Stack so StyleFrame treats it uniformly.
--
-- The Quick-Add TEMPLATE list (CDG.CUSTOM_COOLDOWN_TEMPLATES) is the UI's source for the "+" picker;
-- the user can also add a raw Spell ID + Duration. Both route through I.AddCustom (the Data phase).

local _, ns = ...
ns.CDMGroups = ns.CDMGroups or {}
local CDG = ns.CDMGroups

local GetTime = GetTime

-- In combat the player's own cast spellId can come back as a "secret value": reading or comparing one
-- taints + errors. Guard it before any numeric use. The local fallback keeps a client without the
-- system loading working (the guard then passes everything through).
local issecretvalue = issecretvalue or function() return false end

-- ── Quick-Add template list (the UI's preset picker — shared across dests) ─────
-- Each = { spellID, duration }. Name/icon are resolved from the spell at add time (I.AddCustom fills
-- them when the opts don't carry one). Cast-triggered: the player's own UNIT_SPELLCAST_SUCCEEDED of the
-- spellId starts the fixed-duration swipe.
CDG.CUSTOM_COOLDOWN_TEMPLATES = {
    { spellID = 1236616, duration = 30 },   -- Light's Potential
    { spellID = 1236994, duration = 30 },   -- Potion of Recklessness
    { spellID = 374968,  duration = 10 },   -- Time Spiral
    { spellID = 2825,    duration = 40 },   -- Bloodlust
}

-- ════════════════════════════════════════════════════════════════════════════════
-- CustomFor(I): attach the custom-cooldown runtime onto a Config/Engine instance. Per-instance pools
-- + a per-instance cast event frame (NOT shared between dests).
-- ════════════════════════════════════════════════════════════════════════════════
local function CustomFor(I)
    -- iconFrames[spellId] = the live drawn frame (created lazily, reused). framePool = parked frames
    -- reclaimed from removed customs, reused before allocating. active[spellId] = swipe running.
    local iconFrames = {}
    local framePool  = {}
    local active     = {}

    -- Create (or reclaim from the pool) the drawn frame for a custom cooldown. The frame mirrors a
    -- native CDM item frame's shape so the engine's StyleFrame treats it uniformly: an ARTWORK Icon
    -- texture, a CooldownFrameTemplate child (the buff-style fill swipe), and our own Title / Stack
    -- FontStrings. Size / style / position are imposed by the ENGINE; we only build the frame + own its
    -- cooldown lifecycle.
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
            cd:SetReverse(true)   -- fill up as time passes (buff-style, like the reference addon)
            f.Cooldown = cd

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
        local def = I.GetCustom and I.GetCustom(spellId)
        if not def then return end
        local dur = tonumber(def.duration) or 0
        if dur <= 0 then return end

        local f = CustomFrame(spellId)
        if f.Icon and I.SpellTexture then f.Icon:SetTexture(I.SpellTexture(spellId)) end

        local startTime = overrideStartTime or GetTime()
        if f.Cooldown then
            -- C_DurationUtil drives a buff-style fill swipe (the reference addon's pattern); fall back to a plain
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
        if I.RefreshLayout then I.RefreshLayout() end
    end

    Deactivate = function(spellId)
        if not active[spellId] then return end
        active[spellId] = nil
        local f = iconFrames[spellId]
        if f then
            if f.Cooldown then f.Cooldown:SetScript("OnCooldownDone", nil) end
            f:Hide()
        end
        if I.RefreshLayout then I.RefreshLayout() end
    end

    -- ── Public API the ENGINE + UI consume ──────────────────────────────────────
    function I.CustomActive(spellId) return active[spellId] and true or false end

    function I.GetCustomFrame(spellId)
        if not active[spellId] then return nil end
        return CustomFrame(spellId)
    end

    -- All active custom frames, keyed by spellId — the engine folds these into its frameOf map. A custom
    -- the user has REMOVED (no longer registered) is auto-torn-down here so its drawn frame doesn't
    -- linger after I.RemoveCustom cleared the data without touching this module.
    function I.EnumActiveCustomFrames()
        local out = {}
        for spellId in pairs(active) do
            if I.IsCustom and not I.IsCustom(spellId) then
                -- Tear down inline (NOT via Deactivate, which would re-enter RefreshLayout while this
                -- runs inside it): clear state + hide. Clearing a key during pairs traversal is safe.
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

    function I.HideInactiveCustomFrames()
        for spellId, f in pairs(iconFrames) do
            if not active[spellId] then f:Hide() end
        end
    end

    I.ActivateCustom   = Activate
    I.DeactivateCustom = Deactivate

    function I.DeactivateAllCustom()
        if not next(active) then return end
        local list = {}
        for spellId in pairs(active) do list[#list + 1] = spellId end
        for i = 1, #list do Deactivate(list[i]) end
    end

    -- Drop a removed custom's drawn frame back to the pool (called by the UI after I.RemoveCustom
    -- clears the data). Idempotent for a never-seen spellId.
    function I.ReleaseCustomFrame(spellId)
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

    -- Convenience: add one of the Quick-Add templates to a group at a precise (rowIndex,colIndex) when
    -- given (resolves the duration from the template). A raw Spell ID + Duration the user types goes
    -- straight through I.AddCustom.
    function I.AddCustomFromTemplate(spellID, groupId, rowIndex, colIndex)
        for _, t in ipairs(CDG.CUSTOM_COOLDOWN_TEMPLATES) do
            if t.spellID == spellID then
                if I.AddCustom then
                    I.AddCustom(spellID, groupId, { duration = t.duration, rowIndex = rowIndex, colIndex = colIndex })
                end
                return true
            end
        end
        return false
    end

    -- ── Cast trigger ─────────────────────────────────────────────────────────────
    local function OnSpellCastSucceeded(_, unit, _, spellId)
        if unit ~= "player" then return end
        if issecretvalue(spellId) then return end
        if I.IsCustom and I.IsCustom(spellId) then Activate(spellId) end
    end

    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:RegisterEvent("PLAYER_DEAD")
    ev:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_DEAD" then
            I.DeactivateAllCustom()
        else
            OnSpellCastSucceeded(event, ...)
        end
    end)

    return I
end

CDG.CustomFor = CustomFor

-- Attach the custom-cooldown runtime to the "essential" instance now (the only dest this phase).
if CDG.essential then CustomFor(CDG.essential) end
