-- Modules/BuffGroups/UI/ConfigWindow.lua
-- "Buffs" panel: a "Buff groups" cadre holding one sub-cadre per group, an "Unused"
-- sub-cadre and a "Create group" button. Each group cadre lays out as:
--   [group name input]
--   the draggable icon strip + a trailing "+" tile  (reorder / add custom buff)
--   a COLLAPSIBLE "Group settings" group with sub-cadres in order:
--     Position (anchorTo dropdown + grow direction + drag position editor + posX/posY),
--     Border (enable / colour / thickness), Glow (enable / colour), and an "Icons"
--     sub-cadre wrapping { Icon size (W/H), Timer, Title, Stacks }.
-- Per-GROUP settings apply to every icon in the group; a PENCIL on each tile opens a
-- per-ICON override editor (a SUBSET: Border, icon size, show/hide Timer/Stacks/Title,
-- Glow) writing via BG.IconSet, with a "reset to group" (BG.IconReset).
--
-- Drag-to-reorder: dragging an icon lifts the tile itself (it follows the cursor on a
-- top-level layer — one moving icon, no ghost) and the strips live-reflow: the strip under
-- the cursor opens a gap at the insertion slot, others close theirs — so you can reorder
-- within a group AND move between groups (rows). On release the buff is reassigned +
-- reordered (BG.MoveBuff) and the panel rebuilds.

local _, ns = ...
local L  = ns.L
local BG = ns.BuffGroups

local ICON, PAD = 30, 4
local STEP = ICON + 6       -- horizontal step (icon + 6px gap)
local GAP_BG = 6            -- vertical gap between wrapped rows
local PER_ROW = 12          -- icons per row (groups cap here; Unused wraps to more rows)
local GROUP_CAP = BG.GROUP_CAP or 12   -- max icons per group (shared with the engine seed walk)

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ── anchorTo / growDir option maps (label <-> stored key) ──────────────────────
-- A group's anchor target and grow direction are plain group keys; the dropdowns map a
-- localised label to/from the stored key (ns.AnchorList-style, but a fixed local set).
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
    return "utility"
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

-- relPos: which side/corner of the anchor frame the group sits on (label <-> stored key).
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

-- ════════════════════════════════════════════════════════════════════════════════
-- Shared Timer / Title / Stacks sub-cadre builders (used by BOTH the per-GROUP panel
-- and the per-ICON pencil editor). Each takes an ACCESSOR BUNDLE so the same UI can target
-- either a group (BG.GGet/BG.GSet) or one icon (BG.IconGet/BG.IconSet/BG.IconReset):
--   bundle.get(key)        -> the effective value (group: GGet; icon: IconGet -> group)
--   bundle.set(key, val)   -> write it (group: GSet; icon: IconSet)
--   bundle.reset(key)|nil  -> drop one override (icon: IconReset(sid,key)); nil for a group
--   bundle.has(keys)|nil   -> true if ANY key in `keys` has a RAW icon override (icon only;
--                             nil for a group). Drives the per-section "Override group
--                             settings" checkbox + the inner controls' enabledBy gating.
--   bundle.touch()         -> re-apply the live layout
--   bundle.refresh()|nil   -> re-measure/redraw the host menu after a reset/toggle
-- The KEY NAMES are identical in both worlds (showTimer, timerFontKey/Path/Size/Outline/
-- Color, timerPos/timerOffX/timerOffY; likewise title*, stack*), so these read/write through
-- the bundle and never name a group id or spell id directly.
-- ════════════════════════════════════════════════════════════════════════════════

-- A styled-text editor (font / size / colour / outline) for a `prefix` text block:
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

-- Anchor dropdown + X / Y offsets for a `prefix` text block (timer/title/stack).
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

-- Append every non-nil entry of `extra` to `list` (skips a nil entry, e.g. the override
-- toggle in the group context).
local function append(list, extra)
    if extra then list[#list + 1] = extra end
    return list
end

-- Recursive value clone: deep-copies tables (so an icon override never aliases/mutates the
-- group's table — colours {r,g,b,a} or the timerThresholds list), passes scalars through.
local function CloneVal(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = CloneVal(val) end
    return out
end

-- "Override group settings" — the per-ICON, per-section checkbox shown at the TOP of each
-- settings sub-cadre (icon editor only; nil in the group context where bundle.reset == nil,
-- a group having nothing above it to inherit). Its checked-state = the section is currently
-- overridden (ANY of `keys` has a raw icon override, via bundle.has — NOT bundle.get, which
-- falls back to the group and would always look set). Checking it (false->true) STARTS
-- overriding WITHOUT changing appearance: each key is seeded to the current EFFECTIVE (group)
-- value, deep-cloned so a table value (colour / thresholds list) doesn't alias the group's.
-- Unchecking it (true->false) RESETS the section: each key drops its override and inherits the
-- group again. Either way it touch()es the layout then refresh()es so gating + values redraw.
local function OverrideToggle(bundle, keys)
    if not bundle.reset or not bundle.has then return nil end
    return { type = "checkbox", label = L["Override group settings"],
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

-- "Copy group settings" — the per-ICON, per-section button shown just under the override
-- checkbox (icon editor only; nil in the group context, same guard as OverrideToggle). It RE-SYNCS
-- the section's override to the group: each key is written to the group's CURRENT value, deep-cloned
-- so a table value (colour / thresholds list) doesn't alias the group's. Reads the group value via
-- bundle.groupGet (the pure group read, unlike bundle.get which would return the icon's own override
-- once the section is overriding). Gated by the section-override predicate so it's greyed/disabled
-- while the section inherits the group — consistent with the rest of the greyed section.
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

-- An enabledBy predicate (icon editor): a section's inner controls grey out while it INHERITS
-- the group (no key overridden); they light up once the override toggle is checked. In the
-- group context (no bundle.has) the controls are always live, so the group panel is unchanged.
local function SectionOverridden(bundle, keys)
    if not bundle.has then return nil end
    return function() return bundle.has(keys) end
end

-- Time-thresholds list editor: one row per tier (At seconds / size mult / colour / remove)
-- plus an "Add threshold" button. Reads the list through the bundle (group: GGet -> the
-- shared DEFAULT_TIMER_THRESHOLDS when unset; icon: IconGet -> group). EVERY write CLONES the
-- list first (bundle.set with a NEW table) so a per-icon edit never mutates the group's (or the
-- shared default) list. Add/remove change the row count, so they bundle.refresh() to re-render.
-- Gated on the enable checkbox via enabledBy.
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

-- `sectionGate` (icon editor) ANDs the section-override gate onto the thresholds-enabled gate
-- so the list greys both while the timer section inherits the group AND while thresholds are off.
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

-- Timer sub-cadre: show toggle + full font/size/colour/outline editor + position/offset +
-- the time-thresholds toggle and list editor. In the icon editor a leading "Override group
-- settings" checkbox seeds/resets these keys and gates the rest via enabledBy.
local TIMER_KEYS = {
    "showTimer", "timerFontKey", "timerFontPath", "timerFontSize", "timerOutline",
    "timerColor", "timerPos", "timerOffX", "timerOffY",
    "timerThresholdsEnabled", "timerThresholds",
}
local function TimerSection(bundle)
    local gated = SectionOverridden(bundle, TIMER_KEYS)
    return { type = "group", title = L["Timer"],
      -- Group context only: the "Show timer" checkbox greys the rest. In the icon context the
      -- override toggle + enabledBy drive the gating instead, so the override box stays live.
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

-- Title sub-cadre: show toggle + title text + full text editor + position/offset. In the icon
-- editor a leading "Override group settings" checkbox seeds/resets these keys and gates the rest.
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

-- Stacks sub-cadre: show toggle + full text editor + position/offset. In the icon editor a
-- leading "Override group settings" checkbox seeds/resets these keys and gates the rest.
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

-- ════════════════════════════════════════════════════════════════════════════════
-- Per-ICON override editor (the pencil). A movable, scrollable popup hosting a
-- ns.ui.BuildMenu scoped to ONE icon's sparse override. Border / icon size / glow write the
-- ICON_OVERRIDE_KEYS subset; Timer / Title / Stacks now write ANY of their keys (IconSet
-- accepts any key) so an icon can FULLY diverge from its group. Every read goes through
-- BG.IconGet so an unset key shows the inherited group value. Each section leads with an
-- "Override group settings" checkbox: checked = the icon uses its OWN values for the section;
-- unchecked = it inherits the group (the section's controls grey out). Each overriding section
-- also has a "Copy group settings" button (re-sync that section to the group's current values).
-- A single "Copy all group settings" button at the bottom makes the icon a full copy of the group.
-- ════════════════════════════════════════════════════════════════════════════════
local iconEditor       -- singleton { frame, scroll, content, sb, menu }
local editingSid       -- the spell id currently shown
local onIconEditChange -- set per-open: re-applies the layout + refreshes the panel strip
local OpenIconEditor   -- fwd decl: the placeholder toggle re-opens to re-read its state-label

local function IconOptions(sid)
    local function touch() BG.ApplyAll(); if onIconEditChange then onIconEditChange() end end
    local function rebuildMenu() if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end
    -- True if ANY of `keys` is a RAW icon override (not IconGet, which falls back to the group):
    -- the "Override group settings" checkbox's checked-state + the inner controls' enabledBy.
    local function sectionOverridden(keys)
        return function()
            for _, key in ipairs(keys) do if BG.IconHasOverride(sid, key) then return true end end
            return false
        end
    end
    -- The icon accessor bundle for the shared Timer/Title/Stacks sub-cadres: reads inherit the
    -- group (IconGet), writes override (IconSet), reset drops one key (IconReset), `has` reports
    -- raw per-section override state, refresh re-measures the popup after a section reset/toggle.
    local iconBundle = {
        get   = function(key) return BG.IconGet(sid, key) end,
        -- The PURE group value (no per-icon override), used by CopyGroupButton to re-sync the
        -- section to the group even while it's overriding (bundle.get would return the override).
        groupGet = function(key) return BG.GGet(BG.GroupOf(sid), key) end,
        set   = function(key, val) BG.IconSet(sid, key, val) end,
        reset = function(key) BG.IconReset(sid, key) end,
        has   = function(keys) return sectionOverridden(keys)() end,
        touch = touch,
        refresh = rebuildMenu,
    }
    local entries = {
        { type = "label", font = "UnbunkUtilityH6", height = 30,
          text = L["Tick \"Override group settings\" in a section to give this icon its own values; untick it to inherit the group again."] },

        -- Sound alert (PER-ICON ONLY — no group panel, no "Override group settings" box: it isn't
        -- a group-inherited visual). Two rows reusing the shared "sound" widget (its bundled enable
        -- checkbox IS the row's enable, and its built-in gate greys the picker while unchecked).
        -- Bound to BG.IconGet/IconSet for the soundStart*/soundStop* keys; both off by default.
        { type = "group", title = L["Sound alert"], build = function() return {
            { type = "sound", LSM = LSM, label = L["Sound when buff start"],
              getKey    = function() return BG.IconGet(sid, "soundStartSound") end,
              getEnable = function() return BG.IconGet(sid, "soundStartEnabled") == true end,
              onSelect  = function(key, path) BG.IconSet(sid, "soundStartSound", key); BG.IconSet(sid, "soundStartPath", path) end,
              onToggle  = function(v) BG.IconSet(sid, "soundStartEnabled", v and true or false) end,
              onTest    = function()
                  local p = BG.IconGet(sid, "soundStartPath")
                  if p then PlaySoundFile(p, "Master")
                  else local k = BG.IconGet(sid, "soundStartSound"); local r = LSM and k and LSM:Fetch("sound", k); if r then PlaySoundFile(r, "Master") end end
              end },
            { type = "sound", LSM = LSM, label = L["Sound when buff stop"],
              getKey    = function() return BG.IconGet(sid, "soundStopSound") end,
              getEnable = function() return BG.IconGet(sid, "soundStopEnabled") == true end,
              onSelect  = function(key, path) BG.IconSet(sid, "soundStopSound", key); BG.IconSet(sid, "soundStopPath", path) end,
              onToggle  = function(v) BG.IconSet(sid, "soundStopEnabled", v and true or false) end,
              onTest    = function()
                  local p = BG.IconGet(sid, "soundStopPath")
                  if p then PlaySoundFile(p, "Master")
                  else local k = BG.IconGet(sid, "soundStopSound"); local r = LSM and k and LSM:Fetch("sound", k); if r then PlaySoundFile(r, "Master") end end
              end },
        } end },

        -- Show/Hide placeholder (PER-ICON ONLY — flips the icon's `placeholder` boolean via IconSet,
        -- default false via the GROUP_TEMPLATE fallback). When ON the icon ALWAYS reserves its slot:
        -- active it shows its native frame, inactive a dim desaturated placeholder fills the gap. A plain
        -- button's label is captured at build time, so on click we flip + touch() then re-open the editor
        -- (re-running IconOptions) so the label re-reads its state — the same spell, same onChange.
        { type = "button", width = 200, hostHeight = 30,
          label = (BG.IconGet(sid, "placeholder") == true) and L["Hide placeholder"] or L["Show placeholder"],
          onClick = function()
              BG.IconSet(sid, "placeholder", BG.IconGet(sid, "placeholder") ~= true)
              touch()
              OpenIconEditor(sid, onIconEditChange)
          end },

        -- Icon size (W / H). Leading "Override group settings" checkbox seeds/resets iconW/iconH
        -- and gates the W/H inputs (greyed while inheriting the group).
        { type = "group", title = L["Icon size"], build = function()
            local keys = { "iconW", "iconH" }
            local gated = sectionOverridden(keys)
            local e = {}
            append(e, OverrideToggle(iconBundle, keys))
            append(e, CopyGroupButton(iconBundle, keys, gated))
            e[#e + 1] = { type = "custom", height = 30, enabledBy = gated, build = function(host)
                local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); wLbl:SetText(L["W"])
                local wInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(BG.IconGet(sid, "iconW") or 32),
                    onEnter = function(v) if v and v > 0 then BG.IconSet(sid, "iconW", v); touch() end end,
                })
                wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                local hInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(BG.IconGet(sid, "iconH") or 32),
                    onEnter = function(v) if v and v > 0 then BG.IconSet(sid, "iconH", v); touch() end end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                return { frame = host, height = 30, Refresh = function()
                    wInput.SetText(tostring(BG.IconGet(sid, "iconW") or 32))
                    hInput.SetText(tostring(BG.IconGet(sid, "iconH") or 32))
                end }
            end }
            return e
        end },

        -- Border (enable / colour / thickness).
        { type = "group", title = L["Border"], build = function()
            local keys = { "borderEnabled", "borderColor", "borderSize" }
            local gated = sectionOverridden(keys)
            local e = {}
            append(e, OverrideToggle(iconBundle, keys))
            append(e, CopyGroupButton(iconBundle, keys, gated))
            e[#e + 1] = { type = "checkbox", label = L["Show border"], enabledBy = gated,
              get = function() return BG.IconGet(sid, "borderEnabled") ~= false end,
              set = function(v) BG.IconSet(sid, "borderEnabled", v); touch()
                  if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end }
            e[#e + 1] = { type = "textEditor", label = L["Border color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return gated() and BG.IconGet(sid, "borderEnabled") ~= false end,
              getColor = function() return BG.IconGet(sid, "borderColor") end,
              onColorChange = function(r, g, b, a) BG.IconSet(sid, "borderColor", { r = r, g = g, b = b, a = a }); touch() end }
            e[#e + 1] = { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
              enabledBy = function() return gated() and BG.IconGet(sid, "borderEnabled") ~= false end,
              get = function() return BG.IconGet(sid, "borderSize") or 1 end,
              set = function(v) if v and v > 0 then BG.IconSet(sid, "borderSize", v); touch() end end }
            return e
        end },

        -- Glow (enable / colour).
        { type = "group", title = L["Glow"], build = function()
            local keys = { "glowEnabled", "glowColor" }
            local gated = sectionOverridden(keys)
            local e = {}
            append(e, OverrideToggle(iconBundle, keys))
            append(e, CopyGroupButton(iconBundle, keys, gated))
            e[#e + 1] = { type = "checkbox", label = L["Show glow"], enabledBy = gated,
              get = function() return BG.IconGet(sid, "glowEnabled") == true end,
              set = function(v) BG.IconSet(sid, "glowEnabled", v); touch()
                  if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end }
            e[#e + 1] = { type = "textEditor", label = L["Glow color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return gated() and BG.IconGet(sid, "glowEnabled") == true end,
              getColor = function() return BG.IconGet(sid, "glowColor") end,
              onColorChange = function(r, g, b, a) BG.IconSet(sid, "glowColor", { r = r, g = g, b = b, a = a }); touch() end }
            return e
        end },

        -- Timer / Title / Stacks: the FULL sub-cadres (show toggle + font/size/colour/outline
        -- + position/offset) so an icon can fully override its group, each with a leading
        -- "Override group settings" checkbox. Built from the SHARED builders bound to the icon bundle.
        TimerSection(iconBundle),
        TitleSection(iconBundle),
        StacksSection(iconBundle),

        -- Make the icon a FULL copy of its group: copy every section's group values into the icon
        -- overrides (deep-cloned, like each per-section Copy button), so all sections then override.
        { type = "button", label = L["Copy all group settings"], width = 180, hostHeight = 30,
          onClick = function()
              local gid = BG.GroupOf(sid)
              local function copySection(keys)
                  for _, key in ipairs(keys) do BG.IconSet(sid, key, CloneVal(BG.GGet(gid, key))) end
              end
              copySection({ "iconW", "iconH" })
              copySection({ "borderEnabled", "borderColor", "borderSize" })
              copySection({ "glowEnabled", "glowColor" })
              copySection(TIMER_KEYS)
              copySection(TITLE_KEYS)
              copySection(STACK_KEYS)
              touch()
              if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end },
    }
    -- For a buff not in the native Cooldown Manager (red in the strip), warn at the TOP of the editor,
    -- between the spell title and the "Overrides..." line.
    if BG.DisplayedKnown() and not BG.IsDisplayable(sid) then
        table.insert(entries, 1, { type = "label", font = "UnbunkUtilityH6", height = 30,
            color = { 1, 0.3, 0.3 },
            text = L["Not in the Cooldown Manager's tracked buffs — it won't display."] })
    end
    return entries
end

local function EnsureIconEditor()
    if iconEditor then return iconEditor end

    local f = CreateFrame("Frame", "UnbunkUtilityBuffIconEditor", UIParent, "BackdropTemplate")
    -- Sized so the inner sub-cadres (which draw their content ~518px wide, like the main panel)
    -- aren't clipped on the right: the scroll's visible width is f-width minus the 10px left +
    -- 30px right insets (= 600-40 = 560), wider than the menu's 540 content + originX.
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
    tinsert(UISpecialFrames, "UnbunkUtilityBuffIconEditor")   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    f.title = title

    -- A small spell-icon texture flanking the (centred) title on each side, showing the
    -- edited buff's icon. Set in OpenIconEditor to BG.SpellTexture(sid) with the same slight
    -- TexCoord crop (0.07..0.93) the strip tiles use. ~20px (≈ the title height); anchored just
    -- left of / right of the title FontString so they never overlap it or the close button.
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

    -- Close button (white cross tinting to the brand colour on hover, like the main window).
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
    content:SetSize(560, 10)   -- tracks the wider window (scroll visible width) so nothing clips right
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

-- Open the per-icon editor for `sid`. `onChange` (the panel's rebuild) refreshes the
-- strip's pencil affordances after a reset/toggle so they reflect the override state.
function OpenIconEditor(sid, onChange)
    local ed = EnsureIconEditor()
    editingSid = sid
    onIconEditChange = onChange
    ed.title:SetText(BG.SpellName(sid) or L["Edit icon"])
    -- Flank the title with the buff's spell icon on both sides.
    local tex = BG.SpellTexture(sid)
    if ed.titleIconL then ed.titleIconL:SetTexture(tex) end
    if ed.titleIconR then ed.titleIconR:SetTexture(tex) end

    -- Size the scroll child to the built menu so the scrollbar's range reaches the bottom cadre.
    -- `ed.menu.height` is the SUM of each entry's declared height — but the self-sizing sub-cadres
    -- (sound / textEditor / colour) can render slightly taller than they report, so the sum can fall
    -- short and clip the last cadre. So we mirror the MAIN panel's ResizeContentArea: after a frame
    -- lets WoW lay the stack out, measure the REAL extent from content-top down to the lowest child's
    -- GetBottom and grow the scroll child to fit. The immediate menu.height set avoids a 1px window on
    -- the first paint; the deferred GetBottom pass then refines it (and re-runs after every Rebuild).
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
        -- Defer one frame so the freshly-stacked cadres have a layout pass, then grow to the real
        -- measured bottom (+12 bottom pad) if it exceeds the declared sum, and refresh the scroll range.
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
    -- A Rebuild from a section's reset/toggle re-measures; keep height in sync after it.
    local rawBuild
    ClearIconMenu(ed)
    ed.menu = ns.ui.BuildMenu(ed.content, IconOptions(sid), {
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
-- The Buffs panel.
-- ════════════════════════════════════════════════════════════════════════════════
local function CreateBuffsPanel(parent)
    local menu
    local function rebuild() if menu then menu.Rebuild() end end
    local function touch() BG.ApplyAll() end

    BG.pe = {}
    local strips = {}                 -- current strip objects, rebuilt each render
    local dragTile, dragSid, dragHovered, dragHole
    local dragLayer                   -- top-level layer the lifted tile rides on (no scroll clip)
    local stopDrag                    -- forward decl (the OnUpdate driver calls it on mouse release)

    local function ensureDragLayer()
        if dragLayer then return dragLayer end
        dragLayer = CreateFrame("Frame", nil, UIParent)
        dragLayer:SetFrameStrata("TOOLTIP")
        dragLayer:SetAllPoints(UIParent)   -- no mouse: hover tests below are geometric
        return dragLayer
    end

    -- Geometric "is the cursor inside this frame" — computed from GetCursorPosition rather than
    -- :IsMouseOver(), which is unreliable while a drag has the mouse captured. Same unit math as
    -- slotAt (cursor / effective scale, compared to the frame rect).
    local function cursorOver(f)
        local l, b, w, h = f:GetRect()
        if not l then return false end
        local s = f:GetEffectiveScale()
        if not (s and s > 0) then return false end
        local mx, my = GetCursorPosition()
        mx, my = mx / s, my / s
        return mx >= l and mx < l + w and my >= b and my < b + h
    end

    -- The lifted tile ITSELF rides a top-level layer and follows the cursor (one real moving icon
    -- — the others visibly slide around it, instead of a ghost masking the gap). Release is found
    -- by polling the mouse button, NOT OnDragStop (which is flaky once the frame is reparented).
    -- The hovered strip opens a one-slot gap; relayout() skips the dragged spell.
    local function dragOnUpdate()
        if not dragTile then return end
        if not IsMouseButtonDown("LeftButton") then stopDrag(); return end
        local scale = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        if scale and scale > 0 and mx then
            dragTile:ClearAllPoints()
            dragTile:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / scale, my / scale)
        end
        local hovered, hole
        for _, s in ipairs(strips) do
            if s.frame:IsVisible() and cursorOver(s.frame) then
                hovered = s; hole = s.slotAt(dragSid); break
            end
        end
        dragHovered, dragHole = hovered, hole
        for _, s in ipairs(strips) do s.relayout(dragSid, s == hovered and hole or nil) end
    end

    -- A persistent driver frame runs the loop, so it keeps firing even though the dragged tile is
    -- reparented onto dragLayer (and rebuilt on drop).
    local driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", dragOnUpdate)

    local function startDrag(tile, spellId)
        dragTile, dragSid, dragHovered, dragHole = tile, spellId, nil, nil
        tile._origParent = tile:GetParent()
        tile:SetParent(ensureDragLayer())   -- top-level: visible above the panel, never clipped
        tile:SetFrameStrata("TOOLTIP")
        tile:Raise()
        driver:Show()
    end

    stopDrag = function()
        local tile = dragTile
        if not tile then return end          -- idempotent (poll + OnDragStop can both call us)
        driver:Hide()
        tile:SetParent(tile._origParent or UIParent)   -- back so Rebuild reclaims it
        tile:SetFrameStrata("MEDIUM")
        local sid, hovered, hole = dragSid, dragHovered, dragHole
        dragTile, dragSid, dragHovered, dragHole = nil, nil, nil, nil
        -- Dropped onto a strip -> reassign/reorder; dropped into empty space -> nothing moves
        -- (the rebuild below puts the lifted tile straight back).
        if sid and hovered then
            local full = hovered.groupId ~= 0 and BG.GroupOf(sid) ~= hovered.groupId
                and #BG.GetGroupBuffs(hovered.groupId) >= GROUP_CAP
            if not full then BG.MoveBuff(sid, hovered.groupId, hole); touch() end
        end
        rebuild()
    end

    -- The "+" tile: add a CUSTOM (cast-triggered) buff. A small picker offers the Quick-Add
    -- templates (BG.CUSTOM_BUFF_TEMPLATES) as buttons plus a raw "Spell ID + Duration" pair;
    -- both route through BG.AddCustom into THIS group.
    local function promptAddCustom(groupId)
        local f = ns.ui._bgAddCustom
        if not f then
            f = CreateFrame("Frame", "UnbunkUtilityBuffAddCustom", UIParent, "BackdropTemplate")
            f:SetSize(360, 320)
            f:SetPoint("CENTER")
            f:SetFrameStrata("FULLSCREEN_DIALOG")
            f:SetToplevel(true)
            f:EnableMouse(true)
            f:SetBackdrop({
                bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
                insets   = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
            f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            tinsert(UISpecialFrames, "UnbunkUtilityBuffAddCustom")   -- ESC closes

            local t = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
            t:SetPoint("TOP", f, "TOP", 0, -12); t:SetText(L["Add a buff"])

            local qh = f:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
            qh:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -42); qh:SetText(L["Quick add"])

            f.quickButtons = {}
            local y = 64
            for _, tpl in ipairs(BG.CUSTOM_BUFF_TEMPLATES or {}) do
                local b = ns.ui.CreateButton({ parent = f, width = 324, height = 24,
                    label = BG.SpellName(tpl.spellID) })
                b.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -y)
                b.spellID = tpl.spellID
                b.frame:SetScript("OnClick", function()
                    if f.groupId and b.spellID then BG.AddCustomFromTemplate(b.spellID, f.groupId) end
                    f:Hide(); if f.onDone then f.onDone() end
                end)
                f.quickButtons[#f.quickButtons + 1] = b
                y = y + 28
            end

            local idLbl = f:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            idLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -(y + 8)); idLbl:SetText(L["Spell ID"])
            local idInput = ns.ui.CreateTextInput({
                parent = f, width = 90, height = 22, numeric = true, min = 1, max = 99999999, maxLetters = 8, text = "",
            })
            idInput.frame:SetPoint("LEFT", idLbl, "RIGHT", 8, 0)
            f.idInput = idInput

            local durLbl = f:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            durLbl:SetPoint("LEFT", idInput.frame, "RIGHT", 12, 0); durLbl:SetText(L["Duration"])
            local durInput = ns.ui.CreateTextInput({
                parent = f, width = 50, height = 22, numeric = true, min = 1, max = 3600, maxLetters = 4, text = "30",
            })
            durInput.frame:SetPoint("LEFT", durLbl, "RIGHT", 8, 0)
            f.durInput = durInput

            local add = ns.ui.CreateButton({ parent = f, label = L["Add a buff"], width = 130, height = 24 })
            add.frame:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
            add.frame:SetScript("OnClick", function()
                local sid = tonumber(f.idInput.GetText())
                local dur = tonumber(f.durInput.GetText())
                if sid and sid > 0 and f.groupId then
                    BG.AddCustom(sid, f.groupId, { duration = dur or 0 })
                end
                f:Hide(); if f.onDone then f.onDone() end
            end)

            ns.ui._bgAddCustom = f
        end
        f.groupId = groupId
        f.onDone  = function() touch(); rebuild() end
        f.idInput.SetText("")
        f.durInput.SetText("30")
        f:Show(); f:Raise()
    end

    -- A draggable icon strip for one group (groupId 0 = Unused). Shows ALL buffs assigned to
    -- the group (active or not) so they can be reordered; the in-game layout only draws the
    -- active ones. Groups are a single row capped at GROUP_CAP; Unused wraps to many rows.
    -- The strip object exposes relayout/slotAt used by the drag driver.
    local function BuffStripEntry(groupId)
        local wrap = (groupId == 0)
        local cap  = wrap and nil or GROUP_CAP
        return {
            type  = "custom",
            build = function(host)
                local frame = CreateFrame("Frame", nil, host)
                frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)

                local obj = { frame = frame, groupId = groupId, tiles = {}, wrap = wrap, cap = cap }
                strips[#strips + 1] = obj

                -- Slot -> position (a wrapping grid for Unused, a single row for a group).
                local function placeAt(f, slot)
                    f:ClearAllPoints()
                    if wrap then
                        local col, row = slot % PER_ROW, math.floor(slot / PER_ROW)
                        f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * STEP, -(PAD + row * (ICON + GAP_BG)))
                    else
                        f:SetPoint("LEFT", frame, "LEFT", PAD + slot * STEP, 0)
                    end
                end

                -- Trailing "+" tile.
                local addb = CreateFrame("Button", nil, frame)
                addb:SetSize(ICON, ICON)
                local abord = addb:CreateTexture(nil, "BACKGROUND")
                abord:SetPoint("TOPLEFT", -1, 1); abord:SetPoint("BOTTOMRIGHT", 1, -1); abord:SetColorTexture(0.4, 0.4, 0.4, 1)
                local afill = addb:CreateTexture(nil, "BACKGROUND", nil, 1); afill:SetAllPoints(); afill:SetColorTexture(0.12, 0.12, 0.12, 0.9)
                local aplus = addb:CreateTexture(nil, "ARTWORK"); aplus:SetPoint("CENTER"); aplus:SetSize(ICON - 12, ICON - 12); aplus:SetTexture(UNBUNK_ICON_PLUS_GREEN)
                addb:SetScript("OnEnter", function() afill:SetColorTexture(0.2, 0.2, 0.2, 0.95) end)
                addb:SetScript("OnLeave", function() afill:SetColorTexture(0.12, 0.12, 0.12, 0.9) end)
                addb:SetScript("OnClick", function() promptAddCustom(groupId) end)
                obj.addBtn = addb

                for _, sid in ipairs(BG.GetGroupBuffs(groupId)) do
                    local spellId = sid
                    local b = CreateFrame("Button", nil, frame)
                    b:SetSize(ICON, ICON)
                    local bord = b:CreateTexture(nil, "BACKGROUND")
                    bord:SetPoint("TOPLEFT", -1, 1); bord:SetPoint("BOTTOMRIGHT", 1, -1); bord:SetColorTexture(0.4, 0.4, 0.4, 1)
                    local tex = b:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints(); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); tex:SetTexture(BG.SpellTexture(spellId))
                    b:RegisterForDrag("LeftButton")
                    b:SetScript("OnDragStart", function() startDrag(b, spellId) end)
                    b:SetScript("OnDragStop", function() stopDrag() end)

                    -- A buff that isn't in the native CDM "Tracked Buffs" (not displayable) has no
                    -- native frame, so in a real group it can never show: flag the tile RED as a
                    -- warning. Customs are always displayable; the Unused strip is never flagged.
                    local undisplayable = groupId ~= 0 and BG.DisplayedKnown() and not BG.IsDisplayable(spellId)
                    if undisplayable then
                        tex:SetVertexColor(1, 0.35, 0.35)
                        bord:SetColorTexture(0.9, 0.15, 0.15, 1)
                        -- a tiny "Not displayed" label over the red icon (it can't render in-game)
                        local warn = b:CreateFontString(nil, "OVERLAY")
                        warn:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
                        warn:SetPoint("CENTER", b, "CENTER", 0, 0)
                        warn:SetWordWrap(true)
                        warn:SetJustifyH("CENTER")
                        warn:SetTextColor(1, 0.45, 0.45)
                        -- one word per line (split on spaces, no fixed width) so a long word never
                        -- clips; language-agnostic — a single-word translation just stays on one line.
                        warn:SetText((L["Not displayed"]:gsub("%s+", "\n")))
                    end

                    -- Tooltip on hover: the spell tooltip, plus a red "won't display" warning when
                    -- the buff isn't in the Cooldown Manager's tracked (displayed) set.
                    b:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local shown = false
                        if not BG.IsCustom(spellId) and C_Spell and C_Spell.GetSpellInfo
                            and C_Spell.GetSpellInfo(spellId) then
                            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, spellId)
                        end
                        if not shown then GameTooltip:SetText(BG.SpellName(spellId), 1, 1, 1) end
                        if undisplayable then
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(L["Not in the Cooldown Manager's tracked buffs — it won't display."], 1, 0.3, 0.3, true)
                        end
                        GameTooltip:Show()
                    end)
                    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    -- Pencil: open the per-icon override editor. Hidden on the Unused strip
                    -- (a hidden icon has nothing to style). Tinted brand colour when the icon
                    -- carries any override, so the user can see which icons diverge.
                    if groupId ~= 0 then
                        local pb = CreateFrame("Button", nil, b)
                        pb:SetSize(14, 14); pb:SetPoint("CENTER", b, "TOPLEFT", 4, -4)
                        pb:SetFrameLevel(b:GetFrameLevel() + 5)
                        local pbg = pb:CreateTexture(nil, "BACKGROUND"); pbg:SetAllPoints(); pbg:SetColorTexture(0, 0, 0, 0.6)
                        local pg = pb:CreateTexture(nil, "OVERLAY"); pg:SetPoint("CENTER"); pg:SetSize(10, 10)
                        pg:SetTexture(UNBUNK_ICON_PEN_WHITE)
                        local function paint() if BG.IconHasOverride(spellId) then pg:SetVertexColor(ns.GetBrandColor()) else pg:SetVertexColor(1, 1, 1) end end
                        paint()
                        pb:SetScript("OnEnter", function() pg:SetVertexColor(ns.GetBrandColor()) end)
                        pb:SetScript("OnLeave", paint)
                        pb:SetScript("OnClick", function() OpenIconEditor(spellId, rebuild) end)
                    end

                    if BG.IsCustom(spellId) then
                        local xb = CreateFrame("Button", nil, b)
                        xb:SetSize(14, 14); xb:SetPoint("CENTER", b, "TOPRIGHT", -7, -3)
                        xb:SetFrameLevel(b:GetFrameLevel() + 5)
                        local xbg = xb:CreateTexture(nil, "BACKGROUND"); xbg:SetAllPoints(); xbg:SetColorTexture(0, 0, 0, 0.6)
                        local xg = xb:CreateTexture(nil, "OVERLAY"); xg:SetPoint("CENTER"); xg:SetSize(10, 10); xg:SetTexture(UNBUNK_ICON_CROSS_WHITE)
                        xb:SetScript("OnEnter", function() xg:SetVertexColor(ns.GetBrandColor()) end)
                        xb:SetScript("OnLeave", function() xg:SetVertexColor(1, 1, 1) end)
                        xb:SetScript("OnClick", function()
                            BG.RemoveCustom(spellId)
                            if BG.ReleaseCustomFrame then BG.ReleaseCustomFrame(spellId) end
                            touch(); rebuild()
                        end)
                    end

                    obj.tiles[#obj.tiles + 1] = { frame = b, spellId = spellId }
                end

                -- Insertion index under the cursor (0 .. #non-dragged tiles), read from where the
                -- tiles ACTUALLY sit (absolute coords) rather than a synthetic grid off the
                -- strip's left + a fixed STEP. The index is the count of laid-out tiles that fall
                -- "before" the cursor in reading order (a row above, or the same row and left of
                -- it) — robust to the strip being far wider than its icons and to scroll offset.
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
                                if wrap and tb then
                                    local tcy  = tb + ICON / 2
                                    local band = (ICON + GAP_BG) / 2
                                    if tcy > my + band then          -- tile sits a row above the cursor
                                        before = true
                                    elseif tcy < my - band then      -- a row below the cursor
                                        before = false
                                    else                              -- same row: compare X
                                        before = (tl + ICON / 2) < mx
                                    end
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

                -- Reflow: skip the lifted tile (it follows the cursor), place the rest in order,
                -- leaving a one-slot gap at holeIndex (the hovered strip only).
                function obj.relayout(dragSpell, holeIndex)
                    local seq = {}
                    for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then seq[#seq + 1] = t end end
                    local slot = 0
                    for i, t in ipairs(seq) do
                        if holeIndex and (i - 1) == holeIndex then slot = slot + 1 end
                        placeAt(t.frame, slot); t.frame:Show()
                        slot = slot + 1
                    end
                    if holeIndex and holeIndex >= #seq then slot = slot + 1 end
                    if wrap or (#seq < (cap or math.huge)) then
                        placeAt(addb, slot); addb:Show()
                    else
                        addb:Hide()
                    end
                end

                obj.relayout(nil, nil)

                -- Height: one row for a group, ceil(items / PER_ROW) rows for Unused.
                local items = #obj.tiles + 1   -- + the "+" tile
                local rows  = wrap and math.max(1, math.ceil(items / PER_ROW)) or 1
                local h = PAD * 2 + rows * ICON + math.max(0, rows - 1) * GAP_BG
                host:SetHeight(h)
                return { frame = host, height = h }
            end,
        }
    end

    -- ── Per-group Icon size (W / H) — single row, no per-row split. ────────────────
    local function IconSizeEntry(id)
        return {
            type = "custom", height = 30,
            build = function(host)
                local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); wLbl:SetText(L["W"])
                local wInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(BG.GGet(id, "iconW") or 32),
                    onEnter = function(v) if v and v > 0 then BG.GSet(id, "iconW", v); touch() end end,
                })
                wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                local hInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(BG.GGet(id, "iconH") or 32),
                    onEnter = function(v) if v and v > 0 then BG.GSet(id, "iconH", v); touch() end end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                return { frame = host, height = 30, Refresh = function()
                    wInput.SetText(tostring(BG.GGet(id, "iconW") or 32))
                    hInput.SetText(tostring(BG.GGet(id, "iconH") or 32))
                end }
            end,
        }
    end

    -- The GROUP accessor bundle for the shared Timer/Title/Stacks sub-cadres: reads/writes the
    -- group directly (GGet/GSet). No reset (a group has nothing above it to inherit). refresh =
    -- the panel's full rebuild: it re-applies the gate checkboxes AND re-measures every enclosing
    -- fixed-height cadre, which the time-thresholds editor needs when its row count changes
    -- (a plain menu.Refresh would leave the group box height stale).
    local function GroupBundle(id)
        return {
            get   = function(key) return BG.GGet(id, key) end,
            set   = function(key, val) BG.GSet(id, key, val) end,
            reset = nil,
            touch = touch,
            refresh = rebuild,
        }
    end

    -- ── Sub-cadres of "Group settings" ─────────────────────────────────────────────
    local function PositionGroup(id)
        return { type = "group", title = L["Position"], build = function() return {
            { type = "dropdown", label = L["Anchor to"], width = 180, height = 50,
              getList = AnchorList,
              getCurrentKey = function() return AnchorLabel(BG.GGet(id, "anchorTo")) end,
              onSelect = function(label) BG.GSet(id, "anchorTo", AnchorFromLabel(label)); touch() end },
            { type = "dropdown", label = L["Placement"], width = 180, height = 50,
              getList = RelPosList,
              getCurrentKey = function() return RelPosLabel(BG.GGet(id, "relPos")) end,
              onSelect = function(label) BG.GSet(id, "relPos", RelPosFromLabel(label)); touch() end },
            { type = "dropdown", label = L["Grow direction"], width = 180, height = 50,
              getList = GrowList,
              getCurrentKey = function() return GrowLabel(BG.GGet(id, "growDir")) end,
              onSelect = function(label) BG.GSet(id, "growDir", GrowFromLabel(label)); touch() end },
            { type = "checkbox", label = L["Static Display"],
              get = function() return BG.GGet(id, "staticDisplay") == true end,
              set = function(v) BG.GSet(id, "staticDisplay", v and true or false); touch() end },
            { type = "textinput", label = L["Spacing"], width = 46, numeric = true, min = 0, max = 64, maxLetters = 2,
              get = function() return BG.GGet(id, "spacing") or 1 end,
              set = function(v) if v ~= nil then BG.GSet(id, "spacing", v); touch() end end },
            { type = "position", ref = "pe",
              onBuilt = function(w) BG.pe[id] = w end,
              label = L["Group position (offset from anchor)"],
              getX = function() return BG.GGet(id, "posX") end,
              getY = function() return BG.GGet(id, "posY") end,
              onApply = function(x, yv)
                  if x  then BG.GSet(id, "posX", x)  end
                  if yv then BG.GSet(id, "posY", yv) end
                  touch()
              end,
              onUnlock   = function() BG.SetGroupUnlocked(id, true) end,
              onLock     = function() BG.SetGroupUnlocked(id, false); if BG.pe[id] then BG.pe[id].Refresh() end end,
              isUnlocked = function() return BG.IsGroupUnlocked(id) end },
        } end }
    end

    local function BorderGroup(id)
        return { type = "group", title = L["Border"], build = function() return {
            { type = "checkbox", label = L["Show border"],
              get = function() return BG.GGet(id, "borderEnabled") ~= false end,
              set = function(v) BG.GSet(id, "borderEnabled", v); touch(); if menu then menu.Refresh() end end },
            { type = "textEditor", label = L["Border color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return BG.GGet(id, "borderEnabled") ~= false end,
              getColor = function() return BG.GGet(id, "borderColor") end,
              onColorChange = function(r, g, b, a) BG.GSet(id, "borderColor", { r = r, g = g, b = b, a = a }); touch() end },
            { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
              enabledBy = function() return BG.GGet(id, "borderEnabled") ~= false end,
              get = function() return BG.GGet(id, "borderSize") or 1 end,
              set = function(v) if v and v > 0 then BG.GSet(id, "borderSize", v); touch() end end },
        } end }
    end

    local function GlowGroup(id)
        return { type = "group", title = L["Glow"], build = function() return {
            { type = "checkbox", label = L["Show glow"],
              get = function() return BG.GGet(id, "glowEnabled") == true end,
              set = function(v) BG.GSet(id, "glowEnabled", v); touch(); if menu then menu.Refresh() end end },
            { type = "textEditor", label = L["Glow color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return BG.GGet(id, "glowEnabled") == true end,
              getColor = function() return BG.GGet(id, "glowColor") end,
              onColorChange = function(r, g, b, a) BG.GSet(id, "glowColor", { r = r, g = g, b = b, a = a }); touch() end },
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

    -- "Group settings": a collapsible section holding the sub-cadres (Position, Border,
    -- Glow, Icons). Collapsed state is kept per-group in the saved config. Defaults to
    -- collapsed: an unset (nil) cfgCollapsed reads as collapsed, only an explicit false
    -- expands. Because this section is nested INSIDE the group cadre's GroupBox (whose
    -- height is fixed at build time), toggling it must rebuild the whole panel so every
    -- enclosing cadre re-measures to its real content height (the section's own
    -- ns.ResizeActiveModule only re-measures the top scroll height, not the stale parent
    -- box heights). rebuild() = menu.Rebuild(), which honours the persisted cfgCollapsed.
    local function GroupSettingsSection(id)
        return { type = "section", label = L["Group settings"], showCheckbox = false,
          getCollapsed = function() return BG.GGet(id, "cfgCollapsed") ~= false end,
          onCollapse   = function(c)
              BG.GSet(id, "cfgCollapsed", c and true or false)
              -- Defer the rebuild one frame: CollapsibleSection's own SetCollapsed keeps touching its
              -- frames AFTER calling onCollapse, so tearing them down synchronously here would orphan
              -- them mid-handler. Next frame, the rebuild re-measures every enclosing cadre.
              if C_Timer and C_Timer.After then C_Timer.After(0, rebuild) else rebuild() end
          end,
          build = function() return {
            PositionGroup(id),
            BorderGroup(id),
            GlowGroup(id),
            IconsGroup(id),
        } end }
    end

    -- ── A group cadre: name, the strip + "+", then "Group settings". ───────────────
    local function GroupCadre(id)
        local title = (BG.GGet(id, "name") or ("Group " .. id))
        return { type = "group", title = title, build = function()
            local e = {
                { type = "textinput", label = L["Group name"], width = 200, maxLetters = 32,
                  get = function() return BG.GGet(id, "name") or "" end,
                  set = function(v) BG.GSet(id, "name", v or ""); rebuild() end },
                BuffStripEntry(id),
                -- Re-sort this group's strip so its NATIVE buffs follow the native on-screen order
                -- (the EditMode "Tracked Buffs" arrangement); CUSTOM buffs keep their relative order
                -- AFTER the natives. Reorders within the group only (no add/remove/reassign).
                { type = "button", label = L["Copy native CDM order"], width = 200, hostHeight = 30,
                  onClick = function() BG.SortGroupNativeOrder(id); touch(); rebuild() end },
                GroupSettingsSection(id),
            }
            if id ~= 1 then
                e[#e + 1] = { type = "button", label = L["Delete group"], width = 160, hostHeight = 30,
                    onClick = function() BG.RemoveGroup(id); touch(); rebuild() end }
            end
            return e
        end }
    end

    local function UnusedCadre()
        return { type = "group", title = L["Unused"], build = function() return {
            { type = "label", font = "UnbunkUtilityH6", height = 18,
              text = L["Buffs here are hidden. Drag them onto a group to show them."] },
            BuffStripEntry(0),
        } end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Buffs"] },
        -- The module's global enable, OUTSIDE the cadre (just under the title). It greys the whole
        -- cadre below (enabledBy) when off; Refresh() re-applies that on toggle.
        { type = "checkbox", label = L["Enable custom CDM buffs"],
          get = function() return BG.Enabled() end,
          set = function(v) BG.SetEnabled(v); touch(); if menu then menu.Refresh() end end },
        -- The module's global cadre: every group cadre + Create group + Unused live inside it. It
        -- greys/blocks as a whole when the module is disabled.
        { type = "group", title = L["Buff groups"],
          enabledBy = function() return BG.Enabled() end,
          build = function()
            wipe(strips)
            local entries = {}
            for _, g in ipairs(BG.GroupList()) do
                entries[#entries + 1] = GroupCadre(g.id)
            end
            entries[#entries + 1] = { type = "button", label = L["Create group"], width = 160, hostHeight = 30,
                onClick = function() BG.NewGroup(); touch(); rebuild() end }
            entries[#entries + 1] = UnusedCadre()
            return entries
        end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })

    -- When the user edits the CDM "Tracked Buffs" set in EditMode the engine's ticker detects the
    -- DISPLAYED-set change and calls this. Rebuild the strip/panel so a tile's red flag + its tooltip's
    -- red line re-evaluate (both derive from BG.DisplayedKnown()/BG.IsDisplayable), and rebuild the
    -- per-icon editor if it's open so its red "won't display" message re-evaluates too. Cheap no-op when
    -- the panel isn't built or shown (the engine only fires this on an actual change, never every tick).
    BG.onDisplayedChanged = function()
        if menu and parent and parent:IsShown() then rebuild() end
        -- Re-open the editor for the SAME icon (rather than a plain menu Rebuild): the red "won't
        -- display" line is decided in IconOptions(sid) at open time (a static top-level entry, not a
        -- build closure), so only re-running IconOptions re-evaluates it. editingSid/onIconEditChange
        -- are the open editor's current spell + the panel rebuild it was opened with.
        if iconEditor and iconEditor.frame and iconEditor.frame:IsShown() and editingSid then
            OpenIconEditor(editingSid, onIconEditChange)
        end
    end

    -- "Group settings" defaults to collapsed and re-collapses every time the user leaves
    -- the Buffs panel. On hide, force every group's persisted cfgCollapsed back to true
    -- (HookScript, so BuildMenu's own OnShow refresh hook is not clobbered); on show,
    -- rebuild so the sections render in their (now collapsed) persisted state and every
    -- enclosing cadre re-measures. Both hooks live on the reused panel frame.
    parent:HookScript("OnHide", function()
        for _, g in ipairs(BG.GroupList()) do
            BG.GSet(g.id, "cfgCollapsed", true)
        end
    end)
    parent:HookScript("OnShow", function()
        if menu then menu.Rebuild() end
    end)

    return menu
end

local initBG = CreateFrame("Frame")
initBG:RegisterEvent("ADDON_LOADED")
initBG:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Buffs"], nil, CreateBuffsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
