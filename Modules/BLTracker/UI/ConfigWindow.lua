-- Modules/BLTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

local function CreateBLTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["BL Tracker"] },

        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (instance filter, etc.)
            -- except the enable checkbox itself, which stays live to re-enable.
            gate  = { enabled = function() return BL.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable BL Tracker"],
                        height = 24,
                        get    = function() return BL.CfgGet("enabled") ~= false end,
                        set    = function(val) BL.CfgSet("enabled", val); if menu then menu.Refresh() end end,
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
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            enabledBy = function() return BL.CfgGet("enabled") ~= false end,
            build = function()
                return {
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
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            enabledBy = function() return BL.CfgGet("enabled") ~= false end,
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text) since there is no icon to configure; the checkbox stays live.
            gate      = { enabled = function() return BL.CfgGet("showIcon") ~= false end, master = "showicon" },
            build = function()
                return {
                    -- ── Show icon checkbox + Always-show toggle (inline, to its right) ────
                    {
                        type   = "checkbox",
                        ref    = "showicon",
                        label  = L["Show icon"],
                        height = 24,
                        get    = function() return BL.CfgGet("showIcon") ~= false end,
                        set    = function(val)
                            BL.CfgSet("showIcon", val)
                            BL.ApplyVisuals()
                        end,
                        inline = {
                            {
                                type  = "checkbox",
                                label = L["Always show"],
                                get   = function() return BL.CfgGet("alwaysShow") ~= false end,
                                set   = function(val)
                                    BL.CfgSet("alwaysShow", val)
                                    BL.ApplyVisuals()
                                end,
                                point = { "LEFT", "LEFT", 150, 0 },
                            },
                        },
                    },

                    -- Placement sub-box: Cooldown Manager slot OR free position.
                    -- "Include in cdm" toggles which controls show; its set calls
                    -- menu.Rebuild() so the CDM options swap with the position editor.
                    {
                        type  = "group",
                        title = L["Placement"],
                        build = function()
                            return {
                                -- ── Cooldown Manager integration ──────────────────────────────────────
                                {
                                    type = "checkbox",
                                    label = L["Include in cdm"],
                                    disabled = function() return not ns.IsCDMEnabled() end,
                                    get = function() return ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end,
                                    set = function(v)
                                        BL.CfgSet("includeInCdm", v); BL.ApplySize(); BL.ApplyPosition()
                                        if menu then menu.Rebuild() end
                                    end,
                                },
                                {
                                    type = "dropdown",
                                    label = L["Anchor to"],
                                    width = 200,
                                    height = 50,
                                    when = function() return ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end,
                                    getList = function() return ns.CDMDestList() end,
                                    getCurrentKey = function() return ns.CDMDestLabel(BL.CfgGet("cdmDest") or "essential") end,
                                    -- Row is clamped for DISPLAY only (getCurrentKey below); never written
                                    -- back here — LayoutCDMRow already clamps an out-of-range row at layout
                                    -- time, so a Row 2 saved for Essential is preserved when toggling anchor.
                                    onSelect = function(label) BL.CfgSet("cdmDest", ns.CDMDestKeyFromLabel(label)); BL.ApplySize(); BL.ApplyPosition(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type = "checkbox",
                                    label = L["Icon at the end of the row"],
                                    when = function() return ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end,
                                    get = function() return BL.CfgGet("cdmAtEnd") ~= false end,
                                    set = function(v) BL.CfgSet("cdmAtEnd", v); BL.ApplyPosition(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type = "dropdown",
                                    label = L["Row"],
                                    width = 120,
                                    height = 50,
                                    when = function() return ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end,
                                    getList = function() return ns.CDMRowList(BL.CfgGet("cdmDest") or "essential") end,
                                    getCurrentKey = function() return ns.CDMRowLabel(ns.CDMClampRow(BL.CfgGet("cdmDest") or "essential", BL.CfgGet("cdmRow"))) end,
                                    onSelect = function(label) BL.CfgSet("cdmRow", ns.CDMRowFromLabel(label)); BL.ApplyPosition(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type = "reorder",
                                    label = L["Move in row"],
                                    when = function() return ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end,
                                    getState = function() return ns.CDMAnchor.GetMoveState(BL.GetFrame()) end,
                                    onMove = function(dir) ns.CDMAnchor.Move(BL.GetFrame(), dir) end,
                                },
                                -- ── Position editor (named ref for the onLock self-refresh) ───────────
                                {
                                    type       = "position",
                                    ref        = "pe",
                                    when       = function() return not ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end,
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
                                -- ── Icon size  W / H  (composite -> custom escape hatch) ──────────────
                                {
                                    type   = "custom",
                                    height = 46,
                                    when   = function() return not ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end,
                                    build  = function(host)
                                        local sizeLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
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
                            }
                        end,
                    },

                    -- ── Border (sub-box) ──────────────────────────────────────────────────
                    {
                        type  = "group",
                        title = L["Border"],
                        build = function()
                            return {
                                {
                                    type  = "checkbox",
                                    label = L["Show border"],
                                    get   = function() return BL.CfgGet("borderEnabled") == true end,
                                    set   = function(v) BL.CfgSet("borderEnabled", v); BL.ApplyBorder(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type          = "textEditor",
                                    label         = L["Border color"],
                                    enabledBy     = function() return BL.CfgGet("borderEnabled") == true end,
                                    showText      = false,
                                    showFont      = false,
                                    showSize      = false,
                                    showOutline   = false,
                                    showColor     = true,
                                    getColor      = function() return BL.CfgGet("borderColor") end,
                                    onColorChange = function(r, g, b, a)
                                        BL.CfgSet("borderColor", { r = r, g = g, b = b, a = a })
                                        BL.ApplyBorder()
                                    end,
                                },
                                {
                                    type       = "textinput",
                                    label      = L["Border thickness"],
                                    enabledBy  = function() return BL.CfgGet("borderEnabled") == true end,
                                    width      = 46,
                                    numeric    = true,
                                    min        = 1,
                                    max        = 16,
                                    maxLetters = 2,
                                    get        = function() return BL.CfgGet("borderSize") or 1 end,
                                    set        = function(v) if v and v > 0 then BL.CfgSet("borderSize", v); BL.ApplyBorder() end end,
                                },
                            }
                        end,
                    },

                    -- ── Timer text (sub-box) ──────────────────────────────────────────────
                    {
                        type  = "group",
                        title = L["Timer text"],
                        build = function()
                            return {
                                {
                                    type            = "textEditor",
                                    LSM             = LSM,
                                    label           = L["Timer text"],
                                    showLabel       = false,
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
                        end,
                    },
                }
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
