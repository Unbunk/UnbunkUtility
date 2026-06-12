-- Modules/DeathAlert/UI/ConfigWindow.lua
-- One sub-tab per role (Tank / Healer / DPS) under the Combat Utilities > Death
-- Alert category. Each panel: General (enable + test + instance filter + duration),
-- Sound, and Display (icon / alert text / alert position). The per-role enable
-- checkbox is the master of its panel (greys the rest when off).

local _, ns = ...
local L = ns.L
ns.DeathAlert = ns.DeathAlert or {}
local DA = ns.DeathAlert
DA.menus = DA.menus or {}

local function H2(text) return { type = "label", font = "UnbunkUtilityH2", height = 26, text = text } end

local function BuildRoleOptions(prefix)
    local enabledFn = function() return DA.CfgGet(prefix .. "Enabled") end

    return {
        -- ════════════ General: enable + test + instance filter + duration ════════════
        {
            type  = "group",
            title = L["General"],
            gate  = { enabled = enabledFn, master = "enable" },
            build = function()
                local general = {
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable"],
                        height = 24,
                        get    = enabledFn,
                        set    = function(val)
                            DA.CfgSet(prefix .. "Enabled", val)
                            if DA.menus[prefix] then DA.menus[prefix].Refresh() end
                        end,
                    },

                    -- Test button
                    {
                        type       = "button",
                        label      = L["Test Alert"],
                        width      = 100,
                        height     = 22,
                        hostHeight = 26,
                        btnOffsetY = -2,
                        onClick    = function()
                            local getFrame = prefix == "tank" and DA.GetTankFrame or
                                         prefix == "healer" and DA.GetHealerFrame or
                                         DA.GetDpsFrame
                            local setTest  = prefix == "tank" and DA.SetTankTesting or
                                         prefix == "healer" and DA.SetHealerTesting or
                                         DA.SetDpsTesting
                            setTest(true)
                            getFrame():Show()
                            DA.PlaySound(prefix)
                            local duration = DA.CfgGet(prefix .. "AlertDuration")
                            C_Timer.After(duration, function()
                                setTest(false)
                                getFrame():Hide()
                            end)
                        end,
                    },

                    -- Instance filter
                    {
                        type      = "instanceFilter",
                        getConfig = function() return DA.CfgGet(prefix .. "InstanceFilter") end,
                        setConfig = function(key, val)
                            local filter = DA.CfgGet(prefix .. "InstanceFilter")
                            filter[key] = val
                            DA.CfgSet(prefix .. "InstanceFilter", filter)
                        end,
                    },

                    -- Duration editor
                    {
                        type = "duration",
                        get  = function() return DA.CfgGet(prefix .. "AlertDuration") end,
                        set  = function(val) DA.CfgSet(prefix .. "AlertDuration", val) end,
                    },
                }

                -- Unassigned-role option (DPS only).
                if prefix == "dps" then
                    table.insert(general, {
                        type   = "checkbox",
                        label  = L["Also alert deaths with no assigned role (treat as DPS)"],
                        height = 24,
                        get    = function() return DA.CfgGet("dpsAlertUnassigned") == true end,
                        set    = function(val) DA.CfgSet("dpsAlertUnassigned", val) end,
                    })
                end

                return general
            end,
        },

        -- ════════════ Sound ════════════
        {
            type      = "group",
            title     = L["Sound"],
            enabledBy = enabledFn,
            build = function()
                return {
                    {
                        type      = "sound",
                        getKey    = function() return DA.CfgGet(prefix .. "SoundKey") end,
                        getEnable = function() return DA.CfgGet(prefix .. "EnableSound") end,
                        onSelect  = function(key, path)
                            DA.CfgSet(prefix .. "SoundKey", key)
                            DA.CfgSet(prefix .. "SoundPath", path)
                        end,
                        onToggle  = function(val) DA.CfgSet(prefix .. "EnableSound", val) end,
                        onTest    = function() DA.PlaySound(prefix) end,
                    },
                }
            end,
        },

        -- ════════════ Display: icon, alert text, alert position ════════════
        {
            type      = "group",
            title     = L["Display"],
            enabledBy = enabledFn,
            build = function()
                return {
                    {
                        type  = "group",
                        title = L["Icon"],
                        build = function()
                            return {
                                {
                                    type      = "iconPicker",
                                    enabledBy = enabledFn,
                                    getConfig = function() return DA.CfgGet(prefix .. "Icon") end,
                                    setConfig = function(key, val)
                                        local cfg = DA.CfgGet(prefix .. "Icon")
                                        cfg[key] = val
                                        DA.CfgSet(prefix .. "Icon", cfg)
                                        if prefix == "tank" then DA.ApplyTankIcon()
                                        elseif prefix == "healer" then DA.ApplyHealerIcon()
                                        else DA.ApplyDpsIcon() end
                                    end,
                                    icons = UNBUNK_ICONS or {},
                                },
                            }
                        end,
                    },

                    {
                        type  = "group",
                        title = L["Alert text"],
                        build = function()
                            return {
                                {
                                    type            = "textEditor",
                                    label           = "",
                                    getText         = function() return DA.CfgGet(prefix .. "Message") end,
                                    getFontKey      = function() return DA.CfgGet(prefix .. "FontKey") end,
                                    getFontPath     = function() return DA.CfgGet(prefix .. "FontPath") end,
                                    getFontSize     = function() return DA.CfgGet(prefix .. "FontSize") end,
                                    getColor        = function() return DA.CfgGet(prefix .. "Color") end,
                                    getOutline      = function() return DA.CfgGet(prefix .. "Outline") end,
                                    onTextChange    = function(txt)
                                        DA.CfgSet(prefix .. "Message", txt)
                                        if prefix == "tank" then DA.ApplyTankMessage()
                                        elseif prefix == "healer" then DA.ApplyHealerMessage()
                                        else DA.ApplyDpsMessage() end
                                    end,
                                    onFontChange    = function(key, path)
                                        DA.CfgSet(prefix .. "FontKey", key)
                                        DA.CfgSet(prefix .. "FontPath", path)
                                        if prefix == "tank" then DA.ApplyTankFont()
                                        elseif prefix == "healer" then DA.ApplyHealerFont()
                                        else DA.ApplyDpsFont() end
                                    end,
                                    onSizeChange    = function(size)
                                        DA.CfgSet(prefix .. "FontSize", size)
                                        if prefix == "tank" then DA.ApplyTankFont()
                                        elseif prefix == "healer" then DA.ApplyHealerFont()
                                        else DA.ApplyDpsFont() end
                                    end,
                                    onColorChange   = function(r, g, b, a)
                                        DA.CfgSet(prefix .. "Color", { r=r, g=g, b=b, a=a })
                                        if prefix == "tank" then DA.ApplyTankColor()
                                        elseif prefix == "healer" then DA.ApplyHealerColor()
                                        else DA.ApplyDpsColor() end
                                    end,
                                    onOutlineChange = function(outline)
                                        DA.CfgSet(prefix .. "Outline", outline)
                                        if prefix == "tank" then DA.ApplyTankFont()
                                        elseif prefix == "healer" then DA.ApplyHealerFont()
                                        else DA.ApplyDpsFont() end
                                    end,
                                },
                            }
                        end,
                    },

                    {
                        type  = "group",
                        title = L["Alert position"],
                        build = function()
                            return {
                                {
                                    type       = "position",
                                    label      = "",
                                    onBuilt    = function(w) _G["DeathAlert_PE_" .. prefix] = w end,
                                    getX       = function() return DA.CfgGet(prefix .. "PosX") end,
                                    getY       = function() return DA.CfgGet(prefix .. "PosY") end,
                                    onApply    = function(x, yv)
                                        if x  then DA.CfgSet(prefix .. "PosX", x)  end
                                        if yv then DA.CfgSet(prefix .. "PosY", yv) end
                                        if prefix == "tank" then DA.ApplyTankPosition()
                                        elseif prefix == "healer" then DA.ApplyHealerPosition()
                                        else DA.ApplyDpsPosition() end
                                    end,
                                    onUnlock   = function()
                                        if prefix == "tank" then DA.SetTankUnlocked(true)
                                        elseif prefix == "healer" then DA.SetHealerUnlocked(true)
                                        else DA.SetDpsUnlocked(true) end
                                    end,
                                    onLock     = function()
                                        if prefix == "tank" then DA.SetTankUnlocked(false)
                                        elseif prefix == "healer" then DA.SetHealerUnlocked(false)
                                        else DA.SetDpsUnlocked(false) end
                                    end,
                                    isUnlocked = function()
                                        if prefix == "tank" then return DA.IsTankUnlocked()
                                        elseif prefix == "healer" then return DA.IsHealerUnlocked()
                                        else return DA.IsDpsUnlocked() end
                                    end,
                                },
                            }
                        end,
                    },
                }
            end,
        },
    }
end

local function MakeRolePanel(prefix, titleText)
    return function(parent)
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local options = { H2(titleText) }
        for _, o in ipairs(BuildRoleOptions(prefix)) do
            table.insert(options, o)
        end
        DA.menus[prefix] = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
        return DA.menus[prefix]
    end
end

-- ── Registration (three role sub-tabs) ─────────────────────────────────────────
local initDA = CreateFrame("Frame")
initDA:RegisterEvent("ADDON_LOADED")
initDA:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Tank Death Alert"],   nil, MakeRolePanel("tank",   L["Tank Death Alert"]))
    UnbunkUtility.RegisterModule(L["Healer Death Alert"], nil, MakeRolePanel("healer", L["Healer Death Alert"]))
    UnbunkUtility.RegisterModule(L["DPS Death Alert"],    nil, MakeRolePanel("dps",    L["DPS Death Alert"]))
    self:UnregisterEvent("ADDON_LOADED")
end)
