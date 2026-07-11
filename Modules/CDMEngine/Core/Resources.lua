-- Modules/CDMEngine/Core/Resources.lua
--
-- Phase 4c of the standalone CDM engine (ns.CDMEngine): PURE DATA + spec detection for the class-
-- resource widget (Display/ClassResource.lua does the drawing). No frames, no Unit reads at load.
-- The spec->resources table + the label->descriptor registry let the widget pick and render the
-- current spec's characteristic resource(s). Isolated: reads only Enum + the player's spec.

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
E.Resource = E.Resource or {}
local R = E.Resource

local PT = Enum and Enum.PowerType

-- SPEC_RESOURCES[specID or CLASSFILE] = ORDERED list of resource labels (primary first). Keyed by
-- numeric specID, with a CLASSFILE string fallback so an unknown spec of a known class still resolves.
-- (mirrors Coolinator's Constants.ClassResources)
R.SPEC_RESOURCES = {
    DEATHKNIGHT = { "runes", "runic-power" },
    [250] = { "runes", "runic-power" }, [251] = { "runes", "runic-power" }, [252] = { "runes", "runic-power" },
    DEMONHUNTER = { "fury" },
    [577] = { "fury" }, [581] = { "fury" },
    DRUID = { "combo-points", "rage", "energy", "mana" },
    [102] = { "lunar-power" }, [103] = { "combo-points", "energy" }, [104] = { "rage" }, [105] = { "mana" },
    EVOKER = { "essence", "mana" },
    [1467] = { "essence", "mana" }, [1468] = { "essence", "mana" }, [1473] = { "essence", "mana" },
    HUNTER = { "focus" },
    [253] = { "focus" }, [254] = { "focus" }, [255] = { "focus", "tip-of-the-spear" },
    MAGE = { "mana" },
    [62] = { "arcane-charges", "mana" }, [63] = { "mana" }, [64] = { "mana", "icicles" },
    MONK = { "chi", "energy", "mana" },
    [268] = { "stagger", "energy" }, [269] = { "chi", "energy" }, [270] = { "mana" },
    PALADIN = { "holy-power", "mana" },
    [65] = { "holy-power", "mana" }, [66] = { "holy-power", "mana" }, [70] = { "holy-power", "mana" },
    PRIEST = { "mana" },
    [256] = { "mana" }, [257] = { "mana" }, [258] = { "mana", "insanity" },
    ROGUE = { "combo-points", "energy" },   -- signature resource first (shown at showCount=1)
    [259] = { "combo-points", "energy" }, [260] = { "combo-points", "energy" }, [261] = { "combo-points", "energy" },
    SHAMAN = { "maelstrom-weapon", "mana" },
    [262] = { "maelstrom", "mana" }, [263] = { "maelstrom-weapon", "mana" }, [264] = { "mana" },
    WARLOCK = { "soul-shards", "mana" },
    [265] = { "soul-shards", "mana" }, [266] = { "soul-shards", "mana" }, [267] = { "soul-shards", "mana" },
    WARRIOR = { "rage" },
    [71] = { "rage" }, [72] = { "rage" }, [73] = { "rage" },
}

-- REGISTRY[label] = descriptor { family, ... }. Slice 1 populates bar / pips / essence only; runes,
-- auraBar, auraPips and stagger arrive in later slices. Detect() returns a label even if it has no
-- descriptor yet — the widget simply skips a label whose family is not (yet) implemented.
R.REGISTRY = {
    -- direct power bars
    energy          = { family = "bar", power = PT and PT.Energy },
    mana            = { family = "bar", power = PT and PT.Mana },
    rage            = { family = "bar", power = PT and PT.Rage },
    fury            = { family = "bar", power = PT and PT.Fury },
    focus           = { family = "bar", power = PT and PT.Focus },
    ["runic-power"] = { family = "bar", power = PT and PT.RunicPower },
    insanity        = { family = "bar", power = PT and PT.Insanity },
    ["lunar-power"] = { family = "bar", power = PT and PT.LunarPower },
    ["astral-power"] = { family = "bar", power = PT and PT.LunarPower },   -- alias of lunar-power
    maelstrom       = { family = "bar", power = PT and PT.Maelstrom },
    -- discrete pips (soul-shards render in tenths -> divisor 10; others one pip per point)
    ["soul-shards"]  = { family = "pips", power = PT and PT.SoulShards,    divisor = 10 },
    ["holy-power"]   = { family = "pips", power = PT and PT.HolyPower,     divisor = 1 },
    ["combo-points"] = { family = "pips", power = PT and PT.ComboPoints,   divisor = 1 },
    chi              = { family = "pips", power = PT and PT.Chi,           divisor = 1 },
    ["arcane-charges"] = { family = "pips", power = PT and PT.ArcaneCharges, divisor = 1 },
    -- essence (discrete pips with a charging partial-fill on the filling pip)
    essence          = { family = "essence", power = PT and PT.Essence,   divisor = 1 },
    -- SLICE 2: runes (DK, 6 cooldown pips) + aura-stack resources
    runes            = { family = "runes" },
    icicles              = { family = "auraBar",  spellID = 205473, max = 5 },
    ["tip-of-the-spear"] = { family = "auraBar",  spellID = 260286, max = 3 },
    ["maelstrom-weapon"] = { family = "auraPips", spellID = 344179, max = 10, divisor = 1 },
    -- SLICE 3 label (stagger) still has NO descriptor -> skipped until its family lands.
}

local prevSpecIdx = 1
-- The current spec's key: numeric specID, or the CLASSFILE string as a fallback. prevSpecIdx guards a
-- nil GetSpecialization() during a spec transition (so we keep the last good index rather than error).
function R.GetSpecKey()
    local idx = (GetSpecialization and GetSpecialization()) or prevSpecIdx
    if idx then prevSpecIdx = idx end
    local sid = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
    if sid then return sid end
    local _, cls = UnitClass("player")
    return cls
end

-- The ordered label list for the current spec, or {} (= draw nothing). Type-guards a non-table value
-- (a couple of source rows are numeric / empty placeholders).
function R.Detect()
    local list = R.SPEC_RESOURCES[R.GetSpecKey()]
    if type(list) ~= "table" then return {} end
    return list
end
