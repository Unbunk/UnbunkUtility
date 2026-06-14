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

-- Per-icon config defaults. Visual blocks mirror the potion tracker; the title block
-- is healthstone-styled with the text left empty + hidden by default. Timer urgency
-- tiers are seeded separately (SeedTiers) so editing the list is never "merged back".
local ICON_DEFAULTS = {
    spellId        = 0,
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
    -- Timer text (from potions) + a show toggle. Tiers live in `timerTiers` (seeded).
    showTimer      = true,
    timerFontKey   = "Fira Mono",
    timerFontPath  = nil,
    timerFontSize  = 20,
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
    stackAnchor    = "BOTTOM",
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

-- live[id] = { icon, titleFS, stackFS, lastUseAt, learnedCd, lastExpiry, hasCooldown }
local live = {}

local function FrameName(id) return "UnbunkUtilityCustomCDM" .. id end

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

function CC.SpellName(id)
    local e = Entry(id)
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

-- Current / max charges for a charge-based spell, else nil.
local function GetCharges(spellId)
    if not spellId or spellId == 0 then return nil end
    if C_Spell and C_Spell.GetSpellCharges then
        local ci = C_Spell.GetSpellCharges(spellId)
        if ci then return ci.currentCharges, ci.maxCharges end
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
-- Maps an anchor mode to (fsPoint, framePoint, x, y): the title/stack can sit inside
-- the icon (centre) or just outside any of its four edges.
local ANCHOR_POINTS = {
    CENTER = { "CENTER", "CENTER",  0,  0 },
    TOP    = { "BOTTOM", "TOP",     0,  2 },
    BOTTOM = { "TOP",    "BOTTOM",  0, -2 },
    LEFT   = { "RIGHT",  "LEFT",   -2,  0 },
    RIGHT  = { "LEFT",   "RIGHT",   2,  0 },
}
local function AnchorFS(fs, frame, mode, ox, oy)
    local a = ANCHOR_POINTS[mode] or ANCHOR_POINTS.CENTER
    fs:ClearAllPoints()
    fs:SetPoint(a[1], frame, a[2], a[3] + (ox or 0), a[4] + (oy or 0))
end

local function ApplyTitle(id)
    local d = live[id]
    if not d or not d.titleFS then return end
    local e = Entry(id)
    local fs = d.titleFS
    if not e or not e.showTitle then fs:Hide(); return end
    fs:SetFont(ns.ResolveFontPath(e.titleFontPath, e.titleFontKey), e.titleFontSize or 16, e.titleOutline or "OUTLINE")
    local c = e.titleColor or { r = 1, g = 1, b = 1, a = 1 }
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
    AnchorFS(fs, d.icon.GetFrame(), e.titleAnchor or "TOP", e.titleOffsetX, e.titleOffsetY)
    fs:SetText(e.titleText or "")
    fs:Show()
end

local function ApplyStack(id)
    local d = live[id]
    if not d or not d.stackFS then return end
    local e = Entry(id)
    local fs = d.stackFS
    if not e or not e.showStack then fs:Hide(); return end
    fs:SetFont(ns.ResolveFontPath(e.stackFontPath, e.stackFontKey), e.stackFontSize or 12, e.stackOutline or "OUTLINE")
    local c = e.stackColor or { r = 1, g = 1, b = 1, a = 1 }
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
    AnchorFS(fs, d.icon.GetFrame(), e.stackAnchor or "BOTTOM", e.stackOffsetX, e.stackOffsetY)
    local cur, maxc = GetCharges(e.spellId)
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
    local e = Entry(id)
    if not e then d.icon.Hide(); return end   -- removed / not in this profile -> inert

    d.icon.SetIcon(SpellTexture(e.spellId))
    d.icon.ApplySize()

    -- "Show icon at 0 stacks": for a charge spell at 0 charges, hide the icon when off.
    local cur, maxc = GetCharges(e.spellId)
    if cur and maxc and maxc > 1 and cur == 0 and not e.showAtZero then
        d.icon.Hide()
        return
    end
    d.icon.Show()
    ApplyStack(id)

    local spellId = e.spellId
    if not spellId or spellId == 0 then d.icon.ClearTimer(); return end

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
    if d then return d end
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
            if e[key] ~= nil then return e[key] end
            return ICON_DEFAULTS[key]
        end,
        onDragStop = function(x, y)
            local e = Entry(id)
            if e then e.posX = x; e.posY = y end
        end,
    })
    icon.onExpire = function() end
    d = { icon = icon }
    local frame = icon.GetFrame()
    -- Title / stack drawn over the icon (the timer text lives on a higher child frame,
    -- so a centred title/stack sits under the countdown — acceptable, user-chosen).
    d.titleFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    d.stackFS = frame:CreateFontString(nil, "OVERLAY", nil, 6)
    live[id] = d
    return d
end

local function BuildIcon(id)
    local d = EnsureIcon(id)
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(id)
    ApplyOne(id)
    return d
end

-- ── Public API ────────────────────────────────────────────────────────────────
function CC.UpdateAll()
    for id in pairs(live) do ApplyOne(id) end
end

-- Re-apply every visual of one icon after a config edit (used by the editor).
function CC.ApplyIcon(id)
    local d = live[id]
    if not d then return end
    d.icon.ApplyFont()
    d.icon.ApplySize()
    d.icon.ApplyBorder()
    ApplyTitle(id)
    ApplyOne(id)   -- also re-applies the stack
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
end

function CC.GetEntry(id) return Entry(id) end

-- The custom icons NOT included in the Cooldown Manager (free-positioned), in the
-- order they were added (ascending id). Each item id is the icon's FRAME NAME so the
-- "Free icons" strip's edit/delete controls round-trip through IdFromFrameName.
function CC.GetFreeIcons()
    local s = Store()
    if not s then return {} end
    local ids = {}
    for id, e in pairs(s.icons) do
        if not e.includeInCdm then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do
        out[#out + 1] = { id = FrameName(id), texture = SpellTexture(s.icons[id].spellId), custom = true }
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
    local e = Entry(id)
    if e and e[key] ~= nil then return e[key] end
    return ICON_DEFAULTS[key]
end

-- Write a config value and re-apply the icon (for the editor's setters).
function CC.Set(id, key, val)
    local e = Entry(id)
    if not e then return end
    e[key] = val
    CC.ApplyIcon(id)
end

-- Build every custom icon in the current profile (and refresh all live ids, so any
-- left over from a previous profile that the current one lacks get hidden).
function CC.BuildAll()
    local s = Store()
    if not s then return end
    for id, e in pairs(s.icons) do
        ns.MergeDefaults(e, ICON_DEFAULTS)   -- backfill any missing visual keys
        SeedTiers(e)                         -- give a never-configured entry the default tiers
        BuildIcon(id)
    end
    CC.UpdateAll()
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end   -- lay the (re)built icons out now
end

function CC.Add(dest, row, atEnd, spellId)
    local s = Store()
    if not s then return end
    -- Respect the per-row cap (front + end combined). The "+" tile already hides when
    -- the row is full; this guards the programmatic path too.
    if ns.CDMAnchor and ns.CDMAnchor.RowIconCount
        and ns.CDMAnchor.RowIconCount(dest or "belowPlayer", row or 1) >= ns.CDMAnchor.RowCap(dest or "belowPlayer") then
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

function CC.PromptAddFree()
    ns.ui.ShowPrompt({
        title      = L["Add custom CDM icon"],
        text       = L["Enter a spell ID or name:"],
        default    = "",
        maxLetters = 64,
        acceptText = L["Add"],
        onAccept   = function(value)
            local spellId = ResolveSpell(value)
            if not spellId then
                ns.Print(L["Invalid spell ID or name:"] .. " " .. tostring(value))
                return
            end
            CC.AddFree(spellId)
        end,
    })
end

function CC.SetSpellId(id, spellId)
    local e = Entry(id)
    if not e then return end
    e.spellId = spellId
    local d = live[id]
    if d then d.lastUseAt = nil; d.learnedCd = nil; d.hasCooldown = false; d.lastExpiry = nil end
    ApplyOne(id)
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
end

-- Resolve a user input (ID or name) and set it as the icon's spell. Returns ok.
function CC.SetSpellInput(id, value)
    local sid = ResolveSpell(value)
    if not sid then
        ns.Print(L["Invalid spell ID or name:"] .. " " .. tostring(value))
        return false
    end
    CC.SetSpellId(id, sid)
    return true
end

function CC.Remove(id)
    local s = Store()
    if not s then return end
    local d = live[id]
    if d then
        d.icon.Hide()
        local f = d.icon.GetFrame()
        if f then f:Hide() end
    end
    if s.icons[id] then
        s.icons[id] = nil
        -- Drop its order-map entry so a future icon never inherits the stale slot.
        if ns.db and ns.db.profile and ns.db.profile.cdmOrder then
            ns.db.profile.cdmOrder[FrameName(id)] = nil
        end
    end
    if ns.CustomCDM.CloseEditorFor then ns.CustomCDM.CloseEditorFor(id) end
    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
    if ns.RebuildActiveModule then ns.RebuildActiveModule() end
end

-- ── Add (quick prompt) / edit (full editor window) ────────────────────────────
function CC.PromptAdd(dest, row, atEnd)
    ns.ui.ShowPrompt({
        title      = L["Add custom CDM icon"],
        text       = L["Enter a spell ID or name to add to this row:"],
        default    = "",
        maxLetters = 64,
        acceptText = L["Add"],
        onAccept   = function(value)
            local spellId = ResolveSpell(value)
            if not spellId then
                ns.Print(L["Invalid spell ID or name:"] .. " " .. tostring(value))
                return
            end
            CC.Add(dest, row, atEnd, spellId)
        end,
    })
end

-- The pen opens the full per-icon editor window (defined in UI/Editor.lua).
function CC.PromptEdit(id)
    if not Entry(id) then return end
    if CC.OpenEditor then CC.OpenEditor(id) end
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
            if e.soundOnUse then PlaySound(id, "use") end
        end
    end
end)
CC:RegisterEvent("SPELL_UPDATE_COOLDOWN", function() CC.UpdateAll() end)

CC:ScheduleRepeatingTimer(function() CC.UpdateAll() end, 0.5)

ns.RegisterReloadHook(function() CC.BuildAll() end)

local initCC = CreateFrame("Frame")
initCC:RegisterEvent("PLAYER_LOGIN")
initCC:SetScript("OnEvent", function(self)
    CC.BuildAll()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
