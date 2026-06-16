-- Modules/CustomCDM/UI/Editor.lua
-- The per-icon editor window opened by a custom CDM icon's "pen" control. A movable,
-- scrollable popup hosting a ns.ui.BuildMenu scoped to one icon's config entry (read
-- via ns.CustomCDM.Get / written via ns.CustomCDM.Set, which re-applies the icon live):
-- Spell (ID or name), Timer (show + text style + configurable time thresholds), Title
-- (show + text + anchor + style), Stacks (show + show-at-0 + anchor + style), Border,
-- Icon size, and Sound alerts (on use / when ready).

local ADDON, ns = ...
local L  = ns.L
local CC = ns.CustomCDM

local editor      -- singleton { frame, scroll, content, sb, menu }
local editingId   -- the icon id currently shown

-- ── Anchor dropdown helpers ───────────────────────────────────────────────────
-- Centralised in ns (Core/Shared.lua): Center / edge modes / 4 inside corners.
local AnchorLabel     = ns.AnchorLabel
local AnchorFromLabel = ns.AnchorFromLabel
local AnchorList      = ns.AnchorList

-- A textEditor entry editing one styled-text block (font / size / colour / outline) of
-- a config key prefix, e.g. "timer" -> timerFontKey/timerFontPath/timerFontSize/
-- timerColor/timerOutline.
local function StyleEditor(id, prefix, LSM)
    local function k(suffix) return prefix .. suffix end
    return {
        type        = "textEditor",
        LSM         = LSM,
        showLabel   = false, showText = false,
        showFont    = true,  showSize = true, showColor = true, showOutline = true,
        getFontKey      = function() return CC.Get(id, k("FontKey"))  end,
        getFontPath     = function() return CC.Get(id, k("FontPath")) end,
        getFontSize     = function() return CC.Get(id, k("FontSize")) end,
        getColor        = function() return CC.Get(id, k("Color"))    end,
        getOutline      = function() return CC.Get(id, k("Outline"))  end,
        onFontChange    = function(key, path) CC.Set(id, k("FontKey"), key); CC.Set(id, k("FontPath"), path) end,
        onSizeChange    = function(size)      CC.Set(id, k("FontSize"), size) end,
        onColorChange   = function(r, g, b, a) CC.Set(id, k("Color"), { r = r, g = g, b = b, a = a }) end,
        onOutlineChange = function(outline)   CC.Set(id, k("Outline"), outline) end,
    }
end

-- A composite row: the title/stack "Anchor" dropdown plus X / Y nudge inputs to its
-- right, editing <prefix>Anchor / <prefix>OffsetX / <prefix>OffsetY ("title" / "stack").
local function AnchorOffsetEntry(id, prefix)
    return {
        type   = "custom",
        height = 48,
        build  = function(host)
            local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
            lbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            lbl:SetText(L["Anchor"])

            local ddAnchor = host:CreateFontString(nil, "ARTWORK")
            ddAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -18)
            local dd
            dd = ns.ui.CreateDropdown({
                parent = host, anchorFrame = ddAnchor, width = 130, itemHeight = 20, visibleItems = 5,
                getList = AnchorList,
                getCurrentKey = function() return AnchorLabel(CC.Get(id, prefix .. "Anchor")) end,
                onSelect = function(label)
                    CC.Set(id, prefix .. "Anchor", AnchorFromLabel(label))
                    dd.selectedText:SetText(label)
                end,
            })
            dd.selectedText:SetText(AnchorLabel(CC.Get(id, prefix .. "Anchor")))

            local function offInput(after, gap, axisText, key)
                local axis = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                axis:SetPoint("LEFT", after, "RIGHT", gap, 0)
                axis:SetText(axisText)
                local inp = ns.ui.CreateTextInput({
                    parent = host, width = 44, height = 22, numeric = true, allowNegative = true,
                    min = -512, max = 512, maxLetters = 4,
                    text = tostring(CC.Get(id, key) or 0),
                    onEnter = function(v) if v ~= nil then CC.Set(id, key, v) end end,
                })
                inp.frame:SetPoint("LEFT", axis, "RIGHT", 4, 0)
                return inp
            end
            local xInput = offInput(dd.toggleBtn, 14, "X", prefix .. "OffsetX")
            local yInput = offInput(xInput.frame, 10, "Y", prefix .. "OffsetY")

            return {
                frame     = host,
                height    = 48,
                dropFrame = dd.dropFrame,
                Refresh   = function()
                    dd.selectedText:SetText(AnchorLabel(CC.Get(id, prefix .. "Anchor")))
                    xInput.SetText(tostring(CC.Get(id, prefix .. "OffsetX") or 0))
                    yInput.SetText(tostring(CC.Get(id, prefix .. "OffsetY") or 0))
                end,
            }
        end,
    }
end

-- The custom "time thresholds" list editor: one row per tier (At seconds / size mult /
-- colour / remove) plus an "Add threshold" button. Mutates the LIVE entry.timerTiers
-- and re-applies; add/remove rebuild the whole editor so the row count refreshes.
local function TiersEntry(id, rebuildEditor)
    return {
        type   = "custom",
        height = 60,
        build  = function(host)
            local tiers = CC.Get(id, "timerTiers") or {}
            local ROW_H = 30

            local hdr = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            hdr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            hdr:SetText(L["Time thresholds (size + colour as the timer drops)"])

            local y = 22
            for i, tier in ipairs(tiers) do
                local atLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                atLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
                atLbl:SetText(L["At (s)"])
                local atInput = ns.ui.CreateTextInput({
                    parent = host, width = 42, height = 22, numeric = true, min = 0, max = 3600, maxLetters = 4,
                    text = tostring(tier.at or 0),
                    onEnter = function(v) if v ~= nil then tier.at = v; CC.ApplyIcon(id) end end,
                })
                atInput.frame:SetPoint("LEFT", atLbl, "RIGHT", 4, 0)

                local szLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                szLbl:SetPoint("LEFT", atInput.frame, "RIGHT", 12, 0)
                szLbl:SetText(L["Size x"])
                local szInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 0, max = 10, maxLetters = 4,
                    text = tostring(tier.scale or 1),
                    onEnter = function(v) if v and v > 0 then tier.scale = v; CC.ApplyIcon(id) end end,
                })
                szInput.frame:SetPoint("LEFT", szLbl, "RIGHT", 4, 0)

                local swatch = ns.ui.CreateColorSwatch({
                    parent = host, width = 24, height = 22,
                    getColor = function() return tier.color end,
                    onChange = function(r, g, b, a) tier.color = { r = r, g = g, b = b, a = a }; CC.ApplyIcon(id) end,
                })
                swatch.frame:SetPoint("LEFT", szInput.frame, "RIGHT", 12, 0)

                local rm = ns.ui.CreateButton({
                    parent = host, label = "X", width = 24, height = 22,
                    onClick = function()
                        table.remove(tiers, i)
                        CC.ApplyIcon(id)
                        rebuildEditor()
                    end,
                })
                rm.frame:SetPoint("LEFT", swatch.frame, "RIGHT", 12, 0)

                y = y + ROW_H
            end

            local add = ns.ui.CreateButton({
                parent = host, label = L["Add threshold"], width = 140, height = 22,
                onClick = function()
                    local list = CC.Get(id, "timerTiers")
                    if list then
                        list[#list + 1] = { at = 10, scale = 1, color = { r = 1, g = 1, b = 1, a = 1 } }
                        CC.ApplyIcon(id)
                        rebuildEditor()
                    end
                end,
            })
            add.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
            y = y + 30

            host:SetHeight(math.max(60, y))
            return { frame = host, height = math.max(60, y) }
        end,
    }
end

-- ── Cadre builders (each returns a BuildMenu group entry, bound to an icon id) ─
local function SpellGroup(id)
    return { type = "group", title = L["Spell"], build = function() return {
            { type = "custom", height = 52, build = function(host)
                -- Row 1: the current spell's icon + name.
                local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                local function showName()
                    local sid  = CC.Get(id, "spellId")
                    local tex  = sid and sid ~= 0 and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                    local name = CC.SpellName(id)
                    if tex then fs:SetText(string.format("|T%d:20|t %s", tex, name)) else fs:SetText(name or "") end
                end
                -- The input shows the current spell id, or BLANK for a not-yet-set draft
                -- (no "0" placeholder).
                local function spellText()
                    local sid = CC.Get(id, "spellId")
                    return (sid and sid ~= 0) and tostring(sid) or ""
                end
                showName()

                -- Forward-declared so the input's onEnter (which commits a draft) can use
                -- the button refresher.
                local btn, updateBtn
                updateBtn = function()
                    if btn then btn.SetText(CC.IsDraft(id) and L["Add Icon"] or L["Delete Icon"]) end
                end
                -- Add the (committed) icon for a draft, else just refresh its display.
                local function commitOrApply()
                    if CC.IsDraft(id) then
                        if CC.CommitDraft(id) then showName(); updateBtn() end
                    else
                        showName()
                    end
                end

                -- Row 2: the spell-id/name input + the Add Icon / Delete Icon button.
                local input
                input = ns.ui.CreateTextInput({
                    parent = host, width = 200, height = 22, maxLetters = 64,
                    text = spellText(),
                    -- Enter resolves the spell AND adds the icon (same as "Add Icon").
                    onEnter = function(v) if CC.SetSpellInput(id, v) then commitOrApply() end end,
                })
                input.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -26)

                btn = ns.ui.CreateButton({
                    parent = host, width = 100, height = 22,
                    label = CC.IsDraft(id) and L["Add Icon"] or L["Delete Icon"],
                    onClick = function()
                        if CC.IsDraft(id) then
                            if CC.SetSpellInput(id, input.GetText() or "") then commitOrApply() end
                        else
                            CC.ConfirmRemove(id)
                        end
                    end,
                })
                btn.frame:SetPoint("LEFT", input.frame, "RIGHT", 8, 0)
                return { frame = host, height = 52, Refresh = function()
                    showName()
                    input.SetText(spellText())
                    updateBtn()
                end }
            end },
    } end }
end

local function SoundGroup(id, LSM)
    return { type = "group", title = L["Sound alert"], build = function() return {
        { type = "sound", LSM = LSM, label = L["Sound on use"],
          getKey    = function() return CC.Get(id, "soundKeyUse") end,
          getEnable = function() return CC.Get(id, "soundOnUse") end,
          onSelect  = function(key, path) CC.Set(id, "soundKeyUse", key); CC.Set(id, "soundPathUse", path) end,
          onToggle  = function(v) CC.Set(id, "soundOnUse", v) end,
          onTest    = function() CC.TestSound(id, "use") end },
        { type = "sound", LSM = LSM, label = L["Sound when ready"],
          getKey    = function() return CC.Get(id, "soundKeyReady") end,
          getEnable = function() return CC.Get(id, "soundOnReady") end,
          onSelect  = function(key, path) CC.Set(id, "soundKeyReady", key); CC.Set(id, "soundPathReady", path) end,
          onToggle  = function(v) CC.Set(id, "soundOnReady", v) end,
          onTest    = function() CC.TestSound(id, "ready") end },
    } end }
end

local function BorderGroup(id, refresh, whenFn)
    return { type = "group", title = L["Border"], when = whenFn, build = function() return {
        { type = "checkbox", label = L["Show border"],
          get = function() return CC.Get(id, "borderEnabled") == true end,
          set = function(v) CC.Set(id, "borderEnabled", v); refresh() end },
        { type = "textEditor", label = L["Border color"],
          enabledBy = function() return CC.Get(id, "borderEnabled") == true end,
          showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
          getColor = function() return CC.Get(id, "borderColor") end,
          onColorChange = function(r, g, b, a) CC.Set(id, "borderColor", { r = r, g = g, b = b, a = a }) end },
        { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
          enabledBy = function() return CC.Get(id, "borderEnabled") == true end,
          get = function() return CC.Get(id, "borderSize") or 1 end,
          set = function(v) if v and v > 0 then CC.Set(id, "borderSize", v) end end },
    } end }
end

local function TimerGroup(id, LSM, rebuild)
    return { type = "group", title = L["Timer"],
      gate = { enabled = function() return CC.Get(id, "showTimer") ~= false end, master = "showtimer" },
      build = function() return {
        { type = "checkbox", ref = "showtimer", label = L["Show timer"],
          get = function() return CC.Get(id, "showTimer") ~= false end,
          set = function(v) CC.Set(id, "showTimer", v) end },
        StyleEditor(id, "timer", LSM),
        TiersEntry(id, rebuild),
    } end }
end

local function TitleGroup(id, LSM)
    return { type = "group", title = L["Title"],
      gate = { enabled = function() return CC.Get(id, "showTitle") == true end, master = "showtitle" },
      build = function() return {
        { type = "checkbox", ref = "showtitle", label = L["Show title"],
          get = function() return CC.Get(id, "showTitle") == true end,
          set = function(v) CC.Set(id, "showTitle", v) end },
        { type = "textinput", label = L["Title text"], width = 240, maxLetters = 64,
          get = function() return CC.Get(id, "titleText") or "" end,
          set = function(v) CC.Set(id, "titleText", v or "") end },
        AnchorOffsetEntry(id, "title"),
        StyleEditor(id, "title", LSM),
    } end }
end

local function StacksGroup(id, LSM)
    return { type = "group", title = L["Stacks"],
      gate = { enabled = function() return CC.Get(id, "showStack") ~= false end, master = "showstack" },
      build = function() return {
        { type = "checkbox", ref = "showstack", label = L["Show stacks"], height = 24,
          get = function() return CC.Get(id, "showStack") ~= false end,
          set = function(v) CC.Set(id, "showStack", v) end,
          inline = {
            { type = "checkbox", label = L["Show icon at 0 stacks"],
              get = function() return CC.Get(id, "showAtZero") ~= false end,
              set = function(v) CC.Set(id, "showAtZero", v) end,
              point = { "LEFT", "LEFT", 150, 0 } },
          } },
        AnchorOffsetEntry(id, "stack"),
        StyleEditor(id, "stack", LSM),
    } end }
end

local function PlacementGroup(id, rebuild, refresh)
    local pe   -- free-mode position editor widget (captured via onBuilt)
    return { type = "group", title = L["Placement"], build = function() return {
        { type = "checkbox", label = L["Include in cdm"],
          disabled = function() return not ns.IsCDMEnabled() end,
          get = function() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          set = function(v)
              CC.Set(id, "includeInCdm", v)
              rebuild()
              if ns.RebuildActiveModule then ns.RebuildActiveModule() end
          end },
        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
          when = function() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          getList = function() return ns.CDMDestList() end,
          getCurrentKey = function() return ns.CDMDestLabel(CC.Get(id, "cdmDest") or "belowPlayer") end,
          onSelect = function(label)
              CC.Set(id, "cdmDest", ns.CDMDestKeyFromLabel(label))
              rebuild()
              if ns.RebuildActiveModule then ns.RebuildActiveModule() end
          end },
        { type = "checkbox", label = L["Icon at the end of the row"],
          when = function() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          get = function() return CC.Get(id, "cdmAtEnd") ~= false end,
          set = function(v) CC.Set(id, "cdmAtEnd", v); if ns.RebuildActiveModule then ns.RebuildActiveModule() end end },
        { type = "dropdown", label = L["Row"], width = 120, height = 50,
          when = function() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          getList = function() return ns.CDMRowList(CC.Get(id, "cdmDest") or "belowPlayer") end,
          getCurrentKey = function() return ns.CDMRowLabel(ns.CDMClampRow(CC.Get(id, "cdmDest") or "belowPlayer", CC.Get(id, "cdmRow"))) end,
          onSelect = function(label) CC.Set(id, "cdmRow", ns.CDMRowFromLabel(label)); if ns.RebuildActiveModule then ns.RebuildActiveModule() end end },
        -- Free placement (only when NOT in the CDM): screen position + drag unlock.
        { type = "position", ref = "pe",
          when = function() return not ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          onBuilt = function(w) pe = w end,
          label = L["Icon position (offset from screen center)"],
          getX = function() return CC.Get(id, "posX") end,
          getY = function() return CC.Get(id, "posY") end,
          onApply = function(x, yv)
              if x  then CC.Set(id, "posX", x)  end
              if yv then CC.Set(id, "posY", yv) end
          end,
          onUnlock = function() CC.SetUnlocked(id, true) end,
          onLock   = function() CC.SetUnlocked(id, false); if pe then pe.Refresh() end end,
          isUnlocked = function() return CC.IsUnlocked(id) end },
        -- Icon size — free icons only; a CDM-slotted icon keeps the native row size.
        { type = "custom", height = 46,
          when = function() return not ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          build = function(host)
            local sLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
            sLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sLbl:SetText(L["Icon size"])
            local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20); wLbl:SetText(L["W"])
            local wInput = ns.ui.CreateTextInput({
                parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                text = tostring(CC.Get(id, "iconWidth") or 30),
                onEnter = function(v) if v and v > 0 then CC.Set(id, "iconWidth", v) end end,
            })
            wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
            local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
            local hInput = ns.ui.CreateTextInput({
                parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
                text = tostring(CC.Get(id, "iconHeight") or 30),
                onEnter = function(v) if v and v > 0 then CC.Set(id, "iconHeight", v) end end,
            })
            hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
            return { frame = host, height = 46, Refresh = function()
                wInput.SetText(tostring(CC.Get(id, "iconWidth") or 30))
                hInput.SetText(tostring(CC.Get(id, "iconHeight") or 30))
            end }
          end },
        -- Border at the bottom of Placement, and ONLY for a free icon — in the CDM the
        -- per-dest border (the dest panel's Border cadre) governs every icon there.
        BorderGroup(id, refresh, function() return not ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end),
    } end }
end

-- Build the option list for an icon. `refresh` re-syncs widgets; `rebuild` re-renders
-- the whole menu (used after add/remove of a threshold row, or a placement change).
-- Layout: Spell, then Sound alert, then an "Icon" cadre ("Show icon" toggle) wrapping
-- Placement, Border, Timer, Title, Stacks.
local function EditorOptions(id, LSM, refresh, rebuild)
    return {
        SpellGroup(id),
        SoundGroup(id, LSM),
        { type = "group", title = L["Icon"],
          gate = { enabled = function() return CC.Get(id, "showIcon") ~= false end, master = "showicon" },
          build = function() return {
            { type = "checkbox", ref = "showicon", label = L["Show icon"],
              get = function() return CC.Get(id, "showIcon") ~= false end,
              set = function(v) CC.Set(id, "showIcon", v) end },
            PlacementGroup(id, rebuild, refresh),
            TimerGroup(id, LSM, rebuild),
            TitleGroup(id, LSM),
            StacksGroup(id, LSM),
        } end },
    }
end

-- ── Window scaffolding ────────────────────────────────────────────────────────
local function EnsureWindow()
    if editor then return editor end

    local f = CreateFrame("Frame", "UnbunkUtilityCustomCDMEditor", UIParent, "BackdropTemplate")
    f:SetSize(580, 600)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")          -- above the main config window; below TOOLTIP drop-frames
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
    tinsert(UISpecialFrames, "UnbunkUtilityCustomCDMEditor")   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText(L["Custom CDM icon"])

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
    -- Re-lock any free-drag unlock when the editor closes (mirrors the main window),
    -- and drop an uncommitted draft (the "+" was clicked but "Add Icon" never was).
    f:HookScript("OnHide", function()
        if editingId then
            CC.SetUnlocked(editingId, false)
            if CC.IsDraft and CC.IsDraft(editingId) then CC.DiscardDraft(editingId) end
        end
    end)

    editor = { frame = f, scroll = scroll, content = content, sb = sb }
    return editor
end

-- Tear down the previously-built menu's frames so a re-open (or another icon) starts clean.
local function ClearMenu(ed)
    if not ed.menu then return end
    if ed.menu.content then ed.menu.content:Hide(); ed.menu.content:ClearAllPoints(); ed.menu.content:SetParent(nil) end
    for _, fr in ipairs(ed.menu.auxFrames or {}) do fr:Hide(); fr:ClearAllPoints(); fr:SetParent(nil) end
    ed.menu = nil
end

function CC.OpenEditor(id)
    if not CC.GetEntry(id) then return end
    local ed = EnsureWindow()
    editingId = id
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local function syncHeight()
        if ed.menu then ed.content:SetHeight(math.max(1, ed.menu.height + 12)) end
        ed.sb.Update()
    end
    local function refresh() if ed.menu then ed.menu.Refresh() end end
    local function rebuild() if ed.menu then ed.menu.Rebuild() end; syncHeight() end

    ClearMenu(ed)
    ed.menu = ns.ui.BuildMenu(ed.content, EditorOptions(id, LSM, refresh, rebuild), {
        gap = 10, width = 518, originX = 8, originY = 0, autoHook = false, LSM = LSM,
    })
    syncHeight()
    ed.menu.Refresh()

    ed.frame:Show()
    ed.frame:Raise()
    ed.scroll:SetVerticalScroll(0)
    C_Timer.After(0, function() ed.sb.Update() end)
end

-- Close the editor if it is currently showing the given icon (called when it is removed).
function CC.CloseEditorFor(id)
    if editor and editingId == id and editor.frame:IsShown() then
        editor.frame:Hide()
    end
end
