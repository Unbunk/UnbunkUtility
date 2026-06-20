-- Modules/BLTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

-- A section headerExtra that puts a small grey note right after the section title AND keeps the gear
-- glyph on the far right (e.g. "Override settings  (When in CDM)").
local function HeaderHint(text)
    return function(headerBtn, headerLabel)
        local fs = headerBtn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
        fs:SetPoint("LEFT", headerLabel, "RIGHT", 6, 0)
        fs:SetText(text)
        fs:SetTextColor(0.6, 0.6, 0.6)
        if ns.ui.SettingsHeaderIcon then ns.ui.SettingsHeaderIcon(headerBtn) end
    end
end

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
                local frameName = "BLTrackerFrame"
                local function inCdm() return ns.CDMIncludedVal(BL.CfgGet("includeInCdm")) end
                local function curDest() return BL.CfgGet("cdmDest") or "essential" end
                local function rebuildMenu() if menu then menu.Rebuild() end end
                -- Re-apply the icon after an Override change. The Apply* re-read config through TimerIcon,
                -- which (for a migrated in-CDM icon) now reads the per-icon override; a forced CDM refresh
                -- re-lays the group out.
                local function applyIcon()
                    BL.ApplyVisuals(); BL.ApplyFont(); BL.ApplyBorder(); BL.ApplySize()
                    if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                end

                local e = {
                    -- ── Show icon (+ Always-show inline) ──────────────────────────────────
                    { type = "checkbox", ref = "showicon", label = L["Show icon"], height = 24,
                      get = function() return BL.CfgGet("showIcon") ~= false end,
                      set = function(val) BL.CfgSet("showIcon", val); BL.ApplyVisuals() end,
                      inline = { { type = "checkbox", label = L["Always show"],
                          get = function() return BL.CfgGet("alwaysShow") ~= false end,
                          set = function(val) BL.CfgSet("alwaysShow", val); BL.ApplyVisuals() end,
                          point = { "LEFT", "LEFT", 150, 0 } } } },

                    -- ── Placement mode: in the Cooldown Manager (which dest) or free ───────
                    { type = "group", title = L["Placement"], build = function() return {
                        { type = "checkbox", label = L["Include in cdm"],
                          disabled = function() return not ns.IsCDMEnabled() end,
                          get = function() return inCdm() end,
                          set = function(v) BL.CfgSet("includeInCdm", v); BL.ApplySize(); BL.ApplyPosition(); rebuildMenu() end },
                        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                          when = function() return inCdm() end,
                          getList = function() return ns.CDMDestList() end,
                          getCurrentKey = function() return ns.CDMDestChoiceLabel(BL.CfgGet) end,
                          onSelect = function(label) ns.CDMApplyDestChoice(label, BL.CfgSet); BL.ApplySize(); BL.ApplyPosition(); rebuildMenu() end },
                    } end },

                    -- Free-mode hint: when NOT in the CDM the look is set in "Free icon settings" (the
                    -- Override cadre is greyed). Hidden while in the CDM.
                    { type = "label", font = "UnbunkUtilityH6", height = 18, color = { 0.6, 0.6, 0.6 },
                      when = function() return not inCdm() end,
                      text = L["Check Free icon settings to setup icon"] },
                }

                -- ── Override settings: the per-icon look that governs the icon WHILE IN the CDM (greyed
                -- when free). Backed by the icon's per-icon override in its essential/utility group (shared
                -- IconSections, minus the trackers' own Sound cadre). One-time seeded from the Free look so
                -- it starts identical, then is governed here.
                local ovBundle, ovCtx
                local inst = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[curDest()]
                if inst and inst.SeedIconOverride and ns.CDMGroups.MakeTrackerOverride then
                    -- Default override-set: ONLY Timer (size 14 + urgency thresholds). Rest inherits the group.
                    inst.SeedIconOverride(frameName, {
                        timerFontSize = 14,
                        timerThresholdsEnabled = true,
                        timerThresholds = ns.DefaultTrackerTimerThresholds(),
                    })
                    ovBundle, ovCtx = ns.CDMGroups.MakeTrackerOverride(curDest(), frameName, applyIcon, rebuildMenu)
                end
                e[#e + 1] = {
                    type = "section", label = L["Override settings"], showCheckbox = false,
                    headerExtra = HeaderHint(L["(When in CDM)"]),
                    gate = { enabled = function() return inCdm() end },
                    getCollapsed = function() return BL.CfgGet("ovCollapsed") ~= false end,
                    -- Re-stack the whole menu after a collapse so the enclosing "Icon" group box grows /
                    -- shrinks to fit (a nested section's height change doesn't reflow its parent on its own).
                    onCollapse   = function(c)
                        BL.CfgSet("ovCollapsed", c and true or false)
                        if C_Timer and C_Timer.After then C_Timer.After(0, rebuildMenu) else rebuildMenu() end
                    end,
                    build = function()
                        if ovBundle then
                            return ns.CDMGroups.IconSections(nil, frameName, ovBundle, ovCtx,
                                { omit = { sound = true, placeholder = true, label = true } })
                        end
                        return { { type = "label", font = "UnbunkUtilityBody", height = 36,
                            text = L["These apply when the icon is in the Essential or Utility Cooldown Manager group."] } }
                    end,
                }

                -- ── Free icon settings: the look while NOT in the CDM (greyed when in the CDM) ─────────
                e[#e + 1] = {
                    type = "section", label = L["Free icon settings"], showCheckbox = false,
                    headerExtra = HeaderHint(L["(When not in CDM)"]),
                    gate = { enabled = function() return not inCdm() end },
                    getCollapsed = function() return BL.CfgGet("freeCollapsed") ~= false end,
                    onCollapse   = function(c)
                        BL.CfgSet("freeCollapsed", c and true or false)
                        if C_Timer and C_Timer.After then C_Timer.After(0, rebuildMenu) else rebuildMenu() end
                    end,
                    build = function() return {
                        { type = "position", ref = "pe",
                          onBuilt = function(w) BL.pe = w end,
                          label = L["Icon position (offset from screen center)"],
                          getX = function() return BL.CfgGet("posX") end,
                          getY = function() return BL.CfgGet("posY") end,
                          onApply = function(x, yv) if x then BL.CfgSet("posX", x) end if yv then BL.CfgSet("posY", yv) end BL.ApplyPosition() end,
                          onUnlock = function() BL.SetUnlocked(true) end,
                          onLock = function() BL.SetUnlocked(false); if BL.pe then BL.pe.Refresh() end end,
                          isUnlocked = function() return BL.IsUnlocked() end },
                        { type = "custom", height = 46, build = function(host)
                            local sizeLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                            sizeLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sizeLbl:SetText(L["Icon size"])
                            local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20); wLbl:SetText(L["W"])
                            local wInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                                text = tostring(BL.CfgGet("iconWidth") or 40),
                                onEnter = function(val) if val and val > 0 then BL.CfgSet("iconWidth", val); BL.ApplySize() end end })
                            wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                            local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                            local hInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                                text = tostring(BL.CfgGet("iconHeight") or 40),
                                onEnter = function(val) if val and val > 0 then BL.CfgSet("iconHeight", val); BL.ApplySize() end end })
                            hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                            return { frame = host, height = 46, Refresh = function()
                                wInput.SetText(tostring(BL.CfgGet("iconWidth") or 40)); hInput.SetText(tostring(BL.CfgGet("iconHeight") or 40)) end }
                        end },
                        { type = "group", title = L["Border"], build = function() return {
                            { type = "checkbox", label = L["Show border"],
                              get = function() return BL.CfgGet("borderEnabled") == true end,
                              set = function(v) BL.CfgSet("borderEnabled", v); BL.ApplyBorder(); rebuildMenu() end },
                            { type = "textEditor", label = L["Border color"], enabledBy = function() return BL.CfgGet("borderEnabled") == true end,
                              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                              getColor = function() return BL.CfgGet("borderColor") end,
                              onColorChange = function(r, g, b, a) BL.CfgSet("borderColor", { r = r, g = g, b = b, a = a }); BL.ApplyBorder() end },
                            { type = "textinput", label = L["Border thickness"], enabledBy = function() return BL.CfgGet("borderEnabled") == true end,
                              width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
                              get = function() return BL.CfgGet("borderSize") or 1 end,
                              set = function(v) if v and v > 0 then BL.CfgSet("borderSize", v); BL.ApplyBorder() end end },
                        } end },
                        { type = "group", title = L["Timer"], build = function() return {
                            { type = "textEditor", LSM = LSM, label = L["Timer"], showLabel = false,
                              showText = false, showFont = true, showSize = true, showColor = true, showOutline = true,
                              getFontKey = function() return BL.CfgGet("timerFontKey") end,
                              getFontPath = function() return BL.CfgGet("timerFontPath") end,
                              getFontSize = function() return BL.CfgGet("timerFontSize") end,
                              getColor = function() return BL.CfgGet("timerColor") end,
                              getOutline = function() return BL.CfgGet("timerOutline") end,
                              onFontChange = function(key, path) BL.CfgSet("timerFontKey", key); BL.CfgSet("timerFontPath", path); BL.ApplyFont() end,
                              onSizeChange = function(size) BL.CfgSet("timerFontSize", size); BL.ApplyFont() end,
                              onColorChange = function(r, g, b, a) BL.CfgSet("timerColor", { r = r, g = g, b = b, a = a }); BL.ApplyFont() end,
                              onOutlineChange = function(outline) BL.CfgSet("timerOutline", outline); BL.ApplyFont() end },
                            ns.ui.TiersEntry({ getTiers = function() return BL.CfgGet("timerTiers") end,
                              apply = function() BL.ApplyVisuals() end, rebuild = rebuildMenu }),
                        } end },
                    } end,
                }
                return e
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })

    -- The Override / Free settings sections start collapsed and re-collapse on each tab show (on hide,
    -- persist collapsed = true; on show, Rebuild re-reads getCollapsed). Same idiom as the below-player
    -- and CDMGroups group sections.
    parent:HookScript("OnHide", function()
        BL.CfgSet("ovCollapsed", true); BL.CfgSet("freeCollapsed", true)
    end)
    parent:HookScript("OnShow", function() if menu then menu.Rebuild() end end)
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
