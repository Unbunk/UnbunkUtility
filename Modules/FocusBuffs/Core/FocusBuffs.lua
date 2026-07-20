-- Modules/FocusBuffs/Core/FocusBuffs.lua
-- Owner utility — the "Focus Freezing" tab. Shows the STACK COUNT of a debuff you apply to your focus
-- (default: the Frost Mage "Freezing" debuff, 1221389) as a BIG number placed above your Cooldown-Manager
-- buff icon.
--
-- How it works WITHOUT reading a secret value: an enemy focus's stack count is a "secret value" in
-- instanced combat, so we cannot read it (C_UnitAuras fields are masked) and cannot use the combat log
-- (registering COMBAT_LOG_EVENT_UNFILTERED is ADDON_ACTION_FORBIDDEN here — see BResTracker/PITracker).
-- BUT Blizzard exposes C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, minCount, maxCount)
-- — a secret-SAFE passthrough: it returns a value that renders via FontString:SetText in combat WITHOUT
-- the addon ever reading it. This is exactly what oUF/ElvUI/UnhaltedUnitFrames use to show enemy debuff
-- stacks in combat. So we draw our OWN FontString and feed it that value. No dependency on Blizzard's
-- FocusFrame (which a unit-frame addon may disable) or on any other addon rendering the debuff.
--
-- auraInstanceID is NOT secret (oUF reads it every UNIT_AURA), so we can enumerate the focus's debuffs and
-- get each id — but the SPELL id IS secret in combat, so we cannot single out "only freezing". Instead we
-- render every focus debuff's display count; with minCount = 2 only STACKING debuffs produce a number, so
-- in practice only your freezing stacks show (non-stacking debuffs render empty → invisible).
--
-- Placement: a movable anchor (drag, persisted per-profile) + best-effort auto-follow of the live CDM buff
-- icon for the tracked spellID (resolvable out of combat; the anchor is the reliable fallback).
--
-- Per-profile config (ns.db.profile.focusBuffs); disabled by default, owner-gated "Personal utilities" tab.

local _, ns = ...
ns.FocusBuffs = ns.FocusBuffs or {}
local FB = ns.FocusBuffs

local DEFAULTS = {
    enabled    = false,
    spellID    = 1246769,   -- CDM buff to anchor the number above (Frost Mage "Shatter") — a readable player buff
    countScale = 2,         -- size multiplier on the drawn number
    minCount   = 1,         -- GetAuraApplicationDisplayCount floor: only debuffs with >= this many stacks show a number
    fontKey    = "",        -- LSM font key for the number ("" = the addon's global font)
    fontPath   = "",        -- resolved font path (paired with fontKey; "" = use the global font)
    outline    = "THICKOUTLINE", -- SetFont outline flags: "", "OUTLINE", "THICKOUTLINE", "MONOCHROME|OUTLINE", …
    color      = { r = 0, g = 145/255, b = 1, a = 1 },   -- number colour (0091FF)
    autoFollow = true,      -- best-effort anchor above the CDM buff icon for spellID
    point      = "CENTER",  -- movable-anchor placement (fallback / manual)
    x          = 0,
    y          = 0,
}

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.focusBuffs end
FB.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    p.focusBuffs = p.focusBuffs or {}
    -- One-time: the spellID field changed meaning (was the focus DEBUFF id, now the CDM BUFF to anchor
    -- above = "Shatter"), so bump the old default forward to keep existing configs anchoring correctly.
    if p.focusBuffs.spellID == 1221389 then p.focusBuffs.spellID = 1246769 end
    -- One-time: adopt the owner's chosen baseline look on the existing config (fresh installs get it via
    -- DEFAULTS). Guarded so later manual tweaks are never re-overridden.
    if not p.focusBuffs._baseline1 then
        p.focusBuffs._baseline1 = true
        p.focusBuffs.countScale = 2
        p.focusBuffs.minCount   = 1
        p.focusBuffs.outline    = "THICKOUTLINE"
        p.focusBuffs.color      = { r = 0, g = 145/255, b = 1, a = 1 }
    end
    ns.MergeDefaults(p.focusBuffs, DEFAULTS)
    if FB.Apply then FB.Apply() end
end
ns.RegisterCfgInitHook(InitCfg)

function FB.Get(key) local c = Cfg(); return c and c[key] end
function FB.Enabled() return FB.Get("enabled") == true end
function FB.Set(key, v)
    local c = Cfg(); if c then c[key] = v end
    FB.Apply()
end

local unlocked = false
local anchor

-- ── Movable anchor ─────────────────────────────────────────────────────────────
-- Our own frame. Always Shown so it stays a valid anchor target; chrome (backdrop + label) and mouse are
-- only enabled while the user is positioning it.
local function ApplyAnchorPos()
    if not anchor then return end
    local c = Cfg()
    anchor:ClearAllPoints()
    anchor:SetPoint((c and c.point) or "CENTER", UIParent, (c and c.point) or "CENTER", (c and c.x) or 0, (c and c.y) or 0)
end

local function SaveAnchorPos()
    local c = Cfg(); if not (c and anchor) then return end
    local point, _, _, x, y = anchor:GetPoint()
    if point then c.point, c.x, c.y = point, x, y end
end

local function SetChrome(a, on)
    if on then
        local r, g, b = ns.GetBrandColor()
        a:SetBackdropColor(r, g, b, 0.25)
        a:SetBackdropBorderColor(r, g, b, 1)
        if a.label then a.label:Show() end
    else
        a:SetBackdropColor(0, 0, 0, 0)
        a:SetBackdropBorderColor(0, 0, 0, 0)
        if a.label then a.label:Hide() end
    end
end

local function EnsureAnchor()
    if anchor then return anchor end
    local a = CreateFrame("Frame", "UnbunkUtilityFocusFreezeAnchor", UIParent, "BackdropTemplate")
    a:SetSize(64, 40)
    a:SetFrameStrata("MEDIUM")
    a:SetClampedToScreen(true)
    a:SetMovable(true)
    a:RegisterForDrag("LeftButton")
    a:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    local lbl = a:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
    lbl:SetPoint("CENTER")
    lbl:SetText(ns.L["Freeze stacks"])
    a.label = lbl
    a:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    a:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveAnchorPos() end)
    a:EnableMouse(false)
    anchor = a
    SetChrome(a, false)
    ApplyAnchorPos()
    return a
end

function FB.SetUnlocked(v)
    unlocked = v and true or false
    local a = EnsureAnchor()
    a:EnableMouse(unlocked)
    SetChrome(a, unlocked)
    if unlocked then a:Show(); a:Raise() end
end
function FB.IsUnlocked() return unlocked end

function FB.ResetPos()
    local c = Cfg(); if c then c.point, c.x, c.y = DEFAULTS.point, DEFAULTS.x, DEFAULTS.y end
    ApplyAnchorPos()
end

if ns.RegisterBrandRefresh then
    ns.RegisterBrandRefresh("FocusFreezeAnchor", function(r, g, b)
        if anchor and unlocked then
            anchor:SetBackdropColor(r, g, b, 0.25)
            anchor:SetBackdropBorderColor(r, g, b, 1)
        end
    end)
end

-- ── Number overlay (our own FontStrings) ────────────────────────────────────────
local FrameShown  -- fwd decl (used by ResolveCDMIcon)
local overlay
local fsPool = {}

local function EnsureOverlay()
    if overlay then return overlay end
    overlay = CreateFrame("Frame", "UnbunkUtilityFocusFreezeOverlay", UIParent)
    overlay:SetSize(1, 1)
    overlay:SetFrameStrata("HIGH")
    overlay:Hide()
    return overlay
end

-- Pooled number FontStrings. All numbers share the overlay's BOTTOM point (overlapping): only STACKING
-- debuffs render a value, so in practice a single number (freezing) shows. countScale scales the base size.
local BASE_FONT_SIZE = 18
local function GetFS(i)
    if fsPool[i] then return fsPool[i] end
    local fs = EnsureOverlay():CreateFontString(nil, "OVERLAY")
    fs:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 0)
    fsPool[i] = fs
    return fs
end

-- Face a number FontString per config: font (LSM key/path override, else the addon's global font),
-- outline flags and colour. Size is applied separately via SetScale (countScale) in RenderCounts.
local function StyleFS(fs)
    local c   = Cfg()
    local key = (c and c.fontKey  and c.fontKey  ~= "") and c.fontKey  or nil
    local pth = (c and c.fontPath and c.fontPath ~= "") and c.fontPath or nil
    local path = (key or pth) and ns.ResolveFontPath(pth, key)
        or (ns.GetAddonFontPath and ns.GetAddonFontPath())
        or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(path, BASE_FONT_SIZE, (c and c.outline) or DEFAULTS.outline)
    local col = (c and c.color) or DEFAULTS.color
    fs:SetTextColor(col.r or 1, col.g or 1, col.b or 1, col.a or 1)
end

-- ── CDM buff-icon resolution (best-effort auto-follow) ──────────────────────────
FrameShown = function(f)
    if not f then return false end
    local ok, s = pcall(f.IsShown, f)
    return ok and s and true or false
end

local function ResolveCDMIcon(spellID)
    if not (spellID and ns.ResolveCDMGroupFrame) then return nil end
    local g = ns.ResolveCDMGroupFrame("buff:1")
    if not g then return nil end
    -- Engine mode: own-drawn E.Icon frames cache a (combat-safe) spellID.
    if type(g.children) == "table" then
        for _, ic in ipairs(g.children) do
            local sid = ic.spellID or ic._lastGoodSid or ic.baseSpellID
            if sid == spellID and FrameShown(ic) then return ic end
        end
    end
    local A = ns.CDMAnchor
    -- Engine mode: adopted native buff pool frames (spellId secret-guarded → nil in combat).
    if type(g.nativeBuffs) == "table" and A and A.NativeFrameSpellId then
        for _, nf in ipairs(g.nativeBuffs) do
            if A.NativeFrameSpellId(nf) == spellID and FrameShown(nf) then return nf end
        end
    end
    -- Native mode: scan the buff viewer pool.
    if A and A.EnumBuffIcons and A.NativeFrameSpellId then
        for _, nf in ipairs(A.EnumBuffIcons()) do
            if A.NativeFrameSpellId(nf) == spellID and FrameShown(nf) then return nf end
        end
    end
    return nil
end

-- The frame the numbers sit above: the live CDM icon when auto-follow is on and it resolves right now,
-- else our movable anchor. No stale caching (a native buff pool frame can be recycled onto another spell).
local function CurrentTarget()
    local c = Cfg()
    if c and c.autoFollow then
        local ic = ResolveCDMIcon(c.spellID or DEFAULTS.spellID)
        if ic then return ic end
    end
    return EnsureAnchor()
end

-- ── Apply ───────────────────────────────────────────────────────────────────────
-- Render one FontString per focus debuff, fed by the secret-safe GetAuraApplicationDisplayCount. We read
-- auraInstanceID (not secret) but never the stack value itself. pcall'd per aura so a stray secret can't
-- abort the pass.
local function RenderCounts(ov, scale, minCount)
    local shown = 0
    local getCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    local getByIndex = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
    if not (getCount and getByIndex) then return 0 end
    for i = 1, 40 do
        local data = getByIndex("focus", i)
        if not data then break end
        local ok = pcall(function()
            local aII = data.auraInstanceID
            if aII then
                shown = shown + 1
                local fs = GetFS(shown)
                StyleFS(fs)
                fs:SetScale(scale)
                fs:SetText(getCount("focus", aII, minCount, 999))   -- secret-safe: renders, never read
                fs:Show()
            end
        end)
        if not ok then shown = math.max(shown, 0) end
    end
    return shown
end

function FB.Apply()
    if not FB.Enabled() then
        if overlay then overlay:Hide() end
        return
    end
    EnsureAnchor(); ApplyAnchorPos()
    local ov = EnsureOverlay()

    if not UnitExists("focus") then
        ov:Hide()
        return
    end

    local c        = Cfg()
    local scale    = math.max(0.3, (c and c.countScale) or DEFAULTS.countScale)
    local minCount = (c and c.minCount) or DEFAULTS.minCount
    local target   = CurrentTarget()

    ov:ClearAllPoints()
    ov:SetPoint("BOTTOM", target, "TOP", 0, 4)
    ov:Show()

    local shown = RenderCounts(ov, scale, minCount)
    for i = shown + 1, #fsPool do fsPool[i]:Hide() end
end

-- ── Triggers ──────────────────────────────────────────────────────────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if not FB.Enabled() then return end
    C_Timer.After(0, FB.Apply)
end)

-- Focus aura changes go through the shared dispatcher (coalesced to one next-frame callback).
ns.AuraDispatch.Register("focus", function()
    if FB.Enabled() then FB.Apply() end
end)

-- Drop the unlock chrome when combat starts (it must not linger as a click-catching movable frame).
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function() if unlocked then FB.SetUnlocked(false) end end)

ns.RegisterReloadHook(function()
    if unlocked then FB.SetUnlocked(false) end
    FB.Apply()
end)

-- ── Diagnostic ──────────────────────────────────────────────────────────────────
-- /uufreeze — checks the pieces: is a focus set, how many debuffs the API sees, whether the secret-safe
-- render API exists, and whether the CDM buff icon resolves for auto-follow. (We can't print the stack
-- value — it is secret — so confirm the number visually with the feature enabled.)
SLASH_UUFREEZE1 = "/uufreeze"
SlashCmdList["UUFREEZE"] = function()
    print(("|cff338cff[Focus Freezing]|r enabled=%s spellID=%s countScale=%s minCount=%s autoFollow=%s")
        :format(tostring(FB.Enabled()), tostring(FB.Get("spellID")), tostring(FB.Get("countScale")),
                tostring(FB.Get("minCount")), tostring(FB.Get("autoFollow"))))
    print(("  focusExists=%s  GetAuraApplicationDisplayCount=%s")
        :format(tostring(UnitExists("focus")),
                tostring(C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount ~= nil)))
    local n = 0
    pcall(function()
        for i = 1, 40 do
            local d = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex and C_UnitAuras.GetDebuffDataByIndex("focus", i)
            if not d then break end
            n = n + 1
        end
    end)
    print(("  API focus debuffs: %d (run with the freezing debuff up)"):format(n))
    local c  = Cfg()
    local ic = c and ResolveCDMIcon(c.spellID or DEFAULTS.spellID)
    print(("  CDM icon resolved: %s  |  target = %s")
        :format(ic and (ic.GetName and ic:GetName() or "(anon frame)") or "no",
                ic and "CDM icon" or "movable anchor"))
end
