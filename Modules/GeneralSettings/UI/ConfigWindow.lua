-- Modules/GeneralSettings/UI/ConfigWindow.lua
-- Global addon-wide options: combo sounds + death-alert anti-spam toggles.
-- Profile management lives in its own tab (Modules/Profiles/UI/ConfigWindow.lua).

local _, ns = ...
local L = ns.L

local function CreateGeneralSettingsPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local options = {
        -- ── Minimap icon section ─────────────────────────────────────────────
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

        -- ── Player speed display section ─────────────────────────────────────
        -- On-screen movement-speed readout (engine in Modules/SpeedDisplay).
        -- The text colour is driven by the speed tier, so no colour picker here.
        {
            type  = "group",
            title = L["Player speed display"],
            build = function()
                local SD = ns.SpeedDisplay
                return {
                    {
                        type   = "checkbox",
                        label  = L["Show player movement speed on screen"],
                        get    = function() return SD.CfgGet("enabled") == true end,
                        set    = function(val)
                            SD.CfgSet("enabled", val)
                            SD.ApplyEnabled()
                        end,
                    },

                    -- Greyed hint: the colour is speed-driven, not user-picked.
                    {
                        type = "label",
                        text = L["|cffaaaaaaText colour changes with speed.|r"],
                    },

                    -- Font / size / outline (colour omitted — it follows the speed tier).
                    {
                        type        = "textEditor",
                        LSM         = LSM,
                        label       = L["Speed text appearance"],
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

                    -- Position editor (named ref for the drag self-refresh, like Death Anim).
                    {
                        type       = "position",
                        ref        = "speedPE",
                        onBuilt    = function(w) ns.SpeedDisplay.pe = w end,
                        label      = L["Speed display position (offset from screen center)"],
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
                }
            end,
        },

        -- ── Combo sounds section ─────────────────────────────────────────────
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

                    -- BL combo sound picker
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

                    -- Potion combo sound picker
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

        -- ── Death-alert anti-spam section ────────────────────────────────────
        {
            type  = "group",
            title = L["Death alert anti-spam"],
            build = function()
                return {
                    -- Wipe detection (checkbox + greyed description on the line below).
                    -- Kept as custom to preserve the description FontString anchored to the
                    -- host at (26, -20), which the plain "checkbox" type cannot reproduce.
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

                    -- DPS spam guard (checkbox + greyed description on the line below).
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

        -- ── Boss reset sound section ─────────────────────────────────────────
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

        -- ── Below player frame CDM row ───────────────────────────────────────
        -- Account-wide size of the icons placed in the artificial row below the
        -- PlayerFrame (any tracker with cdmDest = "belowPlayer"). Changing it
        -- re-applies the whole CDM layout so every below-player icon resizes.
        {
            type  = "group",
            title = L["Below player frame CDM row"],
            build = function()
                return {
                    {
                        type   = "custom",
                        height = 46,
                        build  = function(host)
                            local function Row() return ns.db.global.cdmBelowRow end

                            local sizeLbl = host:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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

                            local offLbl = host:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                            offLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            offLbl:SetText(L["Offset"])

                            local xLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                            xLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                            xLbl:SetText("X")

                            local xInput = ns.ui.CreateTextInput({
                                parent = host, width = 56, height = 22,
                                numeric = true, min = -2000, max = 2000, maxLetters = 5,
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
                                numeric = true, min = -2000, max = 2000, maxLetters = 5,
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
                                -- Bail if this build was torn down (host orphaned by a
                                -- Rebuild / profile switch) so a stale ns.OnBelowRowMoved
                                -- closure never writes to dead widgets.
                                if not host:GetParent() then return end
                                xInput.SetText(tostring((Row() and Row().offsetX) or 0))
                                yInput.SetText(tostring((Row() and Row().offsetY) or 0))
                            end
                            -- Live-update the boxes while the user drags the row.
                            ns.OnBelowRowMoved = Refresh

                            return { frame = host, height = 46, Refresh = Refresh }
                        end,
                    },

                    -- Unlock to drag the row to a custom spot (e.g. a non-default
                    -- player frame addon); the drop position is saved as the offset.
                    -- Unlock/Lock toggle button, like the position editors.
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
                }
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initGS = CreateFrame("Frame")
initGS:RegisterEvent("ADDON_LOADED")
initGS:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["General Settings"], nil, CreateGeneralSettingsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
