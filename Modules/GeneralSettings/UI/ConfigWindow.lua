-- Modules/GeneralSettings/UI/ConfigWindow.lua
-- Panels registered here (the nav tree in Core.lua places them into main tabs):
--   Addon settings        — minimap button + welcome message       (General Settings)
--   Player speed display  — on-screen speed readout                (Extra Utilities)
--   Multi-alert combo     — combo sounds                           (Extra Utilities)
--   Boss reset sound      — wipe/reset sound                       (Extra Utilities)
--   Death alert anti-spam — wipe + DPS-burst alert suppression     (Combat > Death Alerts)
--   Below player frame    — the below-player CDM row                (Cooldown Manager)
--   Free icons            — icons taken out of the CDM             (Cooldown Manager)
-- (The old "Essentials"/"Utility" bucket panels were retired — CDMGroups owns those now.)

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
                        -- The colour is speed-driven, not user-picked. H6 = small
                        -- descriptive text; the grey comes from the inline |cffaaaaaa..|r code.
                        { type = "label", font = "UnbunkUtilityH6", text = L["|cffaaaaaaText colour changes with speed.|r"] },
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

-- ── Multi-alert combo (Extra Utilities) ───────────────────────────────────────
local function CreateComboPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local options = {
        H2(L["Multi-alert combo"]),
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
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
end

-- ── Death alert anti-spam (Combat Utilities > Death Alerts) ────────────────────
local function CreateDeathAntiSpamPanel(parent)
    local options = {
        H2(L["Death alert anti-spam"]),
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
                            -- H6: small descriptive hint. The grey comes from the inline
                            -- |cffaaaaaa..|r code in the text, overriding H6's white default.
                            local desc = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
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
                            -- H6: small descriptive hint. The grey comes from the inline
                            -- |cffaaaaaa..|r code in the text, overriding H6's white default.
                            local desc = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
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
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

-- ── Boss reset sound (Extra Utilities) ─────────────────────────────────────────
local function CreateBossResetPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local options = {
        H2(L["Boss reset sound"]),
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

-- Brand-coloured "Drag" hint, centred just below a reorder cadre's bottom border, to
-- signal that the icons inside can be dragged to reorder them. Re-tints live with the
-- brand colour. The FontString is parented to the cadre it sits under, so it shows /
-- hides with it and renders in the gap below (the cadre never clips its children).
local function AddDragHint(cadre, inside)
    local fs = cadre:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
    if inside then
        fs:SetPoint("BOTTOM", cadre, "BOTTOM", 0, 3)    -- inside the cadre, just above the bottom border
    else
        fs:SetPoint("TOP", cadre, "BOTTOM", 0, -2)      -- centred just below the bottom border
    end
    fs:SetText(L["Drag"])
    fs:SetTextColor(ns.GetBrandColor())
    if ns.RegisterBrandRefresh then
        ns.RegisterBrandRefresh(fs, function() fs:SetTextColor(ns.GetBrandColor()) end)
    end
    return fs
end

-- Maps an addon icon's frame name to its config panel, so the pen on a non-custom icon
-- (in the reorder strips AND the Free icons tab) navigates to that tracker's own tab.
local FREE_PANEL_PREFIX = {
    { "RacialTracker",      "Racial Tracker"      },
    { "PotionTracker",      "Potion Tracker"      },
    { "HealthstoneTracker", "Healthstone Tracker" },
    { "TrinketTracker",     "Trinket Tracker"     },
    { "BLTracker",          "BL Tracker"          },
    { "PITracker",          "PI Tracker"          },
    { "UnbunkUtilityDefensive", "Defensive Tracker" },
}
local function FreePanelForFrame(name)
    if type(name) ~= "string" then return nil end
    for _, e in ipairs(FREE_PANEL_PREFIX) do
        if name:find("^" .. e[1]) then return L[e[2]] end
    end
    return nil
end
-- Shared so the CDMGroups (essential/utility) per-icon pencil can route an ADDON tracker to its own tab
-- (same as the below-player / Free-icons strips do), instead of opening the per-icon override editor. Returns
-- nil for a native cooldown (number key) or a non-tracker frame → caller falls back to its default action.
ns.PanelForTrackerFrame = FreePanelForFrame

-- The CDM row reorder strip entry (a Front/End cadre pair per row) used by the Below-player
-- panel; forward-declared here so CreateBelowPlayerPanel can reference it (defined further down).
local CDMRowReorderEntry

-- The "Border" cadre shown in the Below-player frame panel: ONE border (show / colour /
-- thickness) the CDM applies to EVERY icon in that dest. (A free icon — one taken out of the
-- CDM — keeps its own Border cadre instead.)
local function DestBorderEntry(dest)
    -- if/return (not `and`) so all three values come back, not just the first.
    local function db()
        if ns.CDMAnchor then return ns.CDMAnchor.GetDestBorder(dest) end
        return true, { r = 0, g = 0, b = 0, a = 1 }, 1
    end
    local function isOn() local e = db(); return e and true or false end
    return { type = "group", title = L["Border"], build = function() return {
        { type = "checkbox", label = L["Show border"],
          get = isOn,
          set = function(v) if ns.CDMAnchor then ns.CDMAnchor.SetDestBorder(dest, "borderEnabled", v and true or false) end end },
        { type = "textEditor", label = L["Border color"],
          enabledBy = isOn,
          showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
          getColor = function() local _, col = db(); return col end,
          onColorChange = function(r, g, b, a) if ns.CDMAnchor then ns.CDMAnchor.SetDestBorder(dest, "borderColor", { r = r, g = g, b = b, a = a }) end end },
        { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
          enabledBy = isOn,
          get = function() local _, _, sz = db(); return sz end,
          set = function(v) if v and v > 0 and ns.CDMAnchor then ns.CDMAnchor.SetDestBorder(dest, "borderSize", v) end end },
    } end }
end

-- Below-player glow-type dropdown (pixel/autocast/button — proc is N/A for trackers). Reuses the
-- (localized) glow labels from the CDMGroups glow cadre.
local BP_GLOWTYPES = { "pixel", "autocast", "button" }
local function BPGlowLabel(key)
    if key == "autocast" then return L["Autocast Glow"] end
    if key == "button"   then return L["Button Glow"]   end
    return L["Pixel Glow"]
end
local function BPGlowList()
    local t = {}
    for _, k in ipairs(BP_GLOWTYPES) do t[#t + 1] = BPGlowLabel(k) end
    return t
end
local function BPGlowFromLabel(label)
    for _, k in ipairs(BP_GLOWTYPES) do if BPGlowLabel(k) == label then return k end end
    return "pixel"
end

-- ── Below player frame (CDM row) ──────────────────────────────────────────────
local function CreateBelowPlayerPanel(parent)
    local function Row() return ns.db.profile.cdmBelowRow end
    local belowMenu   -- fwd: section refreshes + the manual-mode checkbox re-apply via belowMenu.Refresh

    -- Per-bucket config sub-table (front / end). Delegates to the single source of truth in CDMAnchor
    -- (auto-creates + routes the same way the per-dest accessors do), so the two never diverge.
    local function BucketTbl(bucket)
        return ns.CDMAnchor and ns.CDMAnchor.BelowBucketCfg and ns.CDMAnchor.BelowBucketCfg(bucket) or nil
    end

    -- One collapsible "<Front|End> of the row settings" section governing ONLY its half of the row. Every
    -- cadre inside reads/writes the bucket's OWN config via the dest "belowFront"/"belowEnd" (routed by
    -- ns.CDMAnchor to cdmBelowRow.front / .end), so the two sections are fully independent. `bucket` is the
    -- sub-table key ("front"/"end"); `dest` the routed config dest; `title` the section header.
    local function BelowSettingsSection(bucket, dest, title)
        -- Ensure this bucket's Timer/Title/Stacks defaults exist (CfgInit seeds them too; this also covers
        -- a panel opened before CDMGroups finished loading). Additive, missing-keys-only.
        ns.SeedBelowBucketDefaults(BucketTbl(bucket))

        -- Per-bucket icon config accessors for the Timer/Title/Stacks sections + CDM grow/static/spacing.
        local function GDC(key, default) return (ns.CDMAnchor and ns.CDMAnchor.GetDestCfg and ns.CDMAnchor.GetDestCfg(dest, key, default)) or default end
        local function SDC(key, val) if ns.CDMAnchor then ns.CDMAnchor.SetDestCfg(dest, key, val) end end

        -- Bundle for the REUSED essential Timer/Title/Stacks sections. No has/reset → no "Override" toggle;
        -- the section's own `gate` greys its controls on the show checkbox; touch/refresh re-render the menu.
        local bundle = {
            get     = function(key) return GDC(key, nil) end,
            set     = function(key, val) SDC(key, val) end,
            touch   = function() if belowMenu then belowMenu.Refresh() end end,
            refresh = function() if belowMenu then belowMenu.Refresh() end end,
        }

        return { type = "section", label = title, showCheckbox = false,
          headerExtra = ns.ui.SettingsHeaderIcon,
          -- Collapsed by DEFAULT (and re-folded on each tab show via the OnHide/OnShow hooks below):
          -- expanded only while the user has explicitly opened it this visit (settingsCollapsed == false).
          getCollapsed = function() local b = BucketTbl(bucket); return not b or b.settingsCollapsed ~= false end,
          onCollapse   = function(c) local b = BucketTbl(bucket); if b then b.settingsCollapsed = c and true or false end end,
          build = function() return {

            -- ════════════ CDM settings ════════════
            -- Per-bucket "Show press overlay" / "Show Keybinds" (TimerIcon reads these via
            -- ns.CDMAnchor.GetDestCdmFlag for any icon in this bucket) + grow/static/spacing. Flags default OFF.
            { type = "group", title = L["CDM settings"], build = function() return {
                { type = "checkbox", label = L["Show press overlay"],
                  get = function() return ns.CDMAnchor and ns.CDMAnchor.GetDestCdmFlag(dest, "showPressOverlay") or false end,
                  set = function(v) if ns.CDMAnchor then ns.CDMAnchor.SetDestCdmFlag(dest, "showPressOverlay", v) end end },
                { type = "checkbox", label = L["Show Keybinds"],
                  get = function() return ns.CDMAnchor and ns.CDMAnchor.GetDestCdmFlag(dest, "showKeybinds") or false end,
                  set = function(v) if ns.CDMAnchor then ns.CDMAnchor.SetDestCdmFlag(dest, "showKeybinds", v) end end },
                { type = "dropdown", label = L["Grow direction"], width = 180, height = 50,
                  getList = (ns.CDMGroups and ns.CDMGroups.GrowList) or function() return {} end,
                  getCurrentKey = function() return (ns.CDMGroups and ns.CDMGroups.GrowLabel(GDC("growDir", "RIGHT"))) or "" end,
                  onSelect = function(label) if ns.CDMGroups then SDC("growDir", ns.CDMGroups.GrowFromLabel(label)) end end },
                { type = "checkbox", label = L["Static Display"],
                  get = function() return GDC("staticDisplay", false) and true or false end,
                  set = function(v) SDC("staticDisplay", v and true or false) end },
                { type = "textinput", label = L["Spacing"], width = 46, numeric = true, min = 0, max = 64, maxLetters = 2,
                  get = function() return GDC("spacing", 0) end,
                  set = function(v) if v ~= nil then SDC("spacing", v) end end },
            } end },

            -- Border for every icon in this bucket (the CDM manages it; free icons use their own).
            DestBorderEntry(dest),

            -- ════════════ Glow ════════════
            -- Per-bucket glow: a LibCustomGlow halo on a tracker while the tracked spell is PROCCED.
            -- Types pixel/autocast/button.
            { type = "group", title = L["Glow"], build = function() return {
                { type = "checkbox", label = L["Show glow on proc"],
                  get = function() return ns.CDMAnchor and (select(1, ns.CDMAnchor.GetDestGlow(dest))) or false end,
                  set = function(v)
                      if ns.CDMAnchor then ns.CDMAnchor.SetDestGlow(dest, "glowEnabled", v and true or false) end
                      if belowMenu then belowMenu.Refresh() end
                  end },
                { type = "dropdown", label = L["Glow type"], width = 180, height = 50,
                  getList = BPGlowList,
                  enabledBy = function() return ns.CDMAnchor and (select(1, ns.CDMAnchor.GetDestGlow(dest))) or false end,
                  getCurrentKey = function() return BPGlowLabel(ns.CDMAnchor and (select(2, ns.CDMAnchor.GetDestGlow(dest))) or "pixel") end,
                  onSelect = function(label) if ns.CDMAnchor then ns.CDMAnchor.SetDestGlow(dest, "glowType", BPGlowFromLabel(label)) end end },
                { type = "textEditor", label = L["Glow color"],
                  showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                  enabledBy = function() return ns.CDMAnchor and (select(1, ns.CDMAnchor.GetDestGlow(dest))) or false end,
                  getColor = function() return ns.CDMAnchor and (select(3, ns.CDMAnchor.GetDestGlow(dest))) or nil end,
                  onColorChange = function(r, g, b, a) if ns.CDMAnchor then ns.CDMAnchor.SetDestGlow(dest, "glowColor", { r = r, g = g, b = b, a = a }) end end },
            } end },

            -- ════════════ Icons (icon size + Timer / Title / Stacks) ════════════
            { type = "group", title = L["Icons"], build = function() return {
                { type = "label", font = "UnbunkUtilityH6", height = 18, text = L["Icon size"] },
                {
                    type   = "custom",
                    height = 28,
                    build  = function(host)
                        local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        wLbl:SetPoint("LEFT", host, "LEFT", 0, 0)
                        wLbl:SetText(L["W"])
                        local wInput = ns.ui.CreateTextInput({
                            parent = host, width = 46, height = 22,
                            numeric = true, min = 8, max = 512, maxLetters = 3,
                            text = tostring((BucketTbl(bucket) and BucketTbl(bucket).width) or 36),
                            onEnter = function(val)
                                local b = BucketTbl(bucket)
                                if val and val > 0 and b then
                                    b.width = val
                                    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
                                end
                            end,
                        })
                        wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

                        local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
                        hLbl:SetText(L["H"])
                        local hInput = ns.ui.CreateTextInput({
                            parent = host, width = 46, height = 22,
                            numeric = true, min = 8, max = 512, maxLetters = 3,
                            text = tostring((BucketTbl(bucket) and BucketTbl(bucket).height) or 36),
                            onEnter = function(val)
                                local b = BucketTbl(bucket)
                                if val and val > 0 and b then
                                    b.height = val
                                    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
                                end
                            end,
                        })
                        hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                        return {
                            frame = host, height = 28,
                            Refresh = function()
                                local b = BucketTbl(bucket)
                                wInput.SetText(tostring((b and b.width)  or 36))
                                hInput.SetText(tostring((b and b.height) or 36))
                            end,
                        }
                    end,
                },

                -- Timer / Title / Stacks: the SAME shared sections as essential, fed THIS bucket's bundle
                -- (writes to cdmBelowRow.<bucket>, defaults seeded above). Pixel-identical to essential.
                ns.CDMGroups.TimerSection(bundle),
                ns.CDMGroups.TitleSection(bundle),
                ns.CDMGroups.StacksSection(bundle, { cd = true }),
            } end },

          } end }
    end

    local options = {
        H2(L["CDM: Below player frame"]),

        -- Master enable for the WHOLE below-player row, OUTSIDE any cadre (mirrors the
        -- Essential/Utility/Buffs enable checkboxes). OFF -> the row's icons simply DON'T render
        -- (you can still assign icons to the row, they just won't show); the forced RefreshAll
        -- hides them all at once.
        { type = "checkbox", label = L["Enable Below player frame"],
          get = function() return ns.CDMAnchor and ns.CDMAnchor.IsBelowEnabled() end,
          set = function(v)
              if ns.CDMAnchor and ns.CDMAnchor.SetBelowEnabled then ns.CDMAnchor.SetBelowEnabled(v) end
              -- Disabling while the row is unlocked for drag would leave the (now empty) drag
              -- overlay lingering; lock it, mirroring the Manual-mode toggle.
              if not v and ns.CDMAnchor and ns.CDMAnchor.IsBelowUnlocked
                  and ns.CDMAnchor.IsBelowUnlocked() then
                  ns.CDMAnchor.SetBelowUnlocked(false)
              end
              if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
              if belowMenu then belowMenu.Refresh() end
          end },

        -- ════════════ Row icon order (Front / End of the row, drag to reorder) ══════
        -- The per-icon "Icon at the end of the row" checkbox decides which bucket — and so which
        -- "<Front|End> of the row settings" section below — governs each icon.
        CDMRowReorderEntry("belowPlayer"),

        -- ════════════ Manual mode (shared placement of BOTH buckets) ════════════
        -- Placement is a single concern: the enable toggle + unlock-to-drag apply to both buckets, and
        -- the front/end offsets sit together so the parts can be positioned relative to each other.
        -- Per-bucket APPEARANCE/layout lives in the two "… of the row settings" sections below instead.
        -- OFF (default): both buckets stay flush under the PlayerFrame (front bottom-left, end bottom-
        -- right) at 0,0. ON: the per-bucket offsets / drag take effect. The group gate greys the
        -- position controls while the checkbox is off; the checkbox itself stays live.
        { type = "group", title = L["Manual mode"],
          gate = { enabled = function() return Row() and Row().manualEnabled == true end, master = "enable" },
          build = function() return {
            {
                type   = "checkbox",
                ref    = "enable",
                label  = L["Enable manual positioning"],
                get    = function() return Row() and Row().manualEnabled == true end,
                set    = function(val)
                    if Row() then Row().manualEnabled = val end
                    -- Leaving manual mode: re-lock any active drag; the FORCED RefreshAll then snaps
                    -- both buckets back to their flush 0,0 positions (BelowOffset -> 0,0). Forced because
                    -- manualEnabled is not in the layout signature and the stored offset VALUES don't
                    -- change — only their meaning (honoured vs ignored) — so a non-forced refresh would
                    -- early-out on an unchanged signature and leave the buckets at their manual offsets.
                    if not val and ns.CDMAnchor and ns.CDMAnchor.IsBelowUnlocked
                        and ns.CDMAnchor.IsBelowUnlocked() then
                        ns.CDMAnchor.SetBelowUnlocked(false)
                    end
                    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll(true) end
                    if belowMenu then belowMenu.Refresh() end
                end,
            },

            -- Manual offsets, set independently per bucket: the FRONT bucket from the
            -- player frame's bottom-LEFT corner, the END bucket from its bottom-RIGHT.
            {
                type   = "custom",
                height = 74,
                build  = function(host)
                    local offLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                    offLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                    offLbl:SetText(L["Offset"])

                    -- One "<label>  X [..] Y [..]" row writing the given config keys; returns
                    -- a closure that re-reads both inputs from the saved values.
                    local function offsetRow(yOff, rowText, keyX, keyY)
                        local rLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        rLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, yOff)
                        rLbl:SetWidth(44); rLbl:SetJustifyH("LEFT")
                        rLbl:SetText(rowText)

                        local xLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        xLbl:SetPoint("LEFT", rLbl, "RIGHT", 2, 0)
                        xLbl:SetText("X")
                        local xInput = ns.ui.CreateTextInput({
                            parent = host, width = 56, height = 22,
                            numeric = true, allowNegative = true, min = -2000, max = 2000, maxLetters = 5,
                            text = tostring((Row() and Row()[keyX]) or 0),
                            onEnter = function(val)
                                if val ~= nil and Row() then
                                    Row()[keyX] = val
                                    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
                                end
                            end,
                        })
                        xInput.frame:SetPoint("LEFT", xLbl, "RIGHT", 4, 0)

                        local yLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        yLbl:SetPoint("LEFT", xInput.frame, "RIGHT", 12, 0)
                        yLbl:SetText("Y")
                        local yInput = ns.ui.CreateTextInput({
                            parent = host, width = 56, height = 22,
                            numeric = true, allowNegative = true, min = -2000, max = 2000, maxLetters = 5,
                            text = tostring((Row() and Row()[keyY]) or 0),
                            onEnter = function(val)
                                if val ~= nil and Row() then
                                    Row()[keyY] = val
                                    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
                                end
                            end,
                        })
                        yInput.frame:SetPoint("LEFT", yLbl, "RIGHT", 4, 0)

                        return function()
                            xInput.SetText(tostring((Row() and Row()[keyX]) or 0))
                            yInput.SetText(tostring((Row() and Row()[keyY]) or 0))
                        end
                    end

                    local refreshFront = offsetRow(-24, L["Front"], "offsetX",    "offsetY")
                    local refreshEnd   = offsetRow(-50, L["End"],   "endOffsetX", "endOffsetY")

                    local function Refresh()
                        if not host:GetParent() then return end
                        refreshFront(); refreshEnd()
                    end
                    ns.OnBelowRowMoved = Refresh
                    return { frame = host, height = 74, Refresh = Refresh }
                end,
            },

            -- Unlock to drag either bucket (front / end) to a custom spot.
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

        -- ════════════ Front / End of the row settings (one collapsible section per bucket) ════════════
        -- Each governs ONLY its half of the row, routed by the dest "belowFront"/"belowEnd".
        BelowSettingsSection("front", "belowFront", L["Front of the row settings"]),
        BelowSettingsSection("end",   "belowEnd",   L["End of the row settings"]),
    }
    belowMenu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })

    -- Both "… of the row settings" sections start collapsed AND re-fold whenever the user leaves &
    -- returns to this tab: on hide, persist collapsed = true for each bucket; on show, Rebuild re-reads
    -- getCollapsed so the sections fold again. (Same idiom as the CDMGroups group sections.)
    parent:HookScript("OnHide", function()
        for _, bucket in ipairs({ "front", "end" }) do
            local b = BucketTbl(bucket)
            if b then b.settingsCollapsed = true end
        end
    end)
    parent:HookScript("OnShow", function()
        if belowMenu then belowMenu.Rebuild() end
    end)

    return belowMenu
end

-- ── CDM row reorder strips (essential / utility / below player) ───────────────
-- One pair of drag-reorder cadres ("Front of the row" / "End of the row") per row
-- the destination renders, side by side. An empty cadre shows a grey "No icons".
-- belowPlayer reports a single row, so it shows just one Front/End pair (no row
-- label) — the exact same widget as essential/utility, driven by the same bucket
-- APIs (GetRowCount / GetBucketIcons / SetBucketOrder).
function CDMRowReorderEntry(dest)
    return {
            type   = "custom",
            height = 90,
            build  = function(host)
                local GAP, HALF, SIDE = 10, 245, 8
                local rows = {}   -- pool: rows[r] = { container, label, front, endbox, frontStrip, endStrip }

                -- The drop: move `itemId` from `fromStrip`'s bucket to `toStrip`'s bucket of the
                -- SAME row at holeIndex. Each strip carries its bucket identity (dest/row/atEnd).
                --   * Same bucket  -> reorder: drop itemId, re-insert it at the hole, persist.
                --   * Front <-> End -> flip the icon's cdmAtEnd (its bucket membership), then write
                --     the TARGET bucket order with itemId at the hole and the SOURCE bucket without
                --     it. Both buckets are persisted via SetBucketOrder (front=false / end=true).
                -- Driven entirely by our buckets — we never touch the native viewer (no taint).
                local function doMove(itemId, fromStrip, toStrip, holeIndex)
                    if not ns.CDMAnchor then return end
                    local rr = toStrip.row
                    -- Source bucket order, minus the moved id.
                    local srcIds = {}
                    for _, it in ipairs(ns.CDMAnchor.GetBucketIcons(fromStrip.dest, fromStrip.row, fromStrip.atEnd)) do
                        if it.id ~= itemId then srcIds[#srcIds + 1] = it.id end
                    end
                    if fromStrip.atEnd == toStrip.atEnd then
                        -- Same bucket: re-insert at the hole within the (de-duped) source list.
                        local at = math.max(1, math.min(#srcIds + 1, (holeIndex or 0) + 1))
                        table.insert(srcIds, at, itemId)
                        ns.CDMAnchor.SetBucketOrder(fromStrip.dest, fromStrip.row, fromStrip.atEnd, srcIds)
                    else
                        -- Cross-bucket: reject if the TARGET bucket is already at its cap (4) — the icon
                        -- snaps back (the rebuild re-reads the unchanged order), nothing shifts. The
                        -- transient "Row is full" hint already shows on the target while hovering it.
                        if ns.CDMAnchor.BucketIconCount(toStrip.dest, rr, toStrip.atEnd)
                            >= ns.CDMAnchor.BucketCap(toStrip.dest) then
                            return
                        end
                        -- Cross-bucket: flip the icon's end-of-row flag, then write both buckets.
                        ns.CDMAnchor.SetIconAtEnd(itemId, toStrip.atEnd)
                        local dstIds = {}
                        for _, it in ipairs(ns.CDMAnchor.GetBucketIcons(toStrip.dest, rr, toStrip.atEnd)) do
                            if it.id ~= itemId then dstIds[#dstIds + 1] = it.id end
                        end
                        local at = math.max(1, math.min(#dstIds + 1, (holeIndex or 0) + 1))
                        table.insert(dstIds, at, itemId)
                        ns.CDMAnchor.SetBucketOrder(toStrip.dest, rr, toStrip.atEnd, dstIds)
                        ns.CDMAnchor.SetBucketOrder(fromStrip.dest, fromStrip.row, fromStrip.atEnd, srcIds)
                    end
                    -- Re-apply the live CDM (SetBucketOrder already calls RefreshAll, but the cross-
                    -- bucket flip needs the layout re-bucketed). Defer the panel rebuild one frame so
                    -- it runs AFTER the drag controller finishes re-laying its (about-to-be-replaced)
                    -- strips — the rebuild swaps in fresh strips + dragGroup and refreshes the "+" gating.
                    ns.CDMAnchor.RefreshAll(true)
                    C_Timer.After(0, function() if ns.RebuildActiveModule then ns.RebuildActiveModule() end end)
                end

                local function ensureRow(r)
                    local rw = rows[r]
                    if rw then return rw end
                    rw = {}
                    -- One drag group per ROW: the Front and End strips of this row swap tiles; other
                    -- rows are separate groups (a cross-row move would change cdmRow, which these
                    -- bucket APIs don't persist — handled on each icon's own tab instead).
                    rw.dragGroup = { strips = {} }
                    rw.container = CreateFrame("Frame", nil, host)
                    rw.container:SetWidth(HALF * 2 + GAP)

                    rw.label = rw.container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                    rw.label:SetPoint("TOPLEFT", rw.container, "TOPLEFT", 0, 0)

                    -- Custom-icon hooks shared by both strips: the "+" adds a custom
                    -- icon into THIS cadre's bucket (dest/row/atEnd), the X removes one,
                    -- the pen re-opens its spell-ID editor. (id = the icon's frame name.)
                    local function onRemoveCustom(id)
                        local cid = ns.CustomCDM and ns.CustomCDM.IdFromFrameName(id)
                        if cid then ns.CustomCDM.ConfirmRemove(cid) end
                    end
                    local function onEditCustom(id)
                        local cid = ns.CustomCDM and ns.CustomCDM.IdFromFrameName(id)
                        if cid then ns.CustomCDM.PromptEdit(cid) end
                    end
                    -- The pen on a non-custom (addon) icon jumps to that tracker's tab.
                    local function onNavigate(panel)
                        if panel and ns.NavigateToPanel then ns.NavigateToPanel(panel) end
                    end
                    -- getIcons wrapper: tag each non-custom (addon) icon with its nav panel.
                    local function bucketIcons(atEnd)
                        local list = (ns.CDMAnchor and ns.CDMAnchor.GetBucketIcons(dest, r, atEnd)) or {}
                        for _, it in ipairs(list) do
                            if not it.custom then it.nav = FreePanelForFrame(it.id) end
                        end
                        return list
                    end
                    -- Each bucket (front / end) is capped INDEPENDENTLY at BucketCap (4 below-player): the
                    -- "+" hides on a full bucket, and a cross-bucket drop into a full bucket is rejected in
                    -- doMove. Reorder within a full bucket still works.
                    local function canAddToBucket(atEnd)
                        if not ns.CDMAnchor then return false end
                        return ns.CDMAnchor.BucketIconCount(dest, r, atEnd) < ns.CDMAnchor.BucketCap(dest)
                    end

                    rw.front = ns.ui.CreateGroupBox({
                        parent = rw.container, title = L["Front of the row"], width = HALF, sidePad = SIDE,
                        createContent = function(cf)
                            rw.frontStrip = ns.ui.CreateIconReorderStrip({
                                parent = cf, width = HALF - 2 * SIDE, emptyText = L["No icons"],
                                dragGroup = rw.dragGroup,   -- shares tiles with the End strip of this row
                                getIcons = function() return bucketIcons(false) end,
                                setOrder = function(ids) if ns.CDMAnchor then ns.CDMAnchor.SetBucketOrder(dest, r, false, ids) end end,
                                onMove         = doMove,
                                onAdd          = function() if ns.CustomCDM then ns.CustomCDM.PromptAdd(dest, r, false) end end,
                                canAdd         = function() return canAddToBucket(false) end,
                                fullText       = L["Row is full"],
                                onRemoveCustom = onRemoveCustom,
                                onEditCustom   = onEditCustom,
                                onNavigate     = onNavigate,
                            })
                            rw.frontStrip.dest, rw.frontStrip.row, rw.frontStrip.atEnd = dest, r, false
                            rw.frontStrip.frame:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
                            return 40
                        end,
                    })
                    rw.endbox = ns.ui.CreateGroupBox({
                        parent = rw.container, title = L["End of the row"], width = HALF, sidePad = SIDE,
                        createContent = function(cf)
                            rw.endStrip = ns.ui.CreateIconReorderStrip({
                                parent = cf, width = HALF - 2 * SIDE, emptyText = L["No icons"],
                                dragGroup = rw.dragGroup,   -- shares tiles with the Front strip of this row
                                getIcons = function() return bucketIcons(true) end,
                                setOrder = function(ids) if ns.CDMAnchor then ns.CDMAnchor.SetBucketOrder(dest, r, true, ids) end end,
                                onMove         = doMove,
                                onAdd          = function() if ns.CustomCDM then ns.CustomCDM.PromptAdd(dest, r, true) end end,
                                canAdd         = function() return canAddToBucket(true) end,
                                fullText       = L["Row is full"],
                                onRemoveCustom = onRemoveCustom,
                                onEditCustom   = onEditCustom,
                                onNavigate     = onNavigate,
                            })
                            rw.endStrip.dest, rw.endStrip.row, rw.endStrip.atEnd = dest, r, true
                            rw.endStrip.frame:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
                            return 40
                        end,
                    })
                    -- "Drag" hint under each cadre's bottom border.
                    AddDragHint(rw.front.frame)
                    AddDragHint(rw.endbox.frame)
                    rows[r] = rw
                    return rw
                end

                local function rebuildAll()
                    local nRows = (ns.CDMAnchor and ns.CDMAnchor.GetRowCount and ns.CDMAnchor.GetRowCount(dest)) or 0
                    if nRows < 1 then nRows = 1 end          -- always show one (possibly empty) pair
                    local showLabel = nRows > 1
                    local y = 0
                    for r = 1, nRows do
                        local rw = ensureRow(r)
                        rw.container:Show()
                        rw.container:ClearAllPoints()
                        rw.container:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)

                        local labelH = 0
                        if showLabel then
                            rw.label:SetText(string.format(L["Row %d"], r))
                            rw.label:Show()
                            labelH = 20
                        else
                            rw.label:Hide()
                        end

                        rw.front.frame:ClearAllPoints()
                        rw.front.frame:SetPoint("TOPLEFT", rw.container, "TOPLEFT", 0, -labelH)
                        rw.endbox.frame:ClearAllPoints()
                        rw.endbox.frame:SetPoint("TOPLEFT", rw.container, "TOPLEFT", HALF + GAP, -labelH)

                        rw.frontStrip.Refresh()
                        rw.endStrip.Refresh()

                        -- +16 (was +10): leave room for the "Drag" hint under the cadres.
                        local rowH = labelH + math.max(rw.front.height, rw.endbox.height) + 16
                        rw.container:SetHeight(rowH)
                        y = y + rowH
                    end
                    for r = nRows + 1, #rows do rows[r].container:Hide() end
                    host:SetHeight(math.max(1, y))
                    if ns.ResizeActiveModule then ns.ResizeActiveModule() end
                end
                rebuildAll()

                return { frame = host, height = math.max(90, host:GetHeight() or 90), Refresh = rebuildAll }
            end,
    }
end


-- ── Free icons sub-tab ────────────────────────────────────────────────────────
-- A big (10-row) wrapping grid of every icon taken OUT of the Cooldown Manager, in
-- add order. Custom ones get the pen (edit) / cross (delete); addon tracker ones are
-- clicked to jump to their own settings. A trailing "+" adds a new free custom icon.
local function CreateFreeIconsPanel(parent)
    local function onEditFree(itemId)
        local cid = ns.CustomCDM and ns.CustomCDM.IdFromFrameName(itemId)
        if cid then ns.CustomCDM.PromptEdit(cid) end
    end
    -- Free icons are positioned independently on screen (each by its own posX/posY), so this
    -- grid's order is purely a display preference. We persist it in the SAME per-frame order map
    -- the CDM buckets use (ns.db.profile.cdmOrder) — keyed by each icon's unique frame id, and a
    -- free icon is never in a bucket, so the bucket sorts never see these entries. Drag reflows
    -- the grid fluidly (BuffGroups-style, multi-row) and commits the new order on release.
    local function freeOrderMap()
        if not (ns.db and ns.db.profile) then return nil end
        ns.db.profile.cdmOrder = ns.db.profile.cdmOrder or {}
        return ns.db.profile.cdmOrder
    end
    local options = {
        H2(L["CDM: Free icons"]),

        -- Master enable for ALL free icons (those taken out of the Cooldown Manager). OFF -> every
        -- free icon simply doesn't render (you can still add / configure them here). Same hide-when-off
        -- behaviour as the Below player frame toggle; RefreshAll(true) applies it at once.
        { type = "checkbox", label = L["Enable Free icons"],
          get = function() return ns.CDMAnchor and ns.CDMAnchor.IsFreeEnabled() end,
          set = function(v)
              if ns.CDMAnchor and ns.CDMAnchor.SetFreeEnabled then ns.CDMAnchor.SetFreeEnabled(v) end
              if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
          end },
        { type = "label", font = "UnbunkUtilityH6", height = 36,
          text = L["Icons taken out of the Cooldown Manager. The pen edits a custom icon (cross deletes it) or opens an addon icon's tab; the + adds a new free custom icon."] },
        {
            type   = "custom",
            height = 10,
            build  = function(host)
                -- A cadre framing the whole 10-row grid: just a 1px border, NO fill. A filled slab (even
                -- at 0.10/0.5) reads as a greyed/dimmed box over the panel, so keep it a plain thin-bordered
                -- outline. The strip sits inset by BOX_PAD; the host reserves the extra height.
                local BOX_PAD = 6
                local box = CreateFrame("Frame", nil, host, "BackdropTemplate")
                box:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                box:SetBackdrop({
                    edgeFile = "Interface/Buttons/WHITE8X8",
                    edgeSize = 1,
                })
                box:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
                local s = ns.ui.CreateIconReorderStrip({
                    parent = host, width = 500, rows = 10, wrap = true, emptyText = L["No icons"],
                    getIcons = function()
                        local out = {}
                        if ns.CustomCDM then
                            for _, it in ipairs(ns.CustomCDM.GetFreeIcons()) do out[#out + 1] = it end
                        end
                        if ns.CDMAnchor and ns.CDMAnchor.GetFreeTrackerIcons then
                            for _, it in ipairs(ns.CDMAnchor.GetFreeTrackerIcons()) do
                                local nav = FreePanelForFrame(it.id)
                                if nav then it.nav = nav; out[#out + 1] = it end
                            end
                        end
                        -- Stable sort by the saved free order (add order is the fallback for any
                        -- not-yet-dragged icon, so a fresh grid keeps its current look).
                        local map = freeOrderMap()
                        if map then
                            local base = {}
                            for i, it in ipairs(out) do base[it.id] = i end
                            table.sort(out, function(a, b)
                                local ao = map[a.id] or (1000 + base[a.id])
                                local bo = map[b.id] or (1000 + base[b.id])
                                if ao ~= bo then return ao < bo end
                                return base[a.id] < base[b.id]
                            end)
                        end
                        return out
                    end,
                    -- Persist the dragged order into the shared per-frame map (display-only).
                    setOrder = function(ids)
                        local map = freeOrderMap()
                        if map then for i, id in ipairs(ids) do map[id] = i end end
                    end,
                    onAdd          = function() if ns.CustomCDM then ns.CustomCDM.PromptAddFreeChoice() end end,
                    onRemoveCustom = function(itemId)
                        local cid = ns.CustomCDM and ns.CustomCDM.IdFromFrameName(itemId)
                        if cid then ns.CustomCDM.ConfirmRemove(cid) end
                    end,
                    onEditCustom   = onEditFree,
                    onNavigate     = function(panel)
                        if panel and ns.NavigateToPanel then ns.NavigateToPanel(panel) end
                    end,
                })
                s.frame:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -BOX_PAD)
                box:SetSize(500 + 2 * BOX_PAD, s.height + 2 * BOX_PAD)
                host:SetHeight(s.height + 2 * BOX_PAD)
                return { frame = host, height = s.height + 2 * BOX_PAD, Refresh = s.Refresh }
            end,
        },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

-- ── Registration (sub-tabs) ────────────────────────────────────────────────────
UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Addon settings"],          nil, CreateAddonSettingsPanel)
    UnbunkUtility.RegisterModule(L["Player speed display"],    nil, CreatePlayerSpeedPanel)
    UnbunkUtility.RegisterModule(L["Multi-alert combo"],       nil, CreateComboPanel)
    UnbunkUtility.RegisterModule(L["Boss reset sound"],        nil, CreateBossResetPanel)
    UnbunkUtility.RegisterModule(L["Death alert anti-spam"],   nil, CreateDeathAntiSpamPanel)
    UnbunkUtility.RegisterModule(L["Below player frame"],      nil, CreateBelowPlayerPanel)
    UnbunkUtility.RegisterModule(L["Free icons"],             nil, CreateFreeIconsPanel)
end)
