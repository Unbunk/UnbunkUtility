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

-- Config-driven appearance PARITY with the native CDM: read the native per-icon config (I.IconGet resolves
-- per-icon override -> group -> template) and restyle OUR OWN regions to match. Phase 1 covers border (shared
-- ns.CDMAnchor.ApplyFrameBorder), the C-side countdown number (font/colour via a per-frame CreateFont +
-- SetCountdownFont, plus the native decimals/mm:ss formatter — all secret-safe, drawn C-side), and the
-- stack/charge count. Size + title + keybind + urgency tiers land in later slices. E.Icon is 100% ours, so
-- every write here is taint-free. Cheap early-out when no CDMGroups dest backs this icon.
function Icon.StyleFrame(f)
    local I = DestI(f)
    local sid = f._lastGoodSid or f.spellID
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
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not showTimer) end
    if f._cdFont then
        f._cdFont:SetFont(ns.ResolveFontPath(I.IconGet(sid, "timerFontPath"), I.IconGet(sid, "timerFontKey")),
            I.IconGet(sid, "timerFontSize") or 14, I.IconGet(sid, "timerOutline") or "OUTLINE")
        local tcol = I.IconGet(sid, "timerColor")
        if tcol then f._cdFont:SetTextColor(tcol.r, tcol.g, tcol.b, tcol.a or 1) end
        if cd.SetCountdownFont then cd:SetCountdownFont(f._cdFontName) end
    end
    if cd.SetCountdownFormatter then
        cd:SetCountdownFormatter(ns.CDMGroups.CooldownFormatter
            and ns.CDMGroups.CooldownFormatter.GetFor(I, sid) or nil)
    end

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

-- Swipe: ONE secret-safe source. ns.SpellRealCooldownSwipe returns the duration object of the real
-- cooldown (or the recharging charge's arc), or nil when the spell is idle / only on GCD — in which
-- case we Clear() (drawing a swipe then would look falsely ready/busy).
local function UpdateSwipe(f)
    local sid = f.spellID or f._lastGoodSid
    if not sid then f.Cooldown:Clear(); return end
    local swipe = ns.SpellRealCooldownSwipe and ns.SpellRealCooldownSwipe(sid)
    local onGcd = false
    -- Default ON (togglable): if there's no REAL cooldown, draw the global-cooldown sweep instead (Coolinator
    -- style). Its number is hidden (a GCD "1" flashing on every cast is noise); a real cooldown keeps its number.
    if not swipe and E.Cfg and E.Cfg.Get and E.Cfg.Get("showGcdSwipe") and ns.SpellGcdSwipe then
        swipe = ns.SpellGcdSwipe(sid)
        onGcd = swipe ~= nil
    end
    if swipe and f.Cooldown.SetCooldownFromDurationObject then
        f.Cooldown:SetHideCountdownNumbers(onGcd)   -- number on a real CD; hidden during the GCD spin
        f.Cooldown:SetCooldownFromDurationObject(swipe)
    else
        f.Cooldown:Clear()
    end
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
    f.cdmID, f.spellID, f.baseSpellID, f.info, f._lastGoodSid = nil, nil, nil, nil, nil
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    pool[#pool + 1] = f
end

function Icon.ReleaseAll()
    for f in pairs(active) do Icon.Release(f) end
end
