-- Modules/RacialTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.RacialTracker = ns.RacialTracker or {}
local RT = ns.RacialTracker

local function CreateRacialTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.Rebuild / menu.refs.pe

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Racial Tracker"] },

        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (instance filter, tracked
            -- racial display, etc.) except the enable checkbox itself, which stays live.
            gate  = { enabled = function() return RT.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable Racial Tracker"],
                        get    = function() return RT.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            RT.CfgSet("enabled", val)
                            RT.ApplyAll()
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- ── Test button (toggles Test / Stop Test) ────────────────────────────
                    {
                        type   = "custom",
                        height = 30,
                        build  = function(host)
                            local testBtn
                            local function RefreshTestBtn()
                                testBtn.SetText(RT.IsTesting() and L["Stop Test"] or L["Test"])
                            end
                            testBtn = ns.ui.CreateButton({
                                parent  = host,
                                label   = L["Test"],
                                width   = 100,
                                height  = 22,
                                onClick = function()
                                    if RT.IsTesting() then RT.StopTest() else RT.RunTest() end
                                    RefreshTestBtn()
                                end,
                            })
                            testBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -4)
                            return { frame = host, height = 30, Refresh = RefreshTestBtn }
                        end,
                    },

                    -- ── Instance filter ───────────────────────────────────────────────────
                    {
                        type      = "instanceFilter",
                        getConfig = function() return RT.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local filter = RT.CfgGet("instanceFilter")
                            filter[key] = val
                            RT.CfgSet("instanceFilter", filter)
                        end,
                    },

                    -- ── Tracked racial: header + detected name/icon, optional manual override ──
                    {
                        type   = "custom",
                        height = 126,
                        build  = function(host)
                            -- "Tracked racial :" header (H4)
                            local hdr = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                            hdr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            hdr:SetText(L["Tracked racial :"])

                            -- Detected racial name (H5) + its icon to the right…
                            local nameFs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH5")
                            nameFs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -22)
                            local raceIcon = host:CreateTexture(nil, "OVERLAY")
                            raceIcon:SetSize(18, 18)
                            raceIcon:SetPoint("LEFT", nameFs, "RIGHT", 6, 0)
                            raceIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                            raceIcon:Hide()
                            -- …or a red "No racial detected" (H6) when nothing is tracked.
                            local noneFs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                            noneFs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -22)
                            noneFs:SetText(L["No racial detected"])
                            noneFs:SetTextColor(1, 0.27, 0.27)
                            noneFs:Hide()

                            -- Manual detection checkbox (off by default).
                            local manualCb = ns.ui.CreateCheckbox({
                                parent  = host,
                                label   = L["Manual racial detection"],
                                checked = RT.CfgGet("manualEnabled") == true,
                                onClick = function(val)
                                    RT.CfgSet("manualEnabled", val)
                                    RT.ResolveAndApply()
                                    if menu then menu.Refresh() end
                                end,
                            })
                            manualCb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -48)

                            -- Spell ID label + input (below the checkbox); only used when
                            -- manual detection is on, so it's dimmed/inert otherwise.
                            local ovLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            ovLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -78)
                            ovLbl:SetText(L["Spell ID"])
                            local ovInput = ns.ui.CreateTextInput({
                                parent = host, width = 80, height = 22,
                                numeric = true, min = 0, max = 9999999, maxLetters = 7,
                                text = tostring(RT.CfgGet("spellOverride") or 0),
                                onEnter = function(val)
                                    RT.CfgSet("spellOverride", val or 0)
                                    RT.ResolveAndApply()
                                    if menu then menu.Refresh() end
                                end,
                            })
                            ovInput.frame:SetPoint("TOPLEFT", ovLbl, "BOTTOMLEFT", 0, -4)

                            local function refresh()
                                -- Detected/tracked racial name + icon, or the red fallback.
                                local id = RT.GetSpellId()
                                if id then
                                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                                    nameFs:SetText((info and info.name) or tostring(id))
                                    nameFs:Show()
                                    local ic = info and info.iconID
                                    if ic then raceIcon:SetTexture(ic); raceIcon:Show() else raceIcon:Hide() end
                                    noneFs:Hide()
                                else
                                    nameFs:Hide()
                                    raceIcon:Hide()
                                    noneFs:Show()
                                end
                                -- Manual override controls.
                                manualCb.SetChecked(RT.CfgGet("manualEnabled") == true)
                                ovInput.SetText(tostring(RT.CfgGet("spellOverride") or 0))
                                local on = RT.CfgGet("manualEnabled") == true
                                ovLbl:SetAlpha(on and 1 or 0.4)
                                ovInput.frame:SetAlpha(on and 1 or 0.4)
                                if ovInput.editBox then ovInput.editBox:EnableMouse(on) end
                            end
                            refresh()

                            return { frame = host, height = 126, Refresh = refresh }
                        end,
                    },
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            enabledBy = function() return RT.CfgGet("enabled") ~= false end,
            build = function()
                return {
                    -- ── Sound on use ──────────────────────────────────────────────────────
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound on use"],
                        getKey    = function() return RT.CfgGet("soundKeyUse") end,
                        getEnable = function() return RT.CfgGet("soundOnUse") end,
                        onSelect  = function(key, path)
                            RT.CfgSet("soundKeyUse", key)
                            RT.CfgSet("soundPathUse", path)
                        end,
                        onToggle  = function(val) RT.CfgSet("soundOnUse", val) end,
                        onTest    = function() RT.PlaySound("soundUse") end,
                    },

                    -- ── Sound when ready ──────────────────────────────────────────────────
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound when ready"],
                        getKey    = function() return RT.CfgGet("soundKeyReady") end,
                        getEnable = function() return RT.CfgGet("soundOnReady") end,
                        onSelect  = function(key, path)
                            RT.CfgSet("soundKeyReady", key)
                            RT.CfgSet("soundPathReady", path)
                        end,
                        onToggle  = function(val) RT.CfgSet("soundOnReady", val) end,
                        onTest    = function() RT.PlaySound("soundReady") end,
                    },
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            enabledBy = function() return RT.CfgGet("enabled") ~= false end,
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text) since there is no icon to configure; the checkbox stays live.
            gate      = { enabled = function() return RT.CfgGet("showIcon") ~= false end, master = "showicon" },
            build = function()
                local frameName = "RacialTrackerFrame"
                local function inCdm() return ns.CDMIncludedVal(RT.CfgGet("includeInCdm")) end
                local function curDest() return RT.CfgGet("cdmDest") or "belowPlayer" end
                local function rebuildMenu() if menu then menu.Rebuild() end end
                local function applyIcon()
                    RT.ApplyAll(); RT.ApplyTimerVisuals(); RT.ApplyBorder(); RT.ApplySize()
                    if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                end

                local e = {
                    { type = "checkbox", ref = "showicon", label = L["Show icon"],
                      get = function() return RT.CfgGet("showIcon") ~= false end,
                      set = function(val) RT.CfgSet("showIcon", val); RT.ApplyAll() end },

                    { type = "group", title = L["Placement"], build = function() return {
                        { type = "checkbox", label = L["Include in cdm"],
                          disabled = function() return not ns.IsCDMEnabled() end,
                          get = function() return inCdm() end,
                          set = function(v) RT.CfgSet("includeInCdm", v); RT.ApplySize(); RT.ApplyPosition(); RT.ApplyAll(); rebuildMenu() end },
                        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                          when = function() return inCdm() end,
                          getList = function() return ns.CDMDestList() end,
                          getCurrentKey = function() return ns.CDMDestChoiceLabel(RT.CfgGet) end,
                          onSelect = function(label) ns.CDMApplyDestChoice(label, RT.CfgSet); RT.ApplySize(); RT.ApplyPosition(); RT.ApplyAll(); rebuildMenu() end },
                    } end },
                }

                local cfg = {
                    frameName  = frameName,
                    getDest    = curDest,
                    cdmAtEnd   = function() return RT.CfgGet("cdmAtEnd") end,
                    inCdm      = inCdm,
                    applyIcon  = applyIcon,
                    rebuild    = rebuildMenu,
                    getOv      = function() return RT.CfgGet("ovCollapsed") ~= false end,
                    setOv      = function(c) RT.CfgSet("ovCollapsed", c) end,
                    getFree    = function() return RT.CfgGet("freeCollapsed") ~= false end,
                    setFree    = function(c) RT.CfgSet("freeCollapsed", c) end,
                    -- Default override-set: ONLY Timer (size 14 + urgency thresholds). Rest inherits the group.
                    seedValues = function() return {
                        timerFontSize = 14,
                        timerThresholdsEnabled = true,
                        timerThresholds = ns.DefaultTrackerTimerThresholds(),
                    } end,
                    freeBuild  = function() return {
                        { type = "position", ref = "pe",
                          onBuilt = function(w) RT.pe = w end,
                          label = L["Icon position (offset from screen center)"],
                          getX = function() return RT.CfgGet("posX") end,
                          getY = function() return RT.CfgGet("posY") end,
                          onApply = function(x, yv) if x then RT.CfgSet("posX", x) end if yv then RT.CfgSet("posY", yv) end RT.ApplyPosition(); RT.ApplyAll() end,
                          onUnlock = function() RT.SetUnlocked(true) end,
                          onLock = function() RT.SetUnlocked(false); if RT.pe then RT.pe.Refresh() end end,
                          isUnlocked = function() return RT.IsUnlocked() end },
                        { type = "custom", height = 46, build = function(host)
                            local sizeLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                            sizeLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sizeLbl:SetText(L["Icon size"])
                            local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20); wLbl:SetText(L["W"])
                            local wInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                                text = tostring(RT.CfgGet("iconWidth") or 30),
                                onEnter = function(val) if val and val > 0 then RT.CfgSet("iconWidth", val); RT.ApplySize(); RT.ApplyAll() end end })
                            wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                            local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                            local hInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                                text = tostring(RT.CfgGet("iconHeight") or 30),
                                onEnter = function(val) if val and val > 0 then RT.CfgSet("iconHeight", val); RT.ApplySize(); RT.ApplyAll() end end })
                            hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                            return { frame = host, height = 46, Refresh = function()
                                wInput.SetText(tostring(RT.CfgGet("iconWidth") or 30)); hInput.SetText(tostring(RT.CfgGet("iconHeight") or 30)) end }
                        end },
                        { type = "group", title = L["Border"], build = function() return {
                            { type = "checkbox", label = L["Show border"],
                              get = function() return RT.CfgGet("borderEnabled") == true end,
                              set = function(v) RT.CfgSet("borderEnabled", v); RT.ApplyBorder(); rebuildMenu() end },
                            { type = "textEditor", label = L["Border color"], enabledBy = function() return RT.CfgGet("borderEnabled") == true end,
                              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                              getColor = function() return RT.CfgGet("borderColor") end,
                              onColorChange = function(r, g, b, a) RT.CfgSet("borderColor", { r = r, g = g, b = b, a = a }); RT.ApplyBorder() end },
                            { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
                              enabledBy = function() return RT.CfgGet("borderEnabled") == true end,
                              get = function() return RT.CfgGet("borderSize") or 1 end,
                              set = function(v) if v and v > 0 then RT.CfgSet("borderSize", v); RT.ApplyBorder() end end },
                        } end },
                        { type = "group", title = L["Timer"], build = function() return {
                            { type = "textEditor", LSM = LSM, label = L["Timer"], showLabel = false,
                              showText = false, showFont = true, showSize = true, showColor = true, showOutline = true,
                              getFontKey = function() return RT.CfgGet("timerFontKey") end,
                              getFontPath = function() return RT.CfgGet("timerFontPath") end,
                              getFontSize = function() return RT.CfgGet("timerFontSize") end,
                              getColor = function() return RT.CfgGet("timerColor") end,
                              getOutline = function() return RT.CfgGet("timerOutline") end,
                              onFontChange = function(key, path) RT.CfgSet("timerFontKey", key); RT.CfgSet("timerFontPath", path); RT.ApplyTimerVisuals() end,
                              onSizeChange = function(size) RT.CfgSet("timerFontSize", size); RT.ApplyTimerVisuals() end,
                              onColorChange = function(r, g, b, a) RT.CfgSet("timerColor", { r = r, g = g, b = b, a = a }); RT.ApplyTimerVisuals() end,
                              onOutlineChange = function(outline) RT.CfgSet("timerOutline", outline); RT.ApplyTimerVisuals() end },
                            ns.ui.TiersEntry({ getTiers = function() return RT.CfgGet("timerTiers") end,
                              apply = function() RT.ApplyTimerVisuals() end, rebuild = rebuildMenu }),
                        } end },
                    } end,
                }
                for _, x in ipairs(ns.CDMGroups.TrackerCdmCadres(cfg)) do e[#e + 1] = x end
                return e
            end,
        },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })

    -- The Override / Free settings sections start collapsed and re-collapse on each tab show.
    parent:HookScript("OnHide", function()
        RT.CfgSet("ovCollapsed", true); RT.CfgSet("freeCollapsed", true)
    end)
    parent:HookScript("OnShow", function() if menu then menu.Rebuild() end end)
    return menu
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initRTUI = CreateFrame("Frame")
initRTUI:RegisterEvent("ADDON_LOADED")
initRTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Racial Tracker"], nil, CreateRacialTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
