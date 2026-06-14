-- UI/SoundPicker.lua

local _, ns = ...
local L = ns.L
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

ns.ui = ns.ui or {}

function ns.ui.CreateSoundPicker(parent, LSM, config)
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

    -- Localised "no sound" sentinel, used consistently for the list entry, the
    -- current-value display and the onSelect comparison (so localising the
    -- label can't break the comparison).
    local NONE = L["None"]

    -- The no-LSM fallback EditBox is numeric; only pre-fill it when the stored
    -- value is actually a numeric sound id. A stored LSM *key* is text, which a
    -- numeric box renders blank — looking like the user lost their setting.
    local function NumericSoundText()
        local k = getSoundKey()
        return (k and tonumber(k)) and tostring(k) or "8959"
    end

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetWidth(518)

    local height = 0

    -- Greys + mouse-blocks the controls below when the sound is disabled (assigned
    -- once they're built). `gateDimFrames` collects the frames to fade per branch.
    local ApplySoundGate
    local gateDimFrames = {}

    -- ── Checkbox (master — stays interactive while the rest greys) ──────────────

    local soundCheckbox = ns.ui.CreateCheckbox({
        parent  = container,
        label   = config.label or L["Alert sound"],
        checked = getSoundEnable() ~= false,
        onClick = function(val)
            onEnableToggle(val)
            if ApplySoundGate then ApplySoundGate() end
        end,
    })
    soundCheckbox.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    height = height + 24

    -- ── Dropdown ──────────────────────────────────────────────────────────────

    local selectedText = nil
    local soundEntry = nil
    local dropFrameRef = nil

    if LSM then
        local ddAnchor = soundCheckbox.frame

        local dd = ns.ui.CreateDropdown({
            parent        = container,
            anchorFrame   = ddAnchor,
            width         = 290,
            itemHeight    = 20,
            visibleItems  = 10,
            searchable    = true,
            getList       = function()
                local list = { NONE }
                for _, name in ipairs(LSM:List("sound")) do
                    table.insert(list, name)
                end
                return list
            end,
            getCurrentKey = function() return getSoundKey() or NONE end,
            onSelect      = function(name)
                if name == NONE then
                    onSoundSelect(nil, nil)
                else
                    local path = LSM:Fetch("sound", name)
                    onSoundSelect(name, path)
                end
            end,
        })
        -- (CreateDropdown already initialises selectedText from getCurrentKey.)
        selectedText = dd.selectedText
        dropFrameRef = dd.dropFrame

        local soundTest = CreateFrame("Button", nil, container)
        soundTest:SetSize(22, 22)
        soundTest:SetPoint("LEFT", dd.toggleBtn, "RIGHT", 6, 0)
        -- White speaker glyph tinted to the brand blue via SetVertexColor (re-applied
        -- after each texture swap, since SetNormalTexture resets the tint). Resting
        -- shows the "off" variant, swap to "on" (emitting) on hover.
        local function tintSpeaker(btn)
            local t = btn:GetNormalTexture()
            if t then t:SetVertexColor(ns.GetBrandColor()) end
        end
        soundTest:SetNormalTexture(UNBUNK_ICON_SPEAKER_OFF)
        tintSpeaker(soundTest)
        -- Re-tint live on a brand-colour change (weak-keyed by the button).
        if ns.RegisterBrandRefresh then ns.RegisterBrandRefresh(soundTest, function() tintSpeaker(soundTest) end) end
        soundTest:SetScript("OnEnter", function(self) self:SetNormalTexture(UNBUNK_ICON_SPEAKER_ON); tintSpeaker(self) end)
        soundTest:SetScript("OnLeave", function(self) self:SetNormalTexture(UNBUNK_ICON_SPEAKER_OFF); tintSpeaker(self) end)
        soundTest:SetScript("OnClick", onTest)

        gateDimFrames = { dd.toggleBtn, soundTest }   -- selectedText is a child of toggleBtn
        height = height + 30
    else
        local noLSM = container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
        noLSM:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
        noLSM:SetTextColor(1, 0.5, 0)
        noLSM:SetText(L["LibSharedMedia-3.0 not found — enter sound ID manually:"])

        height = height + 20

        local soundBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
        soundBox:SetSize(100, 20)
        soundBox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
        soundBox:SetAutoFocus(false)
        soundBox:SetNumeric(true)
        soundBox:SetMaxLetters(6)
        soundBox:SetText(NumericSoundText())
        -- Persist the entered sound id so the no-LSM fallback actually saves.
        soundBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            local txt = self:GetText()
            onSoundSelect(txt ~= "" and txt or nil, nil)
        end)
        soundEntry = soundBox

        local soundTest = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        soundTest:SetSize(60, 22)
        soundTest:SetPoint("LEFT", soundBox, "RIGHT", 8, 0)
        soundTest:SetText(L["Test"])
        soundTest:SetScript("OnClick", function()
            local id = tonumber(soundBox:GetText())
            if id then PlaySound(id) end
        end)

        gateDimFrames = { noLSM, soundBox, soundTest }
        height = height + 30
    end

    container:SetHeight(height)

    -- ── Disable gate: grey + block the controls while the sound is unchecked ─────
    -- Only the controls BELOW the checkbox are gated, so the "Alert sound" checkbox
    -- itself stays live to re-enable. The blocked region spans from just under the
    -- checkbox to the bottom of the picker.
    local gateRegion = CreateFrame("Frame", nil, container)
    gateRegion:SetPoint("TOPLEFT",     soundCheckbox.frame, "BOTTOMLEFT", 0, -2)
    gateRegion:SetPoint("BOTTOMRIGHT", container,            "BOTTOMRIGHT", 0, 0)
    local applyGate = ns.ui.MakeDisableGate(gateRegion)
    ApplySoundGate = function()
        applyGate(getSoundEnable() ~= false, gateDimFrames)
    end
    ApplySoundGate()

    local result = {}
    result.frame = container
    result.height = height
    result.soundCheckbox = soundCheckbox
    result.dropFrame = dropFrameRef   -- so BuildMenu.Rebuild reclaims the drop frame

    function result.Refresh()
        soundCheckbox.SetChecked(getSoundEnable() ~= false)
        if selectedText then
            selectedText:SetText(getSoundKey() or NONE)
        end
        if soundEntry then
            soundEntry:SetText(NumericSoundText())
        end
        ApplySoundGate()
    end

    return result
end