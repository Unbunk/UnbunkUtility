-- Modules/BResTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

local SIDES = { "Left", "Right", "Above", "Below" }

-- The stored side value stays the raw English key (Core/PlayerList branches on it
-- literally), so the dropdowns show localised labels and map label<->key for
-- display only (mirrors CDMDestLabel/CDMDestKeyFromLabel).
local function SideLabels()
    local t = {}
    for i, k in ipairs(SIDES) do t[i] = L[k] end
    return t
end
local function SideLabel(key) return L[key or "Left"] end
local function SideKeyFromLabel(label)
    for _, k in ipairs(SIDES) do if L[k] == label then return k end end
    return "Left"
end

local function CreateBResTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["BRez Tracker"] },

        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (instance filter, etc.)
            -- except the enable checkbox itself, which stays live to re-enable.
            gate  = { enabled = function() return BR.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable BRez Tracker"],
                        height = 28,
                        get    = function() return BR.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            BR.CfgSet("enabled", val)
                            BR.ApplyVisuals()
                            if BR.RefreshList then BR.RefreshList() end
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- ── Test button (below enable; greys with the module when disabled) ───
                    {
                        type    = "button",
                        label   = L["Test"],
                        width   = 80,
                        height  = 22,
                        onClick = function() BR.RunTest(15) end,
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
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            enabledBy = function() return BR.CfgGet("enabled") ~= false end,
            build = function()
                return {
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
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            enabledBy = function() return BR.CfgGet("enabled") ~= false end,
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text) since there is no icon to configure; the checkbox stays live.
            gate      = { enabled = function() return BR.CfgGet("showIcon") ~= false end, master = "showicon" },
            build = function()
                return {
                    -- ── Show icon checkbox ────────────────────────────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "showicon",
                        label  = L["Show icon"],
                        height = 24,
                        get    = function() return BR.CfgGet("showIcon") ~= false end,
                        set    = function(val)
                            BR.CfgSet("showIcon", val)
                            BR.ApplyVisuals()
                        end,
                    },

                    -- ── Placement sub-box: Cooldown Manager slot OR free position. ────────
                    -- "Include in cdm" toggles which controls show; its set calls
                    -- menu.Rebuild() so the CDM options swap with the position editor.
                    {
                        type  = "group",
                        title = L["Placement"],
                        build = function()
                            return {
                                -- ── Cooldown Manager integration ──────────────────────────────
                                { type = "checkbox", label = L["Include in cdm"],
                                  disabled = function() return not ns.IsCDMEnabled() end,
                                  get = function() return ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) end,
                                  set = function(v) BR.CfgSet("includeInCdm", v); BR.ApplySize(); BR.ApplyPosition(); if menu then menu.Rebuild() end end },
                                { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                                  when = function() return ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) end,
                                  getList = function() return ns.CDMDestList() end,
                                  getCurrentKey = function() return ns.CDMDestLabel(BR.CfgGet("cdmDest") or "essential") end,
                                  onSelect = function(label) BR.CfgSet("cdmDest", ns.CDMDestKeyFromLabel(label)); BR.ApplySize(); BR.ApplyPosition(); if menu then menu.Refresh() end end },
                                { type = "checkbox", label = L["Icon at the end of the row"],
                                  when = function() return ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) end,
                                  get = function() return BR.CfgGet("cdmAtEnd") ~= false end,
                                  set = function(v) BR.CfgSet("cdmAtEnd", v); BR.ApplyPosition(); if menu then menu.Refresh() end end },
                                { type = "dropdown", label = L["Row"], width = 120, height = 50,
                                  when = function() return ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) end,
                                  getList = function() return ns.CDMRowList(BR.CfgGet("cdmDest") or "essential") end,
                                  getCurrentKey = function() return ns.CDMRowLabel(ns.CDMClampRow(BR.CfgGet("cdmDest") or "essential", BR.CfgGet("cdmRow"))) end,
                                  onSelect = function(label) BR.CfgSet("cdmRow", ns.CDMRowFromLabel(label)); BR.ApplyPosition(); if menu then menu.Refresh() end end },
                                { type = "reorder", label = L["Move in row"],
                                  when = function() return ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) end,
                                  getState = function() return ns.CDMAnchor.GetMoveState(BR.GetFrame()) end,
                                  onMove = function(dir) ns.CDMAnchor.Move(BR.GetFrame(), dir) end },

                                -- ── Position editor (named ref for the onLock self-refresh) ───────────
                                {
                                    type       = "position",
                                    ref        = "pe",
                                    when       = function() return not ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) end,
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
                                -- ── Icon size  W / H  (composite -> custom escape hatch) ──────────────
                                -- Free mode only. In the CDM the size is automatic.
                                {
                                    type   = "custom",
                                    height = 46,
                                    when   = function() return not ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) end,
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
                                    get = function() return BR.CfgGet("borderEnabled") == true end,
                                    set = function(v) BR.CfgSet("borderEnabled", v); BR.ApplyBorder(); if menu then menu.Refresh() end end,
                                },
                                {
                                    type = "textEditor", label = L["Border color"],
                                    enabledBy = function() return BR.CfgGet("borderEnabled") == true end,
                                    showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                                    getColor = function() return BR.CfgGet("borderColor") end,
                                    onColorChange = function(r, g, b, a) BR.CfgSet("borderColor", { r = r, g = g, b = b, a = a }); BR.ApplyBorder() end,
                                },
                                {
                                    type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
                                    enabledBy = function() return BR.CfgGet("borderEnabled") == true end,
                                    get = function() return BR.CfgGet("borderSize") or 1 end,
                                    set = function(v) if v and v > 0 then BR.CfgSet("borderSize", v); BR.ApplyBorder() end end,
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
                        end,
                    },
                }
            end,
        },

        -- ════════════ Player list ════════════
        -- Top-level group (sibling of Icon): greys when the MODULE is disabled, but is
        -- intentionally NOT inside the Icon group's "Show icon" gate — the player list is
        -- unrelated to the icon and must stay configurable while the icon is hidden.
        {
            type  = "group",
            title = L["Player list"],
            enabledBy = function() return BR.CfgGet("enabled") ~= false end,
            build = function()
                return {
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
                                            getList       = SideLabels,
                                            getCurrentKey = function() return SideLabel(BR.CfgGet("listSide")) end,
                                            onSelect      = function(label)
                                                BR.CfgSet("listSide", SideKeyFromLabel(label))
                                                if BR.ApplyListPosition then BR.ApplyListPosition() end
                                                if BR.RefreshList       then BR.RefreshList()       end
                                            end,
                                        })
                                        listSideDD.selectedText:SetText(SideLabel(BR.CfgGet("listSide")))
                                        return {
                                            frame   = host,
                                            height  = 46,
                                            Refresh = function()
                                                listSideDD.selectedText:SetText(SideLabel(BR.CfgGet("listSide")))
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
                                            getList       = SideLabels,
                                            getCurrentKey = function() return SideLabel(BR.CfgGet("rowStatusSide")) end,
                                            onSelect      = function(label)
                                                BR.CfgSet("rowStatusSide", SideKeyFromLabel(label))
                                                if BR.RefreshList then BR.RefreshList() end
                                            end,
                                        })
                                        statusSideDD.selectedText:SetText(SideLabel(BR.CfgGet("rowStatusSide")))
                                        return {
                                            frame   = host,
                                            height  = 46,
                                            Refresh = function()
                                                statusSideDD.selectedText:SetText(SideLabel(BR.CfgGet("rowStatusSide")))
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
                }
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
