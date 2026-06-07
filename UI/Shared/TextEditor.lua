-- UI/TextEditor.lua

-- Note: MONOCHROME is a font *rendering* flag (disables anti-aliasing), not a
-- true outline. On its own ("MONOCHROME") it produces no outline and can render
-- some fonts hard to read. It is kept here for completeness / back-compat with
-- already-saved configs; the OUTLINE / THICKOUTLINE variants are what users
-- typically want from this control.
local _, ns = ...
local L = ns.L

local OUTLINE_OPTIONS = {
    "", "OUTLINE", "THICKOUTLINE", "MONOCHROME",
    "MONOCHROME|OUTLINE", "MONOCHROME|THICKOUTLINE",
}

local OUTLINE_LABELS = {
    [""]                        = L["No outline"],
    ["OUTLINE"]                 = L["Outline"],
    ["THICKOUTLINE"]            = L["Thick outline"],
    ["MONOCHROME"]              = L["Monochrome"],
    ["MONOCHROME|OUTLINE"]      = L["Monochrome + Outline"],
    ["MONOCHROME|THICKOUTLINE"] = L["Monochrome + Thick outline"],
}

ns.ui = ns.ui or {}

function ns.ui.CreateTextEditor(parent, config)
    local LSM             = config.LSM
    local label           = config.label or L["Text"]
    -- Width of the text input box. Default 340; callers in a narrow (nested) box
    -- pass a smaller value so the trailing color swatch + size input still fit.
    local textWidth       = config.textWidth or 340
    local showText        = config.showText    ~= false
    local showFont        = config.showFont    ~= false
    local showSize        = config.showSize    ~= false
    local showColor       = config.showColor   ~= false
    local showOutline     = config.showOutline ~= false
    -- Safe defaults so a caller that enables a show* flag but forgets the matching
    -- getter degrades gracefully (returns nil) instead of nil-deref'ing at build;
    -- every downstream use already handles a nil return.
    local getText         = config.getText
    local getFontKey      = config.getFontKey  or function() return nil end
    local getFontPath     = config.getFontPath
    local getFontSize     = config.getFontSize or function() return nil end
    local getColor        = config.getColor    or function() return nil end
    local getOutline      = config.getOutline  or function() return nil end
    local onTextChange    = config.onTextChange
    local onFontChange    = config.onFontChange
    local onSizeChange    = config.onSizeChange
    local onColorChange   = config.onColorChange
    local onOutlineChange = config.onOutlineChange

    -- When the text input, font dropdown and size are all shown, the size control
    -- is relocated to the Font row (right of the font dropdown) instead of the
    -- cramped text row, so it never overflows a narrow nested box (e.g. the
    -- DeathAlert "Alert text" sub-box). Falls back to the text row when there is
    -- no font row to host it (showFont false / LSM missing).
    local sizeOnFontRow = showText and showSize and showFont and (LSM ~= nil)

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetWidth(518)

    local height = 0
    local result = {}

    -- ── Section label ─────────────────────────────────────────────────────────

    local sectionLabel = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sectionLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    sectionLabel:SetText(label)
    height = height + 20

    -- ── Text content ──────────────────────────────────────────────────────────

    if showText then
        local textInput = ns.ui.CreateTextInput({
            parent     = container,
            width      = textWidth,
            height     = 22,
            maxLetters = 100,
            text       = getText and getText() or "",
            onEnter    = function(val)
                -- Allow saving an empty string so the user can deliberately
                -- clear the message (previously the blank was dropped and the
                -- old value reappeared on the next Refresh).
                if val ~= nil and onTextChange then onTextChange(val) end
            end,
        })
        textInput.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
        result.textBox = textInput.editBox

        -- Color swatch to the right of the text input.
        if showColor then
            local colorSwatch = CreateFrame("Button", nil, container)
            colorSwatch:SetSize(16, 16)
            colorSwatch:SetPoint("LEFT", textInput.frame, "RIGHT", 10, 0)

            local swatchTex = colorSwatch:CreateTexture(nil, "BACKGROUND")
            swatchTex:SetAllPoints()

            local colorLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            colorLbl:SetPoint("LEFT", colorSwatch, "RIGHT", 4, 0)
            colorLbl:SetText(L["Color"])

            local function RefreshSwatch()
                local c = getColor()
                if c then swatchTex:SetColorTexture(c.r, c.g, c.b, 1) end
            end
            RefreshSwatch()
            result.RefreshSwatch = RefreshSwatch

            colorSwatch:SetScript("OnClick", function()
                local c = getColor() or { r = 1, g = 1, b = 1, a = 1 }
                ColorPickerFrame:SetupColorPickerAndShow({
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        onColorChange(r, g, b, a) RefreshSwatch()
                    end,
                    opacityFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        onColorChange(r, g, b, a) RefreshSwatch()
                    end,
                    cancelFunc = function(prev)
                        -- `opacity` in previousValues already holds the alpha
                        -- (set via opacity = c.a below), so use it directly
                        -- rather than the legacy 1-opacity conversion.
                        local a = prev.a or prev.opacity or 1
                        onColorChange(prev.r, prev.g, prev.b, a) RefreshSwatch()
                    end,
                    r = c.r, g = c.g, b = c.b, opacity = c.a,
                    hasOpacity = true,
                })
            end)

            -- Size input to the right of the color swatch (unless relocated to the
            -- Font row to keep a narrow box from overflowing).
            if showSize and not sizeOnFontRow then
                local sizeLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                sizeLbl:SetPoint("LEFT", colorLbl, "RIGHT", 10, 0)
                sizeLbl:SetText(L["Size"])

                local sizeInput = ns.ui.CreateTextInput({
                    parent     = container,
                    width      = 46,
                    height     = 22,
                    numeric    = true,
                    min        = 6,
                    max        = 64,
                    maxLetters = 3,
                    text       = tostring(getFontSize() or 22),
                    onEnter    = function(val)
                        if val and val > 0 then onSizeChange(val) end
                    end,
                })
                sizeInput.frame:SetPoint("LEFT", sizeLbl, "RIGHT", 4, 0)
                result.sizeBox = sizeInput.editBox
            end
        elseif showSize and not sizeOnFontRow then
            local sizeLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            sizeLbl:SetPoint("LEFT", textInput.frame, "RIGHT", 10, 0)
            sizeLbl:SetText(L["Size"])

            local sizeInput = ns.ui.CreateTextInput({
                parent     = container,
                width      = 46,
                height     = 22,
                numeric    = true,
                min        = 6,
                max        = 64,
                maxLetters = 3,
                text       = tostring(getFontSize() or 22),
                onEnter    = function(val)
                    if val and val > 0 then onSizeChange(val) end
                end,
            })
            sizeInput.frame:SetPoint("LEFT", sizeLbl, "RIGHT", 4, 0)
            result.sizeBox = sizeInput.editBox
        end

        height = height + 30
    elseif (showSize and getFontSize and onSizeChange) or (showColor and getColor and onColorChange) then
        -- Standalone Size + Color row when there is no text input above.
        local rightAnchor

        if showSize and getFontSize and onSizeChange then
            local sizeLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            sizeLbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
            sizeLbl:SetText(L["Size"])

            local sizeInput = ns.ui.CreateTextInput({
                parent     = container,
                width      = 46,
                height     = 22,
                numeric    = true,
                min        = 6,
                max        = 64,
                maxLetters = 3,
                text       = tostring(getFontSize() or 22),
                onEnter    = function(val)
                    if val and val > 0 then onSizeChange(val) end
                end,
            })
            sizeInput.frame:SetPoint("LEFT", sizeLbl, "RIGHT", 4, 0)
            result.sizeBox = sizeInput.editBox
            rightAnchor = sizeInput.frame
        end

        if showColor and getColor and onColorChange then
            local colorSwatch = CreateFrame("Button", nil, container)
            colorSwatch:SetSize(16, 16)
            if rightAnchor then
                colorSwatch:SetPoint("LEFT", rightAnchor, "RIGHT", 14, 0)
            else
                colorSwatch:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(height + 4))
            end

            local swatchTex = colorSwatch:CreateTexture(nil, "BACKGROUND")
            swatchTex:SetAllPoints()

            local colorLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            colorLbl:SetPoint("LEFT", colorSwatch, "RIGHT", 4, 0)
            colorLbl:SetText(L["Color"])

            local function RefreshSwatch()
                local c = getColor()
                if c then swatchTex:SetColorTexture(c.r, c.g, c.b, 1) end
            end
            RefreshSwatch()
            result.RefreshSwatch = RefreshSwatch

            colorSwatch:SetScript("OnClick", function()
                local c = getColor() or { r = 1, g = 1, b = 1, a = 1 }
                ColorPickerFrame:SetupColorPickerAndShow({
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        onColorChange(r, g, b, a); RefreshSwatch()
                    end,
                    opacityFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        onColorChange(r, g, b, a); RefreshSwatch()
                    end,
                    cancelFunc = function(prev)
                        -- `opacity` in previousValues already holds the alpha
                        -- (set via opacity = c.a below), so use it directly
                        -- rather than the legacy 1-opacity conversion.
                        local a = prev.a or prev.opacity or 1
                        onColorChange(prev.r, prev.g, prev.b, a); RefreshSwatch()
                    end,
                    r = c.r, g = c.g, b = c.b, opacity = c.a,
                    hasOpacity = true,
                })
            end)
        end

        height = height + 28
    end

    -- ── Font dropdown ─────────────────────────────────────────────────────────

    if showFont and LSM then
        local fontLabel = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fontLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
        fontLabel:SetText(L["Font"])
        height = height + 18

        local fontDD = ns.ui.CreateDropdown({
            parent        = container,
            anchorFrame   = fontLabel,
            width         = 200,
            itemHeight    = 20,
            visibleItems  = 10,
            getList       = function() return LSM:List("font") end,
            getCurrentKey = getFontKey,
            onSelect      = function(name)
                -- Resolve the LSM key to a path; fall back to the caller's
                -- stored path (config.getFontPath) if the key cannot be resolved.
                local path = LSM:Fetch("font", name)
                if not path and getFontPath then path = getFontPath() end
                onFontChange(name, path)
            end,
        })
        fontDD.selectedText:SetText(getFontKey() or L["(select a font)"])
        result.fontSelectedText = fontDD.selectedText
        -- Exposed so BuildMenu.Rebuild can reclaim the UIParent-parented drop frame.
        result.dropFrames = { fontDD.dropFrame }

        -- Size control on the Font row (right of the font dropdown) when relocated
        -- off the text row — vertically aligned with the dropdown toggle button.
        if sizeOnFontRow then
            local sizeLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            sizeLbl:SetPoint("LEFT", fontDD.toggleBtn, "RIGHT", 16, 0)
            sizeLbl:SetText(L["Size"])

            local sizeInput = ns.ui.CreateTextInput({
                parent     = container,
                width      = 46,
                height     = 22,
                numeric    = true,
                min        = 6,
                max        = 64,
                maxLetters = 3,
                text       = tostring(getFontSize() or 22),
                onEnter    = function(val)
                    if val and val > 0 then onSizeChange(val) end
                end,
            })
            sizeInput.frame:SetPoint("LEFT", sizeLbl, "RIGHT", 4, 0)
            result.sizeBox = sizeInput.editBox
        end

        height = height + 30

        -- Outline picker stacked below the font picker.
        if showOutline then
            local outlineLabel = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            outlineLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
            outlineLabel:SetText(L["Outline"])
            height = height + 18

            local outlineDD = ns.ui.CreateDropdown({
                parent        = container,
                anchorFrame   = outlineLabel,
                width         = 220,
                itemHeight    = 20,
                visibleItems  = 6,
                getList       = function()
                    local list = {}
                    for _, v in ipairs(OUTLINE_OPTIONS) do
                        table.insert(list, OUTLINE_LABELS[v])
                    end
                    return list
                end,
                getCurrentKey = function()
                    return OUTLINE_LABELS[getOutline() or ""] or L["No outline"]
                end,
                onSelect      = function(lbl)
                    for _, v in ipairs(OUTLINE_OPTIONS) do
                        if OUTLINE_LABELS[v] == lbl then
                            onOutlineChange(v)
                            break
                        end
                    end
                end,
            })
            outlineDD.selectedText:SetText(OUTLINE_LABELS[getOutline() or ""] or L["No outline"])
            result.outlineSelectedText = outlineDD.selectedText
            if result.dropFrames then result.dropFrames[#result.dropFrames + 1] = outlineDD.dropFrame end

            height = height + 30
        end
    end

    container:SetHeight(height)
    result.frame  = container
    result.height = height

    function result.Refresh()
        if showText and getText and result.textBox then
            result.textBox:SetText(getText() or "")
        end
        if showFont and result.fontSelectedText then
            result.fontSelectedText:SetText(getFontKey() or L["(select a font)"])
        end
        if showSize and result.sizeBox then
            result.sizeBox:SetText(tostring(getFontSize() or 22))
        end
        if showColor and result.RefreshSwatch then
            result.RefreshSwatch()
        end
        if showOutline and result.outlineSelectedText then
            result.outlineSelectedText:SetText(OUTLINE_LABELS[getOutline() or ""] or L["No outline"])
        end
    end

    return result
end