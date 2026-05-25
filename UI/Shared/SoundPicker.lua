-- UI/SoundPicker.lua

function HealerRange_CreateSoundPicker(parent, LSM, config)
    config = config or {}
    local getSoundKey    = config.getSoundKey    or function() return HealerRangeCfg_Get("soundKey") end
    local getSoundEnable = config.getSoundEnable or function() return HealerRangeCfg_Get("enableSound") end
    local onSoundSelect  = config.onSoundSelect  or function(key, path)
        HealerRangeCfg_Set("soundKey", key)
        HealerRangeCfg_Set("soundPath", path)
    end
    local onEnableToggle = config.onEnableToggle or function(val)
        HealerRangeCfg_Set("enableSound", val)
    end
    local onTest = config.onTest or HealerRangePlaySound
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetWidth(518)

    local height = 0

    -- ── Checkbox ──────────────────────────────────────────────────────────────

    local soundCheckbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    soundCheckbox:SetSize(24, 24)
    soundCheckbox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    soundCheckbox:SetChecked(getSoundEnable() ~= false)
        soundCheckbox:SetScript("OnClick", function(self)
            onEnableToggle(self:GetChecked())
        end)

    local soundCheckLabel = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    soundCheckLabel:SetPoint("LEFT", soundCheckbox, "RIGHT", 2, 0)
    soundCheckLabel:SetText("Alert sound")

    height = height + 28

    -- ── Dropdown ──────────────────────────────────────────────────────────────

    local selectedText = nil

    if LSM then
        local ddAnchor = container:CreateFontString(nil, "ARTWORK")
        ddAnchor:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)

        local dd = HealerRange_CreateDropdown({
            parent        = container,
            anchorFrame   = ddAnchor,
            width         = 290,
            itemHeight    = 20,
            visibleItems  = 10,
            getList       = function() return LSM:List("sound") end,
            getCurrentKey = getSoundKey,
            onSelect      = function(name)
                local path = LSM:Fetch("sound", name)
                onSoundSelect(name, path)
            end,
        })
        dd.selectedText:SetText(getSoundKey() or "(select a sound)")
        selectedText = dd.selectedText

        local soundTest = CreateFrame("Button", nil, container)
        soundTest:SetSize(22, 22)
        soundTest:SetPoint("LEFT", dd.toggleBtn, "RIGHT", 6, 0)
        soundTest:SetNormalTexture("Interface/Common/VoiceChat-Speaker")
        soundTest:SetHighlightTexture("Interface/Common/VoiceChat-On")
        soundTest:SetScript("OnClick", onTest)

        height = height + 30
    else
        local noLSM = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        noLSM:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
        noLSM:SetTextColor(1, 0.5, 0)
        noLSM:SetText("LibSharedMedia-3.0 not found — enter sound ID manually:")

        height = height + 20

        local soundBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
        soundBox:SetSize(100, 20)
        soundBox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
        soundBox:SetAutoFocus(false)
        soundBox:SetNumeric(true)
        soundBox:SetMaxLetters(6)
        soundBox:SetText("8959")
        soundBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        local soundTest = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        soundTest:SetSize(60, 22)
        soundTest:SetPoint("LEFT", soundBox, "RIGHT", 8, 0)
        soundTest:SetText("Test")
        soundTest:SetScript("OnClick", function()
            local id = tonumber(soundBox:GetText())
            if id then PlaySound(id) end
        end)

        height = height + 30
    end

    container:SetHeight(height)

    local result = {}
    result.frame = container
    result.height = height
    result.soundCheckbox = soundCheckbox
    result.selectedText  = selectedText

    function result.Refresh()
        soundCheckbox:SetChecked(getSoundEnable() ~= false)
        if selectedText then
            selectedText:SetText(getSoundKey() or "(select a sound)")
        end
    end

    return result
end