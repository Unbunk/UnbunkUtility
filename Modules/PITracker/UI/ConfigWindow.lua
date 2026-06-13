-- Modules/PITracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

local function CreatePITrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["PI Tracker"] },

        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (Test button, instance
            -- filter) except the enable checkbox itself, which stays live to re-enable.
            gate  = { enabled = function() return PI.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable PI Tracker"],
                        height = 28,
                        disabled = function() return true end,   -- locked: feature unavailable
                        get    = function() return PI.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            PI.CfgSet("enabled", val)
                            PI.ApplyVisuals()
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- ── Test button (greys with the module — not the gate master) ─────────
                    {
                        type    = "button",
                        label   = L["Test"],
                        width   = 80,
                        height  = 22,
                        onClick = function() PI.RunTest(20) end,
                    },

                    -- Instance filter
                    {
                        type      = "instanceFilter",
                        getConfig = function() return PI.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local filter = PI.CfgGet("instanceFilter")
                            filter[key] = val
                            PI.CfgSet("instanceFilter", filter)
                        end,
                    },
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            enabledBy = function() return PI.CfgGet("enabled") ~= false end,
            build = function()
                return {
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
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            enabledBy = function() return PI.CfgGet("enabled") ~= false end,
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text) since there is no icon to configure; the checkbox stays live.
            gate      = { enabled = function() return PI.CfgGet("showIcon") ~= false end, master = "showicon" },
            build = function()
                return {
                    -- Show icon checkbox (gate master — stays live)
                    {
                        type   = "checkbox",
                        ref    = "showicon",
                        label  = L["Show icon"],
                        height = 24,
                        get    = function() return PI.CfgGet("showIcon") ~= false end,
                        set    = function(val)
                            PI.CfgSet("showIcon", val)
                            PI.ApplyVisuals()
                        end,
                    },

                    -- Placement sub-box: Cooldown Manager slot OR free position.
                    -- "Include in cdm" toggles which controls show; its set calls
                    -- menu.Rebuild() so the CDM options swap with the position editor.
                    {
                        type  = "group",
                        title = L["Placement"],
                        build = function()
                            return {
                                {
                                    type = "checkbox",
                                    label = L["Include in cdm"],
                                    disabled = function() return not ns.IsCDMEnabled() end,
                                    get = function() return ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end,
                                    set = function(v)
                                        PI.CfgSet("includeInCdm", v)
                                        PI.ApplySize(); PI.ApplyPosition()
                                        if menu then menu.Rebuild() end
                                    end,
                                },
                                {
                                    type = "dropdown",
                                    label = L["Anchor to"],
                                    width = 200,
                                    height = 50,
                                    when = function() return ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end,
                                    getList = function() return ns.CDMDestList() end,
                                    getCurrentKey = function() return ns.CDMDestLabel(PI.CfgGet("cdmDest") or "essential") end,
                                    onSelect = function(label) PI.CfgSet("cdmDest", ns.CDMDestKeyFromLabel(label)); PI.ApplySize(); PI.ApplyPosition(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type = "checkbox",
                                    label = L["Icon at the end of the row"],
                                    when = function() return ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end,
                                    get = function() return PI.CfgGet("cdmAtEnd") ~= false end,
                                    set = function(v) PI.CfgSet("cdmAtEnd", v); PI.ApplyPosition(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type = "dropdown",
                                    label = L["Row"],
                                    width = 120,
                                    height = 50,
                                    when = function() return ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end,
                                    getList = function() return ns.CDMRowList(PI.CfgGet("cdmDest") or "essential") end,
                                    getCurrentKey = function() return ns.CDMRowLabel(ns.CDMClampRow(PI.CfgGet("cdmDest") or "essential", PI.CfgGet("cdmRow"))) end,
                                    onSelect = function(label) PI.CfgSet("cdmRow", ns.CDMRowFromLabel(label)); PI.ApplyPosition(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type = "reorder",
                                    label = L["Move in row"],
                                    when = function() return ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end,
                                    getState = function() return ns.CDMAnchor.GetMoveState(PI.GetFrame()) end,
                                    onMove = function(dir) ns.CDMAnchor.Move(PI.GetFrame(), dir) end,
                                },
                                -- Free icon position (only when NOT in the CDM)
                                {
                                    type       = "position",
                                    ref        = "pe",
                                    when       = function() return not ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end,
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
                                -- Icon size — free mode only. In the CDM the size is
                                -- automatic: native row size (essential/utility) or the
                                -- account-wide below-player row size (General Settings).
                                {
                                    type   = "custom",
                                    height = 46,
                                    when   = function() return not ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end,
                                    build  = function(host)
                                        local sizeLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                                        sizeLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                                        sizeLbl:SetText(L["Icon size"])

                                        local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
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

                                        local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
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
                                    get   = function() return PI.CfgGet("borderEnabled") == true end,
                                    set   = function(v) PI.CfgSet("borderEnabled", v); PI.ApplyBorder(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type          = "textEditor",
                                    label         = L["Border color"],
                                    enabledBy     = function() return PI.CfgGet("borderEnabled") == true end,
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
                                    enabledBy  = function() return PI.CfgGet("borderEnabled") == true end,
                                    width      = 46,
                                    numeric    = true,
                                    min        = 1,
                                    max        = 16,
                                    maxLetters = 2,
                                    get        = function() return PI.CfgGet("borderSize") or 1 end,
                                    set        = function(v) if v and v > 0 then PI.CfgSet("borderSize", v); PI.ApplyBorder() end end,
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
                        end,
                    },
                }
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    -- NOTE: no parent:HookScript("OnShow", ...) here anymore — BuildMenu did it.

    -- Feature-unavailable banner. Put it in its own frame raised WAY above the greyed
    -- cadres AND the disable-gate click-blockers (those sit at host level + 500), so the
    -- red text reads clearly on top of everything. Anchored a bit above centre.
    local bannerFrame = CreateFrame("Frame", nil, parent)
    bannerFrame:SetAllPoints(parent)
    bannerFrame:SetFrameLevel((parent:GetFrameLevel() or 0) + 1000)
    local banner = bannerFrame:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    banner:SetPoint("CENTER", bannerFrame, "CENTER", 0, 100)
    banner:SetJustifyH("CENTER")
    banner:SetText(L["|cffff4444Feature unavailable since Midnight changes.\nWorking on it...|r"])

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
