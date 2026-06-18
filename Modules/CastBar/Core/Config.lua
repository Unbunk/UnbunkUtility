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
    castColor          = { r = 1.0, g = 0.7,  b = 0.0,  a = 1 },  -- normal cast (gold)
    channelColor       = { r = 0.0, g = 0.9,  b = 0.3,  a = 1 },  -- channelled (green)
    uninterruptibleColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 },  -- not interruptible (grey)
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
