-- Modules/HealthstoneTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

local function CreateHealthstoneTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe
    local function rebuildMenu() if menu then menu.Rebuild() end end
    -- Cold-path cadre edit: HT.ApplyAll / RefreshAll repaint via the GATED ApplyDerivedSizing (setSize),
    -- which would skip a style-only change. Bump the shared style epoch so the re-style gate re-derives once.
    local function applyIcon()
        if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end
        HT.ApplyAll()
        if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Healthstone Tracker"] },

        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (Test button, instance
            -- filter, etc.) except the enable checkbox itself, which stays live to re-enable.
            gate  = { enabled = function() return HT.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable Healthstone Tracker"],
                        get    = function() return HT.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            HT.CfgSet("enabled", val)
                            -- Drive the live transition: start/cancel the steady-state
                            -- ticker so a disabled module is fully stopped (and re-enabling
                            -- restarts it) without needing a /reload.
                            if HT.SetEnabled then HT.SetEnabled(val) end
                            HT.ApplyAll()
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- ── Test button (timed preview: a 2-charge stone with the cooldown
                    -- recharging, auto-stops — not a toggle) ──────────────────────────────
                    {
                        type       = "button",
                        label      = L["Test"],
                        width      = 100,
                        height     = 22,
                        hostHeight = 30,
                        btnOffsetY = -4,
                        onClick    = function() if HT.RunTest then HT.RunTest() end end,
                    },

                    -- ── Instance filter ───────────────────────────────────────────────────
                    {
                        type      = "instanceFilter",
                        getConfig = function() return HT.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local filter = HT.CfgGet("instanceFilter")
                            filter[key] = val
                            HT.CfgSet("instanceFilter", filter)
                        end,
                    },
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            enabledBy = function() return HT.CfgGet("enabled") ~= false end,
            build = function()
                return {
                    -- ── Sound on use ──────────────────────────────────────────────────────
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound on use"],
                        getKey    = function() return HT.CfgGet("soundKeyUse") end,
                        getEnable = function() return HT.CfgGet("soundOnUse") end,
                        onSelect  = function(key, path)
                            HT.CfgSet("soundKeyUse", key)
                            HT.CfgSet("soundPathUse", path)
                        end,
                        onToggle  = function(val) HT.CfgSet("soundOnUse", val) end,
                        onTest    = function() HT.PlaySound("soundUse") end,
                    },

                    -- ── Sound when ready ──────────────────────────────────────────────────
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound when ready"],
                        getKey    = function() return HT.CfgGet("soundKeyReady") end,
                        getEnable = function() return HT.CfgGet("soundOnReady") end,
                        onSelect  = function(key, path)
                            HT.CfgSet("soundKeyReady", key)
                            HT.CfgSet("soundPathReady", path)
                        end,
                        onToggle  = function(val) HT.CfgSet("soundOnReady", val) end,
                        onTest    = function() HT.PlaySound("soundReady") end,
                    },
                }
            end,
        },

        -- ════════════ Icon ════════════
        -- Singleton config but a pool of up to 8 frames. The Override cadre binds to the PRIMARY frame
        -- ("HealthstoneTrackerFrame1"); the lazy seed makes every pooled frame start identical, so they stay
        -- uniform unless you edit the cadre while several distinct healthstone variants are in bags at once (rare).
        ns.CDMGroups.TrackerIconGroup({
            get = HT.CfgGet, set = HT.CfgSet,
            frameName = "HealthstoneTrackerFrame1", defaultDest = "belowPlayer", LSM = LSM,
            enabledBy = function() return HT.CfgGet("enabled") ~= false end,
            rebuild = rebuildMenu, applyIcon = applyIcon,
            onShowIcon = function() HT.ApplyAll() end,
            showIconInline = { { type = "checkbox", label = L["Show at 0 stacks"],
                get = function() return HT.CfgGet("showAtZero") == true end,
                set = function(val) HT.CfgSet("showAtZero", val); HT.ApplyAll() end,
                point = { "LEFT", "LEFT", 150, 0 } } },
            afterInclude = function() local t = HT.GetTracker(); if t and t.ApplySize then t.ApplySize() end HT.ApplyPosition(); HT.ApplyAll(); rebuildMenu() end,
            sizeApply = function() local t = HT.GetTracker(); if t and t.ApplySize then t.ApplySize() end HT.ApplyAll() end,
            seedValues = function() return HT.OverrideSeed() end,
            pos = {
                getX = function() return HT.CfgGet("posX") end,
                getY = function() return HT.CfgGet("posY") end,
                onApply = function(x, yv) if x then HT.CfgSet("posX", x) end if yv then HT.CfgSet("posY", yv) end HT.ApplyAll() end,
                onUnlock = function() HT.SetUnlocked(true) end,
                onLock = function() HT.SetUnlocked(false); if HT.pe then HT.pe.Refresh() end end,
                isUnlocked = function() return HT.IsUnlocked() end,
                onBuilt = function(w) HT.pe = w end,
            },
        }),
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })

    -- The Override / Free settings sections start collapsed and re-collapse on each tab show.
    parent:HookScript("OnHide", function()
        HT.CfgSet("ovCollapsed", true); HT.CfgSet("freeCollapsed", true)
    end)
    parent:HookScript("OnShow", function() if menu then menu.Rebuild() end end)
    return menu
end

-- ── Registration ──────────────────────────────────────────────────────────────

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Healthstone Tracker"], nil, CreateHealthstoneTrackerPanel)
end)
