-- Modules/CombatSettings/UI/ConfigWindow.lua
-- The "Combat settings" sub-tab (Combat Utilities): two independent on-screen
-- display modules in their own cadres — Combat state text and Combat timer. Each
-- has its own enable (greys the rest of its cadre when off), instance filter,
-- text appearance and position, driven through ns.CombatState / ns.CombatTimer.

local _, ns = ...
local L = ns.L

local function CreateCombatSettingsPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local CS  = ns.CombatState
    local CT  = ns.CombatTimer
    local menu  -- forward declare so enable closures can reach menu.Refresh()

    -- Build a textEditor entry (message + font/size/colour/outline) bound to a set
    -- of config keys with a custom prefix, applying via the given on-change hook.
    local function TextEditor(getMsg, setMsg, prefix, onChange)
        return {
            type            = "textEditor",
            LSM             = LSM,
            showLabel       = false,   -- the sub-cadre title already names it
            getText         = getMsg,
            getFontKey      = function() return CS.CfgGet(prefix .. "FontKey") end,
            getFontPath     = function() return CS.CfgGet(prefix .. "FontPath") end,
            getFontSize     = function() return CS.CfgGet(prefix .. "FontSize") end,
            getColor        = function() return CS.CfgGet(prefix .. "Color") end,
            getOutline      = function() return CS.CfgGet(prefix .. "Outline") end,
            onTextChange    = function(t) setMsg(t); onChange() end,
            onFontChange    = function(k, p) CS.CfgSet(prefix .. "FontKey", k); CS.CfgSet(prefix .. "FontPath", p); onChange() end,
            onSizeChange    = function(s) CS.CfgSet(prefix .. "FontSize", s); onChange() end,
            onColorChange   = function(r, g, b, a) CS.CfgSet(prefix .. "Color", { r = r, g = g, b = b, a = a }); onChange() end,
            onOutlineChange = function(o) CS.CfgSet(prefix .. "Outline", o); onChange() end,
        }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Combat settings"] },

        -- ════════════ Combat state text ════════════
        {
            type  = "group",
            title = L["Combat state text"],
            gate  = { enabled = function() return CS.CfgGet("enabled") == true end, master = "csEnable" },
            build = function()
                return {
                    -- Enable (gate master — stays live).
                    {
                        type   = "checkbox",
                        ref    = "csEnable",
                        label  = L["Enable combat state text"],
                        height = 24,
                        get    = function() return CS.CfgGet("enabled") == true end,
                        set    = function(val)
                            CS.CfgSet("enabled", val)
                            CS.SetEnabled(val == true)   -- live start/stop the combat watcher
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- Active in (instance types).
                    {
                        type      = "instanceFilter",
                        getConfig = function() return CS.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local f = CS.CfgGet("instanceFilter") or {}
                            f[key] = val
                            CS.CfgSet("instanceFilter", f)
                            CS.Refresh()
                        end,
                    },

                    -- ── In-combat text sub-cadre ──────────────────────────────────
                    {
                        type  = "group",
                        title = L["In-combat text"],
                        build = function()
                            return {
                                TextEditor(
                                    function() return CS.CfgGet("message") end,
                                    function(t) CS.CfgSet("message", t) end,
                                    "in", function() CS.OnInChanged() end
                                ),
                            }
                        end,
                    },

                    -- ── Out-of-combat text sub-cadre (greys when the box is off) ───
                    {
                        type  = "group",
                        title = L["Out-of-combat text"],
                        gate  = { enabled = function() return CS.CfgGet("showOutOfCombat") == true end, master = "csShowOoc" },
                        build = function()
                            return {
                                {
                                    type   = "checkbox",
                                    ref    = "csShowOoc",
                                    label  = L["Show text out of combat"],
                                    height = 24,
                                    get    = function() return CS.CfgGet("showOutOfCombat") == true end,
                                    set    = function(val)
                                        CS.CfgSet("showOutOfCombat", val)
                                        CS.Refresh()
                                    end,
                                },
                                TextEditor(
                                    function() return CS.CfgGet("outOfCombatText") end,
                                    function(t) CS.CfgSet("outOfCombatText", t) end,
                                    "out", function() CS.OnOutChanged() end
                                ),
                            }
                        end,
                    },

                    -- ── Position sub-cadre ────────────────────────────────────────
                    {
                        type  = "group",
                        title = L["Combat state text position"],
                        build = function()
                            return {
                                {
                                    type       = "position",
                                    onBuilt    = function(w) CS.pe = w end,
                                    label      = "",
                                    getX       = function() return CS.CfgGet("posX") end,
                                    getY       = function() return CS.CfgGet("posY") end,
                                    onApply    = function(x, y)
                                        if x then CS.CfgSet("posX", x) end
                                        if y then CS.CfgSet("posY", y) end
                                        CS.ApplyPosition()
                                    end,
                                    onUnlock   = function() CS.SetUnlocked(true) end,
                                    onLock     = function() CS.SetUnlocked(false); if CS.pe then CS.pe.Refresh() end end,
                                    isUnlocked = function() return CS.IsUnlocked() end,
                                },
                            }
                        end,
                    },
                }
            end,
        },

        -- ════════════ Combat timer ════════════
        {
            type  = "group",
            title = L["Combat timer"],
            gate  = { enabled = function() return CT.CfgGet("enabled") == true end, master = "ctEnable" },
            build = function()
                return {
                    -- Enable (gate master — stays live).
                    {
                        type   = "checkbox",
                        ref    = "ctEnable",
                        label  = L["Enable combat timer"],
                        height = 24,
                        get    = function() return CT.CfgGet("enabled") == true end,
                        set    = function(val)
                            CT.CfgSet("enabled", val)
                            CT.ApplyEnabled()
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- Active in (instance types).
                    {
                        type      = "instanceFilter",
                        getConfig = function() return CT.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local f = CT.CfgGet("instanceFilter")
                            f[key] = val
                            CT.CfgSet("instanceFilter", f)
                            CT.Refresh()
                        end,
                    },

                    -- ── Timer text sub-cadre (appearance — it renders the elapsed time) ──
                    {
                        type  = "group",
                        title = L["Timer text"],
                        build = function()
                            return {
                                {
                                    type            = "textEditor",
                                    LSM             = LSM,
                                    showLabel       = false,
                                    showText        = false,
                                    getFontKey      = function() return CT.CfgGet("fontKey") end,
                                    getFontPath     = function() return CT.CfgGet("fontPath") end,
                                    getFontSize     = function() return CT.CfgGet("fontSize") end,
                                    getColor        = function() return CT.CfgGet("color") end,
                                    getOutline      = function() return CT.CfgGet("outline") end,
                                    onFontChange    = function(k, p) CT.CfgSet("fontKey", k); CT.CfgSet("fontPath", p); CT.ApplyFont() end,
                                    onSizeChange    = function(s) CT.CfgSet("fontSize", s); CT.ApplyFont() end,
                                    onColorChange   = function(r, g, b, a) CT.CfgSet("color", { r = r, g = g, b = b, a = a }); CT.ApplyFont() end,
                                    onOutlineChange = function(o) CT.CfgSet("outline", o); CT.ApplyFont() end,
                                },
                            }
                        end,
                    },

                    -- ── Position sub-cadre ────────────────────────────────────────
                    {
                        type  = "group",
                        title = L["Combat timer position"],
                        build = function()
                            return {
                                {
                                    type       = "position",
                                    onBuilt    = function(w) CT.pe = w end,
                                    label      = "",
                                    getX       = function() return CT.CfgGet("posX") end,
                                    getY       = function() return CT.CfgGet("posY") end,
                                    onApply    = function(x, y)
                                        if x then CT.CfgSet("posX", x) end
                                        if y then CT.CfgSet("posY", y) end
                                        CT.ApplyPosition()
                                    end,
                                    onUnlock   = function() CT.SetUnlocked(true) end,
                                    onLock     = function() CT.SetUnlocked(false); if CT.pe then CT.pe.Refresh() end end,
                                    isUnlocked = function() return CT.IsUnlocked() end,
                                },
                            }
                        end,
                    },

                    -- Out-of-combat behaviour (at the bottom).
                    {
                        type   = "checkbox",
                        label  = L["Hide out of combat"],
                        height = 24,
                        get    = function() return CT.CfgGet("hideOutOfCombat") == true end,
                        set    = function(val) CT.CfgSet("hideOutOfCombat", val); CT.Refresh() end,
                    },
                    {
                        type   = "checkbox",
                        label  = L["Reset out of combat"],
                        height = 24,
                        get    = function() return CT.CfgGet("resetOutOfCombat") == true end,
                        set    = function(val) CT.CfgSet("resetOutOfCombat", val); CT.Refresh() end,
                    },
                }
            end,
        },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    return menu
end

-- ── Registration ───────────────────────────────────────────────────────────────
local initCSUI = CreateFrame("Frame")
initCSUI:RegisterEvent("ADDON_LOADED")
initCSUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Combat settings"], nil, CreateCombatSettingsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
