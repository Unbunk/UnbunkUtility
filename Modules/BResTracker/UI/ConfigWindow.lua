-- Modules/BResTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

local SIDES = { "Left", "Right", "Above", "Below" }

local function CreateBResTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        -- ── Enable checkbox + Test button (inline) ────────────────────────────
        {
            type   = "checkbox",
            label  = L["Enable BRez Tracker"],
            height = 28,
            get    = function() return BR.CfgGet("enabled") ~= false end,
            set    = function(val)
                BR.CfgSet("enabled", val)
                BR.ApplyVisuals()
                if BR.RefreshList then BR.RefreshList() end
            end,
            inline = {
                {
                    type    = "button",
                    label   = L["Test"],
                    width   = 80,
                    height  = 22,
                    onClick = function() BR.RunTest(15) end,
                    -- testBtn.frame:SetPoint("LEFT", enableCb.frame, "RIGHT", 180, 0)
                    point   = { "LEFT", "RIGHT", 180, 0 },
                },
            },
        },

        -- ── Instance filter ───────────────────────────────────────────────────
        {
            type      = "instanceFilter",
            getConfig = function() return BR.CfgGet("instanceFilter") end,
            setConfig = function(key, val)
                local filter = BR.CfgGet("instanceFilter")
                filter[key] = val
                BR.CfgSet("instanceFilter", filter)
            end,
        },

        -- ── Sound on charge regained ──────────────────────────────────────────
        {
            type      = "sound",
            LSM       = LSM,
            label     = L["Sound on charge regained"],
            getKey    = function() return BR.CfgGet("soundKeyReady") end,
            getEnable = function() return BR.CfgGet("soundOnReady") end,
            onSelect  = function(key, path)
                BR.CfgSet("soundKeyReady", key)
                BR.CfgSet("soundPathReady", path)
            end,
            onToggle  = function(val) BR.CfgSet("soundOnReady", val) end,
            onTest    = function() BR.PlaySound() end,
        },

        -- ── Sound on BRes used ────────────────────────────────────────────────
        {
            type      = "sound",
            LSM       = LSM,
            label     = L["Sound on BRes used"],
            getKey    = function() return BR.CfgGet("soundKeyUsed") end,
            getEnable = function() return BR.CfgGet("soundOnUsed") end,
            onSelect  = function(key, path)
                BR.CfgSet("soundKeyUsed", key)
                BR.CfgSet("soundPathUsed", path)
            end,
            onToggle  = function(val) BR.CfgSet("soundOnUsed", val) end,
            onTest    = function() BR.PlaySoundUsed() end,
        },

        -- ── Show icon checkbox ────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Show icon"],
            height = 24,
            get    = function() return BR.CfgGet("showIcon") ~= false end,
            set    = function(val)
                BR.CfgSet("showIcon", val)
                BR.ApplyVisuals()
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
                    text       = tostring(BR.CfgGet("iconWidth") or 45),
                    onEnter    = function(val)
                        if val and val > 0 then
                            BR.CfgSet("iconWidth", val)
                            BR.ApplySize()
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
                    text       = tostring(BR.CfgGet("iconHeight") or 45),
                    onEnter    = function(val)
                        if val and val > 0 then
                            BR.CfgSet("iconHeight", val)
                            BR.ApplySize()
                        end
                    end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                return {
                    frame   = host,
                    height  = 46,
                    Refresh = function()
                        wInput.SetText(tostring(BR.CfgGet("iconWidth")  or 45))
                        hInput.SetText(tostring(BR.CfgGet("iconHeight") or 45))
                    end,
                }
            end,
        },

        -- ── Border ────────────────────────────────────────────────────────────
        {
            type = "checkbox", label = L["Show border"],
            get = function() return BR.CfgGet("borderEnabled") == true end,
            set = function(v) BR.CfgSet("borderEnabled", v); BR.ApplyBorder() end,
        },
        {
            type = "textEditor", label = L["Border color"],
            showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
            getColor = function() return BR.CfgGet("borderColor") end,
            onColorChange = function(r, g, b, a) BR.CfgSet("borderColor", { r = r, g = g, b = b, a = a }); BR.ApplyBorder() end,
        },
        {
            type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
            get = function() return BR.CfgGet("borderSize") or 1 end,
            set = function(v) if v and v > 0 then BR.CfgSet("borderSize", v); BR.ApplyBorder() end end,
        },

        -- ── Position editor (named ref for the onLock self-refresh) ───────────
        {
            type       = "position",
            ref        = "pe",
            onBuilt    = function(w) BR.pe = w end,
            label      = L["Icon position (offset from screen center)"],
            getX       = function() return BR.CfgGet("posX") end,
            getY       = function() return BR.CfgGet("posY") end,
            onApply    = function(x, yv)
                if x  then BR.CfgSet("posX", x)  end
                if yv then BR.CfgSet("posY", yv) end
                BR.ApplyPosition()
            end,
            onUnlock   = function() BR.SetUnlocked(true) end,
            onLock     = function()
                BR.SetUnlocked(false)
                if BR.pe then BR.pe.Refresh() end
            end,
            isUnlocked = function() return BR.IsUnlocked() end,
        },

        -- ── Player list (optional submodule) ──────────────────────────────────
        {
            type = "header",
            text = L["Player list"],
            font = "GameFontNormalLarge",
        },

        {
            type   = "checkbox",
            label  = L["Enable player list"],
            height = 24,
            get    = function() return BR.CfgGet("listEnabled") == true end,
            set    = function(val)
                BR.CfgSet("listEnabled", val)
                if BR.RefreshList then BR.RefreshList() end
            end,
        },

        -- List side dropdown (Left / Right / Above / Below)
        {
            type   = "custom",
            height = 46,
            build  = function(host)
                local listSideLbl = host:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                listSideLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                listSideLbl:SetText(L["List position relative to icon"])
                local listSideAnchor = host:CreateFontString(nil, "ARTWORK")
                listSideAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                local listSideDD = ns.ui.CreateDropdown({
                    parent        = host,
                    anchorFrame   = listSideAnchor,
                    width         = 120,
                    itemHeight    = 20,
                    visibleItems  = 4,
                    getList       = function() return SIDES end,
                    getCurrentKey = function() return BR.CfgGet("listSide") or "Left" end,
                    onSelect      = function(name)
                        BR.CfgSet("listSide", name)
                        if BR.ApplyListPosition then BR.ApplyListPosition() end
                        if BR.RefreshList       then BR.RefreshList()       end
                    end,
                })
                listSideDD.selectedText:SetText(BR.CfgGet("listSide") or "Left")
                return {
                    frame   = host,
                    height  = 46,
                    Refresh = function()
                        listSideDD.selectedText:SetText(BR.CfgGet("listSide") or "Left")
                    end,
                }
            end,
        },

        -- Status side dropdown (Left / Right / Above / Below)
        {
            type   = "custom",
            height = 46,
            build  = function(host)
                local statusSideLbl = host:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                statusSideLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                statusSideLbl:SetText(L["Status icon / timer position relative to name"])
                local statusSideAnchor = host:CreateFontString(nil, "ARTWORK")
                statusSideAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                local statusSideDD = ns.ui.CreateDropdown({
                    parent        = host,
                    anchorFrame   = statusSideAnchor,
                    width         = 120,
                    itemHeight    = 20,
                    visibleItems  = 4,
                    getList       = function() return SIDES end,
                    getCurrentKey = function() return BR.CfgGet("rowStatusSide") or "Left" end,
                    onSelect      = function(name)
                        BR.CfgSet("rowStatusSide", name)
                        if BR.RefreshList then BR.RefreshList() end
                    end,
                })
                statusSideDD.selectedText:SetText(BR.CfgGet("rowStatusSide") or "Left")
                return {
                    frame   = host,
                    height  = 46,
                    Refresh = function()
                        statusSideDD.selectedText:SetText(BR.CfgGet("rowStatusSide") or "Left")
                    end,
                }
            end,
        },

        -- Estimated per-player cooldown (seconds) for the list timers. See the
        -- listCooldownEstimate note in Config.lua / PlayerList.lua. Kept as a
        -- custom block to preserve the exact label(0,0) + input(0,-20) layout
        -- (BuildMenu's textinput anchors the box via BOTTOMLEFT,-2 instead).
        {
            type   = "custom",
            height = 46,
            build  = function(host)
                local cdLbl = host:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                cdLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                cdLbl:SetText(L["Estimated BRes cooldown (seconds)"])
                local cdInput = ns.ui.CreateTextInput({
                    parent     = host,
                    width      = 60,
                    height     = 22,
                    numeric    = true,
                    min        = 1,
                    max        = 3600,
                    maxLetters = 4,
                    text       = tostring(BR.CfgGet("listCooldownEstimate") or 600),
                    onEnter    = function(val)
                        if val and val > 0 then
                            BR.CfgSet("listCooldownEstimate", val)
                            if BR.RefreshList then BR.RefreshList() end
                        end
                    end,
                })
                cdInput.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                return {
                    frame   = host,
                    height  = 46,
                    Refresh = function()
                        cdInput.SetText(tostring(BR.CfgGet("listCooldownEstimate") or 600))
                    end,
                }
            end,
        },

        -- Name text editor (font / size / outline; color is class-based)
        {
            type            = "textEditor",
            LSM             = LSM,
            label           = L["Player name text"],
            showText        = false,
            showFont        = true,
            showSize        = true,
            showColor       = false,
            showOutline     = true,
            getFontKey      = function() return BR.CfgGet("listFontKey") end,
            getFontPath     = function() return BR.CfgGet("listFontPath") end,
            getFontSize     = function() return BR.CfgGet("listFontSize") end,
            getOutline      = function() return BR.CfgGet("listOutline") end,
            onFontChange    = function(key, path)
                BR.CfgSet("listFontKey", key)
                BR.CfgSet("listFontPath", path)
                if BR.RefreshList then BR.RefreshList() end
            end,
            onSizeChange    = function(size)
                BR.CfgSet("listFontSize", size)
                if BR.RefreshList then BR.RefreshList() end
            end,
            onOutlineChange = function(outline)
                BR.CfgSet("listOutline", outline)
                if BR.RefreshList then BR.RefreshList() end
            end,
        },

        -- ── Timer text editor ─────────────────────────────────────────────────
        {
            type            = "textEditor",
            LSM             = LSM,
            label           = L["Timer text"],
            showText        = false,
            showFont        = true,
            showSize        = true,
            showColor       = true,
            showOutline     = true,
            getFontKey      = function() return BR.CfgGet("timerFontKey") end,
            getFontPath     = function() return BR.CfgGet("timerFontPath") end,
            getFontSize     = function() return BR.CfgGet("timerFontSize") end,
            getColor        = function() return BR.CfgGet("timerColor") end,
            getOutline      = function() return BR.CfgGet("timerOutline") end,
            onFontChange    = function(key, path)
                BR.CfgSet("timerFontKey", key)
                BR.CfgSet("timerFontPath", path)
                BR.ApplyFont()
            end,
            onSizeChange    = function(size)
                BR.CfgSet("timerFontSize", size)
                BR.ApplyFont()
            end,
            onColorChange   = function(r, g, b, a)
                BR.CfgSet("timerColor", { r = r, g = g, b = b, a = a })
                BR.ApplyFont()
            end,
            onOutlineChange = function(outline)
                BR.CfgSet("timerOutline", outline)
                BR.ApplyFont()
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    -- NOTE: no parent:HookScript("OnShow", ...) here anymore — BuildMenu did it.
    return menu
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initBRUI = CreateFrame("Frame")
initBRUI:RegisterEvent("ADDON_LOADED")
initBRUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["BRez Tracker"], nil, CreateBResTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
