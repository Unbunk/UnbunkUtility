-- Modules/CustomCDM/Core/CustomCDM.lua
-- User-defined "custom" Cooldown Manager icons: an arbitrary spell (added by ID or name
-- from a reorder cadre's "+" tile) rendered as a fully-configurable ns.ui TimerIcon — it
-- auto-registers with ns.CDMAnchor, shows the spell's cooldown swipe + countdown with
-- user-defined urgency tiers, an optional title and stack (charge) count each anchored
-- around the icon, a configurable border, and optional use / ready sound alerts. Each
-- icon is driven by a per-icon config entry in the profile; the reorder strip exposes a
-- delete (X) and an edit (pen, opens the full editor window) control on each one.
--
-- Lifecycle notes:
--   * Frames can't be destroyed in WoW, so a removed icon is hidden + its config entry
--     deleted; its (now-orphan) descriptor stays registered but reports includeInCdm
--     =false and IsShown()=false, so it is excluded from every layout/bucket. The live
--     frame is kept (one per id) and reused if that id ever resolves again.
--   * getCfg reads the LIVE profile entry every call, so a profile switch (reload hook)
--     just re-points each id at the new profile's entry.

local ADDON, ns = ...
ns.CustomCDM = ns.CustomCDM or {}
local CC = ns.CustomCDM
local L = ns.L

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(CC)
AceTimer:Embed(CC)

-- In combat the player's own spell cooldown fields can come back as "secret values":
-- reading/comparing one taints + errors. Guarded so a client without the system loads.
local issecretvalue = issecretvalue or function() return false end

local FALLBACK_ICON = 134400  -- question mark, shown when the spell texture can't resolve
local GREEN = { r = 0, g = 1, b = 0 }  -- "active buff up" timer colour (shared, read-only)

-- Per-icon config defaults. Visual blocks mirror the potion tracker; the title block
-- is healthstone-styled with the text left empty + hidden by default. Timer urgency
-- tiers are seeded separately (SeedTiers) so editing the list is never "merged back".
local ICON_DEFAULTS = {
    spellId        = 0,
    entryKind      = "spell",   -- "spell" | "item" | "buff": what this icon tracks (item = on-use trinket/potion;
                                -- buff = a cast-triggered, fixed-duration drawn buff swipe — always a free icon)
    itemId         = 0,         -- the tracked item id when entryKind == "item"
    duration       = 30,        -- buff kind: the fixed swipe length (s), armed on the player's own cast
    cdmBuffGroup   = 1,         -- buff kind + in CDM: which Buff-groups group the mirror lands in
    showIcon       = true,   -- off = keep the sound alerts but hide the icon
    includeInCdm   = true,
    cdmDest        = "belowPlayer",
    cdmAtEnd       = false,
    cdmRow         = 1,
    posX           = -300,
    posY           = -300,
    iconWidth      = 30,
    iconHeight     = 30,
    -- Border (from potions).
    borderEnabled  = true,
    borderColor    = { r = 0, g = 0, b = 0, a = 1 },
    borderSize     = 1,
    -- Glow (buff kind only): a coloured pixel glow shown while the buff is active. Off by default;
    -- the colour defaults to F5FF00 even while disabled (consistent across every Glow cadre).
    glowEnabled    = false,
    glowColor      = { r = 0.96, g = 1, b = 0, a = 1 },   -- F5FF00
    -- Timer text (from potions) + a show toggle. Tiers live in `timerTiers` (seeded).
    showTimer      = true,
    timerFontKey   = "Fira Mono",
    timerFontPath  = nil,
    timerFontSize  = 14,
    timerOutline   = "OUTLINE",
    timerColor     = { r = 1, g = 1, b = 1, a = 1 },
    -- Title (healthstone-styled, empty + hidden by default).
    showTitle      = false,
    titleText      = "",
    titleAnchor    = "TOP",
    titleOffsetX   = 0,      -- manual nudge from the anchor
    titleOffsetY   = 0,
    titleFontKey   = "Fira Mono",
    titleFontPath  = nil,
    titleFontSize  = 16,
    titleOutline   = "OUTLINE",
    titleColor     = { r = 1, g = 1, b = 1, a = 1 },
    -- Stacks = spell charges (from potions) + a configurable anchor.
    showStack      = true,
    showAtZero     = true,
    stackAnchor    = "BOTTOMRIGHT",
    stackOffsetX   = 0,      -- manual nudge from the anchor
    stackOffsetY   = 0,
    stackFontKey   = "Fira Mono",
    stackFontPath  = nil,
    stackFontSize  = 12,
    stackOutline   = "OUTLINE",
    stackColor     = { r = 1, g = 1, b = 1, a = 1 },
    -- Sound alerts (off + no sound by default).
    soundOnUse     = false,
    soundKeyUse    = nil,
    soundPathUse   = nil,
    soundOnReady   = false,
    soundKeyReady  = nil,
    soundPathReady = nil,
}

-- Default urgency tiers (match the built-in tracker behaviour: yellow @15s, red @5s).
-- Seeded into a fresh entry; never merged, so deleting/editing tiers sticks.
local DEFAULT_TIERS = {
    { at = 15, scale = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { at = 5,  scale = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
local function SeedTiers(e)
    if e and e.timerTiers == nil then e.timerTiers = ns.DeepCopy(DEFAULT_TIERS) end
end

-- Buff free look uses the SHARED CDMGroups Timer/Title/Stacks sections (same as the Override cadres),
-- so a buff entry stores that schema (timerPos / timerThresholds(+Enabled) / titlePos / stackPos …) with
-- buff-specific defaults that differ from the spell/item ICON_DEFAULTS. Applied force=true on creation
-- (override the ICON_DEFAULTS just merged) and force=false on build (backfill only the missing keys).
local BUFF_DEFAULTS = {
    posX = 0, posY = 0,
    iconWidth = 36, iconHeight = 36,
    timerFontSize = 12, timerPos = "CENTER", timerThresholdsEnabled = false,
    timerColor = { r = 0, g = 1, b = 0, a = 1 },   -- green by default (the "buff up" look), now configurable
    titlePos = "TOP", titleOffX = 0, titleOffY = 0,
    stackFontSize = 8, stackPos = "BOTTOMRIGHT", stackOffX = 2, stackOffY = -2,
    onlyWhenActive = true,   -- a buff free icon shows only while the buff is up (toggle in the editor)
    -- buff glow = "while active" (SetColorGlow), off by default (glowEnabled/glowColor from ICON_DEFAULTS).
}
-- Spell/Item free look (same shared CDMGroups Timer/Title/Stacks sections as buffs, different defaults +
-- a glow-ON-PROC with a type). glowEnabled on by default; glow color F5FF00; thresholds ON by default.
local SPELL_DEFAULTS = {
    posX = 0, posY = 0,
    iconWidth = 44, iconHeight = 44,
    timerFontSize = 14, timerPos = "CENTER", timerThresholdsEnabled = true,
    titlePos = "TOP", titleOffX = 0, titleOffY = 0, showTitle = false,
    stackFontSize = 10, stackPos = "BOTTOMRIGHT", stackOffX = 2, stackOffY = -2,
    glowEnabled = true, glowType = "pixel", glowColor = { r = 0.96, g = 1, b = 0, a = 1 },  -- F5FF00
}
-- The 2 default urgency thresholds, in the CDMGroups {time,size,color} shape (yellow @15s, red @5s).
local DEFAULT_FREE_THRESHOLDS = {
    { time = 15, size = 1.2,  color = { r = 1, g = 0.82, b = 0, a = 1 } },
    { time = 5,  size = 1.45, color = { r = 1, g = 0,    b = 0, a = 1 } },
}
-- Seed the free-look defaults + schema for a custom icon by kind. force=true on creation (override the
-- ICON_DEFAULTS just merged); force=false on build (backfill missing only). On the backfill path it also
-- carries the legacy CC free schema (titleAnchor/stackAnchor/timerTiers) → the shared CDMGroups schema
-- (titlePos/stackPos/timerThresholds) so a pre-existing icon keeps its customised look.
local function SeedFreeLookDefaults(e, force)
    if not e then return end
    if not force then
        if e.titlePos == nil and e.titleAnchor ~= nil then
            e.titlePos = e.titleAnchor; e.titleOffX = e.titleOffsetX; e.titleOffY = e.titleOffsetY
        end
        if e.stackPos == nil and e.stackAnchor ~= nil then
            e.stackPos = e.stackAnchor; e.stackOffX = e.stackOffsetX; e.stackOffY = e.stackOffsetY
        end
        if e.timerThresholds == nil and type(e.timerTiers) == "table" then
            local t = {}
            for _, x in ipairs(e.timerTiers) do t[#t + 1] = { time = x.at, size = x.scale, color = x.color } end
            e.timerThresholds = t
            if e.timerThresholdsEnabled == nil then e.timerThresholdsEnabled = true end
        end
    end
    local d = (e.entryKind == "buff") and BUFF_DEFAULTS or SPELL_DEFAULTS
    for k, v in pairs(d) do
        if force or e[k] == nil then e[k] = (type(v) == "table") and ns.DeepCopy(v) or v end
    end
    if e.timerThresholds == nil then e.timerThresholds = ns.DeepCopy(DEFAULT_FREE_THRESHOLDS) end
end
CC.SeedFreeLookDefaults = SeedFreeLookDefaults

-- live[id] = { icon, titleFS, stackFS, lastUseAt, learnedCd, lastExpiry, hasCooldown }
local live = {}

local function FrameName(id) return "UnbunkUtilityCustomCDM" .. id end
CC.FrameName = FrameName   -- the editor's CDM override cadres key by this frame name

-- ── Buff <-> BuffGroups bridge predicates ─────────────────────────────────────
-- A buff-kind icon can be MIRRORED into the Buffs viewer (drawn there by BuffGroups). These two
-- helpers decide whether that mirror is actually rendering the buff right now; if not, the buff's
-- own free TimerIcon must render it so it never vanishes (BuffGroups off, or no mirror created).
local function BuffGroupsEnabled()
    local BG = ns.BuffGroups
    if not BG then return false end
    if BG.Enabled then return BG.Enabled() and true or false end
    return true
end
-- True only when the buff is in-CDM, BuffGroups is enabled to draw it, a mirror custom exists for
-- its spell, AND that mirror is in a VISIBLE group — i.e. the viewer is actually showing it, so the
-- free icon should stay hidden. A mirror parked in "Unused" (group 0, e.g. dragged there or its
-- group deleted) renders nowhere, so the free icon must take over instead of vanishing.
local function BuffMirrored(e)
    if not (e and e.entryKind == "buff" and ns.CDMIncludedVal(e.includeInCdm)
            and e.spellId and e.spellId ~= 0) then
        return false
    end
    local BG = ns.BuffGroups
    if not (BuffGroupsEnabled() and BG and BG.IsCustom and BG.IsCustom(e.spellId)) then return false end
    return (not BG.GroupOf) or BG.GroupOf(e.spellId) ~= 0
end

-- The profile store: { nextId = N, icons = { [id] = entry } }. Created lazily.
local function Store()
    if not (ns.db and ns.db.profile) then return nil end
    local s = ns.db.profile.cdmCustom
    if not s then s = { nextId = 1, icons = {} }; ns.db.profile.cdmCustom = s end
    s.icons = s.icons or {}
    -- A store that arrived via profile import / hand-edit could hold icons but no
    -- nextId; derive it from the highest existing id so the next Add can never
    -- overwrite an existing entry (a flat "or 1" would still collide on icons[1]).
    if not s.nextId then
        local maxId = 0
        for id in pairs(s.icons) do
            if type(id) == "number" and id > maxId then maxId = id end
        end
        s.nextId = maxId + 1
    end
    return s
end

local function Entry(id)
    local s = Store()
    return s and s.icons[id]
end

-- An in-progress "draft" icon: created by the "+" but not committed until the editor's
-- "Add Icon" button. Held outside the store + not rendered until committed.
local _draft   -- { id = , entry = } or nil

-- Like Entry but resolves the draft too — used by the editor's accessors. Rendering
-- keeps using Entry (a draft is never built/listed until committed).
local function EntryById(id)
    if _draft and _draft.id == id then return _draft.entry end
    return Entry(id)
end
function CC.IsDraft(id) return _draft ~= nil and _draft.id == id end

-- ── Custom-icon identity (used by the reorder strip to show its X / pen) ──────
function CC.IsCustom(name)
    return type(name) == "string" and name:match("^UnbunkUtilityCustomCDM%d+$") ~= nil
end
function CC.IdFromFrameName(name)
    local idStr = type(name) == "string" and name:match("^UnbunkUtilityCustomCDM(%d+)$")
    return idStr and tonumber(idStr) or nil
end

-- ── Spell helpers (cross-version) ─────────────────────────────────────────────
local function SpellTexture(spellId)
    if not spellId or spellId == 0 then return FALLBACK_ICON end
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
    return tex or FALLBACK_ICON
end

local function SpellValid(spellId)
    if not spellId or spellId <= 0 then return false end
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(spellId) ~= nil end
    if GetSpellInfo then return GetSpellInfo(spellId) ~= nil end
    return true
end

-- Resolve a user input (a numeric spell ID, or a spell name) to a spell ID, or nil.
local function ResolveSpell(value)
    if type(value) ~= "string" then value = tostring(value or "") end
    value = value:match("^%s*(.-)%s*$")        -- trim
    if value == "" then return nil end
    local asNum = tonumber(value)
    if asNum then
        return SpellValid(asNum) and asNum or nil
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(value)  -- accepts a spell name
        if info and info.spellID then return info.spellID end
    end
    return nil
end
CC.ResolveSpell = ResolveSpell

-- ── Item helpers (entryKind == "item": on-use trinkets / potions) ──────────────
local function ItemValid(itemId)
    if not itemId or itemId <= 0 then return false end
    return (C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemId)) ~= nil
end
CC.ItemValid = ItemValid

-- Resolve a user input (numeric itemID, item name, or item link) to an itemID, or nil.
local function ResolveItem(value)
    if type(value) ~= "string" then value = tostring(value or "") end
    value = value:match("^%s*(.-)%s*$")        -- trim
    if value == "" then return nil end
    local itemId = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(value)  -- id / name / link
    if itemId then return itemId end
    local asNum = tonumber(value)
    return (asNum and ItemValid(asNum)) and asNum or nil
end
CC.ResolveItem = ResolveItem

local function ItemTexture(itemId)
    if not itemId or itemId == 0 then return FALLBACK_ICON end
    local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId)
    return tex or FALLBACK_ICON
end

local function ItemName(itemId)
    if not itemId or itemId == 0 then return "" end
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemId)
    return n or ("[" .. tostring(itemId) .. "]")
end

local function ItemCooldown(itemId)
    if C_Container and C_Container.GetItemCooldown then
        local start, duration = C_Container.GetItemCooldown(itemId)
        return start or 0, duration or 0
    end
    if GetItemCooldown then local s, du = GetItemCooldown(itemId); return s or 0, du or 0 end
    return 0, 0
end

-- Entry-aware icon texture (spell or item), used by the renderer + the editor.
local function IconTextureForEntry(e)
    if e and e.entryKind == "item" then return ItemTexture(e.itemId) end
    return SpellTexture(e and e.spellId)
end
function CC.IconTexture(id) return IconTextureForEntry(EntryById(id)) end

function CC.SpellName(id)
    local e = EntryById(id)
    if e and e.entryKind == "item" then return ItemName(e.itemId) end
    local sid = e and e.spellId
    if not sid or sid == 0 then return "" end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
    return (info and info.name) or ("[" .. tostring(sid) .. "]")
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

-- Current / max charges for a charge-based spell (plus the recharging charge's
-- cooldown start + duration), else nil.
local function GetCharges(spellId)
    if not spellId or spellId == 0 then return nil end
    if C_Spell and C_Spell.GetSpellCharges then
        local ci = C_Spell.GetSpellCharges(spellId)
        if ci then
            -- In combat these come back as SECRET values that cannot be compared (==/<)
            -- without erroring. Drop any secret field to nil so the truthiness guards
            -- downstream (cur and …, maxc and …) simply skip the charge logic in combat.
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

local function PlaySound(id, which)
    local e = Entry(id)
    if not e then return end
    if which == "use" then
        ns.PlaySoundFromCfg(e, "soundPathUse", "soundKeyUse")
    elseif which == "ready" then
        ns.PlaySoundFromCfg(e, "soundPathReady", "soundKeyReady")
    end
end
-- Exposed so the editor's sound "test" buttons preview the chosen sound (the picker
-- otherwise falls back to HealerRange's sound when no onTest is supplied).
function CC.TestSound(id, which) PlaySound(id, which) end

-- ── Title + stack FontStrings (anchored around the icon) ──────────────────────
-- Anchor placement is centralised in ns (Core/Shared.lua): the title/stack can sit
-- centred, just outside an edge, or inset into one of the four corners.
local AnchorFS = ns.AnchorFS

local function ApplyTitle(id)
    local d = live[id]
    if not d or not d.titleFS then return end
    local e = Entry(id)
    local fs = d.titleFS
    if not e or not e.showTitle then fs:Hide(); return end
    -- In CDM (migrated): TimerIcon.ApplyDestExtras draws the title from the per-icon override store, so
    -- suppress our own draw — the Override-cadre values govern the in-CDM look (mirrors the trackers).
    -- (A buff reads includeInCdm=false via getCfg, so CDMActive is false and this never fires for buffs.)
    if ns.TrackerSuppressOwnExtras and ns.TrackerSuppressOwnExtras(d.icon, FrameName(id), e.cdmDest, ns.DefaultTrackerTimerSeed) then
        fs:Hide(); return
    end
    fs:SetFont(ns.ResolveFontPath(e.titleFontPath, e.titleFontKey), e.titleFontSize or 16, e.titleOutline or "OUTLINE")
    local c = e.titleColor or { r = 1, g = 1, b = 1, a = 1 }
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
    -- Free icons own-draw title from the shared CDMGroups schema (titlePos/titleOffX/Y) — both kinds now
    -- use the shared Title section; legacy titleAnchor is migrated to titlePos by SeedFreeLookDefaults.
    AnchorFS(fs, d.icon.GetFrame(), e.titlePos or "TOP", e.titleOffX, e.titleOffY)
    fs:SetText(e.titleText or "")
    fs:Show()
end

-- ApplyStack runs HOT (every live icon, every 0.5s tick + each coalesced cooldown update), so font/colour/
-- anchor — all static between edits — are applied only when their signature changes (cached on d.stackLook);
-- a steady-state tick then does just SetText + Show/Hide. The spell path passes haveCharges=true with the
-- cur/maxc it already fetched in ApplyOne (so we drop a duplicate GetSpellCharges even when the spell has no
-- charges → both nil); the item/buff paths omit it, and the buff path falls back to GetCharges (item kind
-- never reaches the charge branch) so their behaviour is unchanged.
local function ApplyStack(id, curIn, maxcIn, haveCharges)
    local d = live[id]
    if not d or not d.stackFS then return end
    local e = Entry(id)
    local fs = d.stackFS
    if not e or not e.showStack then fs:Hide(); return end
    -- In CDM (migrated): TimerIcon draws stacks from the per-icon override; suppress our own (see ApplyTitle).
    if ns.TrackerSuppressOwnExtras and ns.TrackerSuppressOwnExtras(d.icon, FrameName(id), e.cdmDest, ns.DefaultTrackerTimerSeed) then
        fs:Hide(); return
    end
    -- Re-apply font/colour/anchor only on a real change: the look signature captures every font/colour/
    -- anchor input, so an editor edit shifts it and the next call re-applies, while steady-state ticks skip it.
    local path = ns.ResolveFontPath(e.stackFontPath, e.stackFontKey)
    local size = e.stackFontSize or 12
    local outline = e.stackOutline or "OUTLINE"
    local c = e.stackColor or { r = 1, g = 1, b = 1, a = 1 }
    local pos = e.stackPos or "BOTTOMRIGHT"
    local sig = path .. "|" .. size .. "|" .. outline .. "|" .. (c.r or 1) .. "," .. (c.g or 1) .. ","
        .. (c.b or 1) .. "," .. (c.a or 1) .. "|" .. pos .. "|" .. (e.stackOffX or 0) .. "," .. (e.stackOffY or 0)
    if d.stackLook ~= sig then
        fs:SetFont(path, size, outline)
        fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
        AnchorFS(fs, d.icon.GetFrame(), pos, e.stackOffX, e.stackOffY)
        d.stackLook = sig
    end
    -- Item kind: show the bag count (how many of the item you carry); spell kind: the recharging charges.
    if e.entryKind == "item" then
        local n = e.itemId and e.itemId ~= 0 and C_Item and C_Item.GetItemCount and C_Item.GetItemCount(e.itemId)
        if n and n > 0 then fs:SetText(tostring(n)); fs:Show() else fs:Hide() end
        return
    end
    local cur, maxc = curIn, maxcIn
    if not haveCharges then cur, maxc = GetCharges(e.spellId) end
    if cur and maxc and maxc > 1 and (cur > 0 or e.showAtZero) then
        fs:SetText(tostring(cur))
        fs:Show()
    else
        fs:Hide()   -- no charges on this spell (or 0 + show-at-0 off) -> nothing to show
    end
end

-- ── One icon's per-tick sync (texture + charges visibility + cooldown swipe) ──
local function ApplyOne(id)
    local d = live[id]
    if not d then return end
    -- Removed: the frame is kept (reused if this id ever resolves again) but stays inert. Bail BEFORE the
    -- Entry() lookup so UpdateAll's per-tick sweep doesn't keep paying for a dead icon (the live[] entry
    -- lingers by design, so without this flag every tick would re-look-up + Hide it forever).
    if d.removed then return end
    local e = Entry(id)
    if not e then d.icon.Hide(); return end   -- removed / not in this profile -> inert

    d.icon.SetIcon(IconTextureForEntry(e))
    d.icon.ApplySize()

    -- Buff kind: a cast-triggered, fixed-duration swipe (no real cooldown to read). The player's own cast
    -- arms `d.buffExpiry` (the UNIT_SPELLCAST_SUCCEEDED handler below); here we just render the green
    -- "buff up" countdown until it elapses, mirroring the spell path's active-buff look. No charges/stacks.
    if e.entryKind == "buff" then
        -- Mirrored into the Buffs viewer (BuffGroups draws it there): keep our own free icon inert.
        -- Only when the mirror is actually rendering it — if BuffGroups is disabled or no mirror was
        -- created, fall through and render the free swipe so the buff never disappears.
        if BuffMirrored(e) then
            if d.icon.SetColorGlow then d.icon.SetColorGlow(false) end
            d.icon.Hide(); return
        end
        local dur    = tonumber(e.duration) or 0
        local active = d.buffExpiry and dur > 0 and GetTime() < d.buffExpiry
        -- "Only show when buff is active" (on by default): hide the free icon while the buff isn't up.
        -- (onExpire re-runs ApplyOne when the swipe elapses, so it hides itself then.) Always show while
        -- unlocked so the icon can still be positioned in the editor.
        local show = e.showIcon ~= false and (active or e.onlyWhenActive == false or d.icon.IsUnlocked())
        if show then d.icon.Show(); ApplyStack(id) else d.icon.Hide() end
        if active then
            -- keepLit (not a locked GREEN): the icon stays lit while the swipe runs, and the timer text
            -- follows the configured timerColor + urgency thresholds from the Timer cadre (green is just
            -- the default timerColor for a buff).
            d.icon.SetTimer(d.buffExpiry, dur, nil, true)
            d.icon.HideCheck()
        else
            d.buffExpiry = nil
            d.icon.ClearTimer()
        end
        -- Glow while the buff is active (and the icon is shown).
        if d.icon.SetColorGlow then
            local on = active and e.showIcon ~= false and e.glowEnabled == true
            local c  = e.glowColor or { r = 0.96, g = 1, b = 0, a = 1 }
            d.icon.SetColorGlow(on, { c.r or 1, c.g or 1, c.b or 1, c.a or 1 })
        end
        return
    end

    -- Item kind: a separate, simpler path — the on-use item cooldown swipe + bag count, no aura / charge
    -- logic. Item cooldowns are NOT secret in combat, so no estimate is needed. The whole spell path below
    -- is left untouched, so spell icons behave exactly as before.
    if e.entryKind == "item" then
        if e.showIcon ~= false then d.icon.Show(); ApplyStack(id) else d.icon.Hide() end
        local iid = e.itemId
        if not iid or iid == 0 then d.icon.ClearTimer(); return end
        local start, duration = ItemCooldown(iid)
        if start and start > 0 and duration and duration > 2.5 then
            d.learnedCd = duration; d.hasCooldown = true; d.lastExpiry = start + duration
            d.icon.SetTimer(start + duration, duration)
        elseif d.hasCooldown then
            d.hasCooldown = false
            local completed = d.lastExpiry and GetTime() >= d.lastExpiry - (ns.READY_EPSILON or 0.3)
            if completed and not (ns.RecentlyZoned and ns.RecentlyZoned()) then
                if e.soundOnReady then PlaySound(id, "ready") end
                d.icon.ClearTimer(); d.icon.BlinkCheck()
            else
                d.icon.ClearTimer(); d.icon.HideCheck()
            end
        else
            d.icon.ClearTimer()
        end
        return
    end

    -- Icon visibility = "Show icon" + the charge "show at 0" rule. The cooldown logic
    -- below still runs when hidden, so a sound-only (Show icon off) icon still alerts.
    local cur, maxc, cdStart, cdDur = GetCharges(e.spellId)
    local hideForZero = cur and maxc and maxc > 1 and cur == 0 and not e.showAtZero
    if e.showIcon ~= false and not hideForZero then
        d.icon.Show()
        ApplyStack(id, cur, maxc, true)   -- reuse the charges fetched just above (no second GetSpellCharges)
    else
        d.icon.Hide()
    end

    local spellId = e.spellId
    if not spellId or spellId == 0 then d.icon.ClearTimer(); return end

    -- 1) Green "active" timer while a positive self-buff (same spellId) is up — exactly
    -- when readable (out of combat / never-secret), else an in-combat estimate from the
    -- recorded cast + the learned aura length.
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

    -- 3) Regular spell cooldown (non-charge spells, or a fully-charged one).
    local start, duration = GetCooldown(spellId)
    if issecretvalue(start) or issecretvalue(duration) then
        -- In combat the timing is secret: estimate from the recorded cast + learned length.
        if d.lastUseAt and d.learnedCd and GetTime() < d.lastUseAt + d.learnedCd then
            d.hasCooldown = true
            d.lastExpiry  = d.lastUseAt + d.learnedCd
            d.icon.SetTimer(d.lastExpiry, d.learnedCd)
        end
    elseif start and start > 0 and duration and duration > 2.5 then
        d.learnedCd  = duration                 -- remember the real length for the estimate
        d.hasCooldown = true
        d.lastExpiry  = start + duration
        d.icon.SetTimer(start + duration, duration)
    elseif duration and duration > 0 then
        -- GCD blip / not-yet-populated cooldown: indeterminate, keep state.
    else
        if d.hasCooldown then
            d.hasCooldown = false
            -- Real "ready" only if the cooldown reached its recorded end AND we are
            -- not in the post-loading-screen settle window.
            local completed = d.lastExpiry and GetTime() >= d.lastExpiry - (ns.READY_EPSILON or 0.3)
            if completed and not (ns.RecentlyZoned and ns.RecentlyZoned()) then
                if e.soundOnReady then PlaySound(id, "ready") end
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

-- Create (once) the TimerIcon + title/stack FontStrings for an id.
local function EnsureIcon(id)
    local d = live[id]
    if d then d.removed = nil; return d end   -- re-Add of a removed id: clear the inert flag so it renders again
    local icon = ns.ui.CreateTimerIcon({
        name   = FrameName(id),
        getCfg = function(key)
            local e = Entry(id)
            if not e then
                -- Removed / not in this profile: report inert so the orphan descriptor
                -- is excluded from every layout/bucket.
                if key == "includeInCdm" then return false end
                return ICON_DEFAULTS[key]
            end
            -- A buff never uses the CDMAnchor bucket layout; its "in CDM" state is the BuffGroups
            -- mirror (see SyncBuffBridge), so it always reads as free here (placed by posX/posY or hidden).
            if key == "includeInCdm" and e.entryKind == "buff" then return false end
            if e[key] ~= nil then return e[key] end
            return ICON_DEFAULTS[key]
        end,
        -- Resolve this icon's item id (item-kind only) so TimerIcon can look up its action-bar keybind
        -- (for "Show Keybinds" / "Show press overlay") and the below-player item name/charges. Spell-kind
        -- icons resolve from spellId instead.
        getItemId = function()
            local e = Entry(id)
            if e and e.entryKind == "item" then return e.itemId end
            return nil
        end,
        -- Lets the CDM reorder strips flip cdmAtEnd (Front <-> End bucket) on a cross-strip drag.
        setCfg = function(key, val)
            local e = Entry(id)
            if e then e[key] = val end
        end,
        onDragStop = function(x, y)
            local e = Entry(id)
            if e then e.posX = x; e.posY = y end
        end,
    })
    -- When a buff's swipe elapses, re-render so "Only show when buff is active" can hide it (spell/item
    -- handle their own cooldown end via UpdateAll, so only the buff path needs this).
    icon.onExpire = function()
        local e = Entry(id)
        if e and e.entryKind == "buff" then ApplyOne(id) end
    end
    d = { icon = icon }
    local frame = icon.GetFrame()
    -- Title / stack drawn over the icon (the timer text lives on a higher child frame,
    -- so a centred title/stack sits under the countdown — acceptable, user-chosen).
    d.titleFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    d.stackFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    live[id] = d
    return d
end

-- ── Buff <-> BuffGroups bridge ────────────────────────────────────────────────
-- A buff-kind icon with "Include in CDM" on is shown in the Buffs viewer, which only the BuffGroups
-- engine can drive (the native buff viewer won't take a cast-triggered buff). So while in-CDM we
-- MIRROR it as a BuffGroups custom buff (Group 1 by default); when it goes free again we drop the
-- mirror. The CustomCDM icon stays the source of truth (spell + duration, always listed in the
-- Free-icons grid for management); BuffGroups owns only the in-viewer rendering. `d.bridgedSid`
-- records the spellId we registered, so a spell change / un-include removes the right mirror.
-- Idempotent (guards on BG.IsCustom): safe to call from build / edit / remove / reload.
local BUFF_BRIDGE_GROUP = 1
local BUFF_BRIDGE_OWNER = "customcdm"   -- marks the BuffGroups custom WE created, so we never touch a user's own
local function SyncBuffBridge(id)
    local BG = ns.BuffGroups
    if not (BG and BG.AddCustom and BG.RemoveCustom and BG.IsCustom) then return end
    local e = Entry(id)
    local d = live[id]
    local function ownedMirror(sid) local def = BG.GetCustom and BG.GetCustom(sid); return def and def.owner == BUFF_BRIDGE_OWNER end
    local prevSid = d and d.bridgedSid
    local want    = e and e.entryKind == "buff" and ns.CDMIncludedVal(e.includeInCdm)
                    and e.spellId and e.spellId ~= 0
    local wantSid = want and e.spellId or nil
    -- Going free, or the spell changed: drop ONLY a mirror WE created (never a user's own
    -- Buff-groups custom of the same spell, which would wipe its group/order/per-icon overrides).
    if prevSid and prevSid ~= wantSid then
        if BG.IsCustom(prevSid) and ownedMirror(prevSid) then
            BG.RemoveCustom(prevSid)
            if BG.ReleaseCustomFrame then BG.ReleaseCustomFrame(prevSid) end
        end
        if d then d.bridgedSid = nil end
    end
    if wantSid then
        if BG.IsCustom(wantSid) then
            if ownedMirror(wantSid) then
                local def = BG.GetCustom and BG.GetCustom(wantSid)
                -- Our mirror: keep its duration in sync. (A swipe already mid-run keeps its old
                -- length until it ends; the new value applies on the next cast — accepted, self-corrects.)
                if def then def.duration = tonumber(e.duration) or def.duration end
                if d then d.bridgedSid = wantSid end
            elseif d then
                d.bridgedSid = nil   -- already a USER's Buff-groups custom: ride on it, never clobber it
            end
        elseif BG.IsNativeTracked and BG.IsNativeTracked(wantSid) then
            -- The spell is a native CDM tracked buff (managed on the Buff groups tab). Mirroring it
            -- would hijack its native slot and erase its per-icon overrides, so refuse — the free icon
            -- keeps rendering (BuffMirrored stays false since no custom is created).
            if d then d.bridgedSid = nil end
        else
            local grp = tonumber(e.cdmBuffGroup)
            if not grp or grp <= 0 then grp = BUFF_BRIDGE_GROUP end
            BG.AddCustom(wantSid, grp, { duration = tonumber(e.duration) or 0, owner = BUFF_BRIDGE_OWNER })
            -- If the free swipe is already mid-run, carry it straight into the viewer (else it shows
            -- nowhere until the next cast re-arms it via BuffGroups' own UNIT_SPELLCAST_SUCCEEDED).
            local dur = tonumber(e.duration) or 0
            if BG.ActivateCustom and d and d.buffExpiry and dur > 0 and GetTime() < d.buffExpiry then
                BG.ActivateCustom(wantSid, d.buffExpiry - dur)
            end
            if d then d.bridgedSid = wantSid end
        end
    end
end
CC.SyncBuffBridge = SyncBuffBridge

-- Is this buff currently RENDERED by the Buffs viewer (the mirror is the live render owner)? The Buff
-- editor gates its Override (in-CDM) vs Free sections on this — not the bare includeInCdm — so a buff
-- parked in "Unused" (which renders free) shows the Free section, not an inert Override section.
function CC.BuffMirrored(id) return BuffMirrored(Entry(id)) end

local function BuildIcon(id)
    local d = EnsureIcon(id)
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(id)
    SyncBuffBridge(id)   -- establish/drop the mirror BEFORE ApplyOne, so its BuffMirrored check is current
    ApplyOne(id)
    -- Position the icon immediately. A free icon anchors itself to posX/posY here; relying on the next
    -- ns.CDMAnchor.RefreshAll() isn't enough because its no-op signature doesn't track free custom icons,
    -- so a mid-session add would otherwise stay UNANCHORED (in the config grid but invisible in game).
    d.icon.ApplyPosition()
    return d
end

-- ── Public API ────────────────────────────────────────────────────────────────
function CC.UpdateAll()
    if next(live) == nil then return end   -- nothing built yet: skip the sweep entirely
    for id in pairs(live) do ApplyOne(id) end
end

-- SPELL_UPDATE_COOLDOWN fires in dense bursts (every GCD, every charge tick). Rather than run a full
-- UpdateAll per event, coalesce them behind a dirty flag drained at ~5Hz: the first event arms a single
-- debounced flush, later events in the window are free. The 0.5s ticker still runs UpdateAll on its own
-- cadence, so this just makes a cooldown change land faster without N sweeps per burst.
local cdDirty = false
local function FlushCooldownDirty()
    cdDirty = false
    CC.UpdateAll()
end
local function MarkCooldownDirty()
    if cdDirty then return end
    cdDirty = true
    if AceTimer and CC.ScheduleTimer then CC:ScheduleTimer(FlushCooldownDirty, 0.2)
    else FlushCooldownDirty() end
end

-- Re-apply every visual of one icon after a config edit (used by the editor).
function CC.ApplyIcon(id)
    local d = live[id]
    if not d then return end
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(id)
    SyncBuffBridge(id)   -- a toggled "Include in CDM" (or new duration/spell) re-syncs the Buffs mirror first
    ApplyOne(id)         -- ...so this re-applies/hides the free icon against the current mirror state
    -- force=true: an editor edit (esp. toggling Include in CDM, which moves the icon between free and a
    -- CDM bucket) must re-lay-out even though the no-op signature can't see this custom-icon change.
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
end

function CC.GetEntry(id) return EntryById(id) end

-- The custom icons NOT included in the Cooldown Manager (free-positioned), in the
-- order they were added (ascending id). Each item id is the icon's FRAME NAME so the
-- "Free icons" strip's edit/delete controls round-trip through IdFromFrameName.
function CC.GetFreeIcons()
    local s = Store()
    if not s then return {} end
    local ids = {}
    for id, e in pairs(s.icons) do
        -- Free icons, plus any whose icon is hidden ("Show icon" off) so they stay manageable
        -- (they're absent from the CDM cadres' shown-only strips), plus EVERY buff-kind icon — a
        -- buff stays in this grid for management even when "in CDM" (mirrored to the Buffs viewer),
        -- because the Buff groups tab has no pen back to the Buff editor.
        if e.entryKind == "buff" or not e.includeInCdm or not e.showIcon then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do
        local e = s.icons[id]
        -- `kind` lets the Free-icons strip's pen route to the right editor (buff -> Buff editor,
        -- spell/item -> the CustomCDM editor) — though CC.PromptEdit already routes by kind itself.
        out[#out + 1] = { id = FrameName(id), texture = IconTextureForEntry(e), custom = true, kind = e.entryKind }
    end
    return out
end

-- Free-placement drag lock (used by the editor's position control for a free icon).
function CC.SetUnlocked(id, v)
    local d = live[id]
    if d then d.icon.SetUnlocked(v) end
end
function CC.IsUnlocked(id)
    local d = live[id]
    return d and d.icon.IsUnlocked() or false
end

-- Read a config value with the per-icon default fallback (for the editor's getters).
function CC.Get(id, key)
    local e = EntryById(id)
    if e and e[key] ~= nil then return e[key] end
    return ICON_DEFAULTS[key]
end

-- Write a config value and re-apply the icon (for the editor's setters). A draft has
-- no live icon yet, so ApplyIcon is a no-op for it until committed.
function CC.Set(id, key, val)
    local e = EntryById(id)
    if not e then return end
    e[key] = val
    CC.ApplyIcon(id)
end

-- Build every custom icon in the current profile (and refresh all live ids, so any
-- left over from a previous profile that the current one lacks get hidden).
-- ── One-time migration: old CDMGroups cast-only customs -> full CustomCDM icons ──
-- The old essential/utility "custom cooldowns" (CDMGroups s.custom[spellId] = {duration,name,icon} — a
-- fixed-duration swipe started at cast) are superseded by CustomCDM icons that track the REAL cooldown.
-- This folds each into a CustomCDM icon (its old dest, includeInCdm) and re-keys its group assignment /
-- order slot / per-icon override from the number spellId to the new icon's frame-name string, so it keeps
-- its exact group + position. The old fixed `duration` is dropped (real cooldown is the upgrade). Per
-- profile, once (flag set up-front so a mid-run error can't double-migrate); the touched CDMGroups
-- sub-tables are deep-copied to a backup first so a bad run is recoverable. Runs from BuildAll
-- (PLAYER_LOGIN + every profile change) — AFTER CDMGroups' own CfgInit reseed, so re-keyed slots survive.
local function MigrateCustoms()
    local p = ns.db and ns.db.profile
    if not p or p.cdmCustomMigratedV1 then return end
    p.cdmCustomMigratedV1 = true   -- set up-front so this never double-runs within a profile
    local groups = p.cdmGroups
    if type(groups) ~= "table" then return end
    local cc = Store(); if not cc then return end
    -- Make sure the next id can't collide with (or overwrite) an existing / hand-edited icon: a stale
    -- low nextId would otherwise stomp cc.icons[1]. (Store() only fixes a *nil* nextId, not a low one.)
    do
        local maxId = 0
        for existingId in pairs(cc.icons) do
            if type(existingId) == "number" and existingId > maxId then maxId = existingId end
        end
        if (cc.nextId or 1) <= maxId then cc.nextId = maxId + 1 end
    end
    -- True if an icon for this (spellId, dest) already exists — so a re-run (e.g. a restored pre-migration
    -- backup that cleared the flag) cleans up the stale custom instead of creating a DUPLICATE icon.
    local function alreadyMigrated(spellId, dest)
        for _, e in pairs(cc.icons) do
            if e.spellId == spellId and e.cdmDest == dest and e.includeInCdm then return true end
        end
        return false
    end
    local migrated = 0
    for _, dest in ipairs({ "essential", "utility" }) do
        local s = groups[dest]
        if type(s) == "table" and type(s.custom) == "table" and next(s.custom) then
            -- Back up the sub-tables we mutate (once per dest) before touching them.
            p.cdmCustomMigrateBackup = p.cdmCustomMigrateBackup or {}
            p.cdmCustomMigrateBackup[dest] = {
                custom  = ns.DeepCopy(s.custom),
                assign  = ns.DeepCopy(s.assign  or {}),
                order   = ns.DeepCopy(s.order   or {}),
                iconCfg = ns.DeepCopy(s.iconCfg or {}),
            }
            -- Snapshot the keys first (we delete from s.custom while iterating).
            local sids = {}
            for spellId in pairs(s.custom) do sids[#sids + 1] = spellId end
            for _, spellId in ipairs(sids) do
                -- Each custom in its OWN pcall so one malformed entry can't abort the whole batch.
                pcall(function()
                    if type(spellId) ~= "number" then s.custom[spellId] = nil; return end   -- drop junk keys
                    if alreadyMigrated(spellId, dest) then s.custom[spellId] = nil; return end
                    -- New CustomCDM icon for this custom (real cooldown; the old fixed duration is dropped).
                    local id = cc.nextId or 1
                    cc.nextId = id + 1
                    local e = {}
                    ns.MergeDefaults(e, ICON_DEFAULTS)
                    SeedTiers(e)
                    e.spellId      = spellId
                    e.cdmDest      = dest
                    e.includeInCdm = true
                    cc.icons[id]   = e
                    -- Re-key the group placement: number spellId -> frame-name string, keeping its slot.
                    local name = FrameName(id)
                    if type(s.assign) == "table" then
                        s.assign[name] = s.assign[spellId]; s.assign[spellId] = nil
                    end
                    if type(s.order) == "table" then
                        for _, rows in pairs(s.order) do          -- rows = a group's row list
                            if type(rows) == "table" then
                                for ri, row in ipairs(rows) do
                                    if type(row) == "table" then
                                        for ci, v in ipairs(row) do if v == spellId then row[ci] = name end end
                                    elseif row == spellId then     -- legacy flat order
                                        rows[ri] = name
                                    end
                                end
                            end
                        end
                    end
                    -- Safety net: if the custom had no (or Unused) assign but its order slot sits in a REAL
                    -- group, anchor it there — else GroupOf(name) defaults to Group 1 and GroupRows filters
                    -- it out of the group its order placed it in (it'd vanish). Keeps the slot.
                    if type(s.assign) == "table" and (not s.assign[name] or s.assign[name] == 0)
                        and type(s.order) == "table" then
                        for gid, rows in pairs(s.order) do
                            if gid ~= 0 and type(rows) == "table" then
                                local found = false
                                for _, row in ipairs(rows) do
                                    if type(row) == "table" then
                                        for _, v in ipairs(row) do if v == name then found = true; break end end
                                    elseif row == name then found = true end
                                    if found then break end
                                end
                                if found then s.assign[name] = gid; break end
                            end
                        end
                    end
                    if type(s.iconCfg) == "table" and s.iconCfg[spellId] ~= nil then
                        s.iconCfg[name] = s.iconCfg[spellId]; s.iconCfg[spellId] = nil
                    end
                    s.custom[spellId] = nil
                    migrated = migrated + 1
                end)
            end
        end
    end
    if migrated > 0 then ns.Print(tostring(migrated) .. " custom cooldown(s) migrated to CustomCDM (real cooldowns).") end
end

function CC.BuildAll()
    local s = Store()
    if not s then return end
    pcall(MigrateCustoms)   -- one-time, flag-gated; never let a migration error break the build/login
    for id, e in pairs(s.icons) do
        -- Claim the free-look defaults + shared schema by kind (and migrate the legacy CC free schema)
        -- FIRST so they win over the generic ICON_DEFAULTS; both are missing-only on the backfill path,
        -- so MergeDefaults then only fills the remaining keys.
        SeedFreeLookDefaults(e)
        ns.MergeDefaults(e, ICON_DEFAULTS)   -- backfill any missing visual keys
        SeedTiers(e)                         -- give a never-configured entry the default tiers
        BuildIcon(id)
        -- Seed/migrate the per-icon CDM override for an in-CDM spell/item icon so its in-CDM appearance
        -- comes from the Override cadre / group default (like the addon trackers) even before its editor is
        -- opened. Buffs use the BuffGroups override instead (handled by SyncBuffBridge), so skip them.
        if e.includeInCdm and e.entryKind ~= "buff" and ns.ReseedTrackerOverride then
            ns.ReseedTrackerOverride(FrameName(id), e.cdmDest or "essential", ns.DefaultTrackerTimerSeed)
        end
    end
    CC.UpdateAll()
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end   -- lay the (re)built icons out now
end

function CC.Add(dest, row, atEnd, spellId)
    local s = Store()
    if not s then return end
    -- Respect the per-BUCKET cap (front / end each, 4 below-player). The "+" tile already hides when the
    -- target bucket is full; this guards the programmatic path too.
    if ns.CDMAnchor and ns.CDMAnchor.BucketIconCount
        and ns.CDMAnchor.BucketIconCount(dest or "belowPlayer", row or 1, atEnd and true or false)
            >= ns.CDMAnchor.BucketCap(dest or "belowPlayer") then
        ns.Print(L["This row is full."])
        return
    end
    local id = s.nextId or 1
    s.nextId = id + 1
    local e = {}
    ns.MergeDefaults(e, ICON_DEFAULTS)
    SeedTiers(e)
    e.spellId      = spellId
    e.cdmDest      = dest or "belowPlayer"
    e.cdmAtEnd     = atEnd and true or false
    e.cdmRow       = row or 1
    e.includeInCdm = true
    s.icons[id]    = e
    BuildIcon(id)
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
    return id
end

-- Create a custom icon NOT in the CDM (free-positioned) — used by the "+" in the
-- Free icons tab. No row cap (free icons aren't bound to a CDM row).
function CC.AddFree(spellId)
    local s = Store()
    if not s then return end
    local id = s.nextId or 1
    s.nextId = id + 1
    local e = {}
    ns.MergeDefaults(e, ICON_DEFAULTS)
    SeedTiers(e)
    e.spellId      = spellId
    e.includeInCdm = false
    s.icons[id]    = e
    BuildIcon(id)
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
    return id
end

-- ── Draft (the editor's "Add Icon" flow) ──────────────────────────────────────
-- Reserve an uncommitted icon for the editor. ctx: dest/row/atEnd/includeInCdm.
local function NewDraft(ctx)
    local s = Store(); if not s then return nil end
    local id = s.nextId or 1            -- reserved; consumed only on commit
    local e = {}
    ns.MergeDefaults(e, ICON_DEFAULTS)
    SeedTiers(e)
    e.spellId      = 0
    e.includeInCdm = ctx.includeInCdm and true or false
    e.cdmDest      = ctx.dest or "belowPlayer"
    e.cdmAtEnd     = ctx.atEnd and true or false
    e.cdmRow       = ctx.row or 1
    -- ctx.group (optional): a CDMGroups placement { dest, groupId, rowIndex, colIndex } recorded by
    -- CommitDraft once the icon exists, so an essential/utility "+" tile drops the new icon into that
    -- exact group/row as a tracker member.
    _draft = { id = id, entry = e, group = ctx.group }
    return id
end

-- Commit the draft (editor "Add Icon"): validate the spell, move it into the store,
-- build the icon. Returns true on success.
function CC.CommitDraft(id)
    if not (_draft and _draft.id == id) then return false end
    local e   = _draft.entry
    local grp = _draft.group
    if e.entryKind == "item" then
        if not (e.itemId and e.itemId ~= 0 and ItemValid(e.itemId)) then
            ns.Print(L["Invalid item ID or name:"] .. " " .. tostring(e.itemId))
            return false
        end
    elseif not (e.spellId and e.spellId ~= 0 and SpellValid(e.spellId)) then
        ns.Print(L["Invalid spell ID or name:"] .. " " .. tostring(e.spellId))
        return false
    end
    -- A buff also needs a positive fixed duration (the cast-triggered swipe length).
    if e.entryKind == "buff" and not (tonumber(e.duration) and tonumber(e.duration) > 0) then
        ns.Print(L["Enter a buff duration greater than 0."])
        return false
    end
    -- The bucket cap governs ONLY below-player buckets / native rows — never CDMGroups group placement
    -- (a group has its own capacity) nor a buff (it goes to the Buffs viewer, not a bucket); so skip those.
    if not grp and e.entryKind ~= "buff" and e.includeInCdm and ns.CDMAnchor and ns.CDMAnchor.BucketIconCount
        and ns.CDMAnchor.BucketIconCount(e.cdmDest or "belowPlayer", e.cdmRow or 1, e.cdmAtEnd and true or false)
            >= ns.CDMAnchor.BucketCap(e.cdmDest or "belowPlayer") then
        ns.Print(L["This row is full."])
        return false
    end
    local s = Store(); if not s then return false end
    s.icons[id] = e
    s.nextId    = math.max(s.nextId or 1, id + 1)
    _draft = nil
    BuildIcon(id)
    -- Group placement: record the now-built icon as a tracker member of the chosen CDMGroups group, by
    -- frame name. Guard grp.dest == e.cdmDest so a dest changed in the editor (Anchor-to) doesn't strand
    -- the icon in the wrong dest's group (it then just folds into that dest's default group).
    if grp and grp.dest == e.cdmDest then
        local inst = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[grp.dest]
        if inst and inst.AddTrackerMember then
            inst.AddTrackerMember(FrameName(id), grp.groupId, { rowIndex = grp.rowIndex, colIndex = grp.colIndex })
        end
    end
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end   -- force: a newly committed icon must lay out now
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
    return true
end

function CC.DiscardDraft(id)
    if _draft and _draft.id == id then _draft = nil end
end

-- The "+" tile opens the editor on a fresh free draft; "Add Icon" inside commits it.
function CC.PromptAddFree()
    local id = NewDraft({ includeInCdm = false })
    if not id then return end
    local e = EntryById(id); if e then SeedFreeLookDefaults(e, true) end
    if CC.OpenEditor then CC.OpenEditor(id) end
end

-- The Free-icons "+" -> "Buff" choice: a fresh free draft of the BUFF kind (cast-triggered,
-- fixed-duration), opened in the dedicated Buff editor; "Add Icon" inside commits it.
function CC.PromptAddFreeBuff()
    local id = NewDraft({ includeInCdm = false })
    if not id then return end
    local e = EntryById(id)
    if e then
        e.entryKind = "buff"
        if not e.duration or e.duration <= 0 then e.duration = ICON_DEFAULTS.duration end
        SeedFreeLookDefaults(e, true)   -- buff free-look schema + defaults (override the merged ICON_DEFAULTS)
    end
    if CC.OpenBuffEditor then CC.OpenBuffEditor(id) end
end

-- The Buff-groups tab "+" tile: same Buff template as Free icons, but pre-set to live in the CDM
-- (Include in CDM on) and mirrored into the clicked buff group. Committing it registers the mirror
-- in that group via SyncBuffBridge. (Group 0 / Unused → the default visible group 1.)
function CC.PromptAddBuffToGroup(groupId)
    local id = NewDraft({ includeInCdm = true })
    if not id then return end
    local e = EntryById(id)
    if e then
        e.entryKind = "buff"
        if not e.duration or e.duration <= 0 then e.duration = ICON_DEFAULTS.duration end
        e.cdmBuffGroup = (groupId and groupId > 0) and groupId or 1
        SeedFreeLookDefaults(e, true)   -- buff free-look schema + defaults (override the merged ICON_DEFAULTS)
    end
    if CC.OpenBuffEditor then CC.OpenBuffEditor(id) end
end

function CC.SetSpellId(id, spellId)
    local e = Entry(id)
    if not e then return end
    e.spellId = spellId
    local d = live[id]
    if d then d.lastUseAt = nil; d.learnedCd = nil; d.hasCooldown = false; d.lastExpiry = nil end
    ApplyOne(id)
    SyncBuffBridge(id)   -- a bridged buff that changed spell re-registers under the new spellId
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
end

function CC.SetItemId(id, itemId)
    local e = Entry(id)
    if not e then return end
    e.itemId = itemId
    local d = live[id]
    if d then d.lastUseAt = nil; d.learnedCd = nil; d.hasCooldown = false; d.lastExpiry = nil end
    ApplyOne(id)
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
end

-- Resolve a user input (ID / name, or item link for items) and set it as the icon's spell OR item,
-- by the icon's entryKind. Returns ok. For a draft it only records the id (committed by "Add Icon").
function CC.SetSpellInput(id, value)
    local e = EntryById(id)
    if e and e.entryKind == "item" then
        local iid = ResolveItem(value)
        if not iid then
            ns.Print(L["Invalid item ID or name:"] .. " " .. tostring(value))
            return false
        end
        if CC.IsDraft(id) then e.itemId = iid; return true end
        CC.SetItemId(id, iid)
        return true
    end
    local sid = ResolveSpell(value)
    if not sid then
        ns.Print(L["Invalid spell ID or name:"] .. " " .. tostring(value))
        return false
    end
    if CC.IsDraft(id) then
        if e then e.spellId = sid end
        return true
    end
    CC.SetSpellId(id, sid)
    return true
end

function CC.Remove(id)
    local s = Store()
    if not s then return end
    local e = s.icons[id]
    local d = live[id]
    if d then
        d.removed = true   -- mark inert: ApplyOne bails early so UpdateAll skips this dead-but-kept icon
        d.icon.Hide()
        local f = d.icon.GetFrame()
        if f then f:Hide() end
    end
    if e then
        s.icons[id] = nil
        -- Drop its order-map entry so a future icon never inherits the stale slot.
        if ns.db and ns.db.profile and ns.db.profile.cdmOrder then
            ns.db.profile.cdmOrder[FrameName(id)] = nil
        end
        -- If it was folded into a CDMGroups group (essential/utility tracker member), drop that group
        -- assignment too, so no orphan frame-name key lingers in the dest's assign/order.
        if e.includeInCdm and ns.CDMGroups and ns.CDMGroups.instances then
            local inst = ns.CDMGroups.instances[e.cdmDest]
            if inst and inst.RemoveTrackerMember then inst.RemoveTrackerMember(FrameName(id)) end
        end
    end
    -- The entry is gone from the store, so CdmFlag now reads false: re-run ApplyKeybind to drop this
    -- (now hidden) frame from the shared press-overlay poller instead of leaving it registered.
    if d and d.icon.ApplyKeybind then d.icon.ApplyKeybind() end
    -- Drop the BuffGroups mirror (if this was a bridged buff). Entry is gone now, so SyncBuffBridge
    -- resolves want=false and removes whatever spellId we registered for this id.
    SyncBuffBridge(id)
    if ns.CustomCDM.CloseEditorFor then ns.CustomCDM.CloseEditorFor(id) end
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end   -- force: re-pack the row/grid without the removed icon
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
end

-- Ask before deleting (the list crosses + the editor's "Delete Icon" both route here):
-- a small dialog showing the icon + its spell name with Yes/No.
function CC.ConfirmRemove(id)
    local e = EntryById(id)
    ns.ui.ShowConfirm({
        title      = L["Delete custom icon"],
        text       = L["Are you sure you want to delete this icon?"],
        icon       = IconTextureForEntry(e),
        name       = CC.SpellName(id),
        acceptText = L["Yes"],
        cancelText = L["No"],
        onAccept   = function() CC.Remove(id) end,
    })
end

-- ── Add (opens the editor on a draft) / edit (opens it on the committed icon) ──
function CC.PromptAdd(dest, row, atEnd)
    local id = NewDraft({ dest = dest, row = row, atEnd = atEnd, includeInCdm = true })
    if not id then return end
    local e = EntryById(id); if e then SeedFreeLookDefaults(e, true) end
    if CC.OpenEditor then CC.OpenEditor(id) end
end

-- Opened by the essential/utility group "+" tiles: a draft pinned to that group. "Add Icon" in the
-- editor commits it AND records it as a tracker member at (groupId, rowIndex, colIndex). rowIndex /
-- colIndex == math.huge mean "new row" / "end of row" (resolved by I.MoveBuff).
function CC.PromptAddToGroup(dest, groupId, rowIndex, colIndex)
    local id = NewDraft({ dest = dest, includeInCdm = true,
        group = { dest = dest, groupId = groupId, rowIndex = rowIndex, colIndex = colIndex } })
    if not id then return end
    local e = EntryById(id); if e then SeedFreeLookDefaults(e, true) end
    if CC.OpenEditor then CC.OpenEditor(id) end
end

-- The pen opens the full per-icon editor window (defined in UI/Editor.lua). Routed by kind so a
-- buff icon opens the dedicated Buff editor and a spell/item icon the standard CustomCDM editor.
function CC.PromptEdit(id)
    local e = Entry(id)
    if not e then return end
    if e.entryKind == "buff" then
        if CC.OpenBuffEditor then CC.OpenBuffEditor(id) end
    elseif CC.OpenEditor then
        CC.OpenEditor(id)
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────
-- The player's OWN cast spellId is readable; record the cast time (for the in-combat
-- estimate) and fire the "on use" sound for any icon tracking that spell.
CC:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellId)
    if unit ~= "player" then return end
    for id, d in pairs(live) do
        local e = Entry(id)
        if e and e.spellId == spellId then
            d.lastUseAt = GetTime()
            -- Buff kind: arm the fixed-duration swipe ONLY when WE render it (free / BuffGroups off).
            -- When the Buffs viewer owns the render, BuffGroups' own cast handler drives the swipe.
            if e.entryKind == "buff" and not BuffMirrored(e) then
                d.buffExpiry = GetTime() + (tonumber(e.duration) or 0)
                ApplyOne(id)
            end
            if e.soundOnUse then PlaySound(id, "use") end
        end
    end
end)
CC:RegisterEvent("SPELL_UPDATE_COOLDOWN", function() MarkCooldownDirty() end)
-- A buff drops on death (mirrors the buff-groups custom buffs): clear every armed swipe.
CC:RegisterEvent("PLAYER_DEAD", function()
    for id, d in pairs(live) do
        if d.buffExpiry then d.buffExpiry = nil; ApplyOne(id) end
    end
end)

CC:ScheduleRepeatingTimer(function() CC.UpdateAll() end, 0.5)

ns.RegisterReloadHook(function() CC.BuildAll() end)

local initCC = CreateFrame("Frame")
initCC:RegisterEvent("PLAYER_LOGIN")
initCC:SetScript("OnEvent", function(self)
    CC.BuildAll()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
