-- Modules/CDMEngine/Display/IconExtras.lua
--
-- Phase 4 of the standalone CDM engine (ns.CDMEngine): per-icon DISPLAY EXTRAS bolted onto the P1
-- E.Icon widget WITHOUT touching Icon.lua's core draw path (Icon.lua only calls Register/Unregister).
-- Two extras so far:
--   * PROC GLOW  — glow the icon while its spell has an activation proc (Brain Freeze, Fingers of Frost…).
--   * RANGE TINT — redden the icon while the spell's target is out of range.
--
-- Both are SPELLID-KEYED and EVENT-DRIVEN — no per-icon OnUpdate (the engine's core rule):
--   proc  : SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE (+ C_SpellActivationOverlay.IsSpellOverlayed seed),
--           matched by BASE spell (C_Spell.GetBaseSpell) so an overridden spell still glows.
--   range : C_Spell.EnableSpellRangeCheck(sid,true) -> SPELL_RANGE_CHECK_UPDATE(sid,inRange,checked)
--           (+ C_Spell.IsSpellInRange seed). Disabled again on Unregister.
--
-- TAINT / SECRET: unlike CDMGroups (which glows NATIVE frames and needs a re-parent firewall because
-- Blizzard hides those from secure code, so an OnHide would ride taint into CooldownViewer.lua:901),
-- this engine glows OUR OWN icon frames — LibCustomGlow can parent straight to the icon, no firewall.
-- The event handler touches ONLY our frames + pure C_Spell reads (no CooldownViewer read, no native
-- frame contact), so even though the CDM co-registers for the glow event, our SEPARATE event frame
-- can't taint Blizzard's secure handler. The ids passed are the resolved DISPLAY id (never a secret),
-- and every native call is existence-checked / pcall-guarded.

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
local Extras = {}
E.IconExtras = Extras

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local GLOW_KEY = "uucdmengine"

local C_Spell = C_Spell
local C_SAO   = C_SpellActivationOverlay
local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell

local function BaseOf(sid)
    local b = GetBaseSpell and GetBaseSpell(sid)
    return b or sid
end

-- The CDMGroups config instance backing this icon's dest ("essential"/"utility"). The engine own-draw
-- cooldowns REUSE the native per-icon glow config as their source of truth (glowEnabled/glowType/glowColor),
-- exactly like the native CDMGroups renderer — NOT the engine's global E.Cfg (which the user's Essential/
-- Utility "Glow" cadre never writes to). Mirrors Icon.lua's DestI.
local function DestI(f)
    return ns.CDMGroups and ns.CDMGroups[f._dest or "essential"]
end

-- ── LibCustomGlow wrappers (start/stop by glowType), parented to OUR icon frame ───────────────────
local GLOW_FNS = {}
if LCG then
    GLOW_FNS.pixel = {
        start = function(f, c) LCG.PixelGlow_Start(f, c, nil, nil, nil, 3, nil, nil, nil, GLOW_KEY) end,  -- th=3: 1px invisible on small icons
        stop  = function(f)    LCG.PixelGlow_Stop(f, GLOW_KEY) end,
    }
    GLOW_FNS.autocast = {
        start = function(f, c) LCG.AutoCastGlow_Start(f, c, nil, nil, nil, nil, nil, GLOW_KEY) end,
        stop  = function(f)    LCG.AutoCastGlow_Stop(f, GLOW_KEY) end,
    }
    GLOW_FNS.button = {   -- no colour: Blizzard's natural yellow proc-glow look
        start = function(f) LCG.ButtonGlow_Start(f) end,
        stop  = function(f) LCG.ButtonGlow_Stop(f) end,
    }
    if LCG.ProcGlow_Start and LCG.ProcGlow_Stop then
        GLOW_FNS.proc = {   -- native proc flipbook, steady loop only (startAnim=false: skip the oversized burst)
            start = function(f) LCG.ProcGlow_Start(f, { key = GLOW_KEY, startAnim = false }) end,
            stop  = function(f) LCG.ProcGlow_Stop(f, GLOW_KEY) end,
        }
    else
        GLOW_FNS.proc = GLOW_FNS.button   -- old lib revision: fall back to ButtonGlow for "proc"
    end
end

-- Effective glow colour as an LCG array {r,g,b,a}. CDMGroups stores glowColor as a HASH {r,g,b,a}; the
-- engine's global E.Cfg (fallback path) stores it as an ARRAY {c[1..4]}.
local function GlowColorArray(f)
    local I = f and DestI(f)
    -- Config is BASE-keyed (CDMGroups keys iconCfg/GroupOf by base spellId), like Icon.StyleFrame — a
    -- transformed cooldown (Blink 1953 -> Shimmer 212653) would otherwise read the template default colour.
    local sid = f and (f.baseSpellID or f._lastGoodSid or f.spellID)
    if I and I.IconGet and sid then
        local c = I.IconGet(sid, "glowColor")
        if type(c) == "table" then return { c.r or 1, c.g or 1, c.b or 1, c.a or 1 } end
    end
    local c = E.Cfg and E.Cfg.Get("glowColor")
    if type(c) == "table" then return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 } end
    return { 0.96, 1, 0, 1 }
end

local function StopGlow(f)
    local active = f._uuGlowActive
    if not active then return end
    local fns = GLOW_FNS[active]
    if fns and fns.stop then pcall(fns.stop, f) end
    f._uuGlowActive = nil
end

-- Reconcile the glow to the desired state. Show ONLY when procGlow is enabled AND the icon is procced.
-- Track the active type so we Start/Stop only on a REAL change (LCG animates itself; restarting churns).
local function UpdateGlow(f)
    if not (f and LCG) then return end
    -- Read the icon's per-spell glow config from its dest's CDMGroups instance (the Essential/Utility "Glow"
    -- cadre: glowEnabled = "show glow on proc", glowType, glowColor). Fall back to the engine's global E.Cfg
    -- only when there is no CDMGroups instance (e.g. the fallback single-group render with no dest).
    local I   = DestI(f)
    local sid = f.baseSpellID or f._lastGoodSid or f.spellID   -- BASE-keyed config (see GlowColorArray)
    local enabled, glowType
    if I and I.IconGet and sid then
        enabled  = I.IconGet(sid, "glowEnabled") == true
        glowType = I.IconGet(sid, "glowType") or "pixel"
    else
        enabled  = E.Cfg and E.Cfg.Get("procGlow") == true
        glowType = (E.Cfg and E.Cfg.Get("glowType")) or "pixel"
    end
    local wantType = (enabled and f._uuProcced) and glowType or nil
    if f._uuGlowActive == wantType then return end
    if f._uuGlowActive then StopGlow(f) end
    if not wantType then return end
    local fns = GLOW_FNS[wantType]
    if fns and fns.start then
        pcall(fns.start, f, GlowColorArray(f))
        f._uuGlowActive = wantType
    end
end

-- ── Range tint on the icon texture ───────────────────────────────────────────────────────────────
local function ApplyRange(f)
    local tex = f.Icon
    if not tex then return end
    if (E.Cfg and E.Cfg.Get("rangeCheck") == true) and f._uuOutOfRange then
        tex:SetVertexColor(0.8, 0, 0, 1)
    else
        tex:SetVertexColor(1, 1, 1, 1)
    end
end

-- ── Per-icon registry (each key holds a SET of frames) ───────────────────────────────────────────
-- A key can be shared by several live icons — two tracked cooldowns whose display spells collapse to
-- the same base (talent variants) share a byBase key. Matching Coolinator's per-frame fan-out, EVERY
-- such icon must react to a proc/range event; a single-slot map would orphan all but the last-registered
-- (its glow would freeze). So each key maps to a SET of frames and the dispatcher iterates it.
local bySpell = {}   -- [displaySid] = { [f]=true }  — range events (SPELL_RANGE_CHECK_UPDATE)
local byBase  = {}   -- [baseSpell]  = { [f]=true }  — proc glow events (matched by C_Spell.GetBaseSpell)

local function AddTo(map, key, f)
    local set = map[key]
    if not set then set = {}; map[key] = set end
    set[f] = true
end
-- Remove f from map[key]; returns true when the set became EMPTY (the last frame left this key).
local function RemoveFrom(map, key, f)
    local set = map[key]
    if not set then return false end
    set[f] = nil
    if next(set) == nil then map[key] = nil; return true end
    return false
end

-- Register (or re-register) an icon's extras once its display spellID is resolved. Idempotent for the
-- same id — Icon.Update calls this every refresh, so it early-outs cheaply once registered.
function Extras.Register(f)
    if not f then return end
    local sid = f.spellID or f._lastGoodSid
    if not sid then return end               -- unresolved (secret in combat): retried on a later Update
    if f._uuExtraSid == sid then return end
    if f._uuExtraSid then Extras.Unregister(f) end   -- id changed: drop the old registration first

    f._uuExtraSid = sid
    AddTo(bySpell, sid, f)
    AddTo(byBase, BaseOf(sid), f)

    -- proc: seed the current overlay state + reconcile the glow
    f._uuProcced = (C_SAO and C_SAO.IsSpellOverlayed and C_SAO.IsSpellOverlayed(sid)) or false
    UpdateGlow(f)

    -- range: turn on the event stream for this spell + seed the current state
    if C_Spell and C_Spell.EnableSpellRangeCheck then pcall(C_Spell.EnableSpellRangeCheck, sid, true) end
    local ir = C_Spell and C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(sid, "target")
    f._uuOutOfRange = (ir == false)
    ApplyRange(f)
end

function Extras.Unregister(f)
    if not f then return end
    StopGlow(f)
    local sid = f._uuExtraSid
    if sid then
        local lastOnSid = RemoveFrom(bySpell, sid, f)
        RemoveFrom(byBase, BaseOf(sid), f)
        -- only cut the range event stream when the LAST icon on this display sid leaves (a sibling
        -- sharing the sid still needs it)
        if lastOnSid and C_Spell and C_Spell.EnableSpellRangeCheck then
            pcall(C_Spell.EnableSpellRangeCheck, sid, false)
        end
    end
    f._uuExtraSid, f._uuProcced, f._uuOutOfRange = nil, nil, nil
    if f.Icon then f.Icon:SetVertexColor(1, 1, 1, 1) end
end

-- Re-apply glow + range to every registered icon. This is the extras' live-refresh reconcile seam, called
-- by the "Range check" toggle in IC.AppendEngineDisplayExtras (UI/Shared/IconCadres.lua) after Cfg.Set
-- (procGlow/glowType/glowColor still have no UI setter yet, so only rangeCheck exercises it today). The
-- unconditional StopGlow forces a restart so a glowColour-only change repaints (LCG captures the colour
-- at Start time; the type-keyed UpdateGlow gate would otherwise swallow a colour-only change).
function Extras.ReapplyAll()
    for _, set in pairs(bySpell) do
        for f in pairs(set) do
            StopGlow(f)
            UpdateGlow(f)
            ApplyRange(f)
        end
    end
end

-- ── Event stream (ONE frame for all icons; no per-icon OnUpdate) ─────────────────────────────────
local ev = CreateFrame("Frame")
if C_SAO then
    ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    ev:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
end
ev:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "SPELL_RANGE_CHECK_UPDATE" then
        local set = bySpell[a1]                      -- a1 = spellID, a2 = isInRange, a3 = checkedRange
        if set then
            local outOfRange = (a3 and a2 == false) and true or false
            for f in pairs(set) do
                f._uuOutOfRange = outOfRange
                ApplyRange(f)
            end
        end
    else
        local set = byBase[BaseOf(a1)]               -- a1 = spellID; match by base so an override glows too
        if set then
            local procced = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            for f in pairs(set) do                   -- fan out: EVERY live icon sharing this base reacts
                f._uuProcced = procced
                UpdateGlow(f)
            end
        end
    end
end)
