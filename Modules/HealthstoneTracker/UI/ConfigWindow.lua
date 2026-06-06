-- Modules/HealthstoneTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

local function CreateHealthstoneTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        -- ── Test button (toggles Test / Stop Test) ────────────────────────────
        {
            type   = "custom",
            height = 30,
            build  = function(host)
                local testBtn
                local function RefreshTestBtn()
                    testBtn.SetText(HT.IsTesting() and L["Stop Test"] or L["Test"])
                end

                testBtn = ns.ui.CreateButton({
                    parent  = host,
                    label   = L["Test"],
                    width   = 100,
                    height  = 22,
                    onClick = function()
                        if HT.IsTesting() then
                            HT.StopTest()
                        else
                            HT.RunTest()
                        end
                        RefreshTestBtn()
                    end,
                })
                testBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -4)

                return {
                    frame   = host,
                    height  = 30,
                    Refresh = RefreshTestBtn,
                }
            end,
        },

        -- ── Enable checkbox ───────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Enable Healthstone Tracker"],
            get    = function() return HT.CfgGet("enabled") ~= false end,
            set    = function(val)
                HT.CfgSet("enabled", val)
                HT.ApplyAll()
            end,
        },

        -- ── Instance filter ───────────────────────────────────────────────────
        {
            type      = "instanceFilter",
            getConfig = function() return HT.CfgGet("instanceFilter") end,
            setConfig = function(key, val)
                local filter = HT.CfgGet("instanceFilter")
                filter[key] = val
                HT.CfgSet("instanceFilter", filter)
            end,
        },

        -- ── Sound on use ──────────────────────────────────────────────────────
        {
            type      = "sound",
            LSM       = LSM,
            label     = L["Sound on use"],
            getKey    = function() return HT.CfgGet("soundKeyUse") end,
            getEnable = function() return HT.CfgGet("soundOnUse") end,
            onSelect  = function(key, path)
                HT.CfgSet("soundKeyUse", key)
                HT.CfgSet("soundPathUse", path)
            end,
            onToggle  = function(val) HT.CfgSet("soundOnUse", val) end,
            onTest    = function() HT.PlaySound("soundUse") end,
        },

        -- ── Sound when ready ──────────────────────────────────────────────────
        {
            type      = "sound",
            LSM       = LSM,
            label     = L["Sound when ready"],
            getKey    = function() return HT.CfgGet("soundKeyReady") end,
            getEnable = function() return HT.CfgGet("soundOnReady") end,
            onSelect  = function(key, path)
                HT.CfgSet("soundKeyReady", key)
                HT.CfgSet("soundPathReady", path)
            end,
            onToggle  = function(val) HT.CfgSet("soundOnReady", val) end,
            onTest    = function() HT.PlaySound("soundReady") end,
        },

        -- ── Show icon checkbox ────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Show icon"],
            get    = function() return HT.CfgGet("showIcon") ~= false end,
            set    = function(val)
                HT.CfgSet("showIcon", val)
                HT.ApplyAll()
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
                    text       = tostring(HT.CfgGet("iconWidth") or 30),
                    onEnter    = function(val)
                        if val and val > 0 then
                            HT.CfgSet("iconWidth", val)
                            local t = HT.GetTracker()
                            if t and t.ApplySize then t.ApplySize() end
                            HT.ApplyAll()
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
                    text       = tostring(HT.CfgGet("iconHeight") or 30),
                    onEnter    = function(val)
                        if val and val > 0 then
                            HT.CfgSet("iconHeight", val)
                            local t = HT.GetTracker()
                            if t and t.ApplySize then t.ApplySize() end
                            HT.ApplyAll()
                        end
                    end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                return {
                    frame   = host,
                    height  = 46,
                    Refresh = function()
                        wInput.SetText(tostring(HT.CfgGet("iconWidth")  or 30))
                        hInput.SetText(tostring(HT.CfgGet("iconHeight") or 30))
                    end,
                }
            end,
        },

        -- ── Border ────────────────────────────────────────────────────────────
        {
            type = "checkbox", label = L["Show border"],
            get = function() return HT.CfgGet("borderEnabled") == true end,
            set = function(v) HT.CfgSet("borderEnabled", v); HT.ApplyBorder() end,
        },
        {
            type = "textEditor", label = L["Border color"],
            showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
            getColor = function() return HT.CfgGet("borderColor") end,
            onColorChange = function(r, g, b, a) HT.CfgSet("borderColor", { r = r, g = g, b = b, a = a }); HT.ApplyBorder() end,
        },
        {
            type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
            get = function() return HT.CfgGet("borderSize") or 1 end,
            set = function(v) if v and v > 0 then HT.CfgSet("borderSize", v); HT.ApplyBorder() end end,
        },

        -- ── Position editor (named ref for the onLock self-refresh) ───────────
        {
            type       = "position",
            ref        = "pe",
            onBuilt    = function(w) HT.pe = w end,
            label      = L["Icon position (offset from screen center)"],
            getX       = function() return HT.CfgGet("posX") end,
            getY       = function() return HT.CfgGet("posY") end,
            onApply    = function(x, yv)
                if x  then HT.CfgSet("posX", x)  end
                if yv then HT.CfgSet("posY", yv) end
                HT.ApplyAll()
            end,
            onUnlock   = function() HT.SetUnlocked(true)  end,
            onLock     = function()
                HT.SetUnlocked(false)
                if HT.pe then HT.pe.Refresh() end
            end,
            isUnlocked = function() return HT.IsUnlocked() end,
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
            getFontKey      = function() return HT.CfgGet("timerFontKey") end,
            getFontPath     = function() return HT.CfgGet("timerFontPath") end,
            getFontSize     = function() return HT.CfgGet("timerFontSize") end,
            getColor        = function() return HT.CfgGet("timerColor") end,
            getOutline      = function() return HT.CfgGet("timerOutline") end,
            onFontChange    = function(key, path)
                HT.CfgSet("timerFontKey", key)
                HT.CfgSet("timerFontPath", path)
                HT.ApplyTimerVisuals()
            end,
            onSizeChange    = function(size)
                HT.CfgSet("timerFontSize", size)
                HT.ApplyTimerVisuals()
            end,
            onColorChange   = function(r, g, b, a)
                HT.CfgSet("timerColor", { r = r, g = g, b = b, a = a })
                HT.ApplyTimerVisuals()
            end,
            onOutlineChange = function(outline)
                HT.CfgSet("timerOutline", outline)
                HT.ApplyTimerVisuals()
            end,
        },

        -- ── Stack text ────────────────────────────────────────────────────────
        {
            type            = "textEditor",
            LSM             = LSM,
            label           = L["Stack text"],
            showText        = false,
            showFont        = true,
            showSize        = true,
            showColor       = true,
            showOutline     = true,
            getFontKey      = function() return HT.CfgGet("stackFontKey") end,
            getFontPath     = function() return HT.CfgGet("stackFontPath") end,
            getFontSize     = function() return HT.CfgGet("stackFontSize") end,
            getColor        = function() return HT.CfgGet("stackColor") end,
            getOutline      = function() return HT.CfgGet("stackOutline") end,
            onFontChange    = function(key, path)
                HT.CfgSet("stackFontKey", key)
                HT.CfgSet("stackFontPath", path)
                HT.ApplyStackVisuals()
            end,
            onSizeChange    = function(size)
                HT.CfgSet("stackFontSize", size)
                HT.ApplyStackVisuals()
            end,
            onColorChange   = function(r, g, b, a)
                HT.CfgSet("stackColor", { r = r, g = g, b = b, a = a })
                HT.ApplyStackVisuals()
            end,
            onOutlineChange = function(outline)
                HT.CfgSet("stackOutline", outline)
                HT.ApplyStackVisuals()
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    -- NOTE: no parent:HookScript("OnShow", ...) here anymore — BuildMenu did it.
    return menu
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initHTUI = CreateFrame("Frame")
initHTUI:RegisterEvent("ADDON_LOADED")
initHTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Healthstone Tracker"], nil, CreateHealthstoneTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
