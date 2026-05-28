-- UI/SoundPicker.lua

local _, ns = ...
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

function HealerRange_CreateSoundPicker(parent, LSM, config)
    config = config or {}
    local getSoundKey    = config.getSoundKey    or function() return HR.CfgGet("soundKey") end
    local getSoundEnable = config.getSoundEnable or function() return HR.CfgGet("enableSound") end
    local onSoundSelect  = config.onSoundSelect  or function(key, path)
        HR.CfgSet("soundKey", key)
        HR.CfgSet("soundPath", path)
    end
    local onEnableToggle = config.onEnableToggle or function(val)
        HR.CfgSet("enableSound", val)
    end
    local onTest = config.onTest or HR.PlaySound
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetWidth(518)

    local height = 0

    -- ── Checkbox ──────────────────────────────────────────────────────────────

    local soundCheckbox = Unbunk_CreateCheckbox({
        parent  = container,
        label   = config.label or "Alert sound",
        checked = getSoundEnable() ~= false,
        onClick = function(val) onEnableToggle(val) end,
    })
    soundCheckbox.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    height = height + 24

    -- ── Dropdown ──────────────────────────────────────────────────────────────

    local selectedText = nil

    if LSM then
        local ddAnchor = soundCheckbox.frame

        local dd = HealerRange_CreateDropdown({
            parent        = container,
            anchorFrame   = ddAnchor,
            width         = 290,
            itemHeight    = 20,
            visibleItems  = 10,
            getList       = function()
                local list = { "None" }
                for _, name in ipairs(LSM:List("sound")) do
                    table.insert(list, name)
                end
                return list
            end,
            getCurrentKey = function() return getSoundKey() or "None" end,
            onSelect      = function(name)
                if name == "None" then
                    onSoundSelect(nil, nil)
                else
                    local path = LSM:Fetch("sound", name)
                    onSoundSelect(name, path)
                end
            end,
        })
        dd.selectedText:SetText(getSoundKey() or "None")
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

    function result.Refresh()
        soundCheckbox.SetChecked(getSoundEnable() ~= false)
        if selectedText then
            selectedText:SetText(getSoundKey() or "None")
        end
    end

    return result
end