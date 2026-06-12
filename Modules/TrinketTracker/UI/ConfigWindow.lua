-- Modules/TrinketTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.TrinketTracker = ns.TrinketTracker or {}
local TT = ns.TrinketTracker

-- Build the ORDERED option list for a single trinket section ("trinket1" /
-- "trinket2"). Returned to BuildMenu via the "section" entry's `build` callback,
-- which wraps it in a nested BuildMenu (inner width 500, gap 10, origin 8/-8 —
-- exactly matching the former imperative CreateTrinketSection + AddWidget).
local function BuildTrinketOptions(prefix, LSM)
    local function GetCfg(key)
        local cfg = TT.CfgGet(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = TT.CfgGet(prefix)
        if cfg then
            cfg[key] = val
            TT.CfgSet(prefix, cfg)
        end
    end

    local tracker = prefix == "trinket1" and TT.GetTracker1() or TT.GetTracker2()

    return {
        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            build = function()
                return {
                    -- ── Sound use ─────────────────────────────────────────────────────────
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound on use"],
                        getKey    = function() return GetCfg("soundKeyUse") end,
                        getEnable = function() return GetCfg("soundOnUse") end,
                        onSelect  = function(key, path)
                            SetCfg("soundKeyUse", key)
                            SetCfg("soundPathUse", path)
                        end,
                        onToggle  = function(val) SetCfg("soundOnUse", val) end,
                        onTest    = function() TT.PlaySound(prefix, "soundUse") end,
                    },

                    -- ── Sound ready ───────────────────────────────────────────────────────
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound when ready"],
                        getKey    = function() return GetCfg("soundKeyReady") end,
                        getEnable = function() return GetCfg("soundOnReady") end,
                        onSelect  = function(key, path)
                            SetCfg("soundKeyReady", key)
                            SetCfg("soundPathReady", path)
                        end,
                        onToggle  = function(val) SetCfg("soundOnReady", val) end,
                        onTest    = function() TT.PlaySound(prefix, "soundReady") end,
                    },
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text) since there is no icon to configure; the checkbox stays live.
            gate  = { enabled = function() return GetCfg("showIcon") ~= false end, master = "showicon" },
            build = function()
                return {
                    -- ── Show icon checkbox (gate master — stays live) ─────────────────────
                    {
                        type   = "checkbox",
                        ref    = "showicon",
                        label  = L["Show icon"],
                        height = 24,
                        get    = function() return GetCfg("showIcon") ~= false end,
                        set    = function(val)
                            SetCfg("showIcon", val)
                            TT.ApplyAll()
                        end,
                    },

                    -- ── Placement sub-box: Cooldown Manager slot OR free position. ────────
                    -- "Include in cdm" toggles which controls show; its set calls
                    -- TT.configMenu.Rebuild() so the CDM options swap with the position editor.
                    {
                        type  = "group",
                        title = L["Placement"],
                        build = function()
                            return {
                                {
                                    type = "checkbox", label = L["Include in cdm"],
                                    disabled = function() return not ns.IsCDMEnabled() end,
                                    get = function() return ns.CDMIncludedVal(GetCfg("includeInCdm")) end,
                                    set = function(v)
                                        SetCfg("includeInCdm", v)
                                        if tracker then tracker.ApplySize() end
                                        if tracker then tracker.ApplyPosition() end
                                        if TT.configMenu then TT.configMenu.Rebuild() end
                                    end,
                                },
                                {
                                    type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                                    when = function() return ns.CDMIncludedVal(GetCfg("includeInCdm")) end,
                                    getList = function() return ns.CDMDestList() end,
                                    getCurrentKey = function() return ns.CDMDestLabel(GetCfg("cdmDest") or "essential") end,
                                    onSelect = function(label)
                                        SetCfg("cdmDest", ns.CDMDestKeyFromLabel(label))
                                        if tracker then tracker.ApplySize() end
                                        if tracker then tracker.ApplyPosition() end
                                        if TT.configMenu then TT.configMenu.Refresh() end
                                    end,
                                },
                                {
                                    type = "checkbox", label = L["Icon at the end of the row"],
                                    when = function() return ns.CDMIncludedVal(GetCfg("includeInCdm")) end,
                                    get = function() return GetCfg("cdmAtEnd") ~= false end,
                                    set = function(v)
                                        SetCfg("cdmAtEnd", v)
                                        if tracker then tracker.ApplyPosition() end
                                        if TT.configMenu then TT.configMenu.Refresh() end
                                    end,
                                },
                                {
                                    type = "dropdown", label = L["Row"], width = 120, height = 50,
                                    when = function() return ns.CDMIncludedVal(GetCfg("includeInCdm")) end,
                                    getList = function() return ns.CDMRowList(GetCfg("cdmDest") or "essential") end,
                                    getCurrentKey = function() return ns.CDMRowLabel(ns.CDMClampRow(GetCfg("cdmDest") or "essential", GetCfg("cdmRow"))) end,
                                    onSelect = function(label)
                                        SetCfg("cdmRow", ns.CDMRowFromLabel(label))
                                        if tracker then tracker.ApplyPosition() end
                                        if TT.configMenu then TT.configMenu.Refresh() end
                                    end,
                                },
                                {
                                    type = "reorder", label = L["Move in row"],
                                    when = function() return ns.CDMIncludedVal(GetCfg("includeInCdm")) end,
                                    getState = function() return ns.CDMAnchor.GetMoveState(tracker and tracker.GetFrame()) end,
                                    onMove = function(dir) ns.CDMAnchor.Move(tracker and tracker.GetFrame(), dir) end,
                                },

                                -- ── Position editor (ref captured into tracker.pe for onLock refresh) ─
                                -- Free icon position (only when NOT in the CDM)
                                {
                                    type       = "position",
                                    ref        = "pe",
                                    when       = function() return not ns.CDMIncludedVal(GetCfg("includeInCdm")) end,
                                    onBuilt    = function(w) if tracker then tracker.pe = w end end,
                                    label      = L["Icon position (offset from screen center)"],
                                    getX       = function() return GetCfg("posX") end,
                                    getY       = function() return GetCfg("posY") end,
                                    onApply    = function(x, yv)
                                        if x  then SetCfg("posX", x)  end
                                        if yv then SetCfg("posY", yv) end
                                        TT.ApplyAll()
                                    end,
                                    onUnlock   = function() if tracker then tracker.SetUnlocked(true) end end,
                                    onLock     = function()
                                        if tracker then tracker.SetUnlocked(false) end
                                        if tracker and tracker.pe then tracker.pe.Refresh() end
                                    end,
                                    isUnlocked = function() return tracker and tracker.IsUnlocked() end,
                                },

                                -- ── Icon size  W / H  (composite -> custom escape hatch) ──────────────
                                -- Free mode only. In the CDM the size is automatic.
                                {
                                    type   = "custom",
                                    height = 46,
                                    when   = function() return not ns.CDMIncludedVal(GetCfg("includeInCdm")) end,
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
                                            text       = tostring(GetCfg("iconWidth") or 40),
                                            onEnter    = function(val)
                                                if val and val > 0 then
                                                    SetCfg("iconWidth", val)
                                                    if tracker then tracker.ApplySize() end
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
                                            text       = tostring(GetCfg("iconHeight") or 40),
                                            onEnter    = function(val)
                                                if val and val > 0 then
                                                    SetCfg("iconHeight", val)
                                                    if tracker then tracker.ApplySize() end
                                                end
                                            end,
                                        })
                                        hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                                        return {
                                            frame   = host,
                                            height  = 46,
                                            Refresh = function()
                                                wInput.SetText(tostring(GetCfg("iconWidth")  or 40))
                                                hInput.SetText(tostring(GetCfg("iconHeight") or 40))
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
                                    type = "checkbox", label = L["Show border"],
                                    get = function() return GetCfg("borderEnabled") == true end,
                                    set = function(v) SetCfg("borderEnabled", v); if tracker then tracker.ApplyBorder() end; if TT.configMenu then TT.configMenu.Refresh() end end,
                                },
                                {
                                    type = "textEditor", label = L["Border color"],
                                    enabledBy = function() return GetCfg("borderEnabled") == true end,
                                    showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                                    getColor = function() return GetCfg("borderColor") end,
                                    onColorChange = function(r, g, b, a)
                                        SetCfg("borderColor", { r = r, g = g, b = b, a = a })
                                        if tracker then tracker.ApplyBorder() end
                                    end,
                                },
                                {
                                    type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
                                    enabledBy = function() return GetCfg("borderEnabled") == true end,
                                    get = function() return GetCfg("borderSize") or 1 end,
                                    set = function(v)
                                        if v and v > 0 then
                                            SetCfg("borderSize", v)
                                            if tracker then tracker.ApplyBorder() end
                                        end
                                    end,
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
                                    getFontKey      = function() return GetCfg("timerFontKey") end,
                                    getFontPath     = function() return GetCfg("timerFontPath") end,
                                    getFontSize     = function() return GetCfg("timerFontSize") end,
                                    getColor        = function() return GetCfg("timerColor") end,
                                    getOutline      = function() return GetCfg("timerOutline") end,
                                    onFontChange    = function(key, path)
                                        SetCfg("timerFontKey", key)
                                        SetCfg("timerFontPath", path)
                                        if tracker then tracker.ApplyFont() end
                                    end,
                                    onSizeChange    = function(size)
                                        SetCfg("timerFontSize", size)
                                        if tracker then tracker.ApplyFont() end
                                    end,
                                    onColorChange   = function(r, g, b, a)
                                        SetCfg("timerColor", { r = r, g = g, b = b, a = a })
                                        if tracker then tracker.ApplyFont() end
                                    end,
                                    onOutlineChange = function(outline)
                                        SetCfg("timerOutline", outline)
                                        if tracker then tracker.ApplyFont() end
                                    end,
                                },
                            }
                        end,
                    },
                }
            end,
        },

        -- ── Trailing spacer ───────────────────────────────────────────────────
        -- Reproduces the original section's "height = height + 16" bottom pad so
        -- the collapsible section reserves exactly the same vertical space.
        {
            type   = "label",
            text   = "",
            height = 16,
        },
    }
end

local function CreateTrinketTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local options = {
        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys the instance filter ("active in") while the
            -- enable checkbox stays live to re-enable.
            gate  = { enabled = function() return TT.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable Trinket Tracker"],
                        height = 24,
                        get    = function() return TT.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            TT.CfgSet("enabled", val)
                            TT.ApplyAll()
                            if TT.configMenu then TT.configMenu.Refresh() end
                        end,
                    },

                    -- ── Instance filter ───────────────────────────────────────────────────
                    {
                        type      = "instanceFilter",
                        getConfig = function() return TT.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local filter = TT.CfgGet("instanceFilter")
                            filter[key] = val
                            TT.CfgSet("instanceFilter", filter)
                        end,
                    },
                }
            end,
        },

        -- ── Trinket 1 section ─────────────────────────────────────────────────
        {
            type      = "section",
            label     = L["Trinket 1 (slot 1)"],
            enabledBy = function() return TT.CfgGet("enabled") ~= false end,
            isChecked = function() return TT.CfgGet("trinket1") and TT.CfgGet("trinket1").enabled end,
            onCheck   = function(val)
                local cfg = TT.CfgGet("trinket1")
                cfg.enabled = val
                TT.CfgSet("trinket1", cfg)
                TT.ApplyAll()
            end,
            getCollapsed = function() return TT._uiCollapsed and TT._uiCollapsed["trinket1"] end,
            onCollapse   = function(v) TT._uiCollapsed = TT._uiCollapsed or {}; TT._uiCollapsed["trinket1"] = v end,
            build     = function() return BuildTrinketOptions("trinket1", LSM) end,
        },

        -- ── Trinket 2 section ─────────────────────────────────────────────────
        {
            type      = "section",
            label     = L["Trinket 2 (slot 2)"],
            enabledBy = function() return TT.CfgGet("enabled") ~= false end,
            isChecked = function() return TT.CfgGet("trinket2") and TT.CfgGet("trinket2").enabled end,
            onCheck   = function(val)
                local cfg = TT.CfgGet("trinket2")
                cfg.enabled = val
                TT.CfgSet("trinket2", cfg)
                TT.ApplyAll()
            end,
            getCollapsed = function() return TT._uiCollapsed and TT._uiCollapsed["trinket2"] end,
            onCollapse   = function(v) TT._uiCollapsed = TT._uiCollapsed or {}; TT._uiCollapsed["trinket2"] = v end,
            build     = function() return BuildTrinketOptions("trinket2", LSM) end,
        },
    }

    -- Top-level stack uses gap=8 (former AddSection GAP). innerWidth=500 makes
    -- each section's nested widgets host at 500 like the old AddWidget did
    -- (SoundPicker/PositionEditor/TextEditor still pin their content to 518
    -- internally). autoHook=true generates the OnShow re-sync automatically.
    TT.configMenu = ns.ui.BuildMenu(parent, options, {
        gap        = 8,
        width      = 518,
        innerWidth = 500,
        LSM        = LSM,
    })
    return TT.configMenu
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initTTUI = CreateFrame("Frame")
initTTUI:RegisterEvent("ADDON_LOADED")
initTTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Trinket Tracker"], nil, CreateTrinketTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
