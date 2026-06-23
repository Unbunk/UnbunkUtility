-- Modules/HealerRange/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

local function CreateHealerRangePanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so the enable set closure can reach menu.Refresh()

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Healer Range"] },

        -- ════════════ General: enable + probe status + test + where active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (probe status, test
            -- button, duration, instance filter) except the enable checkbox itself,
            -- which stays live to re-enable.
            gate  = { enabled = function() return HR.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable Healer Range"],
                        height = 24,
                        get    = function() return HR.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            HR.CfgSet("enabled", val)
                            -- Drive the start/stop transition live: re-enabling restarts the range
                            -- OnUpdate (if in combat+group); disabling stops it now.
                            if HR.RefreshChecking then HR.RefreshChecking() end
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- ── Probe status (FontString with custom Refresh) ─────────────────────
                    {
                        type   = "custom",
                        height = 30,
                        build  = function(host)
                            -- H6: small descriptive text. The green/red colour comes from the
                            -- inline |cff..|r codes in the message, which override H6's white default.
                            local probeMsg = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                            probeMsg:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            probeMsg:SetWidth(500)
                            probeMsg:SetJustifyH("LEFT")
                            probeMsg:SetWordWrap(true)

                            local function RefreshProbeStatus()
                                if not HR.HasCombatProbe() then
                                    probeMsg:SetText(L["|cffff4444Combat range detection unavailable — your class has no friendly spell probe usable in combat. The alert will not trigger.|r"])
                                else
                                    probeMsg:SetText(L["|cff00ff00Combat range detection available. Note: Evoker healers are ignored unless other healers are present in the group.|r"])
                                end
                            end
                            RefreshProbeStatus()   -- set the text now; don't wait for the first menu.Refresh()

                            return {
                                frame   = host,
                                height  = 30,
                                Refresh = RefreshProbeStatus,
                            }
                        end,
                    },

                    -- ── Test Alert button + test duration input ───────────────────────────
                    {
                        type   = "custom",
                        height = 30,
                        build  = function(host)
                            local testAlertBtn = ns.ui.CreateButton({
                                parent  = host,
                                label   = L["Test Alert"],
                                width   = 100,
                                height  = 22,
                                onClick = function()
                                    -- Cancel any in-flight test so a second click doesn't let the first
                                    -- timer fire mid-test (which would SetTesting(false)/hide early).
                                    if HR.testTimer then HR.testTimer:Cancel() end
                                    HR.SetTesting(true)
                                    HR.GetFrame():Show()
                                    HR.PlaySound()
                                    local duration = HR.CfgGet("alertDuration") or 5
                                    HR.testTimer = C_Timer.NewTimer(duration, function()
                                        HR.testTimer = nil
                                        HR.SetTesting(false)
                                        if not HR.IsUnlocked() then
                                            HR.GetFrame():Hide()
                                        end
                                    end)
                                end,
                            })
                            testAlertBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -4)

                            local durLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            durLbl:SetPoint("LEFT", testAlertBtn.frame, "RIGHT", 16, 0)
                            durLbl:SetText(L["Duration"])

                            local durMinusBtn = ns.ui.CreateButton({
                                parent  = host,
                                label   = "-",
                                width   = 22,
                                height  = 22,
                            })
                            durMinusBtn.frame:SetPoint("LEFT", durLbl, "RIGHT", 6, 0)

                            -- Forward-declared so the onEnter closure below can reflect the clamped
                            -- value back into the edit box (assigned just after durInput is created).
                            local durBox

                            local durInput = ns.ui.CreateTextInput({
                                parent     = host,
                                width      = 40,
                                height     = 22,
                                numeric    = true,
                                maxLetters = 3,
                                text       = tostring(HR.CfgGet("alertDuration") or 5),
                                onEnter    = function(val)
                                    -- Clamp typed input to the same [1,60] range the +/- buttons enforce.
                                    if val and val > 0 then
                                        val = math.min(60, math.max(1, val))
                                        HR.CfgSet("alertDuration", val)
                                        if durBox then durBox:SetText(tostring(val)) end
                                    end
                                end,
                            })
                            durInput.frame:SetPoint("LEFT", durMinusBtn.frame, "RIGHT", 4, 0)
                            durBox = durInput.editBox

                            local durPlusBtn = ns.ui.CreateButton({
                                parent  = host,
                                label   = "+",
                                width   = 22,
                                height  = 22,
                            })
                            durPlusBtn.frame:SetPoint("LEFT", durBox, "RIGHT", 4, 0)

                            durMinusBtn.frame:SetScript("OnClick", function()
                                local v = tonumber(durBox:GetText()) or HR.CfgGet("alertDuration") or 5
                                v = math.max(1, v - 1)
                                durBox:SetText(tostring(v))
                                HR.CfgSet("alertDuration", v)
                            end)
                            durPlusBtn.frame:SetScript("OnClick", function()
                                local v = tonumber(durBox:GetText()) or HR.CfgGet("alertDuration") or 5
                                v = math.min(60, v + 1)
                                durBox:SetText(tostring(v))
                                HR.CfgSet("alertDuration", v)
                            end)

                            local durSecLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                            durSecLbl:SetPoint("LEFT", durPlusBtn.frame, "RIGHT", 6, 0)
                            durSecLbl:SetText(L["sec"])

                            return {
                                frame   = host,
                                height  = 30,
                                Refresh = function()
                                    durBox:SetText(tostring(HR.CfgGet("alertDuration") or 5))
                                end,
                            }
                        end,
                    },

                    -- ── Instance filter ───────────────────────────────────────────────────
                    {
                        type      = "instanceFilter",
                        getConfig = function() return HR.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local filter = HR.CfgGet("instanceFilter")
                            filter[key] = val
                            HR.CfgSet("instanceFilter", filter)
                        end,
                    },
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            enabledBy = function() return HR.CfgGet("enabled") ~= false end,
            build = function()
                return {
                    -- ── Sound picker ──────────────────────────────────────────────────────
                    -- The original called ns.ui.CreateSoundPicker(content, LSM) with no config,
                    -- relying on the HealerRange-specific defaults baked into that constructor
                    -- (soundKey/enableSound get/set, HR.PlaySound, L["Alert sound"] label). We
                    -- pass only the label and let those same defaults apply -> identical panel.
                    {
                        type  = "sound",
                        LSM   = LSM,
                        label = L["Alert sound"],
                    },
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            enabledBy = function() return HR.CfgGet("enabled") ~= false end,
            build = function()
                return {
                    -- ── Icon picker ───────────────────────────────────────────────────────
                    {
                        type      = "iconPicker",
                        getConfig = function() return HR.CfgGet("icon") end,
                        setConfig = function(key, val)
                            local cfg = HR.CfgGet("icon")
                            cfg[key] = val
                            HR.CfgSet("icon", cfg)
                            HR.ApplyIcon()
                        end,
                        icons = UNBUNK_ICONS or {},
                    },

                    -- ── Alert text (sub-box) ──────────────────────────────────────────────
                    {
                        type  = "group",
                        title = L["Alert text"],
                        build = function()
                            return {
                                {
                                    type            = "textEditor",
                                    LSM             = LSM,
                                    label           = L["Alert text"],
                                    showLabel       = false,
                                    getText         = function() return HR.CfgGet("alertMessage") end,
                                    getFontKey      = function() return HR.CfgGet("fontKey") end,
                                    getFontPath     = function() return HR.CfgGet("fontPath") end,
                                    getFontSize     = function() return HR.CfgGet("fontSize") end,
                                    getColor        = function() return HR.CfgGet("color") end,
                                    getOutline      = function() return HR.CfgGet("outline") end,
                                    onTextChange    = function(txt)
                                        HR.CfgSet("alertMessage", txt)
                                        if HR.ApplyMessage then HR.ApplyMessage() end
                                    end,
                                    onFontChange    = function(key, path)
                                        HR.CfgSet("fontKey", key)
                                        HR.CfgSet("fontPath", path)
                                        if HR.ApplyFont then HR.ApplyFont() end
                                    end,
                                    onSizeChange    = function(size)
                                        HR.CfgSet("fontSize", size)
                                        if HR.ApplyFont then HR.ApplyFont() end
                                    end,
                                    onColorChange   = function(r, g, b, a)
                                        HR.CfgSet("color", { r=r, g=g, b=b, a=a })
                                        if HR.ApplyColor then HR.ApplyColor() end
                                    end,
                                    onOutlineChange = function(outline)
                                        HR.CfgSet("outline", outline)
                                        if HR.ApplyFont then HR.ApplyFont() end
                                    end,
                                },
                            }
                        end,
                    },

                    -- ── Alert position (sub-box) ──────────────────────────────────────────
                    {
                        type  = "group",
                        title = L["Alert position"],
                        build = function()
                            return {
                                -- ── Position editor (named ref captured into HR.pe for drag callbacks) ─
                                {
                                    type        = "position",
                                    ref         = "pe",
                                    onBuilt     = function(w) HR.pe = w end,
                                    label       = "",   -- the "Alert position" group title already names it

                                    getX        = function() return HR.CfgGet("posX") end,
                                    getY        = function() return HR.CfgGet("posY") end,
                                    onApply     = function(x, yv)
                                        if x  then HR.CfgSet("posX", x)  end
                                        if yv then HR.CfgSet("posY", yv) end
                                        if HR.ApplyPosition then HR.ApplyPosition() end
                                    end,
                                    onUnlock    = function()
                                        if HR.SetUnlocked then HR.SetUnlocked(true) end
                                        ns.Print(L["Alert unlocked — drag to reposition, then click Lock to save."])
                                    end,
                                    onLock      = function()
                                        if HR.SetUnlocked then HR.SetUnlocked(false) end
                                    end,
                                    isUnlocked  = function()
                                        return HR.IsUnlocked and HR.IsUnlocked() or false
                                    end,
                                },
                            }
                        end,
                    },
                }
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> the per-entry Refresh closures (enable
    -- checkbox, probe status, duration box, instance filter, icon picker, sound,
    -- text editor, position) are collected and re-run on OnShow automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    return menu
end

-- ── Registration ──────────────────────────────────────────────────────────────
local initHR = CreateFrame("Frame")
initHR:RegisterEvent("ADDON_LOADED")
initHR:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end

    local blizzPanel = CreateFrame("Frame")
    blizzPanel.name = "UnbunkUtility"
    local blizzTitle = blizzPanel:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH2")
    blizzTitle:SetPoint("TOPLEFT", 16, -16)
    blizzTitle:SetText("UnbunkUtility")
    local openBtn = CreateFrame("Button", nil, blizzPanel, "UIPanelButtonTemplate")
    openBtn:SetSize(160, 22)
    openBtn:SetPoint("TOPLEFT", 16, -80)
    openBtn:SetText(L["Open UnbunkUtility"])
    openBtn:SetScript("OnClick", function()
        UnbunkUtility.OpenWindow()
        HideUIPanel(SettingsPanel)
    end)
    local cat = Settings.RegisterCanvasLayoutCategory(blizzPanel, blizzPanel.name)
    Settings.RegisterAddOnCategory(cat)

    UnbunkUtility.RegisterModule(L["Healer Range"], nil, CreateHealerRangePanel)

    self:UnregisterEvent("ADDON_LOADED")
end)
