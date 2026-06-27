-- Modules/CDMGroups/Core/CooldownFormatter.lua
-- Native-countdown TEXT formatter for the CDM rows, built on C_StringUtil.CreateNumericRuleFormatter and
-- installed via Cooldown:SetCountdownFormatter (in Engine.StyleFrame). The engine formats the number C-side
-- from the cooldown's own (possibly SECRET in combat) duration, so this is the timer-text analogue of the
-- C_StringUtil.TruncateWhenZero charge fix.
--
-- It does two things, BOTH per-icon (read via I.IconGet, override -> group), driven by the SAME Timer-cadre
-- config the icon already has — there is NO separate colour setting:
--   * DECIMALS under timerDecimalThreshold seconds (+ mm:ss / h / d rollover).
--   * The "Enable time thresholds" urgency COLOURS (timerThresholds {time,size,color}) as MULTI-TIER colour
--     breakpoints (e.g. yellow under 15s, red under 5s). Applied C-side, they STAY CORRECT IN COMBAT, unlike
--     our Lua FrameRemaining tier path (which reads remaining and goes nil on a secret cooldown). The tier
--     SIZE scaling can't be reproduced here (a formatter never touches the font), so size stays on the Lua
--     path (out of combat only); colour now survives combat.
-- OFF for an icon when decimals 0 AND thresholds disabled -> GetFor returns nil -> native default formatting.
-- Adapted from Ayije_CDM Core/CooldownFormatter (generalised from one colour threshold to the tier list).

local _, ns = ...
ns.CDMGroups = ns.CDMGroups or {}
local CF = {}
ns.CDMGroups.CooldownFormatter = CF

local CreateNumericRuleFormatter = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter

-- Clone a breakpoint AT a new threshold so a colour boundary can split a base range exactly.
local function CloneAt(src, threshold)
    local copy = { threshold = threshold, format = src.format, rounding = src.rounding,
        step = src.step, min = src.min, max = src.max }
    if src.components then
        local cc = {}
        for i = 1, #src.components do
            local s = src.components[i]
            cc[i] = { div = s.div, mod = s.mod, step = s.step, rounding = s.rounding }
        end
        copy.components = cc
    end
    return copy
end

local function ByThreshold(a, b) return a.threshold < b.threshold end

-- Build the breakpoint list. mm:ss / h / d thresholds are offset just above the integer boundary (59.0001…)
-- so an UP-rounded input in (N, N+1] routes into the larger-unit breakpoint, avoiding a "60" flash.
-- `tiers` = the timerThresholds list ({time,size,color}) or nil when thresholds are off; only time+colour used.
local function BuildBreakpoints(dec, tiers)
    local NEAREST = Enum.NumericRuleFormatRounding.Nearest
    local UP      = Enum.NumericRuleFormatRounding.Up
    local points = {}

    if dec > 0 then
        points[#points + 1] = { threshold = 0,   format = "%.1f", rounding = NEAREST }
        points[#points + 1] = { threshold = dec, format = "%d",   rounding = UP, step = 1 }
    else
        points[#points + 1] = { threshold = 0,   format = "%d",   rounding = UP, step = 1 }
    end
    points[#points + 1] = { threshold = 59.0001,    format = "%d:%02d", rounding = UP, step = 1,
        components = { { div = 60 }, { mod = 60 } } }
    points[#points + 1] = { threshold = 3599.0001,  format = "%dh", rounding = UP, step = 1,
        components = { { div = 3600 } } }
    points[#points + 1] = { threshold = 86399.0001, format = "%dd", rounding = UP, step = 1,
        components = { { div = 86400 } } }

    if tiers and #tiers > 0 then
        -- 1) Split the base ranges at each tier `time`, so the colour can change exactly there.
        for _, tier in ipairs(tiers) do
            local t = tier.time
            if t and t > 0 and tier.color then
                table.sort(points, ByThreshold)
                local ai = 1
                for i = 1, #points do if points[i].threshold <= t then ai = i else break end end
                if points[ai].threshold < t then points[#points + 1] = CloneAt(points[ai], t) end
            end
        end
        -- 2) Colour each breakpoint by the tier with the SMALLEST time strictly greater than its threshold
        --    (the innermost tier the range threshold..next falls below) — mirrors MatchThreshold's "smallest
        --    tier the remaining has fallen to". Above every tier -> no colour.
        for _, p in ipairs(points) do
            local best
            for _, tier in ipairs(tiers) do
                if tier.time and tier.color and tier.time > p.threshold then
                    if not best or tier.time < best.time then best = tier end
                end
            end
            if best then
                local col = best.color
                local c = CreateColor(col.r or 1, col.g or 0, col.b or 0, col.a or 1)
                p.format = c:WrapTextInColorCode(p.format)
            end
        end
    end

    table.sort(points, ByThreshold)
    return points
end

-- Cache keyed by config SIGNATURE: decimals + the colour tiers, both per-icon, so two icons with different
-- thresholds get different formatters and icons that share a config share one. Capped so a live colour-picker
-- drag (which mints a sig per intermediate colour) can't pile up.
local cache, cacheCount = {}, 0

-- Return the formatter for this native frame, or nil when OFF for it (caller passes nil to
-- SetCountdownFormatter -> native default). All inputs are PER-ICON via I.IconGet (override -> group): the
-- decimals (timerDecimalThreshold) and, when timerThresholdsEnabled, the timerThresholds colours.
function CF.GetFor(I, spellId)
    if not (CreateNumericRuleFormatter and I and I.IconGet) then return nil end
    local dec      = tonumber(I.IconGet(spellId, "timerDecimalThreshold")) or 0
    local tiers    = (I.IconGet(spellId, "timerThresholdsEnabled") == true) and I.IconGet(spellId, "timerThresholds") or nil
    local hasColor = tiers and #tiers > 0
    if dec <= 0 and not hasColor then return nil end

    local sig = "d" .. dec
    if hasColor then
        for _, t in ipairs(tiers) do
            local c = t.color
            sig = sig .. "|" .. tostring(t.time) .. (c and string.format(":%.2f,%.2f,%.2f,%.2f", c.r or 1, c.g or 0, c.b or 0, c.a or 1) or "")
        end
    end

    local fmt = cache[sig]
    if not fmt then
        -- Wiping just makes the next StyleFrame pass re-mint the few in-use formatters (old objects GC once
        -- no frame references them); cheap insurance against a colour-drag minting hundreds.
        if cacheCount >= 48 then cache, cacheCount = {}, 0 end
        fmt = CreateNumericRuleFormatter()
        fmt:SetBreakpoints(BuildBreakpoints(dec, tiers))
        cache[sig] = fmt
        cacheCount = cacheCount + 1
    end
    return fmt
end
