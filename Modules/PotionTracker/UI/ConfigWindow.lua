-- Modules/PotionTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.PotionTracker = ns.PotionTracker or {}
local PT = ns.PotionTracker

-- Builds the per-category (health / combat) inner option list consumed by a
-- BuildMenu "section". Returns the ordered options array. Inner widgets render
-- at width 500 / gap 10 / origin (8,-8) — exactly like the old CreatePotionSection
-- AddWidget loop — and a trailing 16px spacer reproduces the old `height + 16`.
local function BuildPotionSectionOptions(prefix, LSM)
    local function GetCfg(key)
        local cfg = PT.CfgGet(prefix)
        return cfg and cfg[key]
    end

    local function SetCfg(key, val)
        local cfg = PT.CfgGet(prefix)
        if cfg then
            cfg[key] = val
            PT.CfgSet(prefix, cfg)
        end
    end

    local tracker = prefix == "health" and PT.GetHealthTracker() or PT.GetCombatTracker()

    local options = {
        -- ── Potion picker + favorite picker + favorite checkbox (composite) ────
        -- Two side-by-side dropdowns plus the "use favorite" checkbox live in a
        -- single 74px host. ns.ui.CreateDropdown needs explicit anchor frames and
        -- the selectedText label is driven by hand, so this stays a custom block.
        {
            type   = "custom",
            height = 74,
            build  = function(potionFrame)
                potionFrame:SetHeight(74)

                local potionLbl = potionFrame:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                potionLbl:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 0, 0)
                potionLbl:SetText(L["Potion"])

                local potionAnchor = potionFrame:CreateFontString(nil, "ARTWORK")
                potionAnchor:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 0, -20)

                -- Build "|T<icon>:16|t Name" so each dropdown row shows its potion
                -- icon next to the name. The same markup is used as the unique
                -- identifier for both the displayed list and the current-selection
                -- comparison.
                local function FormatDisplay(itemID, name)
                    local icon = C_Item.GetItemIconByID(itemID)
                    if icon then
                        return string.format("|T%d:16|t %s", icon, name)
                    end
                    return name
                end

                -- Displays the potion actually being tracked right now (the
                -- resolver's pick, which falls back when the configured one is out
                -- of bags).
                local function ActivePotionDisplay()
                    local id = PT.GetActiveItemId(prefix)
                    if not id then return L["None"] end
                    local name = C_Item.GetItemNameByID(id) or tostring(id)
                    return FormatDisplay(id, name)
                end

                -- displayString -> itemID, rebuilt on every getList() so onSelect
                -- can recover the item ID without re-scanning.
                local displayToId = {}

                local potionDD
                potionDD = ns.ui.CreateDropdown({
                    parent        = potionFrame,
                    anchorFrame   = potionAnchor,
                    width         = 240,
                    itemHeight    = 20,
                    itemGap       = 5,
                    visibleItems  = 8,
                    searchable    = true,
                    getList = function()
                        -- Only show what is actually in the bags for this category;
                        -- no phantom entry for a configured potion that has run out.
                        displayToId = {}
                        local list = {}
                        for _, p in ipairs(PT.GetBagPotions(prefix)) do
                            local display = FormatDisplay(p.id, p.name)
                            table.insert(list, display)
                            displayToId[display] = p.id
                        end
                        return list
                    end,
                    getCurrentKey = ActivePotionDisplay,
                    onSelect = function(display)
                        local id = displayToId[display]
                        if not id then return end
                        SetCfg("itemId", id)
                        -- spellId is derived dynamically by PT.GetActiveSpellId from
                        -- the active item; the resolver never reads a stored
                        -- cfg.spellId, so do not persist one here (it would only ever
                        -- be stale/nil dead data).
                        potionDD.selectedText:SetText(display)
                        PT.ApplyAll()
                    end,
                })
                potionDD.selectedText:SetText(ActivePotionDisplay())

                -- ── Favorite potion picker (curated list) ─────────────────────

                local favLbl = potionFrame:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                favLbl:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 260, 0)
                favLbl:SetText(L["Favorite potion"])

                local favAnchor = potionFrame:CreateFontString(nil, "ARTWORK")
                favAnchor:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 260, -20)

                local function FavoriteDisplay()
                    local id = GetCfg("favoriteId")
                    if not id then return L["None"] end
                    local name = C_Item.GetItemNameByID(id) or ("[" .. id .. "]")
                    return FormatDisplay(id, name)
                end

                local favDisplayToId = {}

                local favoriteDD
                favoriteDD = ns.ui.CreateDropdown({
                    parent        = potionFrame,
                    anchorFrame   = favAnchor,
                    width         = 200,
                    itemHeight    = 20,
                    itemGap       = 5,
                    visibleItems  = 8,
                    searchable    = true,
                    getList = function()
                        favDisplayToId = {}
                        local list = {}
                        for _, p in ipairs(PT.GetFavoritePotions(prefix)) do
                            local display = FormatDisplay(p.id, p.name)
                            table.insert(list, display)
                            favDisplayToId[display] = p.id
                        end
                        return list
                    end,
                    getCurrentKey = FavoriteDisplay,
                    onSelect = function(display)
                        local id = favDisplayToId[display]
                        if not id then return end
                        SetCfg("favoriteId", id)
                        favoriteDD.selectedText:SetText(display)
                        PT.ApplyAll()
                    end,
                })
                favoriteDD.selectedText:SetText(FavoriteDisplay())

                -- Favorite enable checkbox, sitting below the dropdown.
                local favCb = ns.ui.CreateCheckbox({
                    parent  = potionFrame,
                    label   = L["Use favorite when in bag"],
                    checked = GetCfg("favoriteEnabled") == true,
                    onClick = function(val)
                        SetCfg("favoriteEnabled", val)
                        PT.ApplyAll()
                    end,
                })
                favCb.frame:SetPoint("TOPLEFT", potionFrame, "TOPLEFT", 260, -46)

                return {
                    frame   = potionFrame,
                    height  = 74,
                    Refresh = function()
                        potionDD.selectedText:SetText(ActivePotionDisplay())
                        favoriteDD.selectedText:SetText(FavoriteDisplay())
                        favCb.SetChecked(GetCfg("favoriteEnabled") == true)
                    end,
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            build = function()
                return {
                    -- ── Sound use ──────────────────────────────────────────────────────────
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
                        onTest    = function() PT.PlaySound(prefix, "soundUse") end,
                    },

                    -- ── Sound ready ────────────────────────────────────────────────────────
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
                        onTest    = function() PT.PlaySound(prefix, "soundReady") end,
                    },
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text / stack) since there is no icon to configure; the checkbox stays live.
            gate  = { enabled = function() return GetCfg("showIcon") ~= false end, master = "showicon" },
            build = function()
                local frameName = (prefix == "health") and "PotionTrackerHealth" or "PotionTrackerCombat"
                local function inCdm() return ns.CDMIncludedVal(GetCfg("includeInCdm")) end
                local function curDest() return GetCfg("cdmDest") or "belowPlayer" end
                local function rebuildMenu() if PT.configMenu then PT.configMenu.Rebuild() end end
                local function applyIcon()
                    PT.ApplyAll()
                    if tracker then tracker.ApplyFont(); tracker.ApplyBorder(); tracker.ApplySize() end
                    if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                end

                local e = {
                    { type = "checkbox", ref = "showicon", label = L["Show icon"], height = 24,
                      get = function() return GetCfg("showIcon") ~= false end,
                      set = function(val) SetCfg("showIcon", val); tracker.ApplyVisuals() end,
                      inline = { { type = "checkbox", label = L["Show at 0 stacks"],
                          get = function() return GetCfg("showAtZero") == true end,
                          set = function(val) SetCfg("showAtZero", val); tracker.ApplyVisuals(); PT.ApplyStackVisuals(prefix, tracker) end,
                          point = { "LEFT", "LEFT", 150, 0 } } } },

                    { type = "group", title = L["Placement"], build = function() return {
                        { type = "checkbox", label = L["Include in cdm"],
                          disabled = function() return not ns.IsCDMEnabled() end,
                          get = function() return inCdm() end,
                          set = function(v) SetCfg("includeInCdm", v); tracker.ApplySize(); tracker.ApplyPosition(); PT.ApplyStackVisuals(prefix, tracker); rebuildMenu() end },
                        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                          when = function() return inCdm() end,
                          getList = function() return ns.CDMDestList() end,
                          getCurrentKey = function() return ns.CDMDestChoiceLabel(GetCfg) end,
                          onSelect = function(label) ns.CDMApplyDestChoice(label, SetCfg); tracker.ApplySize(); tracker.ApplyPosition(); rebuildMenu() end },
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
                    seedValues = function() return PT.OverrideSeed(prefix) end,
                    freeBuild  = function()
                        return ns.CDMGroups.TrackerFreeCadres({
                            get       = GetCfg,
                            set       = SetCfg,
                            touch     = applyIcon,
                            rebuild   = rebuildMenu,
                            sizeApply = function() if tracker then tracker.ApplySize() end end,
                            LSM       = LSM,
                            pos = {
                                getX = function() return GetCfg("posX") end,
                                getY = function() return GetCfg("posY") end,
                                onApply = function(x, yv) if x then SetCfg("posX", x) end if yv then SetCfg("posY", yv) end PT.ApplyAll() end,
                                onUnlock = function() tracker.SetUnlocked(true) end,
                                onLock = function() tracker.SetUnlocked(false); if tracker.pe then tracker.pe.Refresh() end end,
                                isUnlocked = function() return tracker.IsUnlocked() end,
                                onBuilt = function(w) tracker.pe = w end,
                            },
                        })
                    end,
                }
                for _, x in ipairs(ns.CDMGroups.TrackerCdmCadres(cfg)) do e[#e + 1] = x end
                return e
            end,
        },

        -- ── Trailing padding ───────────────────────────────────────────────────
        -- Reproduces the old `height = height + 16` bottom padding (the empty
        -- spacer's gap + height = 10 + 16 = 26 also restores the trailing GAP the
        -- old AddWidget loop added after the last widget).
        {
            type   = "label",
            text   = "",
            height = 16,
        },
    }

    return options
end

local function CreatePotionTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Potion Tracker"] },

        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys the instance filter ("active in") while the
            -- enable checkbox stays live to re-enable.
            gate  = { enabled = function() return PT.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable Potion Tracker"],
                        height = 24,
                        get    = function() return PT.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            PT.CfgSet("enabled", val)
                            PT.ApplyAll()
                            if PT.configMenu then PT.configMenu.Refresh() end
                        end,
                    },

                    -- ── Instance filter ───────────────────────────────────────────────────
                    {
                        type      = "instanceFilter",
                        getConfig = function() return PT.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local filter = PT.CfgGet("instanceFilter")
                            filter[key] = val
                            PT.CfgSet("instanceFilter", filter)
                        end,
                    },
                }
            end,
        },

        -- ── Health potion section ─────────────────────────────────────────────
        {
            type      = "section",
            label     = L["Health Potion"],
            enabledBy = function() return PT.CfgGet("enabled") ~= false end,
            LSM       = LSM,
            isChecked = function() return PT.CfgGet("health") and PT.CfgGet("health").enabled end,
            onCheck   = function(val)
                local cfg = PT.CfgGet("health")
                cfg.enabled = val
                PT.CfgSet("health", cfg)
                PT.ApplyAll()
            end,
            getCollapsed = function() return PT._uiCollapsed and PT._uiCollapsed["health"] end,
            onCollapse   = function(v) PT._uiCollapsed = PT._uiCollapsed or {}; PT._uiCollapsed["health"] = v end,
            build     = function() return BuildPotionSectionOptions("health", LSM) end,
        },

        -- ── Combat potion section ─────────────────────────────────────────────
        {
            type      = "section",
            label     = L["Combat Potion"],
            enabledBy = function() return PT.CfgGet("enabled") ~= false end,
            LSM       = LSM,
            isChecked = function() return PT.CfgGet("combat") and PT.CfgGet("combat").enabled end,
            onCheck   = function(val)
                local cfg = PT.CfgGet("combat")
                cfg.enabled = val
                PT.CfgSet("combat", cfg)
                PT.ApplyAll()
            end,
            getCollapsed = function() return PT._uiCollapsed and PT._uiCollapsed["combat"] end,
            onCollapse   = function(v) PT._uiCollapsed = PT._uiCollapsed or {}; PT._uiCollapsed["combat"] = v end,
            build     = function() return BuildPotionSectionOptions("combat", LSM) end,
        },
    }

    -- Outer panel: gap=8, width=518. Inner sections render at width 500 / gap 10 /
    -- origin (8,-8), matching the old CreatePotionSection AddWidget loop. autoHook
    -- generates the OnShow re-sync (enable, instance filter, both sections and all
    -- their inner widgets).
    PT.configMenu = ns.ui.BuildMenu(parent, options, {
        gap        = 8,
        width      = 518,
        LSM        = LSM,
        innerWidth = 500,
        innerGap   = 10,
    })

    -- Each potion's Override / Free sections start collapsed and re-collapse on tab show.
    parent:HookScript("OnHide", function()
        for _, p in ipairs({ "health", "combat" }) do
            local c = PT.CfgGet(p)
            if c then c.ovCollapsed = true; c.freeCollapsed = true; PT.CfgSet(p, c) end
        end
    end)
    parent:HookScript("OnShow", function() if PT.configMenu then PT.configMenu.Rebuild() end end)
    return PT.configMenu
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initPTUI = CreateFrame("Frame")
initPTUI:RegisterEvent("ADDON_LOADED")
initPTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Potion Tracker"], nil, CreatePotionTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
