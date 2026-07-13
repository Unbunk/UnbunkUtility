-- Modules/CDMEngine/UI/ConfigWindow.lua
--
-- Config panel for the standalone CDM engine (ns.CDMEngine). Declarative BuildMenu, mirroring the
-- other modules (pilot: PITracker/UI/ConfigWindow.lua). It exposes the engine's persisted knobs and a
-- few session actions:
--   Engine        : show/hide the widgets, toggle design mode, reset group positions.
--   Class resources: enable, show-all vs signature, bar/pip sizes, empty pips, reset position.
--                   Applied live via E.Resource.Rebuild().
-- Everything the panel drives is our OWN config / frames — no native-frame contact.

local _, ns = ...
local L = ns.L
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine

local function CreateCDMEnginePanel(parent)
    local menu   -- forward-declared so set() closures can call menu.Refresh()

    -- Live-apply shorthands (all guarded — the engine modules load before this panel is ever opened,
    -- but stay defensive).
    local function RebuildResources() if E.Resource and E.Resource.Rebuild then E.Resource.Rebuild() end end
    local function ResourcesOn() return E.Cfg and E.Cfg.GetResource("enable") == true end

    -- Numeric size field for a resource.* key (integer, clamped by the widget's min/max).
    local function NumEntry(label, key, mn, mx)
        return {
            type = "textinput", label = label, width = 60, numeric = true, min = mn, max = mx, maxLetters = 4,
            get = function() return E.Cfg and E.Cfg.GetResource(key) end,
            set = function(v)
                if v and E.Cfg then E.Cfg.SetResource(key, math.floor(v)); RebuildResources() end
            end,
        }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["CDM Settings (beta)"] },
        { type = "label", height = 18, text = L["Choose which Cooldown Manager engine is active."] },
        { type = "label", height = 18, text = L["Native = full-featured (its Essential/Utility/Buffs tabs appear below)."] },
        { type = "label", height = 18, text = L["Standalone = the beta engine, configured here."] },

        -- ════════════ Engine (session actions) ════════════
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
                        if menu then menu.Rebuild() end   -- re-run build: flipped button label + status
                    end,
                },
                {
                    type = "label", height = 30,
                    text = L["Position each group from its own tab: Essential / Utility / Buffs / Bars → Position (X/Y)."],
                },
            } end,
        },

        -- ════════════ Class resources (persisted; live via Rebuild) ════════════
        {
            type = "group", title = L["Class resources"],
            gate = { enabled = function() return ResourcesOn() end, master = "resEnable" },
            build = function() return {
                {
                    type = "checkbox", ref = "resEnable", label = L["Enable class resources"],
                    get = function() return ResourcesOn() end,
                    set = function(v)
                        if E.Cfg then E.Cfg.SetResource("enable", v) end
                        RebuildResources()
                        if menu then menu.Refresh() end
                    end,
                },
                {
                    type = "checkbox", label = L["Show all of the spec's resources"],
                    get = function() return E.Cfg and (E.Cfg.GetResource("showCount") or 0) == 0 end,
                    set = function(v)
                        if E.Cfg then E.Cfg.SetResource("showCount", v and 0 or 1) end   -- 0 = all, 1 = signature only
                        RebuildResources()
                    end,
                },
                NumEntry(L["Bar width"],   "barWidth",   40, 600),
                NumEntry(L["Bar height"],  "barHeight",   4,  60),
                NumEntry(L["Pip size"],    "pipSize",     6,  60),
                NumEntry(L["Pip spacing"], "pipSpacing",  0,  20),
                NumEntry(L["Row spacing"], "rowSpacing",  0,  30),
                {
                    type = "checkbox", label = L["Show empty pips"],
                    get = function() return E.Cfg and E.Cfg.GetResource("showEmpty") ~= false end,
                    set = function(v)
                        if E.Cfg then E.Cfg.SetResource("showEmpty", v) end
                        RebuildResources()
                    end,
                },
                {
                    type = "button", label = L["Reset resource position"], width = 180,
                    onClick = function()
                        if E.Cfg then E.Cfg.ClearResourcePos() end
                        if E.Resource then E.Resource.ApplyPosition() end
                    end,
                },
            } end,
        },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

-- ── Registration ────────────────────────────────────────────────────────────────
UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["CDM Settings (beta)"], nil, CreateCDMEnginePanel)
end)
