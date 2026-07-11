-- Modules/CDMEngine/Core/Mode.lua
--
-- The CDM display MODE switch (ns.CDMMode): "native" (default — the mature native-reuse restyling of
-- Blizzard's CooldownViewer) vs "engine" (hide the 4 native viewers and show the standalone
-- ns.CDMEngine widgets). ns.CDMMode is the SINGLE SOURCE OF TRUTH.
--
-- LEVEL 1 (this file) = the VISUAL switch. In engine mode we MASK the natives with SetAlpha(0) — which
-- is taint-safe: SetAlpha is NOT a geometry / movable / SHOWN write, so it never enters Blizzard's
-- 12.1.0 "secret value" comparisons (unlike Hide/SetShown), and a per-viewer SetAlpha hook re-forces 0
-- so Blizzard's / Ayije's fade can't un-hide it. The native-reuse still RUNS in engine mode (invisible).
--
-- LEVEL 2 (later) = the native-reuse consults ns.CDMMode.IsEngine() to STOP its own work in engine mode
-- (real taint + perf escape). The gate is exposed here now; the stop is not wired yet.

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
ns.CDMMode = ns.CDMMode or {}
local M = ns.CDMMode

-- The viewers the ENGINE replaces = its 3 SPEC groups (Essential / Utility / TrackedBuff). It does NOT
-- draw Tracked BARS, so BuffBarCooldownViewer is intentionally left visible + configurable (its "Bars"
-- config tab stays in the nav even in engine mode).
local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }

-- ── Source of truth (persisted in the engine config as "mode") ────────────────────────────────────
function M.Get()
    local m = E.Cfg and E.Cfg.Get("mode")
    return (m == "engine") and "engine" or "native"
end
function M.IsEngine() return M.Get() == "engine" end   -- the gate the native-reuse will consult (Level 2)

-- Whether a given native viewer is currently HIDDEN + alpha-owned by the engine (engine mode + one of
-- the 3 viewers it covers). The native-reuse (the Fader now; CDMGroups/BuffGroups later) consults this
-- to leave that viewer alone instead of fighting the engine's SetAlpha(0) re-force hook.
local VIEWER_SET = {}
for _, n in ipairs(VIEWERS) do VIEWER_SET[n] = true end
function M.IsViewerMasked(name) return M.IsEngine() and VIEWER_SET[name] == true end

-- ── Native masking (SetAlpha 0, re-forced via a per-viewer hook) ──────────────────────────────────
local maskForcing = false   -- recursion guard for our own SetAlpha inside the hook
local hooked = {}           -- [frame] = true once its SetAlpha is hooked
local masked = {}           -- [frame] = true while we hold its alpha at 0 (so native mode restores once)

local function ForceMask(f)
    maskForcing = true
    f:SetAlpha(0)
    maskForcing = false
end

local function EnsureHook(f)
    if hooked[f] then return end
    hooked[f] = true
    -- hooksecurefunc is flow-isolated (its taint is discarded on return), and SetAlpha is not a taint
    -- vector — so re-forcing 0 here is safe. Guard our own re-set + only act in engine mode.
    hooksecurefunc(f, "SetAlpha", function(self, a)
        if maskForcing then return end
        if M.IsEngine() and a ~= 0 then ForceMask(self); masked[self] = true end
    end)
end

local function ApplyMask()
    local engine = M.IsEngine()
    for _, name in ipairs(VIEWERS) do
        local f = _G[name]
        if f and f.SetAlpha then
            EnsureHook(f)
            if engine then
                ForceMask(f); masked[f] = true
            elseif masked[f] then
                masked[f] = nil
                f:SetAlpha(1)   -- restore ONCE on switch back; the hook no-ops in native mode, fade takes over
            end
        end
    end
end

-- ── Apply the whole mode: mask natives + show/hide the engine ─────────────────────────────────────
local lastAppliedMode
function M.Apply()
    ApplyMask()
    if E.Layout and E.Layout.SetShown then E.Layout.SetShown(M.IsEngine()) end
    -- Re-route CDMAnchor (Level 2): owned() now returns the new value for essential/utility, so CDMAnchor
    -- stops pinning the CDM trackers to the (masked) native viewer and lets the engine host them — and
    -- re-anchors them back to the native viewer on switch to native. Coalesced inside CDMAnchor.
    if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
    -- On an ACTUAL mode change, force the native-reuse (CDMGroups / BuffGroups) to a FULL relayout so it
    -- reclaims the trackers the engine displaced. Leaving engine mode, Group.Release re-parented those
    -- frames to UIParent + ClearAllPoints WITHOUT CDMGroups knowing, so its lastLayoutSig pass-level
    -- early-out (which folds ns.StyleEpoch) would skip re-placing them and they'd stay orphaned (no point).
    -- Bumping the epoch busts that signature so the next 0.2s RefreshLayout tick re-folds them. Gated on a
    -- real change so a zone-change M.Apply (PLAYER_ENTERING_WORLD, same mode) doesn't churn a full re-style.
    local m = M.Get()
    if m ~= lastAppliedMode then
        lastAppliedMode = m
        if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end
    end
end

function M.Set(mode)
    mode = (mode == "engine") and "engine" or "native"
    if E.Cfg then E.Cfg.Set("mode", mode) end
    M.Apply()
    if ns.RefreshNav then ns.RefreshNav() end   -- show/hide the native-engine config tabs (Essential/Utility/Buffs)
end

function M.Toggle() M.Set(M.IsEngine() and "native" or "engine") end

-- ── Apply on world enter (viewers exist, past the loading screen) + on profile switch ─────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function() M.Apply() end)
ns.RegisterReloadHook(function()   -- profile change / import: the new profile's mode wins
    M.Apply()
    if ns.RefreshNav then ns.RefreshNav() end
end)

-- ── Slash: /uucdmmode [native|engine] (toggle if no arg) ──────────────────────────────────────────
SLASH_UUCDMMODE1 = "/uucdmmode"
SlashCmdList["UUCDMMODE"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "engine" or msg == "native" then M.Set(msg) else M.Toggle() end
    local m = "CDM mode: " .. M.Get()
    if ns.Print then ns.Print(m) else print("|cff338cff[UnbunkUtility]|r " .. m) end
end
