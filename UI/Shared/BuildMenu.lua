-- UI/Shared/BuildMenu.lua
-- Declarative menu generator. Replaces the imperative "content frame + local
-- AddModule + per-widget SetPoint + hand-written OnShow" boilerplate found in
-- Modules/*/UI/ConfigWindow.lua. It does NOT add a new widget layer: it CALLS
-- the existing ns.ui.Create* constructors and stacks their .frame exactly like
-- AddModule does today, so the rendered panel is indistinguishable from the
-- current one (same widgets, order, callbacks, 518 width, GAP, OnShow re-sync).
--
-- Usage:
--   local menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
--   -- options is an ordered array of entry tables (see ENTRY TYPES below).
--   -- menu.content / menu.Refresh / menu.refs / menu.frames / menu.widgets / menu.height
--
-- See the design spec for the full contract. Each entry maps 1:1 onto an
-- existing widget; defaults (~= false / == true / or <default>) live entirely
-- in the caller's get closures — BuildMenu never injects defaults.

local _, ns = ...
ns.ui = ns.ui or {}

-- ── Disable gate ─────────────────────────────────────────────────────────────
-- Shared helper to "grey out" a set of controls when the option that drives them is
-- unchecked: the controls are no longer functional, so fade them and swallow CLICKS
-- over their region so they can't reach the now-inert widgets. The mouse WHEEL is
-- forwarded up to the nearest scrollable ancestor so the config window still scrolls
-- when the cursor is over a greyed region (swallowing it froze the scrollbar).
--
-- MakeDisableGate(blockerHost) returns Apply(enabled, dimFrames, master):
--   * dimFrames : frames faded to 0.4 when disabled (their children fade too), 1 when enabled.
--   * blockerHost : a transparent click-eating overlay is laid over this frame while disabled.
--   * master    : optional frame (the CONTROLLING checkbox, when it sits inside the
--                 blocked region) raised above the overlay so it stays clickable.
function ns.ui.MakeDisableGate(blockerHost)
    local blocker
    return function(enabled, dimFrames, master)
        if dimFrames then
            for _, f in ipairs(dimFrames) do f:SetAlpha(enabled and 1 or 0.4) end
        end
        if enabled then
            if blocker then blocker:Hide() end
            return
        end
        if not blocker then
            blocker = CreateFrame("Frame", nil, blockerHost)
            blocker:SetAllPoints(blockerHost)
            blocker:SetFrameLevel((blockerHost:GetFrameLevel() or 0) + 500)
            blocker:EnableMouse(true)          -- eat clicks on the inert controls
            blocker:EnableMouseWheel(true)     -- but forward the wheel so scrolling still works
            blocker:SetScript("OnMouseWheel", function(self, delta)
                local p = self:GetParent()
                while p do
                    if p:IsMouseWheelEnabled() then
                        local h = p:GetScript("OnMouseWheel")
                        if h then h(p, delta) end
                        return
                    end
                    p = p:GetParent()
                end
            end)
        end
        blocker:Show()
        if master then master:SetFrameLevel(blocker:GetFrameLevel() + 10) end
    end
end

-- Horizontal inset of a group box's content from its border (also the visual
-- indent of a nested sub-box from its parent box).
local GROUP_SIDEPAD = 10

-- ── Per-type default host heights (for widgets with no intrinsic height) ──────
local DEFAULT_HEIGHTS = {
    checkbox  = 24,
    textinput = 22,
    label     = 20,
    header    = 20,
    row       = 0,
    custom    = 0,
}

-- Resolve a point spec's relativeTo. `relSpec` may be:
--   nil              -> default relative frame (caller-provided)
--   "$ref"           -> the primary frame of a previously-built sibling by ref
--   a frame object   -> used as-is
local function ResolveRelative(relSpec, defaultFrame, refs)
    if relSpec == nil then
        return defaultFrame
    end
    if type(relSpec) == "string" then
        local refName = relSpec:match("^%$(.+)$")
        if refName and refs[refName] then
            local w = refs[refName]
            return w.frame or w
        end
        return defaultFrame
    end
    -- Already a frame (or frame-like) object.
    return relSpec
end

-- Build a single leaf control (no stacking, no width) into `host`, positioning
-- it relative to `defaultRel` using entry.point when provided. Returns the
-- widget result and appends any refresher closure to `refreshers`. Used both
-- for inline children and row children.
local function BuildChild(entry, host, defaultRel, refs, refreshers, result)
    local t = entry.type
    local widget

    if t == "checkbox" then
        widget = ns.ui.CreateCheckbox({
            parent   = host,
            label    = entry.label,
            checked  = entry.get and entry.get() or false,
            onClick  = entry.set,
            disabled = entry.disabled,
        })
        if entry.get then
            table.insert(refreshers, function() widget.SetChecked(entry.get()) end)
        end

    elseif t == "button" then
        widget = ns.ui.CreateButton({
            parent  = host,
            label   = entry.label,
            width   = entry.width,
            height  = entry.height,
            onClick = entry.onClick,
        })

    elseif t == "textinput" then
        widget = ns.ui.CreateTextInput({
            parent     = host,
            width      = entry.width,
            height     = entry.height,
            numeric    = entry.numeric,
            allowNegative = entry.allowNegative,
            min        = entry.min,
            max        = entry.max,
            maxLetters = entry.maxLetters,
            text       = entry.get and tostring(entry.get() or "") or "",
            onEnter    = entry.set,
        })
        if entry.get then
            table.insert(refreshers, function() widget.SetText(tostring(entry.get() or "")) end)
        end

    elseif t == "label" or t == "header" then
        -- A bare FontString anchored inside the host.
        local fontObj = entry.font or (t == "header" and "UnbunkUtilityH4" or "UnbunkUtilityBody")
        local fs = host:CreateFontString(nil, "ARTWORK", fontObj)
        fs:SetText(entry.text or "")
        if entry.color then fs:SetTextColor(entry.color[1], entry.color[2], entry.color[3], entry.color[4] or 1) end
        widget = { frame = fs, fontString = fs }

    else
        -- Unknown child type: create an empty placeholder so positioning math
        -- never indexes nil.
        widget = { frame = CreateFrame("Frame", nil, host) }
    end

    -- Positioning. Two accepted point shapes:
    --   inline form: { myPoint, relPoint, x, y }            (relativeTo = defaultRel)
    --   row    form: { myPoint, "$ref"/frame, relPoint, x, y }
    -- The row form is detected when point[2] is a frame object or a "$ref"
    -- string, i.e. an explicit relativeTo rather than the relative anchor point.
    local f = widget.frame
    if entry.point then
        local p = entry.point
        f:ClearAllPoints()
        local p2 = p[2]
        local isRowForm = (type(p2) == "table")
            or (type(p2) == "string" and p2:match("^%$"))
        if isRowForm then
            local rel = ResolveRelative(entry.relTo or p2, defaultRel, refs)
            f:SetPoint(p[1], rel, p[3], p[4] or 0, p[5] or 0)
        else
            local rel = ResolveRelative(entry.relTo, defaultRel, refs)
            f:SetPoint(p[1], rel, p[2], p[3] or 0, p[4] or 0)
        end
    elseif defaultRel then
        -- No explicit point: anchor TOPLEFT to the host origin.
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    end

    if entry.ref then
        refs[entry.ref] = widget
        if result then result.frames[entry.ref] = widget and widget.frame end
    end
    if entry.onBuilt then
        entry.onBuilt(widget, entry)
    end

    return widget
end

function ns.ui.BuildMenu(parent, options, panelOpts)
    panelOpts = panelOpts or {}
    options   = options or {}

    local width    = panelOpts.width   or 518
    local gap      = panelOpts.gap     or 12
    -- Top-level panels get a left margin so a group box's left border is not
    -- clipped at the scroll-viewport edge and the 518 stack reads centred in the
    -- ~550 content area. Nested BuildMenus (sections / groups) pass originX
    -- explicitly, so this default only affects the outer module call.
    local originX  = panelOpts.originX or 16
    local originY  = panelOpts.originY or 0
    -- Heading depth: groups deepen the hierarchy (root cadre = H3, nested = H4);
    -- sections do NOT (a section's own cadres stay at the parent's level). Exactly ONE
    -- H2 per tab (the "General" cadre / a standalone tab title) is set via an explicit
    -- heading override on that entry.
    local depth        = panelOpts.depth or 0
    local groupHeading = (depth == 0) and "UnbunkUtilityH3" or "UnbunkUtilityH4"
    local autoHook = panelOpts.autoHook
    if autoHook == nil then autoHook = true end
    local LSM      = panelOpts.LSM

    local contentParent = panelOpts.contentParent or parent

    -- BuildMenu owns its inner content frame (callers stop creating it).
    local content = CreateFrame("Frame", nil, contentParent)
    content:SetAllPoints(contentParent)
    -- Tag it as a full-bleed wrapper: it SetAllPoints its parent (so its bottom is
    -- the parent's, not the content's), which would otherwise peg the main window's
    -- per-tab scroll-height measurement to the tallest tab. ComputeModuleHeight skips
    -- tagged frames when measuring but still walks INTO them for the real widgets.
    content._uuMenuContent = true

    local result = {
        content   = content,
        refs      = {},
        frames    = {},
        widgets   = {},
        -- UIParent-parented helper frames (dropdown drop-frames, incl. those of
        -- nested group/section menus) that Rebuild must Hide+SetParent(nil) so they
        -- don't accumulate on UIParent across rebuilds.
        auxFrames = {},
    }
    local refs       = result.refs
    local refreshers = {}

    local lastFrame  = nil
    local totalHeight = 0
    local built      = {}   -- every host frame stacked this pass (for Rebuild teardown)

    -- Optional disable gate: greys + mouse-blocks every stacked control EXCEPT the
    -- `master` checkbox while `enabled()` is false — for a group/module whose leading
    -- checkbox turns its dependent controls on/off (the checkbox stays live; the rest
    -- grey out and stop responding). panelOpts.gate = { enabled = fn, master = "ref" }.
    -- `master` is matched against entry.ref; if no entry matches, the whole stack is
    -- gated (e.g. a module disabled from elsewhere with no in-panel toggle).
    local disableGate = panelOpts.gate
    local masterHost            -- host frame of the master checkbox (kept interactive)
    local ApplyDisableGate      -- assigned after the first build pass

    -- Stack one resolved frame `f` below the previous one. `spentHeight` is the
    -- height this entry contributes to the running total (and is applied to the
    -- host frame via SetHeight when `setHostHeight` is true).
    local function Stack(f, entryWidth, spentHeight, setHostHeight)
        f:SetWidth(entryWidth or width)
        f:ClearAllPoints()
        if lastFrame then
            f:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -gap)
            totalHeight = totalHeight + gap
        else
            f:SetPoint("TOPLEFT", content, "TOPLEFT", originX, originY)
        end
        if setHostHeight and spentHeight then
            f:SetHeight(spentHeight)
        end
        totalHeight = totalHeight + (spentHeight or 0)
        lastFrame = f
        built[#built + 1] = f
    end

    local function buildAll()
    for _, entry in ipairs(options) do
        -- Skip entries gated by a `shown` / `when` predicate that is false.
        local gate = entry.shown or entry.when
        local skip = gate and not gate()

        if not skip then
            local t       = entry.type
            local widget                       -- the primary widget result
            local hostFrame                    -- the frame BuildMenu stacks
            local spentHeight                  -- height to spend for stacking
            local setHostHeight = true         -- whether to SetHeight(host)
            local addRefresh                   -- closure appended after build

            -- ── Self-sizing widgets (return their own .frame/.height/.Refresh) ──
            if t == "duration" then
                widget = ns.ui.CreateDurationEditor({
                    parent           = content,
                    getDuration      = entry.get,
                    onDurationChange = entry.set,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                if widget.Refresh then addRefresh = widget.Refresh end

            elseif t == "instanceFilter" then
                widget = ns.ui.CreateInstanceFilter({
                    parent    = content,
                    getConfig = entry.getConfig or entry.get,
                    setConfig = entry.setConfig or entry.set,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                if widget.Refresh then addRefresh = widget.Refresh end

            elseif t == "sound" then
                widget = ns.ui.CreateSoundPicker(content, entry.LSM or LSM, {
                    label          = entry.label,
                    getSoundKey    = entry.getKey    or entry.getSoundKey,
                    getSoundEnable = entry.getEnable or entry.getSoundEnable,
                    onSoundSelect  = entry.onSelect  or entry.onSoundSelect,
                    onEnableToggle = entry.onToggle  or entry.onEnableToggle,
                    onTest         = entry.onTest,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                if widget.Refresh then addRefresh = widget.Refresh end

            elseif t == "position" then
                widget = ns.ui.CreatePositionEditor(content, {
                    label      = entry.label,
                    getX       = entry.getX,
                    getY       = entry.getY,
                    onApply    = entry.onApply,
                    onUnlock   = entry.onUnlock,
                    onLock     = entry.onLock,
                    isUnlocked = entry.isUnlocked,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                if widget.Refresh then addRefresh = widget.Refresh end

            elseif t == "textEditor" then
                widget = ns.ui.CreateTextEditor(content, {
                    LSM             = entry.LSM or LSM,
                    label           = entry.label,
                    showLabel       = entry.showLabel,   -- false suppresses the inner label (group title already names it)
                    textWidth       = entry.textWidth,
                    showText        = entry.showText,
                    showFont        = entry.showFont,
                    showSize        = entry.showSize,
                    showColor       = entry.showColor,
                    showOutline     = entry.showOutline,
                    getText         = entry.getText,
                    getFontKey      = entry.getFontKey,
                    getFontPath     = entry.getFontPath,
                    getFontSize     = entry.getFontSize,
                    getColor        = entry.getColor,
                    getOutline      = entry.getOutline,
                    onTextChange    = entry.onTextChange,
                    onFontChange    = entry.onFontChange,
                    onSizeChange    = entry.onSizeChange,
                    onColorChange   = entry.onColorChange,
                    onOutlineChange = entry.onOutlineChange,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                if widget.Refresh then addRefresh = widget.Refresh end

            elseif t == "iconPicker" then
                widget = ns.ui.CreateIconPicker({
                    parent    = content,
                    getConfig = entry.getConfig or entry.get,
                    setConfig = entry.setConfig or entry.set,
                    icons     = entry.icons,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                if widget.Refresh then addRefresh = widget.Refresh end

            -- ── Collapsible section (nested BuildMenu inside) ──────────────────
            elseif t == "section" then
                local sectionSub
                widget = ns.ui.CreateCollapsibleSection({
                    parent        = content,
                    heading       = entry.heading or "UnbunkUtilityH3",
                    label         = entry.label,
                    showCheckbox  = entry.showCheckbox,
                    isChecked     = entry.isChecked,
                    onCheck       = entry.onCheck,
                    getCollapsed  = entry.getCollapsed,
                    onCollapse    = entry.onCollapse,
                    headerExtra   = entry.headerExtra,
                    createContent = function(cf)
                        local innerOptions = entry.build and entry.build(cf) or {}
                        local secOriginX = panelOpts.innerOriginX or 8
                        sectionSub = ns.ui.BuildMenu(cf, innerOptions, {
                            -- Reserve a RIGHT margin equal to the left originX inset so full-width children
                            -- with VISIBLE borders (nested group boxes) don't overflow the section's right
                            -- edge — that's why the sub-cadres of "Group settings" stuck out ~8px on expand.
                            -- The 518-internal shared widgets (InstanceFilter/SoundPicker/TextEditor/Icon
                            -- Picker) left-align their visible content well under this width and the section
                            -- never SetClipsChildren, so the slightly narrower host doesn't clip them. An
                            -- explicit innerWidth (genuinely-narrower sections) is still respected as-is.
                            width    = panelOpts.innerWidth or (width - 2 * secOriginX),
                            gap      = panelOpts.innerGap     or 10,
                            originX  = secOriginX,
                            originY  = panelOpts.innerOriginY or -8,
                            autoHook = false,
                            LSM      = entry.LSM or LSM,
                            gate     = entry.gate,   -- grey the section's whole body when entry.gate.enabled() is false
                            depth    = depth,   -- a section does NOT deepen the heading level
                        })
                        return sectionSub.height
                    end,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                addRefresh = function()
                    if widget.Refresh then widget.Refresh() end
                    if sectionSub then sectionSub.Refresh() end
                end
                if sectionSub and sectionSub.auxFrames then
                    for _, fr in ipairs(sectionSub.auxFrames) do
                        result.auxFrames[#result.auxFrames + 1] = fr
                    end
                end

            -- ── Group box (bordered frame around a nested BuildMenu) ───────────
            elseif t == "group" then
                local groupSub
                -- The box fills `boxW` (current panel width by default) and insets
                -- its content by GROUP_SIDEPAD on each side, so the nested stack is
                -- innerW wide. Nesting one group inside another therefore indents
                -- the inner box by GROUP_SIDEPAD — borders never reach the edge.
                local boxW   = entry.width or width
                local innerW = boxW - 2 * GROUP_SIDEPAD
                widget = ns.ui.CreateGroupBox({
                    parent  = content,
                    heading = entry.heading or groupHeading,
                    title   = entry.title or entry.label,
                    width   = boxW,
                    sidePad = GROUP_SIDEPAD,
                    topPad  = entry.topPad,
                    botPad  = entry.botPad,
                    createContent = function(cf)
                        local innerOptions = entry.build and entry.build(cf) or (entry.children or {})
                        groupSub = ns.ui.BuildMenu(cf, innerOptions, {
                            width    = innerW,
                            gap      = entry.innerGap or panelOpts.innerGap or gap,
                            originX  = 0,
                            originY  = 0,
                            autoHook = false,
                            LSM      = entry.LSM or LSM,
                            gate     = entry.gate,   -- grey the box's controls when its lead checkbox is off
                            depth    = depth + 1,    -- a nested group is one level deeper (H3)
                        })
                        return groupSub.height
                    end,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                addRefresh = function()
                    if groupSub then groupSub.Refresh() end
                end
                if groupSub and groupSub.auxFrames then
                    for _, fr in ipairs(groupSub.auxFrames) do
                        result.auxFrames[#result.auxFrames + 1] = fr
                    end
                end

            -- ── Fixed-height widgets hosted in a wrapper frame ─────────────────
            elseif t == "checkbox" then
                hostFrame = CreateFrame("Frame", nil, content)
                spentHeight = entry.height or DEFAULT_HEIGHTS.checkbox
                -- The gate's master checkbox stays live and re-applies the gate on toggle.
                local onClick = entry.set
                if disableGate and entry.ref and entry.ref == disableGate.master then
                    masterHost = hostFrame
                    onClick = function(v)
                        if entry.set then entry.set(v) end
                        if ApplyDisableGate then ApplyDisableGate() end
                    end
                end
                widget = ns.ui.CreateCheckbox({
                    parent   = hostFrame,
                    label    = entry.label,
                    checked  = entry.get and entry.get() or false,
                    onClick  = onClick,
                    disabled = entry.disabled,
                })
                widget.frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                if entry.get then
                    addRefresh = function() widget.SetChecked(entry.get()) end
                end

            elseif t == "button" then
                hostFrame = CreateFrame("Frame", nil, content)
                local btnH = entry.height or 22
                spentHeight = entry.hostHeight or (btnH + 4)
                widget = ns.ui.CreateButton({
                    parent  = hostFrame,
                    label   = entry.label,
                    width   = entry.width,
                    height  = btnH,
                    onClick = entry.onClick,
                })
                widget.frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, entry.btnOffsetY or 0)

            elseif t == "textinput" then
                hostFrame = CreateFrame("Frame", nil, content)
                -- entry.height sizes the HOST frame (matches the spec); entry.inputHeight
                -- sizes the edit box itself (default 22).
                local inputH = entry.inputHeight or DEFAULT_HEIGHTS.textinput
                local labelFs
                if entry.label then
                    labelFs = hostFrame:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                    labelFs:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                    labelFs:SetText(entry.label)
                end
                -- Host height: explicit entry.height wins; else a label adds 20px above
                -- the box, otherwise the host is exactly the box height.
                spentHeight = entry.height or (entry.label and (inputH + 20)) or inputH
                widget = ns.ui.CreateTextInput({
                    parent     = hostFrame,
                    width      = entry.width,
                    height     = inputH,
                    numeric    = entry.numeric,
                    allowNegative = entry.allowNegative,
                    min        = entry.min,
                    max        = entry.max,
                    maxLetters = entry.maxLetters,
                    text       = entry.get and tostring(entry.get() or "") or "",
                    onEnter    = entry.set,
                    disabled   = entry.disabled,
                })
                if labelFs then
                    widget.frame:SetPoint("TOPLEFT", labelFs, "BOTTOMLEFT", 0, -2)
                else
                    widget.frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                end
                if entry.get or entry.disabled then
                    addRefresh = function()
                        if entry.get then widget.SetText(tostring(entry.get() or "")) end
                        if widget.Refresh then widget.Refresh() end   -- re-evaluate the disabled state
                    end
                end

            elseif t == "slider" then
                hostFrame = CreateFrame("Frame", nil, content)
                local labelFs
                if entry.label then
                    labelFs = hostFrame:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                    labelFs:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                    labelFs:SetText(entry.label)
                end
                spentHeight = entry.height or (entry.label and 48 or 30)
                widget = ns.ui.CreateSlider({
                    parent    = hostFrame,
                    width     = entry.width or 200,
                    min       = entry.min or 0,
                    max       = entry.max or 100,
                    step      = entry.step or 1,
                    value     = entry.get and entry.get() or (entry.min or 0),
                    format    = entry.format,
                    decimals  = entry.decimals,
                    onChange  = entry.set,
                    editBox   = entry.editBox,
                    editWidth = entry.editWidth,
                })
                if labelFs then
                    widget.frame:SetPoint("TOPLEFT", labelFs, "BOTTOMLEFT", 0, -2)
                else
                    widget.frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                end
                if entry.get then
                    addRefresh = function() widget.SetValue(entry.get()) end
                end

            elseif t == "label" or t == "header" then
                hostFrame = CreateFrame("Frame", nil, content)
                spentHeight = entry.height or DEFAULT_HEIGHTS.label
                local fontObj = entry.font or (t == "header" and "UnbunkUtilityH4" or "UnbunkUtilityBody")
                local fs = hostFrame:CreateFontString(nil, "ARTWORK", fontObj)
                fs:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                fs:SetText(entry.text or "")
                if entry.color then fs:SetTextColor(entry.color[1], entry.color[2], entry.color[3], entry.color[4] or 1) end
                widget = { frame = hostFrame, fontString = fs }

            elseif t == "dropdown" then
                hostFrame = CreateFrame("Frame", nil, content)
                -- Auto label (~12px) + toggle (22px) needs ~44px; callers with a
                -- tighter layout pass entry.height explicitly.
                spentHeight = entry.height or 44
                local anchor = entry.anchorFrame
                if not anchor then
                    -- entry.font overrides the auto-label font (default = the small
                    -- highlight font); entry.labelGap inserts an empty spacer so the
                    -- toggle sits a fixed distance below the top, reproducing panels
                    -- that anchored the box to a -labelGap spacer FontString.
                    local lbl = hostFrame:CreateFontString(nil, "ARTWORK", entry.font or "UnbunkUtilityBody")
                    lbl:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                    lbl:SetText(entry.label or "")
                    if entry.labelGap then
                        local spacer = hostFrame:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        spacer:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, -entry.labelGap)
                        anchor = spacer
                    else
                        anchor = lbl
                    end
                end
                widget = ns.ui.CreateDropdown({
                    parent        = hostFrame,
                    anchorFrame   = anchor,
                    width         = entry.width,
                    itemHeight    = entry.itemHeight,
                    visibleItems  = entry.visibleItems,
                    searchable    = entry.searchable,
                    getList       = entry.getList,
                    getCurrentKey = entry.getCurrentKey,
                    onSelect      = entry.onSelect,
                })
                if entry.getCurrentKey and widget.SetCurrent then
                    addRefresh = function() widget.SetCurrent(entry.getCurrentKey()) end
                elseif widget.RefreshList then
                    addRefresh = widget.RefreshList
                end

            -- ── Reorder: arrow buttons ( < > ) to move an item within a row ────
            elseif t == "reorder" then
                widget = ns.ui.CreateReorder({
                    parent   = content,
                    label    = entry.label,
                    getState = entry.getState,
                    onMove   = entry.onMove,
                })
                hostFrame   = widget.frame
                spentHeight = entry.height or 26
                if widget.Refresh then addRefresh = widget.Refresh end

            -- ── Row: an array of leaf children laid out by explicit points ─────
            elseif t == "row" then
                hostFrame = CreateFrame("Frame", nil, content)
                spentHeight = entry.height or DEFAULT_HEIGHTS.row
                for _, child in ipairs(entry.children or {}) do
                    BuildChild(child, hostFrame, hostFrame, refs, refreshers, result)
                end
                widget = { frame = hostFrame }

            -- ── Custom: escape hatch for hand-built composites ─────────────────
            elseif t == "custom" then
                hostFrame = CreateFrame("Frame", nil, content)
                hostFrame:SetWidth(entry.width or width)
                -- `builtWidget` (NOT `built`): avoid shadowing the outer host-frame
                -- teardown list `built` declared above.
                local builtWidget = entry.build and entry.build(hostFrame) or { frame = hostFrame }
                widget = builtWidget
                -- Prefer the frame the builder returns; default to the host.
                hostFrame = builtWidget.frame or hostFrame
                -- Height priority: builder height > entry height > current height.
                spentHeight = builtWidget.height or entry.height or hostFrame:GetHeight()
                if builtWidget.Refresh then addRefresh = builtWidget.Refresh end
                if entry.refresh then
                    local prev = addRefresh
                    addRefresh = function()
                        if prev then prev() end
                        entry.refresh()
                    end
                end

            else
                -- Unknown entry type: render nothing but keep the pipeline safe.
                hostFrame = CreateFrame("Frame", nil, content)
                spentHeight = entry.height or 0
                widget = { frame = hostFrame }
            end

            -- ── INLINE children anchored relative to the primary widget ────────
            if entry.inline and widget then
                local primaryFrame = widget.frame
                local builtInline = {}
                for i, child in ipairs(entry.inline) do
                    -- relTo="<index>" chains to a previous inline sibling.
                    local rel = primaryFrame
                    if child.relTo and builtInline[tonumber(child.relTo)] then
                        rel = builtInline[tonumber(child.relTo)].frame
                    end
                    builtInline[i] = BuildChild(child, hostFrame, rel, refs, refreshers, result)
                end
            end

            -- ── Stack the resolved host frame ──────────────────────────────────
            Stack(hostFrame, entry.width, spentHeight, setHostHeight)

            -- ── Bookkeeping: refs / frames / widgets / refreshers ──────────────
            if entry.ref then
                refs[entry.ref] = widget
                result.frames[entry.ref] = widget and widget.frame
            end
            if entry.onBuilt then
                -- Fires for every type (incl. "custom") so the caller can
                -- capture the widget result before BuildMenu returns.
                entry.onBuilt(widget, entry)
            end
            table.insert(result.widgets, widget)
            -- Collect UIParent-parented drop-frames (a single .dropFrame, or a
            -- widget exposing several via .dropFrames) so Rebuild can reclaim them.
            if widget then
                if widget.dropFrame then
                    result.auxFrames[#result.auxFrames + 1] = widget.dropFrame
                end
                if widget.dropFrames then
                    for _, fr in ipairs(widget.dropFrames) do
                        result.auxFrames[#result.auxFrames + 1] = fr
                    end
                end
            end
            if addRefresh then
                table.insert(refreshers, addRefresh)
            end

            -- Per-entry disable gate: grey + mouse-block THIS entry's host while
            -- `enabledBy()` is false (the controls it depends on are off). Used for a
            -- checkbox that gates a few sibling controls — e.g. "Show border" greying
            -- the border colour + thickness. The controlling checkbox's `set` must call
            -- menu.Refresh() so toggling it re-applies the gate.
            if entry.enabledBy and hostFrame then
                local applyEntryGate = ns.ui.MakeDisableGate(hostFrame)
                local thisHost = hostFrame
                local function applyEnabledBy()
                    applyEntryGate(entry.enabledBy() and true or false, { thisHost })
                end
                applyEnabledBy()
                table.insert(refreshers, applyEnabledBy)
            end
        end
    end
    end  -- buildAll

    -- Initial build pass.
    buildAll()
    result.height = totalHeight

    -- Wire the disable gate (if any) now that every host frame exists. Greys + blocks
    -- all stacked controls except the master checkbox while the feature is off.
    if disableGate and disableGate.enabled then
        local applyGate = ns.ui.MakeDisableGate(content)
        ApplyDisableGate = function()
            local dim = {}
            for _, f in ipairs(built) do
                if f ~= masterHost then dim[#dim + 1] = f end
            end
            applyGate(disableGate.enabled() and true or false, dim, masterHost)
        end
        ApplyDisableGate()
    end

    function result.Refresh()
        for _, fn in ipairs(refreshers) do
            fn()
        end
        if ApplyDisableGate then ApplyDisableGate() end
    end

    -- Tear down everything built and rebuild from the (static) options list,
    -- re-evaluating each entry's `when`/`shown` predicate. Used for reactive
    -- panels where toggling one control changes which entries are shown (e.g. the
    -- CDM block vs the position editor). Old frames are hidden + orphaned (WoW
    -- frames are not destroyable); a settings panel is toggled rarely so this is
    -- fine. After rebuilding it asks the host to re-measure its scroll height.
    function result.Rebuild()
        for _, f in ipairs(built) do
            f:Hide()
            f:ClearAllPoints()
            f:SetParent(nil)
        end
        -- Reclaim UIParent-parented drop-frames (incl. those from nested
        -- group/section menus) so they don't pile up on UIParent each Rebuild.
        for _, f in ipairs(result.auxFrames) do
            f:Hide()
            f:ClearAllPoints()
            f:SetParent(nil)
        end
        wipe(result.auxFrames)
        wipe(built)
        wipe(result.widgets)
        wipe(result.frames)
        wipe(refs)
        wipe(refreshers)
        masterHost  = nil   -- re-captured by buildAll when the master checkbox is rebuilt
        lastFrame   = nil
        totalHeight = 0
        buildAll()
        result.height = totalHeight
        result.Refresh()
        if ns.ResizeActiveModule then ns.ResizeActiveModule() end
    end

    if autoHook and parent and parent.HookScript then
        parent:HookScript("OnShow", result.Refresh)
    end

    return result
end
