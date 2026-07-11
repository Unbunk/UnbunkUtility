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

-- Build a fresh handle. A black BACKGROUND fill + a 1px icon inset gives a clean 1px border for the
-- MVP (fancy masks/borders come later). The Cooldown swipe EMPTIES (SetReverse(false)) — it is a
-- cooldown, not a buff fill.
local function BuildFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(f) else f:SetFrameStrata("MEDIUM") end

    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg:SetAllPoints()
    f.Bg:SetColorTexture(0, 0, 0, 1)

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetPoint("TOPLEFT", 1, -1)
    f.Icon:SetPoint("BOTTOMRIGHT", -1, 1)

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", 1, -1)
    cd:SetPoint("BOTTOMRIGHT", -1, 1)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(false)              -- cooldown swipe empties as time passes
    cd:SetHideCountdownNumbers(false) -- let the native Cooldown draw the number (secret-safe, C-side)
    f.Cooldown = cd

    f.Count = f:CreateFontString(nil, "OVERLAY", nil, 7)
    f.Count:SetFontObject("NumberFontNormal")
    f.Count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

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

-- Swipe: ONE secret-safe source. ns.SpellRealCooldownSwipe returns the duration object of the real
-- cooldown (or the recharging charge's arc), or nil when the spell is idle / only on GCD — in which
-- case we Clear() (drawing a swipe then would look falsely ready/busy).
local function UpdateSwipe(f)
    local sid = f.spellID or f._lastGoodSid
    if not sid then f.Cooldown:Clear(); return end
    local swipe = ns.SpellRealCooldownSwipe and ns.SpellRealCooldownSwipe(sid)
    if swipe and f.Cooldown.SetCooldownFromDurationObject then
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
    end
    UpdateSwipe(f)
    UpdateCharges(f)
    if E.IconExtras then E.IconExtras.Register(f) end   -- proc glow + range tint (registers once sid is resolved)
end

function Icon.Setup(f, cdmID)
    f.cdmID = cdmID
    f.spellID, f.baseSpellID, f.info = nil, nil, nil
    Resolve(f)
    local sid = f.spellID or f._lastGoodSid
    f.Icon:SetTexture((sid and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or FALLBACK_ICON)
    Icon.ApplySize(f, ICON_SIZE)
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
