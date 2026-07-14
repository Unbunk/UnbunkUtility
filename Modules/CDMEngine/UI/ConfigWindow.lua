-- Modules/CDMEngine/UI/ConfigWindow.lua
--
-- Config panels for the standalone CDM engine (ns.CDMEngine). Declarative BuildMenu.
--   CDM Settings   : pick the active engine (native vs standalone) + how each group is positioned.
--   Class resources: its OWN tab (after "Free icons"). A master enable, then ONE cadre per detected
--                    resource bar (per spec), each with a "Bar settings" sub-cadre + a "Position"
--                    sub-cadre (anchor / placement / X-Y / unlock). Applied live via E.Resource.
-- Everything the panels drive is our OWN config / frames — no native-frame contact.

local _, ns = ...
local L = ns.L
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine

-- ── CDM Settings: which engine is active + a positioning hint ──────────────────────
local function CreateCDMEnginePanel(parent)
    local menu   -- forward-declared so the mode button can call menu.Rebuild()
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["CDM Settings"] },
        { type = "label", height = 18, text = L["Choose which Cooldown Manager engine is active."] },
        { type = "label", height = 18, text = L["Native = full-featured (its Essential/Utility/Buffs tabs appear below)."] },
        { type = "label", height = 18, text = L["Standalone = the beta engine, configured here."] },

        {
            type = "group", title = L["Engine"],
            build = function()
                local engine = ns.CDMMode and ns.CDMMode.IsEngine()
                return {
                {
                    type = "label", height = 20,
                    text = engine and L["Active: standalone engine (beta)"] or L["Active: native Cooldown Manager"],
                },
                {
                    type = "button", width = 260,
                    label = engine and L["Use native CDM engine"] or L["Use the standalone engine (beta)"],
                    onClick = function()
                        if ns.CDMMode then ns.CDMMode.Set(engine and "native" or "engine") end   -- Set() also RefreshNav()
                        if menu then menu.Rebuild() end
                    end,
                },
                {
                    type = "label", height = 30,
                    text = L["Position each group from its own tab: Essential / Utility / Buffs / Bars → Position (X/Y)."],
                },
            } end,
        },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

-- ── Class resources: one cadre per resource bar (per spec) ─────────────────────────
-- Anchor / adapt target keys ↔ labels (the 6 CDM targets; "Anchor to" also offers the earlier bars).
local DEST_KEYS  = { "essential", "utility", "belowPlayer", "belowFront", "belowEnd", "buff" }
local DEST_LABEL = {
    essential   = L["Essential"],
    utility     = L["Utility"],
    belowPlayer = L["Below player frame"],
    belowFront  = L["Below player frame (front)"],
    belowEnd    = L["Below player frame (end)"],
    buff        = L["Buff"],
}
-- Placement keys ↔ labels.
local PLACE_KEYS  = { "above", "below", "left", "right", "topleft", "topright", "bottomleft", "bottomright" }
local PLACE_LABEL = {
    above = L["Above"], below = L["Below"], left = L["Left"], right = L["Right"],
    topleft = L["Top-left"], topright = L["Top-right"], bottomleft = L["Bottom-left"], bottomright = L["Bottom-right"],
}
local function DestLabels()
    local t = {}
    for _, k in ipairs(DEST_KEYS) do t[#t + 1] = DEST_LABEL[k] end
    return t
end
local function DestKeyFromLabel(lbl)
    for _, k in ipairs(DEST_KEYS) do if DEST_LABEL[k] == lbl then return k end end
    return "essential"
end
-- Resource-bar anchor targets (Last bar + "N: name") for the current spec, from the shared source.
local function ResBarTargets()
    return (E.Resource and E.Resource.AnchorTargets and E.Resource.AnchorTargets()) or {}
end
local function ResBarCount()
    local d = E.Resource and E.Resource.Detect and E.Resource.Detect()
    return (type(d) == "table") and #d or 0
end
-- A resource-bar target is "self" for bar i (excluded so a bar can't anchor / adapt to itself).
local function IsSelfTarget(key, i)
    if key == ("resbar:" .. i) then return true end
    if key == "resbar:last" and i == ResBarCount() then return true end
    return false
end
-- CDM dests + every resource bar (Last bar + "N: name") EXCEPT bar i itself. Shared by "Anchor to" + "Adapt to".
local function TargetLabels(i)
    local t = DestLabels()
    for _, tgt in ipairs(ResBarTargets()) do
        if not IsSelfTarget(tgt.key, i) then t[#t + 1] = tgt.label end
    end
    return t
end
local function TargetLabelFor(key, i)
    for _, tgt in ipairs(ResBarTargets()) do if tgt.key == key then return tgt.label end end
    local n = (type(key) == "string") and key:match("^bar(%d+)$")   -- legacy per-bar key -> its resbar label
    if n then for _, tgt in ipairs(ResBarTargets()) do if tgt.key == ("resbar:" .. n) then return tgt.label end end end
    return DEST_LABEL[key] or DEST_LABEL.essential
end
local function TargetKeyFromLabel(lbl)
    for _, k in ipairs(DEST_KEYS) do if DEST_LABEL[k] == lbl then return k end end
    for _, tgt in ipairs(ResBarTargets()) do if tgt.label == lbl then return tgt.key end end
    return "essential"
end
local function PlaceLabels()
    local t = {}
    for _, k in ipairs(PLACE_KEYS) do t[#t + 1] = PLACE_LABEL[k] end
    return t
end
local function PlaceKeyFromLabel(lbl)
    for _, k in ipairs(PLACE_KEYS) do if PLACE_LABEL[k] == lbl then return k end end
    return "above"
end
-- Text position keys ↔ labels (left / middle / right).
local TPOS_KEYS  = { "left", "center", "right" }
local TPOS_LABEL = { left = L["Left"], center = L["Middle"], right = L["Right"] }
local function TposLabels()
    local t = {}
    for _, k in ipairs(TPOS_KEYS) do t[#t + 1] = TPOS_LABEL[k] end
    return t
end
local function TposKeyFromLabel(lbl)
    for _, k in ipairs(TPOS_KEYS) do if TPOS_LABEL[k] == lbl then return k end end
    return "center"
end

local function CreateClassResourcesPanel(parent)
    local menu   -- forward-declared so set() closures can call menu.Refresh()
    local R = E.Resource

    local function Get(specKey, i, key) return E.Cfg and E.Cfg.GetBar(specKey, i, key) end
    local function ReRes()  if R and R.Rebuild     then R.Rebuild()     end end   -- cell/size change -> full rebuild
    local function RePos()  if R and R.Reposition  then R.Reposition()  end end   -- position/anchor -> re-anchor only
    local function ResourcesOn() return E.Cfg and E.Cfg.GetResource("enable") == true end

    -- Integer size field for a per-bar key. `disabled` (optional fn) greys it when true.
    local function NumEntry(label, specKey, i, key, mn, mx, disabled)
        return {
            type = "textinput", label = label, width = 60, numeric = true, min = mn, max = mx, maxLetters = 4,
            get = function() return Get(specKey, i, key) end,
            set = function(v) if v and E.Cfg then E.Cfg.SetBar(specKey, i, key, math.floor(v)); ReRes() end end,
            disabled = disabled,
        }
    end

    -- The split-density row (continuous "bar" resources only): "[slider = dividers] per [X] <resource>", laid
    -- out inline. X counts in THOUSANDS with a "K" prefix on the name when the resource max is > 100k (mana),
    -- so the box shows e.g. 50 for 50000. Stored as the raw amount in splitUnit.
    local function SplitDensityRow(specKey, i, label)
        return {
            type = "custom", height = 34,
            build = function(host)
                local desc  = R and R.REGISTRY and R.REGISTRY[label]
                local power = desc and desc.power
                local resName = tostring(label or "")
                local function IsK() return ((power and UnitPowerMax("player", power)) or 0) > 100000 end

                local s = ns.ui.CreateSlider({
                    parent = host, width = 110, min = 1, max = 10, step = 1,
                    value = Get(specKey, i, "splitCount") or 2,
                    onChange = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, "splitCount", math.floor(v)); ReRes() end end,
                })
                s.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)

                local perFs = host:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
                perFs:SetPoint("LEFT", s.frame, "RIGHT", 10, 0)
                perFs:SetText(L["per"] or "per")

                local ti = ns.ui.CreateTextInput({
                    parent = host, width = 56, numeric = true, min = 1, maxLetters = 7,
                    onEnter = function(v)
                        if v and E.Cfg then
                            E.Cfg.SetBar(specKey, i, "splitUnit", math.floor(v) * (IsK() and 1000 or 1)); ReRes()
                        end
                    end,
                })
                ti.frame:SetPoint("LEFT", perFs, "RIGHT", 8, 0)

                local nameFs = host:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
                nameFs:SetPoint("LEFT", ti.frame, "RIGHT", 8, 0)

                local function Sync()
                    local unit = Get(specKey, i, "splitUnit") or 50000
                    local k = IsK()
                    ti.SetText(tostring(k and math.floor(unit / 1000 + 0.5) or math.floor(unit)))
                    nameFs:SetText((k and "K " or "") .. resName)
                    s.SetValue(Get(specKey, i, "splitCount") or 2)
                end
                Sync()
                return { frame = host, height = 34, Refresh = Sync }
            end,
        }
    end

    -- The "Bar settings" sub-cadre: Bar width (greyed when "Adapt width to" is on) / Bar height, then the
    -- "Adapt width to" toggle + its target dropdown (label-less: the checkbox names it), then Show empty pips.
    local function BarSettingsCadre(specKey, i)
        return { type = "group", title = L["Bar settings"], build = function() return {
            {
                type = "checkbox", label = L["Adapt width to"],
                get = function() return Get(specKey, i, "adaptWidth") == true end,
                set = function(v)
                    if E.Cfg then E.Cfg.SetBar(specKey, i, "adaptWidth", v and true or false); ReRes() end
                    if menu then menu.Refresh() end   -- re-grey / un-grey Bar width
                end,
            },
            {
                type = "dropdown", width = 180, height = 40,   -- no label: the checkbox above names it
                getList = function() return TargetLabels(i) end,
                getCurrentKey = function() return TargetLabelFor(Get(specKey, i, "adaptTo"), i) end,
                onSelect = function(lbl) if E.Cfg then E.Cfg.SetBar(specKey, i, "adaptTo", TargetKeyFromLabel(lbl)); ReRes() end end,
            },
            NumEntry(L["Bar width"], specKey, i, "barWidth", 40, 600,
                function() return Get(specKey, i, "adaptWidth") == true end),
            NumEntry(L["Bar height"], specKey, i, "barHeight", 4, 60),
            {
                type = "checkbox", label = L["Show empty pips"],
                get = function() return Get(specKey, i, "showEmpty") ~= false end,
                set = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, "showEmpty", v and true or false); ReRes() end end,
            },
        } end }
    end

    -- The "Split bars settings" sub-cadre: Show split bars (all bars) + a thickness slider (with edit box),
    -- and — continuous "bar" resources only — the inline density row "[n] per [X] <resource>".
    local function SplitBarsCadre(specKey, i, fam, label)
        return { type = "group", title = L["Split bars settings"], build = function()
            local e = {
                {
                    type = "checkbox", label = L["Show split bars"],
                    get = function()
                        local v = Get(specKey, i, "showSplit")
                        if v == nil then v = (fam ~= "bar") end   -- unset: primary "bar" bars default OFF, pips ON
                        return v == true
                    end,
                    set = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, "showSplit", v and true or false); ReRes() end end,
                },
                {
                    type = "slider", label = L["Split bar thickness"], width = 200, min = 1, max = 10, step = 1, editBox = true,
                    get = function() return Get(specKey, i, "splitThickness") or 1 end,
                    set = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, "splitThickness", math.floor(v)); ReRes() end end,
                },
            }
            if fam == "bar" then e[#e + 1] = SplitDensityRow(specKey, i, label) end   -- inline "[n] per [X] name"
            return e
        end }
    end

    -- The "Resource text" sub-cadre (continuous "bar" resources only, e.g. mana): two nested sub-cadres —
    -- Value and Percentage — each with a show toggle, a left/middle/right position, and a font/size/colour/
    -- outline editor. Text tweaks use the LIGHT R.RefreshText (no full rebuild -> smooth colour drag).
    local function ResourceTextCadre(specKey, i)
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local function ReText() if R and R.RefreshText then R.RefreshText() end end
        local function PosDropdown(label, key)
            return {
                type = "dropdown", label = label, width = 180, height = 50,
                getList = TposLabels,
                getCurrentKey = function() return TPOS_LABEL[Get(specKey, i, key)] or TPOS_LABEL.center end,
                onSelect = function(lbl) if E.Cfg then E.Cfg.SetBar(specKey, i, key, TposKeyFromLabel(lbl)); ReText() end end,
            }
        end
        -- One text (prefix "value" / "percent"): show + position + font/size/colour/outline.
        local function TextSub(prefix, title, checkLabel, posLabel)
            local showKey = "show" .. prefix:sub(1, 1):upper() .. prefix:sub(2) .. "Text"   -- showValueText / showPercentText
            return { type = "group", title = title, build = function() return {
                {
                    type = "checkbox", label = checkLabel,
                    get = function() return Get(specKey, i, showKey) == true end,
                    set = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, showKey, v and true or false); ReText() end end,
                },
                PosDropdown(posLabel, prefix .. "TextPos"),
                {
                    type = "textEditor", LSM = LSM, showLabel = false, showText = false,
                    showFont = true, showSize = true, showColor = true, showOutline = true,
                    getFontKey  = function() return Get(specKey, i, prefix .. "FontKey") end,
                    getFontPath = function() return Get(specKey, i, prefix .. "FontPath") end,
                    getFontSize = function() return Get(specKey, i, prefix .. "FontSize") or 12 end,
                    getOutline  = function() return Get(specKey, i, prefix .. "Outline") or "OUTLINE" end,
                    getColor    = function() return Get(specKey, i, prefix .. "Color") or { r = 1, g = 1, b = 1, a = 1 } end,
                    onFontChange = function(key, path)
                        if E.Cfg then E.Cfg.SetBar(specKey, i, prefix .. "FontKey", key); E.Cfg.SetBar(specKey, i, prefix .. "FontPath", path); ReText() end
                    end,
                    onSizeChange    = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, prefix .. "FontSize", v); ReText() end end,
                    onOutlineChange = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, prefix .. "Outline", v); ReText() end end,
                    onColorChange   = function(r, g, b, a) if E.Cfg then E.Cfg.SetBar(specKey, i, prefix .. "Color", { r = r, g = g, b = b, a = a }); ReText() end end,
                },
            } end }
        end
        return { type = "group", title = L["Resource text"], build = function() return {
            TextSub("value",   L["Value"],      L["Show value (e.g. 500k/500k)"], L["Value position"]),
            TextSub("percent", L["Percentage"], L["Show percentage"],             L["Percentage position"]),
        } end }
    end

    -- The "Position" sub-cadre (LAST): X / Y / Unlock, then Anchor to + Placement.
    local function PositionCadre(specKey, i)
        return { type = "group", title = L["Position"], build = function() return {
            {
                type = "position",
                label = L["Position (offset from anchor)"],
                getX = function() return Get(specKey, i, "posX") end,
                getY = function() return Get(specKey, i, "posY") end,
                onApply = function(x, yv)
                    if E.Cfg then
                        if x  then E.Cfg.SetBar(specKey, i, "posX", x)  end
                        if yv then E.Cfg.SetBar(specKey, i, "posY", yv) end
                    end
                    RePos()
                end,
                onUnlock   = function() if R and R.SetBarUnlocked then R.SetBarUnlocked(i, true)  end end,
                onLock     = function() if R and R.SetBarUnlocked then R.SetBarUnlocked(i, false) end end,
                isUnlocked = function() return R and R.IsBarUnlocked and R.IsBarUnlocked(i) or false end,
            },
            {
                type = "dropdown", label = L["Anchor to"], width = 180, height = 50,
                getList = function() return TargetLabels(i) end,
                getCurrentKey = function() return TargetLabelFor(Get(specKey, i, "anchorTo"), i) end,
                onSelect = function(lbl) if E.Cfg then E.Cfg.SetBar(specKey, i, "anchorTo", TargetKeyFromLabel(lbl)); RePos() end end,
            },
            {
                type = "dropdown", label = L["Placement"], width = 180, height = 50,
                getList = PlaceLabels,
                getCurrentKey = function() return PLACE_LABEL[Get(specKey, i, "placement")] or PLACE_LABEL.above end,
                onSelect = function(lbl) if E.Cfg then E.Cfg.SetBar(specKey, i, "placement", PlaceKeyFromLabel(lbl)); RePos() end end,
            },
        } end }
    end

    -- One cadre per detected bar: "Enable resource bar" + Bar settings + (Resource text, bar-family only) + Position.
    local function BarCadre(specKey, i, label, fam)
        local master = "barEnable" .. i
        return {
            type = "group", title = ("%d. %s"):format(i, label), heading = "UnbunkUtilityH2",
            gate = { enabled = function() return Get(specKey, i, "enable") ~= false end, master = master },
            build = function()
                local e = {
                    {
                        type = "checkbox", ref = master, label = L["Enable resource bar"],
                        get = function() return Get(specKey, i, "enable") ~= false end,
                        set = function(v)
                            if E.Cfg then E.Cfg.SetBar(specKey, i, "enable", v and true or false) end
                            ReRes()
                            if menu then menu.Refresh() end
                        end,
                    },
                    BarSettingsCadre(specKey, i),
                    SplitBarsCadre(specKey, i, fam, label),
                }
                if fam == "bar" then e[#e + 1] = ResourceTextCadre(specKey, i) end   -- value/percent: continuous power bars only
                e[#e + 1] = PositionCadre(specKey, i)
                return e
            end,
        }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Class resources"] },
        {
            type = "checkbox", label = L["Enable class resources"],
            get = function() return ResourcesOn() end,
            set = function(v)
                if E.Cfg then E.Cfg.SetResource("enable", v and true or false) end
                ReRes()
            end,
        },
    }

    -- One cadre per resource of the CURRENT spec (config is keyed per spec). Reopen the tab after a spec
    -- change to rebuild the cadre list for the new spec.
    local specKey = R and R.GetSpecKey and R.GetSpecKey()
    local labels  = (R and R.Detect and R.Detect()) or {}
    if specKey and #labels > 0 then
        for i = 1, #labels do
            local desc = R and R.REGISTRY and R.REGISTRY[labels[i]]
            options[#options + 1] = BarCadre(specKey, i, labels[i], desc and desc.family)
        end
    else
        options[#options + 1] = { type = "label", height = 20, text = L["This spec has no tracked resources."] }
    end

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

-- ── Registration ────────────────────────────────────────────────────────────────
UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["CDM Settings"],    nil, CreateCDMEnginePanel)
    UnbunkUtility.RegisterModule(L["Class resources"], nil, CreateClassResourcesPanel)
end)
