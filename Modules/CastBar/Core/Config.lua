-- Modules/CastBar/Core/Config.lua
-- Per-profile config for the custom player cast bar (ns.db.profile.CastBar). The whole
-- module is enabled by default, and by default it also hides Blizzard's native player
-- cast bar (hideBlizzard) so the two don't overlap.

local _, ns = ...
ns.CastBar = ns.CastBar or {}
local CB = ns.CastBar

local DEFAULTS = {
    enabled       = true,    -- whole module on by default
    hideBlizzard  = true,    -- hide Blizzard's PlayerCastingBarFrame (checked by default)
    -- Placement: anchored to a CDM viewer at a relative position, + a fine-tune offset.
    anchorTo         = "utility",     -- "essential" | "utility" | "belowPlayer"
    positionRelative = "bottom",      -- bottom/top/bottomleft/bottomright/topleft/topright
    posX          = 0,
    posY          = 0,
    -- Bar size.
    width         = 255,
    height        = 40,
    adaptWidth    = true,             -- match the width of a CDM viewer
    adaptWidthTo  = "utility",        -- which one (same keys as anchorTo)
    -- Icon.
    showIcon      = true,
    iconPosition  = "left",           -- "left" | "right"
    iconGap       = 1,                -- px between the icon and the bar
    -- Bar / background textures (LibSharedMedia statusbar keys).
    barTexture    = "Better Blizzard",
    bgTexture     = "Better Blizzard",
    -- What to show.
    showSpellName = true,
    showTimer     = true,
    showSpark     = true,
    sparkThickness = 20,              -- spark width in px (it's a vertical line at the fill edge)
    -- Spell-name text style + offset (its own, no longer a shared global style).
    nameFontKey   = "Fira Mono", nameFontPath = nil, nameFontSize = 12, nameOutline = "OUTLINE",
    nameColor     = { r = 1, g = 1, b = 1, a = 1 },
    nameXOffset   = 3,  nameYOffset = 0,
    -- Timer text style + offset.
    timerFontKey  = "Fira Mono", timerFontPath = nil, timerFontSize = 12, timerOutline = "OUTLINE",
    timerColor    = { r = 1, g = 1, b = 1, a = 1 },
    timerXOffset  = -3, timerYOffset = 0,
    -- Bar fill colours per cast state.
    castColor          = { r = 0.20, g = 0.55, b = 1.0, a = 1 },  -- #338CFF (brand blue)
    channelColor       = { r = 0.20, g = 0.72, b = 1.0, a = 1 },  -- #33B8FF
    uninterruptibleColor = { r = 0.20, g = 0.55, b = 1.0, a = 1 },  -- #338CFF (brand blue)
    -- End-of-cast feedback: briefly hold the (non-channel) bar in a success / interrupted colour
    -- after it ends. Cosmetic; the interrupted flash is the useful part (you see a kick land, or
    -- your own cast get kicked). endFeedbackHold has no UI (the widget can't take decimals) — it's
    -- a config-only override; 0 disables the hold.
    showEndFeedback  = true,
    endFeedbackHold  = 0.5,                                       -- seconds to hold the coloured bar
    completeColor    = { r = 0.20, g = 0.80, b = 0.35, a = 1 },   -- success green
    interruptedColor = { r = 0.90, g = 0.20, b = 0.20, a = 1 },   -- interrupted / failed red
    -- Fill engine escape hatch: native SetTimerDuration (no per-frame OnUpdate) by default. Set
    -- false (config-only, no UI) to fall back to the per-frame fill if the native engine ever
    -- misbehaves on a given client.
    nativeFill       = true,
    -- Border around the whole bar (icon + fill).
    borderEnabled   = true,
    borderColor     = { r = 0, g = 0, b = 0, a = 1 },             -- black
    borderThickness = 1,
}

function CB.CfgInit()
    if not ns.db then return end
    ns.db.profile.CastBar = ns.db.profile.CastBar or {}
    local s = ns.db.profile.CastBar
    ns.MergeDefaults(s, DEFAULTS)
    -- One-shot: fold the old shared text style (fontKey/fontSize/outline/textColor) into the
    -- new per-name + per-timer styles so existing setups keep their look.
    if not s.textStyleSplitV1 then
        s.textStyleSplitV1 = true
        if s.fontKey or s.fontSize or s.outline or s.textColor then
            for _, p in ipairs({ "name", "timer" }) do
                if s.fontKey   then s[p .. "FontKey"]  = s.fontKey  end
                if s.fontPath  then s[p .. "FontPath"] = s.fontPath end
                if s.fontSize  then s[p .. "FontSize"] = s.fontSize end
                if s.outline   then s[p .. "Outline"]  = s.outline  end
                if s.textColor then s[p .. "Color"]    = ns.DeepCopy(s.textColor) end
            end
        end
    end
    -- One-shot: bump the stock cast/channel/uninterruptible colours to the brand palette for
    -- setups still sitting on the old gold/green/grey defaults. Anything the user customised
    -- (i.e. not matching the old default) is left untouched.
    if not s.brandColorsV1 then
        s.brandColorsV1 = true
        local OLD = {
            castColor            = { r = 1.0, g = 0.7, b = 0.0 },
            channelColor         = { r = 0.0, g = 0.9, b = 0.3 },
            uninterruptibleColor = { r = 0.6, g = 0.6, b = 0.6 },
        }
        local function near(a, b) return a and math.abs((a or 0) - b) < 0.01 end
        for key, o in pairs(OLD) do
            local c = s[key]
            if c and near(c.r, o.r) and near(c.g, o.g) and near(c.b, o.b) then
                s[key] = ns.CopyDefault(DEFAULTS[key])
            end
        end
    end
end
ns.RegisterCfgInitHook(CB.CfgInit)

-- ── "Position relative to anchor" keys ↔ localized labels ↔ anchor points ──────
-- key -> { container point, anchor-frame point } (where the bar sits vs the anchor).
CB.REL_POINTS = {
    bottom      = { "TOP",         "BOTTOM"      },
    top         = { "BOTTOM",      "TOP"         },
    bottomleft  = { "TOPLEFT",     "BOTTOMLEFT"  },
    bottomright = { "TOPRIGHT",    "BOTTOMRIGHT" },
    topleft     = { "BOTTOMLEFT",  "TOPLEFT"     },
    topright    = { "BOTTOMRIGHT", "TOPRIGHT"    },
}
CB.REL_ORDER = { "bottom", "top", "bottomleft", "bottomright", "topleft", "topright" }

function CB.RelLabel(key)
    local L = ns.L
    local map = {
        bottom = L["Bottom"], top = L["Top"], bottomleft = L["Bottom left"],
        bottomright = L["Bottom right"], topleft = L["Top left"], topright = L["Top right"],
    }
    return map[key] or map.bottom
end
function CB.RelList()
    local t = {}
    for _, k in ipairs(CB.REL_ORDER) do t[#t + 1] = CB.RelLabel(k) end
    return t
end
function CB.RelKeyFromLabel(label)
    for _, k in ipairs(CB.REL_ORDER) do if CB.RelLabel(k) == label then return k end end
    return "bottom"
end

function CB.CfgGet(key)
    local t = ns.db and ns.db.profile.CastBar
    local v = t and t[key]
    if v == nil then return ns.CopyDefault(DEFAULTS[key]) end
    return v
end

function CB.CfgSet(key, value)
    if not ns.db then return end
    ns.db.profile.CastBar = ns.db.profile.CastBar or {}
    ns.db.profile.CastBar[key] = value
end
