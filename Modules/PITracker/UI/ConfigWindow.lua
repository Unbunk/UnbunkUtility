-- Modules/PITracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

local function CreatePITrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        -- ── Enable checkbox + Test button (inline) ────────────────────────────
        {
            type   = "checkbox",
            label  = L["Enable PI Tracker"],
            height = 28,
            get    = function() return PI.CfgGet("enabled") ~= false end,
            set    = function(val)
                PI.CfgSet("enabled", val)
                PI.ApplyVisuals()
            end,
            inline = {
                {
                    type    = "button",
                    label   = L["Test"],
                    width   = 80,
                    height  = 22,
                    onClick = function() PI.RunTest(20) end,
                    -- testBtn.frame:SetPoint("LEFT", enableCb.frame, "RIGHT", 180, 0)
                    point   = { "LEFT", "RIGHT", 180, 0 },
                },
            },
        },

        -- ── Instance filter ───────────────────────────────────────────────────
        {
            type      = "instanceFilter",
            getConfig = function() return PI.CfgGet("instanceFilter") end,
            setConfig = function(key, val)
                local filter = PI.CfgGet("instanceFilter")
                filter[key] = val
                PI.CfgSet("instanceFilter", filter)
            end,
        },

        -- ── Sound PI ──────────────────────────────────────────────────────────
        {
            type      = "sound",
            LSM       = LSM,
            label     = L["Sound on PI"],
            getKey    = function() return PI.CfgGet("soundKeyPI") end,
            getEnable = function() return PI.CfgGet("soundOnPI") end,
            onSelect  = function(key, path)
                PI.CfgSet("soundKeyPI", key)
                PI.CfgSet("soundPathPI", path)
            end,
            onToggle  = function(val) PI.CfgSet("soundOnPI", val) end,
            onTest    = function() PI.PlaySound() end,
        },

        -- ── Show icon checkbox ────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Show icon"],
            height = 24,
            get    = function() return PI.CfgGet("showIcon") ~= false end,
            set    = function(val)
                PI.CfgSet("showIcon", val)
                PI.ApplyVisuals()
            end,
        },

        -- ── Icon size  W / H  (composite -> custom escape hatch) ──────────────
        {
            type   = "custom",
            height = 46,
            build  = function(host)
                local sizeLbl = host:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                sizeLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                sizeLbl:SetText(L["Icon size"])

                local wLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                wLbl:SetText(L["W"])

                local wInput = ns.ui.CreateTextInput({
                    parent     = host,
                    width      = 46,
                    height     = 22,
                    numeric    = true,
                    min        = 8,
                    max        = 512,
                    maxLetters = 3,
                    text       = tostring(PI.CfgGet("iconWidth") or 40),
                    onEnter    = function(val)
                        if val and val > 0 then
                            PI.CfgSet("iconWidth", val)
                            PI.ApplySize()
                        end
                    end,
                })
                wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

                local hLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
                hLbl:SetText(L["H"])

                local hInput = ns.ui.CreateTextInput({
                    parent     = host,
                    width      = 46,
                    height     = 22,
                    numeric    = true,
                    min        = 8,
                    max        = 512,
                    maxLetters = 3,
                    text       = tostring(PI.CfgGet("iconHeight") or 40),
                    onEnter    = function(val)
                        if val and val > 0 then
                            PI.CfgSet("iconHeight", val)
                            PI.ApplySize()
                        end
                    end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                return {
                    frame   = host,
                    height  = 46,
                    Refresh = function()
                        wInput.SetText(tostring(PI.CfgGet("iconWidth")  or 40))
                        hInput.SetText(tostring(PI.CfgGet("iconHeight") or 40))
                    end,
                }
            end,
        },

        -- ── Border ─────────────────────────────────────────────────────────────
        {
            type  = "checkbox",
            label = L["Show border"],
            get   = function() return PI.CfgGet("borderEnabled") == true end,
            set   = function(v) PI.CfgSet("borderEnabled", v); PI.ApplyBorder() end,
        },
        {
            type          = "textEditor",
            label         = L["Border color"],
            showText      = false,
            showFont      = false,
            showSize      = false,
            showOutline   = false,
            showColor     = true,
            getColor      = function() return PI.CfgGet("borderColor") end,
            onColorChange = function(r, g, b, a)
                PI.CfgSet("borderColor", { r = r, g = g, b = b, a = a })
                PI.ApplyBorder()
            end,
        },
        {
            type       = "textinput",
            label      = L["Border thickness"],
            width      = 46,
            numeric    = true,
            min        = 1,
            max        = 16,
            maxLetters = 2,
            get        = function() return PI.CfgGet("borderSize") or 1 end,
            set        = function(v) if v and v > 0 then PI.CfgSet("borderSize", v); PI.ApplyBorder() end end,
        },

        -- ── Position editor (named ref for the onLock self-refresh) ───────────
        {
            type       = "position",
            ref        = "pe",
            onBuilt    = function(w) PI.pe = w end,
            label      = L["Icon position (offset from screen center)"],
            getX       = function() return PI.CfgGet("posX") end,
            getY       = function() return PI.CfgGet("posY") end,
            onApply    = function(x, yv)
                if x  then PI.CfgSet("posX", x)  end
                if yv then PI.CfgSet("posY", yv) end
                PI.ApplyPosition()
            end,
            onUnlock   = function() PI.SetUnlocked(true) end,
            onLock     = function()
                PI.SetUnlocked(false)
                if PI.pe then PI.pe.Refresh() end
            end,
            isUnlocked = function() return PI.IsUnlocked() end,
        },

        -- ── Timer text ────────────────────────────────────────────────────────
        {
            type            = "textEditor",
            LSM             = LSM,
            label           = L["Timer text"],
            showText        = false,
            showFont        = true,
            showSize        = true,
            showColor       = true,
            showOutline     = true,
            getFontKey      = function() return PI.CfgGet("timerFontKey") end,
            getFontPath     = function() return PI.CfgGet("timerFontPath") end,
            getFontSize     = function() return PI.CfgGet("timerFontSize") end,
            getColor        = function() return PI.CfgGet("timerColor") end,
            getOutline      = function() return PI.CfgGet("timerOutline") end,
            onFontChange    = function(key, path)
                PI.CfgSet("timerFontKey", key)
                PI.CfgSet("timerFontPath", path)
                PI.ApplyFont()
            end,
            onSizeChange    = function(size)
                PI.CfgSet("timerFontSize", size)
                PI.ApplyFont()
            end,
            onColorChange   = function(r, g, b, a)
                PI.CfgSet("timerColor", { r = r, g = g, b = b, a = a })
                PI.ApplyFont()
            end,
            onOutlineChange = function(outline)
                PI.CfgSet("timerOutline", outline)
                PI.ApplyFont()
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    -- NOTE: no parent:HookScript("OnShow", ...) here anymore — BuildMenu did it.
    return menu
end

-- ── Enregistrement ──────────────────────────────────────────────────────────────

local initPIUI = CreateFrame("Frame")
initPIUI:RegisterEvent("ADDON_LOADED")
initPIUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["PI Tracker"], nil, CreatePITrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
