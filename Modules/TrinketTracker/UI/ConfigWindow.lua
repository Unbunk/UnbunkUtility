-- Modules/TrinketTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.TrinketTracker = ns.TrinketTracker or {}
local TT = ns.TrinketTracker

-- Header extra for a trinket section: shows the equipped trinket's icon to the
-- right of the "(slot N)" label, then an H6 status — green "usable" if the trinket
-- has an on-use spell, red "passive" otherwise. With no trinket equipped in the
-- slot, a red "No trinket" replaces the icon. Returns an update() the section's
-- Refresh re-runs (so it re-reads the slot when the panel is shown / rebuilt).
local function MakeTrinketHeaderExtra(prefix)
    return function(headerBtn, headerLabel)
        local icon = headerBtn:CreateTexture(nil, "OVERLAY")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", headerLabel, "RIGHT", 8, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:Hide()

        local status = headerBtn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
        status:SetPoint("LEFT", icon, "RIGHT", 6, 0)

        local function update()
            local cfg    = TT.CfgGet(prefix)
            local slot   = cfg and cfg.slot
            local itemId = slot and GetInventoryItemID("player", slot)
            if not itemId then
                -- Nothing equipped in this slot: red "No trinket" where the icon would be.
                icon:Hide()
                status:ClearAllPoints()
                status:SetPoint("LEFT", headerLabel, "RIGHT", 8, 0)
                status:SetText(L["No trinket"])
                status:SetTextColor(1, 0.27, 0.27)
                return
            end
            local iconID = select(5, C_Item.GetItemInfoInstant(itemId))
            if iconID then icon:SetTexture(iconID) end
            icon:Show()
            status:ClearAllPoints()
            status:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            -- Usable = the item has an on-use spell (GetItemSpell returns its name);
            -- a passive/stat trinket returns nil. Mirrors the tracker's own detection.
            if C_Item.GetItemSpell(itemId) then
                status:SetText(L["active"])
                status:SetTextColor(0, 1, 0)
            else
                status:SetText(L["passive"])
                status:SetTextColor(1, 0.27, 0.27)
            end
        end

        update()
        return update
    end
end

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
                local frameName = (prefix == "trinket1") and "TrinketTracker1" or "TrinketTracker2"
                local function inCdm() return ns.CDMIncludedVal(GetCfg("includeInCdm")) end
                local function curDest() return GetCfg("cdmDest") or "essential" end
                local function rebuildMenu() if TT.configMenu then TT.configMenu.Rebuild() end end
                local function applyIcon()
                    TT.ApplyAll()
                    if tracker then tracker.ApplyFont(); tracker.ApplyBorder(); tracker.ApplySize() end
                    if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                end

                local e = {
                    { type = "checkbox", ref = "showicon", label = L["Show icon"], height = 24,
                      get = function() return GetCfg("showIcon") ~= false end,
                      set = function(val) SetCfg("showIcon", val); TT.ApplyAll() end },

                    { type = "group", title = L["Placement"], build = function() return {
                        { type = "checkbox", label = L["Include in cdm"],
                          disabled = function() return not ns.IsCDMEnabled() end,
                          get = function() return inCdm() end,
                          set = function(v) SetCfg("includeInCdm", v); if tracker then tracker.ApplySize(); tracker.ApplyPosition() end rebuildMenu() end },
                        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                          when = function() return inCdm() end,
                          getList = function() return ns.CDMDestList() end,
                          getCurrentKey = function() return ns.CDMDestChoiceLabel(GetCfg) end,
                          onSelect = function(label) ns.CDMApplyDestChoice(label, SetCfg); if tracker then tracker.ApplySize(); tracker.ApplyPosition() end rebuildMenu() end },
                    } end },
                }

                local cfg = {
                    frameName  = frameName,
                    getDest    = curDest,
                    cdmAtEnd   = function() return GetCfg("cdmAtEnd") end,
                    inCdm      = inCdm,
                    applyIcon  = applyIcon,
                    rebuild    = rebuildMenu,
                    getOv      = function() return GetCfg("ovCollapsed") ~= false end,
                    setOv      = function(c) SetCfg("ovCollapsed", c) end,
                    getFree    = function() return GetCfg("freeCollapsed") ~= false end,
                    setFree    = function(c) SetCfg("freeCollapsed", c) end,
                    seedValues = function()
                        local thr = {}
                        for _, t in ipairs(GetCfg("timerTiers") or {}) do thr[#thr + 1] = { time = t.at, size = t.scale, color = t.color } end
                        return {
                            showTimer = true,
                            timerFontKey = GetCfg("timerFontKey"), timerFontPath = GetCfg("timerFontPath"),
                            timerFontSize = GetCfg("timerFontSize"), timerOutline = GetCfg("timerOutline"),
                            timerColor = GetCfg("timerColor"), timerPos = "CENTER", timerOffX = 0, timerOffY = 0,
                            timerThresholdsEnabled = true, timerThresholds = thr,
                            borderEnabled = GetCfg("borderEnabled"), borderColor = GetCfg("borderColor"), borderSize = GetCfg("borderSize"),
                            iconW = GetCfg("iconWidth"), iconH = GetCfg("iconHeight"),
                            showTitle = false, showStack = false,
                        }
                    end,
                    freeBuild  = function() return {
                        { type = "position", ref = "pe",
                          onBuilt = function(w) if tracker then tracker.pe = w end end,
                          label = L["Icon position (offset from screen center)"],
                          getX = function() return GetCfg("posX") end,
                          getY = function() return GetCfg("posY") end,
                          onApply = function(x, yv) if x then SetCfg("posX", x) end if yv then SetCfg("posY", yv) end TT.ApplyAll() end,
                          onUnlock = function() if tracker then tracker.SetUnlocked(true) end end,
                          onLock = function() if tracker then tracker.SetUnlocked(false) end if tracker and tracker.pe then tracker.pe.Refresh() end end,
                          isUnlocked = function() return tracker and tracker.IsUnlocked() end },
                        { type = "custom", height = 46, build = function(host)
                            local sizeLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                            sizeLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sizeLbl:SetText(L["Icon size"])
                            local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20); wLbl:SetText(L["W"])
                            local wInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                                text = tostring(GetCfg("iconWidth") or 40),
                                onEnter = function(val) if val and val > 0 then SetCfg("iconWidth", val); if tracker then tracker.ApplySize() end end end })
                            wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                            local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                            local hInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                                text = tostring(GetCfg("iconHeight") or 40),
                                onEnter = function(val) if val and val > 0 then SetCfg("iconHeight", val); if tracker then tracker.ApplySize() end end end })
                            hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                            return { frame = host, height = 46, Refresh = function()
                                wInput.SetText(tostring(GetCfg("iconWidth") or 40)); hInput.SetText(tostring(GetCfg("iconHeight") or 40)) end }
                        end },
                        { type = "group", title = L["Border"], build = function() return {
                            { type = "checkbox", label = L["Show border"],
                              get = function() return GetCfg("borderEnabled") == true end,
                              set = function(v) SetCfg("borderEnabled", v); if tracker then tracker.ApplyBorder() end rebuildMenu() end },
                            { type = "textEditor", label = L["Border color"], enabledBy = function() return GetCfg("borderEnabled") == true end,
                              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                              getColor = function() return GetCfg("borderColor") end,
                              onColorChange = function(r, g, b, a) SetCfg("borderColor", { r = r, g = g, b = b, a = a }); if tracker then tracker.ApplyBorder() end end },
                            { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
                              enabledBy = function() return GetCfg("borderEnabled") == true end,
                              get = function() return GetCfg("borderSize") or 1 end,
                              set = function(v) if v and v > 0 then SetCfg("borderSize", v); if tracker then tracker.ApplyBorder() end end end },
                        } end },
                        { type = "group", title = L["Timer"], build = function() return {
                            { type = "textEditor", LSM = LSM, label = L["Timer"], showLabel = false,
                              showText = false, showFont = true, showSize = true, showColor = true, showOutline = true,
                              getFontKey = function() return GetCfg("timerFontKey") end,
                              getFontPath = function() return GetCfg("timerFontPath") end,
                              getFontSize = function() return GetCfg("timerFontSize") end,
                              getColor = function() return GetCfg("timerColor") end,
                              getOutline = function() return GetCfg("timerOutline") end,
                              onFontChange = function(key, path) SetCfg("timerFontKey", key); SetCfg("timerFontPath", path); if tracker then tracker.ApplyFont() end end,
                              onSizeChange = function(size) SetCfg("timerFontSize", size); if tracker then tracker.ApplyFont() end end,
                              onColorChange = function(r, g, b, a) SetCfg("timerColor", { r = r, g = g, b = b, a = a }); if tracker then tracker.ApplyFont() end end,
                              onOutlineChange = function(outline) SetCfg("timerOutline", outline); if tracker then tracker.ApplyFont() end end },
                            ns.ui.TiersEntry({ getTiers = function() return GetCfg("timerTiers") end,
                              apply = function() if tracker then tracker.ApplyVisuals() end end, rebuild = rebuildMenu }),
                        } end },
                    } end,
                }
                for _, x in ipairs(ns.CDMGroups.TrackerCdmCadres(cfg)) do e[#e + 1] = x end
                return e
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
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Trinket Tracker"] },

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
            headerExtra  = MakeTrinketHeaderExtra("trinket1"),
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
            headerExtra  = MakeTrinketHeaderExtra("trinket2"),
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

    -- Each trinket's Override / Free sections start collapsed and re-collapse on tab show.
    parent:HookScript("OnHide", function()
        for _, p in ipairs({ "trinket1", "trinket2" }) do
            local c = TT.CfgGet(p)
            if c then c.ovCollapsed = true; c.freeCollapsed = true; TT.CfgSet(p, c) end
        end
    end)
    parent:HookScript("OnShow", function() if TT.configMenu then TT.configMenu.Rebuild() end end)
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
