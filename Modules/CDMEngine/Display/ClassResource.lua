-- Modules/CDMEngine/Display/ClassResource.lua
--
-- Phase 4c of the standalone CDM engine (ns.CDMEngine): the CLASS-RESOURCE widget. Draws the current
-- spec's characteristic resource (combo points, holy power, essence, an energy/mana bar, ...) beside
-- the CDM icons, in OUR OWN frames. SLICE 1 = the power-based families (bar / discrete pips / essence);
-- runes, aura-based resources and stagger arrive in later slices as pure additions to `Families` + the
-- descriptor registry (Core/Resources.lua), with NO change to this scaffold.
--
-- TAINT / SECRET: like IconExtras, a SEPARATE event frame reads only game state
-- (UnitPower/UnitPowerMax/UnitPartialPower — none a CDM read, none secret except Stagger, added later
-- with an issecretvalue guard) onto our own frames, so it can't taint Blizzard's secure CDM handler
-- even though the CDM co-registers UNIT_POWER_*. Power events stay OFF Layout's coalesced firewall
-- (UNIT_POWER_FREQUENT is ~per-tick and needs no deferral — it never touches the CDM); only the
-- SPEC-CHANGE re-detect goes through a trivial flag + C_Timer.After(0) firewall. NO native-frame contact
-- (never PlayerFrame / EssencePlayerFrame / RuneFrame / ...), NO hooksecurefunc. Per-cell OnUpdate only
-- for essence (bounded, self-cancelling) — the one documented exception in slice 1.

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
E.Resource = E.Resource or {}
local R = E.Resource

local UnitPower, UnitPowerMax, UnitPartialPower = UnitPower, UnitPowerMax, UnitPartialPower
local issecretvalue = issecretvalue or function() return false end   -- ready for the secret Stagger family (slice 3)

local DEFAULT_X, DEFAULT_Y = 0, -140   -- below the icon container on a fresh profile (fully draggable)

-- Fallback bar/pip colours by power enum (PowerBarColor's keying is unreliable across power types).
local COLORS = {}
do
    local P = Enum and Enum.PowerType
    if P then
        COLORS[P.Energy]        = { 1.00, 0.85, 0.10 }
        COLORS[P.Mana]          = { 0.20, 0.40, 1.00 }
        COLORS[P.Rage]          = { 0.90, 0.15, 0.15 }
        COLORS[P.Focus]         = { 1.00, 0.50, 0.25 }
        COLORS[P.Fury]          = { 0.79, 0.26, 0.99 }
        COLORS[P.RunicPower]    = { 0.00, 0.82, 1.00 }
        COLORS[P.Insanity]      = { 0.40, 0.00, 0.80 }
        COLORS[P.LunarPower]    = { 0.30, 0.52, 0.90 }
        COLORS[P.Maelstrom]     = { 0.00, 0.50, 1.00 }
        COLORS[P.SoulShards]    = { 0.58, 0.51, 0.79 }
        COLORS[P.HolyPower]     = { 0.95, 0.90, 0.60 }
        COLORS[P.ComboPoints]   = { 1.00, 0.85, 0.10 }
        COLORS[P.Chi]           = { 0.71, 1.00, 0.92 }
        COLORS[P.ArcaneCharges] = { 0.10, 0.65, 1.00 }
        COLORS[P.Essence]       = { 0.20, 0.85, 0.90 }
    end
end
local function ColorFor(power)
    local c = COLORS[power]
    if c then return c[1], c[2], c[3] end
    return 0.6, 0.6, 0.6
end
local RUNE_COLOR = { 0.00, 0.82, 1.00 }   -- runic blue (runes family)
local AURA_COLOR = { 0.60, 0.80, 1.00 }   -- generic aura-stack colour (auraBar/auraPips)

local function Cfg(key) return E.Cfg and E.Cfg.GetResource(key) end
local function Say(msg)
    if ns.Print then ns.Print(msg) else print("|cff338cff[UnbunkUtility]|r " .. tostring(msg)) end
end

-- ── State ─────────────────────────────────────────────────────────────────────────────────────
local container
local shown = false
local activeRows = {}   -- drawn rows: { family, desc, cells = {cell,...}, power, divisor, _y }
local Rebuild, ScheduleSpecRebuild   -- forward-declared (used by Families.update before their definitions)

-- ── Cell pool (our frames; a re-acquired frame MUST Show() — the pool gotcha) ────────────────────
-- One cell shape reused by every family: a Frame whose dark BACKGROUND doubles as a 1px border around
-- an inset StatusBar (mirrors the icon's border idiom).
local cellPool = {}
local function BuildCell()
    local c = CreateFrame("Frame", nil, container)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0, 0, 0, 0.85)
    c.sb = CreateFrame("StatusBar", nil, c)
    c.sb:SetPoint("TOPLEFT", 1, -1)
    c.sb:SetPoint("BOTTOMRIGHT", -1, 1)
    c.sb:SetStatusBarTexture("Interface/Buttons/WHITE8X8")
    return c
end
local function AcquireCell()
    local c = table.remove(cellPool) or BuildCell()
    c:SetParent(container)
    c:Show()
    return c
end
local function ReleaseCell(c)
    c:SetScript("OnUpdate", nil)   -- essence arms a per-cell ticker; drop it before pooling
    if c.sb and c.sb.SetTimerDuration then pcall(c.sb.SetTimerDuration, c.sb, nil) end   -- stop a rune timer fill
    c:Hide()
    c:ClearAllPoints()
    cellPool[#cellPool + 1] = c
end

-- ── Families: contract = setup(row, desc, cfg) + update(row) [+ teardown(row)] ──────────────────
-- update() re-reads live state and repaints; it is driven by the shared event frame, never a ticker
-- (except essence's bounded per-cell OnUpdate while a pip charges).
-- SECRET CONTRACT: this DATA handler co-fires SYNCHRONOUSLY with Blizzard's secure CDM refresh, so a
-- family whose update() reads a POSSIBLY-SECRET power MUST guard it (Stagger, slice 3):
--   local v = UnitStagger("player"); if issecretvalue(v) then return end   -- BEFORE any SetValue/compare
-- The slice-1 families (bar/pips/essence) read only NON-secret power, so no guard is needed here.
local Families = {}

Families.bar = {   -- imitates Coolinator GenerateBarForResource, on our own StatusBar
    setup = function(row, desc, cfg)
        local c = row.cells[1]
        c:SetSize(cfg.barWidth, cfg.barHeight)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(row._y or 0))
        row.power = desc.power
        c.sb:SetStatusBarColor(ColorFor(desc.power))
        Families.bar.update(row)
    end,
    update = function(row)
        if not row.power then return end
        local sb = row.cells[1].sb
        local mx = UnitPowerMax("player", row.power)
        sb:SetMinMaxValues(0, (mx and mx > 0) and mx or 1)
        sb:SetValue(UnitPower("player", row.power) or 0)
    end,
}

Families.pips = {   -- imitates GeneratePipResource: each pip is a mini 0..divisor fill
    setup = function(row, desc, cfg)
        row.power, row.divisor = desc.power, desc.divisor or 1
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(ColorFor(desc.power))
            c.sb:SetMinMaxValues(0, row.divisor)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), -(row._y or 0))
        end
        Families.pips.update(row)
    end,
    update = function(row)
        if not row.power then return end
        local mx  = UnitPowerMax("player", row.power) or 0
        local cur = UnitPower("player", row.power, true) or 0   -- true = unmodified value (partial fills)
        if math.max(mx, 1) ~= #row.cells then ScheduleSpecRebuild(); return end   -- max grew/shrank -> re-alloc cells
        local pips = mx           -- pip COUNT is the RAW max; divisor scales the VALUE only, never the count
        local val  = cur / row.divisor
        local showEmpty = Cfg("showEmpty") ~= false
        for i, c in ipairs(row.cells) do
            if i > pips then
                c:Hide()
            elseif val >= i then
                c:Show(); c.sb:SetValue(row.divisor)
            elseif math.ceil(val) < i then
                c:SetShown(showEmpty); c.sb:SetValue(0)
            else
                c:Show(); c.sb:SetValue(cur % row.divisor)
            end
        end
    end,
}

Families.essence = {   -- imitates GenerateEssenceResource: pip run + OnUpdate ONLY while a pip charges
    setup = function(row, desc, cfg)
        row.power = desc.power
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(ColorFor(desc.power))
            c.sb:SetMinMaxValues(0, 1000)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), -(row._y or 0))
        end
        Families.essence.update(row)
    end,
    update = function(row)
        if not row.power then return end
        local mx  = UnitPowerMax("player", row.power) or 0
        local cur = UnitPower("player", row.power) or 0
        if math.max(mx, 1) ~= #row.cells then ScheduleSpecRebuild(); return end   -- max grew/shrank -> re-alloc cells
        local showEmpty = Cfg("showEmpty") ~= false
        for i, c in ipairs(row.cells) do
            c:SetScript("OnUpdate", nil)   -- clear a stale charging ticker before re-deciding
            if i > mx then
                c:Hide()
            elseif cur >= i then
                c:Show(); c.sb:SetValue(1000)
            elseif cur < i - 1 then
                c:SetShown(showEmpty); c.sb:SetValue(0)
            else   -- THIS pip is charging: arm a bounded OnUpdate that self-cancels when partial regresses
                c:Show()
                local p = UnitPartialPower and UnitPartialPower("player", row.power) or 0
                c.sb:SetValue(p)
                if UnitPartialPower then
                    local power = row.power
                    c:SetScript("OnUpdate", function(self)
                        local pp = UnitPartialPower("player", power)
                        local v = self.sb:GetValue()
                        if pp < v then self.sb:SetValue(1000); self:SetScript("OnUpdate", nil)   -- pip completed
                        elseif pp ~= v then self.sb:SetValue(pp) end
                    end)
                end
            end
        end
    end,
    teardown = function(row)
        for _, c in ipairs(row.cells) do c:SetScript("OnUpdate", nil) end
    end,
}

-- ── SLICE 2 families: runes (DK cooldown pips) + aura-stack resources ────────────────────────────
Families.runes = {   -- 6 cells; each shows a rune (sorted by recharge start), C-side timer fill on cooldown
    setup = function(row, desc, cfg)
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(RUNE_COLOR[1], RUNE_COLOR[2], RUNE_COLOR[3])
            c.sb:SetMinMaxValues(0, 1)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), -(row._y or 0))
            c:Show()
        end
        Families.runes.update(row)
    end,
    update = function(row)
        if not GetRuneCooldown then return end
        local times = {}
        for i = 1, 6 do times[i] = { GetRuneCooldown(i) } end   -- { startTime, duration, isReady }
        table.sort(times, function(a, b) return (a[1] or 0) < (b[1] or 0) end)
        for i, c in ipairs(row.cells) do
            local t = times[i]
            if not t then
                c:Hide()
            else
                local s, d, ready = t[1] or 0, t[2] or 0, t[3]
                c:Show()
                if c.sb.SetTimerDuration then pcall(c.sb.SetTimerDuration, c.sb, nil) end   -- leave timer mode; re-armed below if on cd
                if ready then
                    c.sb:SetMinMaxValues(0, 1); c.sb:SetValue(1)
                elseif s > 0 and d > 0 and c.sb.SetTimerDuration
                       and C_DurationUtil and C_DurationUtil.CreateDuration then
                    c.runeDur = c.runeDur or C_DurationUtil.CreateDuration()
                    if c.runeDur.SetTimeFromStart then
                        c.runeDur:SetTimeFromStart(s, d)
                        c.sb:SetTimerDuration(c.runeDur)   -- C-side recharge fill, no OnUpdate
                    else
                        c.sb:SetValue(0)
                    end
                else
                    c.sb:SetValue(0)   -- fallback: empty while on cooldown (no timer API)
                end
            end
        end
    end,
}

Families.auraBar = {   -- a bar whose fill = the player's stack count of an aura (icicles, tip of the spear)
    setup = function(row, desc, cfg)
        row.spellID, row.max = desc.spellID, desc.max or 1
        local c = row.cells[1]
        c:SetSize(cfg.barWidth, cfg.barHeight)
        c.sb:SetStatusBarColor(AURA_COLOR[1], AURA_COLOR[2], AURA_COLOR[3])
        c.sb:SetMinMaxValues(0, row.max)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(row._y or 0))
        Families.auraBar.update(row)
    end,
    update = function(row)
        if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID and row.spellID) then return end
        local a = C_UnitAuras.GetUnitAuraBySpellID("player", row.spellID)
        row.cells[1].sb:SetValue((a and a.applications) or 0)
    end,
}

Families.auraPips = {   -- discrete pips whose fill = the player's stack count of an aura (maelstrom weapon)
    setup = function(row, desc, cfg)
        row.spellID, row.divisor = desc.spellID, desc.divisor or 1
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(AURA_COLOR[1], AURA_COLOR[2], AURA_COLOR[3])
            c.sb:SetMinMaxValues(0, row.divisor)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), -(row._y or 0))
        end
        Families.auraPips.update(row)
    end,
    update = function(row)
        if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID and row.spellID) then return end
        local a = C_UnitAuras.GetUnitAuraBySpellID("player", row.spellID)
        local cur = (a and a.applications) or 0
        local val = cur / row.divisor
        local showEmpty = Cfg("showEmpty") ~= false
        for i, c in ipairs(row.cells) do
            if val >= i then c:Show(); c.sb:SetValue(row.divisor)
            elseif math.ceil(val) < i then c:SetShown(showEmpty); c.sb:SetValue(0)
            else c:Show(); c.sb:SetValue(cur % row.divisor) end
        end
    end,
}

local function ReleaseRow(row)
    local fam = Families[row.family]
    if fam and fam.teardown then fam.teardown(row) end
    for _, c in ipairs(row.cells) do ReleaseCell(c) end
    wipe(row.cells)
end

-- How many cells a descriptor needs (pips/essence scale with the live max; a bar is one cell).
local function CellCountFor(desc)
    if desc.family == "pips" then
        return math.max(UnitPowerMax("player", desc.power) or 0, 1)   -- RAW max = pip count (divisor is a value scale)
    elseif desc.family == "essence" then
        return math.max(UnitPowerMax("player", desc.power) or 0, 1)
    elseif desc.family == "runes" then
        return 6
    elseif desc.family == "auraPips" then
        return math.max(desc.max or 1, 1)
    else
        return 1   -- bar / auraBar
    end
end

-- Whether a descriptor can actually be drawn by its family (guards a missing power enum / spellID, an
-- old client, or a label whose slice-3 family is not implemented yet).
local function DescUsable(desc)
    if not (desc and Families[desc.family]) then return false end
    local f = desc.family
    if f == "bar" or f == "pips" or f == "essence" then return desc.power ~= nil end
    if f == "auraBar" or f == "auraPips" then return desc.spellID ~= nil end
    return true   -- runes (and a future stagger) need no extra descriptor field
end

-- ── Position ────────────────────────────────────────────────────────────────────────────────────
local function ApplyPosition()
    if not container then return end
    local p = E.Cfg and E.Cfg.GetResourcePos()
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", (p and p.x) or DEFAULT_X, (p and p.y) or DEFAULT_Y)
end

-- ── DATA event frame (own frame; IconExtras taint pattern — only game-state reads onto our frames) ──
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    for _, row in ipairs(activeRows) do
        local fam = Families[row.family]
        if fam then fam.update(row) end
    end
end)
local registeredEvents = {}
local UNIT_SCOPED = {   -- events that take a unit filter (RegisterUnitEvent "player"); RUNE_POWER_UPDATE does not
    UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_AURA = true,
}
local FAMILY_EVENTS = {
    bar      = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" },
    pips     = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" },
    essence  = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" },
    runes    = { "RUNE_POWER_UPDATE" },
    auraBar  = { "UNIT_AURA" },
    auraPips = { "UNIT_AURA" },
}
local function RegisterFamilyEvents(family)
    local evs = FAMILY_EVENTS[family]
    if not evs then return end
    for _, e in ipairs(evs) do
        if not registeredEvents[e] then
            registeredEvents[e] = true
            if UNIT_SCOPED[e] then pcall(ev.RegisterUnitEvent, ev, e, "player")
            else                   pcall(ev.RegisterEvent, ev, e) end
        end
    end
end
local function UnregisterData()
    ev:UnregisterAllEvents()
    wipe(registeredEvents)
end

-- ── SPEC-CHANGE firewall (trivial handler = flag + C_Timer.After(0); re-detect the resource) ────────
local specQueued = false
local function DoSpecRebuild()
    specQueued = false
    if not shown then return end
    if E.Design and E.Design.dragging then   -- never rebuild under a drag: re-arm and let the drop run it
        specQueued = true
        C_Timer.After(0, DoSpecRebuild)
        return
    end
    Rebuild()
end
function ScheduleSpecRebuild()
    if specQueued then return end
    specQueued = true
    C_Timer.After(0, DoSpecRebuild)
end
local specEv = CreateFrame("Frame")
specEv:SetScript("OnEvent", function() ScheduleSpecRebuild() end)   -- trivial: NO reads here
local function RegisterSpecEvents()
    for _, e in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_ENTERING_WORLD" }) do
        pcall(specEv.RegisterEvent, specEv, e)
    end
end
local function UnregisterSpec() specEv:UnregisterAllEvents() end

-- ── Build ────────────────────────────────────────────────────────────────────────────────────────
local function EnsureContainer()
    if container then return end
    container = CreateFrame("Frame", "UnbunkCDMEngineResource", UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(container) end
    container:SetSize(1, 1)
    ApplyPosition()
end

Rebuild = function()
    if not (container and shown) then return end
    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    wipe(activeRows)
    UnregisterData()
    if not Cfg("enable") then
        container:Hide()
        -- still let the designer re-evaluate: with the widget off, R.IsShown() is false so Reattach
        -- detaches the now-stale '__resource__' overlay instead of leaving a grabbable frame behind.
        if E.Design and E.Design.Reattach then E.Design.Reattach() end
        return
    end

    local labels = R.Detect()
    local cfg = {
        barWidth   = Cfg("barWidth")   or 200, barHeight = Cfg("barHeight") or 16,
        pipSize    = Cfg("pipSize")    or 22,  pipSpacing = Cfg("pipSpacing") or 3,
    }
    local rowSpacing = Cfg("rowSpacing") or 4
    local cap = Cfg("showCount")   -- 0 / nil = draw all the spec's resources; N>0 = cap to N
    local n = (cap and cap > 0) and math.min(cap, #labels) or #labels
    local y, w = 0, 1
    for i = 1, n do
        local desc = R.REGISTRY[labels[i]]
        -- Skip a label with no descriptor, or one whose family can't be drawn (missing power / spellID,
        -- an old client, or a slice-3 family not implemented yet).
        if DescUsable(desc) then
            local row = { family = desc.family, desc = desc, cells = {}, _y = y }
            for k = 1, CellCountFor(desc) do row.cells[k] = AcquireCell() end
            Families[desc.family].setup(row, desc, cfg)
            RegisterFamilyEvents(desc.family)
            activeRows[#activeRows + 1] = row
            local isBar = (desc.family == "bar" or desc.family == "auraBar")
            local rowH = isBar and cfg.barHeight or cfg.pipSize
            local rowW = isBar and cfg.barWidth
                or (#row.cells * (cfg.pipSize + cfg.pipSpacing) - cfg.pipSpacing)
            y = y + rowH + rowSpacing
            w = math.max(w, rowW)
        end
    end
    container:SetSize(math.max(w, 1), math.max(y - rowSpacing, 1))
    container:SetShown(#activeRows > 0)
    ApplyPosition()
    if E.Design and E.Design.Reattach then E.Design.Reattach() end   -- designer re-glues its overlay
end

-- ── Public surface (mirrors E.Layout.*; driven by Layout's Show/Hide hooks + the designer) ─────────
function R.EnsureShown()
    if shown then return end
    shown = true
    EnsureContainer()
    container:Show()
    RegisterSpecEvents()
    Rebuild()
end
function R.HideWidgets()
    if not shown then return end
    shown = false
    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    wipe(activeRows)
    UnregisterData()
    UnregisterSpec()
    if container then container:Hide() end
end
function R.IsShown() return shown and #activeRows > 0 end
function R.GetContainer() return container end
function R.ApplyPosition() ApplyPosition() end
function R.Rebuild() if shown then ScheduleSpecRebuild() end end   -- external nudge (config change) -> coalesced

-- ── Slash: /uucdmresources (toggle the enable flag) ───────────────────────────────────────────────
SLASH_UUCDMRESOURCES1 = "/uucdmresources"
SlashCmdList["UUCDMRESOURCES"] = function()
    if not E.Cfg then return end
    local on = not (E.Cfg.GetResource("enable") == true)
    E.Cfg.SetResource("enable", on)
    if shown then Rebuild() end
    Say("CDM resources: " .. (on and "ON" or "OFF") .. (shown and "" or "  (enable widgets with /uucdmwidgets)"))
end
