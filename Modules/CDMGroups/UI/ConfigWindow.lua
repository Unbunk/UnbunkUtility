-- Modules/CDMGroups/UI/ConfigWindow.lua
-- "Essential (groups)" / "Utility (groups)" panel — a GENERALIZED, dest-parameterized clone of
-- Modules/BuffGroups/UI/ConfigWindow.lua. CreatePanel(I) builds the panel bound to ONE Config
-- instance (ns.CDMGroups.essential + ns.CDMGroups.utility each get one CreatePanel call).
--
-- Layout (same template as Buffs): an enable checkbox under the title (DEFAULT OFF — the new engine
-- only takes over the native Essential viewer when this is ON; until then the OLD bucket system runs),
-- then a "Cooldown groups" cadre holding one sub-cadre per group, an "Unused" sub-cadre and a
-- "Create group" button. Each group cadre: name input, a draggable icon strip (reorder / move between
-- groups), and a collapsible "Group settings" (Position / Border / Glow / Icons). A PENCIL on each
-- tile opens the per-ICON override editor (the same shared SUBSET as Buffs).
--
-- DIFFERENCES from the Buffs panel: NO "+" add tile / custom-buff prompt (natives only this phase).
-- The red "Not displayed" flag IS present: a cooldown placed in a real group that isn't in the native
-- CDM's tracked (displayed) set can't show there, so its tile is flagged red (port of BuffGroups).

local _, ns = ...
local L = ns.L

local ICON, PAD = 30, 4
local STEP = ICON + 6
local GAP_BG = 6
local PER_ROW = 12

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ── anchorTo / growDir / relPos option maps (label <-> stored key) — identical to Buffs ──
local ANCHOR_ORDER = { "essential", "utility", "belowPlayer", "screen" }
local function AnchorLabel(key)
    if key == "essential"   then return L["Essential"]    end
    if key == "screen"      then return L["Screen"]       end
    if key == "belowPlayer" then return L["Below player"] end
    return L["Utility"]
end
local function AnchorList()
    local t = {}
    for _, k in ipairs(ANCHOR_ORDER) do t[#t + 1] = AnchorLabel(k) end
    return t
end
local function AnchorFromLabel(label)
    for _, k in ipairs(ANCHOR_ORDER) do
        if AnchorLabel(k) == label then return k end
    end
    return "essential"
end

local GROW_ORDER = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER_H", "CENTER_V" }
local function GrowLabel(key)
    if key == "LEFT"     then return L["Left"]                  end
    if key == "UP"       then return L["Up"]                    end
    if key == "DOWN"     then return L["Down"]                  end
    if key == "CENTER_H" then return L["Center (horizontal)"]   end
    if key == "CENTER_V" then return L["Center (vertical)"]     end
    return L["Right"]
end
local function GrowList()
    local t = {}
    for _, k in ipairs(GROW_ORDER) do t[#t + 1] = GrowLabel(k) end
    return t
end
local function GrowFromLabel(label)
    for _, k in ipairs(GROW_ORDER) do
        if GrowLabel(k) == label then return k end
    end
    return "RIGHT"
end

local GLOWTYPE_ORDER = { "pixel", "autocast", "button", "proc" }
local function GlowTypeLabel(key)
    if key == "autocast" then return L["Autocast Glow"] end
    if key == "button"   then return L["Button Glow"]   end
    if key == "proc"     then return L["Proc Glow"]     end
    return L["Pixel Glow"]
end
local function GlowTypeList()
    local t = {}
    for _, k in ipairs(GLOWTYPE_ORDER) do t[#t + 1] = GlowTypeLabel(k) end
    return t
end
local function GlowTypeFromLabel(label)
    for _, k in ipairs(GLOWTYPE_ORDER) do
        if GlowTypeLabel(k) == label then return k end
    end
    return "pixel"
end

local RELPOS_ORDER = { "above", "below", "left", "right", "topleft", "topright", "bottomleft", "bottomright" }
local function RelPosLabel(key)
    if key == "below"       then return L["Below"]        end
    if key == "left"        then return L["Left"]         end
    if key == "right"       then return L["Right"]        end
    if key == "topleft"     then return L["Top-left"]     end
    if key == "topright"    then return L["Top-right"]    end
    if key == "bottomleft"  then return L["Bottom-left"]  end
    if key == "bottomright" then return L["Bottom-right"] end
    return L["Above"]
end
local function RelPosList()
    local t = {}
    for _, k in ipairs(RELPOS_ORDER) do t[#t + 1] = RelPosLabel(k) end
    return t
end
local function RelPosFromLabel(label)
    for _, k in ipairs(RELPOS_ORDER) do
        if RelPosLabel(k) == label then return k end
    end
    return "above"
end

-- ── Shared Timer / Title / Stacks sub-cadre builders (bundle-driven, like Buffs) ──
local function append(list, extra)
    if extra then list[#list + 1] = extra end
    return list
end

local function CloneVal(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = CloneVal(val) end
    return out
end

local function StyleEditorFor(bundle, prefix)
    local function k(suffix) return prefix .. suffix end
    return {
        type        = "textEditor", LSM = LSM,
        showLabel   = false, showText = false,
        showFont    = true,  showSize = true, showColor = true, showOutline = true,
        getFontKey      = function() return bundle.get(k("FontKey"))  end,
        getFontPath     = function() return bundle.get(k("FontPath")) end,
        getFontSize     = function() return bundle.get(k("FontSize")) end,
        getColor        = function() return bundle.get(k("Color"))    end,
        getOutline      = function() return bundle.get(k("Outline"))  end,
        onFontChange    = function(key, path) bundle.set(k("FontKey"), key); bundle.set(k("FontPath"), path); bundle.touch() end,
        onSizeChange    = function(size)       bundle.set(k("FontSize"), size); bundle.touch() end,
        onColorChange   = function(r, g, b, a) bundle.set(k("Color"), { r = r, g = g, b = b, a = a }); bundle.touch() end,
        onOutlineChange = function(outline)    bundle.set(k("Outline"), outline); bundle.touch() end,
    }
end

local function PosOffsetFor(bundle, prefix)
    return {
        type = "custom", height = 48,
        build = function(host)
            local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            lbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); lbl:SetText(L["Anchor"])

            local ddAnchor = host:CreateFontString(nil, "ARTWORK")
            ddAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -18)
            local dd
            dd = ns.ui.CreateDropdown({
                parent = host, anchorFrame = ddAnchor, width = 130, itemHeight = 20, visibleItems = 5,
                getList = ns.AnchorList,
                getCurrentKey = function() return ns.AnchorLabel(bundle.get(prefix .. "Pos")) end,
                onSelect = function(label)
                    bundle.set(prefix .. "Pos", ns.AnchorFromLabel(label)); bundle.touch()
                    dd.selectedText:SetText(label)
                end,
            })
            dd.selectedText:SetText(ns.AnchorLabel(bundle.get(prefix .. "Pos")))

            local function offInput(after, gap, axisText, key)
                local axis = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                axis:SetPoint("LEFT", after, "RIGHT", gap, 0); axis:SetText(axisText)
                local inp = ns.ui.CreateTextInput({
                    parent = host, width = 44, height = 22, numeric = true, allowNegative = true,
                    min = -512, max = 512, maxLetters = 4,
                    text = tostring(bundle.get(key) or 0),
                    onEnter = function(v) if v ~= nil then bundle.set(key, v); bundle.touch() end end,
                })
                inp.frame:SetPoint("LEFT", axis, "RIGHT", 4, 0)
                return inp
            end
            local xInput = offInput(dd.toggleBtn, 14, "X", prefix .. "OffX")
            local yInput = offInput(xInput.frame, 10, "Y", prefix .. "OffY")

            return {
                frame = host, height = 48, dropFrame = dd.dropFrame,
                Refresh = function()
                    dd.selectedText:SetText(ns.AnchorLabel(bundle.get(prefix .. "Pos")))
                    xInput.SetText(tostring(bundle.get(prefix .. "OffX") or 0))
                    yInput.SetText(tostring(bundle.get(prefix .. "OffY") or 0))
                end,
            }
        end,
    }
end

local function OverrideToggle(bundle, keys, label)
    if not bundle.reset or not bundle.has then return nil end
    return { type = "checkbox", label = label or L["Override group settings"],
        get = function() return bundle.has(keys) end,
        set = function(v)
            if v then
                for _, key in ipairs(keys) do bundle.set(key, CloneVal(bundle.get(key))) end
            else
                for _, key in ipairs(keys) do bundle.reset(key) end
            end
            bundle.touch()
            if bundle.refresh then bundle.refresh() end
        end }
end

local function CopyGroupButton(bundle, keys, gated)
    if not bundle.reset or not bundle.has then return nil end
    local groupGet = bundle.groupGet or bundle.get
    return { type = "button", label = L["Copy group settings"], width = 180, hostHeight = 30, enabledBy = gated,
        onClick = function()
            for _, key in ipairs(keys) do bundle.set(key, CloneVal(groupGet(key))) end
            bundle.touch()
            if bundle.refresh then bundle.refresh() end
        end }
end

local function SectionOverridden(bundle, keys)
    if not bundle.has then return nil end
    return function() return bundle.has(keys) end
end

local function CloneThresholds(list)
    local out = {}
    for _, t in ipairs(list or {}) do
        local c = t.color
        out[#out + 1] = {
            time  = t.time or 0,
            size  = t.size or 1,
            color = c and { r = c.r, g = c.g, b = c.b, a = c.a or 1 } or { r = 1, g = 1, b = 1, a = 1 },
        }
    end
    return out
end

local function ThresholdsEditor(bundle, sectionGate)
    return {
        type   = "custom", height = 60,
        enabledBy = function()
            if sectionGate and not sectionGate() then return false end
            return bundle.get("timerThresholdsEnabled") == true
        end,
        build  = function(host)
            local list  = bundle.get("timerThresholds") or {}
            local ROW_H = 30

            local hdr = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            hdr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            hdr:SetText(L["Time thresholds (size + colour as the timer drops)"])

            local y = 22
            for i, tier in ipairs(list) do
                local atLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                atLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
                atLbl:SetText(L["At (s)"])
                local atInput = ns.ui.CreateTextInput({
                    parent = host, width = 42, height = 22, numeric = true, min = 0, max = 3600, maxLetters = 4,
                    text = tostring(tier.time or 0),
                    onEnter = function(v)
                        if v ~= nil then
                            local nl = CloneThresholds(list); nl[i].time = v
                            bundle.set("timerThresholds", nl); bundle.touch()
                        end
                    end,
                })
                atInput.frame:SetPoint("LEFT", atLbl, "RIGHT", 4, 0)

                local szLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                szLbl:SetPoint("LEFT", atInput.frame, "RIGHT", 12, 0)
                szLbl:SetText(L["Size x"])
                local szInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 0, max = 10, maxLetters = 4,
                    text = tostring(tier.size or 1),
                    onEnter = function(v)
                        if v and v > 0 then
                            local nl = CloneThresholds(list); nl[i].size = v
                            bundle.set("timerThresholds", nl); bundle.touch()
                        end
                    end,
                })
                szInput.frame:SetPoint("LEFT", szLbl, "RIGHT", 4, 0)

                local swatch = ns.ui.CreateColorSwatch({
                    parent = host, width = 24, height = 22,
                    getColor = function() return tier.color end,
                    onChange = function(r, g, b, a)
                        local nl = CloneThresholds(list); nl[i].color = { r = r, g = g, b = b, a = a }
                        bundle.set("timerThresholds", nl); bundle.touch()
                    end,
                })
                swatch.frame:SetPoint("LEFT", szInput.frame, "RIGHT", 12, 0)

                local rm = ns.ui.CreateButton({
                    parent = host, label = "X", width = 24, height = 22,
                    onClick = function()
                        local nl = CloneThresholds(list); table.remove(nl, i)
                        bundle.set("timerThresholds", nl); bundle.touch()
                        if bundle.refresh then bundle.refresh() end
                    end,
                })
                rm.frame:SetPoint("LEFT", swatch.frame, "RIGHT", 12, 0)

                y = y + ROW_H
            end

            local add = ns.ui.CreateButton({
                parent = host, label = L["Add threshold"], width = 140, height = 22,
                onClick = function()
                    local nl = CloneThresholds(list)
                    nl[#nl + 1] = { time = 10, size = 1, color = { r = 1, g = 1, b = 1, a = 1 } }
                    bundle.set("timerThresholds", nl); bundle.touch()
                    if bundle.refresh then bundle.refresh() end
                end,
            })
            add.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
            y = y + 30

            host:SetHeight(math.max(60, y))
            return { frame = host, height = math.max(60, y) }
        end,
    }
end

local TIMER_KEYS = {
    "showTimer", "timerFontKey", "timerFontPath", "timerFontSize", "timerOutline",
    "timerColor", "timerPos", "timerOffX", "timerOffY",
    "timerThresholdsEnabled", "timerThresholds",
}
local function TimerSection(bundle)
    local gated = SectionOverridden(bundle, TIMER_KEYS)
    return { type = "group", title = L["Timer"],
      gate = (not bundle.has) and { enabled = function() return bundle.get("showTimer") ~= false end, master = "showtimer" } or nil,
      build = function()
        local e = {}
        append(e, OverrideToggle(bundle, TIMER_KEYS))
        append(e, CopyGroupButton(bundle, TIMER_KEYS, gated))
        e[#e + 1] = { type = "checkbox", ref = "showtimer", label = L["Show timer"], enabledBy = gated,
              get = function() return bundle.get("showTimer") ~= false end,
              set = function(v) bundle.set("showTimer", v); bundle.touch() end }
        local style = StyleEditorFor(bundle, "timer"); style.enabledBy = gated; e[#e + 1] = style
        local pos = PosOffsetFor(bundle, "timer"); pos.enabledBy = gated; e[#e + 1] = pos
        e[#e + 1] = { type = "checkbox", label = L["Enable time thresholds"], enabledBy = gated,
              get = function() return bundle.get("timerThresholdsEnabled") == true end,
              set = function(v) bundle.set("timerThresholdsEnabled", v and true or false); bundle.touch()
                  if bundle.refresh then bundle.refresh() end end }
        local thr = ThresholdsEditor(bundle, gated); e[#e + 1] = thr
        return e
      end }
end

local TITLE_KEYS = {
    "showTitle", "titleText", "titleFontKey", "titleFontPath", "titleFontSize",
    "titleOutline", "titleColor", "titlePos", "titleOffX", "titleOffY",
}
local function TitleSection(bundle)
    local gated = SectionOverridden(bundle, TITLE_KEYS)
    return { type = "group", title = L["Title"],
      gate = (not bundle.has) and { enabled = function() return bundle.get("showTitle") == true end, master = "showtitle" } or nil,
      build = function()
        local e = {}
        append(e, OverrideToggle(bundle, TITLE_KEYS))
        append(e, CopyGroupButton(bundle, TITLE_KEYS, gated))
        e[#e + 1] = { type = "checkbox", ref = "showtitle", label = L["Show title"], enabledBy = gated,
              get = function() return bundle.get("showTitle") == true end,
              set = function(v) bundle.set("showTitle", v); bundle.touch() end }
        e[#e + 1] = { type = "textinput", label = L["Title text"], width = 240, maxLetters = 64, enabledBy = gated,
              get = function() return bundle.get("titleText") or "" end,
              set = function(v) bundle.set("titleText", v or ""); bundle.touch() end }
        local style = StyleEditorFor(bundle, "title"); style.enabledBy = gated; e[#e + 1] = style
        local pos = PosOffsetFor(bundle, "title"); pos.enabledBy = gated; e[#e + 1] = pos
        return e
      end }
end

local STACK_KEYS = {
    "showStack", "showAtZero", "stackFontKey", "stackFontPath", "stackFontSize", "stackOutline",
    "stackColor", "stackPos", "stackOffX", "stackOffY",
}
local function StacksSection(bundle)
    local gated = SectionOverridden(bundle, STACK_KEYS)
    return { type = "group", title = L["Stacks/Charges"],
      gate = (not bundle.has) and { enabled = function() return bundle.get("showStack") ~= false end, master = "showstack" } or nil,
      build = function()
        local e = {}
        append(e, OverrideToggle(bundle, STACK_KEYS))
        append(e, CopyGroupButton(bundle, STACK_KEYS, gated))
        e[#e + 1] = { type = "checkbox", ref = "showstack", label = L["Show stacks"], enabledBy = gated,
              get = function() return bundle.get("showStack") ~= false end,
              set = function(v) bundle.set("showStack", v); bundle.touch() end }
        local style = StyleEditorFor(bundle, "stack"); style.enabledBy = gated; e[#e + 1] = style
        local pos = PosOffsetFor(bundle, "stack"); pos.enabledBy = gated; e[#e + 1] = pos
        return e
      end }
end

-- Exposed so the below-player panel (and later the shared custom-icon window) can reuse the SAME
-- Timer/Title/Stacks sections fed a per-dest bundle — pixel-identical to essential, with the show-gate
-- greying handled by the section's own `gate` (active when the bundle has no `has`, i.e. not an override).
ns.CDMGroups = ns.CDMGroups or {}
ns.CDMGroups.TimerSection  = TimerSection
ns.CDMGroups.TitleSection  = TitleSection
ns.CDMGroups.StacksSection = StacksSection
ns.CDMGroups.SectionKeys   = { timer = TIMER_KEYS, title = TITLE_KEYS, stack = STACK_KEYS }
ns.CDMGroups.GrowList      = GrowList
ns.CDMGroups.GrowLabel     = GrowLabel
ns.CDMGroups.GrowFromLabel = GrowFromLabel

-- ════════════════════════════════════════════════════════════════════════════════
-- Per-ICON override editor (the pencil), bound to a Config instance `I`. One singleton editor is
-- shared across panels (re-pointed to the active I + sid on open).
-- ════════════════════════════════════════════════════════════════════════════════
local iconEditor
local editingI, editingSid
local onIconEditChange
local OpenIconEditor   -- fwd decl

-- The icon's option tree, fully parameterised over a `bundle` (config get/set/reset/has/groupGet +
-- touch/refresh) and a `ctx` (editor-frame coupling). This SHARED body backs both the per-icon override
-- editor (the pencil, below) and the standalone CustomCDM editor — each supplies its own bundle + ctx.
-- A control is editable when its section is overridden (bundle.has) OR when the bundle has no override
-- mechanism at all (standalone: bundle.has nil -> always editable). `bundle.refresh` is the full menu
-- re-render the shared section helpers expect; `ctx.refresh`/`ctx.rebuild` are the editor's light/full
-- re-renders and `ctx.reopen` re-opens it. `I`/`sid` are carried for sections that need them in later
-- increments (spell/item resolution); the body reads config only through the bundle.
local function IconSections(I, sid, bundle, ctx)
    local function gatedFor(keys)
        return function()
            if bundle.has then return bundle.has(keys) end
            return true
        end
    end
    local entries = {
        { type = "label", font = "UnbunkUtilityH6", height = 30,
          text = L["Tick \"Override group settings\" in a section to give this icon its own values; untick it to inherit the group again."] },

        { type = "group", title = L["Sound alert"], build = function() return {
            { type = "sound", LSM = LSM, label = L["Sound on use"],
              getKey    = function() return bundle.get("soundStartSound") end,
              getEnable = function() return bundle.get("soundStartEnabled") == true end,
              onSelect  = function(key, path) bundle.set("soundStartSound", key); bundle.set("soundStartPath", path) end,
              onToggle  = function(v) bundle.set("soundStartEnabled", v and true or false) end,
              onTest    = function()
                  local p = bundle.get("soundStartPath")
                  if p then PlaySoundFile(p, "Master")
                  else local k = bundle.get("soundStartSound"); local r = LSM and k and LSM:Fetch("sound", k); if r then PlaySoundFile(r, "Master") end end
              end },
            { type = "sound", LSM = LSM, label = L["Sound when ready"],
              getKey    = function() return bundle.get("soundStopSound") end,
              getEnable = function() return bundle.get("soundStopEnabled") == true end,
              onSelect  = function(key, path) bundle.set("soundStopSound", key); bundle.set("soundStopPath", path) end,
              onToggle  = function(v) bundle.set("soundStopEnabled", v and true or false) end,
              onTest    = function()
                  local p = bundle.get("soundStopPath")
                  if p then PlaySoundFile(p, "Master")
                  else local k = bundle.get("soundStopSound"); local r = LSM and k and LSM:Fetch("sound", k); if r then PlaySoundFile(r, "Master") end end
              end },
        } end },

        { type = "button", width = 200, hostHeight = 30,
          label = (bundle.get("placeholder") == true) and L["Hide placeholder"] or L["Show placeholder"],
          onClick = function()
              bundle.set("placeholder", bundle.get("placeholder") ~= true)
              bundle.touch()
              ctx.reopen()
          end },

        { type = "group", title = L["CDM settings"], build = function()
            local keys = { "showPressOverlay", "showKeybinds" }
            local gated = gatedFor(keys)
            local e = {}
            append(e, OverrideToggle(bundle, keys, L["Override CDM settings"]))
            append(e, CopyGroupButton(bundle, keys, gated))
            e[#e + 1] = { type = "checkbox", label = L["Show press overlay"], enabledBy = gated,
              get = function() return bundle.get("showPressOverlay") == true end,
              set = function(v) bundle.set("showPressOverlay", v and true or false); bundle.touch() end }
            e[#e + 1] = { type = "checkbox", label = L["Show Keybinds"], enabledBy = gated,
              get = function() return bundle.get("showKeybinds") == true end,
              set = function(v) bundle.set("showKeybinds", v and true or false); bundle.touch() end }
            return e
        end },

        { type = "group", title = L["Icon size"], build = function()
            local keys = { "iconW", "iconH" }
            local gated = gatedFor(keys)
            local e = {}
            append(e, OverrideToggle(bundle, keys))
            append(e, CopyGroupButton(bundle, keys, gated))
            e[#e + 1] = { type = "custom", height = 30, enabledBy = gated, build = function(host)
                local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); wLbl:SetText(L["W"])
                local wInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(bundle.get("iconW") or 44),
                    onEnter = function(v) if v and v > 0 then bundle.set("iconW", v); bundle.touch() end end,
                })
                wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                local hInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(bundle.get("iconH") or 44),
                    onEnter = function(v) if v and v > 0 then bundle.set("iconH", v); bundle.touch() end end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                return { frame = host, height = 30, Refresh = function()
                    wInput.SetText(tostring(bundle.get("iconW") or 44))
                    hInput.SetText(tostring(bundle.get("iconH") or 44))
                end }
            end }
            return e
        end },

        { type = "group", title = L["Border"], build = function()
            local keys = { "borderEnabled", "borderColor", "borderSize" }
            local gated = gatedFor(keys)
            local e = {}
            append(e, OverrideToggle(bundle, keys))
            append(e, CopyGroupButton(bundle, keys, gated))
            e[#e + 1] = { type = "checkbox", label = L["Show border"], enabledBy = gated,
              get = function() return bundle.get("borderEnabled") ~= false end,
              set = function(v) bundle.set("borderEnabled", v); bundle.touch(); ctx.refresh() end }
            e[#e + 1] = { type = "textEditor", label = L["Border color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return gated() and bundle.get("borderEnabled") ~= false end,
              getColor = function() return bundle.get("borderColor") end,
              onColorChange = function(r, g, b, a) bundle.set("borderColor", { r = r, g = g, b = b, a = a }); bundle.touch() end }
            e[#e + 1] = { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
              enabledBy = function() return gated() and bundle.get("borderEnabled") ~= false end,
              get = function() return bundle.get("borderSize") or 1 end,
              set = function(v) if v and v > 0 then bundle.set("borderSize", v); bundle.touch() end end }
            return e
        end },

        { type = "group", title = L["Glow"], build = function()
            local keys = { "glowEnabled", "glowType", "glowColor" }
            local gated = gatedFor(keys)
            local e = {}
            append(e, OverrideToggle(bundle, keys))
            append(e, CopyGroupButton(bundle, keys, gated))
            e[#e + 1] = { type = "checkbox", label = L["Show glow on proc"], enabledBy = gated,
              get = function() return bundle.get("glowEnabled") == true end,
              set = function(v) bundle.set("glowEnabled", v); bundle.touch(); ctx.refresh() end }
            e[#e + 1] = { type = "dropdown", label = L["Glow type"], width = 180, height = 50,
              getList = GlowTypeList,
              enabledBy = function() return gated() and bundle.get("glowEnabled") == true end,
              getCurrentKey = function() return GlowTypeLabel(bundle.get("glowType")) end,
              -- Rebuild (NOT refresh) so the Glow color picker's `when` re-evaluates: refresh only re-runs
              -- value refreshers, not the show/hide gates, so the picker wouldn't hide on a type change.
              onSelect = function(label) bundle.set("glowType", GlowTypeFromLabel(label)); bundle.touch(); ctx.rebuild() end }
            e[#e + 1] = { type = "textEditor", label = L["Glow color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              -- The proc + button glows use the NATIVE (uncolored) look, so the color picker doesn't apply.
              when = function() local gt = bundle.get("glowType"); return gt ~= "proc" and gt ~= "button" end,
              enabledBy = function() return gated() and bundle.get("glowEnabled") == true end,
              getColor = function() return bundle.get("glowColor") end,
              onColorChange = function(r, g, b, a) bundle.set("glowColor", { r = r, g = g, b = b, a = a }); bundle.touch() end }
            return e
        end },

        TimerSection(bundle),
        TitleSection(bundle),
        StacksSection(bundle),

        { type = "button", label = L["Copy all group settings"], width = 180, hostHeight = 30,
          onClick = function()
              local function copySection(keys)
                  for _, key in ipairs(keys) do bundle.set(key, CloneVal(bundle.groupGet(key))) end
              end
              copySection({ "showPressOverlay", "showKeybinds" })
              copySection({ "iconW", "iconH" })
              copySection({ "borderEnabled", "borderColor", "borderSize" })
              copySection({ "glowEnabled", "glowType", "glowColor" })
              copySection(TIMER_KEYS)
              copySection(TITLE_KEYS)
              copySection(STACK_KEYS)
              bundle.touch()
              ctx.rebuild()
          end },
    }
    return entries
end
ns.CDMGroups.IconSections = IconSections

-- The per-icon override editor's option tree: binds IconSections to the Config instance `I` + the
-- singleton pencil editor. bundle.* reads/writes the per-icon override store; bundle.refresh is the full
-- Rebuild the shared section helpers expect (the override gates use `when`); ctx routes the editor's own
-- light refresh / full rebuild / reopen.
local function IconOptions(I, sid)
    local function menuRefresh() if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end
    local function menuRebuild() if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end
    local bundle = {
        get      = function(key) return I.IconGet(sid, key) end,
        groupGet = function(key) return I.GGet(I.GroupOf(sid), key) end,
        set      = function(key, val) I.IconSet(sid, key, val) end,
        reset    = function(key) I.IconReset(sid, key) end,
        has      = function(keys)
            for _, key in ipairs(keys) do if I.IconHasOverride(sid, key) then return true end end
            return false
        end,
        touch    = function() I.ApplyAll(); if onIconEditChange then onIconEditChange() end end,
        refresh  = menuRebuild,   -- shared helpers (OverrideToggle/Copy/Timer…) re-render via a full Rebuild
    }
    local ctx = { refresh = menuRefresh, rebuild = menuRebuild, reopen = function() OpenIconEditor(I, sid, onIconEditChange) end }
    return IconSections(I, sid, bundle, ctx)
end

local function EnsureIconEditor()
    if iconEditor then return iconEditor end

    local f = CreateFrame("Frame", "UnbunkUtilityCDGIconEditor", UIParent, "BackdropTemplate")
    f:SetSize(600, 620)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()
    tinsert(UISpecialFrames, "UnbunkUtilityCDGIconEditor")

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    f.title = title

    local titleIconL = f:CreateTexture(nil, "OVERLAY")
    titleIconL:SetSize(20, 20)
    titleIconL:SetPoint("RIGHT", title, "LEFT", -8, 0)
    titleIconL:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.titleIconL = titleIconL

    local titleIconR = f:CreateTexture(nil, "OVERLAY")
    titleIconR:SetSize(20, 20)
    titleIconR:SetPoint("LEFT", title, "RIGHT", 8, 0)
    titleIconR:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.titleIconR = titleIconR

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -6, -6)
    local cb = close:CreateTexture(nil, "BACKGROUND"); cb:SetAllPoints(close); cb:SetColorTexture(0.4, 0.4, 0.4, 1)
    local cf = close:CreateTexture(nil, "BACKGROUND", nil, 1)
    cf:SetPoint("TOPLEFT", 1, -1); cf:SetPoint("BOTTOMRIGHT", -1, 1); cf:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    local cx = close:CreateTexture(nil, "OVERLAY"); cx:SetSize(12, 12); cx:SetPoint("CENTER"); cx:SetTexture(UNBUNK_ICON_CROSS_WHITE)
    close:SetScript("OnEnter", function() local r, g, b = ns.GetBrandColor(); cb:SetColorTexture(r, g, b, 1); cx:SetVertexColor(r, g, b) end)
    close:SetScript("OnLeave", function() cb:SetColorTexture(0.4, 0.4, 0.4, 1); cx:SetVertexColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -44)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)

    local sb = ns.ui.CreateScrollBar({
        parent = f, scrollFrame = scroll, itemHeight = 30, visibleItems = 10,
        getListSize = function()
            local h = content:GetHeight() or 300
            return math.max(10, math.ceil(h / 30))
        end,
    })
    sb.track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 22, 0)
    sb.track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 22, 0)

    f:HookScript("OnShow", function() C_Timer.After(0, function() sb.Update() end) end)

    iconEditor = { frame = f, title = title, titleIconL = titleIconL, titleIconR = titleIconR,
                   scroll = scroll, content = content, sb = sb }
    return iconEditor
end

local function ClearIconMenu(ed)
    if not ed.menu then return end
    if ed.menu.content then ed.menu.content:Hide(); ed.menu.content:ClearAllPoints(); ed.menu.content:SetParent(nil) end
    for _, fr in ipairs(ed.menu.auxFrames or {}) do fr:Hide(); fr:ClearAllPoints(); fr:SetParent(nil) end
    ed.menu = nil
end

function OpenIconEditor(I, sid, onChange)
    local ed = EnsureIconEditor()
    editingI, editingSid = I, sid
    onIconEditChange = onChange
    ed.title:SetText(I.SpellName(sid) or L["Edit icon"])
    local tex = I.SpellTexture(sid)
    if ed.titleIconL then ed.titleIconL:SetTexture(tex) end
    if ed.titleIconR then ed.titleIconR:SetTexture(tex) end

    local function measureContentBottom()
        local top = ed.content:GetTop()
        if not top then return nil end
        local maxDepth = 0
        for i = 1, ed.content:GetNumChildren() do
            local child = select(i, ed.content:GetChildren())
            local bottom = child and child.GetBottom and child:GetBottom()
            if bottom then
                local depth = top - bottom
                if depth > maxDepth then maxDepth = depth end
            end
        end
        return maxDepth
    end
    local function syncHeight()
        if ed.menu then ed.content:SetHeight(math.max(1, ed.menu.height + 12)) end
        ed.sb.Update()
        C_Timer.After(0, function()
            if not (iconEditor and iconEditor.content == ed.content) then return end
            local measured = measureContentBottom()
            if measured then
                local want = math.max(1, measured + 12, (ed.menu and ed.menu.height + 12) or 0)
                if math.abs((ed.content:GetHeight() or 0) - want) > 0.5 then ed.content:SetHeight(want) end
            end
            ed.sb.Update()
        end)
    end
    local rawBuild
    ClearIconMenu(ed)
    ed.menu = ns.ui.BuildMenu(ed.content, IconOptions(I, sid), {
        gap = 10, width = 540, originX = 8, originY = 0, autoHook = false, LSM = LSM,
    })
    rawBuild = ed.menu.Rebuild
    ed.menu.Rebuild = function() rawBuild(); syncHeight() end
    syncHeight()
    ed.menu.Refresh()

    ed.frame:Show()
    ed.frame:Raise()
    ed.scroll:SetVerticalScroll(0)
    C_Timer.After(0, function() ed.sb.Update() end)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- The panel factory, bound to a Config instance `I`. `titleText` / `enableLabel` / `cadreTitle`
-- localise the dest (Essential now).
-- ════════════════════════════════════════════════════════════════════════════════
local function CreatePanel(I, titleText, enableLabel, cadreTitle)
    return function(parent)
        local menu
        local function rebuild() if menu then menu.Rebuild() end end
        local function touch() I.ApplyAll() end

        I.pe = I.pe or {}
        local strips = {}
        local dragTile, dragSid, dragHovered, dragHole
        local dragLayer
        local stopDrag

        local function ensureDragLayer()
            if dragLayer then return dragLayer end
            dragLayer = CreateFrame("Frame", nil, UIParent)
            dragLayer:SetFrameStrata("TOOLTIP")
            dragLayer:SetAllPoints(UIParent)
            return dragLayer
        end

        local function cursorOver(f)
            local l, b, w, h = f:GetRect()
            if not l then return false end
            local s = f:GetEffectiveScale()
            if not (s and s > 0) then return false end
            local mx, my = GetCursorPosition()
            mx, my = mx / s, my / s
            return mx >= l and mx < l + w and my >= b and my < b + h
        end

        local function dragOnUpdate()
            if not dragTile then return end
            if not IsMouseButtonDown("LeftButton") then stopDrag(); return end
            local scale = UIParent:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            if scale and scale > 0 and mx then
                dragTile:ClearAllPoints()
                dragTile:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / scale, my / scale)
            end
            -- The hovered strip yields a DESTINATION: for a real group a table { row, col } or
            -- { newRow = true }; for Unused a plain numeric index. relayout opens the hole there.
            local hovered, hole
            for _, s in ipairs(strips) do
                if s.frame:IsVisible() and cursorOver(s.frame) then
                    hovered = s; hole = s.slotAt(dragSid); break
                end
            end
            dragHovered, dragHole = hovered, hole
            for _, s in ipairs(strips) do s.relayout(dragSid, s == hovered and hole or nil) end
        end

        local driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", dragOnUpdate)

        local function startDrag(tile, spellId)
            dragTile, dragSid, dragHovered, dragHole = tile, spellId, nil, nil
            tile._origParent = tile:GetParent()
            tile:SetParent(ensureDragLayer())
            tile:SetFrameStrata("TOOLTIP")
            tile:Raise()
            driver:Show()
        end

        stopDrag = function()
            local tile = dragTile
            if not tile then return end
            driver:Hide()
            tile:SetParent(tile._origParent or UIParent)
            tile:SetFrameStrata("MEDIUM")
            local sid, hovered, hole = dragSid, dragHovered, dragHole
            dragTile, dragSid, dragHovered, dragHole = nil, nil, nil, nil
            if sid and hovered and hole ~= nil then
                local gid = hovered.groupId
                local full = gid ~= 0 and I.GroupOf(sid) ~= gid
                    and #I.GetGroupBuffs(gid) >= I.GROUP_CAP
                if not full then
                    if gid == 0 then
                        -- Unused stays flat: hole is a numeric index. MoveBuff into its single row.
                        I.MoveBuff(sid, 0, 1, hole)
                    elseif type(hole) == "table" then
                        if hole.newRow then
                            -- Forced new row: a row index past the last starts a brand-new row.
                            I.MoveBuff(sid, gid, math.huge, 0)
                        elseif hole.full then
                            -- Dropped on a maxPerRow-full row: reject (no move) — the icon snaps back.
                        else
                            I.MoveBuff(sid, gid, hole.row, hole.col)
                        end
                    end
                    touch()
                end
            end
            rebuild()
        end

        -- (The old cast-only "+" quick-add picker + its CustomCooldowns.lua engine were removed in
        -- Partie 3 phase F. The essential/utility "+" tiles now open the shared CustomCDM editor via
        -- ns.CustomCDM.PromptAddToGroup, and customs track the real cooldown.)

        -- Build one icon tile button for `spellId` in `frame`. Shared by both strip paths. `undisplayable`
        -- flags a non-displayable cooldown (red); custom icons get an X remove button + a duration-tooltip.
        local function MakeIconTile(frame, groupId, spellId)
            local b = CreateFrame("Button", nil, frame)
            b:SetSize(ICON, ICON)
            local bord = b:CreateTexture(nil, "BACKGROUND")
            bord:SetPoint("TOPLEFT", -1, 1); bord:SetPoint("BOTTOMRIGHT", 1, -1); bord:SetColorTexture(0.4, 0.4, 0.4, 1)
            local tex = b:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); tex:SetTexture(I.SpellTexture(spellId))
            b:RegisterForDrag("LeftButton")
            b:SetScript("OnDragStart", function() startDrag(b, spellId) end)
            b:SetScript("OnDragStop", function() stopDrag() end)

            -- An addon-TRACKER member (BL Tracker, Trinket, …) is keyed by its frame NAME (a string),
            -- not a spellId: it's an addon-drawn icon, always displayable, and has no spell tooltip.
            local isTracker = (type(spellId) == "string") and I.IsTracker and I.IsTracker(spellId)

            -- A NATIVE cooldown that isn't in the CDM's tracked (DISPLAYED) set has no native frame, so in
            -- a real group it can never show: flag the tile RED. A CUSTOM / TRACKER is always displayable;
            -- the Unused strip is never flagged; only flag once the displayed cache is known.
            local undisplayable = groupId ~= 0 and not isTracker and I.DisplayedKnown and I.DisplayedKnown()
                and not (I.IsDisplayable and I.IsDisplayable(spellId))
            if undisplayable then
                tex:SetVertexColor(1, 0.35, 0.35)
                bord:SetColorTexture(0.9, 0.15, 0.15, 1)
                local warn = b:CreateFontString(nil, "OVERLAY")
                warn:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
                warn:SetPoint("CENTER", b, "CENTER", 0, 0)
                warn:SetWordWrap(true)
                warn:SetJustifyH("CENTER")
                warn:SetTextColor(1, 0.45, 0.45)
                warn:SetText((L["Not displayed"]:gsub("%s+", "\n")))
            end

            local isCustom = I.IsCustom and I.IsCustom(spellId)
            -- A CustomCDM icon folded into this group is a tracker member keyed by its frame-name STRING.
            -- It's edited/removed via the shared CustomCDM editor, not the group's per-icon override.
            local isCC = ns.CustomCDM and ns.CustomCDM.IsCustom and ns.CustomCDM.IsCustom(spellId)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local shown = false
                -- A tile keys on the STABLE BASE spellId; resolve the CURRENT display form (keyToDisplay)
                -- so the tooltip matches the tile's live icon/name (Glacial Spike while transformed). Falls
                -- back to the base when the cooldown isn't currently in the pool. Tracker keys (strings) are
                -- untouched.
                local dispSid = spellId
                if type(spellId) == "number" and I.KeyToDisplay and I.KeyToDisplay[spellId] then
                    dispSid = I.KeyToDisplay[spellId]
                end
                -- Skip the spell tooltip for a CUSTOM and a TRACKER (a tracker's key is a frame name, not
                -- a spellId — SetSpellByID would be wrong/error). Both show just the display name instead.
                if not isCustom and not isTracker and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(dispSid) then
                    shown = pcall(GameTooltip.SetSpellByID, GameTooltip, dispSid)
                end
                if not shown then GameTooltip:SetText(I.SpellName(spellId), 1, 1, 1) end
                if isCustom then
                    local def = I.GetCustom and I.GetCustom(spellId)
                    GameTooltip:AddLine(L["Custom cooldown"] .. " (" .. tostring((def and def.duration) or 0) .. "s)", 0.6, 0.8, 1)
                end
                if undisplayable then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["Not in the Cooldown Manager's tracked buffs — it won't display."], 1, 0.3, 0.3, true)
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Pencil: per-icon override editor (hidden on Unused). Tinted brand colour when overridden.
            if groupId ~= 0 then
                local pb = CreateFrame("Button", nil, b)
                pb:SetSize(14, 14); pb:SetPoint("CENTER", b, "TOPLEFT", 4, -4)
                pb:SetFrameLevel(b:GetFrameLevel() + 5)
                local pbg = pb:CreateTexture(nil, "BACKGROUND"); pbg:SetAllPoints(); pbg:SetColorTexture(0, 0, 0, 0.6)
                local pg = pb:CreateTexture(nil, "OVERLAY"); pg:SetPoint("CENTER"); pg:SetSize(10, 10)
                pg:SetTexture(UNBUNK_ICON_PEN_WHITE)
                local function paint() if I.IconHasOverride(spellId) then pg:SetVertexColor(ns.GetBrandColor()) else pg:SetVertexColor(1, 1, 1) end end
                paint()
                pb:SetScript("OnEnter", function() pg:SetVertexColor(ns.GetBrandColor()) end)
                pb:SetScript("OnLeave", paint)
                pb:SetScript("OnClick", function()
                    if isCC and ns.CustomCDM then ns.CustomCDM.PromptEdit(ns.CustomCDM.IdFromFrameName(spellId))
                    else OpenIconEditor(I, spellId, rebuild) end
                end)
            end

            -- An old CDMGroups cast-only custom, OR a CustomCDM icon, gets an X (top-right) that removes it.
            -- A CustomCDM frame routes to CC.ConfirmRemove (deletes the entry + cleans up its group member-
            -- ship via CC.Remove); the old custom uses I.RemoveCustom + frees its drawn frame.
            if isCustom or isCC then
                local xb = CreateFrame("Button", nil, b)
                xb:SetSize(14, 14); xb:SetPoint("CENTER", b, "TOPRIGHT", -7, -3)
                xb:SetFrameLevel(b:GetFrameLevel() + 5)
                local xbg = xb:CreateTexture(nil, "BACKGROUND"); xbg:SetAllPoints(); xbg:SetColorTexture(0, 0, 0, 0.6)
                local xg = xb:CreateTexture(nil, "OVERLAY"); xg:SetPoint("CENTER"); xg:SetSize(10, 10); xg:SetTexture(UNBUNK_ICON_CROSS_WHITE)
                xb:SetScript("OnEnter", function() xg:SetVertexColor(ns.GetBrandColor()) end)
                xb:SetScript("OnLeave", function() xg:SetVertexColor(1, 1, 1) end)
                xb:SetScript("OnClick", function()
                    if isCC and ns.CustomCDM then
                        ns.CustomCDM.ConfirmRemove(ns.CustomCDM.IdFromFrameName(spellId))
                    else
                        if I.RemoveCustom then I.RemoveCustom(spellId) end
                        if I.ReleaseCustomFrame then I.ReleaseCustomFrame(spellId) end
                        touch(); rebuild()
                    end
                end)
            end
            return b
        end

        -- Build one "+" add tile in `frame`, styled like BuffGroups' add tile. onDrop(dest) commits a
        -- dragged icon onto it; onClick adds a custom there. `dest` is the destination passed to MoveBuff.
        local function MakeAddTile(frame, onClick)
            local addb = CreateFrame("Button", nil, frame)
            addb:SetSize(ICON, ICON)
            local abord = addb:CreateTexture(nil, "BACKGROUND")
            abord:SetPoint("TOPLEFT", -1, 1); abord:SetPoint("BOTTOMRIGHT", 1, -1); abord:SetColorTexture(0.4, 0.4, 0.4, 1)
            local afill = addb:CreateTexture(nil, "BACKGROUND", nil, 1); afill:SetAllPoints(); afill:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            local aplus = addb:CreateTexture(nil, "ARTWORK"); aplus:SetPoint("CENTER"); aplus:SetSize(ICON - 12, ICON - 12); aplus:SetTexture(UNBUNK_ICON_PLUS_GREEN)
            addb:SetScript("OnEnter", function() afill:SetColorTexture(0.2, 0.2, 0.2, 0.95) end)
            addb:SetScript("OnLeave", function() afill:SetColorTexture(0.12, 0.12, 0.12, 0.9) end)
            addb:SetScript("OnClick", onClick)
            -- Green drop-target highlight, toggled by relayout when this "+" is the live new-row target.
            function addb.SetDropTarget(on)
                if on then abord:SetColorTexture(0.3, 0.9, 0.3, 1); afill:SetColorTexture(0.16, 0.42, 0.16, 0.95)
                else abord:SetColorTexture(0.4, 0.4, 0.4, 1); afill:SetColorTexture(0.12, 0.12, 0.12, 0.9) end
            end
            return addb
        end

        -- ── The strip ─────────────────────────────────────────────────────────────
        -- groupId 0 = Unused: a FLAT wrap (PER_ROW=12), no "+" tiles, never flagged. A REAL group renders
        -- EXPLICIT ROWS (I.GroupRows) of maxPerRow; each row with room gets an END-of-row "+" tile and a
        -- persistent "new row" "+" sits below the last row. A non-displayable cooldown is flagged RED.
        local function CDStripEntry(groupId)
            local wrap = (groupId == 0)
            return {
                type  = "custom",
                build = function(host)
                    local frame = CreateFrame("Frame", nil, host)
                    frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                    frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)

                    local obj = { frame = frame, groupId = groupId, tiles = {}, wrap = wrap }
                    strips[#strips + 1] = obj

                    -- Place a frame at a (row, col) grid cell (0-based col, 0-based row).
                    local function placeRC(f, row, col)
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * STEP, -(PAD + row * (ICON + GAP_BG)))
                    end

                    if wrap then
                        -- ── Unused: flat wrap, numeric slotAt/relayout (unchanged behaviour) ──
                        for _, sid in ipairs(I.GetGroupBuffs(groupId)) do
                            obj.tiles[#obj.tiles + 1] = { frame = MakeIconTile(frame, groupId, sid), spellId = sid }
                        end

                        local function placeAt(f, slot)
                            placeRC(f, math.floor(slot / PER_ROW), slot % PER_ROW)
                        end

                        function obj.slotAt(dragSpell)
                            local scale = frame:GetEffectiveScale()
                            if not (scale and scale > 0) then return 0 end
                            local mx, my = GetCursorPosition()
                            mx, my = mx / scale, my / scale
                            local idx = 0
                            for _, t in ipairs(obj.tiles) do
                                if t.spellId ~= dragSpell then
                                    local tl, tb = t.frame:GetLeft(), t.frame:GetBottom()
                                    if tl then
                                        local before
                                        if tb then
                                            local tcy  = tb + ICON / 2
                                            local band = (ICON + GAP_BG) / 2
                                            if tcy > my + band then before = true
                                            elseif tcy < my - band then before = false
                                            else before = (tl + ICON / 2) < mx end
                                        else
                                            before = (tl + ICON / 2) < mx
                                        end
                                        if not before then return idx end
                                    end
                                    idx = idx + 1
                                end
                            end
                            return idx
                        end

                        function obj.relayout(dragSpell, holeIndex)
                            local seq = {}
                            for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then seq[#seq + 1] = t end end
                            local slot = 0
                            for i, t in ipairs(seq) do
                                if holeIndex and (i - 1) == holeIndex then slot = slot + 1 end
                                placeAt(t.frame, slot); t.frame:Show()
                                slot = slot + 1
                            end
                        end

                        obj.relayout(nil, nil)

                        local items = #obj.tiles
                        local rows  = math.max(1, math.ceil(math.max(1, items) / PER_ROW))
                        local h = PAD * 2 + rows * ICON + math.max(0, rows - 1) * GAP_BG
                        host:SetHeight(h)
                        return { frame = host, height = h }
                    end

                    -- ── Real group: explicit ROWS + "+" tiles ──────────────────────────────
                    local per = I.MaxPerRow(groupId)
                    local groupRows = I.GroupRows(groupId)
                    -- obj.tiles[i] = { frame, spellId, row (0-based), col (0-based) } for icon tiles.
                    -- obj.addTiles[r] = the end-of-row "+" for row r (0-based); obj.newRowTile = below-rows "+".
                    obj.addTiles = {}
                    obj.rowCount = #groupRows
                    for ri, rowSids in ipairs(groupRows) do
                        for ci, sid in ipairs(rowSids) do
                            obj.tiles[#obj.tiles + 1] = { frame = MakeIconTile(frame, groupId, sid),
                                spellId = sid, row = ri - 1, col = ci - 1 }
                        end
                    end

                    -- The "new row" "+" below the last row: dropping forces a new row; clicking adds a custom there.
                    obj.newRowTile = MakeAddTile(frame, function()
                        if ns.CustomCDM and ns.CustomCDM.PromptAddToGroup then ns.CustomCDM.PromptAddToGroup(I.dest, groupId, math.huge, 0) end
                    end)

                    -- An end-of-row "+" per row that has room (< maxPerRow): dropping appends to that row's
                    -- end; clicking adds a custom there. Rebuilt each relayout to track the live counts.
                    local function ensureRowAddTile(r)
                        if not obj.addTiles[r] then
                            obj.addTiles[r] = MakeAddTile(frame, function()
                                if ns.CustomCDM and ns.CustomCDM.PromptAddToGroup then ns.CustomCDM.PromptAddToGroup(I.dest, groupId, r + 1, math.huge) end
                            end)
                        end
                        return obj.addTiles[r]
                    end

                    -- Row layout: a small "Row N" caption sits ABOVE each row; the icon grid is placed
                    -- below it, so each row is pitched to include the caption band.
                    local ROW_LABEL_H = 13
                    local rowPitch = ROW_LABEL_H + ICON + GAP_BG
                    local function placeCell(f, row, col)   -- 0-based row/col; icons sit BELOW the caption
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * STEP, -(PAD + ROW_LABEL_H + row * rowPitch))
                    end
                    obj.rowLabels = {}
                    local function placeRowLabel(row, text)   -- 0-based row; caption at the band top
                        local fs = obj.rowLabels[row]
                        if not fs then
                            fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            fs:SetTextColor(0.66, 0.66, 0.66)
                            obj.rowLabels[row] = fs
                        end
                        fs:ClearAllPoints()
                        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 1, -(PAD + row * rowPitch))
                        fs:SetText(text); fs:Show()
                    end

                    -- Red "Row is full" caption CENTRED over a row — drawn on a HIGH-level overlay frame
                    -- (above the icon tiles, which are child Buttons that would otherwise hide a plain
                    -- FontString). Shown only while a drag hovers a maxed-out row.
                    local function EnsureFullFrame()
                        if obj.fullFrame then return obj.fullFrame end
                        local f = CreateFrame("Frame", nil, frame)
                        f:SetAllPoints(frame)
                        f:SetFrameLevel((frame:GetFrameLevel() or 1) + 50)
                        obj.fullFrame = f
                        return f
                    end
                    obj.fullLabels = {}
                    local function SetRowFull(row, on)   -- 0-based row
                        local fs = obj.fullLabels[row]
                        if not on then if fs then fs:Hide() end return end
                        if not fs then
                            fs = EnsureFullFrame():CreateFontString(nil, "OVERLAY")
                            fs:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
                            fs:SetTextColor(1, 0.45, 0.45)
                            fs:SetText(L["Row is full"])
                            obj.fullLabels[row] = fs
                        end
                        fs:ClearAllPoints()
                        -- Centre of the row's icon span, vertically centred on the icon band.
                        fs:SetPoint("CENTER", frame, "TOPLEFT", PAD + ((per - 1) * STEP + ICON) / 2,
                            -(PAD + ROW_LABEL_H + row * rowPitch + ICON / 2))
                        fs:Show()
                    end

                    -- Destination cell under the cursor — computed from the SLOT geometry (PAD/STEP/rowPitch),
                    -- NOT the live tile positions, so the preview gap lines up exactly with where the drop
                    -- lands (no off-by-one as tiles shift around). Returns { row, col } (1-based row, 0-based
                    -- col), { newRow = true } when the cursor is below the last row, or { row, full = true }
                    -- when the hovered row is already at maxPerRow.
                    function obj.slotAt(dragSpell)
                        local scale = frame:GetEffectiveScale()
                        local fl, ft = frame:GetLeft(), frame:GetTop()
                        if not (scale and scale > 0 and fl and ft) then return { newRow = true } end
                        local mx, my = GetCursorPosition()
                        mx, my = mx / scale, my / scale
                        local liveRows = obj.layoutRows or {}
                        local nRows = #liveRows
                        -- Row band under the cursor (each row spans rowPitch downward from the frame top).
                        local rowIdx = math.floor((ft - my - PAD) / rowPitch) + 1
                        if rowIdx > nRows then
                            -- Below the last row → a NEW row, UNLESS the last row is still empty (then just
                            -- target that empty row — no point forcing a second empty row below it).
                            if nRows >= 1 and #(liveRows[nRows] or {}) == 0 then return { row = nRows, col = 0 } end
                            return { newRow = true }
                        end
                        if rowIdx < 1 then rowIdx = 1 end
                        local rowTiles = liveRows[rowIdx] or {}
                        -- maxPerRow: a full row can't take another (the dragged icon's OWN row is short one,
                        -- so reordering within a full row still works). Flag it so relayout shows "Row is full".
                        if #rowTiles >= per then return { row = rowIdx, full = true } end
                        -- Insertion column = number of slots whose CENTRE is left of the cursor (geometry).
                        local col = 0
                        while col < #rowTiles and (fl + PAD + col * STEP + ICON / 2) < mx do col = col + 1 end
                        return { row = rowIdx, col = col }
                    end

                    -- Reflow the 2D grid: lay the (non-dragged) tiles out row by row from I.GroupRows. If a
                    -- hole-dest is given, open a one-cell gap at (row, col) (an extra trailing row for
                    -- newRow). Position the per-row end "+" after each non-full row, and the new-row "+"
                    -- below the last row. tileBySid lets us resolve a row's spellId to its tile frame.
                    function obj.relayout(dragSpell, hole)
                        local tileBySid = {}
                        for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then tileBySid[t.spellId] = t end end

                        local holeRow, holeCol, forceNewRow, fullRow
                        if type(hole) == "table" then
                            if hole.newRow then forceNewRow = true
                            elseif hole.full then fullRow = hole.row
                            else holeRow, holeCol = hole.row, hole.col end
                        end

                        local dragging = dragSpell ~= nil
                        -- The stored row the dragged icon came from — counted as still present in that row
                        -- so lifting an icon from a FULL row never pops its "+" (you may drop it right back).
                        local draggedRow
                        if dragSpell then
                            for ri, rowSids in ipairs(groupRows) do
                                for _, sid in ipairs(rowSids) do if sid == dragSpell then draggedRow = ri; break end end
                                if draggedRow then break end
                            end
                        end

                        -- Position the real rows (one per stored row), opening a one-cell GAP at the hole:
                        -- the gap reserves an empty slot so the tiles after it visibly shift to show where
                        -- the dragged icon will land (no marker needed now the slot lines up with the drop).
                        obj.layoutRows = {}
                        for ri, rowSids in ipairs(groupRows) do
                            local liveSids = {}
                            for _, sid in ipairs(rowSids) do
                                if sid ~= dragSpell and tileBySid[sid] then liveSids[#liveSids + 1] = sid end
                            end
                            local gapCol
                            if holeRow == ri then
                                if holeCol == nil or holeCol > #liveSids then gapCol = #liveSids
                                else gapCol = math.max(0, holeCol) end
                            end
                            -- Output cells = the live tiles with a one-slot GAP inserted at 0-based column
                            -- `gapCol` (the empty slot the dragged icon drops into — MoveBuff inserts at that
                            -- same 0-based col, so the visible shift lines up with the real landing).
                            local cells = {}
                            for i = 1, #liveSids do cells[i] = liveSids[i] end
                            if gapCol then table.insert(cells, gapCol + 1, false) end   -- false = the gap
                            local liveRow = {}
                            for c0 = 1, #cells do
                                local cell = cells[c0]
                                if cell ~= false then   -- a `false` cell is the gap: leave that column empty
                                    local t = tileBySid[cell]
                                    placeCell(t.frame, ri - 1, c0 - 1); t.frame:Show()
                                    liveRow[#liveRow + 1] = t
                                end
                            end
                            obj.layoutRows[#obj.layoutRows + 1] = liveRow
                            placeRowLabel(ri - 1, L["Row %d"]:format(ri))   -- "Row N" caption above the row
                            SetRowFull(ri - 1, fullRow == ri)               -- red "Row is full" while hovered
                            -- End-of-row "+" — kept visible during a drag too. The row counts the LIFTED
                            -- icon as still its own (draggedRow), so a full row you're reordering within
                            -- never pops a "+". Positioned after the live cells (incl. the gap).
                            local at = ensureRowAddTile(ri - 1)
                            local rowCount = #liveRow + ((draggedRow == ri) and 1 or 0)
                            if rowCount < per then placeCell(at, ri - 1, #cells); at:Show()
                            else at:Hide() end
                        end
                        if #obj.layoutRows == 0 then obj.layoutRows[1] = {} end
                        local nRows = #obj.layoutRows

                        -- Hide any stale end-"+" / captions / full-labels beyond the live row count.
                        for rk, t in pairs(obj.addTiles) do if rk + 1 > nRows then t:Hide() end end
                        for rk, fs in pairs(obj.rowLabels) do if rk + 1 > nRows then fs:Hide() end end
                        for rk, fs in pairs(obj.fullLabels) do if rk + 1 > nRows then fs:Hide() end end

                        -- New-row "+": below the last row — but ONLY when that last row already has icons.
                        -- An empty last row (e.g. a brand-new group) already accepts the next icon via its
                        -- own row "+", so a second "+" below it is pointless. On a forced new row the icon
                        -- lands at col 0, so SHIFT the "+" right to col 1.
                        -- Use the STORED last row (the dragged icon still belongs to it) so the new-row "+"
                        -- doesn't vanish while you drag the last row's only icon out of it.
                        local lastEmpty = #(groupRows[#groupRows] or {}) == 0
                        if lastEmpty then
                            obj.newRowTile:Hide()
                        else
                            placeCell(obj.newRowTile, nRows, forceNewRow and 1 or 0)
                            obj.newRowTile:Show()
                        end
                    end

                    obj.relayout(nil, nil)

                    -- Height: each captioned row band + one trailing band for the new-row "+".
                    local nRows = math.max(1, #obj.layoutRows)
                    local h = PAD * 2 + (nRows + 1) * rowPitch
                    host:SetHeight(h)
                    return { frame = host, height = h }
                end,
            }
        end

        -- ── Per-group Icon size (W / H) ────────────────────────────────────────────
        local function IconSizeEntry(id)
            return {
                type = "custom", height = 30,
                build = function(host)
                    local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                    wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); wLbl:SetText(L["W"])
                    local wInput = ns.ui.CreateTextInput({
                        parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                        text = tostring(I.GGet(id, "iconW") or 44),
                        onEnter = function(v) if v and v > 0 then I.GSet(id, "iconW", v); touch() end end,
                    })
                    wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                    local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                    hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                    local hInput = ns.ui.CreateTextInput({
                        parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                        text = tostring(I.GGet(id, "iconH") or 44),
                        onEnter = function(v) if v and v > 0 then I.GSet(id, "iconH", v); touch() end end,
                    })
                    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                    return { frame = host, height = 30, Refresh = function()
                        wInput.SetText(tostring(I.GGet(id, "iconW") or 44))
                        hInput.SetText(tostring(I.GGet(id, "iconH") or 44))
                    end }
                end,
            }
        end

        local function GroupBundle(id)
            return {
                get   = function(key) return I.GGet(id, key) end,
                set   = function(key, val) I.GSet(id, key, val) end,
                reset = nil,
                touch = touch,
                refresh = rebuild,
            }
        end

        -- The X / Y numeric inputs + Unlock/Lock toggle (the `position` widget). Lives at the TOP of the
        -- Position sub-cadre now. Drag writes posX/posY (the group's screen-center offset).
        local function PositionBlock(id)
            return { type = "position", ref = "pe",
                onBuilt = function(w) I.pe[id] = w end,
                label = L["Position (offset from screen center)"],
                getX = function() return I.GGet(id, "posX") end,
                getY = function() return I.GGet(id, "posY") end,
                onApply = function(x, yv)
                    if x  then I.GSet(id, "posX", x)  end
                    if yv then I.GSet(id, "posY", yv) end
                    touch()
                end,
                onUnlock   = function() I.SetGroupUnlocked(id, true) end,
                onLock     = function() I.SetGroupUnlocked(id, false); if I.pe[id] then I.pe[id].Refresh() end end,
                isUnlocked = function() return I.IsGroupUnlocked(id) end }
        end

        -- The CDM settings sub-cadre (FIRST in Group settings): the two CDM-display toggles (press overlay
        -- + keybinds), then the group LAYOUT controls (grow direction, static display, spacing). Those
        -- three are per-GROUP (the engine reads them per group in RefreshLayout), so they live here, not in
        -- the per-icon override editor.
        local function CDMSettingsGroup(id)
            return { type = "group", title = L["CDM settings"], build = function() return {
                { type = "checkbox", label = L["Show press overlay"],
                  get = function() return I.GGet(id, "showPressOverlay") == true end,
                  set = function(v) I.GSet(id, "showPressOverlay", v and true or false); touch() end },
                { type = "checkbox", label = L["Show Keybinds"],
                  get = function() return I.GGet(id, "showKeybinds") == true end,
                  set = function(v) I.GSet(id, "showKeybinds", v and true or false); touch() end },
                { type = "dropdown", label = L["Grow direction"], width = 180, height = 50,
                  getList = GrowList,
                  getCurrentKey = function() return GrowLabel(I.GGet(id, "growDir")) end,
                  onSelect = function(label) I.GSet(id, "growDir", GrowFromLabel(label)); touch() end },
                { type = "checkbox", label = L["Static Display"],
                  get = function() return I.GGet(id, "staticDisplay") == true end,
                  set = function(v) I.GSet(id, "staticDisplay", v and true or false); touch() end },
                { type = "textinput", label = L["Spacing"], width = 46, numeric = true, min = 0, max = 64, maxLetters = 2,
                  get = function() return I.GGet(id, "spacing") or 1 end,
                  set = function(v) if v ~= nil then I.GSet(id, "spacing", v); touch() end end },
            } end }
        end

        -- The Rows sub-cadre: "Max icon per row" → the group's maxPerRow. Changing it re-chunks the strip
        -- + the in-game layout (rebuild re-derives I.GroupRows). 1..20.
        local function RowsGroup(id)
            return { type = "group", title = L["Rows"], build = function() return {
                { type = "textinput", label = L["Max icon per row"], width = 46, numeric = true, min = 1, max = 20, maxLetters = 2,
                  get = function() return I.GGet(id, "maxPerRow") or 6 end,
                  set = function(v) if v and v >= 1 then I.GSet(id, "maxPerRow", math.floor(v)); touch(); rebuild() end end },
            } end }
        end

        -- The Position sub-cadre: just X/Y(/Unlock). Grow direction / Static Display / Spacing moved up to
        -- the CDM settings sub-cadre. NO "Anchor to" / Placement dropdowns (groups are screen-center).
        local function PositionGroup(id)
            return { type = "group", title = L["Position"], build = function() return {
                PositionBlock(id),
            } end }
        end

        local function BorderGroup(id)
            return { type = "group", title = L["Border"], build = function() return {
                { type = "checkbox", label = L["Show border"],
                  get = function() return I.GGet(id, "borderEnabled") ~= false end,
                  set = function(v) I.GSet(id, "borderEnabled", v); touch(); if menu then menu.Refresh() end end },
                { type = "textEditor", label = L["Border color"],
                  showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                  enabledBy = function() return I.GGet(id, "borderEnabled") ~= false end,
                  getColor = function() return I.GGet(id, "borderColor") end,
                  onColorChange = function(r, g, b, a) I.GSet(id, "borderColor", { r = r, g = g, b = b, a = a }); touch() end },
                { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
                  enabledBy = function() return I.GGet(id, "borderEnabled") ~= false end,
                  get = function() return I.GGet(id, "borderSize") or 1 end,
                  set = function(v) if v and v > 0 then I.GSet(id, "borderSize", v); touch() end end },
            } end }
        end

        local function GlowGroup(id)
            return { type = "group", title = L["Glow"], build = function() return {
                { type = "checkbox", label = L["Show glow on proc"],
                  get = function() return I.GGet(id, "glowEnabled") == true end,
                  set = function(v) I.GSet(id, "glowEnabled", v); touch(); if menu then menu.Refresh() end end },
                { type = "dropdown", label = L["Glow type"], width = 180, height = 50,
                  getList = GlowTypeList,
                  enabledBy = function() return I.GGet(id, "glowEnabled") == true end,
                  getCurrentKey = function() return GlowTypeLabel(I.GGet(id, "glowType")) end,
                  -- Rebuild (NOT Refresh) so the Glow color picker's `when` re-evaluates (Refresh only
                  -- re-runs value refreshers, not the show/hide gates).
                  onSelect = function(label) I.GSet(id, "glowType", GlowTypeFromLabel(label)); touch()
                      if menu then menu.Rebuild() end end },
                { type = "textEditor", label = L["Glow color"],
                  showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                  -- The proc + button glows use the NATIVE (uncolored) look, so the color picker doesn't apply.
                  when = function() local gt = I.GGet(id, "glowType"); return gt ~= "proc" and gt ~= "button" end,
                  enabledBy = function() return I.GGet(id, "glowEnabled") == true end,
                  getColor = function() return I.GGet(id, "glowColor") end,
                  onColorChange = function(r, g, b, a) I.GSet(id, "glowColor", { r = r, g = g, b = b, a = a }); touch() end },
            } end }
        end

        local function IconsGroup(id)
            return { type = "group", title = L["Icons"], build = function()
                local b = GroupBundle(id)
                return {
                    { type = "label", font = "UnbunkUtilityH6", height = 18, text = L["Icon size"] },
                    IconSizeEntry(id),
                    TimerSection(b),
                    TitleSection(b),
                    StacksSection(b),
                }
            end }
        end

        local function GroupSettingsSection(id)
            return { type = "section", label = L["Group settings"], showCheckbox = false,
              headerExtra = ns.ui.SettingsHeaderIcon,
              getCollapsed = function() return I.GGet(id, "cfgCollapsed") ~= false end,
              onCollapse   = function(c)
                  I.GSet(id, "cfgCollapsed", c and true or false)
                  if C_Timer and C_Timer.After then C_Timer.After(0, rebuild) else rebuild() end
              end,
              build = function() return {
                CDMSettingsGroup(id),
                RowsGroup(id),
                PositionGroup(id),
                BorderGroup(id),
                GlowGroup(id),
                IconsGroup(id),
            } end }
        end

        local function GroupCadre(id)
            local title = (I.GGet(id, "name") or ("Group " .. id))
            return { type = "group", title = title, build = function()
                local e = {
                    { type = "textinput", label = L["Group name"], width = 200, maxLetters = 32,
                      get = function() return I.GGet(id, "name") or "" end,
                      set = function(v) I.GSet(id, "name", v or ""); rebuild() end },
                    CDStripEntry(id),
                    { type = "button", label = L["Copy native CDM order"], width = 200, hostHeight = 30,
                      onClick = function() I.SortGroupNativeOrder(id); touch(); rebuild() end },
                    GroupSettingsSection(id),
                }
                if id ~= 1 then
                    e[#e + 1] = { type = "button", label = L["Delete group"], width = 160, hostHeight = 30,
                        onClick = function() I.RemoveGroup(id); touch(); rebuild() end }
                end
                return e
            end }
        end

        local function UnusedCadre()
            return { type = "group", title = L["Unused"], build = function() return {
                { type = "label", font = "UnbunkUtilityH6", height = 18,
                  text = L["Cooldowns here are hidden. Drag them onto a group to show them."] },
                CDStripEntry(0),
            } end }
        end

        local options = {
            { type = "label", font = "UnbunkUtilityH2", height = 26, text = titleText },
            -- The engine enable, OUTSIDE the cadre. Default ON. Greys the whole cadre below when off;
            -- Refresh() re-applies on toggle, forcing a CDMAnchor refresh so the OLD bucket system
            -- releases / re-takes the Essential viewer immediately.
            { type = "checkbox", label = enableLabel,
              get = function() return I.Enabled() end,
              set = function(v)
                  I.SetEnabled(v)
                  if I.HookNativeViewer then I.HookNativeViewer() end
                  touch()
                  -- Drive OUR engine on the toggle: enabling re-pins/re-styles; disabling runs HideAll
                  -- which releases our pins AND restores the native viewer (M1 — otherwise Unused
                  -- members pinned offscreen stay there until Blizzard next relayouts).
                  if I.RefreshLayout then I.RefreshLayout() end
                  if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                  if menu then menu.Refresh() end
              end },
            { type = "group", title = cadreTitle,
              enabledBy = function() return I.Enabled() end,
              build = function()
                wipe(strips)
                local entries = {}
                for _, g in ipairs(I.GroupList()) do
                    entries[#entries + 1] = GroupCadre(g.id)
                end
                entries[#entries + 1] = { type = "button", label = L["Create group"], width = 160, hostHeight = 30,
                    onClick = function() I.NewGroup(); touch(); rebuild() end }
                entries[#entries + 1] = UnusedCadre()
                return entries
            end },
        }

        menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })

        -- When the user edits the CDM tracked cooldowns in EditMode the engine's ticker / viewer hook
        -- detects the DISPLAYED-set (pool) change and calls this. Rebuild the strip so a tile's red flag
        -- + its tooltip's red line re-evaluate (both derive from I.DisplayedKnown()/I.IsDisplayed), and
        -- re-open the per-icon editor for the same icon if it's open. Cheap no-op when the panel isn't
        -- shown (the engine only fires this on an actual change, never every tick). Mirrors BuffGroups.
        I.onDisplayedChanged = function()
            if menu and parent and parent:IsShown() then rebuild() end
            if iconEditor and iconEditor.frame and iconEditor.frame:IsShown()
                and editingI == I and editingSid then
                OpenIconEditor(I, editingSid, onIconEditChange)
            end
        end

        parent:HookScript("OnHide", function()
            for _, g in ipairs(I.GroupList()) do
                I.GSet(g.id, "cfgCollapsed", true)
            end
        end)
        parent:HookScript("OnShow", function()
            if menu then menu.Rebuild() end
        end)

        return menu
    end
end

local initCDG = CreateFrame("Frame")
initCDG:RegisterEvent("ADDON_LOADED")
initCDG:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    local E = ns.CDMGroups and ns.CDMGroups.essential
    if E then
        -- ESSENTIAL groups tab: registered as L["Essential"] (distinct from the OLD bucket panel's
        -- L["Essentials"], so no clash) — the nav points its single "Essential" entry here.
        UnbunkUtility.RegisterModule(
            L["Essential"], nil,
            CreatePanel(E, L["Essential"], L["Enable custom CDM Essential"], L["Cooldown groups"]))
    end
    local U = ns.CDMGroups and ns.CDMGroups.utility
    if U then
        -- UTILITY groups tab. Unlike Essential there's no spare plural to avoid the name clash with the
        -- OLD bucket panel (also L["Utility"]). CDMGroups loads AFTER GeneralSettings (see the .toc), so
        -- registering under L["Utility"] here SUPERSEDES the old bucket panel in the registry — exactly
        -- the intent: the nav's single { panel = L["Utility"] } entry now resolves to THIS groups panel
        -- (the old bucket createFn is harmlessly dropped; nothing else references it). The CDMGroups
        -- engine OwnsDest("utility") so the old CDMAnchor utility bucket yields automatically.
        UnbunkUtility.RegisterModule(
            L["Utility"], nil,
            CreatePanel(U, L["Utility"], L["Enable custom CDM Utility"], L["Cooldown groups"]))
    end
    self:UnregisterEvent("ADDON_LOADED")
end)
