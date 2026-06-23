-- Modules/BLTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.BLTracker = ns.BLTracker or {}
local BL = ns.BLTracker

local function CreateBLTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe
    local function rebuildMenu() if menu then menu.Rebuild() end end
    -- Re-apply the icon after an Override change. The Apply* re-read config through TimerIcon, which (for a
    -- migrated in-CDM icon) now reads the per-icon override; a forced CDM refresh re-lays the group out.
    local function applyIcon()
        if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- in-CDM size override -> force the engine to re-pack (its layout sig folds the epoch)
        BL.ApplyVisuals(); BL.ApplyFont(); BL.ApplyBorder(); BL.ApplySize()
        if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
    end

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
                        set    = function(val) BL.CfgSet("enabled", val); if BL.Sync then BL.Sync() end; if menu then menu.Refresh() end end,
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
        -- Default override-set (seedValues): ONLY Timer (size 14 + urgency thresholds); the rest inherits the group.
        ns.CDMGroups.TrackerIconGroup({
            get = BL.CfgGet, set = BL.CfgSet,
            frameName = "BLTrackerFrame", defaultDest = "essential", LSM = LSM,
            showIconHeight = 24,
            enabledBy = function() return BL.CfgGet("enabled") ~= false end,
            rebuild = rebuildMenu, applyIcon = applyIcon,
            onShowIcon = function() BL.ApplyVisuals() end,
            showIconInline = { { type = "checkbox", label = L["Always show"],
                get = function() return BL.CfgGet("alwaysShow") ~= false end,
                set = function(val) BL.CfgSet("alwaysShow", val); BL.ApplyVisuals() end,
                point = { "LEFT", "LEFT", 150, 0 } } },
            afterInclude = function() BL.ApplySize(); BL.ApplyPosition(); rebuildMenu() end,
            sizeApply = function() BL.ApplySize() end,
            seedValues = function() return ns.DefaultTrackerTimerSeed() end,
            pos = {
                getX = function() return BL.CfgGet("posX") end,
                getY = function() return BL.CfgGet("posY") end,
                onApply = function(x, yv) if x then BL.CfgSet("posX", x) end if yv then BL.CfgSet("posY", yv) end BL.ApplyPosition() end,
                onUnlock = function() BL.SetUnlocked(true) end,
                onLock = function() BL.SetUnlocked(false); if BL.pe then BL.pe.Refresh() end end,
                isUnlocked = function() return BL.IsUnlocked() end,
                onBuilt = function(w) BL.pe = w end,
            },
        }),
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

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["BL Tracker"], nil, CreateBLTrackerPanel)
end)
