-- UI/TextEditor.lua

local OUTLINE_OPTIONS = {
    "", "OUTLINE", "THICKOUTLINE", "MONOCHROME",
    "MONOCHROME|OUTLINE", "MONOCHROME|THICKOUTLINE",
}

local OUTLINE_LABELS = {
    [""]                        = "No outline",
    ["OUTLINE"]                 = "Outline",
    ["THICKOUTLINE"]            = "Thick outline",
    ["MONOCHROME"]              = "Monochrome",
    ["MONOCHROME|OUTLINE"]      = "Monochrome + Outline",
    ["MONOCHROME|THICKOUTLINE"] = "Monochrome + Thick outline",
}

function HealerRange_CreateTextEditor(parent, config)
    local LSM             = config.LSM
    local label           = config.label or "Text"
    local showText        = config.showText    ~= false
    local showFont        = config.showFont    ~= false
    local showSize        = config.showSize    ~= false
    local showColor       = config.showColor   ~= false
    local showOutline     = config.showOutline ~= false
    local getText         = config.getText
    local getFontKey      = config.getFontKey
    local getFontSize     = config.getFontSize
    local getColor        = config.getColor
    local getOutline      = config.getOutline
    local onTextChange    = config.onTextChange
    local onFontChange    = config.onFontChange
    local onSizeChange    = config.onSizeChange
    local onColorChange   = config.onColorChange
    local onOutlineChange = config.onOutlineChange

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
        local textInput = Unbunk_CreateTextInput({
            parent     = container,
            width      = 340,
            height     = 22,
            maxLetters = 100,
            text       = getText and getText() or "",
            onEnter    = function(val)
                if val and val ~= "" and onTextChange then onTextChange(val) end
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
            colorLbl:SetText("Color")

            local function RefreshSwatch()
                local c = getColor()
                swatchTex:SetColorTexture(c.r, c.g, c.b, 1)
            end
            result.RefreshSwatch = RefreshSwatch

            colorSwatch:SetScript("OnClick", function()
                local c = getColor()
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
                        local a = prev.a or (prev.opacity and (1 - prev.opacity)) or 1
                        onColorChange(prev.r, prev.g, prev.b, a) RefreshSwatch()
                    end,
                    r = c.r, g = c.g, b = c.b, opacity = c.a,
                    hasOpacity = true,
                })
            end)

            -- Size input to the right of the color swatch.
            if showSize then
                local sizeLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                sizeLbl:SetPoint("LEFT", colorLbl, "RIGHT", 10, 0)
                sizeLbl:SetText("Size")

                local sizeInput = Unbunk_CreateTextInput({
                    parent     = parent,
                    width      = 46,
                    height     = 22,
                    numeric    = true,
                    maxLetters = 3,
                    text       = tostring(getFontSize() or 22),
                    onEnter    = function(val)
                        if val and val > 0 then onSizeChange(val) end
                    end,
                })
                sizeInput.frame:SetPoint("LEFT", sizeLbl, "RIGHT", 4, 0)
                result.sizeBox = sizeInput.editBox
            end
        elseif showSize then
            local sizeLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            sizeLbl:SetPoint("LEFT", textInput.frame, "RIGHT", 10, 0)
            sizeLbl:SetText("Size")

            local sizeInput = Unbunk_CreateTextInput({
                parent     = container,
                width      = 46,
                height     = 22,
                numeric    = true,
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
            sizeLbl:SetText("Size")

            local sizeInput = Unbunk_CreateTextInput({
                parent     = container,
                width      = 46,
                height     = 22,
                numeric    = true,
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
            colorLbl:SetText("Color")

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
                        local a = prev.a or (prev.opacity and (1 - prev.opacity)) or 1
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
        fontLabel:SetText("Font")
        height = height + 18

        local fontDD = HealerRange_CreateDropdown({
            parent        = container,
            anchorFrame   = fontLabel,
            width         = 200,
            itemHeight    = 20,
            visibleItems  = 10,
            getList       = function() return LSM:List("font") end,
            getCurrentKey = getFontKey,
            onSelect      = function(name)
                local path = LSM:Fetch("font", name)
                onFontChange(name, path)
            end,
        })
        fontDD.selectedText:SetText(getFontKey() or "(select a font)")
        result.fontSelectedText = fontDD.selectedText

        height = height + 30

        -- Outline picker stacked below the font picker.
        if showOutline then
            local outlineLabel = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            outlineLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
            outlineLabel:SetText("Outline")
            height = height + 18

            local outlineDD = HealerRange_CreateDropdown({
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
                    return OUTLINE_LABELS[getOutline() or ""] or "No outline"
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
            outlineDD.selectedText:SetText(OUTLINE_LABELS[getOutline() or ""] or "No outline")
            result.outlineSelectedText = outlineDD.selectedText

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
            result.fontSelectedText:SetText(getFontKey() or "(select a font)")
        end
        if showSize and result.sizeBox then
            result.sizeBox:SetText(tostring(getFontSize() or 22))
        end
        if showColor and result.RefreshSwatch then
            result.RefreshSwatch()
        end
        if showOutline and result.outlineSelectedText then
            result.outlineSelectedText:SetText(OUTLINE_LABELS[getOutline() or ""] or "No outline")
        end
    end

    return result
end