-- Modules/HealthstoneTracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.HealthstoneTracker = ns.HealthstoneTracker or {}
local HT = ns.HealthstoneTracker

local function CreateHealthstoneTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

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
        {
            type  = "group",
            title = L["Icon"],
            enabledBy = function() return HT.CfgGet("enabled") ~= false end,
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text / stack text) since there is no icon to configure; the checkbox stays live.
            gate      = { enabled = function() return HT.CfgGet("showIcon") ~= false end, master = "showicon" },
            build = function()
                -- Singleton config but a pool of up to 8 frames. The Override cadre binds to the PRIMARY
                -- frame; the lazy seed makes every pooled frame start identical, so they stay uniform unless
                -- you edit the cadre while several distinct healthstone variants are in bags at once (rare).
                local frameName = "HealthstoneTrackerFrame1"
                local function inCdm() return ns.CDMIncludedVal(HT.CfgGet("includeInCdm")) end
                local function curDest() return HT.CfgGet("cdmDest") or "belowPlayer" end
                local function rebuildMenu() if menu then menu.Rebuild() end end
                local function applyIcon()
                    HT.ApplyAll()
                    if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                end

                local e = {
                    { type = "checkbox", ref = "showicon", label = L["Show icon"],
                      get = function() return HT.CfgGet("showIcon") ~= false end,
                      set = function(val) HT.CfgSet("showIcon", val); HT.ApplyAll() end,
                      inline = { { type = "checkbox", label = L["Show at 0 stacks"],
                          get = function() return HT.CfgGet("showAtZero") == true end,
                          set = function(val) HT.CfgSet("showAtZero", val); HT.ApplyAll() end,
                          point = { "LEFT", "LEFT", 150, 0 } } } },

                    { type = "group", title = L["Placement"], build = function() return {
                        { type = "checkbox", label = L["Include in cdm"],
                          disabled = function() return not ns.IsCDMEnabled() end,
                          get = function() return inCdm() end,
                          set = function(v) HT.CfgSet("includeInCdm", v); local t = HT.GetTracker(); if t and t.ApplySize then t.ApplySize() end HT.ApplyPosition(); HT.ApplyAll(); rebuildMenu() end },
                        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                          when = function() return inCdm() end,
                          getList = function() return ns.CDMDestList() end,
                          getCurrentKey = function() return ns.CDMDestChoiceLabel(HT.CfgGet) end,
                          onSelect = function(label) ns.CDMApplyDestChoice(label, HT.CfgSet); local t = HT.GetTracker(); if t and t.ApplySize then t.ApplySize() end HT.ApplyPosition(); HT.ApplyAll(); rebuildMenu() end },
                    } end },
                }

                local cfg = {
                    frameName  = frameName,
                    getDest    = curDest,
                    cdmAtEnd   = function() return HT.CfgGet("cdmAtEnd") end,
                    inCdm      = inCdm,
                    applyIcon  = applyIcon,
                    rebuild    = rebuildMenu,
                    getOv      = function() return HT.CfgGet("ovCollapsed") ~= false end,
                    setOv      = function(c) HT.CfgSet("ovCollapsed", c) end,
                    getFree    = function() return HT.CfgGet("freeCollapsed") ~= false end,
                    setFree    = function(c) HT.CfgSet("freeCollapsed", c) end,
                    seedValues = function() return HT.OverrideSeed() end,
                    freeBuild  = function()
                        return ns.CDMGroups.TrackerFreeCadres({
                            get       = HT.CfgGet,
                            set       = HT.CfgSet,
                            touch     = applyIcon,
                            rebuild   = rebuildMenu,
                            sizeApply = function() local t = HT.GetTracker(); if t and t.ApplySize then t.ApplySize() end HT.ApplyAll() end,
                            LSM       = LSM,
                            pos = {
                                getX = function() return HT.CfgGet("posX") end,
                                getY = function() return HT.CfgGet("posY") end,
                                onApply = function(x, yv) if x then HT.CfgSet("posX", x) end if yv then HT.CfgSet("posY", yv) end HT.ApplyAll() end,
                                onUnlock = function() HT.SetUnlocked(true) end,
                                onLock = function() HT.SetUnlocked(false); if HT.pe then HT.pe.Refresh() end end,
                                isUnlocked = function() return HT.IsUnlocked() end,
                                onBuilt = function(w) HT.pe = w end,
                            },
                        })
                    end,
                }
                for _, x in ipairs(ns.CDMGroups.TrackerCdmCadres(cfg)) do e[#e + 1] = x end
                return e
            end,
        },
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

local initHTUI = CreateFrame("Frame")
initHTUI:RegisterEvent("ADDON_LOADED")
initHTUI:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Healthstone Tracker"], nil, CreateHealthstoneTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
