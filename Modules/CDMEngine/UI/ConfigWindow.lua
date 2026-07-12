-- Modules/CDMEngine/UI/ConfigWindow.lua
--
-- Config panel for the standalone CDM engine (ns.CDMEngine). Declarative BuildMenu, mirroring the
-- other modules (pilot: PITracker/UI/ConfigWindow.lua). It exposes the engine's persisted knobs and a
-- few session actions:
--   Engine        : show/hide the widgets, toggle design mode, reset group positions.
--   Icon extras   : proc glow (enable / style / colour) + range check. Applied live via
--                   E.IconExtras.ReapplyAll() (the reconcile seam built in Phase 4a).
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
    local function ReapplyExtras() if E.IconExtras and E.IconExtras.ReapplyAll then E.IconExtras.ReapplyAll() end end
    local function RebuildResources() if E.Resource and E.Resource.Rebuild then E.Resource.Rebuild() end end
    local function ProcGlowOn() return E.Cfg and E.Cfg.Get("procGlow") == true end
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
                    type = "checkbox", label = L["Design mode (drag to arrange)"],
                    get = function() return E.Design and E.Design.IsActive() end,
                    set = function(v)
                        if E.Design then if v then E.Design.Enter() else E.Design.Exit() end end
                        if menu then menu.Refresh() end   -- re-sync (Enter can bail in combat / Edit Mode)
                    end,
                },
                {
                    type = "button", label = L["Reset group positions"], width = 160,
                    onClick = function()
                        if E.Cfg then E.Cfg.ClearAllGroupPos() end
                        if E.Layout then E.Layout.ScheduleRebuild() end
                        if E.Design and E.Design.IsActive() then E.Design.Reattach() end
                    end,
                },
            } end,
        },

        -- ════════════ Icon extras (persisted; live via ReapplyAll) ════════════
        {
            type = "group", title = L["Icon extras"],
            build = function() return {
                {
                    type = "checkbox", label = L["Proc glow"],
                    get = function() return ProcGlowOn() end,
                    set = function(v)
                        if E.Cfg then E.Cfg.Set("procGlow", v) end
                        ReapplyExtras()
                        if menu then menu.Refresh() end   -- style/colour widgets gate on this
                    end,
                },
                {
                    type = "dropdown", label = L["Glow style"], width = 180, height = 50,
                    enabledBy = ProcGlowOn,
                    getList = function() return { "pixel", "autocast", "button", "proc" } end,
                    getCurrentKey = function() return (E.Cfg and E.Cfg.Get("glowType")) or "pixel" end,
                    onSelect = function(key)
                        if E.Cfg then E.Cfg.Set("glowType", key) end
                        ReapplyExtras()
                    end,
                },
                {
                    type = "textEditor", label = L["Glow colour"],
                    showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                    enabledBy = ProcGlowOn,
                    getColor = function()
                        local c = (E.Cfg and E.Cfg.Get("glowColor")) or { 0.96, 1, 0, 1 }
                        return { r = c[1] or 1, g = c[2] or 1, b = c[3] or 1, a = c[4] or 1 }
                    end,
                    onColorChange = function(r, g, b, a)
                        if E.Cfg then E.Cfg.Set("glowColor", { r, g, b, a }) end   -- stored positional (IconExtras reads c[1..4])
                        ReapplyExtras()
                    end,
                },
                {
                    type = "checkbox", label = L["Range check (red when out of range)"],
                    get = function() return E.Cfg and E.Cfg.Get("rangeCheck") == true end,
                    set = function(v)
                        if E.Cfg then E.Cfg.Set("rangeCheck", v) end
                        ReapplyExtras()
                    end,
                },
                {
                    type = "checkbox", label = L["Show the global cooldown sweep"],
                    get = function() return E.Cfg and E.Cfg.Get("showGcdSwipe") == true end,
                    set = function(v)
                        if E.Cfg then E.Cfg.Set("showGcdSwipe", v) end
                        if E.Layout and E.Layout.ScheduleRebuild then E.Layout.ScheduleRebuild() end   -- re-drive UpdateSwipe
                    end,
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
                        if E.Design and E.Design.IsActive() then E.Design.Reattach() end
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
