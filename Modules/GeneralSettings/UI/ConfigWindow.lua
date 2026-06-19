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
    local belowMenu   -- fwd: the manual-mode checkbox re-applies its gate via belowMenu.Refresh
    -- Per-dest icon config accessors (Title / Stacks cadres → cdmBelowRow; TimerIcon reads them back).
    local function GDC(key, default) return (ns.CDMAnchor and ns.CDMAnchor.GetDestCfg and ns.CDMAnchor.GetDestCfg("belowPlayer", key, default)) or default end
    local function SDC(key, val) if ns.CDMAnchor then ns.CDMAnchor.SetDestCfg("belowPlayer", key, val) end end

    local options = {
        H2(L["CDM: Below player frame"]),

        -- ════════════ Row icon order (Front / End of the row, drag to reorder) ══════
        -- The per-icon "Icon at the end of the row" checkbox decides which cadre each icon
        -- lands in; the below-player destination is a single row, so exactly one pair shows
        -- (no "Row N" label).
        CDMRowReorderEntry("belowPlayer"),

        -- ════════════ Below player frame settings (collapsible section, gear icon) ════════════
        -- Mirrors the essential group's "settings" section: a gear (ns.ui.SettingsHeaderIcon) on the
        -- right, holding the per-dest cadres. Defaults expanded (the whole tab is settings).
        { type = "section", label = L["Below player frame settings"], showCheckbox = false,
          headerExtra = ns.ui.SettingsHeaderIcon,
          getCollapsed = function() local r = Row(); return r and r.settingsCollapsed == true end,
          onCollapse   = function(c) local r = Row(); if r then r.settingsCollapsed = c and true or false end end,
          build = function() return {

        -- ════════════ CDM settings ════════════
        -- Per-dest "Show press overlay" / "Show Keybinds" for the below-player icons (TimerIcon reads
        -- these via ns.CDMAnchor.GetDestCdmFlag for any icon pinned below the player). Both default OFF.
        { type = "group", title = L["CDM settings"], build = function() return {
            { type = "checkbox", label = L["Show press overlay"],
              get = function() return ns.CDMAnchor and ns.CDMAnchor.GetDestCdmFlag("belowPlayer", "showPressOverlay") or false end,
              set = function(v) if ns.CDMAnchor then ns.CDMAnchor.SetDestCdmFlag("belowPlayer", "showPressOverlay", v) end end },
            { type = "checkbox", label = L["Show Keybinds"],
              get = function() return ns.CDMAnchor and ns.CDMAnchor.GetDestCdmFlag("belowPlayer", "showKeybinds") or false end,
              set = function(v) if ns.CDMAnchor then ns.CDMAnchor.SetDestCdmFlag("belowPlayer", "showKeybinds", v) end end },
        } end },

        -- ════════════ Manual mode ════════════
        -- OFF (default): both buckets stay flush under the PlayerFrame (front bottom-left,
        -- end bottom-right) at 0,0. ON: the per-bucket offsets / drag take effect. The
        -- group gate greys the position controls while the checkbox is off; the checkbox
        -- itself stays live.
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
                    -- Leaving manual mode: re-lock any active drag; RefreshAll then snaps
                    -- both buckets back to their flush 0,0 positions (BelowOffset -> 0,0).
                    if not val and ns.CDMAnchor and ns.CDMAnchor.IsBelowUnlocked
                        and ns.CDMAnchor.IsBelowUnlocked() then
                        ns.CDMAnchor.SetBelowUnlocked(false)
                    end
                    if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
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

        -- Border for every below-player icon (the CDM manages it; free icons use their own).
        DestBorderEntry("belowPlayer"),

        -- ════════════ Glow ════════════
        -- Per-dest glow: a LibCustomGlow halo on a tracker while it is ACTIVE (green/buff-up). Types
        -- pixel/autocast/button (proc is N/A for trackers).
        { type = "group", title = L["Glow"], build = function() return {
            { type = "checkbox", label = L["Show glow"],
              get = function() return ns.CDMAnchor and (select(1, ns.CDMAnchor.GetDestGlow("belowPlayer"))) or false end,
              set = function(v)
                  if ns.CDMAnchor then ns.CDMAnchor.SetDestGlow("belowPlayer", "glowEnabled", v and true or false) end
                  if belowMenu then belowMenu.Refresh() end
              end },
            { type = "dropdown", label = L["Glow type"], width = 180, height = 50,
              getList = BPGlowList,
              enabledBy = function() return ns.CDMAnchor and (select(1, ns.CDMAnchor.GetDestGlow("belowPlayer"))) or false end,
              getCurrentKey = function() return BPGlowLabel(ns.CDMAnchor and (select(2, ns.CDMAnchor.GetDestGlow("belowPlayer"))) or "pixel") end,
              onSelect = function(label) if ns.CDMAnchor then ns.CDMAnchor.SetDestGlow("belowPlayer", "glowType", BPGlowFromLabel(label)) end end },
            { type = "textEditor", label = L["Glow color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return ns.CDMAnchor and (select(1, ns.CDMAnchor.GetDestGlow("belowPlayer"))) or false end,
              getColor = function() return ns.CDMAnchor and (select(3, ns.CDMAnchor.GetDestGlow("belowPlayer"))) or nil end,
              onColorChange = function(r, g, b, a) if ns.CDMAnchor then ns.CDMAnchor.SetDestGlow("belowPlayer", "glowColor", { r = r, g = g, b = b, a = a }) end end },
        } end },

        -- ════════════ Icons (icon size; Timer / Title / Stacks added in the next increment) ════════════
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
                        text = tostring((Row() and Row().width) or 36),
                        onEnter = function(val)
                            if val and val > 0 and Row() then
                                Row().width = val
                                if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
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
                        frame = host, height = 28,
                        Refresh = function()
                            wInput.SetText(tostring((Row() and Row().width)  or 36))
                            hInput.SetText(tostring((Row() and Row().height) or 36))
                        end,
                    }
                end,
            },

            -- Timer (per-dest): overrides the timer text colour / size / position / show for below-player
            -- icons; unset keys fall back to each tracker's own timer config.
            { type = "group", title = L["Timer"], build = function() return {
                { type = "checkbox", label = L["Show timer"],
                  get = function() return GDC("showTimer", true) and true or false end,
                  set = function(v) SDC("showTimer", v and true or false); if belowMenu then belowMenu.Refresh() end end },
                { type = "textEditor", label = L["Timer color"],
                  showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                  getColor = function() return GDC("timerColor", nil) end,
                  onColorChange = function(r, g, b, a) SDC("timerColor", { r = r, g = g, b = b, a = a }) end },
                { type = "textinput", label = L["Size"], width = 46, numeric = true, min = 6, max = 40, maxLetters = 2,
                  get = function() return GDC("timerFontSize", 14) end,
                  set = function(v) if v and v > 0 then SDC("timerFontSize", v) end end },
                { type = "dropdown", label = L["Position"], width = 180, height = 50,
                  getList = ns.AnchorList,
                  getCurrentKey = function() return ns.AnchorLabel(GDC("timerPos", "CENTER")) end,
                  onSelect = function(label) SDC("timerPos", ns.AnchorFromLabel(label)) end },
            } end },

            -- Title = the tracked spell/item NAME (per-dest styled). May overflow a small icon — use the
            -- Position dropdown (e.g. below the icon) to place it.
            { type = "group", title = L["Title"], build = function() return {
                { type = "checkbox", label = L["Show title"],
                  get = function() return GDC("titleShow", false) and true or false end,
                  set = function(v) SDC("titleShow", v and true or false); if belowMenu then belowMenu.Refresh() end end },
                { type = "textEditor", label = L["Title color"],
                  showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                  enabledBy = function() return GDC("titleShow", false) and true or false end,
                  getColor = function() return GDC("titleColor", nil) end,
                  onColorChange = function(r, g, b, a) SDC("titleColor", { r = r, g = g, b = b, a = a }) end },
                { type = "textinput", label = L["Size"], width = 46, numeric = true, min = 6, max = 40, maxLetters = 2,
                  enabledBy = function() return GDC("titleShow", false) and true or false end,
                  get = function() return GDC("titleSize", 10) end,
                  set = function(v) if v and v > 0 then SDC("titleSize", v) end end },
                { type = "dropdown", label = L["Position"], width = 180, height = 50,
                  getList = ns.AnchorList,
                  enabledBy = function() return GDC("titleShow", false) and true or false end,
                  getCurrentKey = function() return ns.AnchorLabel(GDC("titlePos", "BOTTOM")) end,
                  onSelect = function(label) SDC("titlePos", ns.AnchorFromLabel(label)) end },
            } end },

            -- Stacks / charges = the tracked spell's charges, or the item count in bags.
            { type = "group", title = L["Stacks/Charges"], build = function() return {
                { type = "checkbox", label = L["Show stacks"],
                  get = function() return GDC("stackShow", false) and true or false end,
                  set = function(v) SDC("stackShow", v and true or false); if belowMenu then belowMenu.Refresh() end end },
                { type = "textEditor", label = L["Stacks color"],
                  showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                  enabledBy = function() return GDC("stackShow", false) and true or false end,
                  getColor = function() return GDC("stackColor", nil) end,
                  onColorChange = function(r, g, b, a) SDC("stackColor", { r = r, g = g, b = b, a = a }) end },
                { type = "textinput", label = L["Size"], width = 46, numeric = true, min = 6, max = 40, maxLetters = 2,
                  enabledBy = function() return GDC("stackShow", false) and true or false end,
                  get = function() return GDC("stackSize", 12) end,
                  set = function(v) if v and v > 0 then SDC("stackSize", v) end end },
                { type = "dropdown", label = L["Position"], width = 180, height = 50,
                  getList = ns.AnchorList,
                  enabledBy = function() return GDC("stackShow", false) and true or false end,
                  getCurrentKey = function() return ns.AnchorLabel(GDC("stackPos", "BOTTOMRIGHT")) end,
                  onSelect = function(label) SDC("stackPos", ns.AnchorFromLabel(label)) end },
            } end },
        } end },

            } end },   -- close: Below player frame settings section
    }
    belowMenu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
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
        { type = "label", font = "UnbunkUtilityH6", height = 36,
          text = L["Icons taken out of the Cooldown Manager. The pen edits a custom icon (cross deletes it) or opens an addon icon's tab; the + adds a new free custom icon."] },
        {
            type   = "custom",
            height = 10,
            build  = function(host)
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
                    onAdd          = function() if ns.CustomCDM then ns.CustomCDM.PromptAddFree() end end,
                    onRemoveCustom = function(itemId)
                        local cid = ns.CustomCDM and ns.CustomCDM.IdFromFrameName(itemId)
                        if cid then ns.CustomCDM.ConfirmRemove(cid) end
                    end,
                    onEditCustom   = onEditFree,
                    onNavigate     = function(panel)
                        if panel and ns.NavigateToPanel then ns.NavigateToPanel(panel) end
                    end,
                })
                s.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                host:SetHeight(s.height)
                return { frame = host, height = s.height, Refresh = s.Refresh }
            end,
        },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

-- ── Registration (sub-tabs) ────────────────────────────────────────────────────
local initGS = CreateFrame("Frame")
initGS:RegisterEvent("ADDON_LOADED")
initGS:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Addon settings"],          nil, CreateAddonSettingsPanel)
    UnbunkUtility.RegisterModule(L["Player speed display"],    nil, CreatePlayerSpeedPanel)
    UnbunkUtility.RegisterModule(L["Multi-alert combo"],       nil, CreateComboPanel)
    UnbunkUtility.RegisterModule(L["Boss reset sound"],        nil, CreateBossResetPanel)
    UnbunkUtility.RegisterModule(L["Death alert anti-spam"],   nil, CreateDeathAntiSpamPanel)
    UnbunkUtility.RegisterModule(L["Below player frame"],      nil, CreateBelowPlayerPanel)
    UnbunkUtility.RegisterModule(L["Free icons"],             nil, CreateFreeIconsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
