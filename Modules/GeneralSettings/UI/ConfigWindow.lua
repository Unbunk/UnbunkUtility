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
            type = "header",
            font = "GameFontNormalLarge",
            text = L["Minimap icon"],
        },
        {
            type   = "checkbox",
            label  = L["Show minimap button (left-click to open settings, drag to reposition)"],
            get    = function() return not (ns.MinimapIcon_IsHidden and ns.MinimapIcon_IsHidden()) end,
            set    = function(val)
                if ns.MinimapIcon_SetHidden then ns.MinimapIcon_SetHidden(not val) end
            end,
        },

        -- ── Combo sounds section ─────────────────────────────────────────────
        {
            type = "header",
            font = "GameFontNormalLarge",
            text = L["Multi-alert combo sounds"],
        },
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

        -- ── Death-alert anti-spam section ────────────────────────────────────
        {
            type = "header",
            font = "GameFontNormalLarge",
            text = L["Death alert anti-spam"],
        },

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

        -- ── Boss reset sound section ─────────────────────────────────────────
        {
            type = "header",
            font = "GameFontNormalLarge",
            text = L["Boss reset sound"],
        },
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
