-- Modules/DetailsProfile/UI/ConfigWindow.lua
-- The owner-only "Personal utilities" sub-tab (gated in Core.lua by debug-unlock AND
-- IsAccountOwner). Hosts the Details! profile auto-switch (ns.DetailsProfile) — a
-- dynamic list of profile cadres, each with a group-based and an instance-based
-- criterion — plus a one-click "Restore my profile" button whose baked-in blob and
-- import logic live in Modules/Profiles/Core/OwnerProfile.lua (ns.RestoreOwnerProfile).

local _, ns = ...
local L = ns.L

local function dcfg() return ns.DetailsProfile and ns.DetailsProfile.Cfg() end

local function CreatePersonalPanel(parent)
    local menu                                   -- forward ref so closures can rebuild
    local function rebuild() if menu then menu.Rebuild() end end
    local function touch()
        if ns.DetailsProfile and ns.DetailsProfile.Apply then ns.DetailsProfile.Apply() end
    end

    -- A delete cross at the top-right of a profile cadre's box (white, brand-tinted on
    -- hover, like the custom-icon / editor crosses). Confirms before removing the entry.
    local function AttachDeleteX(boxFrame, p)
        if not boxFrame then return end
        local close = CreateFrame("Button", nil, boxFrame)
        close:SetSize(18, 18)
        close:SetFrameLevel(boxFrame:GetFrameLevel() + 10)
        close:SetPoint("TOPRIGHT", boxFrame, "TOPRIGHT", -4, -4)
        local bg = close:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(close); bg:SetColorTexture(0, 0, 0, 0.5)
        local x = close:CreateTexture(nil, "OVERLAY")
        x:SetSize(10, 10); x:SetPoint("CENTER"); x:SetTexture(UNBUNK_ICON_CROSS_WHITE)
        close:SetScript("OnEnter", function() x:SetVertexColor(ns.GetBrandColor()) end)
        close:SetScript("OnLeave", function() x:SetVertexColor(1, 1, 1) end)
        close:SetScript("OnClick", function()
            ns.ui.ShowConfirm({
                title    = L["Delete profile"],
                text     = L["Delete this Details! profile entry?"],
                name     = (p.profileName ~= "" and p.profileName) or L["Profile"],
                onAccept = function()
                    if ns.DetailsProfile and ns.DetailsProfile.RemoveProfile then
                        ns.DetailsProfile.RemoveProfile(p)
                    end
                    rebuild()
                end,
            })
        end)
    end

    -- A wrapping, grey H6 description that fits the cadre width (no horizontal overflow)
    -- and self-sizes its height (so it leaves no stray gap below).
    local function GreyDescription(text)
        return { type = "custom", build = function(host)
            local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            fs:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            fs:SetTextColor(0.6, 0.6, 0.6)
            fs:SetText(text)
            local h = math.max(16, math.ceil((fs:GetStringHeight() or 14) + 4))
            host:SetHeight(h)
            return { frame = host, height = h }
        end }
    end

    -- The per-profile fade control: "Fade Details!" + a numeric opacity input + a grey
    -- "% opacity" hint. When checked and any criterion matches, the meter dims to that %.
    local function FadeEntry(p)
        return { type = "custom", height = 26, build = function(host)
            local cb = ns.ui.CreateCheckbox({
                parent = host, label = L["Fade Details!"], checked = p.fadeDetails,
                onClick = function(v) p.fadeDetails = v; touch() end,
            })
            cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            local inp = ns.ui.CreateTextInput({
                parent = host, width = 46, height = 22,
                numeric = true, min = 0, max = 100, maxLetters = 3,
                text = tostring(p.fadeOpacity or 30),
                onEnter = function(v) if v then p.fadeOpacity = v; touch() end end,
            })
            inp.frame:SetPoint("LEFT", cb.label, "RIGHT", 12, 0)
            local pct = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            pct:SetPoint("LEFT", inp.frame, "RIGHT", 6, 0)
            pct:SetTextColor(0.6, 0.6, 0.6)
            pct:SetText(L["% opacity"])
            return { frame = host, height = 26, Refresh = function() cb.SetChecked(p.fadeDetails) end }
        end }
    end

    -- A checkbox with an optional grey H6 hint to the right of its label (e.g. "(2-5)").
    local function HintCheckbox(label, hint, get, set)
        return { type = "custom", height = 24, build = function(host)
            local cb = ns.ui.CreateCheckbox({
                parent  = host,
                label   = label,
                checked = get(),
                onClick = function(v) set(v) end,
            })
            cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            if hint and hint ~= "" then
                local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                fs:SetPoint("LEFT", cb.label, "RIGHT", 8, 0)
                fs:SetTextColor(0.6, 0.6, 0.6)
                fs:SetText(hint)
            end
            return { frame = host, height = 24, Refresh = function() cb.SetChecked(get()) end }
        end }
    end

    -- The custom member-count filters of a group cadre: one row each of
    -- [enable] [min] – [max] [X], plus self-sizing. Add/remove rebuild the menu.
    local FILTER_ROW_H = 28
    local function CustomFiltersEntry(g)
        return { type = "custom", build = function(host)
            local filters = g.custom or {}
            local y = 0
            for i = 1, #filters do
                local fdef = filters[i]
                local cb = ns.ui.CreateCheckbox({
                    parent  = host,
                    label   = "",
                    checked = fdef.enabled ~= false,
                    onClick = function(v) fdef.enabled = v; touch() end,
                })
                cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
                local minI = ns.ui.CreateTextInput({
                    parent = host, width = 40, height = 22,
                    numeric = true, min = 1, max = 40, maxLetters = 2,
                    text = tostring(fdef.min or 1),
                    onEnter = function(v) if v then fdef.min = v; touch() end end,
                })
                minI.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 30, -y)
                local dash = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                dash:SetPoint("LEFT", minI.frame, "RIGHT", 5, 0); dash:SetText("–")
                local maxI = ns.ui.CreateTextInput({
                    parent = host, width = 40, height = 22,
                    numeric = true, min = 1, max = 40, maxLetters = 2,
                    text = tostring(fdef.max or 5),
                    onEnter = function(v) if v then fdef.max = v; touch() end end,
                })
                maxI.frame:SetPoint("LEFT", dash, "RIGHT", 5, 0)
                local del = ns.ui.CreateButton({
                    parent = host, label = "X", width = 24, height = 22,
                    onClick = function() table.remove(filters, i); touch(); rebuild() end,
                })
                del.frame:SetPoint("LEFT", maxI.frame, "RIGHT", 10, 0)
                y = y + FILTER_ROW_H
            end
            host:SetHeight(math.max(1, y))
            return { frame = host, height = math.max(1, y) }
        end }
    end

    -- "Change with group" cadre: enable + fade + the solo/party/raid sub-cadre + the
    -- custom member-count filters and their "add" button.
    local function GroupCadre(p)
        local g = p.group
        return { type = "group", title = L["Change with group"], build = function()
            return {
                { type = "checkbox", label = L["Enable"],
                  get = function() return g.enabled end,
                  set = function(v) g.enabled = v; touch() end },
                { type = "group", build = function()
                    return {
                        HintCheckbox(L["Solo"],  L["(not in a group)"],
                            function() return g.solo end,  function(v) g.solo = v; touch() end),
                        HintCheckbox(L["Group"], L["(2-5)"],
                            function() return g.group end, function(v) g.group = v; touch() end),
                        HintCheckbox(L["Raid"],  L["(raid group)"],
                            function() return g.raid end,  function(v) g.raid = v; touch() end),
                    }
                end },
                CustomFiltersEntry(g),
                { type = "button", label = L["Add custom group filter"], width = 200,
                  onClick = function()
                      g.custom = g.custom or {}
                      g.custom[#g.custom + 1] = { enabled = true, min = 1, max = 5 }
                      touch(); rebuild()
                  end },
            }
        end }
    end

    -- "Change with instance" cadre: enable + fade + the outdoor/dungeon/raid/BG sub-cadre.
    local function InstanceCadre(p)
        local ins = p.instance
        return { type = "group", title = L["Change with instance"], build = function()
            return {
                { type = "checkbox", label = L["Enable"],
                  get = function() return ins.enabled end,
                  set = function(v) ins.enabled = v; touch() end },
                { type = "group", build = function()
                    return {
                        HintCheckbox(L["Outdoor"],      L["(open world)"],
                            function() return ins.outdoor end,      function(v) ins.outdoor = v; touch() end),
                        HintCheckbox(L["Dungeon"],      L["(5-player)"],
                            function() return ins.dungeon end,      function(v) ins.dungeon = v; touch() end),
                        HintCheckbox(L["Raid"],         L["(raid instance)"],
                            function() return ins.raid end,         function(v) ins.raid = v; touch() end),
                        HintCheckbox(L["Battleground"], L["(PvP)"],
                            function() return ins.battleground end, function(v) ins.battleground = v; touch() end),
                    }
                end },
            }
        end }
    end

    -- "Change only in combat state :" — a gate. The checkbox enables it; the dropdown
    -- picks which combat state the whole profile is restricted to. When off, the dropdown
    -- is greyed and click-blocked. (It restricts WHEN the profile applies, it doesn't
    -- trigger on its own — a group/instance criterion still decides WHAT matches.)
    local function CombatGateEntry(p)
        local cmb = p.combat
        local function stateLabel() return cmb.state == "out" and L["Out of combat"] or L["In combat"] end
        return { type = "custom", height = 54, build = function(host)
            local anc = CreateFrame("Frame", nil, host); anc:SetSize(1, 1)
            anc:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -26)
            local dd = ns.ui.CreateDropdown({
                parent = host, anchorFrame = anc, width = 160,
                getList       = function() return { L["In combat"], L["Out of combat"] } end,
                getCurrentKey = stateLabel,
                onSelect      = function(lbl) cmb.state = (lbl == L["Out of combat"]) and "out" or "in"; touch() end,
            })
            local function applyGate()
                local tog = dd.toggleBtn
                if tog then tog:SetAlpha(cmb.enabled and 1 or 0.4); tog:EnableMouse(cmb.enabled and true or false) end
            end
            local cb = ns.ui.CreateCheckbox({
                parent = host, label = L["Change only in combat state :"], checked = cmb.enabled,
                onClick = function(v) cmb.enabled = v; touch(); applyGate() end,
            })
            cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            applyGate()
            return { frame = host, height = 54, Refresh = function()
                cb.SetChecked(cmb.enabled)
                if dd.SetCurrent then dd.SetCurrent(stateLabel()) end
                applyGate()
            end }
        end }
    end

    -- One profile entry cadre: a delete X, the "Change Details! profile" master, the
    -- profile-name input (gated by that master), then the two criterion cadres.
    local function ProfileCadre(p, idx)
        return { type = "group", title = L["Profile"] .. " " .. idx,
            onBuilt = function(widget) AttachDeleteX(widget and widget.frame, p) end,
            build = function()
                -- Backfill `combat` for profiles created earlier this session, migrating
                -- the old inCombat/outOfCombat booleans to the single `state` field.
                p.combat = p.combat or {}
                local cmb = p.combat
                if cmb.enabled == nil then cmb.enabled = false end
                if cmb.state == nil then
                    cmb.state = (cmb.outOfCombat and not cmb.inCombat) and "out" or "in"
                end
                return {
                    { type = "checkbox", label = L["Change Details! profile"],
                      get = function() return p.changeProfile end,
                      set = function(v) p.changeProfile = v; touch(); if menu then menu.Refresh() end end },
                    { type = "textinput", label = L["Details! profile name"], width = 240, maxLetters = 64,
                      enabledBy = function() return p.changeProfile end,
                      get = function() return p.profileName or "" end,
                      set = function(v) p.profileName = v or ""; touch() end },
                    FadeEntry(p),
                    GroupCadre(p),
                    InstanceCadre(p),
                    CombatGateEntry(p),
                }
            end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Personal utilities"] },

        { type = "group", title = L["Details! special settings"], build = function()
            local entries = {
                GreyDescription(L["Create profiles that switch your Details! profile and/or fade the meter based on your group and the instance you are in."]),
            }

            -- Only show (and reserve space for) the warning when Details! is actually absent.
            if not (ns.DetailsProfile and ns.DetailsProfile.DetailsReady()) then
                entries[#entries + 1] = { type = "custom", height = 18, build = function(host)
                    local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                    fs:SetPoint("LEFT", host, "LEFT", 0, 0)
                    fs:SetTextColor(1, 0.5, 0.2)
                    fs:SetText(L["Details! not detected — install / enable it for this to work."])
                    return { frame = host, height = 18 }
                end }
            end

            entries[#entries + 1] = { type = "checkbox", label = L["Enable"],
                get = function() local c = dcfg(); return c and c.enabled end,
                set = function(v) local c = dcfg(); if c then c.enabled = v and true or false end; touch() end }

            local c = dcfg()
            if c and c.profiles then
                for i, p in ipairs(c.profiles) do
                    entries[#entries + 1] = ProfileCadre(p, i)
                end
            end

            -- "Create profile" sits below the existing profiles. Settings apply live (every
            -- set calls touch()), so there is no separate "Apply now" button.
            entries[#entries + 1] = { type = "button", label = L["Create profile"], width = 160, hostHeight = 30,
                onClick = function()
                    if ns.DetailsProfile and ns.DetailsProfile.NewProfile then ns.DetailsProfile.NewProfile() end
                    rebuild()
                end }
            return entries
        end },

        { type = "group", title = L["Restore my profile"], build = function()
            return {
                GreyDescription(L["Imports the UnbunkUtility profile hardcoded in the addon into a new profile (non-destructive), in case you lose your settings."]),
                { type = "button", label = L["Import my profile"], width = 180, hostHeight = 28,
                  onClick = function() if ns.RestoreOwnerProfile then ns.RestoreOwnerProfile() end end },
            }
        end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

local initDP = CreateFrame("Frame")
initDP:RegisterEvent("ADDON_LOADED")
initDP:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Personal utilities"], nil, CreatePersonalPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
