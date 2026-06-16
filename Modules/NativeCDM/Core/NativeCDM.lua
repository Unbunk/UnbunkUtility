-- Modules/NativeCDM/Core/NativeCDM.lua
-- Customize the NATIVE Cooldown Manager icons with the addon's icon engine. When the
-- user "adopts" a native cooldown (the pen in the Essentials/Utility "Native icons"
-- cadre), we render an ns.ui.CreateTimerIcon for that spell — the SAME engine as the
-- custom CDM icons (urgency tiers, title, stacks, border, sounds) — as an injected CDM
-- icon, and ns.CDMAnchor HIDES the underlying native frame so it isn't shown twice.
--
-- An adopted icon is fully repositionable (its editor keeps the Placement cadre), so it
-- behaves exactly like a custom icon, minus the spell input (spell = the native's) and
-- the "icon at the end of the row" choice. Per-spell config is keyed by spellId in the
-- profile (ns.db.profile.cdmNative).

local ADDON, ns = ...
ns.NativeCDM = ns.NativeCDM or {}
local NC = ns.NativeCDM
local L = ns.L

local issecretvalue = issecretvalue or function() return false end
local FALLBACK_ICON = 134400
local GREEN = { r = 0, g = 1, b = 0 }

-- Per-icon defaults — identical VALUES to a custom CDM icon, minus the spell input and
-- the end-of-row choice (cdmAtEnd is fixed false: a native icon takes the start bucket).
local DEFAULTS = {
    showIcon       = true,
    includeInCdm   = true,
    cdmDest        = "essential",   -- set to the panel it was adopted from
    cdmAtEnd       = false,
    cdmRow         = 1,
    posX           = -300,
    posY           = -300,
    iconWidth      = 44,
    iconHeight     = 44,
    borderEnabled  = true,
    borderColor    = { r = 0, g = 0, b = 0, a = 1 },
    borderSize     = 1,
    showTimer      = true,
    timerFontKey   = "Fira Mono",
    timerFontPath  = nil,
    timerFontSize  = 14,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    showTitle      = false,
    titleText      = "",
    titleAnchor    = "TOP",
    titleOffsetX   = 0,
    titleOffsetY   = 0,
    titleFontKey   = "Fira Mono",
    titleFontPath  = nil,
    titleFontSize  = 16,
    titleOutline   = "OUTLINE",
    titleColor     = { r = 1, g = 1, b = 1, a = 1 },
    showStack      = true,
    showAtZero     = true,
    stackAnchor    = "BOTTOMRIGHT",
    stackOffsetX   = 0,
    stackOffsetY   = 0,
    stackFontKey   = "Fira Mono",
    stackFontPath  = nil,
    stackFontSize  = 12,
    stackOutline   = "OUTLINE",
    stackColor     = { r = 1, g = 1, b = 1, a = 1 },
    soundOnUse     = false,
    soundKeyUse    = nil,
    soundPathUse   = nil,
    soundOnReady   = false,
    soundKeyReady  = nil,
    soundPathReady = nil,
}
NC.DEFAULTS = DEFAULTS

local DEFAULT_TIERS = {
    { at = 15, scale = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { at = 5,  scale = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
local function SeedTiers(e)
    if e and e.timerTiers == nil then e.timerTiers = ns.DeepCopy(DEFAULT_TIERS) end
end

-- ── Default styling of NON-adopted native frames ──────────────────────────────
-- A native icon we don't replace still keeps Blizzard's own cooldown/charge text. We
-- restyle it to the addon's default look the same way the reference CDM addon does: a shared Font object
-- drives the cooldown countdown via Cooldown:SetCountdownFont (size/font/outline persist on
-- the widget), the countdown colour is set on the Cooldown's FontString regions, and the
-- charge count FontString is set directly. Values come from DEFAULTS (the editor's defaults);
-- a per-spell customisation replaces the whole icon with our TimerIcon instead.
local nativeCdFont = _G["UnbunkUtilityNativeCDFont"] or CreateFont("UnbunkUtilityNativeCDFont")
local function RefreshNativeCdFont()
    nativeCdFont:SetFont(ns.ResolveFontPath(DEFAULTS.timerFontPath, DEFAULTS.timerFontKey),
                         DEFAULTS.timerFontSize or 14, DEFAULTS.timerOutline or "OUTLINE")
end
RefreshNativeCdFont()

function NC.StyleNativeText(nf)
    if not nf then return end
    local cd = nf.Cooldown
    if cd then
        if cd.SetCountdownFont then cd:SetCountdownFont("UnbunkUtilityNativeCDFont") end
        local c = DEFAULTS.timerColor or { r = 1, g = 1, b = 1, a = 1 }
        if cd.GetRegions then
            for i = 1, select("#", cd:GetRegions()) do
                local rgn = select(i, cd:GetRegions())
                if rgn and rgn.IsObjectType and rgn:IsObjectType("FontString") then
                    rgn:SetTextColor(c.r, c.g, c.b, c.a or 1)
                end
            end
        end
    end
    local charge = nf.ChargeCount and nf.ChargeCount.Current
    if charge and charge.SetFont then
        local sc = DEFAULTS.stackColor or { r = 1, g = 1, b = 1, a = 1 }
        charge:SetFont(ns.ResolveFontPath(DEFAULTS.stackFontPath, DEFAULTS.stackFontKey),
                       DEFAULTS.stackFontSize or 12, DEFAULTS.stackOutline or "OUTLINE")
        charge:SetTextColor(sc.r, sc.g, sc.b, sc.a or 1)
    end
end

local live = {}   -- live[spellId] = { icon, titleFS, stackFS, lastUseAt, learnedCd, lastExpiry, hasCooldown }

local FRAME_PREFIX = "UnbunkUtilityNativeCDM"
local function FrameName(spellId) return FRAME_PREFIX .. spellId end
function NC.FrameName(spellId) return FrameName(spellId) end
function NC.IsNativeFrame(name)
    return type(name) == "string" and name:match("^" .. FRAME_PREFIX .. "%d+$") ~= nil
end
function NC.SpellIdFromFrameName(name)
    local s = type(name) == "string" and name:match("^" .. FRAME_PREFIX .. "(%d+)$")
    return s and tonumber(s) or nil
end

-- ── Config store (per-profile, keyed by spellId) ──────────────────────────────
local function Store()
    if not (ns.db and ns.db.profile) then return nil end
    ns.db.profile.cdmNative = ns.db.profile.cdmNative or {}
    return ns.db.profile.cdmNative
end

local function Entry(spellId)
    local s = Store()
    return s and s[spellId] or nil
end

function NC.IsAdopted(spellId)
    return Entry(spellId) ~= nil
end

-- Hide the native whenever our replacement icon exists for an adopted spell. Native icons
-- are always kept IN the Cooldown Manager (they can't be moved or freed by the addon), so
-- adopting one always replaces it; a half-failed build (no live icon) shows the native.
function NC.ShouldHideNative(spellId)
    local e = Entry(spellId)
    return e ~= nil and live[spellId] ~= nil
end

-- Get the entry, creating it (adopting the native) on first access from the editor /
-- the pen. ctx = { dest, row } seeds the placement of a freshly-adopted icon.
local function EnsureEntry(spellId, ctx)
    local s = Store(); if not s then return nil end
    local e = s[spellId]
    if not e then
        e = {}
        ns.MergeDefaults(e, DEFAULTS)
        SeedTiers(e)
        if ctx then
            if ctx.dest then e.cdmDest = ctx.dest end
            if ctx.row  then e.cdmRow  = ctx.row  end
        end
        s[spellId] = e
    end
    return e
end

-- ── Spell helpers ─────────────────────────────────────────────────────────────
local function SpellTexture(spellId)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
    return tex or FALLBACK_ICON
end
function NC.SpellTexture(spellId) return SpellTexture(spellId) end
function NC.SpellName(spellId)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    return (info and info.name) or ("[" .. tostring(spellId) .. "]")
end

local function GetCooldown(spellId)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(spellId)
        if cd then return cd.startTime, cd.duration end
        return 0, 0
    end
    local start, duration = GetSpellCooldown(spellId)
    return start or 0, duration or 0
end

local function GetCharges(spellId)
    if C_Spell and C_Spell.GetSpellCharges then
        local ci = C_Spell.GetSpellCharges(spellId)
        if ci then
            local cur, maxc = ci.currentCharges, ci.maxCharges
            local cdS, cdD  = ci.cooldownStartTime, ci.cooldownDuration
            if issecretvalue(cur)  then cur  = nil end
            if issecretvalue(maxc) then maxc = nil end
            if issecretvalue(cdS)  then cdS  = nil end
            if issecretvalue(cdD)  then cdD  = nil end
            return cur, maxc, cdS, cdD
        end
    end
    return nil
end

local function SpellKnown(spellId)
    if IsPlayerSpell and IsPlayerSpell(spellId) then return true end
    if IsSpellKnown and IsSpellKnown(spellId) then return true end
    return false
end

local function PlaySound(spellId, which)
    local e = Entry(spellId)
    if not e then return end
    if which == "use" then
        ns.PlaySoundFromCfg(e, "soundPathUse", "soundKeyUse")
    elseif which == "ready" then
        ns.PlaySoundFromCfg(e, "soundPathReady", "soundKeyReady")
    end
end
function NC.TestSound(spellId, which) PlaySound(spellId, which) end

-- ── Title + stack FontStrings ─────────────────────────────────────────────────
-- Anchor placement is centralised in ns (Core/Shared.lua) so every icon shares the
-- same modes (edges + 4 inside corners).
local AnchorFS = ns.AnchorFS

local function ApplyTitle(spellId)
    local d = live[spellId]
    if not d or not d.titleFS then return end
    local e = Entry(spellId)
    local fs = d.titleFS
    if not e or not e.showTitle then fs:Hide(); return end
    fs:SetFont(ns.ResolveFontPath(e.titleFontPath, e.titleFontKey), e.titleFontSize or 16, e.titleOutline or "OUTLINE")
    local c = e.titleColor or { r = 1, g = 1, b = 1, a = 1 }
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
    AnchorFS(fs, d.icon.GetFrame(), e.titleAnchor or "TOP", e.titleOffsetX, e.titleOffsetY)
    fs:SetText(e.titleText or "")
    fs:Show()
end

local function ApplyStack(spellId)
    local d = live[spellId]
    if not d or not d.stackFS then return end
    local e = Entry(spellId)
    local fs = d.stackFS
    if not e or not e.showStack then fs:Hide(); return end
    fs:SetFont(ns.ResolveFontPath(e.stackFontPath, e.stackFontKey), e.stackFontSize or 12, e.stackOutline or "OUTLINE")
    local c = e.stackColor or { r = 1, g = 1, b = 1, a = 1 }
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
    AnchorFS(fs, d.icon.GetFrame(), e.stackAnchor or "BOTTOMRIGHT", e.stackOffsetX, e.stackOffsetY)
    local cur, maxc = GetCharges(spellId)
    if cur and maxc and maxc > 1 and (cur > 0 or e.showAtZero) then
        fs:SetText(tostring(cur)); fs:Show()
    else
        fs:Hide()
    end
end

-- ── Per-icon per-tick sync (identical engine to the custom / defensive icons) ──
local function ApplyOne(spellId)
    local d = live[spellId]
    if not d then return end
    local e = Entry(spellId)
    -- Inert when un-adopted (entry gone), the Cooldown Manager is off, or the spell is
    -- no longer known (e.g. respec); the native frame is then shown by Blizzard again.
    if not e or not ns.IsCDMEnabled() or not SpellKnown(spellId) then
        d.icon.Hide(); return
    end

    d.icon.SetIcon(SpellTexture(spellId))
    d.icon.ApplySize()

    local cur, maxc, cdStart, cdDur = GetCharges(spellId)
    local hideForZero = cur and maxc and maxc > 1 and cur == 0 and not e.showAtZero
    if e.showIcon ~= false and not hideForZero then
        d.icon.Show()
        ApplyStack(spellId)
    else
        d.icon.Hide()
    end

    -- 1) Green "active" timer while a positive self-buff of the same spell is up.
    local foundBuff = false
    local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(spellId)
    if aura and ns.AuraTimerReadable and ns.AuraTimerReadable(spellId) then
        foundBuff = true
        if ns.LearnAuraDuration then ns.LearnAuraDuration(spellId, aura.duration) end
        d.icon.SetTimer(aura.expirationTime, aura.duration, GREEN)
        d.icon.HideCheck()
    elseif d.lastUseAt and UnitAffectingCombat("player") then
        local dur = ns.GetAuraDuration and ns.GetAuraDuration(spellId)
        if dur and dur > 0 and GetTime() < d.lastUseAt + dur then
            foundBuff = true
            d.icon.SetTimer(d.lastUseAt + dur, dur, GREEN)
            d.icon.HideCheck()
        end
    end
    if foundBuff then return end

    -- 2) Multi-charge: show the recharging charge's timer even while a charge remains.
    if maxc and maxc > 1 and cur and cur < maxc and cdStart and not issecretvalue(cdStart)
        and cdStart > 0 and cdDur and cdDur > 0 then
        d.learnedCd   = cdDur
        d.hasCooldown = true
        d.lastExpiry  = cdStart + cdDur
        d.icon.SetTimer(cdStart + cdDur, cdDur)
        d.icon.HideCheck()
        return
    end

    -- 3) Regular spell cooldown.
    local start, duration = GetCooldown(spellId)
    if issecretvalue(start) or issecretvalue(duration) then
        if d.lastUseAt and d.learnedCd and GetTime() < d.lastUseAt + d.learnedCd then
            d.hasCooldown = true
            d.lastExpiry  = d.lastUseAt + d.learnedCd
            d.icon.SetTimer(d.lastExpiry, d.learnedCd)
        end
    elseif start and start > 0 and duration and duration > 2.5 then
        d.learnedCd  = duration
        d.hasCooldown = true
        d.lastExpiry  = start + duration
        d.icon.SetTimer(start + duration, duration)
    elseif duration and duration > 0 then
        -- GCD blip: keep state.
    else
        if d.hasCooldown then
            d.hasCooldown = false
            local completed = d.lastExpiry and GetTime() >= d.lastExpiry - (ns.READY_EPSILON or 1.5)
            if completed and not (ns.RecentlyZoned and ns.RecentlyZoned()) then
                if e.soundOnReady then PlaySound(spellId, "ready") end
                d.icon.ClearTimer()
                d.icon.BlinkCheck()
            else
                d.icon.ClearTimer()
                d.icon.HideCheck()
            end
        else
            d.icon.ClearTimer()
        end
    end
end

-- ── Icon construction ─────────────────────────────────────────────────────────
local function EnsureIcon(spellId)
    local d = live[spellId]
    if d then return d end
    local icon = ns.ui.CreateTimerIcon({
        name   = FrameName(spellId),
        getCfg = function(key)
            -- A native icon is permanently IN the CDM (no Placement controls), so it always
            -- reports included — this is what makes TimerIcon.ApplyBorder use the dest's CDM
            -- border for it, like every other CDM icon.
            if key == "includeInCdm" then return true end
            local e = Entry(spellId)
            if not e then return DEFAULTS[key] end
            if e[key] ~= nil then return e[key] end
            return DEFAULTS[key]
        end,
        onDragStop = function(x, y)
            local e = Entry(spellId)
            if e then e.posX = x; e.posY = y end
        end,
    })
    icon.onExpire = function() end
    d = { icon = icon }
    local frame = icon.GetFrame()
    d.titleFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    d.stackFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    live[spellId] = d
    return d
end

local function BuildIcon(spellId)
    local d = EnsureIcon(spellId)
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(spellId)
    ApplyOne(spellId)
    return d
end

function NC.ApplyIcon(spellId)
    local d = live[spellId]
    if not d then BuildIcon(spellId); return end
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(spellId)
    ApplyOne(spellId)
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
end

function NC.Get(spellId, key)
    local e = Entry(spellId)
    if e and e[key] ~= nil then return e[key] end
    return DEFAULTS[key]
end
function NC.Set(spellId, key, val)
    local e = Entry(spellId)
    if not e then return end
    e[key] = val
    NC.ApplyIcon(spellId)
end
function NC.SetUnlocked(spellId, v)
    local d = live[spellId]
    if d then d.icon.SetUnlocked(v) end
end
function NC.IsUnlocked(spellId)
    local d = live[spellId]
    return d and d.icon.IsUnlocked() or false
end

-- ── Adopt / un-adopt ──────────────────────────────────────────────────────────
-- Adopt a native: create its config entry (seeding dest/row), build the icon. The
-- native frame is hidden by ns.CDMAnchor on the next layout pass.
function NC.Adopt(spellId, dest, row)
    if not spellId then return end
    local e = EnsureEntry(spellId, { dest = dest, row = row })
    if not e then return end   -- profile not ready yet: don't build an orphaned icon
    BuildIcon(spellId)
    -- Hide the native NOW (synchronously) so it doesn't briefly show alongside our icon
    -- in the ~0.1s before the throttled layout pass would otherwise hide it.
    if ns.CDMAnchor and ns.CDMAnchor.HideNativeForSpell then ns.CDMAnchor.HideNativeForSpell(spellId) end
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
end

-- Un-adopt: delete the entry + hide our icon; the native frame returns next layout.
function NC.Remove(spellId)
    local s = Store()
    if s then s[spellId] = nil end
    local d = live[spellId]
    if d then d.icon.Hide(); d.icon.ClearTimer() end
    if NC.CloseEditorFor then NC.CloseEditorFor(spellId) end
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
end

function NC.ConfirmRemove(spellId)
    ns.ui.ShowConfirm({
        title    = L["Stop customizing this native icon?"],
        text     = L["The native cooldown icon returns to its default Blizzard look."],
        icon     = SpellTexture(spellId),
        name     = NC.SpellName(spellId),
        onAccept = function() NC.Remove(spellId) end,
    })
end

-- All adopted spells for a dest, as { spellId, texture, name, row } (for the cadre, so
-- adopted icons stay listed even though their native frame is hidden).
function NC.AdoptedForDest(dest)
    local s = Store(); if not s then return {} end
    local out = {}
    for spellId, e in pairs(s) do
        -- Every adopted spell of this dest stays listed (even if freed from the CDM), so
        -- it remains editable / un-adoptable from the cadre rather than vanishing.
        if (e.cdmDest or "essential") == dest then
            out[#out + 1] = { spellId = spellId, texture = SpellTexture(spellId),
                              name = NC.SpellName(spellId), row = e.cdmRow or 1 }
        end
    end
    return out
end

-- ── Public sync ───────────────────────────────────────────────────────────────
function NC.UpdateAll()
    local s = Store(); if not s then return end
    for spellId in pairs(s) do ApplyOne(spellId) end
end

-- (Re)build every adopted icon; hide any live icon whose entry was removed.
function NC.Rebuild()
    local s = Store() or {}
    for spellId in pairs(s) do BuildIcon(spellId) end
    for spellId, d in pairs(live) do
        if not s[spellId] then d.icon.Hide() end
    end
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
end

-- ── Events ────────────────────────────────────────────────────────────────────
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
f:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local d = live[spellId]
        if d then
            d.lastUseAt = GetTime()
            local e = Entry(spellId)
            if e and e.soundOnUse then PlaySound(spellId, "use") end
        end
    else
        NC.UpdateAll()
    end
end)

local ticker = CreateFrame("Frame")
local accum = 0
ticker:SetScript("OnUpdate", function(_, dt)
    accum = accum + dt
    if accum < 0.5 then return end
    accum = accum - 0.5   -- preserve overshoot so the interval doesn't drift slow
    NC.UpdateAll()
end)

ns.RegisterReloadHook(function() NC.Rebuild() end)

local initNC = CreateFrame("Frame")
initNC:RegisterEvent("PLAYER_LOGIN")
initNC:SetScript("OnEvent", function(self)
    NC.Rebuild()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
