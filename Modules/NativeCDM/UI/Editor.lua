-- Modules/NativeCDM/UI/Editor.lua
-- The per-spell editor for a customized NATIVE Cooldown Manager icon, opened by the pen
-- in the Essentials/Utility "Native icons" cadre. A native icon is FIXED in the CDM at the
-- Blizzard slot it occupies — it can't be moved, freed, or resized by the addon — so the
-- editor only styles it: a header (spell + "Stop customizing") then the Sound, Timer,
-- Title and Stacks cadres. There is no Placement and no per-icon Border: the icon's border
-- is the CDM dest's border (the Essentials/Utility panel's Border cadre). State is read /
-- written via ns.NativeCDM.Get / .Set (which re-applies the icon live).

local ADDON, ns = ...
local L  = ns.L
local NC = ns.NativeCDM

local editor      -- singleton { frame, scroll, content, sb, menu }
local editingId   -- the spellId currently shown

-- ── Anchor dropdown helpers ───────────────────────────────────────────────────
-- Centralised in ns (Core/Shared.lua): Center / edge modes / 4 inside corners.
local AnchorLabel     = ns.AnchorLabel
local AnchorFromLabel = ns.AnchorFromLabel
local AnchorList      = ns.AnchorList

local function StyleEditor(id, prefix, LSM)
    local function k(suffix) return prefix .. suffix end
    return {
        type        = "textEditor",
        LSM         = LSM,
        showLabel   = false, showText = false,
        showFont    = true,  showSize = true, showColor = true, showOutline = true,
        getFontKey      = function() return NC.Get(id, k("FontKey"))  end,
        getFontPath     = function() return NC.Get(id, k("FontPath")) end,
        getFontSize     = function() return NC.Get(id, k("FontSize")) end,
        getColor        = function() return NC.Get(id, k("Color"))    end,
        getOutline      = function() return NC.Get(id, k("Outline"))  end,
        onFontChange    = function(key, path) NC.Set(id, k("FontKey"), key); NC.Set(id, k("FontPath"), path) end,
        onSizeChange    = function(size)      NC.Set(id, k("FontSize"), size) end,
        onColorChange   = function(r, g, b, a) NC.Set(id, k("Color"), { r = r, g = g, b = b, a = a }) end,
        onOutlineChange = function(outline)   NC.Set(id, k("Outline"), outline) end,
    }
end

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
                getCurrentKey = function() return AnchorLabel(NC.Get(id, prefix .. "Anchor")) end,
                onSelect = function(label)
                    NC.Set(id, prefix .. "Anchor", AnchorFromLabel(label))
                    dd.selectedText:SetText(label)
                end,
            })
            dd.selectedText:SetText(AnchorLabel(NC.Get(id, prefix .. "Anchor")))

            local function offInput(after, gap, axisText, key)
                local axis = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                axis:SetPoint("LEFT", after, "RIGHT", gap, 0)
                axis:SetText(axisText)
                local inp = ns.ui.CreateTextInput({
                    parent = host, width = 44, height = 22, numeric = true, allowNegative = true,
                    min = -512, max = 512, maxLetters = 4,
                    text = tostring(NC.Get(id, key) or 0),
                    onEnter = function(v) if v ~= nil then NC.Set(id, key, v) end end,
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
                    dd.selectedText:SetText(AnchorLabel(NC.Get(id, prefix .. "Anchor")))
                    xInput.SetText(tostring(NC.Get(id, prefix .. "OffsetX") or 0))
                    yInput.SetText(tostring(NC.Get(id, prefix .. "OffsetY") or 0))
                end,
            }
        end,
    }
end

local function TiersEntry(id, rebuildEditor)
    return {
        type   = "custom",
        height = 60,
        build  = function(host)
            local tiers = NC.Get(id, "timerTiers") or {}
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
                    onEnter = function(v) if v ~= nil then tier.at = v; NC.ApplyIcon(id) end end,
                })
                atInput.frame:SetPoint("LEFT", atLbl, "RIGHT", 4, 0)

                local szLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                szLbl:SetPoint("LEFT", atInput.frame, "RIGHT", 12, 0)
                szLbl:SetText(L["Size x"])
                local szInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 0, max = 10, maxLetters = 4,
                    text = tostring(tier.scale or 1),
                    onEnter = function(v) if v and v > 0 then tier.scale = v; NC.ApplyIcon(id) end end,
                })
                szInput.frame:SetPoint("LEFT", szLbl, "RIGHT", 4, 0)

                local swatch = ns.ui.CreateColorSwatch({
                    parent = host, width = 24, height = 22,
                    getColor = function() return tier.color end,
                    onChange = function(r, g, b, a) tier.color = { r = r, g = g, b = b, a = a }; NC.ApplyIcon(id) end,
                })
                swatch.frame:SetPoint("LEFT", szInput.frame, "RIGHT", 12, 0)

                local rm = ns.ui.CreateButton({
                    parent = host, label = "X", width = 24, height = 22,
                    onClick = function()
                        table.remove(tiers, i)
                        NC.ApplyIcon(id)
                        rebuildEditor()
                    end,
                })
                rm.frame:SetPoint("LEFT", swatch.frame, "RIGHT", 12, 0)

                y = y + ROW_H
            end

            local add = ns.ui.CreateButton({
                parent = host, label = L["Add threshold"], width = 140, height = 22,
                onClick = function()
                    local list = NC.Get(id, "timerTiers")
                    if list then
                        list[#list + 1] = { at = 10, scale = 1, color = { r = 1, g = 1, b = 1, a = 1 } }
                        NC.ApplyIcon(id)
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

-- ── Cadre builders ────────────────────────────────────────────────────────────
-- Header: the spell's icon + name (no input — the spell is the native's), plus a
-- "Stop customizing" button that un-adopts and closes the editor.
local function HeaderGroup(id)
    return { type = "group", title = L["Spell"], build = function() return {
        { type = "custom", height = 52, build = function(host)
            local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            local function showName()
                local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                local name = NC.SpellName(id)
                if tex then fs:SetText(string.format("|T%d:20|t %s", tex, name)) else fs:SetText(name or "") end
            end
            showName()
            local btn = ns.ui.CreateButton({
                parent = host, width = 180, height = 22, label = L["Stop customizing"],
                onClick = function() NC.ConfirmRemove(id) end,
            })
            btn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -26)
            return { frame = host, height = 52, Refresh = showName }
        end },
    } end }
end

local function SoundGroup(id, LSM)
    return { type = "group", title = L["Sound alert"], build = function() return {
        { type = "sound", LSM = LSM, label = L["Sound on use"],
          getKey    = function() return NC.Get(id, "soundKeyUse") end,
          getEnable = function() return NC.Get(id, "soundOnUse") end,
          onSelect  = function(key, path) NC.Set(id, "soundKeyUse", key); NC.Set(id, "soundPathUse", path) end,
          onToggle  = function(v) NC.Set(id, "soundOnUse", v) end,
          onTest    = function() NC.TestSound(id, "use") end },
        { type = "sound", LSM = LSM, label = L["Sound when ready"],
          getKey    = function() return NC.Get(id, "soundKeyReady") end,
          getEnable = function() return NC.Get(id, "soundOnReady") end,
          onSelect  = function(key, path) NC.Set(id, "soundKeyReady", key); NC.Set(id, "soundPathReady", path) end,
          onToggle  = function(v) NC.Set(id, "soundOnReady", v) end,
          onTest    = function() NC.TestSound(id, "ready") end },
    } end }
end

local function TimerGroup(id, LSM, rebuild)
    return { type = "group", title = L["Timer"],
      gate = { enabled = function() return NC.Get(id, "showTimer") ~= false end, master = "showtimer" },
      build = function() return {
        { type = "checkbox", ref = "showtimer", label = L["Show timer"],
          get = function() return NC.Get(id, "showTimer") ~= false end,
          set = function(v) NC.Set(id, "showTimer", v) end },
        StyleEditor(id, "timer", LSM),
        TiersEntry(id, rebuild),
    } end }
end

local function TitleGroup(id, LSM)
    return { type = "group", title = L["Title"],
      gate = { enabled = function() return NC.Get(id, "showTitle") == true end, master = "showtitle" },
      build = function() return {
        { type = "checkbox", ref = "showtitle", label = L["Show title"],
          get = function() return NC.Get(id, "showTitle") == true end,
          set = function(v) NC.Set(id, "showTitle", v) end },
        { type = "textinput", label = L["Title text"], width = 240, maxLetters = 64,
          get = function() return NC.Get(id, "titleText") or "" end,
          set = function(v) NC.Set(id, "titleText", v or "") end },
        AnchorOffsetEntry(id, "title"),
        StyleEditor(id, "title", LSM),
    } end }
end

local function StacksGroup(id, LSM)
    return { type = "group", title = L["Stacks"],
      gate = { enabled = function() return NC.Get(id, "showStack") ~= false end, master = "showstack" },
      build = function() return {
        { type = "checkbox", ref = "showstack", label = L["Show stacks"], height = 24,
          get = function() return NC.Get(id, "showStack") ~= false end,
          set = function(v) NC.Set(id, "showStack", v) end,
          inline = {
            { type = "checkbox", label = L["Show icon at 0 stacks"],
              get = function() return NC.Get(id, "showAtZero") ~= false end,
              set = function(v) NC.Set(id, "showAtZero", v) end,
              point = { "LEFT", "LEFT", 150, 0 } },
          } },
        AnchorOffsetEntry(id, "stack"),
        StyleEditor(id, "stack", LSM),
    } end }
end

-- A native icon is fixed in the CDM (no placement, no per-icon border — the CDM dest's
-- border governs it), so the editor is just the style cadres: Sound, Timer, Title, Stacks.
local function EditorOptions(id, LSM, refresh, rebuild)
    return {
        HeaderGroup(id),
        SoundGroup(id, LSM),
        TimerGroup(id, LSM, rebuild),
        TitleGroup(id, LSM),
        StacksGroup(id, LSM),
    }
end

-- ── Window scaffolding ────────────────────────────────────────────────────────
local function EnsureWindow()
    if editor then return editor end

    local f = CreateFrame("Frame", "UnbunkUtilityNativeCDMEditor", UIParent, "BackdropTemplate")
    f:SetSize(580, 600)
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
    tinsert(UISpecialFrames, "UnbunkUtilityNativeCDMEditor")

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText(L["Native CDM icon"])

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
    f:HookScript("OnHide", function()
        if editingId then NC.SetUnlocked(editingId, false) end
    end)

    editor = { frame = f, scroll = scroll, content = content, sb = sb }
    return editor
end

local function ClearMenu(ed)
    if not ed.menu then return end
    if ed.menu.content then ed.menu.content:Hide(); ed.menu.content:ClearAllPoints(); ed.menu.content:SetParent(nil) end
    for _, fr in ipairs(ed.menu.auxFrames or {}) do fr:Hide(); fr:ClearAllPoints(); fr:SetParent(nil) end
    ed.menu = nil
end

-- Open (and adopt, if not already) the native icon for `spellId`. dest/row seed a
-- freshly-adopted icon's placement (the panel/row the pen was clicked in).
function NC.OpenEditor(spellId, dest, row)
    if not spellId then return end
    NC.Adopt(spellId, dest, row)
    local ed = EnsureWindow()
    editingId = spellId
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local function syncHeight()
        if ed.menu then ed.content:SetHeight(math.max(1, ed.menu.height + 12)) end
        ed.sb.Update()
    end
    local function refresh() if ed.menu then ed.menu.Refresh() end end
    local function rebuild() if ed.menu then ed.menu.Rebuild() end; syncHeight() end

    ClearMenu(ed)
    ed.menu = ns.ui.BuildMenu(ed.content, EditorOptions(spellId, LSM, refresh, rebuild), {
        gap = 10, width = 518, originX = 8, originY = 0, autoHook = false, LSM = LSM,
    })
    syncHeight()
    ed.menu.Refresh()

    ed.frame:Show()
    ed.frame:Raise()
    ed.scroll:SetVerticalScroll(0)
    C_Timer.After(0, function() ed.sb.Update() end)
end

function NC.CloseEditorFor(spellId)
    if editor and editingId == spellId and editor.frame:IsShown() then
        editor.frame:Hide()
    end
end
