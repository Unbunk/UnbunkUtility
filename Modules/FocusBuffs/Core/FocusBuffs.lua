-- Modules/FocusBuffs/Core/FocusBuffs.lua
-- Owner utility: declutter the default Blizzard FocusFrame by hiding DEBUFF icons while
-- KEEPING their stack count. Each focus debuff button's icon + cooldown swipe + coloured
-- border are faded to alpha 0; the Count FontString is left untouched, so Blizzard still
-- shows it for stacking debuffs (count >= 2) and nothing for the rest — i.e. stacking
-- debuffs become floating numbers and the others disappear.
--
-- The focus debuff buttons have lived in a few shapes across 12.0.x (named buttons, the
-- legacy debuffFrames/dispelDebuffFrames arrays, and the 12.0.8+ container whose aura
-- frames carry .auraInstanceID). We try them all, and fall back to walking the frame for
-- HARMFUL aura buttons — so this keeps working whichever layout the client is on. Per-
-- profile config (ns.db.profile.focusBuffs); disabled by default and reachable only from
-- the owner-gated "Personal utilities" tab.

local _, ns = ...
ns.FocusBuffs = ns.FocusBuffs or {}
local FB = ns.FocusBuffs

local DEFAULTS = { enabled = false }

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.focusBuffs end
FB.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    p.focusBuffs = p.focusBuffs or {}
    ns.MergeDefaults(p.focusBuffs, DEFAULTS)
    if FB.Apply then FB.Apply() end
end
ns.RegisterCfgInitHook(InitCfg)

function FB.Get(key) local c = Cfg(); return c and c[key] == true end
function FB.Set(key, v)
    local c = Cfg(); if c then c[key] = v and true or false end
    FB.Apply()
end

-- ── Button styling ────────────────────────────────────────────────────────────
-- Buttons we have faded, so each pass can RESTORE them first (handles frame pooling /
-- focus changes / the toggle going off) before re-fading the current debuffs. Weak-keyed
-- so dropped buttons don't pin frames.
local touched = setmetatable({}, { __mode = "k" })

-- Set the alpha of a debuff button's icon / cooldown / border (never the Count).
local function SetVisualAlpha(btn, a)
    if not btn then return end
    local nm   = btn.GetName and btn:GetName()
    local icon = btn.Icon or btn.icon or (nm and _G[nm .. "Icon"])
    if icon and icon.SetAlpha then icon:SetAlpha(a) end
    if btn.Cooldown and btn.Cooldown.SetAlpha then btn.Cooldown:SetAlpha(a) end
    local border = btn.Border or btn.DebuffBorder or btn.border or (nm and _G[nm .. "Border"])
    if border and border.SetAlpha then border:SetAlpha(a) end
end

local function Dim(btn)
    if not btn or touched[btn] then return end
    SetVisualAlpha(btn, 0)
    touched[btn] = true
end

-- ── Debuff button discovery ───────────────────────────────────────────────────
-- An aura button is any frame carrying .auraInstanceID. When we already know it's a
-- debuff (named button / debuff array / debuff container) we dim it directly; the
-- whole-frame fallback classifies via the aura data instead.
local function IsHarmfulFocusAura(aid)
    if not (aid and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then return false end
    local d = C_UnitAuras.GetAuraDataByAuraInstanceID("focus", aid)
    if not d then return false end
    local h = d.isHarmful
    -- Never read a secret aura field (enemy focus in combat) — skip rather than taint.
    if issecretvalue and issecretvalue(h) then return false end
    return h == true
end

-- Recurse a DEBUFF container (every aura button under it is a debuff): dim each.
local function DimContainer(frame, depth)
    if not frame or depth > 4 then return end
    if frame.auraInstanceID then Dim(frame) end
    local n = frame.GetNumChildren and frame:GetNumChildren() or 0
    for i = 1, n do DimContainer(select(i, frame:GetChildren()), depth + 1) end
end

-- Fallback: walk the whole focus frame and dim only the HARMFUL aura buttons (so buffs
-- are left alone) — used only when none of the known debuff fields exist.
local function DimHarmful(frame, depth)
    if not frame or depth > 5 then return end
    if frame.auraInstanceID and IsHarmfulFocusAura(frame.auraInstanceID) then Dim(frame) end
    local n = frame.GetNumChildren and frame:GetNumChildren() or 0
    for i = 1, n do DimHarmful(select(i, frame:GetChildren()), depth + 1) end
end

local function DimKnownDebuffs(f)
    -- 1) Named buttons (older retail): FocusFrameDebuff1..N.
    for i = 1, 40 do
        local b = _G["FocusFrameDebuff" .. i]
        if not b then break end
        Dim(b)
    end
    -- 2) Legacy arrays of debuff buttons.
    for _, field in ipairs({ "debuffFrames", "dispelDebuffFrames" }) do
        local arr = f[field]
        if type(arr) == "table" then
            for _, b in ipairs(arr) do
                if type(b) == "table" and b.auraInstanceID then Dim(b) end
            end
        end
    end
    -- 3) New (12.0.8+) debuff container: a frame whose descendant buttons carry auraInstanceID.
    if type(f.debuffs) == "table" and f.debuffs.GetNumChildren then DimContainer(f.debuffs, 0) end
end

-- ── Apply ─────────────────────────────────────────────────────────────────────
function FB.Apply()
    if not FocusFrame then return end
    -- Restore everything we previously faded, then re-fade the current debuffs (or, when
    -- disabled, just leave them restored).
    for btn in pairs(touched) do SetVisualAlpha(btn, 1) end
    wipe(touched)
    if not FB.Get("enabled") then return end

    DimKnownDebuffs(FocusFrame)
    -- If none of the known debuff fields matched this client, fall back to classifying.
    if next(touched) == nil then DimHarmful(FocusFrame, 0) end
end

-- ── Triggers ──────────────────────────────────────────────────────────────────
-- Re-apply after Blizzard repaints the focus auras. A direct hook on the frame's aura
-- update (if present) runs in the same frame → no flash; the deferred events are the
-- version-proof fallback (one-frame defer so we run after Blizzard's own handler).
local function Refresh() if FB.Get("enabled") then FB.Apply() end end

if FocusFrame and type(FocusFrame.UpdateAuras) == "function" then
    hooksecurefunc(FocusFrame, "UpdateAuras", Refresh)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if not FB.Get("enabled") then return end
    -- One-frame defer so we run after Blizzard repaints the (new) focus's auras.
    C_Timer.After(0, FB.Apply)
end)

-- Focus aura changes go through the shared dispatcher, which already coalesces a
-- burst of UNIT_AURA into a single next-frame callback — so no per-event timer.
ns.AuraDispatch.Register("focus", function()
    if not FB.Get("enabled") then return end
    FB.Apply()
end)

ns.RegisterReloadHook(function() FB.Apply() end)
