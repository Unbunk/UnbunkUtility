-- Modules/BLTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

local function CreateBLTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        -- ── Enable checkbox ───────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Enable BL Tracker"],
            height = 24,
            get    = function() return BL.CfgGet("enabled") ~= false end,
            set    = function(val) BL.CfgSet("enabled", val) end,
        },

        -- ── Instance filter ───────────────────────────────────────────────────
        {
            type      = "instanceFilter",
            getConfig = function() return BL.CfgGet("instanceFilter") end,
            setConfig = function(key, val)
                local filter = BL.CfgGet("instanceFilter")
                filter[key] = val
                BL.CfgSet("instanceFilter", filter)
            end,
        },

        -- ── Sound on Bloodlust ────────────────────────────────────────────────
        {
            type      = "sound",
            LSM       = LSM,
            label     = L["Sound on Bloodlust"],
            getKey    = function() return BL.CfgGet("soundKeyBL") end,
            getEnable = function() return BL.CfgGet("soundOnBL") end,
            onSelect  = function(key, path)
                BL.CfgSet("soundKeyBL", key)
                BL.CfgSet("soundPathBL", path)
            end,
            onToggle  = function(val) BL.CfgSet("soundOnBL", val) end,
            onTest    = function() BL.PlaySound("soundPathBL") end,
        },

        -- ── Sound when Bloodlust ready ────────────────────────────────────────
        {
            type      = "sound",
            LSM       = LSM,
            label     = L["Sound when Bloodlust ready"],
            getKey    = function() return BL.CfgGet("soundKeyReady") end,
            getEnable = function() return BL.CfgGet("soundOnReady") end,
            onSelect  = function(key, path)
                BL.CfgSet("soundKeyReady", key)
                BL.CfgSet("soundPathReady", path)
            end,
            onToggle  = function(val) BL.CfgSet("soundOnReady", val) end,
            onTest    = function() BL.PlaySound("soundPathReady") end,
        },

        -- ── Show icon checkbox ────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Show icon"],
            height = 24,
            get    = function() return BL.CfgGet("showIcon") ~= false end,
            set    = function(val)
                BL.CfgSet("showIcon", val)
                BL.ApplyVisuals()
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
                    text       = tostring(BL.CfgGet("iconWidth") or 40),
                    onEnter    = function(val)
                        if val and val > 0 then
                            BL.CfgSet("iconWidth", val)
                            BL.ApplySize()
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
                    text       = tostring(BL.CfgGet("iconHeight") or 40),
                    onEnter    = function(val)
                        if val and val > 0 then
                            BL.CfgSet("iconHeight", val)
                            BL.ApplySize()
                        end
                    end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                return {
                    frame   = host,
                    height  = 46,
                    Refresh = function()
                        wInput.SetText(tostring(BL.CfgGet("iconWidth")  or 40))
                        hInput.SetText(tostring(BL.CfgGet("iconHeight") or 40))
                    end,
                }
            end,
        },

        -- ── Position editor (named ref for the onLock self-refresh) ───────────
        {
            type       = "position",
            ref        = "pe",
            onBuilt    = function(w) BL.pe = w end,
            label      = L["Icon position (offset from screen center)"],
            getX       = function() return BL.CfgGet("posX") end,
            getY       = function() return BL.CfgGet("posY") end,
            onApply    = function(x, yv)
                if x  then BL.CfgSet("posX", x)  end
                if yv then BL.CfgSet("posY", yv) end
                BL.ApplyPosition()
            end,
            onUnlock   = function() BL.SetUnlocked(true) end,
            onLock     = function()
                BL.SetUnlocked(false)
                if BL.pe then BL.pe.Refresh() end
            end,
            isUnlocked = function() return BL.IsUnlocked() end,
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
            getFontKey      = function() return BL.CfgGet("timerFontKey") end,
            getFontPath     = function() return BL.CfgGet("timerFontPath") end,
            getFontSize     = function() return BL.CfgGet("timerFontSize") end,
            getColor        = function() return BL.CfgGet("timerColor") end,
            getOutline      = function() return BL.CfgGet("timerOutline") end,
            onFontChange    = function(key, path)
                BL.CfgSet("timerFontKey", key)
                BL.CfgSet("timerFontPath", path)
                BL.ApplyFont()
            end,
            onSizeChange    = function(size)
                BL.CfgSet("timerFontSize", size)
                BL.ApplyFont()
            end,
            onColorChange   = function(r, g, b, a)
                BL.CfgSet("timerColor", { r = r, g = g, b = b, a = a })
                BL.ApplyFont()
            end,
            onOutlineChange = function(outline)
                BL.CfgSet("timerOutline", outline)
                BL.ApplyFont()
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    -- NOTE: no parent:HookScript("OnShow", ...) here anymore — BuildMenu did it.
    return menu
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initBLUI = CreateFrame("Frame")
initBLUI:RegisterEvent("ADDON_LOADED")
initBLUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["BL Tracker"], nil, CreateBLTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
