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
-- The FLAT (non-group) anchor targets. The four CDM group TYPES are offered PER GROUP via GroupTargets()
-- (shared source in Core/CDMAnchor.lua), so "essential"/"utility" no longer live here as singletons.
local ANCHOR_ORDER = { "belowPlayer", "belowFront", "belowEnd", "screen" }
-- The current spec's resource bars (+ "Last bar") as extra anchor targets, from the shared source. Anchoring
-- a group to a "resbar:*" key rides that resource bar in BOTH modes (native = ContainerAnchor; engine =
-- Layout.ApplyFreePositions). Empty when the spec has no resources.
local function ResBarTargets()
    return (ns.ResourceBarAnchorTargets and ns.ResourceBarAnchorTargets()) or {}
end
-- One entry per GROUP of every type: "Essential (Group 1)", "Utility (Group 2)", "Buffs (Group 1)", "Bars
-- (Group 1)"… excludeKey omits THIS group's own key so it can never anchor to itself.
local function GroupTargets(excludeKey)
    return (ns.CDMGroupAnchorTargets and ns.CDMGroupAnchorTargets(nil, excludeKey)) or {}
end
local function AnchorLabel(key)
    if ns.IsCDMGroupAnchorKey and ns.IsCDMGroupAnchorKey(key) then return ns.CDMGroupAnchorLabel(key) end
    if key == "screen"      then return L["Screen"]                     end
    if key == "belowPlayer" then return L["Below player frame"]         end
    if key == "belowFront"  then return L["Below player frame (front)"] end
    if key == "belowEnd"    then return L["Below player frame (end)"]   end
    if type(key) == "string" and key:match("^resbar:") then
        for _, tgt in ipairs(ResBarTargets()) do if tgt.key == key then return tgt.label end end
        return L["Last bar"] or key   -- stored resbar key whose bar isn't in the current spec
    end
    return tostring(key)
end
local function AnchorList(excludeKey)
    local t = {}
    for _, tgt in ipairs(GroupTargets(excludeKey)) do t[#t + 1] = tgt.label end
    for _, k in ipairs(ANCHOR_ORDER) do t[#t + 1] = AnchorLabel(k) end
    for _, tgt in ipairs(ResBarTargets()) do t[#t + 1] = tgt.label end
    return t
end
local function AnchorFromLabel(label)
    for _, tgt in ipairs(GroupTargets()) do if tgt.label == label then return tgt.key end end
    for _, k in ipairs(ANCHOR_ORDER) do
        if AnchorLabel(k) == label then return k end
    end
    for _, tgt in ipairs(ResBarTargets()) do if tgt.label == label then return tgt.key end end
    -- No match. Return nil so the caller KEEPS the current value instead of clobbering it: a resource-bar /
    -- per-group label fails to resolve here only when its source list is momentarily empty (Detect() / the
    -- group set has no entry yet, e.g. right after login).
    return nil
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
-- Shared icon-customization cadres now live in ns.ui.IconCadres (UI/Shared/IconCadres.lua),
-- bundle-driven and reused across BuffGroups / CDMGroups / CustomCDM / the trackers. Alias the
-- Timer/Title/Stacks sections this panel still calls directly; the per-icon override set and the
-- group Border/Glow/Icon-size cadres now go through the shared builders (IC.OverrideSet / IC.Border
-- / IC.Glow / IC.IconSize) below.
-- ════════════════════════════════════════════════════════════════════════════════
local IC            = ns.ui.IconCadres
local TimerSection  = IC.Timer
local TitleSection  = IC.Title
local StacksSection = IC.Stacks

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

-- Per-icon override accessor bundle (exported so the CustomCDM Buff editor can embed the SAME per-icon
-- override cadres bound to BG.iconCfg[spellId]): reads inherit the group (IconGet), writes override
-- (IconSet), reset drops one key, `has` reports raw per-section override state; touch re-applies the
-- layout; refresh re-renders the host menu.
function BG.MakeIconBundle(sid, touch, refresh)
    return {
        get      = function(key) return BG.IconGet(sid, key) end,
        groupGet = function(key) return BG.GGet(BG.GroupOf(sid), key) end,
        set      = function(key, val) BG.IconSet(sid, key, val) end,
        reset    = function(key) BG.IconReset(sid, key) end,
        has      = function(keys)
            for _, key in ipairs(keys) do if BG.IconHasOverride(sid, key) then return true end end
            return false
        end,
        touch    = touch,
        refresh  = refresh,
    }
end

-- The ordered per-icon OVERRIDE cadres for a BUFF — a thin wrapper over the shared assembler
-- ns.ui.IconCadres.OverrideSet (buff variant: no CDM settings, buff glow, buff start/stop sound).
-- Parameterised over `bundle` (BG.MakeIconBundle) + `ctx` (touch via the bundle; refreshLight/rebuild/
-- reopen/omit) so BOTH the Buff-groups pencil and the CustomCDM Buff editor render the SAME inner
-- layout. ctx.omit.{label,sound,placeholder} drop those chrome entries.
function BG.IconOverrideSections(sid, bundle, ctx)
    ctx = ctx or {}
    local entries = IC.OverrideSet(bundle, {
        refresh = ctx.refreshLight or ctx.rebuild,
        rebuild = ctx.rebuild,
        reopen  = ctx.reopen or ctx.rebuild,
    }, {
        type            = "buff",
        omit            = ctx.omit,
        iconSizeDefault = 32,
    })
    -- For a buff not in the native Cooldown Manager (red in the strip), warn at the TOP of the editor,
    -- between the spell title and the "Overrides..." line.
    if BG.DisplayedKnown() and not BG.IsDisplayable(sid) then
        table.insert(entries, 1, { type = "label", font = "UnbunkUtilityH6", height = 30,
            color = { 1, 0.3, 0.3 },
            text = L["Not in the Cooldown Manager's tracked buffs — it won't display."] })
    end
    return entries
end

-- The Buff-groups pencil's option tree: the shared override cadres bound to the singleton editor popup.
local function IconOptions(sid)
    local function touch() BG.ApplyAll(); if onIconEditChange then onIconEditChange() end end
    local function rebuildMenu() if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end
    local function refreshMenu() if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end
    return BG.IconOverrideSections(sid, BG.MakeIconBundle(sid, touch, rebuildMenu), {
        touch = touch, rebuild = rebuildMenu, refreshLight = refreshMenu,
        reopen = function() OpenIconEditor(sid, onIconEditChange) end,
    })
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

    -- The "+" tile opens the shared CustomCDM Buff editor (ns.CustomCDM.PromptAddBuffToGroup), the same
    -- template as the Free-icons "+ -> Buff", pre-set to live in the clicked group as a bridged buff —
    -- so custom buffs are authored + managed identically everywhere (replaces the old quick-add popup).

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
                -- Open the SAME Buff template as the Free-icons "+" (CustomCDM Buff editor), pre-set to
                -- live in this buff group (a bridged CustomCDM buff). Replaces the old quick-add/spellID
                -- popup so custom buffs are created + managed the same way everywhere.
                addb:SetScript("OnClick", function()
                    if ns.CustomCDM and ns.CustomCDM.PromptAddBuffToGroup then
                        ns.CustomCDM.PromptAddBuffToGroup(groupId)
                    end
                end)
                obj.addBtn = addb

                -- Red "Row is full" caption over the strip on a high overlay, shown when a (non-wrap)
                -- group is at GROUP_CAP. The "+" already hides at the cap (relayout) and drops into a full
                -- group are rejected, so nothing shifts — this mirrors the CDMGroups full-row feedback.
                obj.fullOverlay = CreateFrame("Frame", nil, frame)
                obj.fullOverlay:SetAllPoints(frame)
                obj.fullOverlay:SetFrameLevel(frame:GetFrameLevel() + 20)
                obj.fullOverlay:Hide()
                local bfull = obj.fullOverlay:CreateFontString(nil, "OVERLAY")
                bfull:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
                bfull:SetTextColor(1, 0.45, 0.45)
                bfull:SetText(L["Row is full"])
                bfull:SetPoint("CENTER", obj.fullOverlay, "CENTER", 0, 0)

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

                    -- A CustomCDM-owned mirror (a bridged buff) is managed from the Free-icons Buff
                    -- editor, not here — no delete cross, so deleting it there can't orphan the source.
                    local cdef = BG.GetCustom and BG.GetCustom(spellId)
                    if BG.IsCustom(spellId) and not (cdef and cdef.owner) then
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
                        if obj.fullOverlay then obj.fullOverlay:Hide() end
                    else
                        addb:Hide()
                        -- Transient: show "Row is full" ONLY while a foreign icon is dragged over the full
                        -- group (holeIndex set). At rest — relayout(nil, nil) — it stays hidden.
                        if obj.fullOverlay then obj.fullOverlay:SetShown(holeIndex ~= nil) end
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

    -- ── Per-group Icon size (W / H) — the shared IC.IconSize fed a plain group bundle (no
    -- override toggle); IconsGroup prints its own "Icon size" label above, so opts.label = false.
    local function IconSizeEntry(id)
        return IC.IconSize({
            get   = function(key) return BG.GGet(id, key) end,
            set   = function(key, val) BG.GSet(id, key, val) end,
            touch = touch,
        }, { bare = true, label = false, kw = "iconW", kh = "iconH", max = 256, defaultW = 32, defaultH = 32 })
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

    -- Light vs full menu re-render for the shared Border/Glow cadres in the GROUP panel: a checkbox
    -- toggle re-greys via Refresh (mirrors what these inline cadres did before).
    local groupCtx = {
        refresh = function() if menu then menu.Refresh() end end,
        rebuild = function() if menu then menu.Rebuild() end end,
    }

    -- ── Sub-cadres of "Group settings" ─────────────────────────────────────────────
    local function PositionGroup(id)
        return { type = "group", title = L["Position"], build = function() return {
            { type = "dropdown", label = L["Anchor to"], width = 180, height = 50,
              getList = function() return AnchorList("buff:" .. id) end,   -- exclude this group's own key
              getCurrentKey = function() return AnchorLabel(BG.GGet(id, "anchorTo")) end,
              onSelect = function(label) local k = AnchorFromLabel(label); if k then BG.GSet(id, "anchorTo", k); touch() end end },
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

    -- Group Border / Glow — shared IC builders fed a plain group bundle. Border default ON
    -- (~= false); Glow = buff variant ("Show glow" + colour, no glow-type dropdown).
    local function BorderGroup(id) return IC.Border(GroupBundle(id), { defaultOn = true, ctx = groupCtx, nativeBorder = true }) end
    local function GlowGroup(id)   return IC.Glow(GroupBundle(id), { variant = "buff", ctx = groupCtx }) end

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
          headerExtra = ns.ui.SettingsHeaderIcon,
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
          shown = function() return not (ns.CDMMode and ns.CDMMode.IsEngine()) end,   -- native-only toggle: hidden in engine mode (the engine renders this category regardless)
          get = function() return BG.Enabled() end,
          set = function(v) BG.SetEnabled(v); touch(); if menu then menu.Refresh() end end },
        -- The module's global cadre: every group cadre + Create group + Unused live inside it. It
        -- greys/blocks as a whole when the module is disabled.
        { type = "group", title = L["Buff groups"],
          enabledBy = function() return BG.Enabled() or (ns.CDMMode and ns.CDMMode.IsEngine()) end,   -- editable in engine mode too (same config drives the engine)
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

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Buffs"], nil, CreateBuffsPanel)
end)
