-- Modules/CDMEngine/Display/Icon.lua
--
-- Phase 1 of the standalone CDM engine (ns.CDMEngine). A pooled, 100%-OWN icon widget drawn beside
-- the native viewers — it never touches / hooks / mutates a native CDM frame (that would taint the
-- secure refresh). It mirrors the proven CustomBuffs "CustomFrame" shape (Icon + CooldownFrameTemplate
-- + Count) and drives everything SECRET-SAFE: the swipe from a native duration OBJECT
-- (ns.SpellRealCooldownSwipe -> Cooldown:SetCooldownFromDurationObject), the countdown number left to
-- the native Cooldown (SetHideCountdownNumbers(false)), and charges via C_StringUtil.TruncateWhenZero.
-- We NEVER recompute start/duration in Lua for a spell (they are secret in combat).

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
local Icon = {}
E.Icon = Icon

local issecretvalue    = issecretvalue or function() return false end   -- testing secrecy is always safe
local C_Spell          = C_Spell
local TruncateWhenZero = C_StringUtil and C_StringUtil.TruncateWhenZero

local ICON_SIZE    = 40
local FALLBACK_ICON = 134400   -- question-mark, for an unresolved / unknown spell

-- Crop to match the native CDM icon zoom (copied verbatim from UI/Shared/TimerIcon.lua:247-256).
local ICON_ZOOM = 0.07
local function IconTexCoordFor(w, h)
    if not (w and h) or w <= 0 or h <= 0 then return ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM end
    local texW = 1 - ICON_ZOOM * 2
    local aspect = w / h
    local xR = aspect < 1 and aspect or 1
    local yR = aspect > 1 and 1 / aspect or 1
    return -0.5 * texW * xR + 0.5,  0.5 * texW * xR + 0.5,
           -0.5 * texW * yR + 0.5,  0.5 * texW * yR + 0.5
end

local pool, active = {}, {}

local fontSeq = 0   -- unique name suffix for each frame's countdown Font object

-- The CDMGroups config instance backing this icon's dest ("essential"/"utility"). The engine REUSES the
-- native per-dest config (groups + per-icon overrides) as its single source of truth: I.IconGet(sid, key)
-- resolves per-icon override -> group default -> template. Phase 1 wires only "essential".
local function DestI(f)
    return ns.CDMGroups and ns.CDMGroups[f._dest or "essential"]
end

-- Build a fresh handle. The icon FILLS the frame; the border is drawn as inset edges by StyleFrame
-- (ns.CDMAnchor.ApplyFrameBorder) so it matches the native CDM look and honours the per-icon config. The
-- Cooldown swipe EMPTIES (SetReverse(false)) — it is a cooldown, not a buff fill.
local function BuildFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(f) else f:SetFrameStrata("MEDIUM") end

    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg:SetAllPoints()
    f.Bg:SetColorTexture(0, 0, 0, 1)

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints()   -- fills the frame; StyleFrame draws the border as inset edges over it

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(false)              -- cooldown swipe empties as time passes
    cd:SetHideCountdownNumbers(false) -- let the native Cooldown draw the number (secret-safe, C-side)
    f.Cooldown = cd

    f.Count = f:CreateFontString(nil, "OVERLAY", nil, 7)
    f.Count:SetFontObject("NumberFontNormal")
    f.Count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

    f.Title   = f:CreateFontString(nil, "OVERLAY", nil, 7)   -- free label (StyleFrame styles/positions/hides)
    f.Keybind = f:CreateFontString(nil, "OVERLAY", nil, 7)   -- action-bar keybind text
    -- Give both a default font up front: StyleFrame only sets a font when the feature is ENABLED (both default
    -- OFF), yet Release SetText("")s them to blank inherited text. A fontless FontString errors on SetText
    -- ("Font not set"), so seed a font object at creation (like Count above); StyleFrame overrides it when shown.
    f.Title:SetFontObject("GameFontHighlightSmall")
    f.Keybind:SetFontObject("GameFontHighlightSmall")

    -- A per-frame CreateFont object drives the C-side countdown number's font/colour via cd:SetCountdownFont
    -- — the only way to restyle the secret-safe native countdown. Named uniquely so each pooled frame keeps
    -- its own font.
    fontSeq = fontSeq + 1
    f._cdFontName = "UnbunkUtilityEngTimer" .. fontSeq
    f._cdFont     = CreateFont(f._cdFontName)

    return f
end

-- Resolve the DISPLAY + BASE spell id of a cooldownID and MEMORISE them on the handle. Both native
-- resolvers return nil when the id is secret (combat), so we cache the last good display id and reuse
-- it in Update — never re-resolving (nor comparing) a secret value in combat.
local function Resolve(f)
    local info = E.Blob and E.Blob.GetInfo and E.Blob.GetInfo(f.cdmID)
    if type(info) ~= "table" then return end
    f.info = info
    local A = ns.CDMAnchor
    local sid = A and A.NativeFrameSpellId and A.NativeFrameSpellId({ cooldownInfo = info })
    if sid then f.spellID, f._lastGoodSid = sid, sid end
    local base = A and A.NativeFrameBaseSpellId and A.NativeFrameBaseSpellId({ cooldownInfo = info })
    if base then f.baseSpellID = base end
end

function Icon.ApplySize(f, size)
    size = size or ICON_SIZE
    f:SetSize(size, size)
    f.Icon:SetTexCoord(IconTexCoordFor(size, size))
end

-- Re-anchor the native Cooldown's countdown FontString to the configured timer position (timerPos/OffX/OffY),
-- parity with CDMGroups' StyleCooldownRegions/AnchorTimerFS. The Cooldown creates its number FontString
-- LAZILY (first time it shows) and re-centres it when the cooldown restarts, so we (re)find + cache the
-- region and re-apply on each swipe start. No-op unless the icon has a NON-default timer position.
local function AnchorCountdown(f)
    if not (f._timerReanchor and ns.AnchorFS) then return end
    local cd = f.Cooldown
    if not cd then return end
    local fs = f._cdText
    if not (fs and fs.SetPoint) then
        fs = cd.Text or cd.text
        if not (fs and fs.IsObjectType and fs:IsObjectType("FontString")) then
            fs = nil
            for _, r in ipairs({ cd:GetRegions() }) do
                if r and r.IsObjectType and r:IsObjectType("FontString") then fs = r; break end
            end
        end
        f._cdText = fs
    end
    if fs and fs.SetPoint then
        pcall(ns.AnchorFS, fs, f, f._timerPos or "CENTER", f._timerOffX, f._timerOffY)
    end
end

-- Config-driven appearance PARITY with the native CDM: read the native per-icon config (I.IconGet resolves
-- per-icon override -> group -> template) and restyle OUR OWN regions to match. Phase 1 covers border (shared
-- ns.CDMAnchor.ApplyFrameBorder), the C-side countdown number (font/colour via a per-frame CreateFont +
-- SetCountdownFont, plus the native decimals/mm:ss formatter — all secret-safe, drawn C-side), and the
-- stack/charge count. Size + title + keybind + urgency tiers land in later slices. E.Icon is 100% ours, so
-- every write here is taint-free. Cheap early-out when no CDMGroups dest backs this icon.
function Icon.StyleFrame(f)
    local I = DestI(f)
    -- Resolve config by the STABLE BASE spellId: CDMGroups keys iconCfg (per-icon overrides) AND the group
    -- assign store by base (I.GroupOf/I.IconGet). Using the DISPLAY id for a transformed cooldown (e.g.
    -- Blink 1953 -> Shimmer 212653) makes GroupOf() fall through to Unused(0) -> the icon reads the template
    -- default size/style instead of its real group's -> it renders oversized/mis-styled. Fall back to the
    -- display id only if the base hasn't resolved yet (secret in combat before the first out-of-combat pass).
    local sid = f.baseSpellID or f._lastGoodSid or f.spellID
    if not (I and sid and I.IconGet) then return end

    -- Size: the icon fills the frame; ArrangeGroup then lays the group out by each icon's measured size,
    -- so a non-square iconW/iconH flows correctly.
    local iconW = I.IconGet(sid, "iconW") or ICON_SIZE
    local iconH = I.IconGet(sid, "iconH") or ICON_SIZE
    f:SetSize(iconW, iconH)
    f.Icon:SetTexCoord(IconTexCoordFor(iconW, iconH))

    -- Border: inset edges over the filled icon (default enabled / black / 1px), per the icon's config.
    if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then
        ns.CDMAnchor.ApplyFrameBorder(f, I.IconGet(sid, "borderEnabled") ~= false,
            I.IconGet(sid, "borderColor"), I.IconGet(sid, "borderSize"))
    end

    -- C-side countdown number: font + colour (via our per-frame Font) + the native formatter (decimals /
    -- mm:ss / colour-below-threshold, formatted C-side so it stays correct in combat). Secret-safe.
    local cd = f.Cooldown
    local showTimer = I.IconGet(sid, "showTimer") ~= false
    f._showTimer = showTimer   -- cached so UpdateSwipe honours it (UpdateSwipe re-touches SetHideCountdownNumbers)
    -- "Show cd with 1 stacks or more" (default ON): draw the recharge arc for a multi-charge spell even while a
    -- charge is usable (a real cooldown is inactive then). Cached so UpdateSwipe reads it cheaply every refresh.
    f._showCdWithStacks = I.IconGet(sid, "showCdWithStacks") ~= false
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not showTimer) end
    if f._cdFont then
        f._cdFont:SetFont(ns.ResolveFontPath(I.IconGet(sid, "timerFontPath"), I.IconGet(sid, "timerFontKey")),
            I.IconGet(sid, "timerFontSize") or 14, I.IconGet(sid, "timerOutline") or "OUTLINE")
        local tcol = I.IconGet(sid, "timerColor")
        if tcol then f._cdFont:SetTextColor(tcol.r, tcol.g, tcol.b, tcol.a or 1) end
        if cd.SetCountdownFont then cd:SetCountdownFont(f._cdFontName) end
    end
    f._tierScale = nil   -- just set the BASE size; the tier poller re-applies any threshold scale next tick
    if cd.SetCountdownFormatter then
        cd:SetCountdownFormatter(ns.CDMGroups.CooldownFormatter
            and ns.CDMGroups.CooldownFormatter.GetFor(I, sid) or nil)
    end
    -- Timer text POSITION (timerPos/OffX/OffY): re-anchor the native countdown FontString to match CDMGroups.
    -- Cached + re-applied on each swipe start (the Cooldown re-centres its number when it restarts).
    f._timerPos  = I.IconGet(sid, "timerPos") or "CENTER"
    f._timerOffX = I.IconGet(sid, "timerOffX")
    f._timerOffY = I.IconGet(sid, "timerOffY")
    f._timerReanchor = (f._timerPos ~= "CENTER")
        or (f._timerOffX and f._timerOffX ~= 0) or (f._timerOffY and f._timerOffY ~= 0) or false
    AnchorCountdown(f)

    -- Stack / charge count (our own Count FontString): font / colour / position per config.
    if I.IconGet(sid, "showStack") ~= false then
        f.Count:SetFont(ns.ResolveFontPath(I.IconGet(sid, "stackFontPath"), I.IconGet(sid, "stackFontKey")),
            I.IconGet(sid, "stackFontSize") or 10, I.IconGet(sid, "stackOutline") or "OUTLINE")
        local sc = I.IconGet(sid, "stackColor") or { r = 1, g = 1, b = 1, a = 1 }
        f.Count:SetTextColor(sc.r, sc.g, sc.b, sc.a or 1)
        if ns.AnchorFS then
            ns.AnchorFS(f.Count, f, I.IconGet(sid, "stackPos") or "BOTTOMRIGHT",
                I.IconGet(sid, "stackOffX"), I.IconGet(sid, "stackOffY"))
        end
    end

    -- Title (free label over the icon; default OFF).
    if I.IconGet(sid, "showTitle") == true then
        f.Title:SetFont(ns.ResolveFontPath(I.IconGet(sid, "titleFontPath"), I.IconGet(sid, "titleFontKey")),
            I.IconGet(sid, "titleFontSize") or 12, I.IconGet(sid, "titleOutline") or "OUTLINE")
        local c = I.IconGet(sid, "titleColor") or { r = 1, g = 1, b = 1, a = 1 }
        f.Title:SetTextColor(c.r, c.g, c.b, c.a or 1)
        f.Title:SetDrawLayer("OVERLAY", 7)
        if ns.AnchorFS then
            ns.AnchorFS(f.Title, f, I.IconGet(sid, "titlePos") or "TOP",
                I.IconGet(sid, "titleOffX"), I.IconGet(sid, "titleOffY"))
        end
        f.Title:SetText(I.IconGet(sid, "titleText") or "")
        f.Title:Show()
    else
        f.Title:Hide()
    end

    -- Keybind text from the action bar (shared CDG keybind map; default OFF).
    if I.IconGet(sid, "showKeybinds") == true and ns.CDGKeybinds and ns.CDGKeybinds.GetKeybindText then
        f.Keybind:SetFont(ns.ResolveFontPath(I.IconGet(sid, "keybindFontPath"), I.IconGet(sid, "keybindFontKey")),
            I.IconGet(sid, "keybindFontSize") or 12, I.IconGet(sid, "keybindOutline") or "OUTLINE")
        local c = I.IconGet(sid, "keybindColor") or { r = 1, g = 1, b = 1, a = 1 }
        f.Keybind:SetTextColor(c.r, c.g, c.b, c.a or 1)
        f.Keybind:SetDrawLayer("OVERLAY", 7)
        if ns.AnchorFS then
            ns.AnchorFS(f.Keybind, f, I.IconGet(sid, "keybindPos") or "TOPLEFT",
                I.IconGet(sid, "keybindOffX"), I.IconGet(sid, "keybindOffY"))
        end
        local txt = ns.CDGKeybinds.GetKeybindText(sid)
        if txt and txt ~= "" then f.Keybind:SetText(txt); f.Keybind:Show() else f.Keybind:Hide() end
    else
        f.Keybind:Hide()
    end
end

-- Is a charge/stack still usable? currentCharges is SECRET in combat -> treat as "not determinable" (false),
-- which desaturates on cooldown, matching the native TimerIcon behaviour (ChargesAvailable / ApplyCdDesat).
local function ChargeAvailable(sid)
    local ci = sid and C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    if not ci then return false end
    local cur = ci.currentCharges
    if cur == nil or issecretvalue(cur) then return false end
    return cur > 0
end
-- "Darken icon when on cd with stacks" parity with the native path (TimerIcon.ApplyCdDesat): on a REAL
-- cooldown, grey the icon — unless a charge is still usable AND the darken-with-stacks toggle is OFF.
local function ApplyDesat(f, onRealCd)
    if not (f.Icon and f.Icon.SetDesaturated) then return end
    if not onRealCd then f.Icon:SetDesaturated(false); return end
    local I   = DestI(f)
    local sid = f.baseSpellID or f._lastGoodSid or f.spellID
    local darken = I and sid and I.IconGet and I.IconGet(sid, "darkenOnCdWithStacks") == true
    f.Icon:SetDesaturated(darken or not ChargeAvailable(f.spellID or f._lastGoodSid))
end

-- Swipe: ONE secret-safe source. ns.SpellRealCooldownSwipe returns the duration object of the real
-- cooldown (or the recharging charge's arc), or nil when the spell is idle / only on GCD — in which
-- case we Clear() (drawing a swipe then would look falsely ready/busy).
local function UpdateSwipe(f)
    local sid = f.spellID or f._lastGoodSid
    if not sid then f.Cooldown:Clear(); ApplyDesat(f, false); return end
    local realSwipe = ns.SpellRealCooldownSwipe and ns.SpellRealCooldownSwipe(sid)
    local swipe = realSwipe
    local onGcd = false
    -- "Show cd with 1 stacks or more": no real cooldown (a charge is still usable) but the user wants the
    -- recharge arc drawn anyway, like the native CooldownViewer. Secret-safe object; nothing is drawn at full.
    if not swipe and f._showCdWithStacks and ns.SpellChargeRechargeSwipe then
        swipe = ns.SpellChargeRechargeSwipe(sid)
    end
    -- Default ON (togglable): if there's no REAL cooldown, draw the global-cooldown sweep instead (the reference engine
    -- style). Its number is hidden (a GCD "1" flashing on every cast is noise); a real cooldown keeps its number.
    if not swipe and E.Cfg and E.Cfg.Get and E.Cfg.Get("showGcdSwipe") and ns.SpellGcdSwipe then
        swipe = ns.SpellGcdSwipe(sid)
        onGcd = swipe ~= nil
    end
    if swipe and f.Cooldown.SetCooldownFromDurationObject then
        f.Cooldown:SetHideCountdownNumbers(onGcd or (f._showTimer == false))   -- honour showTimer=off; also hide during the GCD spin
        f.Cooldown:SetCooldownFromDurationObject(swipe)
        AnchorCountdown(f)   -- the Cooldown re-centres its number on (re)start; re-apply the configured position
    else
        f.Cooldown:Clear()
    end
    -- Desaturation is driven by the REAL cooldown only: a recharge arc drawn by "Show cd with 1 stacks or
    -- more" leaves the icon LIT (a charge is still usable), and the GCD spin never greys (realSwipe is nil then).
    ApplyDesat(f, realSwipe ~= nil)
end

-- Charge count. Only shown for a multi-charge spell that is not full. In combat currentCharges is
-- SECRET -> render it C-side via TruncateWhenZero without ever reading it in Lua.
local function UpdateCharges(f)
    local count = f.Count
    local sid = f.spellID or f._lastGoodSid
    local ci = sid and C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    if not ci then count:Hide(); return end
    local maxc = ci.maxCharges
    if issecretvalue(maxc) then maxc = nil end
    if not (type(maxc) == "number" and maxc > 1) then count:Hide(); return end
    local cur = ci.currentCharges
    if cur ~= nil and issecretvalue(cur) then
        if TruncateWhenZero and pcall(count.SetText, count, TruncateWhenZero(cur)) then count:Show() else count:Hide() end
    elseif type(cur) == "number" then
        count:SetText(cur); count:Show()   -- multi-charge: show the count at all levels (native behaviour)
    else
        count:Hide()
    end
end

function Icon.Update(f)
    if not f.cdmID then return end
    -- Self-heal a never-resolved id: a Setup that ran IN combat can't resolve the display spell (the
    -- ids are secret then) and leaves the icon a fallback with no swipe. Re-resolve here — it succeeds
    -- once we're out of combat (the row's PLAYER_REGEN_ENABLED refresh drives this) — and re-apply the
    -- texture. NOTE: live spell TRANSFORMATIONS (override changing mid-fight) are NOT tracked in Phase 1;
    -- they pick up at the next Rebuild (live override rebind is a later phase).
    if not (f.spellID or f._lastGoodSid) then
        Resolve(f)
        local sid = f.spellID or f._lastGoodSid
        f.Icon:SetTexture((sid and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or FALLBACK_ICON)
        if sid then Icon.StyleFrame(f) end   -- re-style now that a config lookup by sid is possible
    end
    UpdateSwipe(f)
    UpdateCharges(f)
    if E.IconExtras then E.IconExtras.Register(f) end   -- proc glow + range tint (registers once sid is resolved)
end

function Icon.Setup(f, cdmID)
    f.cdmID = cdmID
    f._dest = f._dest or "essential"   -- Phase 1 wires only Essential to the native config
    f.spellID, f.baseSpellID, f.info = nil, nil, nil
    Resolve(f)
    local sid = f.spellID or f._lastGoodSid
    f.Icon:SetTexture((sid and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or FALLBACK_ICON)
    Icon.ApplySize(f, ICON_SIZE)
    Icon.StyleFrame(f)   -- config-driven border / countdown font / stacks (our own frame, no taint)
    f:Show()   -- a pooled icon was Hidden by Release; Setup means "display this" (symmetric)
    Icon.Update(f)
end

function Icon.Acquire()
    local f = table.remove(pool) or BuildFrame()
    active[f] = true
    return f
end

-- Park: cut the OnCooldownDone script + Clear() FIRST (a ghost OnCooldownDone would re-activate a dead
-- entry), blank the count, hide, unparent, and return to the pool.
function Icon.Release(f)
    if not f then return end
    active[f] = nil
    if E.IconExtras then E.IconExtras.Unregister(f) end   -- stop glow + disable range check + reset tint
    if f.Cooldown then
        f.Cooldown:SetScript("OnCooldownDone", nil)
        f.Cooldown:Clear()
    end
    if f.Count then f.Count:SetText(""); f.Count:Hide() end
    if f.Icon and f.Icon.SetDesaturated then f.Icon:SetDesaturated(false) end   -- pooled reuse: start lit
    -- Blank the decorations so a POOLED frame reused in combat for a spell whose id is still secret (StyleFrame
    -- early-outs) can't inherit the prior spell's title/keybind/border over the fallback art.
    if f.Title   then f.Title:SetText("");   f.Title:Hide()   end
    if f.Keybind then f.Keybind:SetText(""); f.Keybind:Hide() end
    if f.PressOverlay then f.PressOverlay:Hide() end
    if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then ns.CDMAnchor.ApplyFrameBorder(f, false) end
    f.cdmID, f.spellID, f.baseSpellID, f.info, f._lastGoodSid, f._dest, f._showTimer, f._tierScale = nil, nil, nil, nil, nil, nil, nil, nil
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    pool[#pool + 1] = f
end

function Icon.ReleaseAll()
    for f in pairs(active) do Icon.Release(f) end
end

-- ── Press overlay: flash the icon while its action-bar keybind is physically HELD, mirroring the native
-- CDMGroups poller (Engine.lua). Taint-free: only IsKeyDown / modifier getters + a plain texture on OUR own
-- frame; the config (showPressOverlay / pressOverlayColor) resolves per-icon by the BASE spellId via the
-- backing CDMGroups instance. A single 0.05s poller runs ONLY while at least one shown icon wants it. ────
local PRESS_FALLBACK = { r = 1, g = 1, b = 1, a = 0.35 }
local function FrameOverlay(f)
    if f.PressOverlay then return f.PressOverlay end
    local tex = f:CreateTexture(nil, "OVERLAY", nil, 1)   -- above the icon (ARTWORK), below border/text (sublevel 7)
    tex:SetAllPoints(f)
    tex:Hide()
    f.PressOverlay = tex
    return tex
end
local function ComboDown(c)
    if c.shift ~= IsShiftKeyDown()   then return false end
    if c.ctrl  ~= IsControlKeyDown() then return false end
    if c.alt   ~= IsAltKeyDown()     then return false end
    return IsKeyDown(c.key)
end
local function AnyComboDown(combos)
    for _, c in ipairs(combos) do if ComboDown(c) then return true end end
    return false
end
-- Press overlay is registered under the action's spellId, which may be the BASE or the live DISPLAY id, so
-- try both (mirrors CDMGroups' keyToDisplay fallback).
local function IconCombos(f, sid)
    if not (ns.CDGKeybinds and ns.CDGKeybinds.GetRawCombos) then return nil end
    local combos = ns.CDGKeybinds.GetRawCombos(sid)
    if not combos and f.spellID and f.spellID ~= sid then
        combos = ns.CDGKeybinds.GetRawCombos(f.spellID)
    end
    return combos
end
local pressAccum = 0
local pressPoll = CreateFrame("Frame")
pressPoll:Hide()
pressPoll:SetScript("OnUpdate", function(_, dt)
    pressAccum = pressAccum + dt
    if pressAccum < 0.05 then return end
    pressAccum = 0
    local typing = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()   -- don't flash while typing in a box
    for f in pairs(active) do
        local I   = DestI(f)
        local sid = f.baseSpellID or f._lastGoodSid or f.spellID
        local want = false
        if (not typing) and I and sid and I.IconGet and I.IconGet(sid, "showPressOverlay") == true then
            local combos = IconCombos(f, sid)
            if combos and AnyComboDown(combos) then want = true end
        end
        if want then
            local ov = FrameOverlay(f)
            local pc = (I and I.IconGet(sid, "pressOverlayColor")) or PRESS_FALLBACK
            ov:SetColorTexture(pc.r, pc.g, pc.b, pc.a or 0.35)
            ov:Show()
        elseif f.PressOverlay then
            f.PressOverlay:Hide()
        end
    end
end)

-- Enable the poller only when a shown icon actually wants the overlay (avoid an idle 0.05s OnUpdate). Called
-- by Layout after every build; a showPressOverlay edit bumps ns.StyleEpoch -> a full rebuild -> this re-runs.
function Icon.RefreshPressPoll()
    for f in pairs(active) do
        local I   = DestI(f)
        local sid = f.baseSpellID or f._lastGoodSid or f.spellID
        if I and sid and I.IconGet and I.IconGet(sid, "showPressOverlay") == true then
            pressPoll:Show(); return
        end
    end
    pressPoll:Hide()
end

-- ── Timer-urgency SIZE scaling (timerThresholds): the countdown number GROWS below a configured time. The
-- number is drawn C-side (secret-safe) so we can't restyle it from its value per frame; instead we read the
-- cooldown's REMAINING time (GetSpellCooldown — readable everywhere EXCEPT instanced combat, where it's
-- secret, so we hold the last size) on a throttled tick and rescale the per-frame countdown Font. Colour
-- below a threshold is already handled C-side by the CooldownFormatter, so only SIZE lives here. ───────────
local function TierScaleFor(f)
    local I   = DestI(f)
    local sid = f.baseSpellID or f._lastGoodSid or f.spellID
    if not (I and sid and I.IconGet and I.IconGet(sid, "timerThresholdsEnabled") == true) then return 1 end
    local thr = I.IconGet(sid, "timerThresholds")
    if type(thr) ~= "table" then return 1 end
    local dsid = f.spellID or f._lastGoodSid
    local cd = dsid and C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(dsid)
    if not (cd and cd.isActive) then return 1 end                       -- ready -> base size
    local st, du = cd.startTime, cd.duration
    if st == nil or du == nil or issecretvalue(st) or issecretvalue(du) then return nil end   -- secret -> hold
    local remaining = (st + du) - GetTime()
    if remaining <= 0 then return 1 end
    local best, bestAt   -- the most urgent matching tier (smallest `time` the remaining has fallen to/below)
    for _, x in ipairs(thr) do
        local at = x.time or 0
        if remaining <= at and (not bestAt or at < bestAt) then best, bestAt = x, at end
    end
    return (best and best.size) or 1   -- size = a scale multiplier (parity with TimerIcon SetTimerFont)
end
local function ApplyTierSize(f)
    local scale = TierScaleFor(f)
    if scale == nil or f._tierScale == scale then return end   -- secret time held, or unchanged -> nothing to do
    f._tierScale = scale
    local I   = DestI(f)
    local sid = f.baseSpellID or f._lastGoodSid or f.spellID
    if not (I and sid and f._cdFont) then return end
    local base = I.IconGet(sid, "timerFontSize") or 14
    f._cdFont:SetFont(ns.ResolveFontPath(I.IconGet(sid, "timerFontPath"), I.IconGet(sid, "timerFontKey")),
        math.max(8, math.floor(base * scale)), I.IconGet(sid, "timerOutline") or "OUTLINE")
    if f.Cooldown.SetCountdownFont then f.Cooldown:SetCountdownFont(f._cdFontName) end
    AnchorCountdown(f)   -- SetCountdownFont can re-centre the number; hold the configured position
end
local tierAccum = 0
local tierPoll = CreateFrame("Frame")
tierPoll:Hide()
tierPoll:SetScript("OnUpdate", function(_, dt)
    tierAccum = tierAccum + dt
    if tierAccum < 0.2 then return end
    tierAccum = 0
    for f in pairs(active) do ApplyTierSize(f) end
end)
-- Enable the tier poller only while a shown icon has thresholds ON (avoid an idle OnUpdate). Layout calls this
-- after every build; a threshold edit bumps ns.StyleEpoch -> a rebuild -> this re-runs.
function Icon.RefreshTierPoll()
    for f in pairs(active) do
        local I   = DestI(f)
        local sid = f.baseSpellID or f._lastGoodSid or f.spellID
        if I and sid and I.IconGet and I.IconGet(sid, "timerThresholdsEnabled") == true then
            tierPoll:Show(); return
        end
    end
    tierPoll:Hide()
end
