-- Modules/RacialTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.RacialTracker = ns.RacialTracker or {}
local RT = ns.RacialTracker

local function CreateRacialTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.Rebuild / menu.refs.pe
    local function rebuildMenu() if menu then menu.Rebuild() end end
    local function applyIcon()
        if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- in-CDM size override -> force the engine to re-pack (its layout sig folds the epoch)
        RT.ApplyAll(); RT.ApplyTimerVisuals(); RT.ApplyBorder(); RT.ApplySize()
        if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
    end

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
                            -- SetEnabled drives the live transition: starts/stops the
                            -- 0.5s ticker and re-resolves + repaints (no /reload needed).
                            RT.SetEnabled(val)
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
        -- Default override-set (seedValues): ONLY Timer (size 14 + urgency thresholds); the rest inherits the group.
        ns.CDMGroups.TrackerIconGroup({
            get = RT.CfgGet, set = RT.CfgSet,
            frameName = "RacialTrackerFrame", defaultDest = "belowPlayer", LSM = LSM,
            enabledBy = function() return RT.CfgGet("enabled") ~= false end,
            rebuild = rebuildMenu, applyIcon = applyIcon,
            onShowIcon = function() RT.ApplyAll() end,
            afterInclude = function() RT.ApplySize(); RT.ApplyPosition(); RT.ApplyAll(); rebuildMenu() end,
            sizeApply = function() RT.ApplySize() end,
            seedValues = function() return ns.DefaultTrackerTimerSeed() end,
            pos = {
                getX = function() return RT.CfgGet("posX") end,
                getY = function() return RT.CfgGet("posY") end,
                onApply = function(x, yv) if x then RT.CfgSet("posX", x) end if yv then RT.CfgSet("posY", yv) end RT.ApplyPosition(); RT.ApplyAll() end,
                onUnlock = function() RT.SetUnlocked(true) end,
                onLock = function() RT.SetUnlocked(false); if RT.pe then RT.pe.Refresh() end end,
                isUnlocked = function() return RT.IsUnlocked() end,
                onBuilt = function(w) RT.pe = w end,
            },
        }),
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

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Racial Tracker"], nil, CreateRacialTrackerPanel)
end)
