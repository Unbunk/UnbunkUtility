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
    local menu  -- forward declare so enable/toggle closures can reach menu.Refresh/Rebuild

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
                            CS.ApplyEnabled()
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- Active in (instance types).
                    {
                        type      = "instanceFilter",
                        getConfig = function() return CS.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local f = CS.CfgGet("instanceFilter")
                            f[key] = val
                            CS.CfgSet("instanceFilter", f)
                            CS.Refresh()
                        end,
                    },

                    -- In-combat text + appearance (message / font / size / colour / outline).
                    {
                        type            = "textEditor",
                        LSM             = LSM,
                        label           = L["In-combat text"],
                        getText         = function() return CS.CfgGet("message") end,
                        getFontKey      = function() return CS.CfgGet("fontKey") end,
                        getFontPath     = function() return CS.CfgGet("fontPath") end,
                        getFontSize     = function() return CS.CfgGet("fontSize") end,
                        getColor        = function() return CS.CfgGet("color") end,
                        getOutline      = function() return CS.CfgGet("outline") end,
                        onTextChange    = function(t) CS.CfgSet("message", t); CS.Refresh() end,
                        onFontChange    = function(k, p) CS.CfgSet("fontKey", k); CS.CfgSet("fontPath", p); CS.ApplyFont(); CS.Refresh() end,
                        onSizeChange    = function(s) CS.CfgSet("fontSize", s); CS.ApplyFont(); CS.Refresh() end,
                        onColorChange   = function(r, g, b, a) CS.CfgSet("color", { r = r, g = g, b = b, a = a }); CS.ApplyFont() end,
                        onOutlineChange = function(o) CS.CfgSet("outline", o); CS.ApplyFont(); CS.Refresh() end,
                    },

                    -- Optional out-of-combat text (its input only shows when ticked).
                    {
                        type   = "checkbox",
                        label  = L["Also show a text out of combat"],
                        height = 24,
                        get    = function() return CS.CfgGet("showOutOfCombat") == true end,
                        set    = function(val)
                            CS.CfgSet("showOutOfCombat", val)
                            CS.Refresh()
                            if menu then menu.Rebuild() end
                        end,
                    },
                    {
                        type       = "textinput",
                        label      = L["Out-of-combat text"],
                        when       = function() return CS.CfgGet("showOutOfCombat") == true end,
                        maxLetters = 64,
                        get        = function() return CS.CfgGet("outOfCombatText") end,
                        set        = function(t) CS.CfgSet("outOfCombatText", t); CS.Refresh() end,
                    },

                    -- Position.
                    {
                        type       = "position",
                        onBuilt    = function(w) CS.pe = w end,
                        label      = L["Combat state text position"],
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

                    -- Timer text appearance (no message — it renders the elapsed time).
                    {
                        type            = "textEditor",
                        LSM             = LSM,
                        label           = L["Timer text"],
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

                    -- Position.
                    {
                        type       = "position",
                        onBuilt    = function(w) CT.pe = w end,
                        label      = L["Combat timer position"],
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
