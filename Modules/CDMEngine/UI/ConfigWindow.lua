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
local function BarLabel(n) return (L["Bar"] or "Bar") .. " " .. n end

local function DestLabels()
    local t = {}
    for _, k in ipairs(DEST_KEYS) do t[#t + 1] = DEST_LABEL[k] end
    return t
end
local function DestKeyFromLabel(lbl)
    for _, k in ipairs(DEST_KEYS) do if DEST_LABEL[k] == lbl then return k end end
    return "essential"
end
local function AnchorLabels(i)   -- CDM targets + Bar 1..(i-1)
    local t = DestLabels()
    for n = 1, (i - 1) do t[#t + 1] = BarLabel(n) end
    return t
end
local function AnchorLabelFor(key, i)
    if type(key) == "string" then
        local n = key:match("^bar(%d+)$")
        if n then return BarLabel(tonumber(n)) end
    end
    return DEST_LABEL[key] or DEST_LABEL.essential
end
local function AnchorKeyFromLabel(lbl, i)
    for _, k in ipairs(DEST_KEYS) do if DEST_LABEL[k] == lbl then return k end end
    for n = 1, (i - 1) do if BarLabel(n) == lbl then return "bar" .. n end end
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

local function CreateClassResourcesPanel(parent)
    local menu   -- forward-declared so set() closures can call menu.Refresh()
    local R = E.Resource

    local function Get(specKey, i, key) return E.Cfg and E.Cfg.GetBar(specKey, i, key) end
    local function ReRes()  if R and R.Rebuild     then R.Rebuild()     end end   -- cell/size change -> full rebuild
    local function RePos()  if R and R.Reposition  then R.Reposition()  end end   -- position/anchor -> re-anchor only
    local function ResourcesOn() return E.Cfg and E.Cfg.GetResource("enable") == true end

    -- Integer size field for a per-bar key.
    local function NumEntry(label, specKey, i, key, mn, mx)
        return {
            type = "textinput", label = label, width = 60, numeric = true, min = mn, max = mx, maxLetters = 4,
            get = function() return Get(specKey, i, key) end,
            set = function(v) if v and E.Cfg then E.Cfg.SetBar(specKey, i, key, math.floor(v)); ReRes() end end,
        }
    end

    -- The "Bar settings" sub-cadre: sizes (with Adapt to under Bar width) + Show empty pips.
    local function BarSettingsCadre(specKey, i)
        return { type = "group", title = L["Bar settings"], build = function() return {
            NumEntry(L["Bar width"], specKey, i, "barWidth", 40, 600),
            {
                type = "dropdown", label = L["Adapt to"], width = 180, height = 50,
                getList = DestLabels,
                getCurrentKey = function() return DEST_LABEL[Get(specKey, i, "adaptTo")] or DEST_LABEL.essential end,
                onSelect = function(lbl) if E.Cfg then E.Cfg.SetBar(specKey, i, "adaptTo", DestKeyFromLabel(lbl)); ReRes() end end,
            },
            NumEntry(L["Bar height"],  specKey, i, "barHeight",  4,  60),
            NumEntry(L["Pip size"],    specKey, i, "pipSize",    6,  60),
            NumEntry(L["Pip spacing"], specKey, i, "pipSpacing", 0,  20),
            {
                type = "checkbox", label = L["Show empty pips"],
                get = function() return Get(specKey, i, "showEmpty") ~= false end,
                set = function(v) if E.Cfg then E.Cfg.SetBar(specKey, i, "showEmpty", v and true or false); ReRes() end end,
            },
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
                getList = function() return AnchorLabels(i) end,
                getCurrentKey = function() return AnchorLabelFor(Get(specKey, i, "anchorTo"), i) end,
                onSelect = function(lbl) if E.Cfg then E.Cfg.SetBar(specKey, i, "anchorTo", AnchorKeyFromLabel(lbl, i)); RePos() end end,
            },
            {
                type = "dropdown", label = L["Placement"], width = 180, height = 50,
                getList = PlaceLabels,
                getCurrentKey = function() return PLACE_LABEL[Get(specKey, i, "placement")] or PLACE_LABEL.above end,
                onSelect = function(lbl) if E.Cfg then E.Cfg.SetBar(specKey, i, "placement", PlaceKeyFromLabel(lbl)); RePos() end end,
            },
        } end }
    end

    -- One cadre per detected bar: "Enable resource bar" + Bar settings + Position (last).
    local function BarCadre(specKey, i, label)
        local master = "barEnable" .. i
        return {
            type = "group", title = ("%d. %s"):format(i, label), heading = "UnbunkUtilityH2",
            gate = { enabled = function() return Get(specKey, i, "enable") ~= false end, master = master },
            build = function() return {
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
                PositionCadre(specKey, i),
            } end,
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
            options[#options + 1] = BarCadre(specKey, i, labels[i])
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
