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

-- A "Reset to group" button that drops a set of keys back to the group (icon editor only;
-- a nil bundle.reset means the group panel, which has nothing above it to inherit -> no button).
local function ResetButton(bundle, keys)
    if not bundle.reset then return nil end
    return { type = "button", label = L["Reset to group"], width = 140, hostHeight = 28,
        onClick = function()
            for _, key in ipairs(keys) do bundle.reset(key) end
            bundle.touch()
            if bundle.refresh then bundle.refresh() end
        end }
end

-- Append every non-nil entry of `extra` to `list` (skips the ResetButton when it's nil).
local function append(list, extra)
    if extra then list[#list + 1] = extra end
    return list
end

-- Timer sub-cadre: show toggle + full font/size/colour/outline editor + position/offset.
local function TimerSection(bundle)
    return { type = "group", title = L["Timer"],
      gate = { enabled = function() return bundle.get("showTimer") ~= false end, master = "showtimer" },
      build = function()
        local e = {
            { type = "checkbox", ref = "showtimer", label = L["Show timer"],
              get = function() return bundle.get("showTimer") ~= false end,
              set = function(v) bundle.set("showTimer", v); bundle.touch() end },
            StyleEditorFor(bundle, "timer"),
            PosOffsetFor(bundle, "timer"),
        }
        return append(e, ResetButton(bundle, {
            "showTimer", "timerFontKey", "timerFontPath", "timerFontSize", "timerOutline",
            "timerColor", "timerPos", "timerOffX", "timerOffY",
        }))
      end }
end

-- Title sub-cadre: show toggle + title text + full text editor + position/offset.
local function TitleSection(bundle)
    return { type = "group", title = L["Title"],
      gate = { enabled = function() return bundle.get("showTitle") == true end, master = "showtitle" },
      build = function()
        local e = {
            { type = "checkbox", ref = "showtitle", label = L["Show title"],
              get = function() return bundle.get("showTitle") == true end,
              set = function(v) bundle.set("showTitle", v); bundle.touch() end },
            { type = "textinput", label = L["Title text"], width = 240, maxLetters = 64,
              get = function() return bundle.get("titleText") or "" end,
              set = function(v) bundle.set("titleText", v or ""); bundle.touch() end },
            StyleEditorFor(bundle, "title"),
            PosOffsetFor(bundle, "title"),
        }
        return append(e, ResetButton(bundle, {
            "showTitle", "titleText", "titleFontKey", "titleFontPath", "titleFontSize",
            "titleOutline", "titleColor", "titlePos", "titleOffX", "titleOffY",
        }))
      end }
end

-- Stacks sub-cadre: show toggle + full text editor + position/offset.
local function StacksSection(bundle)
    return { type = "group", title = L["Stacks/Charges"],
      gate = { enabled = function() return bundle.get("showStack") ~= false end, master = "showstack" },
      build = function()
        local e = {
            { type = "checkbox", ref = "showstack", label = L["Show stacks"],
              get = function() return bundle.get("showStack") ~= false end,
              set = function(v) bundle.set("showStack", v); bundle.touch() end },
            StyleEditorFor(bundle, "stack"),
            PosOffsetFor(bundle, "stack"),
        }
        return append(e, ResetButton(bundle, {
            "showStack", "stackFontKey", "stackFontPath", "stackFontSize", "stackOutline",
            "stackColor", "stackPos", "stackOffX", "stackOffY",
        }))
      end }
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Per-ICON override editor (the pencil). A movable, scrollable popup hosting a
-- ns.ui.BuildMenu scoped to ONE icon's sparse override. Border / icon size / glow write the
-- ICON_OVERRIDE_KEYS subset; Timer / Title / Stacks now write ANY of their keys (IconSet
-- accepts any key) so an icon can FULLY diverge from its group. Every read goes through
-- BG.IconGet so an unset key shows the inherited group value. A per-section "reset to group"
-- drops that section's overrides back to the group default.
-- ════════════════════════════════════════════════════════════════════════════════
local iconEditor       -- singleton { frame, scroll, content, sb, menu }
local editingSid       -- the spell id currently shown
local onIconEditChange -- set per-open: re-applies the layout + refreshes the panel strip

local function IconOptions(sid)
    local function touch() BG.ApplyAll(); if onIconEditChange then onIconEditChange() end end
    -- The icon accessor bundle for the shared Timer/Title/Stacks sub-cadres: reads inherit the
    -- group (IconGet), writes override (IconSet), reset drops one key (IconReset), refresh
    -- re-measures the popup after a section reset/toggle.
    local iconBundle = {
        get   = function(key) return BG.IconGet(sid, key) end,
        set   = function(key, val) BG.IconSet(sid, key, val) end,
        reset = function(key) BG.IconReset(sid, key) end,
        touch = touch,
        refresh = function() if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end,
    }
    return {
        { type = "label", font = "UnbunkUtilityH6", height = 30,
          text = L["Overrides here win over the group; reset a section to inherit the group again."] },

        -- Icon size (W / H).
        { type = "group", title = L["Icon size"], build = function() return {
            { type = "custom", height = 30, build = function(host)
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
            end },
            { type = "button", label = L["Reset to group"], width = 140, hostHeight = 28,
              onClick = function() BG.IconReset(sid, "iconW"); BG.IconReset(sid, "iconH"); touch()
                  if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end },
        } end },

        -- Border (enable / colour / thickness).
        { type = "group", title = L["Border"], build = function() return {
            { type = "checkbox", label = L["Show border"],
              get = function() return BG.IconGet(sid, "borderEnabled") ~= false end,
              set = function(v) BG.IconSet(sid, "borderEnabled", v); touch()
                  if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end },
            { type = "textEditor", label = L["Border color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return BG.IconGet(sid, "borderEnabled") ~= false end,
              getColor = function() return BG.IconGet(sid, "borderColor") end,
              onColorChange = function(r, g, b, a) BG.IconSet(sid, "borderColor", { r = r, g = g, b = b, a = a }); touch() end },
            { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
              enabledBy = function() return BG.IconGet(sid, "borderEnabled") ~= false end,
              get = function() return BG.IconGet(sid, "borderSize") or 1 end,
              set = function(v) if v and v > 0 then BG.IconSet(sid, "borderSize", v); touch() end end },
            { type = "button", label = L["Reset to group"], width = 140, hostHeight = 28,
              onClick = function() BG.IconReset(sid, "borderEnabled"); BG.IconReset(sid, "borderColor")
                  BG.IconReset(sid, "borderSize"); touch()
                  if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end },
        } end },

        -- Glow (enable / colour).
        { type = "group", title = L["Glow"], build = function() return {
            { type = "checkbox", label = L["Show glow"],
              get = function() return BG.IconGet(sid, "glowEnabled") == true end,
              set = function(v) BG.IconSet(sid, "glowEnabled", v); touch()
                  if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end },
            { type = "textEditor", label = L["Glow color"],
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              enabledBy = function() return BG.IconGet(sid, "glowEnabled") == true end,
              getColor = function() return BG.IconGet(sid, "glowColor") end,
              onColorChange = function(r, g, b, a) BG.IconSet(sid, "glowColor", { r = r, g = g, b = b, a = a }); touch() end },
            { type = "button", label = L["Reset to group"], width = 140, hostHeight = 28,
              onClick = function() BG.IconReset(sid, "glowEnabled"); BG.IconReset(sid, "glowColor"); touch()
                  if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end },
        } end },

        -- Timer / Title / Stacks: the FULL sub-cadres (show toggle + font/size/colour/outline
        -- + position/offset) so an icon can fully override its group, each with a section
        -- "Reset to group". Built from the SHARED builders bound to the icon accessor bundle.
        TimerSection(iconBundle),
        TitleSection(iconBundle),
        StacksSection(iconBundle),

        { type = "button", label = L["Reset all overrides"], width = 180, hostHeight = 30,
          onClick = function() BG.IconReset(sid); touch()
              if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end },
    }
end

local function EnsureIconEditor()
    if iconEditor then return iconEditor end

    local f = CreateFrame("Frame", "UnbunkUtilityBuffIconEditor", UIParent, "BackdropTemplate")
    f:SetSize(560, 560)
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
    content:SetSize(540, 10)
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

    iconEditor = { frame = f, title = title, scroll = scroll, content = content, sb = sb }
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
local function OpenIconEditor(sid, onChange)
    local ed = EnsureIconEditor()
    editingSid = sid
    onIconEditChange = onChange
    ed.title:SetText(BG.SpellName(sid) or L["Edit icon"])

    local function syncHeight()
        if ed.menu then ed.content:SetHeight(math.max(1, ed.menu.height + 12)) end
        ed.sb.Update()
    end
    -- A Rebuild from a section's reset/toggle re-measures; keep height in sync after it.
    local rawBuild
    ClearIconMenu(ed)
    ed.menu = ns.ui.BuildMenu(ed.content, IconOptions(sid), {
        gap = 10, width = 518, originX = 8, originY = 0, autoHook = false, LSM = LSM,
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
                        warn:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
                        warn:SetPoint("CENTER", b, "CENTER", 0, 0)
                        warn:SetWidth(ICON)
                        warn:SetWordWrap(true)
                        warn:SetJustifyH("CENTER")
                        warn:SetTextColor(1, 0.45, 0.45)
                        warn:SetText(L["Not displayed"])
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
                            GameTooltip:AddLine(L["Not in the Cooldown Manager's tracked buffs — it won't display here."], 1, 0.3, 0.3, true)
                        end
                        GameTooltip:Show()
                    end)
                    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    -- Pencil: open the per-icon override editor. Hidden on the Unused strip
                    -- (a hidden icon has nothing to style). Tinted brand colour when the icon
                    -- carries any override, so the user can see which icons diverge.
                    if groupId ~= 0 then
                        local pb = CreateFrame("Button", nil, b)
                        pb:SetSize(14, 14); pb:SetPoint("CENTER", b, "BOTTOMRIGHT", -7, 3)
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
    -- group directly (GGet/GSet). No reset (a group has nothing above it to inherit), and the
    -- panel's own menu.Refresh keeps the gate checkboxes in sync.
    local function GroupBundle(id)
        return {
            get   = function(key) return BG.GGet(id, key) end,
            set   = function(key, val) BG.GSet(id, key, val) end,
            reset = nil,
            touch = touch,
            refresh = function() if menu then menu.Refresh() end end,
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
        { type = "group", title = L["General"], build = function() return {
            { type = "checkbox", label = L["Enable buff groups"],
              get = function() return BG.Enabled() end,
              set = function(v) BG.SetEnabled(v); touch(); if menu then menu.Refresh() end end },
            { type = "label", font = "UnbunkUtilityH6", height = 30,
              text = L["A custom layout built from the native buff Cooldown Manager. Drag buff icons between groups; each group has its own placement, border and icon size."] },
        } end },
        { type = "group", title = L["Buff groups"], build = function()
            wipe(strips)
            local entries = {}
            for _, g in ipairs(BG.GroupList()) do
                entries[#entries + 1] = GroupCadre(g.id)
            end
            entries[#entries + 1] = UnusedCadre()
            entries[#entries + 1] = { type = "button", label = L["Create group"], width = 160, hostHeight = 30,
                onClick = function() BG.NewGroup(); touch(); rebuild() end }
            return entries
        end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })

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
