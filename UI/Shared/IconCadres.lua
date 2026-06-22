-- UI/Shared/IconCadres.lua
-- ════════════════════════════════════════════════════════════════════════════════
-- SHARED icon-customization "cadres" (BuildMenu sections), bundle-driven, used by
-- EVERY icon config in the addon: the native CDM per-icon override editor (CDMGroups),
-- the 7 addon trackers (via CDMGroups.TrackerFreeCadres/TrackerCdmCadres), the buff
-- groups (BuffGroups), and the custom-icon editor (CustomCDM). Before this module those
-- cadres were copy-pasted across three 700–1800 line files; here they live ONCE.
--
-- THE BUNDLE CONTRACT — every cadre reads/writes config only through a `bundle`, never
-- naming a group/spell id directly:
--   bundle.get(key)        -> effective value (override → group/default)
--   bundle.set(key, val)
--   bundle.touch()         -- re-apply the icon in game
--   bundle.refresh()|nil   -- re-measure/redraw the host menu (row count / greying changes)
--   -- OVERRIDE mode ONLY (nil in free/group mode → controls always live, no toggle):
--   bundle.groupGet(key)|nil   bundle.has(keys)|nil   bundle.reset(key)|nil
--   bundle.stashGet(key)|nil   bundle.stashSet(key,val)|nil  -- remember values across off/on
--
-- A cadre auto-adapts: when bundle.has/reset exist it's an OVERRIDE cadre (the
-- "Override group settings" checkbox + "Copy group settings" button + greying appear);
-- otherwise it's a FREE/GROUP cadre (plain controls). The KEY NAMES are identical across
-- worlds (showTimer, timer*/title*/stack*, border*, glow*, showPressOverlay/showKeybinds)
-- EXCEPT icon-size (iconW/iconH override vs iconWidth/iconHeight free) and sound (two
-- schemas) — both parameterised below.
-- ════════════════════════════════════════════════════════════════════════════════

local _, ns = ...
ns.ui = ns.ui or {}
local IC = {}
ns.ui.IconCadres = IC

local L   = ns.L
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ── tiny plumbing ───────────────────────────────────────────────────────────────
-- Append a non-nil entry (skips the override toggle / copy button in free/group mode).
local function append(list, extra) if extra then list[#list + 1] = extra end return list end

-- Recursive value clone so an icon override never aliases/mutates the group's table
-- (colours {r,g,b,a} or the timerThresholds list); scalars pass through.
local function CloneVal(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = CloneVal(val) end
    return out
end
IC.CloneVal = CloneVal

-- Specialised clone for the timer-threshold list (preserves the colour RGBA structure).
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

-- ── Glow-type enum (moved here from CDMGroups; re-exported there for back-compat) ──
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
IC.GlowTypeList      = GlowTypeList
IC.GlowTypeLabel     = GlowTypeLabel
IC.GlowTypeFromLabel = GlowTypeFromLabel

-- ── override infrastructure ───────────────────────────────────────────────────────
-- "Override group settings" — per-section checkbox at the TOP of an override cadre (nil in
-- free/group mode). Checked = the section is overridden (ANY of `keys` has a raw override,
-- via bundle.has). Checking it seeds each key to the current effective value (stash, else
-- group), deep-cloned so a table value doesn't alias the group's; unchecking resets each
-- key (stashing it first so re-checking restores it). Either way touch()+refresh().
local function OverrideToggle(bundle, keys, label)
    if not bundle.reset or not bundle.has then return nil end
    return { type = "checkbox", label = label or L["Override group settings"],
        get = function() return bundle.has(keys) end,
        set = function(v)
            if v then
                for _, key in ipairs(keys) do
                    local prev = bundle.stashGet and bundle.stashGet(key)
                    -- explicit nil test, NOT `prev ~= nil and prev or group` — a stashed boolean
                    -- false (showTitle/showStack/borderEnabled) would collapse through and/or.
                    local val; if prev ~= nil then val = prev else val = bundle.get(key) end
                    bundle.set(key, CloneVal(val))
                end
            else
                for _, key in ipairs(keys) do
                    if bundle.stashSet then bundle.stashSet(key, CloneVal(bundle.get(key))) end
                    bundle.reset(key)
                end
            end
            bundle.touch()
            if bundle.refresh then bundle.refresh() end
        end }
end
IC.OverrideToggle = OverrideToggle

-- "Copy group settings" — re-syncs the overriding section to the group's CURRENT values
-- (deep-cloned). Reads via bundle.groupGet (pure group read). Greyed while inheriting.
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
IC.CopyGroupButton = CopyGroupButton

-- enabledBy predicate: a section's inner controls grey out while it INHERITS the group;
-- light up once overridden. Returns nil in free/group mode (controls always live).
local function SectionOverridden(bundle, keys)
    if not bundle.has then return nil end
    return function() return bundle.has(keys) end
end
IC.SectionOverridden = SectionOverridden

-- A generic "is this section editable?" gate for cadres that build their key list inline:
-- override mode → only when overridden; free/group mode → always.
local function gatedFor(bundle, keys)
    return function()
        if bundle.has then return bundle.has(keys) end
        return true
    end
end
IC.gatedFor = gatedFor

-- Resolve the (refresh, rebuild, reopen) callbacks a cadre uses for greying / row-count /
-- editor re-open. Override cadres pass opts.ctx (the editor's light/full/reopen); free
-- cadres fall back to bundle.refresh for all three.
local function rfns(bundle, opts)
    local ctx = (opts and opts.ctx) or {}
    local function noop() end
    return (ctx.refresh or bundle.refresh or noop),
           (ctx.rebuild or bundle.refresh or noop),
           (ctx.reopen  or bundle.refresh or noop)
end

-- ── styled-text + position sub-editors (shared by Timer/Title/Stacks) ──────────────
-- Font / size / colour / outline editor for a `prefix` text block:
-- "timer" -> timerFontKey/timerFontPath/timerFontSize/timerColor/timerOutline.
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
IC.StyleEditorFor = StyleEditorFor

-- Anchor dropdown + X / Y offsets for a `prefix` text block (uses the SCREEN anchor list
-- from Core/Shared.lua: Center / edges / inside corners).
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
IC.PosOffsetFor = PosOffsetFor

-- Time-thresholds list editor (one row per tier: At seconds / size mult / colour / remove
-- + "Add threshold"). EVERY write clones the list first so a per-icon edit never mutates
-- the group's (or the shared default) list. `sectionGate` (override) ANDs the section-
-- override gate onto the thresholds-enabled gate.
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
IC.ThresholdsEditor = ThresholdsEditor

-- ── Timer / Title / Stacks sections ───────────────────────────────────────────────
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
        e[#e + 1] = ThresholdsEditor(bundle, gated)
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
    "showStack", "showAtZero", "stackShowZero", "darkenOnCdWithStacks",
    "stackFontKey", "stackFontPath", "stackFontSize", "stackOutline",
    "stackColor", "stackPos", "stackOffX", "stackOffY",
}
-- opts.cd = true for the spell/item variants (cooldowns + charges): adds the "Show at 0 stacks" (count text)
-- and "Darken icon when on cd with stacks" toggles. Buffs pass nothing (those two don't apply to them).
local function StacksSection(bundle, opts)
    opts = opts or {}
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
        if opts.cd then
            -- Draw the count as "0" when it reaches zero instead of hiding it. Default ON.
            e[#e + 1] = { type = "checkbox", ref = "stackshowzero", label = L["Show at 0 stacks"], enabledBy = gated,
                  get = function() return bundle.get("stackShowZero") ~= false end,
                  set = function(v) bundle.set("stackShowZero", v); bundle.touch() end }
            -- OFF (default): a cooldown keeps the icon lit while a charge/stack is still usable, greying it
            -- only once none remain. ON: the icon greys on cooldown regardless of remaining charges.
            e[#e + 1] = { type = "checkbox", ref = "darkenoncdwithstacks", label = L["Darken icon when on cd with stacks"], enabledBy = gated,
                  get = function() return bundle.get("darkenOnCdWithStacks") == true end,
                  set = function(v) bundle.set("darkenOnCdWithStacks", v and true or false); bundle.touch() end }
        end
        local style = StyleEditorFor(bundle, "stack"); style.enabledBy = gated; e[#e + 1] = style
        local pos = PosOffsetFor(bundle, "stack"); pos.enabledBy = gated; e[#e + 1] = pos
        return e
      end }
end

IC.Timer       = TimerSection
IC.Title       = TitleSection
IC.Stacks      = StacksSection
IC.SectionKeys = { timer = TIMER_KEYS, title = TITLE_KEYS, stack = STACK_KEYS }

-- ── per-cadre builders (each returns ONE BuildMenu entry, override/free auto-adapting) ──

-- CDM settings: flash the icon while its action-bar keybind is HELD (press overlay) +
-- draw that keybind on the icon. Both opt-in (default off).
function IC.CdmSettings(bundle)
    return { type = "group", title = L["CDM settings"], build = function()
        local keys  = { "showPressOverlay", "showKeybinds" }
        local gated = gatedFor(bundle, keys)
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
    end }
end

-- Icon size (W / H). opts.kw/kh = the two keys (iconW/iconH override+group, iconWidth/
-- iconHeight free); opts.bare = a row WITHOUT the group wrapper/override toggle (for use
-- inside an "Icon" group) — with an H4 "Icon size" label unless opts.label == false (the
-- group panels print their own label above it); opts.max (256 override / 512 free);
-- opts.sizeApply (free trackers need a special re-apply after a resize, else bundle.touch).
function IC.IconSize(bundle, opts)
    opts = opts or {}
    local kw   = opts.kw or "iconW"
    local kh   = opts.kh or "iconH"
    local dW   = opts.defaultW or 44
    local dH   = opts.defaultH or 44
    local maxv = opts.max or 256
    local function apply() if opts.sizeApply then opts.sizeApply() else bundle.touch() end end

    local function row(withLabel, enabledBy)
        local h = withLabel and 46 or 30
        return { type = "custom", height = h, enabledBy = enabledBy, build = function(host)
            local yTop = 0
            if withLabel then
                local sLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                sLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sLbl:SetText(L["Icon size"])
                yTop = 20
            end
            local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -yTop); wLbl:SetText(L["W"])
            local wInput = ns.ui.CreateTextInput({
                parent = host, width = 46, height = 22, numeric = true, min = 8, max = maxv, maxLetters = 3,
                text = tostring(bundle.get(kw) or dW),
                onEnter = function(v) if v and v > 0 then bundle.set(kw, v); apply() end end,
            })
            wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
            local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
            local hInput = ns.ui.CreateTextInput({
                parent = host, width = 46, height = 22, numeric = true, min = 8, max = maxv, maxLetters = 3,
                text = tostring(bundle.get(kh) or dH),
                onEnter = function(v) if v and v > 0 then bundle.set(kh, v); apply() end end,
            })
            hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
            return { frame = host, height = h, Refresh = function()
                wInput.SetText(tostring(bundle.get(kw) or dW))
                hInput.SetText(tostring(bundle.get(kh) or dH))
            end }
        end }
    end

    if opts.bare then return row(opts.label ~= false, nil) end
    return { _omit = "size", type = "group", title = L["Icon size"], build = function()
        local keys  = { kw, kh }
        local gated = gatedFor(bundle, keys)
        local e = {}
        append(e, OverrideToggle(bundle, keys))
        append(e, CopyGroupButton(bundle, keys, gated))
        e[#e + 1] = row(false, gated)
        return e
    end }
end

-- Border (enable / colour / thickness). opts.defaultOn: override/group default ON
-- (borderEnabled ~= false); free default OFF (borderEnabled == true). opts.when on the group.
function IC.Border(bundle, opts)
    opts = opts or {}
    local defaultOn = opts.defaultOn
    local function isOn() local v = bundle.get("borderEnabled"); if defaultOn then return v ~= false else return v == true end end
    local refresh = (rfns(bundle, opts))
    return { type = "group", title = L["Border"], when = opts.when, build = function()
        local keys  = { "borderEnabled", "borderColor", "borderSize" }
        local gated = gatedFor(bundle, keys)
        local e = {}
        append(e, OverrideToggle(bundle, keys))
        append(e, CopyGroupButton(bundle, keys, gated))
        e[#e + 1] = { type = "checkbox", label = L["Show border"], enabledBy = gated,
          get = function() return isOn() end,
          set = function(v) bundle.set("borderEnabled", v); bundle.touch(); refresh() end }
        e[#e + 1] = { type = "textEditor", label = L["Border color"],
          showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
          enabledBy = function() return gated() and isOn() end,
          getColor = function() return bundle.get("borderColor") end,
          onColorChange = function(r, g, b, a) bundle.set("borderColor", { r = r, g = g, b = b, a = a }); bundle.touch() end }
        e[#e + 1] = { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
          enabledBy = function() return gated() and isOn() end,
          get = function() return bundle.get("borderSize") or 1 end,
          set = function(v) if v and v > 0 then bundle.set("borderSize", v); bundle.touch() end end }
        return e
    end }
end

-- Glow. opts.variant "proc" (Spell/Item: "Show glow on proc" + glow-type dropdown +
-- colour hidden for proc/button native looks) | "buff" ("Show glow" + colour always).
-- opts.keys = override-tracking keys (buff = {glowEnabled,glowColor}; proc adds glowType).
function IC.Glow(bundle, opts)
    opts = opts or {}
    local variant = opts.variant or "buff"
    local keys    = opts.keys or ((variant == "proc") and { "glowEnabled", "glowType", "glowColor" } or { "glowEnabled", "glowColor" })
    local refresh, rebuild = rfns(bundle, opts)
    return { type = "group", title = L["Glow"], when = opts.when, build = function()
        local gated = gatedFor(bundle, keys)
        local e = {}
        append(e, OverrideToggle(bundle, keys))
        append(e, CopyGroupButton(bundle, keys, gated))
        e[#e + 1] = { type = "checkbox", label = (variant == "proc") and L["Show glow on proc"] or L["Show glow"], enabledBy = gated,
          get = function() return bundle.get("glowEnabled") == true end,
          set = function(v) bundle.set("glowEnabled", v and true or false); bundle.touch(); refresh() end }
        if variant == "proc" then
            e[#e + 1] = { type = "dropdown", label = L["Glow type"], width = 200, height = 50,
              getList = GlowTypeList,
              enabledBy = function() return gated() and bundle.get("glowEnabled") == true end,
              getCurrentKey = function() return GlowTypeLabel(bundle.get("glowType")) end,
              -- rebuild (NOT refresh) so the colour picker's `when` re-evaluates for the new type.
              onSelect = function(label) bundle.set("glowType", GlowTypeFromLabel(label)); bundle.touch(); rebuild() end }
        end
        e[#e + 1] = { type = "textEditor", label = L["Glow color"],
          showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
          -- proc + button glows use the NATIVE (uncolored) look → hide the swatch (proc variant only).
          when = (variant == "proc") and function() local gt = bundle.get("glowType"); return gt ~= "proc" and gt ~= "button" end or nil,
          enabledBy = function() return gated() and bundle.get("glowEnabled") == true end,
          getColor = function() return bundle.get("glowColor") end,
          onColorChange = function(r, g, b, a) bundle.set("glowColor", { r = r, g = g, b = b, a = a }); bundle.touch() end }
        return e
    end }
end

-- Default sound rows per variant (the two-slot "Sound alert" cadre). Spell/Item =
-- "Sound on use" / "Sound when ready"; Buff = "Sound when buff start" / "Sound when buff
-- stop". Both default to the soundStart*/soundStop* key schema; CustomCDM overrides with
-- its own keys + onTest via opts.rows.
function IC.SoundRows(variant)
    if variant == "buff" then
        return {
            { label = L["Sound when buff start"], keySound = "soundStartSound", keyPath = "soundStartPath", keyEnabled = "soundStartEnabled" },
            { label = L["Sound when buff stop"],  keySound = "soundStopSound",  keyPath = "soundStopPath",  keyEnabled = "soundStopEnabled"  },
        }
    end
    return {
        { label = L["Sound on use"],     keySound = "soundStartSound", keyPath = "soundStartPath", keyEnabled = "soundStartEnabled" },
        { label = L["Sound when ready"], keySound = "soundStopSound",  keyPath = "soundStopPath",  keyEnabled = "soundStopEnabled"  },
    }
end

-- Sound alert cadre. opts.rows = list of { label, keySound, keyPath, keyEnabled, onTest? }.
-- Default onTest plays the chosen custom file, else fetches the LSM sound.
function IC.Sound(bundle, opts)
    opts = opts or {}
    local rows = opts.rows or IC.SoundRows(opts.variant)
    return { _omit = "sound", type = "group", title = opts.title or L["Sound alert"], build = function()
        local e = {}
        for _, r in ipairs(rows) do
            e[#e + 1] = { type = "sound", LSM = LSM, label = r.label,
              getKey    = function() return bundle.get(r.keySound) end,
              getEnable = function() return bundle.get(r.keyEnabled) == true end,
              onSelect  = function(key, path) bundle.set(r.keySound, key); bundle.set(r.keyPath, path) end,
              onToggle  = function(v) bundle.set(r.keyEnabled, v and true or false) end,
              onTest    = r.onTest or function()
                  local p = bundle.get(r.keyPath)
                  if p then PlaySoundFile(p, "Master")
                  else local k = bundle.get(r.keySound); local res = LSM and k and LSM:Fetch("sound", k); if res then PlaySoundFile(res, "Master") end end
              end }
        end
        return e
    end }
end

-- Icon position (offset) widget — thin wrapper over the BuildMenu "position" primitive.
function IC.Position(opts)
    opts = opts or {}
    return { type = "position", ref = opts.ref or "pe",
        onBuilt    = opts.onBuilt,
        label      = opts.label or L["Icon position (offset from screen center)"],
        getX       = opts.getX, getY = opts.getY, onApply = opts.onApply,
        onUnlock   = opts.onUnlock, onLock = opts.onLock, isUnlocked = opts.isUnlocked }
end

-- ── assemblers ─────────────────────────────────────────────────────────────────────
-- "Override settings" cadre set, bound to a per-icon OVERRIDE bundle (+ ctx for the
-- editor's light/full/reopen). opts.type "spellitem" (adds CDM settings, proc glow) |
-- "buff" (no CDM settings, buff glow). opts.omit.{label,sound,placeholder,size} drops
-- those chrome entries (trackers omit sound+placeholder+label; below-player omits size).
-- opts.soundRows overrides the sound slots; opts.append = extra trailing entries.
function IC.OverrideSet(bundle, ctx, opts)
    opts = opts or {}
    local omit = opts.omit or {}
    local typ  = opts.type or "spellitem"
    local glowVariant = (typ == "buff") and "buff" or "proc"
    local glowKeys    = (typ == "buff") and { "glowEnabled", "glowColor" } or { "glowEnabled", "glowType", "glowColor" }
    local _, _, reopen = rfns(bundle, { ctx = ctx })

    local entries = {
        { _omit = "label", type = "label", font = "UnbunkUtilityH6", height = 30,
          text = L["Tick \"Override group settings\" in a section to give this icon its own values; untick it to inherit the group again."] },

        IC.Sound(bundle, { rows = opts.soundRows or IC.SoundRows(typ) }),

        { _omit = "placeholder", type = "button", width = 200, hostHeight = 30,
          label = (bundle.get("placeholder") == true) and L["Hide placeholder"] or L["Show placeholder"],
          onClick = function()
              bundle.set("placeholder", bundle.get("placeholder") ~= true)
              bundle.touch(); reopen()
          end },
    }
    if typ ~= "buff" then entries[#entries + 1] = IC.CdmSettings(bundle) end
    entries[#entries + 1] = IC.IconSize(bundle, { kw = "iconW", kh = "iconH", defaultW = opts.iconSizeDefault, defaultH = opts.iconSizeDefault })
    entries[#entries + 1] = IC.Border(bundle, { defaultOn = true, ctx = ctx })
    entries[#entries + 1] = IC.Glow(bundle, { variant = glowVariant, keys = glowKeys, ctx = ctx })
    entries[#entries + 1] = IC.Timer(bundle)
    entries[#entries + 1] = IC.Title(bundle)
    entries[#entries + 1] = IC.Stacks(bundle, { cd = typ ~= "buff" })
    entries[#entries + 1] = { type = "button", label = L["Copy all group settings"], width = 180, hostHeight = 30,
        onClick = function()
            local function copySection(keys) for _, k in ipairs(keys) do bundle.set(k, CloneVal(bundle.groupGet(k))) end end
            if typ ~= "buff" then copySection({ "showPressOverlay", "showKeybinds" }) end
            if not omit.size then copySection({ "iconW", "iconH" }) end
            copySection({ "borderEnabled", "borderColor", "borderSize" })
            copySection(glowKeys)
            copySection(TIMER_KEYS); copySection(TITLE_KEYS); copySection(STACK_KEYS)
            bundle.touch()
            local _, rebuild = rfns(bundle, { ctx = ctx }); rebuild()
        end }

    if opts.append then for _, x in ipairs(opts.append) do entries[#entries + 1] = x end end

    if next(omit) then
        local kept = {}
        for _, e in ipairs(entries) do
            if not (e._omit and omit[e._omit]) then kept[#kept + 1] = e end
        end
        entries = kept
    end
    return entries
end

-- "Free icon settings" cadre set, bound to the icon's OWN config (no override store).
-- opts.type "spellitem" (Position → CDM settings → Border → Glow(proc) → Icon{...}) |
-- "buff" (Position → Border → Glow(buff) → Icon{...}). opts.position = IC.Position opts;
-- opts.sizeApply = special resize re-apply. Icon group = Icon size + Timer/Title/Stacks.
function IC.FreeSet(bundle, opts)
    opts = opts or {}
    local typ = opts.type or "spellitem"
    local glowVariant = (typ == "buff") and "buff" or "proc"
    local out = {}
    if opts.position then out[#out + 1] = IC.Position(opts.position) end
    if typ ~= "buff" then out[#out + 1] = IC.CdmSettings(bundle) end
    out[#out + 1] = IC.Border(bundle, { defaultOn = false })
    out[#out + 1] = IC.Glow(bundle, { variant = glowVariant })
    out[#out + 1] = { type = "group", title = L["Icon"], build = function()
        return {
            IC.IconSize(bundle, { bare = true, kw = "iconWidth", kh = "iconHeight", max = 512, sizeApply = opts.sizeApply }),
            IC.Timer(bundle),
            IC.Title(bundle),
            IC.Stacks(bundle, { cd = typ ~= "buff" }),
        }
    end }
    return out
end
