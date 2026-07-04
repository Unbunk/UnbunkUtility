-- Modules/DetailsProfile/UI/ConfigWindow.lua
-- The owner-only "Personal utilities" sub-category (gated in Core.lua by debug-unlock
-- AND IsAccountOwner). It holds two tabs:
--   * "Restore my profile"        — a one-click import of the baked-in UnbunkUtility
--                                    profile (blob + logic in Modules/Profiles/Core/
--                                    OwnerProfile.lua, ns.RestoreOwnerProfile).
--   * "Details! special settings" — the Details! profile auto-switch (ns.DetailsProfile):
--                                    a dynamic list of profile cadres, each with a
--                                    group-based and an instance-based criterion.

local _, ns = ...
local L = ns.L

local function dcfg() return ns.DetailsProfile and ns.DetailsProfile.Cfg() end

-- A wrapping, grey H6 description that fits the cadre width (no horizontal overflow)
-- and self-sizes its height (so it leaves no stray gap below). Shared by both tabs.
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

-- ── "Details! special settings" tab ────────────────────────────────────────────
local function CreateDetailsPanel(parent)
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

    -- The per-profile fade control: "Details! Opacity" toggle + a faded % input, and a "Mouse over Opacity"
    -- % input below (the alpha while the cursor is over the meter). When the toggle is on and any criterion
    -- matches, the meter dims to the faded %, rising to the mouse-over % on hover.
    local function FadeEntry(p)
        return { type = "custom", height = 52, build = function(host)
            -- Row 1: "Details! Opacity" toggle + the faded % input.
            local cb = ns.ui.CreateCheckbox({
                parent = host, label = L["Details! Opacity"], checked = p.fadeDetails,
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
            pct:SetText("%")
            -- Row 2: "Mouse over Opacity" toggle (default off) + its % input (the opacity while the cursor
            -- is over the meter). When unchecked, hovering leaves the meter at its faded opacity.
            local mcb = ns.ui.CreateCheckbox({
                parent = host, label = L["Mouse over Opacity"], checked = p.mouseOverEnabled == true,
                onClick = function(v) p.mouseOverEnabled = v; touch() end,
            })
            mcb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -28)
            local moInp = ns.ui.CreateTextInput({
                parent = host, width = 46, height = 22,
                numeric = true, min = 0, max = 100, maxLetters = 3,
                text = tostring(p.mouseOverOpacity or 100),
                onEnter = function(v) if v then p.mouseOverOpacity = v; touch() end end,
            })
            moInp.frame:SetPoint("LEFT", mcb.label, "RIGHT", 12, 0)
            local moPct = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            moPct:SetPoint("LEFT", moInp.frame, "RIGHT", 6, 0)
            moPct:SetTextColor(0.6, 0.6, 0.6)
            moPct:SetText("%")
            return { frame = host, height = 52, Refresh = function() cb.SetChecked(p.fadeDetails); mcb.SetChecked(p.mouseOverEnabled == true) end }
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

    -- The dynamic body: a description, an optional "not detected" warning, the master
    -- Enable, every saved profile cadre, then the "Create profile" button. Returned by
    -- the group's `build` so menu.Rebuild() regenerates it after add/remove.
    local function BuildBody()
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
    end

    -- ── "Windows settings" cadre ──────────────────────────────────────────────
    local DP = ns.DetailsProfile

    -- One Details! window's size/position cadre. Its whole box is greyed (gate) when the
    -- window is LOCKED or LINKED (snapped) to another — Details! owns the geometry then, so a
    -- manual W/H/X/Y would fight it or break the snapped group.
    local function WindowCadre(inst, idx)
        return { type = "group", title = L["Window"] .. " " .. idx,
            gate = { enabled = function() return not DP.IsWindowGated(inst) end },
            build = function()
                local entries = {}
                -- Why-greyed hint: added ONLY when the window is gated (a lock/link change re-signs the
                -- window set and rebuilds), so an EDITABLE window has no dead band above its inputs.
                if DP.IsWindowGated(inst) then
                    local reason = DP.IsWindowLocked(inst)
                        and L["Locked in Details! — unlock it there to edit."]
                        or  L["Linked to another window — detach it in Details! to edit."]
                    entries[#entries + 1] = { type = "custom", height = 16, build = function(host)
                        local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                        fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                        fs:SetTextColor(0.6, 0.6, 0.6)
                        fs:SetText(reason)
                        return { frame = host, height = 16 }
                    end }
                end
                -- W / H / X / Y inputs. Apply on Enter; each keeps the sibling axis and re-reads all four
                -- afterwards. W/H are clamped to Details!'s own window bounds (150 x 7 .. screen) — a raw
                -- SetSize would otherwise allow a broken 1px window.
                entries[#entries + 1] = { type = "custom", height = 58, build = function(host)
                    local wIn, hIn, xIn, yIn, refresh
                    local maxW = math.floor(GetScreenWidth()  or 2560)
                    local maxH = math.floor(GetScreenHeight() or 1440)
                    local function num(box, fb) local v = box and tonumber(box.GetText()); return v or fb end
                    local function label(text, ox, oy)
                        local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        fs:SetPoint("TOPLEFT", host, "TOPLEFT", ox, oy)
                        fs:SetText(text)
                    end
                    wIn = ns.ui.CreateTextInput({ parent = host, width = 60, height = 22,
                        numeric = true, min = 150, max = maxW, maxLetters = 5, text = "0",
                        onEnter = function(v) if v then DP.SetWindowSize(inst, v, num(hIn, v)); if refresh then refresh() end end end })
                    hIn = ns.ui.CreateTextInput({ parent = host, width = 60, height = 22,
                        numeric = true, min = 7, max = maxH, maxLetters = 5, text = "0",
                        onEnter = function(v) if v then DP.SetWindowSize(inst, num(wIn, v), v); if refresh then refresh() end end end })
                    xIn = ns.ui.CreateTextInput({ parent = host, width = 60, height = 22,
                        numeric = true, allowNegative = true, maxLetters = 6, text = "0",
                        onEnter = function(v) if v then DP.SetWindowPos(inst, v, num(yIn, 0)); if refresh then refresh() end end end })
                    yIn = ns.ui.CreateTextInput({ parent = host, width = 60, height = 22,
                        numeric = true, allowNegative = true, maxLetters = 6, text = "0",
                        onEnter = function(v) if v then DP.SetWindowPos(inst, num(xIn, 0), v); if refresh then refresh() end end end })
                    label("W", 0, -4);    wIn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 18, 0)
                    label("H", 110, -4);  hIn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 128, 0)
                    label("X", 0, -32);   xIn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 18, -28)
                    label("Y", 110, -32); yIn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 128, -28)
                    refresh = function()
                        -- Skip a box the user is currently typing in (a live poll refresh must not
                        -- clobber an unsubmitted edit); the others still track the window live.
                        local w, h, x, y = DP.GetWindowRect(inst)
                        if not wIn.editBox:HasFocus() then wIn.SetText(tostring(w)) end
                        if not hIn.editBox:HasFocus() then hIn.SetText(tostring(h)) end
                        if not xIn.editBox:HasFocus() then xIn.SetText(tostring(x)) end
                        if not yIn.editBox:HasFocus() then yIn.SetText(tostring(y)) end
                    end
                    refresh()
                    return { frame = host, height = 58, Refresh = refresh }
                end }
                return entries
            end }
    end

    -- The "Windows settings" body: a description, then one cadre per created Details! window.
    local function BuildWindowsBody()
        local entries = {
            GreyDescription(L["Set each Details! window's size (W/H) and position (X/Y). A window that is locked or linked (snapped) to another is greyed — unlock / detach it in Details! first."]),
        }
        if not (DP and DP.DetailsReady and DP.DetailsReady()) then
            entries[#entries + 1] = { type = "custom", height = 18, build = function(host)
                local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                fs:SetPoint("LEFT", host, "LEFT", 0, 0)
                fs:SetTextColor(1, 0.5, 0.2)
                fs:SetText(L["Details! not detected — install / enable it for this to work."])
                return { frame = host, height = 18 }
            end }
            return entries
        end
        local n = DP.NumWindows()
        if n == 0 then
            entries[#entries + 1] = GreyDescription(L["No Details! window found."])
            return entries
        end
        for i = 1, n do
            local inst = DP.GetWindow(i)
            -- Only OPEN windows (skip empty slots AND closed-but-not-destroyed windows).
            if DP.IsWindowOpen(inst) then entries[#entries + 1] = WindowCadre(inst, i) end
        end
        return entries
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Details! special settings"] },
        { type = "group", title = L["Windows settings"],  build = BuildWindowsBody },
        { type = "group", title = L["Profiles settings"], build = BuildBody },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })

    -- Keep the Windows cadre live even while the tab stays open (Details! fires no event we can hook
    -- for a manual drag / resize / lock). Two signatures split the work so we never do more than needed:
    --   * STRUCT (count + each window's gated state): a change means a window opened/closed/locked/
    --     unlocked/linked -> full Rebuild (adds/removes cadres, greying + hint). Orphans frames, so it
    --     runs ONLY on this rare change.
    --   * GEOM (W/H/X/Y): a change means a manual drag/resize -> cheap menu.Refresh() re-reads the fields.
    -- Unchanged -> no work. Driven by a throttled ticker that only runs while THIS tab is shown (it is a
    -- child of `parent`, so it hides — and stops — with the tab), plus an immediate sync on show.
    local lastStruct, lastGeom
    local function windowSigs()
        if not (DP and DP.NumWindows) then return "0", "0" end
        local n = DP.NumWindows()
        local st, gm = { tostring(n) }, {}
        for i = 1, n do
            local inst = DP.GetWindow(i)
            if DP.IsWindowOpen(inst) then
                st[#st + 1] = i .. (DP.IsWindowGated(inst) and "g" or "e")
                local w, h, x, y = DP.GetWindowRect(inst)
                gm[#gm + 1] = i .. ":" .. w .. "," .. h .. "," .. x .. "," .. y
            end
        end
        return table.concat(st, ","), table.concat(gm, ";")
    end
    local function syncNow()
        if not menu then return end
        local st, gm = windowSigs()
        if st ~= lastStruct then
            lastStruct, lastGeom = st, gm
            rebuild()
        elseif gm ~= lastGeom then
            lastGeom = gm
            menu.Refresh()
        end
    end
    lastStruct, lastGeom = windowSigs()
    parent:HookScript("OnShow", syncNow)

    local poller = CreateFrame("Frame", nil, parent)
    poller:SetSize(1, 1)
    local accum = 0
    poller:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 0.25 then return end
        accum = 0
        syncNow()
    end)
    return menu
end

-- ── "Restore my profile" tab ───────────────────────────────────────────────────
local function CreateRestorePanel(parent)
    -- An orange "not available" note line (addon absent / no import path).
    local function WarnLine(text)
        return { type = "custom", height = 18, build = function(host)
            local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            fs:SetPoint("LEFT", host, "LEFT", 0, 0)
            fs:SetTextColor(1, 0.5, 0.2)
            fs:SetText(text)
            return { frame = host, height = 18 }
        end }
    end

    -- Run one addon's import, then report / prompt reload in chat.
    local function RunImport(entry, b)
        if InCombatLockdown() then ns.Print(L["Can't import a profile in combat."]); return end
        local ok, detail = b.run()
        if ok then
            if detail == "reload" then
                ns.ui.ShowConfirm({
                    title    = L["Reload UI?"],
                    text     = string.format(L["%s imported. A UI reload is needed to fully apply it. Reload now?"], entry.label),
                    onAccept = function() ReloadUI() end,
                })
            elseif detail == "confirm" then
                ns.Print(string.format(L["%s: confirm the import in the addon's own dialog."], entry.label))
            else
                ns.Print(string.format(L["%s profile imported."], entry.label))
            end
        else
            local msg
            if detail == "empty"        then msg = L["no string saved — paste it into AddonProfiles.lua first."]
            elseif detail == "notloaded" then msg = L["addon not detected."]
            elseif detail == "decode"    then msg = L["could not decode the string."]
            else msg = tostring(detail) end
            ns.Print(string.format(L["%s import failed: %s"], entry.label, msg))
        end
    end

    -- One import button + a grey "(no string saved yet)" hint when its blob is still empty.
    local function ImportButtonRow(entry, b)
        return { type = "custom", height = 30, build = function(host)
            local btn = ns.ui.CreateButton({
                parent = host, label = L[b.labelKey], width = 200, height = 22,
                onClick = function() RunImport(entry, b) end,
            })
            btn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -4)
            if ns.AddonProfiles and ns.AddonProfiles.BlobEmpty(b.blob) then
                local hint = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                hint:SetPoint("LEFT", btn.frame, "RIGHT", 10, 0)
                hint:SetTextColor(0.6, 0.6, 0.6)
                hint:SetText(L["(no string saved yet)"])
            end
            return { frame = host, height = 30 }
        end }
    end

    -- Dominos can't export a profile string, so capture the LIVE Dominos profile into a copyable box
    -- (read-only: snaps back on edit) — the user copies it into AddonProfiles.lua's `dominos` blob.
    local function DominosExportRow()
        return { type = "custom", height = 82, build = function(host)
            local hint = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            hint:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            hint:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
            hint:SetJustifyH("LEFT"); hint:SetWordWrap(true); hint:SetTextColor(0.6, 0.6, 0.6)
            hint:SetText(L["Dominos can't export — capture your CURRENT Dominos profile here, copy it, and paste it into AddonProfiles.lua's dominos blob."])

            local input = ns.ui.CreateTextInput({ parent = host, width = 380, height = 22, maxLetters = 0 })
            input.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -30)
            local box, val = input.editBox, ""
            box:SetScript("OnTextChanged", function(self)
                if self:GetText() ~= val then self:SetText(val); self:HighlightText() end
            end)

            local btn = ns.ui.CreateButton({
                parent = host, label = L["Capture current Dominos profile"], width = 240, height = 22,
                onClick = function()
                    val = (ns.AddonProfiles and ns.AddonProfiles.ExportDominos and ns.AddonProfiles.ExportDominos()) or ""
                    if val == "" then ns.Print(L["Dominos not loaded (or serializer missing)."]); return end
                    box:SetText(val); box:SetFocus(); box:HighlightText()   -- select-all for Ctrl+C
                end,
            })
            btn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -56)
            return { frame = host, height = 82 }
        end }
    end

    -- One addon cadre: its import button(s), or a greyed note when unavailable.
    local function AddonCadre(entry)
        return { type = "group", title = L[entry.label], build = function()
            local AP = ns.AddonProfiles
            if not AP then return { WarnLine(L["addon not detected."]) } end
            if entry.unsupported == "notinstalled" or not AP.Loaded(entry.addon) then
                return { WarnLine(L["This addon is not detected — install / enable it for this to work."]) }
            end
            if entry.unsupported == "nostring" then
                return { WarnLine(L["This addon has no profile-string import."]) }
            end
            local items = {}
            for _, b in ipairs(entry.buttons or {}) do
                items[#items + 1] = ImportButtonRow(entry, b)
            end
            if entry.exportHelper == "dominos" then
                items[#items + 1] = DominosExportRow()
            end
            return items
        end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Restore my profile"] },
        -- UnbunkUtility's own baked-in profile (the original one-click restore).
        { type = "group", title = "UnbunkUtility", build = function()
            return {
                { type = "button", label = L["Import my profile"], width = 180, hostHeight = 28,
                  onClick = function() if ns.RestoreOwnerProfile then ns.RestoreOwnerProfile() end end },
            }
        end },
    }

    -- One cadre per other addon, driven by ns.AddonProfiles.ENTRIES.
    if ns.AddonProfiles and ns.AddonProfiles.ENTRIES then
        for _, entry in ipairs(ns.AddonProfiles.ENTRIES) do
            options[#options + 1] = AddonCadre(entry)
        end
    end

    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Restore my profile"],        nil, CreateRestorePanel)
    UnbunkUtility.RegisterModule(L["Details! special settings"], nil, CreateDetailsPanel)
end)
