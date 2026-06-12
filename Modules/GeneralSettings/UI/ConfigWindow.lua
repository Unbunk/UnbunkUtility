-- Modules/GeneralSettings/UI/ConfigWindow.lua
-- Four sub-tabs of the "General Settings" main tab:
--   Addon settings            — minimap button + welcome message
--   Player speed display      — on-screen speed readout
--   Multi-alert / anti-spam   — combo sounds + death-alert anti-spam + boss reset sound
--   Below player frame        — the CDM artificial row under the PlayerFrame

local _, ns = ...
local L = ns.L

local function H2(text) return { type = "label", font = "UnbunkUtilityH2", height = 26, text = text } end

-- ── Addon settings ────────────────────────────────────────────────────────────
local function CreateAddonSettingsPanel(parent)
    local options = {
        H2(L["Addon settings"]),

        {
            type  = "group",
            title = L["Minimap icon"],
            build = function()
                return {
                    {
                        type   = "checkbox",
                        label  = L["Show minimap button (left-click to open settings, drag to reposition)"],
                        get    = function() return not (ns.MinimapIcon_IsHidden and ns.MinimapIcon_IsHidden()) end,
                        set    = function(val)
                            if ns.MinimapIcon_SetHidden then ns.MinimapIcon_SetHidden(not val) end
                        end,
                    },
                }
            end,
        },

        {
            type  = "group",
            title = L["Welcome message"],
            build = function()
                return {
                    {
                        type   = "checkbox",
                        label  = L["Show the login message in chat"],
                        get    = function() return ns.Welcome_IsEnabled and ns.Welcome_IsEnabled() end,
                        set    = function(val)
                            if ns.Welcome_SetEnabled then ns.Welcome_SetEnabled(val) end
                        end,
                    },
                }
            end,
        },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

-- ── Player speed display ──────────────────────────────────────────────────────
local function CreatePlayerSpeedPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local SD  = ns.SpeedDisplay
    local menu  -- forward declare so the enable checkbox can re-evaluate the gate
    local options = {
        H2(L["Player speed display"]),

        {
            type  = "group",
            title = L["Speed display"],
            -- Unchecking "Show movement speed" greys the appearance / position
            -- sub-cadres; the enable checkbox itself stays live to re-enable.
            gate  = { enabled = function() return SD.CfgGet("enabled") == true end, master = "enable" },
            build = function() return {

                {
                    type   = "checkbox",
                    ref    = "enable",
                    label  = L["Show player movement speed on screen"],
                    height = 24,
                    get    = function() return SD.CfgGet("enabled") == true end,
                    set    = function(val)
                        SD.CfgSet("enabled", val)
                        SD.ApplyEnabled()
                        if menu then menu.Refresh() end
                    end,
                },

                -- ── Text appearance sub-cadre ─────────────────────────────────
                {
                    type  = "group",
                    title = L["Speed text appearance"],
                    build = function() return {
                        -- The colour is speed-driven, not user-picked.
                        { type = "label", text = L["|cffaaaaaaText colour changes with speed.|r"] },
                        {
                            type        = "textEditor",
                            LSM         = LSM,
                            label       = "",
                            showText    = false,
                            showColor   = false,
                            showFont    = true,
                            showSize    = true,
                            showOutline = true,
                            getFontKey  = function() return SD.CfgGet("fontKey") end,
                            getFontPath = function() return SD.CfgGet("fontPath") end,
                            getFontSize = function() return SD.CfgGet("fontSize") end,
                            getOutline  = function() return SD.CfgGet("outline") end,
                            onFontChange = function(key, path)
                                SD.CfgSet("fontKey", key)
                                SD.CfgSet("fontPath", path)
                                SD.ApplyFont()
                            end,
                            onSizeChange = function(val)
                                SD.CfgSet("fontSize", val)
                                SD.ApplyFont()
                            end,
                            onOutlineChange = function(val)
                                SD.CfgSet("outline", val)
                                SD.ApplyFont()
                            end,
                        },
                    } end,
                },

                -- ── Position sub-cadre ────────────────────────────────────────
                {
                    type  = "group",
                    title = L["Speed display position"],
                    build = function() return {
                        {
                            type       = "position",
                            ref        = "speedPE",
                            onBuilt    = function(w) ns.SpeedDisplay.pe = w end,
                            label      = "",
                            getX       = function() return SD.CfgGet("posX") end,
                            getY       = function() return SD.CfgGet("posY") end,
                            onApply    = function(x, yv)
                                if x  then SD.CfgSet("posX", x)  end
                                if yv then SD.CfgSet("posY", yv) end
                                SD.ApplyPosition()
                            end,
                            onUnlock   = function() SD.SetUnlocked(true) end,
                            onLock     = function()
                                SD.SetUnlocked(false)
                                if SD.pe then SD.pe.Refresh() end
                            end,
                            isUnlocked = function() return SD.IsUnlocked() end,
                        },
                    } end,
                },

            } end,
        },
    }
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    return menu
end

-- ── Multi-alert / anti-spam ───────────────────────────────────────────────────
local function CreateMultiAlertPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local options = {
        H2(L["Multi-alert / anti-spam"]),

        -- Combo sounds
        {
            type  = "group",
            title = L["Multi-alert combo sounds"],
            build = function()
                return {
                    {
                        type   = "checkbox",
                        label  = L["Enable combo sounds (collapse near-simultaneous tracker sounds into one)"],
                        get    = function() return ns.db.global.combo.enabled == true end,
                        set    = function(val) ns.db.global.combo.enabled = val end,
                    },
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["BL combo (Bloodlust + Potion / Trinket)"],
                        getKey    = function() return ns.db.global.combo.blKey end,
                        getEnable = function() return ns.db.global.combo.blEnabled end,
                        onSelect  = function(key, path)
                            ns.db.global.combo.blKey  = key
                            ns.db.global.combo.blPath = path
                        end,
                        onToggle  = function(val) ns.db.global.combo.blEnabled = val end,
                        onTest    = function() ns.combo.PlayBLCombo() end,
                    },
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Potion combo (Potion + Trinket, without BL)"],
                        getKey    = function() return ns.db.global.combo.potionKey end,
                        getEnable = function() return ns.db.global.combo.potionEnabled end,
                        onSelect  = function(key, path)
                            ns.db.global.combo.potionKey  = key
                            ns.db.global.combo.potionPath = path
                        end,
                        onToggle  = function(val) ns.db.global.combo.potionEnabled = val end,
                        onTest    = function() ns.combo.PlayPotionCombo() end,
                    },
                }
            end,
        },

        -- Death-alert anti-spam
        {
            type  = "group",
            title = L["Death alert anti-spam"],
            build = function()
                return {
                    {
                        type   = "custom",
                        height = 40,
                        build  = function(host)
                            local cb = ns.ui.CreateCheckbox({
                                parent  = host,
                                label   = L["Wipe detection: silence ALL death alerts when many people die at once"],
                                checked = ns.db.global.wipe.enabled == true,
                                onClick = function(val) ns.db.global.wipe.enabled = val end,
                            })
                            cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            local desc = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                            desc:SetPoint("TOPLEFT", host, "TOPLEFT", 26, -20)
                            desc:SetText(string.format(
                                L["|cffaaaaaa%d+ deaths in %ds, silence for %ds|r"],
                                ns.db.global.wipe.deathThreshold or 8,
                                ns.db.global.wipe.timeWindow or 3,
                                ns.db.global.wipe.suppressDuration or 15
                            ))
                            return {
                                frame   = host,
                                height  = 40,
                                Refresh = function() cb.SetChecked(ns.db.global.wipe.enabled == true) end,
                            }
                        end,
                    },
                    {
                        type   = "custom",
                        height = 40,
                        build  = function(host)
                            local cb = ns.ui.CreateCheckbox({
                                parent  = host,
                                label   = L["DPS spam guard: silence DPS death alerts on burst DPS deaths"],
                                checked = ns.db.global.dpsSpam.enabled == true,
                                onClick = function(val) ns.db.global.dpsSpam.enabled = val end,
                            })
                            cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            local desc = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                            desc:SetPoint("TOPLEFT", host, "TOPLEFT", 26, -20)
                            desc:SetText(string.format(
                                L["|cffaaaaaa%d+ DPS deaths in %ds, silence DPS alerts for %ds|r"],
                                ns.db.global.dpsSpam.deathThreshold or 3,
                                ns.db.global.dpsSpam.timeWindow or 3,
                                ns.db.global.dpsSpam.suppressDuration or 6
                            ))
                            return {
                                frame   = host,
                                height  = 40,
                                Refresh = function() cb.SetChecked(ns.db.global.dpsSpam.enabled == true) end,
                            }
                        end,
                    },
                }
            end,
        },

        -- Boss reset sound
        {
            type  = "group",
            title = L["Boss reset sound"],
            build = function()
                return {
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Play a sound when a boss is reset (raid/party wipe)"],
                        getKey    = function() return ns.db.global.bossReset.soundKey end,
                        getEnable = function() return ns.db.global.bossReset.enabled end,
                        onSelect  = function(key, path)
                            ns.db.global.bossReset.soundKey  = key
                            ns.db.global.bossReset.soundPath = path
                        end,
                        onToggle  = function(val) ns.db.global.bossReset.enabled = val end,
                        onTest    = function() ns.bossReset.PlayTest() end,
                    },
                }
            end,
        },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
end

-- ── Below player frame (CDM row) ──────────────────────────────────────────────
local function CreateBelowPlayerPanel(parent)
    local options = {
        H2(L["Below player frame"]),

        { type = "group", title = L["Cooldown Manager row"], build = function() return {

        -- Icon size (W / H)
        {
            type   = "custom",
            height = 46,
            build  = function(host)
                local function Row() return ns.db.global.cdmBelowRow end

                local sizeLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                sizeLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                sizeLbl:SetText(L["Icon size"])

                local wLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                wLbl:SetText(L["W"])

                local wInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22,
                    numeric = true, min = 8, max = 512, maxLetters = 3,
                    text = tostring((Row() and Row().width) or 36),
                    onEnter = function(val)
                        if val and val > 0 and Row() then
                            Row().width = val
                            if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
                        end
                    end,
                })
                wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

                local hLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
                hLbl:SetText(L["H"])

                local hInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22,
                    numeric = true, min = 8, max = 512, maxLetters = 3,
                    text = tostring((Row() and Row().height) or 36),
                    onEnter = function(val)
                        if val and val > 0 and Row() then
                            Row().height = val
                            if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
                        end
                    end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                return {
                    frame = host, height = 46,
                    Refresh = function()
                        wInput.SetText(tostring((Row() and Row().width)  or 36))
                        hInput.SetText(tostring((Row() and Row().height) or 36))
                    end,
                }
            end,
        },

        -- Manual offset from the PlayerFrame bottom-left corner.
        {
            type   = "custom",
            height = 46,
            build  = function(host)
                local function Row() return ns.db.global.cdmBelowRow end

                local offLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                offLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                offLbl:SetText(L["Offset"])

                local xLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                xLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                xLbl:SetText("X")

                local xInput = ns.ui.CreateTextInput({
                    parent = host, width = 56, height = 22,
                    numeric = true, allowNegative = true, min = -2000, max = 2000, maxLetters = 5,
                    text = tostring((Row() and Row().offsetX) or 0),
                    onEnter = function(val)
                        if val ~= nil and Row() then
                            Row().offsetX = val
                            if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
                        end
                    end,
                })
                xInput.frame:SetPoint("LEFT", xLbl, "RIGHT", 4, 0)

                local yLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                yLbl:SetPoint("LEFT", xInput.frame, "RIGHT", 12, 0)
                yLbl:SetText("Y")

                local yInput = ns.ui.CreateTextInput({
                    parent = host, width = 56, height = 22,
                    numeric = true, allowNegative = true, min = -2000, max = 2000, maxLetters = 5,
                    text = tostring((Row() and Row().offsetY) or 0),
                    onEnter = function(val)
                        if val ~= nil and Row() then
                            Row().offsetY = val
                            if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
                        end
                    end,
                })
                yInput.frame:SetPoint("LEFT", yLbl, "RIGHT", 4, 0)

                local function Refresh()
                    if not host:GetParent() then return end
                    xInput.SetText(tostring((Row() and Row().offsetX) or 0))
                    yInput.SetText(tostring((Row() and Row().offsetY) or 0))
                end
                ns.OnBelowRowMoved = Refresh

                return { frame = host, height = 46, Refresh = Refresh }
            end,
        },

        -- Unlock to drag the row to a custom spot.
        {
            type   = "custom",
            height = 28,
            build  = function(host)
                local function unlocked() return ns.CDMAnchor and ns.CDMAnchor.IsBelowUnlocked() end
                local btn, Refresh
                Refresh = function() if btn then btn.SetText(unlocked() and L["Lock"] or L["Unlock"]) end end
                btn = ns.ui.CreateButton({
                    parent  = host,
                    width   = 160,
                    height  = 22,
                    label   = unlocked() and L["Lock"] or L["Unlock"],
                    onClick = function()
                        if ns.CDMAnchor then ns.CDMAnchor.SetBelowUnlocked(not unlocked()) end
                        Refresh()
                    end,
                })
                btn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                return { frame = host, height = 28, Refresh = Refresh }
            end,
        },

        } end },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

-- ── Registration (four sub-tabs) ───────────────────────────────────────────────
local initGS = CreateFrame("Frame")
initGS:RegisterEvent("ADDON_LOADED")
initGS:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Addon settings"],          nil, CreateAddonSettingsPanel)
    UnbunkUtility.RegisterModule(L["Player speed display"],    nil, CreatePlayerSpeedPanel)
    UnbunkUtility.RegisterModule(L["Multi-alert / anti-spam"], nil, CreateMultiAlertPanel)
    UnbunkUtility.RegisterModule(L["Below player frame"],      nil, CreateBelowPlayerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
