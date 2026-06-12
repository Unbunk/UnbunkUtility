-- Modules/PlayerDeathAnimation/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.PlayerDeath = ns.PlayerDeath or {}
local PD = ns.PlayerDeath

local function CreatePlayerDeathPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach the menu if needed

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Death Anim"] },

        -- ════════════ General: enable + Test ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (the Test button, etc.)
            -- except the enable checkbox itself, which stays live to re-enable.
            gate  = { enabled = function() return PD.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable Player Death Animation"],
                        height = 24,
                        get    = function() return PD.CfgGet("enabled") ~= false end,
                        set    = function(val) PD.CfgSet("enabled", val); if menu then menu.Refresh() end end,
                    },

                    -- ── Test button ───────────────────────────────────────────────────────
                    {
                        type       = "button",
                        label      = L["Test"],
                        width      = 80,
                        height     = 22,
                        hostHeight = 26,
                        btnOffsetY = -2,
                        onClick    = function()
                            -- Gate the whole test on the master enable flag so a disabled
                            -- module is fully silent (mirrors the PLAYER_DEAD handler).
                            if not PD.CfgGet("enabled") then return end
                            if PD.CfgGet("soundEnabled") then
                                PD.PlaySound()
                            end
                            PD.Play()
                        end,
                    },
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type      = "group",
            title     = L["Sound"],
            enabledBy = function() return PD.CfgGet("enabled") ~= false end,
            build = function()
                return {
                    -- ── Sound ─────────────────────────────────────────────────────────────
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound on death"],
                        getKey    = function() return PD.CfgGet("soundKey") end,
                        getEnable = function() return PD.CfgGet("soundEnabled") end,
                        onSelect  = function(key, path)
                            PD.CfgSet("soundKey", key)
                            PD.CfgSet("soundPath", path)
                        end,
                        onToggle  = function(val) PD.CfgSet("soundEnabled", val) end,
                        onTest    = function() PD.PlaySound() end,
                    },
                }
            end,
        },

        -- ════════════ Animation ════════════
        {
            type      = "group",
            title     = L["Animation"],
            enabledBy = function() return PD.CfgGet("enabled") ~= false end,
            build = function()
                return {
                    -- ── Animation checkbox ────────────────────────────────────────────────
                    {
                        type   = "checkbox",
                        label  = L["Show animation on death"],
                        height = 24,
                        get    = function() return PD.CfgGet("animEnabled") ~= false end,
                        set    = function(val) PD.CfgSet("animEnabled", val) end,
                    },

                    -- ── Animation picker ──────────────────────────────────────────────────
                    -- Custom: the original draws a GameFontNormal "Animation" title at y=0
                    -- and anchors the dropdown to an empty FontString at y=-20 (so the
                    -- toggle sits lower than BuildMenu's built-in dropdown label layout).
                    -- Preserve that exact geometry here.
                    {
                        type   = "custom",
                        height = 50,
                        build  = function(host)
                            local animPickerLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                            animPickerLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            animPickerLbl:SetText(L["Animation"])

                            local animAnchor = host:CreateFontString(nil, "ARTWORK")
                            animAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)

                            local animDD = ns.ui.CreateDropdown({
                                parent        = host,
                                anchorFrame   = animAnchor,
                                width         = 200,
                                itemHeight    = 20,
                                visibleItems  = 6,
                                getList       = function()
                                    local list = {}
                                    if UNBUNK_ANIMATIONS then
                                        for _, anim in ipairs(UNBUNK_ANIMATIONS) do
                                            table.insert(list, anim.label)
                                        end
                                    end
                                    return list
                                end,
                                getCurrentKey = function()
                                    local idx = PD.CfgGet("animIndex") or 1
                                    -- Fall back to index 1 for an out-of-range saved value (e.g. an
                                    -- imported profile), matching GetCurrentAnim's runtime fallback so
                                    -- the toggle label and the played animation agree.
                                    if not (UNBUNK_ANIMATIONS and UNBUNK_ANIMATIONS[idx]) then idx = 1 end
                                    return (UNBUNK_ANIMATIONS and UNBUNK_ANIMATIONS[idx] and UNBUNK_ANIMATIONS[idx].label) or ""
                                end,
                                onSelect      = function(label)
                                    if UNBUNK_ANIMATIONS then
                                        for i, anim in ipairs(UNBUNK_ANIMATIONS) do
                                            if anim.label == label then
                                                PD.CfgSet("animIndex", i)
                                                break
                                            end
                                        end
                                    end
                                end,
                            })

                            return {
                                frame   = host,
                                height  = 50,
                                Refresh = function()
                                    local idx = PD.CfgGet("animIndex") or 1
                                    if not (UNBUNK_ANIMATIONS and UNBUNK_ANIMATIONS[idx]) then
                                        idx = 1
                                        PD.CfgSet("animIndex", 1)  -- heal a stale out-of-range index
                                    end
                                    if UNBUNK_ANIMATIONS and UNBUNK_ANIMATIONS[idx] then
                                        animDD.selectedText:SetText(UNBUNK_ANIMATIONS[idx].label)
                                    end
                                end,
                            }
                        end,
                    },

                    -- ── FPS ───────────────────────────────────────────────────────────────
                    -- Custom: composite of label + minus button + numeric input + plus
                    -- button + "fps" suffix, with the +/- steppers writing animFPS.
                    {
                        type   = "custom",
                        height = 46,
                        build  = function(host)
                            local fpsLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                            fpsLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            fpsLbl:SetText(L["Frames per second"])

                            local fpsMinusBtn = ns.ui.CreateButton({
                                parent = host,
                                label  = "-",
                                width  = 22,
                                height = 22,
                            })
                            fpsMinusBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)

                            local fpsInput = ns.ui.CreateTextInput({
                                parent     = host,
                                width      = 46,
                                height     = 22,
                                numeric    = true,
                                min        = 1,
                                max        = 60,
                                maxLetters = 2,
                                text       = tostring(PD.CfgGet("animFPS") or 16),
                                onEnter    = function(val)
                                    if val and val > 0 then
                                        PD.CfgSet("animFPS", val)
                                    end
                                end,
                            })
                            fpsInput.frame:SetPoint("LEFT", fpsMinusBtn.frame, "RIGHT", 4, 0)

                            local fpsPlusBtn = ns.ui.CreateButton({
                                parent = host,
                                label  = "+",
                                width  = 22,
                                height = 22,
                            })
                            fpsPlusBtn.frame:SetPoint("LEFT", fpsInput.frame, "RIGHT", 4, 0)

                            local fpsSecLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                            fpsSecLbl:SetPoint("LEFT", fpsPlusBtn.frame, "RIGHT", 6, 0)
                            fpsSecLbl:SetText(L["fps"])

                            fpsMinusBtn.frame:SetScript("OnClick", function()
                                -- Fall back to the SAVED value (not a hardcoded 16) if the box
                                -- holds rejected/stale text, so the step is always relative.
                                local v = tonumber(fpsInput.GetText()) or PD.CfgGet("animFPS") or 16
                                v = math.max(1, v - 1)
                                fpsInput.SetText(tostring(v))
                                PD.CfgSet("animFPS", v)
                            end)

                            fpsPlusBtn.frame:SetScript("OnClick", function()
                                local v = tonumber(fpsInput.GetText()) or PD.CfgGet("animFPS") or 16
                                v = math.min(60, v + 1)
                                fpsInput.SetText(tostring(v))
                                PD.CfgSet("animFPS", v)
                            end)

                            return {
                                frame   = host,
                                height  = 46,
                                Refresh = function()
                                    fpsInput.SetText(tostring(PD.CfgGet("animFPS") or 16))
                                end,
                            }
                        end,
                    },

                    -- ── Duration editor ───────────────────────────────────────────────────
                    -- The shared DurationEditor hardcodes "Alert duration"; this module
                    -- drives the on-screen animation duration. Relabel the widget's
                    -- internal section header (done in onBuilt) to avoid the misleading
                    -- "Alert duration" text.
                    {
                        type    = "duration",
                        get     = function() return PD.CfgGet("animDuration") end,
                        set     = function(val) PD.CfgSet("animDuration", val) end,
                        onBuilt = function(w)
                            for i = 1, select("#", w.frame:GetRegions()) do
                                local region = select(i, w.frame:GetRegions())
                                if region and region.GetObjectType and region:GetObjectType() == "FontString"
                                    and region:GetText() == L["Alert duration"] then
                                    region:SetText(L["Animation duration"])
                                    break
                                end
                            end
                        end,
                    },

                    -- ── Loop checkbox ─────────────────────────────────────────────────────
                    {
                        type   = "checkbox",
                        label  = L["Loop animation until duration ends"],
                        height = 24,
                        get    = function() return PD.CfgGet("animLoop") or false end,
                        set    = function(val) PD.CfgSet("animLoop", val) end,
                    },

                    -- ── Animation size  W / H  (composite -> custom escape hatch) ─────────
                    {
                        type   = "custom",
                        height = 46,
                        build  = function(host)
                            local sizeLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                            sizeLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                            sizeLbl:SetText(L["Animation size"])

                            local wLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                            wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)
                            wLbl:SetText(L["W"])

                            local wInput = ns.ui.CreateTextInput({
                                parent     = host,
                                width      = 60,
                                height     = 22,
                                numeric    = true,
                                min        = 16,
                                max        = 1024,
                                maxLetters = 4,
                                text       = tostring(PD.CfgGet("animWidth") or 250),
                                onEnter    = function(val)
                                    if val and val > 0 then
                                        PD.CfgSet("animWidth", val)
                                        PD.ApplySize()
                                    end
                                end,
                            })
                            wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

                            local hLbl = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                            hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
                            hLbl:SetText(L["H"])

                            local hInput = ns.ui.CreateTextInput({
                                parent     = host,
                                width      = 60,
                                height     = 22,
                                numeric    = true,
                                min        = 16,
                                max        = 1024,
                                maxLetters = 4,
                                text       = tostring(PD.CfgGet("animHeight") or 100),
                                onEnter    = function(val)
                                    if val and val > 0 then
                                        PD.CfgSet("animHeight", val)
                                        PD.ApplySize()
                                    end
                                end,
                            })
                            hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

                            return {
                                frame   = host,
                                height  = 46,
                                Refresh = function()
                                    wInput.SetText(tostring(PD.CfgGet("animWidth")  or 250))
                                    hInput.SetText(tostring(PD.CfgGet("animHeight") or 100))
                                end,
                            }
                        end,
                    },

                    -- ── Position editor (named ref for the onLock self-refresh) ───────────
                    {
                        type       = "position",
                        ref        = "pe",
                        onBuilt    = function(w) PD.pe = w end,
                        label      = L["Animation position (offset from screen center)"],
                        getX       = function() return PD.CfgGet("posX") end,
                        getY       = function() return PD.CfgGet("posY") end,
                        onApply    = function(x, yv)
                            if x  then PD.CfgSet("posX", x)  end
                            if yv then PD.CfgSet("posY", yv) end
                            PD.ApplyPosition()
                        end,
                        onUnlock   = function() PD.SetUnlocked(true) end,
                        onLock     = function()
                            PD.SetUnlocked(false)
                            if PD.pe then PD.pe.Refresh() end
                        end,
                        isUnlocked = function() return PD.IsUnlocked() end,
                    },
                }
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    -- NOTE: no parent:HookScript("OnShow", ...) here anymore — BuildMenu did it.
    return menu
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initPDA = CreateFrame("Frame")
initPDA:RegisterEvent("ADDON_LOADED")
initPDA:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Death Anim"], nil, CreatePlayerDeathPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
