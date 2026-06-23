-- Modules/BarGroups/UI/ConfigWindow.lua
-- "Bars" panel: a "Bar groups" cadre holding one sub-cadre per group, an "Unused" sub-cadre and
-- a "Create group" button — the SAME group model as the Buffs panel, but driving the native BAR
-- viewer (BuffBarCooldownViewer). Each group cadre lays out as:
--   [group name input]
--   the draggable bar strip (reorder / move between groups)
--   "Copy native CDM order" button
--   a COLLAPSIBLE "Group settings" with: Position (anchor / placement / grow / spacing / drag)
--     and Bar style (bar colour, background colour, icon position, fill direction, height, width).
-- Per-GROUP settings apply to every bar in the group; a PENCIL on each tile opens a per-BAR
-- override editor writing the same bar keys via BR.IconSet, PLUS a custom-name override
-- ("Override name" checkbox + text input). Drag-to-reorder works exactly like the Buffs strip.

local _, ns = ...
local L  = ns.L
local BR = ns.BarGroups

local ICON, PAD = 30, 4
local STEP = ICON + 6       -- horizontal step (icon + 6px gap)
local GAP_BG = 6            -- vertical gap between wrapped rows
local PER_ROW = 12          -- icons per row (groups cap here; Unused wraps to more rows)
local GROUP_CAP = BR.GROUP_CAP or 12

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ── anchorTo / growDir / relPos / iconPosition / fillDirection option maps ──────
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
    for _, k in ipairs(ANCHOR_ORDER) do if AnchorLabel(k) == label then return k end end
    return "utility"
end

-- Bars stack vertically, so only DOWN / UP are exposed.
local GROW_ORDER = { "DOWN", "UP" }
local function GrowLabel(key) if key == "UP" then return L["Up"] end return L["Down"] end
local function GrowList()
    local t = {}
    for _, k in ipairs(GROW_ORDER) do t[#t + 1] = GrowLabel(k) end
    return t
end
local function GrowFromLabel(label)
    for _, k in ipairs(GROW_ORDER) do if GrowLabel(k) == label then return k end end
    return "DOWN"
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
    for _, k in ipairs(RELPOS_ORDER) do if RelPosLabel(k) == label then return k end end
    return "below"
end

local ICONPOS_ORDER = { "LEFT", "RIGHT", "HIDDEN" }
local function IconPosLabel(key)
    if key == "RIGHT"  then return L["Right"]  end
    if key == "HIDDEN" then return L["Hidden"] end
    return L["Left"]
end
local function IconPosList()
    local t = {}
    for _, k in ipairs(ICONPOS_ORDER) do t[#t + 1] = IconPosLabel(k) end
    return t
end
local function IconPosFromLabel(label)
    for _, k in ipairs(ICONPOS_ORDER) do if IconPosLabel(k) == label then return k end end
    return "LEFT"
end

local FILL_ORDER = { "LEFT", "RIGHT" }
local function FillLabel(key) if key == "RIGHT" then return L["Right"] end return L["Left"] end
local function FillList()
    local t = {}
    for _, k in ipairs(FILL_ORDER) do t[#t + 1] = FillLabel(k) end
    return t
end
local function FillFromLabel(label)
    for _, k in ipairs(FILL_ORDER) do if FillLabel(k) == label then return k end end
    return "LEFT"
end

-- ── Shared override helpers (mirror the Buffs panel's OverrideToggle / CopyGroupButton) ──
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

-- "Override group settings" — the per-BAR, per-section checkbox at the top of each override
-- sub-cadre (pencil editor only; nil in the group context). Checked = the section is overridden;
-- checking it seeds each key to the current EFFECTIVE (group) value (deep-cloned), unchecking it
-- resets each key back to the group.
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

-- "Copy group settings" — re-sync an overriding section to the group's current values.
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

-- A section's inner controls grey out while it INHERITS the group (no key overridden); they light
-- up once the override toggle is checked. nil in the group context (controls always live).
local function SectionOverridden(bundle, keys)
    if not bundle.has then return nil end
    return function() return bundle.has(keys) end
end

-- ── Bundle-based bar control builders (used by BOTH the group panel and the pencil editor) ──
local function ColorEntry(bundle, key, label, gated)
    return { type = "textEditor", label = label,
        showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
        enabledBy = gated,
        getColor = function() return bundle.get(key) end,
        onColorChange = function(r, g, b, a) bundle.set(key, { r = r, g = g, b = b, a = a }); bundle.touch() end }
end
local function DropEntry(bundle, key, label, listFn, labelFn, fromLabelFn, gated)
    return { type = "dropdown", label = label, width = 180, height = 50, enabledBy = gated,
        getList = listFn,
        getCurrentKey = function() return labelFn(bundle.get(key)) end,
        onSelect = function(lbl) bundle.set(key, fromLabelFn(lbl)); bundle.touch() end }
end
local function NumEntry(bundle, key, label, mn, mx, gated)
    return { type = "textinput", label = label, width = 60, numeric = true, min = mn, max = mx, maxLetters = 4,
        enabledBy = gated,
        get = function() return bundle.get(key) or mn end,
        set = function(v) if v ~= nil then bundle.set(key, v); bundle.touch() end end }
end
-- The saved texture key if it's a registered LSM statusbar, else the bundled default — so the
-- dropdown's shown label matches what actually renders.
local function EffectiveTexture(key)
    if key and LSM and LSM:IsValid("statusbar", key) then return key end
    if LSM and LSM:IsValid("statusbar", "Better Blizzard") then return "Better Blizzard" end
    return key or "Better Blizzard"
end
local function TextureEntry(bundle, gated)
    return { type = "dropdown", label = L["Bar texture"], width = 220, height = 50, searchable = true,
        enabledBy = gated,
        getList = function() return LSM and LSM:List("statusbar") or {} end,
        getCurrentKey = function() return EffectiveTexture(bundle.get("barTexture")) end,
        onSelect = function(lbl) bundle.set("barTexture", lbl); bundle.touch() end }
end

-- Key groups for the override sections.
local COLOR_KEYS  = { "barTexture", "barColor", "bgColor" }
local LAYOUT_KEYS = { "iconPosition", "fillDirection", "invertFill" }
local SIZE_KEYS   = { "barWidth", "barHeight" }
local VISUAL_KEYS = { "barTexture", "barColor", "bgColor", "iconPosition", "fillDirection", "invertFill", "barWidth", "barHeight" }

-- The shared "Bar style" controls for a bundle, optionally gated (pencil sections grey while
-- inheriting). Returns the three logical blocks' worth of entries flat so the group panel can
-- render them directly; the pencil wraps each block in its own override sub-cadre instead.
local function ColorBlock(bundle, gated)
    return {
        TextureEntry(bundle, gated),
        ColorEntry(bundle, "barColor", L["Bar color"], gated),
        ColorEntry(bundle, "bgColor",  L["Background color"], gated),
    }
end
local function LayoutBlock(bundle, gated)
    return {
        DropEntry(bundle, "iconPosition",  L["Icon position"], IconPosList, IconPosLabel, IconPosFromLabel, gated),
        DropEntry(bundle, "fillDirection", L["Fill direction"], FillList, FillLabel, FillFromLabel, gated),
        { type = "checkbox", label = L["Invert fill"], enabledBy = gated,
          get = function() return bundle.get("invertFill") == true end,
          set = function(v) bundle.set("invertFill", v and true or false); bundle.touch() end },
    }
end
local function SizeBlock(bundle, gated)
    return {
        NumEntry(bundle, "barWidth",  L["Bar width"],  10, 1024, gated),
        NumEntry(bundle, "barHeight", L["Bar height"],  4,  256, gated),
    }
end

-- ════════════════════════════════════════════════════════════════════════════════
-- Per-BAR override editor (the pencil): a movable, scrollable popup hosting a BuildMenu scoped
-- to ONE bar's sparse override. Each section leads with an "Override group settings" checkbox;
-- the Name section's "Override name" checkbox IS its own gate (no inherit-from-group name).
-- ════════════════════════════════════════════════════════════════════════════════
local iconEditor       -- singleton { frame, scroll, content, sb, menu }
local editingSid       -- the spell id currently shown
local onIconEditChange -- set per-open: re-applies the layout + refreshes the panel strip
local OpenIconEditor   -- fwd decl

local function MakeIconBundle(sid, touch, refresh)
    return {
        get      = function(key) return BR.IconGet(sid, key) end,
        groupGet = function(key) return BR.GGet(BR.GroupOf(sid), key) end,
        set      = function(key, val) BR.IconSet(sid, key, val) end,
        reset    = function(key) BR.IconReset(sid, key) end,
        has      = function(keys)
            for _, key in ipairs(keys) do if BR.IconHasOverride(sid, key) then return true end end
            return false
        end,
        touch    = touch,
        refresh  = refresh,
    }
end

-- The ordered per-bar OVERRIDE cadres (Bar colors, Bar layout, Bar size, Name, Copy-all + the
-- not-displayable warning).
local function BarOverrideSections(sid, bundle, ctx)
    ctx = ctx or {}
    local touch = ctx.touch or function() end
    local function menuRefresh() if ctx.refreshLight then ctx.refreshLight() elseif ctx.rebuild then ctx.rebuild() end end
    local function menuRebuild() if ctx.rebuild then ctx.rebuild() end end

    local entries = {
        { type = "label", font = "UnbunkUtilityH6", height = 30,
          text = L["Tick \"Override group settings\" in a section to give this bar its own values; untick it to inherit the group again."] },

        -- Bar colours (bar fill + background).
        { type = "group", title = L["Bar colors"], build = function()
            local gated = SectionOverridden(bundle, COLOR_KEYS)
            local e = {}
            append(e, OverrideToggle(bundle, COLOR_KEYS))
            append(e, CopyGroupButton(bundle, COLOR_KEYS, gated))
            for _, en in ipairs(ColorBlock(bundle, gated)) do e[#e + 1] = en end
            return e
        end },

        -- Bar layout (icon position + fill direction).
        { type = "group", title = L["Bar layout"], build = function()
            local gated = SectionOverridden(bundle, LAYOUT_KEYS)
            local e = {}
            append(e, OverrideToggle(bundle, LAYOUT_KEYS))
            append(e, CopyGroupButton(bundle, LAYOUT_KEYS, gated))
            for _, en in ipairs(LayoutBlock(bundle, gated)) do e[#e + 1] = en end
            return e
        end },

        -- Bar size (width + height).
        { type = "group", title = L["Bar size"], build = function()
            local gated = SectionOverridden(bundle, SIZE_KEYS)
            local e = {}
            append(e, OverrideToggle(bundle, SIZE_KEYS))
            append(e, CopyGroupButton(bundle, SIZE_KEYS, gated))
            for _, en in ipairs(SizeBlock(bundle, gated)) do e[#e + 1] = en end
            return e
        end },

        -- Name override (per-bar custom name). The checkbox IS the override gate — there's no
        -- group-level custom name to inherit; unchecked = the native spell name shows.
        { type = "group", title = L["Name"], build = function() return {
            { type = "checkbox", label = L["Override name"],
              get = function() return BR.IconGet(sid, "nameOverride") == true end,
              set = function(v) BR.IconSet(sid, "nameOverride", v and true or false); touch(); menuRefresh() end },
            { type = "textinput", label = L["Custom name"], width = 240, maxLetters = 60,
              enabledBy = function() return BR.IconGet(sid, "nameOverride") == true end,
              get = function() return BR.IconGet(sid, "customName") or "" end,
              set = function(v) BR.IconSet(sid, "customName", v or ""); touch() end },
        } end },

        -- Make the bar a FULL copy of its group's visual settings (the name override is left as-is).
        { type = "button", label = L["Copy all group settings"], width = 180, hostHeight = 30,
          onClick = function()
              local gid = BR.GroupOf(sid)
              for _, key in ipairs(VISUAL_KEYS) do BR.IconSet(sid, key, CloneVal(BR.GGet(gid, key))) end
              touch()
              menuRebuild()
          end },
    }

    if BR.DisplayedKnown() and not BR.IsDisplayable(sid) then
        table.insert(entries, 1, { type = "label", font = "UnbunkUtilityH6", height = 30,
            color = { 1, 0.3, 0.3 },
            text = L["Not in the Cooldown Manager's bar viewer — it won't display."] })
    end
    return entries
end

local function IconOptions(sid)
    local function touch() BR.ApplyAll(); if onIconEditChange then onIconEditChange() end end
    local function rebuildMenu() if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end
    local function refreshMenu() if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end
    return BarOverrideSections(sid, MakeIconBundle(sid, touch, rebuildMenu), {
        touch = touch, rebuild = rebuildMenu, refreshLight = refreshMenu,
    })
end

local function EnsureIconEditor()
    if iconEditor then return iconEditor end

    local f = CreateFrame("Frame", "UnbunkUtilityBarOverrideEditor", UIParent, "BackdropTemplate")
    f:SetSize(600, 560)
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
    tinsert(UISpecialFrames, "UnbunkUtilityBarOverrideEditor")   -- ESC closes

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

function OpenIconEditor(sid, onChange)
    local ed = EnsureIconEditor()
    editingSid = sid
    onIconEditChange = onChange
    ed.title:SetText(BR.SpellName(sid) or L["Edit icon"])
    local tex = BR.SpellTexture(sid)
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
-- The Bars panel.
-- ════════════════════════════════════════════════════════════════════════════════
local function CreateBarsPanel(parent)
    local menu
    local function rebuild() if menu then menu.Rebuild() end end
    local function touch() BR.ApplyAll() end

    BR.pe = {}
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
        if sid and hovered then
            local full = hovered.groupId ~= 0 and BR.GroupOf(sid) ~= hovered.groupId
                and #BR.GetGroupBuffs(hovered.groupId) >= GROUP_CAP
            if not full then BR.MoveBuff(sid, hovered.groupId, hole); touch() end
        end
        rebuild()
    end

    -- A draggable bar strip for one group (groupId 0 = Unused). Shows ALL bars assigned to the
    -- group (active or not) so they can be reordered; the in-game layout only draws active ones.
    local function BarStripEntry(groupId)
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

                local function placeAt(f, slot)
                    f:ClearAllPoints()
                    if wrap then
                        local col, row = slot % PER_ROW, math.floor(slot / PER_ROW)
                        f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * STEP, -(PAD + row * (ICON + GAP_BG)))
                    else
                        f:SetPoint("LEFT", frame, "LEFT", PAD + slot * STEP, 0)
                    end
                end

                -- Red "Row is full" caption, shown only while a foreign bar is dragged over a full group.
                obj.fullOverlay = CreateFrame("Frame", nil, frame)
                obj.fullOverlay:SetAllPoints(frame)
                obj.fullOverlay:SetFrameLevel(frame:GetFrameLevel() + 20)
                obj.fullOverlay:Hide()
                local bfull = obj.fullOverlay:CreateFontString(nil, "OVERLAY")
                bfull:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
                bfull:SetTextColor(1, 0.45, 0.45)
                bfull:SetText(L["Row is full"])
                bfull:SetPoint("CENTER", obj.fullOverlay, "CENTER", 0, 0)

                for _, sid in ipairs(BR.GetGroupBuffs(groupId)) do
                    local spellId = sid
                    local b = CreateFrame("Button", nil, frame)
                    b:SetSize(ICON, ICON)
                    local bord = b:CreateTexture(nil, "BACKGROUND")
                    bord:SetPoint("TOPLEFT", -1, 1); bord:SetPoint("BOTTOMRIGHT", 1, -1); bord:SetColorTexture(0.4, 0.4, 0.4, 1)
                    local tex = b:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints(); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); tex:SetTexture(BR.SpellTexture(spellId))
                    b:RegisterForDrag("LeftButton")
                    b:SetScript("OnDragStart", function() startDrag(b, spellId) end)
                    b:SetScript("OnDragStop", function() stopDrag() end)

                    -- A bar not in the native bar viewer's pool has no native frame: in a real group it
                    -- can never show, so flag the tile RED. The Unused strip is never flagged.
                    local undisplayable = groupId ~= 0 and BR.DisplayedKnown() and not BR.IsDisplayable(spellId)
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

                    b:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local shown = false
                        if C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId) then
                            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, spellId)
                        end
                        if not shown then GameTooltip:SetText(BR.SpellName(spellId), 1, 1, 1) end
                        if undisplayable then
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(L["Not in the Cooldown Manager's bar viewer — it won't display."], 1, 0.3, 0.3, true)
                        end
                        GameTooltip:Show()
                    end)
                    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    -- Pencil: open the per-bar override editor (hidden on the Unused strip). Tinted
                    -- brand colour when the bar carries any override.
                    if groupId ~= 0 then
                        local pb = CreateFrame("Button", nil, b)
                        pb:SetSize(14, 14); pb:SetPoint("CENTER", b, "TOPLEFT", 4, -4)
                        pb:SetFrameLevel(b:GetFrameLevel() + 5)
                        local pbg = pb:CreateTexture(nil, "BACKGROUND"); pbg:SetAllPoints(); pbg:SetColorTexture(0, 0, 0, 0.6)
                        local pg = pb:CreateTexture(nil, "OVERLAY"); pg:SetPoint("CENTER"); pg:SetSize(10, 10)
                        pg:SetTexture(UNBUNK_ICON_PEN_WHITE)
                        local function paint() if BR.IconHasOverride(spellId) then pg:SetVertexColor(ns.GetBrandColor()) else pg:SetVertexColor(1, 1, 1) end end
                        paint()
                        pb:SetScript("OnEnter", function() pg:SetVertexColor(ns.GetBrandColor()) end)
                        pb:SetScript("OnLeave", paint)
                        pb:SetScript("OnClick", function() OpenIconEditor(spellId, rebuild) end)
                    end

                    obj.tiles[#obj.tiles + 1] = { frame = b, spellId = spellId }
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
                                if wrap and tb then
                                    local tcy  = tb + ICON / 2
                                    local band = (ICON + GAP_BG) / 2
                                    if tcy > my + band then
                                        before = true
                                    elseif tcy < my - band then
                                        before = false
                                    else
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

                function obj.relayout(dragSpell, holeIndex)
                    local seq = {}
                    for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then seq[#seq + 1] = t end end
                    local slot = 0
                    for i, t in ipairs(seq) do
                        if holeIndex and (i - 1) == holeIndex then slot = slot + 1 end
                        placeAt(t.frame, slot); t.frame:Show()
                        slot = slot + 1
                    end
                    if not wrap and #seq >= (cap or math.huge) then
                        -- Transient: "Row is full" ONLY while a foreign bar hovers a full group.
                        if obj.fullOverlay then obj.fullOverlay:SetShown(holeIndex ~= nil) end
                    elseif obj.fullOverlay then
                        obj.fullOverlay:Hide()
                    end
                end

                obj.relayout(nil, nil)

                local items = math.max(1, #obj.tiles)
                local rows  = wrap and math.max(1, math.ceil(items / PER_ROW)) or 1
                local h = PAD * 2 + rows * ICON + math.max(0, rows - 1) * GAP_BG
                host:SetHeight(h)
                return { frame = host, height = h }
            end,
        }
    end

    -- ── The GROUP accessor bundle for the shared bar-style controls ───────────────
    local function GroupBundle(id)
        return {
            get   = function(key) return BR.GGet(id, key) end,
            set   = function(key, val) BR.GSet(id, key, val) end,
            reset = nil,
            touch = touch,
            refresh = rebuild,
        }
    end

    -- ── Sub-cadres of "Group settings" ─────────────────────────────────────────────
    local function PositionGroup(id)
        return { type = "group", title = L["Position"], build = function()
          local e = {}
          -- Changing the anchor toggles whether Placement is shown (Screen is always centred, so it
          -- has no side/corner) — rebuild (deferred so the open dropdown isn't torn down mid-select).
          e[#e + 1] = { type = "dropdown", label = L["Anchor to"], width = 180, height = 50,
              getList = AnchorList,
              getCurrentKey = function() return AnchorLabel(BR.GGet(id, "anchorTo")) end,
              onSelect = function(label)
                  BR.GSet(id, "anchorTo", AnchorFromLabel(label)); touch()
                  if C_Timer and C_Timer.After then C_Timer.After(0, rebuild) else rebuild() end
              end }
          -- Placement (side/corner of the anchor) is meaningless when anchored to the screen centre.
          if BR.GGet(id, "anchorTo") ~= "screen" then
              e[#e + 1] = { type = "dropdown", label = L["Placement"], width = 180, height = 50,
                  getList = RelPosList,
                  getCurrentKey = function() return RelPosLabel(BR.GGet(id, "relPos")) end,
                  onSelect = function(label) BR.GSet(id, "relPos", RelPosFromLabel(label)); touch() end }
          end
          e[#e + 1] = { type = "dropdown", label = L["Grow direction"], width = 180, height = 50,
              getList = GrowList,
              getCurrentKey = function() return GrowLabel(BR.GGet(id, "growDir")) end,
              onSelect = function(label) BR.GSet(id, "growDir", GrowFromLabel(label)); touch() end }
          for _, en in ipairs({
            { type = "checkbox", label = L["Static Display"],
              get = function() return BR.GGet(id, "staticDisplay") == true end,
              set = function(v) BR.GSet(id, "staticDisplay", v and true or false); touch() end },
            { type = "textinput", label = L["Spacing"], width = 46, numeric = true, min = 0, max = 64, maxLetters = 2,
              get = function() return BR.GGet(id, "spacing") or 1 end,
              set = function(v) if v ~= nil then BR.GSet(id, "spacing", v); touch() end end },
            { type = "position", ref = "pe",
              onBuilt = function(w) BR.pe[id] = w end,
              label = L["Group position (offset from anchor)"],
              getX = function() return BR.GGet(id, "posX") end,
              getY = function() return BR.GGet(id, "posY") end,
              onApply = function(x, yv)
                  if x  then BR.GSet(id, "posX", x)  end
                  if yv then BR.GSet(id, "posY", yv) end
                  touch()
              end,
              onUnlock   = function() BR.SetGroupUnlocked(id, true) end,
              onLock     = function() BR.SetGroupUnlocked(id, false); if BR.pe[id] then BR.pe[id].Refresh() end end,
              isUnlocked = function() return BR.IsGroupUnlocked(id) end },
          }) do e[#e + 1] = en end
          return e
        end }
    end

    local function BarStyleGroup(id)
        return { type = "group", title = L["Bar style"], build = function()
            local gb = GroupBundle(id)
            local e = {}
            for _, en in ipairs(ColorBlock(gb, nil))  do e[#e + 1] = en end
            for _, en in ipairs(LayoutBlock(gb, nil)) do e[#e + 1] = en end
            for _, en in ipairs(SizeBlock(gb, nil))   do e[#e + 1] = en end
            return e
        end }
    end

    local function GroupSettingsSection(id)
        return { type = "section", label = L["Group settings"], showCheckbox = false,
          headerExtra = ns.ui.SettingsHeaderIcon,
          getCollapsed = function() return BR.GGet(id, "cfgCollapsed") ~= false end,
          onCollapse   = function(c)
              BR.GSet(id, "cfgCollapsed", c and true or false)
              if C_Timer and C_Timer.After then C_Timer.After(0, rebuild) else rebuild() end
          end,
          build = function() return {
            PositionGroup(id),
            BarStyleGroup(id),
        } end }
    end

    local function GroupCadre(id)
        local title = (BR.GGet(id, "name") or ("Group " .. id))
        return { type = "group", title = title, build = function()
            local e = {
                { type = "textinput", label = L["Group name"], width = 200, maxLetters = 32,
                  get = function() return BR.GGet(id, "name") or "" end,
                  set = function(v) BR.GSet(id, "name", v or ""); rebuild() end },
                BarStripEntry(id),
                { type = "button", label = L["Copy native CDM order"], width = 200, hostHeight = 30,
                  onClick = function() BR.SortGroupNativeOrder(id); touch(); rebuild() end },
                GroupSettingsSection(id),
            }
            if id ~= 1 then
                e[#e + 1] = { type = "button", label = L["Delete group"], width = 160, hostHeight = 30,
                    onClick = function() BR.RemoveGroup(id); touch(); rebuild() end }
            end
            return e
        end }
    end

    local function UnusedCadre()
        return { type = "group", title = L["Unused"], build = function() return {
            { type = "label", font = "UnbunkUtilityH6", height = 18,
              text = L["Bars here are hidden. Drag them onto a group to show them."] },
            BarStripEntry(0),
        } end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Bars"] },
        { type = "checkbox", label = L["Enable custom CDM Bars"],
          get = function() return BR.Enabled() end,
          set = function(v)
              BR.SetEnabled(v)
              -- Live transition: on enable do a full bring-up (re-hook + re-seed + relayout) since
              -- login/events skip work while off; on disable RefreshLayout falls through to HideAll.
              if v then BR.HookNativeViewerPublic(); BR.Rebuild() else BR.ApplyAll() end
              if menu then menu.Refresh() end
              -- The native bar viewer only comes up cleanly through a fresh login/reload, so on ENABLE
              -- offer a reload (the live bring-up above is best-effort only).
              if v then
                  ns.ui.ShowConfirm({
                      title = L["Enable custom CDM Bars"],
                      text = L["This feature requires a reload to function."],
                      acceptText = L["Reload"],
                      cancelText = L["Later"],
                      onAccept = function()
                          if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
                      end,
                  })
              end
          end },
        { type = "label", font = "UnbunkUtilityBody", height = 30,
          text = L["A custom layout built from the native bar Cooldown Manager. Enable the \"Buff Bar\" viewer in Blizzard's Edit Mode for bars to appear."] },
        { type = "group", title = L["Bar groups"],
          enabledBy = function() return BR.Enabled() end,
          build = function()
            wipe(strips)
            local entries = {}
            for _, g in ipairs(BR.GroupList()) do
                entries[#entries + 1] = GroupCadre(g.id)
            end
            entries[#entries + 1] = { type = "button", label = L["Create group"], width = 160, hostHeight = 30,
                onClick = function() BR.NewGroup(); touch(); rebuild() end }
            entries[#entries + 1] = UnusedCadre()
            return entries
        end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })

    BR.onDisplayedChanged = function()
        if menu and parent and parent:IsShown() then rebuild() end
        if iconEditor and iconEditor.frame and iconEditor.frame:IsShown() and editingSid then
            OpenIconEditor(editingSid, onIconEditChange)
        end
    end

    parent:HookScript("OnHide", function()
        for _, g in ipairs(BR.GroupList()) do
            BR.GSet(g.id, "cfgCollapsed", true)
        end
    end)
    parent:HookScript("OnShow", function()
        if menu then menu.Rebuild() end
    end)

    return menu
end

local initBR = CreateFrame("Frame")
initBR:RegisterEvent("ADDON_LOADED")
initBR:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Bars"], nil, CreateBarsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
