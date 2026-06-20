-- Modules/DefensiveTracker/UI/ConfigWindow.lua
-- Item/Spell Trackers > Defensive Tracker. A General cadre (enable + active-in filter)
-- then one collapsible section per class defensive (header = spell icon + name). Each
-- section reuses the custom-CDM-icon config template, reordered: Sound first, then an
-- "Icon" sub-cadre ("Show icon" + Placement, Border, Timer, Title, Stacks).

local ADDON, ns = ...
local L  = ns.L
local DT = ns.DefensiveTracker

local function panelRefresh() if DT.configMenu then DT.configMenu.Refresh() end end
local function panelRebuild() if DT.configMenu then DT.configMenu.Rebuild() end end

-- ── Anchor + offset / style / tiers helpers (per spellId) ─────────────────────
-- Anchor modes centralised in ns (Core/Shared.lua): Center / edges / 4 inside corners.
local AnchorLabel     = ns.AnchorLabel
local AnchorFromLabel = ns.AnchorFromLabel
local AnchorList      = ns.AnchorList

local function StyleEditor(sid, prefix, LSM)
    local function k(s) return prefix .. s end
    return {
        type = "textEditor", LSM = LSM, showLabel = false, showText = false,
        showFont = true, showSize = true, showColor = true, showOutline = true,
        getFontKey      = function() return DT.Get(sid, k("FontKey"))  end,
        getFontPath     = function() return DT.Get(sid, k("FontPath")) end,
        getFontSize     = function() return DT.Get(sid, k("FontSize")) end,
        getColor        = function() return DT.Get(sid, k("Color"))    end,
        getOutline      = function() return DT.Get(sid, k("Outline"))  end,
        onFontChange    = function(key, path) DT.Set(sid, k("FontKey"), key); DT.Set(sid, k("FontPath"), path) end,
        onSizeChange    = function(size)      DT.Set(sid, k("FontSize"), size) end,
        onColorChange   = function(r, g, b, a) DT.Set(sid, k("Color"), { r = r, g = g, b = b, a = a }) end,
        onOutlineChange = function(outline)   DT.Set(sid, k("Outline"), outline) end,
    }
end

local function AnchorOffsetEntry(sid, prefix)
    return {
        type = "custom", height = 48,
        build = function(host)
            local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
            lbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); lbl:SetText(L["Anchor"])
            local ddAnchor = host:CreateFontString(nil, "ARTWORK")
            ddAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -18)
            local dd
            dd = ns.ui.CreateDropdown({
                parent = host, anchorFrame = ddAnchor, width = 130, itemHeight = 20, visibleItems = 5,
                getList = AnchorList,
                getCurrentKey = function() return AnchorLabel(DT.Get(sid, prefix .. "Anchor")) end,
                onSelect = function(label) DT.Set(sid, prefix .. "Anchor", AnchorFromLabel(label)); dd.selectedText:SetText(label) end,
            })
            dd.selectedText:SetText(AnchorLabel(DT.Get(sid, prefix .. "Anchor")))
            local function offInput(after, gap, axisText, key)
                local axis = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                axis:SetPoint("LEFT", after, "RIGHT", gap, 0); axis:SetText(axisText)
                local inp = ns.ui.CreateTextInput({
                    parent = host, width = 44, height = 22, numeric = true, allowNegative = true,
                    min = -512, max = 512, maxLetters = 4,
                    text = tostring(DT.Get(sid, key) or 0),
                    onEnter = function(v) if v ~= nil then DT.Set(sid, key, v) end end,
                })
                inp.frame:SetPoint("LEFT", axis, "RIGHT", 4, 0)
                return inp
            end
            local xInput = offInput(dd.toggleBtn, 14, "X", prefix .. "OffsetX")
            local yInput = offInput(xInput.frame, 10, "Y", prefix .. "OffsetY")
            return {
                frame = host, height = 48, dropFrame = dd.dropFrame,
                Refresh = function()
                    dd.selectedText:SetText(AnchorLabel(DT.Get(sid, prefix .. "Anchor")))
                    xInput.SetText(tostring(DT.Get(sid, prefix .. "OffsetX") or 0))
                    yInput.SetText(tostring(DT.Get(sid, prefix .. "OffsetY") or 0))
                end,
            }
        end,
    }
end

local function TiersEntry(sid)
    return {
        type = "custom", height = 60,
        build = function(host)
            local tiers = DT.Get(sid, "timerTiers") or {}
            local ROW_H = 30
            local hdr = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            hdr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            hdr:SetText(L["Time thresholds (size + colour as the timer drops)"])
            local y = 22
            for i, tier in ipairs(tiers) do
                local atLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                atLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); atLbl:SetText(L["At (s)"])
                local atInput = ns.ui.CreateTextInput({
                    parent = host, width = 42, height = 22, numeric = true, min = 0, max = 3600, maxLetters = 4,
                    text = tostring(tier.at or 0),
                    onEnter = function(v) if v ~= nil then tier.at = v; DT.ApplyIcon(sid) end end,
                })
                atInput.frame:SetPoint("LEFT", atLbl, "RIGHT", 4, 0)
                local szLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                szLbl:SetPoint("LEFT", atInput.frame, "RIGHT", 12, 0); szLbl:SetText(L["Size x"])
                local szInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 0, max = 10, maxLetters = 4,
                    text = tostring(tier.scale or 1),
                    onEnter = function(v) if v and v > 0 then tier.scale = v; DT.ApplyIcon(sid) end end,
                })
                szInput.frame:SetPoint("LEFT", szLbl, "RIGHT", 4, 0)
                local swatch = ns.ui.CreateColorSwatch({
                    parent = host, width = 24, height = 22,
                    getColor = function() return tier.color end,
                    onChange = function(r, g, b, a) tier.color = { r = r, g = g, b = b, a = a }; DT.ApplyIcon(sid) end,
                })
                swatch.frame:SetPoint("LEFT", szInput.frame, "RIGHT", 12, 0)
                local rm = ns.ui.CreateButton({
                    parent = host, label = "X", width = 24, height = 22,
                    onClick = function() table.remove(tiers, i); DT.ApplyIcon(sid); panelRebuild() end,
                })
                rm.frame:SetPoint("LEFT", swatch.frame, "RIGHT", 12, 0)
                y = y + ROW_H
            end
            local add = ns.ui.CreateButton({
                parent = host, label = L["Add threshold"], width = 140, height = 22,
                onClick = function()
                    local list = DT.Get(sid, "timerTiers")
                    if list then list[#list + 1] = { at = 10, scale = 1, color = { r = 1, g = 1, b = 1, a = 1 } }; DT.ApplyIcon(sid); panelRebuild() end
                end,
            })
            add.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
            y = y + 30
            host:SetHeight(math.max(60, y))
            return { frame = host, height = math.max(60, y) }
        end,
    }
end

-- ── Cadre builders (each a BuildMenu group entry) ─────────────────────────────
local function SoundGroup(sid, LSM)
    return { type = "group", title = L["Sound alert"], build = function() return {
        { type = "sound", LSM = LSM, label = L["Sound on use"],
          getKey = function() return DT.Get(sid, "soundKeyUse") end,
          getEnable = function() return DT.Get(sid, "soundOnUse") end,
          onSelect = function(key, path) DT.Set(sid, "soundKeyUse", key); DT.Set(sid, "soundPathUse", path) end,
          onToggle = function(v) DT.Set(sid, "soundOnUse", v) end,
          onTest = function() DT.TestSound(sid, "use") end },
        { type = "sound", LSM = LSM, label = L["Sound when ready"],
          getKey = function() return DT.Get(sid, "soundKeyReady") end,
          getEnable = function() return DT.Get(sid, "soundOnReady") end,
          onSelect = function(key, path) DT.Set(sid, "soundKeyReady", key); DT.Set(sid, "soundPathReady", path) end,
          onToggle = function(v) DT.Set(sid, "soundOnReady", v) end,
          onTest = function() DT.TestSound(sid, "ready") end },
    } end }
end

local function BorderGroup(sid, whenFn)
    return { type = "group", title = L["Border"], when = whenFn, build = function() return {
        { type = "checkbox", label = L["Show border"],
          get = function() return DT.Get(sid, "borderEnabled") == true end,
          set = function(v) DT.Set(sid, "borderEnabled", v); panelRefresh() end },
        { type = "textEditor", label = L["Border color"],
          enabledBy = function() return DT.Get(sid, "borderEnabled") == true end,
          showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
          getColor = function() return DT.Get(sid, "borderColor") end,
          onColorChange = function(r, g, b, a) DT.Set(sid, "borderColor", { r = r, g = g, b = b, a = a }) end },
        { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
          enabledBy = function() return DT.Get(sid, "borderEnabled") == true end,
          get = function() return DT.Get(sid, "borderSize") or 1 end,
          set = function(v) if v and v > 0 then DT.Set(sid, "borderSize", v) end end },
    } end }
end

local function TimerGroup(sid, LSM)
    return { type = "group", title = L["Timer"],
      gate = { enabled = function() return DT.Get(sid, "showTimer") ~= false end, master = "showtimer" },
      build = function() return {
        { type = "checkbox", ref = "showtimer", label = L["Show timer"],
          get = function() return DT.Get(sid, "showTimer") ~= false end,
          set = function(v) DT.Set(sid, "showTimer", v) end },
        StyleEditor(sid, "timer", LSM),
        TiersEntry(sid),
    } end }
end

local function TitleGroup(sid, LSM)
    return { type = "group", title = L["Title"],
      gate = { enabled = function() return DT.Get(sid, "showTitle") == true end, master = "showtitle" },
      build = function() return {
        { type = "checkbox", ref = "showtitle", label = L["Show title"],
          get = function() return DT.Get(sid, "showTitle") == true end,
          set = function(v) DT.Set(sid, "showTitle", v) end },
        { type = "textinput", label = L["Title text"], width = 240, maxLetters = 64,
          get = function() return DT.Get(sid, "titleText") or "" end,
          set = function(v) DT.Set(sid, "titleText", v or "") end },
        AnchorOffsetEntry(sid, "title"),
        StyleEditor(sid, "title", LSM),
    } end }
end

local function StacksGroup(sid, LSM)
    return { type = "group", title = L["Stacks/Charges"],
      gate = { enabled = function() return DT.Get(sid, "showStack") ~= false end, master = "showstack" },
      build = function() return {
        { type = "checkbox", ref = "showstack", label = L["Show stacks"], height = 24,
          get = function() return DT.Get(sid, "showStack") ~= false end,
          set = function(v) DT.Set(sid, "showStack", v) end,
          inline = {
            { type = "checkbox", label = L["Show icon at 0 stacks"],
              get = function() return DT.Get(sid, "showAtZero") ~= false end,
              set = function(v) DT.Set(sid, "showAtZero", v) end,
              point = { "LEFT", "LEFT", 150, 0 } },
          } },
        AnchorOffsetEntry(sid, "stack"),
        StyleEditor(sid, "stack", LSM),
    } end }
end

-- The "Icon" sub-cadre: "Show icon" gate + placement identity, then the shared Override / Free cadres.
-- Free holds this defensive's own position / size / Border / Timer / Title / Stacks; Override holds the
-- per-icon look that governs the icon while it is in the Cooldown Manager.
local function IconGroup(sid, LSM)
    return { type = "group", title = L["Icon"],
      gate = { enabled = function() return DT.Get(sid, "showIcon") ~= false end, master = "showicon" },
      build = function()
        local frameName = "UnbunkUtilityDefensive" .. sid
        local pe
        local function inCdm() return ns.CDMIncludedVal(DT.Get(sid, "includeInCdm")) end
        local function curDest() return DT.Get(sid, "cdmDest") or "belowPlayer" end
        local function applyIcon()
            DT.ApplyIcon(sid)  -- already forces a CDMAnchor re-pin
        end

        local e = {
            { type = "checkbox", ref = "showicon", label = L["Show icon"],
              get = function() return DT.Get(sid, "showIcon") ~= false end,
              set = function(v) DT.Set(sid, "showIcon", v) end },

            { type = "group", title = L["Placement"], build = function() return {
                { type = "checkbox", label = L["Include in cdm"],
                  disabled = function() return not ns.IsCDMEnabled() end,
                  get = function() return inCdm() end,
                  set = function(v) DT.Set(sid, "includeInCdm", v); panelRebuild(); if ns.RebuildActiveModule then ns.RebuildActiveModule() end end },
                { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                  when = function() return inCdm() end,
                  getList = function() return ns.CDMDestList() end,
                  getCurrentKey = function() return ns.CDMDestChoiceLabel(function(k) return DT.Get(sid, k) end) end,
                  onSelect = function(label)
                      ns.CDMApplyDestChoice(label, function(k, v) DT.Set(sid, k, v) end)
                      panelRebuild(); if ns.RebuildActiveModule then ns.RebuildActiveModule() end
                  end },
            } end },
        }

        local cfg = {
            frameName  = frameName,
            getDest    = curDest,
            cdmAtEnd   = function() return DT.Get(sid, "cdmAtEnd") end,
            inCdm      = inCdm,
            applyIcon  = applyIcon,
            rebuild    = panelRebuild,
            getOv      = function() return DT.Get(sid, "ovCollapsed") ~= false end,
            setOv      = function(c) DT.Set(sid, "ovCollapsed", c) end,
            getFree    = function() return DT.Get(sid, "freeCollapsed") ~= false end,
            setFree    = function(c) DT.Set(sid, "freeCollapsed", c) end,
            seedValues = function() return DT.OverrideSeed(sid) end,
            freeBuild  = function() return {
                { type = "position", ref = "pe",
                  onBuilt = function(w) pe = w end,
                  label = L["Icon position (offset from screen center)"],
                  getX = function() return DT.Get(sid, "posX") end,
                  getY = function() return DT.Get(sid, "posY") end,
                  onApply = function(x, yv) if x then DT.Set(sid, "posX", x) end if yv then DT.Set(sid, "posY", yv) end end,
                  onUnlock = function() DT.SetUnlocked(sid, true) end,
                  onLock   = function() DT.SetUnlocked(sid, false); if pe then pe.Refresh() end end,
                  isUnlocked = function() return DT.IsUnlocked(sid) end },
                { type = "custom", height = 46, build = function(host)
                    local sLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                    sLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sLbl:SetText(L["Icon size"])
                    local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                    wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20); wLbl:SetText(L["W"])
                    local wInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                        text = tostring(DT.Get(sid, "iconWidth") or 30),
                        onEnter = function(v) if v and v > 0 then DT.Set(sid, "iconWidth", v) end end })
                    wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                    local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                    hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                    local hInput = ns.ui.CreateTextInput({ parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                        text = tostring(DT.Get(sid, "iconHeight") or 30),
                        onEnter = function(v) if v and v > 0 then DT.Set(sid, "iconHeight", v) end end })
                    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                    return { frame = host, height = 46, Refresh = function()
                        wInput.SetText(tostring(DT.Get(sid, "iconWidth") or 30))
                        hInput.SetText(tostring(DT.Get(sid, "iconHeight") or 30))
                    end }
                end },
                BorderGroup(sid),
                TimerGroup(sid, LSM),
                TitleGroup(sid, LSM),
                StacksGroup(sid, LSM),
            } end,
        }
        for _, x in ipairs(ns.CDMGroups.TrackerCdmCadres(cfg)) do e[#e + 1] = x end
        return e
      end }
end

-- One collapsible section per defensive: header = spell icon + name; body = Sound, Icon.
local function DefensiveSection(sid, LSM)
    return {
        type      = "section",
        heading   = "UnbunkUtilityH3",
        label     = DT.SpellName(sid),
        showCheckbox = true,   -- header checkbox = enable this defensive globally
        isChecked    = function() return DT.Get(sid, "enabled") ~= false end,
        onCheck      = function(v) DT.Set(sid, "enabled", v) end,
        getCollapsed = function() return DT._uiCollapsed and DT._uiCollapsed[sid] end,
        onCollapse   = function(v) DT._uiCollapsed = DT._uiCollapsed or {}; DT._uiCollapsed[sid] = v end,
        headerExtra  = function(headerBtn, headerLabel)
            local icon = headerBtn:CreateTexture(nil, "OVERLAY")
            icon:SetSize(18, 18); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(DT.SpellTexture(sid))
            local p, rel, rp, x, y = headerLabel:GetPoint()
            icon:SetPoint(p or "LEFT", rel or headerBtn, rp or "LEFT", x or 0, y or 0)
            headerLabel:ClearAllPoints()
            headerLabel:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            return function() icon:SetTexture(DT.SpellTexture(sid)); headerLabel:SetText(DT.SpellName(sid)) end
        end,
        build = function() return {
            SoundGroup(sid, LSM),
            IconGroup(sid, LSM),
        } end,
    }
end

local function CreateDefensiveTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Defensive Tracker"] },

        -- General: enable + active-in filter (greys the filter when disabled).
        { type = "group", title = L["General"],
          gate = { enabled = function() return DT.Enabled() end, master = "enable" },
          build = function() return {
            { type = "checkbox", ref = "enable", label = L["Enable Defensive Tracker"], height = 24,
              get = function() return DT.Enabled() end,
              set = function(v) DT.SetEnabled(v) end },
            { type = "instanceFilter",
              getConfig = function() return DT.GetFilter() end,
              setConfig = function(k, v) DT.SetFilter(k, v) end },
        } end },
    }

    -- One section per tracked defensive (class + current spec).
    for _, sid in ipairs(DT.ActiveIds()) do
        options[#options + 1] = DefensiveSection(sid, LSM)
    end

    DT.configMenu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })

    -- Every defensive's Override / Free sections start collapsed and re-collapse on tab show.
    parent:HookScript("OnHide", function()
        local c = ns.db and ns.db.profile and ns.db.profile.defensiveTracker
        if c and c.spells then
            for _, e in pairs(c.spells) do e.ovCollapsed = true; e.freeCollapsed = true end
        end
    end)
    parent:HookScript("OnShow", function() if DT.configMenu then DT.configMenu.Rebuild() end end)
    return DT.configMenu
end

local initDTUI = CreateFrame("Frame")
initDTUI:RegisterEvent("ADDON_LOADED")
initDTUI:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Defensive Tracker"], nil, CreateDefensiveTrackerPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
