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

                local potionLbl = potionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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
                    visibleItems  = 8,
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

                local favLbl = potionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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
                    visibleItems  = 8,
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

        -- ── Show icon checkbox ─────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Show icon"],
            height = 24,
            get    = function() return GetCfg("showIcon") ~= false end,
            set    = function(val)
                SetCfg("showIcon", val)
                tracker.ApplyVisuals()
            end,
        },

        -- ── Icon size  W / H  (composite -> custom escape hatch) ───────────────
        {
            type   = "custom",
            height = 46,
            build  = function(sizeFrame)
                sizeFrame:SetHeight(46)

                local sizeLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                sizeLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, 0)
                sizeLbl:SetText(L["Icon size"])

                local wLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                wLbl:SetPoint("TOPLEFT", sizeFrame, "TOPLEFT", 0, -20)
                wLbl:SetText(L["W"])

                local wInput = ns.ui.CreateTextInput({
                    parent     = sizeFrame,
                    width      = 46,
                    height     = 22,
                    numeric    = true,
                    min        = 8,
                    max        = 512,
                    maxLetters = 3,
                    text       = tostring(GetCfg("iconWidth") or 30),
                    onEnter    = function(val)
                        if val and val > 0 then
                            SetCfg("iconWidth", val)
                            tracker.ApplySize()
                        end
                    end,
                })
                wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

                local hLbl = sizeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
                hLbl:SetText(L["H"])

                local hInput = ns.ui.CreateTextInput({
                    parent     = sizeFrame,
                    width      = 46,
                    height     = 22,
                    numeric    = true,
                    min        = 8,
                    max        = 512,
                    maxLetters = 3,
                    text       = tostring(GetCfg("iconHeight") or 30),
                    onEnter    = function(val)
                        if val and val > 0 then
                            SetCfg("iconHeight", val)
                            tracker.ApplySize()
                        end
                    end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                return {
                    frame   = sizeFrame,
                    height  = 46,
                    Refresh = function()
                        wInput.SetText(tostring(GetCfg("iconWidth") or 30))
                        hInput.SetText(tostring(GetCfg("iconHeight") or 30))
                    end,
                }
            end,
        },

        -- ── Border (icon border) ───────────────────────────────────────────────
        {
            type = "checkbox", label = L["Show border"],
            get = function() return GetCfg("borderEnabled") == true end,
            set = function(v) SetCfg("borderEnabled", v); tracker.ApplyBorder() end,
        },
        {
            type = "textEditor", label = L["Border color"],
            showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
            getColor = function() return GetCfg("borderColor") end,
            onColorChange = function(r, g, b, a)
                SetCfg("borderColor", { r = r, g = g, b = b, a = a }); tracker.ApplyBorder()
            end,
        },
        {
            type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
            get = function() return GetCfg("borderSize") or 1 end,
            set = function(v) if v and v > 0 then SetCfg("borderSize", v); tracker.ApplyBorder() end end,
        },

        -- ── Position editor (named ref for the onLock self-refresh) ────────────
        {
            type       = "position",
            ref        = "pe",
            onBuilt    = function(w) tracker.pe = w end,
            label      = L["Icon position (offset from screen center)"],
            getX       = function() return GetCfg("posX") end,
            getY       = function() return GetCfg("posY") end,
            onApply    = function(x, yv)
                if x  then SetCfg("posX", x)  end
                if yv then SetCfg("posY", yv) end
                PT.ApplyAll()
            end,
            onUnlock   = function() tracker.SetUnlocked(true) end,
            onLock     = function()
                tracker.SetUnlocked(false)
                if tracker.pe then tracker.pe.Refresh() end
            end,
            isUnlocked = function() return tracker.IsUnlocked() end,
        },

        -- ── Timer text ─────────────────────────────────────────────────────────
        {
            type            = "textEditor",
            LSM             = LSM,
            label           = L["Timer text"],
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
                tracker.ApplyFont()
            end,
            onSizeChange    = function(size)
                SetCfg("timerFontSize", size)
                tracker.ApplyFont()
            end,
            onColorChange   = function(r, g, b, a)
                SetCfg("timerColor", { r = r, g = g, b = b, a = a })
                tracker.ApplyFont()
            end,
            onOutlineChange = function(outline)
                SetCfg("timerOutline", outline)
                tracker.ApplyFont()
            end,
        },

        -- ── Show stack count checkbox ──────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Show stack count below icon"],
            height = 24,
            get    = function() return GetCfg("showStack") ~= false end,
            set    = function(val)
                SetCfg("showStack", val)
                PT.ApplyStackVisuals(prefix, tracker)
            end,
        },

        -- ── Stack text ─────────────────────────────────────────────────────────
        {
            type            = "textEditor",
            LSM             = LSM,
            label           = L["Stack text"],
            showText        = false,
            showFont        = true,
            showSize        = true,
            showColor       = true,
            showOutline     = true,
            getFontKey      = function() return GetCfg("stackFontKey") end,
            getFontPath     = function() return GetCfg("stackFontPath") end,
            getFontSize     = function() return GetCfg("stackFontSize") end,
            getColor        = function() return GetCfg("stackColor") end,
            getOutline      = function() return GetCfg("stackOutline") end,
            onFontChange    = function(key, path)
                SetCfg("stackFontKey", key)
                SetCfg("stackFontPath", path)
                PT.ApplyStackVisuals(prefix, tracker)
            end,
            onSizeChange    = function(size)
                SetCfg("stackFontSize", size)
                PT.ApplyStackVisuals(prefix, tracker)
            end,
            onColorChange   = function(r, g, b, a)
                SetCfg("stackColor", { r = r, g = g, b = b, a = a })
                PT.ApplyStackVisuals(prefix, tracker)
            end,
            onOutlineChange = function(outline)
                SetCfg("stackOutline", outline)
                PT.ApplyStackVisuals(prefix, tracker)
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
        -- ── Enable checkbox ───────────────────────────────────────────────────
        {
            type   = "checkbox",
            label  = L["Enable Potion Tracker"],
            height = 24,
            get    = function() return PT.CfgGet("enabled") ~= false end,
            set    = function(val)
                PT.CfgSet("enabled", val)
                PT.ApplyAll()
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

        -- ── Health potion section ─────────────────────────────────────────────
        {
            type      = "section",
            label     = L["Health Potion"],
            LSM       = LSM,
            isChecked = function() return PT.CfgGet("health") and PT.CfgGet("health").enabled end,
            onCheck   = function(val)
                local cfg = PT.CfgGet("health")
                cfg.enabled = val
                PT.CfgSet("health", cfg)
                PT.ApplyAll()
            end,
            build     = function() return BuildPotionSectionOptions("health", LSM) end,
        },

        -- ── Combat potion section ─────────────────────────────────────────────
        {
            type      = "section",
            label     = L["Combat Potion"],
            LSM       = LSM,
            isChecked = function() return PT.CfgGet("combat") and PT.CfgGet("combat").enabled end,
            onCheck   = function(val)
                local cfg = PT.CfgGet("combat")
                cfg.enabled = val
                PT.CfgSet("combat", cfg)
                PT.ApplyAll()
            end,
            build     = function() return BuildPotionSectionOptions("combat", LSM) end,
        },
    }

    -- Outer panel: gap=8, width=518. Inner sections render at width 500 / gap 10 /
    -- origin (8,-8), matching the old CreatePotionSection AddWidget loop. autoHook
    -- generates the OnShow re-sync (enable, instance filter, both sections and all
    -- their inner widgets).
    return ns.ui.BuildMenu(parent, options, {
        gap        = 8,
        width      = 518,
        LSM        = LSM,
        innerWidth = 500,
        innerGap   = 10,
    })
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initPTUI = CreateFrame("Frame")
initPTUI:RegisterEvent("ADDON_LOADED")
initPTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Potion Tracker"], nil, CreatePotionTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
