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

-- ── Value / percent text (continuous "bar" resources, e.g. mana) ─────────────────────────────────
-- We render the continuous VALUE text DEFENSIVELY C-side (never touching the number in Lua) — exactly like
-- Ayije_CDM's Tags.lua: AbbreviateNumbers(v) -> "250K" ; FontString:SetFormattedText(fmt, v) consumes v ;
-- UnitPowerPercent(...) returns the % (we never divide cur/max ourselves). NOTE: plain UnitPower(...) COUNTS
-- (combo points, holy power, soul shards, essence, runes) are NOT secret here — this widget runs on its OWN
-- event frame (UNIT_POWER_*), not inside the CDM secure refresh — so the pip / essence families below do read
-- them in Lua. STAGGER is the one genuinely secret resource and is issecretvalue-guarded in its own family.
local AbbreviateNumbers = AbbreviateNumbers
local UnitPowerPercent  = UnitPowerPercent
local SCALE_TO_100      = CurveConstants and CurveConstants.ScaleTo100
local TEXT_ANCHOR = { left = { "LEFT", 3 }, center = { "CENTER", 0 }, right = { "RIGHT", -3 } }
local function PlaceText(fs, sb, pos)
    local a = TEXT_ANCHOR[pos] or TEXT_ANCHOR.center
    fs:ClearAllPoints()
    fs:SetPoint(a[1], sb, a[1], a[2], 0)
end
-- A per-row OVERLAY frame ABOVE the pip/bar cells: split dividers + value/percent text draw on top of the
-- fill (the cells are child frames = higher level than bf, so a texture on bf hides behind them). Within
-- bf.fx the draw order is OVERLAY sublevel 1 (dividers) < sublevel 5 (text) -> fill < dividers < text.
local function EnsureFX(bf)
    local fx = bf.fx
    if not fx then
        fx = CreateFrame("Frame", nil, bf)
        fx:SetAllPoints(bf)
        bf.fx = fx
    end
    fx:SetFrameLevel(bf:GetFrameLevel() + 10)   -- above the cells (bf+1) and their StatusBars (bf+2)
    return fx
end
-- Apply the configured font path / size / outline / colour to a text FontString, with a guard so a bad LSM
-- path can never leave it fontless (which would throw "Font not set" on SetText).
local DEFAULT_TEXT_FONT = ns._fontBasePath or "Fonts\\FRIZQT__.TTF"
local function StyleFS(fs, path, key, size, outline, color)
    local resolved = (ns.ResolveFontPath and ns.ResolveFontPath(path, key or "Fira Mono")) or path or DEFAULT_TEXT_FONT
    if not fs:SetFont(resolved, size or 12, outline or "OUTLINE") then
        fs:SetFont(DEFAULT_TEXT_FONT, size or 12, "")
    end
    if color then fs:SetTextColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    else fs:SetTextColor(1, 1, 1, 1) end
end
-- (Re)apply the value + percent FontStrings (on bf.fx, above the dividers) per the row's text config.
local function ApplyBarText(row)
    local bf = row.frame
    if not bf then return end
    -- Value/percent text is ONLY for the primary continuous power bar (family "bar", e.g. mana). Pips / aura /
    -- stagger must never show it — but showValueText defaults true and R.RefreshText calls this for EVERY row,
    -- so the family gate lives here: hide any leftover FontStrings for a non-"bar" row and bail.
    if row.family ~= "bar" then
        local pfx = bf.fx
        if pfx then
            if pfx.valueFS   then pfx.valueFS:Hide()   end
            if pfx.percentFS then pfx.percentFS:Hide() end
        end
        return
    end
    local fx = EnsureFX(bf)
    if row.showValueText then
        if not fx.valueFS then
            fx.valueFS = fx:CreateFontString(nil, "OVERLAY")
            fx.valueFS:SetDrawLayer("OVERLAY", 5)
        end
        StyleFS(fx.valueFS, row.valueFontPath, row.valueFontKey, row.valueFontSize, row.valueOutline, row.valueColor)
        PlaceText(fx.valueFS, bf, row.valueTextPos); fx.valueFS:Show()
    elseif fx.valueFS then fx.valueFS:Hide() end
    if row.showPercentText then
        if not fx.percentFS then
            fx.percentFS = fx:CreateFontString(nil, "OVERLAY")
            fx.percentFS:SetDrawLayer("OVERLAY", 5)
        end
        StyleFS(fx.percentFS, row.percentFontPath, row.percentFontKey, row.percentFontSize, row.percentOutline, row.percentColor)
        PlaceText(fx.percentFS, bf, row.percentTextPos); fx.percentFS:Show()
    elseif fx.percentFS then fx.percentFS:Hide() end
end
local function UpdateBarText(row, cur, mx)
    local fx = row.frame and row.frame.fx
    if not fx then return end
    if fx.valueFS and fx.valueFS:IsShown() then
        -- "cur/max" abbreviated. cur may be SECRET: AbbreviateNumbers consumes it C-side (proven by Ayije),
        -- but feeding the resulting (secret) string through %s is NOT proven — so try it, and if it can't
        -- render, fall back to the proven %d/%d (SetFormattedText takes a secret number directly). Text
        -- always shows and a %s failure can never crash the rebuild.
        local ok = pcall(fx.valueFS.SetFormattedText, fx.valueFS, "%s/%s",
            AbbreviateNumbers(cur or 0), AbbreviateNumbers(mx or 0))
        if not ok then fx.valueFS:SetFormattedText("%d/%d", cur or 0, mx or 0) end
    end
    if fx.percentFS and fx.percentFS:IsShown() then
        -- C-side percentage: NEVER compute cur/max in Lua (cur is secret). UnitPowerPercent returns 0..100.
        local pct = (UnitPowerPercent and row.power) and UnitPowerPercent("player", row.power, false, SCALE_TO_100) or 0
        fx.percentFS:SetFormattedText("%d%%", pct)
    end
end

-- ── Per-bar appearance: fill texture / fill colour / background texture / background colour ──────
-- All optional (nil = the built-in look). ResolveStatusbar falls back to solid WHITE8X8 (the historical
-- fill); SetFill only overrides the family/state colour when row.barColor is set; StyleCells paints the
-- background (nil bgTexture = a flat colour, defaulting to black 85%).
local LSM_RES = LibStub and LibStub("LibSharedMedia-3.0", true)
local function ResolveStatusbar(key)
    if key and key ~= "" and LSM_RES and LSM_RES:IsValid("statusbar", key) then
        return LSM_RES:Fetch("statusbar", key)
    end
    return "Interface/Buttons/WHITE8X8"
end
local function SetFill(row, sb, r, g, b)
    local oc = row.barColor
    if oc then sb:SetStatusBarColor(oc.r or 1, oc.g or 1, oc.b or 1) else sb:SetStatusBarColor(r, g, b) end
end
-- Paint every cell's fill texture + background. Runs once per (re)build AFTER the family sized/placed the
-- cells; pooled cells are ALWAYS fully re-styled here so no stale texture survives a reuse.
local function StyleCells(row, cfg)
    local barTex = ResolveStatusbar(cfg.barTexture)
    local bgTex  = (cfg.bgTexture and cfg.bgTexture ~= "" and LSM_RES and LSM_RES:IsValid("statusbar", cfg.bgTexture))
                   and LSM_RES:Fetch("statusbar", cfg.bgTexture) or nil
    local bg     = cfg.bgColor
    for _, c in ipairs(row.cells) do
        c.sb:SetStatusBarTexture(barTex)
        if bgTex then
            c.bg:SetTexture(bgTex)
            if bg then c.bg:SetVertexColor(bg.r or 1, bg.g or 1, bg.b or 1, bg.a or 1)
            else c.bg:SetVertexColor(1, 1, 1, 1) end
        elseif bg then
            c.bg:SetColorTexture(bg.r or 0, bg.g or 0, bg.b or 0, bg.a or 0.85)
        else
            c.bg:SetColorTexture(0, 0, 0, 0.85)
        end
    end
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
        SetFill(row, c.sb, ColorFor(desc.power))
        ApplyBarText(row)
        Families.bar.update(row)
    end,
    update = function(row)
        if not row.power then return end
        local sb  = row.cells[1].sb
        local mx  = UnitPowerMax("player", row.power)
        local cur = UnitPower("player", row.power)
        sb:SetMinMaxValues(0, (mx and mx > 0) and mx or 1)
        sb:SetValue(cur or 0)              -- fill: secret-safe C-side
        UpdateBarText(row, cur, mx)        -- text: C-side formatters (secret-safe), see UpdateBarText
    end,
}

Families.pips = {
    setup = function(row, desc, cfg)
        row.power, row.divisor = desc.power, desc.divisor or 1
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.barWidth / math.max(#row.cells, 1), cfg.barHeight)
            SetFill(row, c.sb, ColorFor(desc.power))
            c.sb:SetMinMaxValues(0, row.divisor)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.barWidth / math.max(#row.cells, 1)), 0)
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

-- Hoisted so a filling-essence pip doesn't allocate a fresh OnUpdate closure on every UNIT_POWER_UPDATE;
-- the cell stores its power token on itself and this shared handler reads it.
local function EssencePipOnUpdate(self)
    local pp = UnitPartialPower("player", self._essPower)
    local v  = self.sb:GetValue()
    if pp < v then self.sb:SetValue(1000); self:SetScript("OnUpdate", nil)
    elseif pp ~= v then self.sb:SetValue(pp) end
end

Families.essence = {
    setup = function(row, desc, cfg)
        row.power = desc.power
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.barWidth / math.max(#row.cells, 1), cfg.barHeight)
            SetFill(row, c.sb, ColorFor(desc.power))
            c.sb:SetMinMaxValues(0, 1000)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.barWidth / math.max(#row.cells, 1)), 0)
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
                    c._essPower = row.power
                    c:SetScript("OnUpdate", EssencePipOnUpdate)   -- hoisted: no per-event closure alloc
                end
            end
        end
    end,
    teardown = function(row)
        for _, c in ipairs(row.cells) do c:SetScript("OnUpdate", nil) end
    end,
}

-- Hoisted scratch (6 preallocated slots) + comparator so runes.update sorts by cooldown each
-- RUNE_POWER_UPDATE without allocating a fresh table + 6 sub-tables + a closure per event. The slot
-- sub-tables never escape the function; each call overwrites all six in place before sorting.
local runeTimes = { {}, {}, {}, {}, {}, {} }
local function RuneTimeLess(a, b) return (a[1] or 0) < (b[1] or 0) end

Families.runes = {
    setup = function(row, desc, cfg)
        for i, c in ipairs(row.cells) do
            c:SetSize(cfg.barWidth / math.max(#row.cells, 1), cfg.barHeight)
            SetFill(row, c.sb, RUNE_COLOR[1], RUNE_COLOR[2], RUNE_COLOR[3])
            c.sb:SetMinMaxValues(0, 1)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.barWidth / math.max(#row.cells, 1)), 0)
            c:Show()
        end
        Families.runes.update(row)
    end,
    update = function(row)
        if not GetRuneCooldown then return end
        for i = 1, 6 do
            local t = runeTimes[i]
            t[1], t[2], t[3] = GetRuneCooldown(i)
        end
        table.sort(runeTimes, RuneTimeLess)
        for i, c in ipairs(row.cells) do
            local t = runeTimes[i]
            if not t then
                c:Hide()
            else
                local s, d, ready = t[1] or 0, t[2] or 0, t[3]
                c:Show()
                if c.sb.SetTimerDuration then pcall(c.sb.SetTimerDuration, c.sb, nil) end
                if ready then
                    SetFill(row, c.sb, RUNE_READY_COLOR[1], RUNE_READY_COLOR[2], RUNE_READY_COLOR[3])
                    c.sb:SetMinMaxValues(0, 1); c.sb:SetValue(1)
                else
                    SetFill(row, c.sb, RUNE_COLOR[1], RUNE_COLOR[2], RUNE_COLOR[3])
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
        SetFill(row, c.sb, AURA_COLOR[1], AURA_COLOR[2], AURA_COLOR[3])
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
            c:SetSize(cfg.barWidth / math.max(#row.cells, 1), cfg.barHeight)
            SetFill(row, c.sb, AURA_COLOR[1], AURA_COLOR[2], AURA_COLOR[3])
            c.sb:SetMinMaxValues(0, row.divisor)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row.frame, "TOPLEFT", (i - 1) * (cfg.barWidth / math.max(#row.cells, 1)), 0)
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
            SetFill(row, self.sb, col[1], col[2], col[3])
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

-- Resolve an Essential/Utility/Buff/Bar dest — now a per-group key ("essential:2" / …) or a legacy plain
-- type (-> group 1) — to a live frame: the engine's OWN group frame in engine mode, else the native module's
-- per-group container (falling back to the raw viewer).
local function GroupFrameFor(dest)
    if not ns.ParseCDMGroupKey then return nil end
    local d, id = ns.ParseCDMGroupKey(dest)   -- NOT `(X and X())`: parens/`and` truncate multi-returns -> id=nil
    if not d then return nil end
    if ns.CDMMode and ns.CDMMode.IsEngine() then
        local L = E.Layout
        local ef = L and L.GroupFrame and L.GroupFrame(d .. ":" .. id)
        if ef and ef.IsShown and ef:IsShown() and ef:GetLeft() then return ef end
        return nil
    end
    local inst = (d == "buff" and ns.BuffGroups) or (d == "bar" and ns.BarGroups) or (ns.CDMGroups and ns.CDMGroups[d])
    local box  = inst and inst.GetContainer and inst.GetContainer(id)
    if box and box:IsShown() and box:GetLeft() then return box end
    if d == "buff" then return _G.BuffIconCooldownViewer end
    return ns.GetCDMViewer and ns.GetCDMViewer(d) or nil
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
-- Highest currently-drawn bar index (the "Last bar" / "resbar:last" target).
local function LastBarIndex()
    local last
    for i in pairs(bars) do if not last or i > last then last = i end end
    return last
end
-- Resolve any anchor target (a CDM dest, a below-player bucket, the below-row middle, OR a resource bar:
-- "resbar:<i>" / "resbar:last", plus the legacy "bar<i>" key). Intra-module -> the live pooled bar frame.
local function AnchorFrameFor(dest)
    if dest == "belowPlayer" then return BelowMiddleFrame() end
    if dest == "belowFront"  then return _G["UnbunkUtilityCDMBelowRow"] end
    if dest == "belowEnd"    then return _G["UnbunkUtilityCDMBelowRowEnd"] end
    if type(dest) == "string" then
        local sub = dest:match("^resbar:(.+)$")
        if sub then
            if sub == "last" then local li = LastBarIndex(); return li and bars[li] or nil end
            return bars[tonumber(sub)]
        end
        local n = dest:match("^bar(%d+)$")   -- legacy per-bar key
        if n then return bars[tonumber(n)] end
    end
    return GroupFrameFor(dest)
end

local function PositionBar(bf, specKey, i)
    local af  = AnchorFrameFor(Bar(specKey, i, "anchorTo"))
    if af == bf then af = nil end   -- a bar must NEVER anchor to itself (resbar:last after a shrink, or legacy bar<i>); WoW errors on self-SetPoint
    local rel = REL_POINTS[Bar(specKey, i, "placement")] or REL_POINTS.above
    local px, py = Bar(specKey, i, "posX") or 0, Bar(specKey, i, "posY") or 0
    bf:ClearAllPoints()
    if af then bf:SetPoint(rel[1], af, rel[2], px, py)
    else       bf:SetPoint("CENTER", UIParent, "CENTER", px, py) end   -- anchor absent -> screen centre
end

-- The bar-family width, adapted to its "Adapt to" target's width when that target is present + sized.
local function AdaptedBarWidth(specKey, i)
    local base = Bar(specKey, i, "barWidth") or 200
    if Bar(specKey, i, "adaptWidth") ~= true then return base end   -- fixed width unless "Adapt width to" is on
    local af = AnchorFrameFor(Bar(specKey, i, "adaptTo"))
    local aw = af and af.GetWidth and af:GetWidth()
    if aw and aw > 1 then return aw end
    return base
end

-- ── Shared cross-module anchor targets (resource bars as anchor points for OTHER modules) ─────────
-- The bar frames are POOLED (identity changes each rebuild), so external modules anchor to PERSISTENT
-- proxy handles that SetAllPoints() the live bar (following its moves/resizes); only the (re)link happens
-- on rebuild, after which we poke the consumers so a bar that appeared/disappeared is re-resolved. Keys are
-- "resbar:<i>" / "resbar:last"; the resolver returns nil while a bar is absent (caller keeps its fallback).
local anchorHandles = {}
local function HandleFrame(sub)
    local h = anchorHandles[sub]
    if not h then h = CreateFrame("Frame", nil, UIParent); anchorHandles[sub] = h end
    return h
end
local function UpdateAnchorHandles()
    for _, h in pairs(anchorHandles) do h:ClearAllPoints(); h:Hide() end
    for i, bf in pairs(bars) do local h = HandleFrame(i); h:SetAllPoints(bf); h:Show() end
    local li = LastBarIndex()
    if li then local h = HandleFrame("last"); h:SetAllPoints(bars[li]); h:Show() end
end
local notifyQueued = false
local function NotifyAnchorConsumers()   -- deferred + coalesced: off any co-fire, taint-safe
    if notifyQueued then return end
    notifyQueued = true
    C_Timer.After(0, function()
        notifyQueued = false
        if E.Layout   and E.Layout.ReapplyPositions   then E.Layout.ReapplyPositions() end   -- engine groups riding a bar
        if ns.CastBar    and ns.CastBar.NotifyAnchorChanged then ns.CastBar.NotifyAnchorChanged() end
        if ns.BuffGroups and ns.BuffGroups.RefreshLayout    then ns.BuffGroups.RefreshLayout() end   -- native mode
        if ns.BarGroups  and ns.BarGroups.RefreshLayout     then ns.BarGroups.RefreshLayout() end    -- native mode
    end)
end
-- key ("resbar:<i>"/"resbar:last") -> the stable proxy handle, or nil if that bar isn't currently drawn.
function R.AnchorFrameForKey(key)
    local sub = (type(key) == "string") and key:match("^resbar:(.+)$")
    if not sub then return nil end
    if sub ~= "last" then sub = tonumber(sub) end
    local h = anchorHandles[sub]
    if h and h:IsShown() then return h end
    return nil
end
-- Ordered {key,label} anchor targets for the CURRENT spec ("Last bar" first, then "1: Name", "2: Name", ...).
-- Cached in module-level scratch: the Fader hover driver calls this every tick, and the list only changes on
-- spec / bar-count change. atSpec is force-invalidated from the spec-change path so a swap always rebuilds.
-- Callers (Fader hover, ConfigWindow) copy .key/.label immediately, so handing back a reused table is safe.
local atCache, atSpec = {}, nil
function R.AnchorTargets()
    local spec, labels = R.GetSpecKey(), R.Detect()
    local n = (type(labels) == "table") and #labels or 0
    if n == 0 then
        if #atCache > 0 then wipe(atCache) end
        atSpec = spec
        return atCache
    end
    if spec == atSpec and #atCache == n + 1 then return atCache end   -- unchanged -> reuse in place
    atSpec = spec
    for i = #atCache, n + 2, -1 do atCache[i] = nil end   -- shrank -> drop the tail
    atCache[1] = atCache[1] or {}
    atCache[1].key   = "resbar:last"
    atCache[1].label = (ns.L and ns.L["Last bar"]) or "Last bar"
    for i = 1, n do
        local e = atCache[i + 1]
        if not e then e = {}; atCache[i + 1] = e end   -- only allocate when the list grows
        e.key   = "resbar:" .. i
        e.label = i .. ": " .. tostring(labels[i])
    end
    return atCache
end
-- ns-level shims so other modules don't reach into E.Resource internals.
ns.ResourceBarAnchorTargets = function() return R.AnchorTargets() end
ns.ResolveResourceBarFrame  = function(key) return R.AnchorFrameForKey(key) end
ns.IsResourceBarAnchorKey   = function(key) return type(key) == "string" and key:match("^resbar:") ~= nil end

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
    local af  = AnchorFrameFor(Bar(specKey, i, "anchorTo"))
    if af == bf then af = nil end   -- mirror PositionBar: never measure the bar against itself
    af = af or UIParent
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

-- ── Split dividers (a line between pips / segment lines on a continuous bar) ────────────────────
local BAR_SEGMENTS = 4   -- a continuous "split" bar is cut into this many even segments (e.g. mana)
local function HideDividers(bf)
    if bf._dividers then for _, d in ipairs(bf._dividers) do d:Hide() end end
end
local function Divider(bf, k)
    local fx = EnsureFX(bf)                           -- on the overlay -> above the pip/bar fill
    bf._dividers = bf._dividers or {}
    local d = bf._dividers[k]
    if not d then d = fx:CreateTexture(nil, "OVERLAY", nil, 1); bf._dividers[k] = d end
    d:SetColorTexture(0, 0, 0, 0.9)
    return d
end
-- Place divider k centred at `centerOff` UI-units from bf's LEFT, PIXEL-SNAPPED so EVERY divider renders the
-- SAME width: the physical width is an integer number of screen pixels and the left edge lands on the pixel
-- grid. Otherwise a 2px line at a fractional sub-pixel (common at non-integer UI scale) rasterises as 1 or 3
-- px — that's the "some splits thicker than others" artefact. Needs bf positioned (call AFTER PositionBar).
local function PlaceDivider(bf, k, centerOff, thick, h)
    local d = Divider(bf, k)
    local s = bf:GetEffectiveScale() or 1
    local physW = math.max(1, math.floor((thick or 1) + 0.5))   -- thickness IS physical px (so 1 vs 2 differ at any UI scale)
    d:ClearAllPoints()
    d:SetHeight(math.max(h or 1, 1))
    local bfLeft = bf:GetLeft()
    if bfLeft and s > 0 then
        -- Snap BOTH edges to integer physical pixels (LEFT + RIGHT points), so every divider is EXACTLY physW px
        -- wide. Snapping only the left edge + a fractional SetSize width leaves the RIGHT edge sub-pixel (float
        -- error in physW/s * s), which rasterises one line a touch thinner than the rest.
        local leftPx = math.floor((bfLeft + centerOff) * s + 0.5) - math.floor(physW / 2)
        d:SetPoint("LEFT",  bf, "LEFT", leftPx / s - bfLeft, 0)
        d:SetPoint("RIGHT", bf, "LEFT", (leftPx + physW) / s - bfLeft, 0)
    else
        d:SetWidth(physW / s)                                                -- not laid out yet -> unsnapped
        d:SetPoint("CENTER", bf, "LEFT", centerOff, 0)
    end
    d:Show()
end
local function ApplySplit(row)
    local bf = row.frame
    HideDividers(bf)
    if not row.showSplit then return end
    local thick = math.max(row.splitThickness or 1, 1)
    local w, h  = bf:GetWidth(), bf:GetHeight()
    if BAR_FAMILIES[row.family] then                 -- continuous bar
        local mx = row.power and UnitPowerMax("player", row.power)
        if mx and mx > 0 then
            -- Resource-based: a divider every (splitUnit / splitCount) of the power, positioned by amount.
            local per  = math.max(row.splitCount or 2, 1)
            local unit = row.splitUnit or 50000
            local step = (unit > 0) and (unit / per) or mx
            local k, res = 1, step
            while res < mx and k <= 64 do            -- cap: never draw a runaway number of dividers
                PlaceDivider(bf, k, w * (res / mx), thick, h)
                k, res = k + 1, res + step
            end
        elseif row.max and row.max > 1 then          -- aura-STACK bar (e.g. icicles): a divider at each stack
            for k = 1, row.max - 1 do                --   boundary so the segments match the max stack count
                PlaceDivider(bf, k, w * k / row.max, thick, h)
            end
        else                                         -- stagger (continuous %) -> even fallback segments
            for k = 1, BAR_SEGMENTS - 1 do
                PlaceDivider(bf, k, w * k / BAR_SEGMENTS, thick, h)
            end
        end
    else                                             -- pips -> a divider centred on each REAL pip edge (anchored
        local s   = bf:GetEffectiveScale() or 1      -- to the cell, so it always lines up with the pip — a
        local wUI = math.max(1, math.floor(thick + 0.5)) / s   -- computed+snapped offset drifted ~1px off it)
        for k = 1, #row.cells - 1 do
            local d = Divider(bf, k)
            d:SetSize(wUI, math.max(h, 1))
            d:ClearAllPoints()
            d:SetPoint("CENTER", row.cells[k], "RIGHT", 0, 0)
            d:Show()
        end
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
    bf:SetAlpha(1)   -- clear any stale fade alpha from a pooled/reused bar (the Fader can fade class resources)
    bf:Show()
    return bf
end
local function ReleaseBarFrame(bf)
    if bf.row then ReleaseRow(bf.row); bf.row = nil end
    bf:SetScript("OnDragStart", nil); bf:SetScript("OnDragStop", nil)
    bf:SetMovable(false); bf:EnableMouse(false)
    if bf._dragHi then bf._dragHi:Hide() end
    HideDividers(bf)
    if bf.fx then
        if bf.fx.valueFS   then bf.fx.valueFS:Hide()   end
        if bf.fx.percentFS then bf.fx.percentFS:Hide() end
    end
    bf:Hide()
    bf:ClearAllPoints()
    barPool[#barPool + 1] = bf
end
local function ReleaseAllBars()
    for _, bf in pairs(bars) do ReleaseBarFrame(bf) end
    wipe(bars)
end

-- Append every live resource-bar frame to `out`. The Fader uses this to fade the class-resource bars WITH the
-- CDM (fading a bar frame cascades to its cells + text; nothing re-forces a bar's alpha). Live pool — the Fader
-- enumerates every tick, so this never caches.
function R.CollectBars(out, fg)
    out = out or {}
    for i, bf in pairs(bars) do
        -- fg (optional per-bar fade-scope table): a "resbar:i" key set to false is EXCLUDED from the fade.
        if not fg or fg["resbar:" .. i] ~= false then out[#out + 1] = bf end
    end
    return out
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
    atSpec = nil   -- force R.AnchorTargets to rebuild even if the label count is unchanged across the swap/talent change
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
                local cfg = {
                    barWidth  = AdaptedBarWidth(specKey, i),   -- adapts to adaptTo when adaptWidth is on, else fixed
                    barHeight = Bar(specKey, i, "barHeight") or 16,
                    barTexture = Bar(specKey, i, "barTexture"),   -- LSM statusbar (nil = solid WHITE8X8)
                    bgTexture  = Bar(specKey, i, "bgTexture"),    -- LSM statusbar (nil = flat colour background)
                    bgColor    = Bar(specKey, i, "bgColor"),      -- {r,g,b,a} (nil = black 85%)
                }
                local bf  = AcquireBarFrame()
                local ss  = Bar(specKey, i, "showSplit")
                if ss == nil then ss = (desc.family ~= "bar") end   -- primary "bar" bars default split OFF; pips ON
                local row = { family = desc.family, desc = desc, cells = {}, frame = bf,
                              barColor = Bar(specKey, i, "barColor"),   -- per-bar fill colour override ({r,g,b,a}; nil = family/state colour)
                              showEmpty = Bar(specKey, i, "showEmpty") ~= false,
                              showSplit = ss == true,
                              showValueText   = Bar(specKey, i, "showValueText")   == true,
                              valueTextPos    = Bar(specKey, i, "valueTextPos")    or "center",
                              showPercentText = Bar(specKey, i, "showPercentText") == true,
                              percentTextPos  = Bar(specKey, i, "percentTextPos")  or "center",
                              splitUnit       = Bar(specKey, i, "splitUnit")  or 50000,
                              splitCount      = Bar(specKey, i, "splitCount") or 2,
                              splitThickness  = Bar(specKey, i, "splitThickness") or 1,
                              valueFontKey    = Bar(specKey, i, "valueFontKey")   or "Fira Mono",
                              valueFontPath   = Bar(specKey, i, "valueFontPath"),
                              valueFontSize   = Bar(specKey, i, "valueFontSize")   or 12,
                              valueOutline    = Bar(specKey, i, "valueOutline")    or "OUTLINE",
                              valueColor      = Bar(specKey, i, "valueColor"),
                              percentFontKey  = Bar(specKey, i, "percentFontKey")  or "Fira Mono",
                              percentFontPath = Bar(specKey, i, "percentFontPath"),
                              percentFontSize = Bar(specKey, i, "percentFontSize") or 12,
                              percentOutline  = Bar(specKey, i, "percentOutline")  or "OUTLINE",
                              percentColor    = Bar(specKey, i, "percentColor") }
                bf.row = row
                for k = 1, CellCountFor(desc) do row.cells[k] = AcquireCell(bf) end
                StyleCells(row, cfg)               -- paint fill texture + bg FIRST: SetStatusBarTexture RESETS the fill colour to white
                Families[desc.family].setup(row, desc, cfg)   -- family SetFill re-colours AFTER, so the family/state colour wins over that reset
                RegisterFamilyEvents(desc.family)
                -- Both bars AND pips fill barWidth x barHeight (pips = N equal segments of it).
                bf:SetSize(math.max(cfg.barWidth, 1), math.max(cfg.barHeight, 1))
                bars[i] = bf                       -- register BEFORE positioning so a later bar can anchor to it
                PositionBar(bf, specKey, i)
                ApplySplit(row)                    -- AFTER PositionBar: needs bf:GetLeft() for pixel-snapping
                ApplyBarInteractivity(bf, specKey, i)
            end
        end
    end
    UpdateAnchorHandles()      -- relink the stable proxies to the fresh (pooled) bar frames
    NotifyAnchorConsumers()    -- a bar may have appeared/disappeared -> re-anchor external consumers
end

-- Re-resolve anchors + re-adapt width WITHOUT rebuilding cells: the engine draws its groups into POOLED
-- frames (identity changes each rebuild), so a bar anchored to a group must re-point after an engine build.
local function RepositionAll()
    if not shown then return end
    local specKey = R.GetSpecKey()
    for i, bf in pairs(bars) do
        local row = bf.row
        if row then
            local barW = AdaptedBarWidth(specKey, i)
            local barH = Bar(specKey, i, "barHeight") or 16
            bf:SetSize(math.max(barW, 1), math.max(barH, 1))
            if BAR_FAMILIES[row.family] and row.cells[1] then
                row.cells[1]:SetSize(barW, barH)
            else                                 -- pips: re-fill the (possibly adapted) width across the cells
                local n = math.max(#row.cells, 1)
                local pw = barW / n
                for k, c in ipairs(row.cells) do
                    c:SetSize(pw, barH)
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", bf, "TOPLEFT", (k - 1) * pw, 0)
                end
            end
            PositionBar(bf, specKey, i)
            ApplySplit(row)   -- AFTER PositionBar so dividers pixel-snap to the bar's SETTLED screen position
            ApplyBarInteractivity(bf, specKey, i)
        end
    end
    UpdateAnchorHandles()      -- bars were re-anchored/-sized -> keep the proxies glued to them
    NotifyAnchorConsumers()    -- re-pin any engine group / cast bar riding a bar to the settled positions
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
    UpdateAnchorHandles()      -- bars gone -> hide the proxies
    NotifyAnchorConsumers()    -- external consumers fall back (resource anchors now absent)
end
function R.IsShown() return shown and next(bars) ~= nil end
function R.Rebuild() if shown then ScheduleSpecRebuild() end end   -- config change -> coalesced full rebuild
function R.Reposition() RepositionAll() end                        -- engine build poke -> re-anchor only

-- Light re-style of the value/percent TEXT only (font / size / outline / colour / position / show) without a
-- full rebuild — cheap enough for the colour swatch's LIVE drag. Re-reads the text config into each row.
function R.RefreshText()
    if not shown then return end
    local specKey = R.GetSpecKey()
    for i, bf in pairs(bars) do
        local row = bf.row
        if row then
            row.showValueText   = Bar(specKey, i, "showValueText")   == true
            row.valueTextPos    = Bar(specKey, i, "valueTextPos")    or "center"
            row.valueFontKey    = Bar(specKey, i, "valueFontKey")    or "Fira Mono"
            row.valueFontPath   = Bar(specKey, i, "valueFontPath")
            row.valueFontSize   = Bar(specKey, i, "valueFontSize")   or 12
            row.valueOutline    = Bar(specKey, i, "valueOutline")    or "OUTLINE"
            row.valueColor      = Bar(specKey, i, "valueColor")
            row.showPercentText = Bar(specKey, i, "showPercentText") == true
            row.percentTextPos  = Bar(specKey, i, "percentTextPos")  or "center"
            row.percentFontKey  = Bar(specKey, i, "percentFontKey")  or "Fira Mono"
            row.percentFontPath = Bar(specKey, i, "percentFontPath")
            row.percentFontSize = Bar(specKey, i, "percentFontSize") or 12
            row.percentOutline  = Bar(specKey, i, "percentOutline")  or "OUTLINE"
            row.percentColor    = Bar(specKey, i, "percentColor")
            ApplyBarText(row)
            if BAR_FAMILIES[row.family] and row.power then
                UpdateBarText(row, UnitPower("player", row.power), UnitPowerMax("player", row.power))
            end
        end
    end
end

-- Light re-style of the fill TEXTURE + BACKGROUND + fill-colour override without a full rebuild — cheap
-- enough for the colour swatch's LIVE drag (mirrors RefreshText). Re-reads the appearance config into each
-- row and re-applies it to the existing cells. NOTE: a CLEARED barColor (revert to the family/state colour)
-- still needs a full rebuild, but the swatch only ever SETS a colour, so live drag stays smooth here.
function R.RefreshStyle()
    if not shown then return end
    local specKey = R.GetSpecKey()
    for i, bf in pairs(bars) do
        local row = bf.row
        if row then
            row.barColor = Bar(specKey, i, "barColor")
            StyleCells(row, {
                barTexture = Bar(specKey, i, "barTexture"),
                bgTexture  = Bar(specKey, i, "bgTexture"),
                bgColor    = Bar(specKey, i, "bgColor"),
            })
            -- StyleCells' SetStatusBarTexture reset the fill to white -> re-apply the EFFECTIVE fill colour
            -- (per-bar override OR the family default) for the DEFAULT (unset barColor) case too, not only when
            -- an override is set. Runes/stagger further self-correct to their live state on the next data event.
            local fc = row.barColor or R.DefaultFillColor(i)
            if fc then
                for _, c in ipairs(row.cells) do
                    c.sb:SetStatusBarColor(fc.r or 1, fc.g or 1, fc.b or 1)
                end
            end
        end
    end
end

-- The default FILL colour a bar renders when barColor is UNSET — so the config swatch can display it (mana
-- blue, etc.) instead of blank. A single representative colour for the multi-state families (runes / aura /
-- stagger). Reads the CURRENT spec's resource for bar `i` (the config panel is always current-spec).
function R.DefaultFillColor(i)
    local labels = R.Detect()
    local desc   = labels and labels[i] and R.REGISTRY[labels[i]]
    if not desc then return { r = 0.6, g = 0.6, b = 0.6, a = 1 } end
    local fam = desc.family
    if fam == "runes" then
        return { r = RUNE_COLOR[1], g = RUNE_COLOR[2], b = RUNE_COLOR[3], a = 1 }
    elseif fam == "auraBar" or fam == "auraPips" then
        return { r = AURA_COLOR[1], g = AURA_COLOR[2], b = AURA_COLOR[3], a = 1 }
    elseif fam == "stagger" then
        local col = STAGGER_COLORS.light
        return { r = col[1], g = col[2], b = col[3], a = 1 }
    end
    local r, g, b = ColorFor(desc.power)
    return { r = r, g = g, b = b, a = 1 }
end

-- Profile change / import / RESET re-runs the reload hooks: fully REBUILD the bars so a wiped/loaded config
-- actually repaints (a Reposition alone would keep the stale split / size / text). Coalesced.
ns.RegisterReloadHook(function() if shown then ScheduleSpecRebuild() end end)

-- Per-bar unlock (drag), driven by the config panel's Position sub-cadre.
function R.SetBarUnlocked(i, on)
    unlocked[i] = on and true or nil
    local bf = bars[i]
    if bf then ApplyBarInteractivity(bf, R.GetSpecKey(), i) end
end
function R.IsBarUnlocked(i) return unlocked[i] == true end
