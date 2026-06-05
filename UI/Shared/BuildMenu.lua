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
local L = ns.L
ns.ui = ns.ui or {}

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
local function BuildChild(entry, host, defaultRel, refs, refreshers)
    local t = entry.type
    local widget

    if t == "checkbox" then
        widget = ns.ui.CreateCheckbox({
            parent  = host,
            label   = entry.label,
            checked = entry.get and entry.get() or false,
            onClick = entry.set,
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
        local fontObj = entry.font or (t == "header" and "GameFontNormal" or "GameFontHighlightSmall")
        local fs = host:CreateFontString(nil, "ARTWORK", fontObj)
        fs:SetText(entry.text or "")
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
    local originX  = panelOpts.originX or 0
    local originY  = panelOpts.originY or 0
    local autoHook = panelOpts.autoHook
    if autoHook == nil then autoHook = true end
    local LSM      = panelOpts.LSM

    local contentParent = panelOpts.contentParent or parent

    -- BuildMenu owns its inner content frame (callers stop creating it).
    local content = CreateFrame("Frame", nil, contentParent)
    content:SetAllPoints(contentParent)

    local result = {
        content = content,
        refs    = {},
        frames  = {},
        widgets = {},
    }
    local refs       = result.refs
    local refreshers = {}

    local lastFrame  = nil
    local totalHeight = 0

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
    end

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
                    label         = entry.label,
                    showCheckbox  = entry.showCheckbox,
                    isChecked     = entry.isChecked,
                    onCheck       = entry.onCheck,
                    createContent = function(cf)
                        local innerOptions = entry.build and entry.build(cf) or {}
                        sectionSub = ns.ui.BuildMenu(cf, innerOptions, {
                            -- Default inner width to the OUTER width, not a hardcoded
                            -- 500: InstanceFilter/SoundPicker/TextEditor/IconPicker draw
                            -- their content at 518 internally, so a 500 host would clip
                            -- them. Modules whose sections are genuinely narrower pass
                            -- innerWidth explicitly.
                            width    = panelOpts.innerWidth   or width,
                            gap      = panelOpts.innerGap     or 10,
                            originX  = panelOpts.innerOriginX or 8,
                            originY  = panelOpts.innerOriginY or -8,
                            autoHook = false,
                            LSM      = entry.LSM or LSM,
                        })
                        return sectionSub.height
                    end,
                })
                hostFrame, spentHeight, setHostHeight = widget.frame, widget.height, false
                addRefresh = function()
                    if widget.Refresh then widget.Refresh() end
                    if sectionSub then sectionSub.Refresh() end
                end

            -- ── Fixed-height widgets hosted in a wrapper frame ─────────────────
            elseif t == "checkbox" then
                hostFrame = CreateFrame("Frame", nil, content)
                spentHeight = entry.height or DEFAULT_HEIGHTS.checkbox
                widget = ns.ui.CreateCheckbox({
                    parent  = hostFrame,
                    label   = entry.label,
                    checked = entry.get and entry.get() or false,
                    onClick = entry.set,
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
                    labelFs = hostFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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
                    min        = entry.min,
                    max        = entry.max,
                    maxLetters = entry.maxLetters,
                    text       = entry.get and tostring(entry.get() or "") or "",
                    onEnter    = entry.set,
                })
                if labelFs then
                    widget.frame:SetPoint("TOPLEFT", labelFs, "BOTTOMLEFT", 0, -2)
                else
                    widget.frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                end
                if entry.get then
                    addRefresh = function() widget.SetText(tostring(entry.get())) end
                end

            elseif t == "label" or t == "header" then
                hostFrame = CreateFrame("Frame", nil, content)
                spentHeight = entry.height or DEFAULT_HEIGHTS.label
                local fontObj = entry.font or (t == "header" and "GameFontNormal" or "GameFontHighlightSmall")
                local fs = hostFrame:CreateFontString(nil, "ARTWORK", fontObj)
                fs:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                fs:SetText(entry.text or "")
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
                    local lbl = hostFrame:CreateFontString(nil, "ARTWORK", entry.font or "GameFontHighlightSmall")
                    lbl:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
                    lbl:SetText(entry.label or "")
                    if entry.labelGap then
                        local spacer = hostFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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
                    getList       = entry.getList,
                    getCurrentKey = entry.getCurrentKey,
                    onSelect      = entry.onSelect,
                })
                if entry.getCurrentKey and widget.SetCurrent then
                    addRefresh = function() widget.SetCurrent(entry.getCurrentKey()) end
                elseif widget.RefreshList then
                    addRefresh = widget.RefreshList
                end

            -- ── Row: an array of leaf children laid out by explicit points ─────
            elseif t == "row" then
                hostFrame = CreateFrame("Frame", nil, content)
                spentHeight = entry.height or DEFAULT_HEIGHTS.row
                for _, child in ipairs(entry.children or {}) do
                    BuildChild(child, hostFrame, hostFrame, refs, refreshers)
                end
                widget = { frame = hostFrame }

            -- ── Custom: escape hatch for hand-built composites ─────────────────
            elseif t == "custom" then
                hostFrame = CreateFrame("Frame", nil, content)
                hostFrame:SetWidth(entry.width or width)
                local built = entry.build and entry.build(hostFrame) or { frame = hostFrame }
                widget = built
                -- Prefer the frame the builder returns; default to the host.
                hostFrame = built.frame or hostFrame
                -- Height priority: builder height > entry height > current height.
                spentHeight = built.height or entry.height or hostFrame:GetHeight()
                if built.Refresh then addRefresh = built.Refresh end
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
                    builtInline[i] = BuildChild(child, hostFrame, rel, refs, refreshers)
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
            if addRefresh then
                table.insert(refreshers, addRefresh)
            end
        end
    end

    result.height = totalHeight

    function result.Refresh()
        for _, fn in ipairs(refreshers) do
            fn()
        end
    end

    if autoHook and parent and parent.HookScript then
        parent:HookScript("OnShow", result.Refresh)
    end

    return result
end
