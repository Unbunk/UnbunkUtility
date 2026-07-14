-- Modules/CDMEngine/Display/ClassResource.lua
--
-- The CLASS-RESOURCE widget for the standalone CDM engine (ns.CDMEngine). Draws the current spec's
-- characteristic resources (combo points, holy power, essence, an energy/mana bar, runes, aura stacks,
-- stagger) in OUR OWN frames. Each detected resource is an INDEPENDENT bar: its own frame, its own
-- enable, its own anchor (a CDM group / the player frame / a below-player bucket / a Buff group / an
-- EARLIER resource bar), placement, X/Y offset and (for bar families) adapt-width. Config is keyed
-- per SPEC (each spec's ordered resources get their own bar settings; see Core/Config.lua GetBar/SetBar).
--
-- TAINT / SECRET: a SEPARATE event frame reads only game state (UnitPower/UnitPowerMax/UnitPartialPower
-- /aura stacks; Stagger is the one secret, issecretvalue-guarded) onto our own frames, so it can't taint
-- Blizzard's secure CDM handler. NO native-frame contact (never PlayerFrame/RuneFrame/... except reading
-- an anchor frame's geometry), NO hooksecurefunc. Per-cell OnUpdate only for essence + stagger (bounded).

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
E.Resource = E.Resource or {}
local R = E.Resource

local UnitPower, UnitPowerMax, UnitPartialPower = UnitPower, UnitPowerMax, UnitPartialPower
local issecretvalue = issecretvalue or function() return false end

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
local RUNE_COLOR       = { 0.15, 0.45, 0.62 }
local RUNE_READY_COLOR = { 0.20, 0.90, 1.00 }
local AURA_COLOR       = { 0.60, 0.80, 1.00 }

local function Cfg(key) return E.Cfg and E.Cfg.GetResource(key) end                  -- master flag (.enable)
local function Bar(specKey, i, key) return E.Cfg and E.Cfg.GetBar(specKey, i, key) end -- per-bar setting
local function Say(msg)
    if ns.Print then ns.Print(msg) else print("|cff338cff[UnbunkUtility]|r " .. tostring(msg)) end
end

-- ── State ─────────────────────────────────────────────────────────────────────────────────────
local shown = false
local bars = {}          -- [i] = bar frame (each holds ONE resource's row: bf.row = { family, desc, cells, ... })
local unlocked = {}      -- [i] = true while bar i is unlocked for dragging
local Rebuild, ScheduleSpecRebuild   -- forward-declared (used before their definitions)

-- ── Cell pool (our frames; a re-acquired frame MUST Show() — the pool gotcha) ────────────────────
local cellPool = {}
local function BuildCell()
    local c = CreateFrame("Frame", nil, UIParent)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0, 0, 0, 0.85)
    c.sb = CreateFrame("StatusBar", nil, c)
    c.sb:SetPoint("TOPLEFT", 1, -1)
    c.sb:SetPoint("BOTTOMRIGHT", -1, 1)
    c.sb:SetStatusBarTexture("Interface/Buttons/WHITE8X8")
    return c
end
local function AcquireCell(parent)
    local c = table.remove(cellPool) or BuildCell()
    c:SetParent(parent)
    c:Show()
    return c
end
local function ReleaseCell(c)
    c:SetScript("OnUpdate", nil)
    if c.sb and c.sb.SetTimerDuration then pcall(c.sb.SetTimerDuration, c.sb, nil) end
    c:Hide()
    c:ClearAllPoints()
    cellPool[#cellPool + 1] = c
end

-- ── Families: contract = setup(row, desc, cfg) + update(row) [+ teardown(row)] ──────────────────
-- Cells are parented to row.frame (the bar's OWN frame) at offset 0; the frame is positioned as a whole.
local Families = {}

Families.bar = {
    setup = function(row, desc, cfg)
        local c = row.cells[1]
        c:SetSize(cfg.barWidth, cfg.barHeight)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
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

Families.pips = {
    setup = function(row, desc, cfg)
        row.power, row.divisor = desc.power, desc.divisor or 1
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(ColorFor(desc.power))
            c.sb:SetMinMaxValues(0, row.divisor)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), 0)
        end
        Families.pips.update(row)
    end,
    update = function(row)
        if not row.power then return end
        local mx  = UnitPowerMax("player", row.power) or 0
        local cur = UnitPower("player", row.power, true) or 0
        if math.max(mx, 1) ~= #row.cells then ScheduleSpecRebuild(); return end
        local pips = mx
        local val  = cur / row.divisor
        local showEmpty = row.showEmpty ~= false
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

Families.essence = {
    setup = function(row, desc, cfg)
        row.power = desc.power
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(ColorFor(desc.power))
            c.sb:SetMinMaxValues(0, 1000)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), 0)
        end
        Families.essence.update(row)
    end,
    update = function(row)
        if not row.power then return end
        local mx  = UnitPowerMax("player", row.power) or 0
        local cur = UnitPower("player", row.power) or 0
        if math.max(mx, 1) ~= #row.cells then ScheduleSpecRebuild(); return end
        local showEmpty = row.showEmpty ~= false
        for i, c in ipairs(row.cells) do
            c:SetScript("OnUpdate", nil)
            if i > mx then
                c:Hide()
            elseif cur >= i then
                c:Show(); c.sb:SetValue(1000)
            elseif cur < i - 1 then
                c:SetShown(showEmpty); c.sb:SetValue(0)
            else
                c:Show()
                local p = UnitPartialPower and UnitPartialPower("player", row.power) or 0
                c.sb:SetValue(p)
                if UnitPartialPower then
                    local power = row.power
                    c:SetScript("OnUpdate", function(self)
                        local pp = UnitPartialPower("player", power)
                        local v = self.sb:GetValue()
                        if pp < v then self.sb:SetValue(1000); self:SetScript("OnUpdate", nil)
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

Families.runes = {
    setup = function(row, desc, cfg)
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(RUNE_COLOR[1], RUNE_COLOR[2], RUNE_COLOR[3])
            c.sb:SetMinMaxValues(0, 1)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), 0)
            c:Show()
        end
        Families.runes.update(row)
    end,
    update = function(row)
        if not GetRuneCooldown then return end
        local times = {}
        for i = 1, 6 do times[i] = { GetRuneCooldown(i) } end
        table.sort(times, function(a, b) return (a[1] or 0) < (b[1] or 0) end)
        for i, c in ipairs(row.cells) do
            local t = times[i]
            if not t then
                c:Hide()
            else
                local s, d, ready = t[1] or 0, t[2] or 0, t[3]
                c:Show()
                if c.sb.SetTimerDuration then pcall(c.sb.SetTimerDuration, c.sb, nil) end
                if ready then
                    c.sb:SetStatusBarColor(RUNE_READY_COLOR[1], RUNE_READY_COLOR[2], RUNE_READY_COLOR[3])
                    c.sb:SetMinMaxValues(0, 1); c.sb:SetValue(1)
                else
                    c.sb:SetStatusBarColor(RUNE_COLOR[1], RUNE_COLOR[2], RUNE_COLOR[3])
                    if s > 0 and d > 0 and c.sb.SetTimerDuration
                       and C_DurationUtil and C_DurationUtil.CreateDuration then
                        c.runeDur = c.runeDur or C_DurationUtil.CreateDuration()
                        if c.runeDur.SetTimeFromStart then
                            c.runeDur:SetTimeFromStart(s, d)
                            c.sb:SetTimerDuration(c.runeDur)
                        else
                            c.sb:SetValue(0)
                        end
                    else
                        c.sb:SetValue(0)
                    end
                end
            end
        end
    end,
}

Families.auraBar = {
    setup = function(row, desc, cfg)
        row.spellID, row.max = desc.spellID, desc.max or 1
        local c = row.cells[1]
        c:SetSize(cfg.barWidth, cfg.barHeight)
        c.sb:SetStatusBarColor(AURA_COLOR[1], AURA_COLOR[2], AURA_COLOR[3])
        c.sb:SetMinMaxValues(0, row.max)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
        Families.auraBar.update(row)
    end,
    update = function(row)
        if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID and row.spellID) then return end
        local a = C_UnitAuras.GetUnitAuraBySpellID("player", row.spellID)
        row.cells[1].sb:SetValue((a and a.applications) or 0)
    end,
}

Families.auraPips = {
    setup = function(row, desc, cfg)
        row.spellID, row.divisor = desc.spellID, desc.divisor or 1
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.pipSize, cfg.pipSize)
            c.sb:SetStatusBarColor(AURA_COLOR[1], AURA_COLOR[2], AURA_COLOR[3])
            c.sb:SetMinMaxValues(0, row.divisor)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.pipSize + cfg.pipSpacing), 0)
        end
        Families.auraPips.update(row)
    end,
    update = function(row)
        if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID and row.spellID) then return end
        local a = C_UnitAuras.GetUnitAuraBySpellID("player", row.spellID)
        local cur = (a and a.applications) or 0
        local val = cur / row.divisor
        local showEmpty = row.showEmpty ~= false
        for i, c in ipairs(row.cells) do
            if val >= i then c:Show(); c.sb:SetValue(row.divisor)
            elseif math.ceil(val) < i then c:SetShown(showEmpty); c.sb:SetValue(0)
            else c:Show(); c.sb:SetValue(cur % row.divisor) end
        end
    end,
}

local STAGGER_LIGHT, STAGGER_HEAVY = 0.30, 0.60
local STAGGER_COLORS = {
    light    = { 0.52, 1.00, 0.52 },
    moderate = { 1.00, 0.90, 0.45 },
    heavy    = { 1.00, 0.42, 0.42 },
}
Families.stagger = {
    setup = function(row, desc, cfg)
        local c = row.cells[1]
        c:SetSize(cfg.barWidth, cfg.barHeight)
        c.sb:SetMinMaxValues(0, 1)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
        c:SetScript("OnUpdate", function(self)
            local cur = UnitStagger and UnitStagger("player")
            if cur == nil or issecretvalue(cur) then return end
            local maxHP = UnitHealthMax("player")
            if not (maxHP and maxHP > 0) then self.sb:SetValue(0); return end
            local ratio = cur / maxHP
            self.sb:SetValue(ratio > 1 and 1 or ratio)
            local col = (ratio >= STAGGER_HEAVY and STAGGER_COLORS.heavy)
                or (ratio >= STAGGER_LIGHT and STAGGER_COLORS.moderate)
                or STAGGER_COLORS.light
            self.sb:SetStatusBarColor(col[1], col[2], col[3])
        end)
    end,
    update = function() end,
    teardown = function(row)
        for _, c in ipairs(row.cells) do c:SetScript("OnUpdate", nil) end
    end,
}

local BAR_FAMILIES = { bar = true, auraBar = true, stagger = true }

local function ReleaseRow(row)
    local fam = Families[row.family]
    if fam and fam.teardown then fam.teardown(row) end
    for _, c in ipairs(row.cells) do ReleaseCell(c) end
    wipe(row.cells)
end

local function CellCountFor(desc)
    if desc.family == "pips" then
        return math.max(UnitPowerMax("player", desc.power) or 0, 1)
    elseif desc.family == "essence" then
        return math.max(UnitPowerMax("player", desc.power) or 0, 1)
    elseif desc.family == "runes" then
        return 6
    elseif desc.family == "auraPips" then
        return math.max(desc.max or 1, 1)
    else
        return 1
    end
end

local function DescUsable(desc)
    if not (desc and Families[desc.family]) then return false end
    local f = desc.family
    if f == "bar" or f == "pips" or f == "essence" then return desc.power ~= nil end
    if f == "auraBar" or f == "auraPips" then return desc.spellID ~= nil end
    return true
end

-- ── Anchor + placement + adapt-width ─────────────────────────────────────────────────────────────
-- placement key -> { bar-frame point, anchor point } (where the bar sits vs the anchor).
local REL_POINTS = {
    above       = { "BOTTOM",      "TOP"         },
    below       = { "TOP",         "BOTTOM"      },
    left        = { "RIGHT",       "LEFT"        },
    right       = { "LEFT",        "RIGHT"       },
    topleft     = { "BOTTOMLEFT",  "TOPLEFT"     },
    topright    = { "BOTTOMRIGHT", "TOPRIGHT"    },
    bottomleft  = { "TOPLEFT",     "BOTTOMLEFT"  },
    bottomright = { "TOPRIGHT",    "BOTTOMRIGHT" },
}
R.REL_ORDER = { "above", "below", "left", "right", "topleft", "topright", "bottomleft", "bottomright" }
-- Anchor-to targets shared by "Anchor to" (+ the previous bars) and "Adapt to".
R.DEST_ORDER = { "essential", "utility", "belowPlayer", "belowFront", "belowEnd", "buff" }

local GROUP_CATKEY = { essential = "essential:1", utility = "utility:1", buff = "buff:1" }
-- Resolve an Essential/Utility/Buff dest to a live frame: the engine's OWN group frame in engine mode,
-- else the native CDMGroups/BuffGroups Group-1 container (falling back to the raw viewer).
local function GroupFrameFor(dest)
    if ns.CDMMode and ns.CDMMode.IsEngine() then
        local L = E.Layout
        local ef = L and L.GroupFrame and L.GroupFrame(GROUP_CATKEY[dest])
        if ef and ef.IsShown and ef:IsShown() and ef:GetLeft() then return ef end
        return nil
    end
    local inst = (dest == "buff") and ns.BuffGroups or (ns.CDMGroups and ns.CDMGroups[dest])
    local box  = inst and inst.GetContainer and inst.GetContainer(1)
    if box and box:IsShown() and box:GetLeft() then return box end
    if dest == "buff" then return _G.BuffIconCooldownViewer end
    return ns.GetCDMViewer and ns.GetCDMViewer(dest) or nil
end
-- "Below player frame" (plain) = the MIDDLE of the two below-player buckets: a helper frame spanning from
-- the front bucket's top-left to the end bucket's bottom-right, so its CENTRE is the row centre (front/end
-- anchor to the individual buckets). Follows the buckets live via SetPoint; nil until both buckets exist.
local belowMiddle
local function BelowMiddleFrame()
    local front = _G["UnbunkUtilityCDMBelowRow"]
    local endf  = _G["UnbunkUtilityCDMBelowRowEnd"]
    if not (front and endf) then return nil end
    if not belowMiddle then belowMiddle = CreateFrame("Frame", nil, UIParent) end
    belowMiddle:ClearAllPoints()
    belowMiddle:SetPoint("TOPLEFT",     front, "TOPLEFT",     0, 0)
    belowMiddle:SetPoint("BOTTOMRIGHT", endf,  "BOTTOMRIGHT", 0, 0)
    return belowMiddle
end
-- Resolve any anchor target (a CDM dest, a below-player bucket, the below-row middle, OR an earlier bar).
local function AnchorFrameFor(dest)
    if dest == "belowPlayer" then return BelowMiddleFrame() end
    if dest == "belowFront"  then return _G["UnbunkUtilityCDMBelowRow"] end
    if dest == "belowEnd"    then return _G["UnbunkUtilityCDMBelowRowEnd"] end
    local n = (type(dest) == "string") and dest:match("^bar(%d+)$")
    if n then return bars[tonumber(n)] end
    return GroupFrameFor(dest)
end

local function PositionBar(bf, specKey, i)
    local af  = AnchorFrameFor(Bar(specKey, i, "anchorTo"))
    local rel = REL_POINTS[Bar(specKey, i, "placement")] or REL_POINTS.above
    local px, py = Bar(specKey, i, "posX") or 0, Bar(specKey, i, "posY") or 0
    bf:ClearAllPoints()
    if af then bf:SetPoint(rel[1], af, rel[2], px, py)
    else       bf:SetPoint("CENTER", UIParent, "CENTER", px, py) end   -- anchor absent -> screen centre
end

-- The bar-family width, adapted to its "Adapt to" target's width when that target is present + sized.
local function AdaptedBarWidth(specKey, i)
    local base = Bar(specKey, i, "barWidth") or 200
    local af = AnchorFrameFor(Bar(specKey, i, "adaptTo"))
    local aw = af and af.GetWidth and af:GetWidth()
    if aw and aw > 1 then return aw end
    return base
end

-- ── Drag / unlock (per bar) ──────────────────────────────────────────────────────────────────────
-- Named point of a frame in screen pixels (scale folded in).
local function PointPx(frame, point)
    if not (frame and frame.GetLeft) then return nil end
    local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    local s = frame:GetEffectiveScale()
    if not (l and b and s) then return nil end
    local x = point:find("LEFT") and l or (point:find("RIGHT") and (l + w) or (l + w / 2))
    local y = point:find("BOTTOM") and b or (point:find("TOP") and (b + h) or (b + h / 2))
    return x * s, y * s
end
-- After a drag, derive posX/posY so PositionBar reproduces where the bar was dropped (relative to its anchor).
local function SaveDraggedPos(bf, specKey, i)
    local af  = AnchorFrameFor(Bar(specKey, i, "anchorTo")) or UIParent
    local rel = REL_POINTS[Bar(specKey, i, "placement")] or REL_POINTS.above
    local bx, by = PointPx(bf, rel[1])
    local ax, ay = PointPx(af, rel[2])
    local s = bf:GetEffectiveScale()
    if bx and ax and s and s > 0 and E.Cfg then
        E.Cfg.SetBar(specKey, i, "posX", math.floor((bx - ax) / s + 0.5))
        E.Cfg.SetBar(specKey, i, "posY", math.floor((by - ay) / s + 0.5))
    end
end
local function ApplyBarInteractivity(bf, specKey, i)
    if unlocked[i] then
        bf:SetMovable(true); bf:EnableMouse(true); bf:RegisterForDrag("LeftButton")
        bf:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
        bf:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SaveDraggedPos(self, specKey, i)
            PositionBar(self, specKey, i)
        end)
        if not bf._dragHi then bf._dragHi = bf:CreateTexture(nil, "OVERLAY"); bf._dragHi:SetAllPoints() end
        local r, g, b = 0.20, 0.55, 1
        if ns.GetBrandColor then r, g, b = ns.GetBrandColor() end
        bf._dragHi:SetColorTexture(r, g, b, 0.30); bf._dragHi:Show()
    else
        bf:SetMovable(false); bf:EnableMouse(false)
        bf:SetScript("OnDragStart", nil); bf:SetScript("OnDragStop", nil)
        if bf._dragHi then bf._dragHi:Hide() end
    end
end

-- ── Bar-frame pool ───────────────────────────────────────────────────────────────────────────────
local barPool = {}
local function BuildBarFrame()
    local bf = CreateFrame("Frame", nil, UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(bf) end
    bf:SetSize(1, 1)
    return bf
end
local function AcquireBarFrame()
    local bf = table.remove(barPool) or BuildBarFrame()
    bf:Show()
    return bf
end
local function ReleaseBarFrame(bf)
    if bf.row then ReleaseRow(bf.row); bf.row = nil end
    bf:SetScript("OnDragStart", nil); bf:SetScript("OnDragStop", nil)
    bf:SetMovable(false); bf:EnableMouse(false)
    if bf._dragHi then bf._dragHi:Hide() end
    bf:Hide()
    bf:ClearAllPoints()
    barPool[#barPool + 1] = bf
end
local function ReleaseAllBars()
    for _, bf in pairs(bars) do ReleaseBarFrame(bf) end
    wipe(bars)
end

-- ── DATA event frame (own frame; IconExtras taint pattern) ───────────────────────────────────────
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    for _, bf in pairs(bars) do
        local row = bf.row
        local fam = row and Families[row.family]
        if fam then fam.update(row) end
    end
end)
local registeredEvents = {}
local UNIT_SCOPED = {
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

-- ── SPEC-CHANGE firewall (trivial handler = flag + C_Timer.After(0); re-detect) ─────────────────────
local specQueued = false
local function DoSpecRebuild()
    specQueued = false
    if not shown then return end
    Rebuild()
end
function ScheduleSpecRebuild()
    if specQueued then return end
    specQueued = true
    C_Timer.After(0, DoSpecRebuild)
end
local specEv = CreateFrame("Frame")
specEv:SetScript("OnEvent", function() ScheduleSpecRebuild() end)
local function RegisterSpecEvents()
    for _, e in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_ENTERING_WORLD" }) do
        pcall(specEv.RegisterEvent, specEv, e)
    end
end
local function UnregisterSpec() specEv:UnregisterAllEvents() end

-- ── Build ────────────────────────────────────────────────────────────────────────────────────────
Rebuild = function()
    if not shown then return end
    ReleaseAllBars()
    UnregisterData()
    if not (Cfg("enable") == true) then return end   -- master OFF -> nothing

    local specKey = R.GetSpecKey()
    local labels  = R.Detect()
    for i = 1, #labels do
        if Bar(specKey, i, "enable") ~= false then
            local desc = R.REGISTRY[labels[i]]
            if DescUsable(desc) then
                local isBar = BAR_FAMILIES[desc.family] == true
                local cfg = {
                    barWidth  = isBar and AdaptedBarWidth(specKey, i) or (Bar(specKey, i, "barWidth") or 200),
                    barHeight = Bar(specKey, i, "barHeight") or 16,
                    pipSize   = Bar(specKey, i, "pipSize") or 22,
                    pipSpacing = Bar(specKey, i, "pipSpacing") or 3,
                }
                local bf  = AcquireBarFrame()
                local row = { family = desc.family, desc = desc, cells = {}, frame = bf,
                              showEmpty = Bar(specKey, i, "showEmpty") ~= false }
                bf.row = row
                for k = 1, CellCountFor(desc) do row.cells[k] = AcquireCell(bf) end
                Families[desc.family].setup(row, desc, cfg)
                RegisterFamilyEvents(desc.family)
                local rowW = isBar and cfg.barWidth
                    or (#row.cells * (cfg.pipSize + cfg.pipSpacing) - cfg.pipSpacing)
                local rowH = isBar and cfg.barHeight or cfg.pipSize
                bf:SetSize(math.max(rowW, 1), math.max(rowH, 1))
                bars[i] = bf                       -- register BEFORE positioning so a later bar can anchor to it
                PositionBar(bf, specKey, i)
                ApplyBarInteractivity(bf, specKey, i)
            end
        end
    end
end

-- Re-resolve anchors + re-adapt width WITHOUT rebuilding cells: the engine draws its groups into POOLED
-- frames (identity changes each rebuild), so a bar anchored to a group must re-point after an engine build.
local function RepositionAll()
    if not shown then return end
    local specKey = R.GetSpecKey()
    for i, bf in pairs(bars) do
        local row = bf.row
        if row then
            if BAR_FAMILIES[row.family] and row.cells[1] then
                local barW = AdaptedBarWidth(specKey, i)
                local barH = Bar(specKey, i, "barHeight") or 16
                row.cells[1]:SetSize(barW, barH)
                bf:SetSize(math.max(barW, 1), math.max(barH, 1))
            end
            PositionBar(bf, specKey, i)
            ApplyBarInteractivity(bf, specKey, i)
        end
    end
end

-- ── Public surface (driven by Layout's Show/Hide hooks + config edits + the engine's rebuild poke) ──
function R.EnsureShown()
    if shown then return end
    shown = true
    RegisterSpecEvents()
    Rebuild()
end
function R.HideWidgets()
    if not shown then return end
    shown = false
    ReleaseAllBars()
    UnregisterData()
    UnregisterSpec()
end
function R.IsShown() return shown and next(bars) ~= nil end
function R.Rebuild() if shown then ScheduleSpecRebuild() end end   -- config change -> coalesced full rebuild
function R.Reposition() RepositionAll() end                        -- engine build poke -> re-anchor only

-- Per-bar unlock (drag), driven by the config panel's Position sub-cadre.
function R.SetBarUnlocked(i, on)
    unlocked[i] = on and true or nil
    local bf = bars[i]
    if bf then ApplyBarInteractivity(bf, R.GetSpecKey(), i) end
end
function R.IsBarUnlocked(i) return unlocked[i] == true end

-- ── Slash: /uucdmresources (toggle the master enable flag) ──────────────────────────────────────────
SLASH_UUCDMRESOURCES1 = "/uucdmresources"
SlashCmdList["UUCDMRESOURCES"] = function()
    if not E.Cfg then return end
    local on = not (E.Cfg.GetResource("enable") == true)
    E.Cfg.SetResource("enable", on)
    if shown then Rebuild() end
    Say("CDM resources: " .. (on and "ON" or "OFF") .. (shown and "" or "  (enable widgets with /uucdmwidgets)"))
end
