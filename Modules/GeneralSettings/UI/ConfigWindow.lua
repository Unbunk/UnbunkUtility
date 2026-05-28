-- Modules/GeneralSettings/UI/ConfigWindow.lua
-- Global addon-wide options: combo sounds + death-alert anti-spam toggles.
-- Profile management lives in its own tab (Modules/Profiles/UI/ConfigWindow.lua).

local _, ns = ...

local function CreateGeneralSettingsPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints(parent)

    local GAP = 12
    local lastFrame = nil

    local function AddModule(frame, frameHeight)
        frame:SetWidth(518)
        if lastFrame then
            frame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -GAP)
        else
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        lastFrame = frame
    end

    -- ── Combo sounds section ─────────────────────────────────────────────────

    local comboTitleFrame = CreateFrame("Frame", nil, content)
    comboTitleFrame:SetHeight(20)
    local comboTitleLbl = comboTitleFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    comboTitleLbl:SetPoint("TOPLEFT", comboTitleFrame, "TOPLEFT", 0, 0)
    comboTitleLbl:SetText("Multi-alert combo sounds")
    AddModule(comboTitleFrame, 20)

    local comboMasterFrame = CreateFrame("Frame", nil, content)
    comboMasterFrame:SetHeight(24)
    local comboMasterCb = Unbunk_CreateCheckbox({
        parent  = comboMasterFrame,
        label   = "Enable combo sounds (collapse near-simultaneous tracker sounds into one)",
        checked = UnbunkUtilityDB.combo.enabled == true,
        onClick = function(val) UnbunkUtilityDB.combo.enabled = val end,
    })
    comboMasterCb.frame:SetPoint("TOPLEFT", comboMasterFrame, "TOPLEFT", 0, 0)
    AddModule(comboMasterFrame, 24)

    -- BL combo sound picker
    local blComboPicker = HealerRange_CreateSoundPicker(content, LSM, {
        label          = "BL combo (Bloodlust + Potion / Trinket)",
        getSoundKey    = function() return UnbunkUtilityDB.combo.blKey end,
        getSoundEnable = function() return UnbunkUtilityDB.combo.blEnabled end,
        onSoundSelect  = function(key, path)
            UnbunkUtilityDB.combo.blKey  = key
            UnbunkUtilityDB.combo.blPath = path
        end,
        onEnableToggle = function(val) UnbunkUtilityDB.combo.blEnabled = val end,
        onTest         = function() ns.combo.PlayBLCombo() end,
    })
    AddModule(blComboPicker.frame, blComboPicker.height)

    -- Potion combo sound picker
    local potionComboPicker = HealerRange_CreateSoundPicker(content, LSM, {
        label          = "Potion combo (Potion + Trinket, without BL)",
        getSoundKey    = function() return UnbunkUtilityDB.combo.potionKey end,
        getSoundEnable = function() return UnbunkUtilityDB.combo.potionEnabled end,
        onSoundSelect  = function(key, path)
            UnbunkUtilityDB.combo.potionKey  = key
            UnbunkUtilityDB.combo.potionPath = path
        end,
        onEnableToggle = function(val) UnbunkUtilityDB.combo.potionEnabled = val end,
        onTest         = function() ns.combo.PlayPotionCombo() end,
    })
    AddModule(potionComboPicker.frame, potionComboPicker.height)

    -- ── Death-alert anti-spam section ────────────────────────────────────────

    local antiTitleFrame = CreateFrame("Frame", nil, content)
    antiTitleFrame:SetHeight(20)
    local antiTitleLbl = antiTitleFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    antiTitleLbl:SetPoint("TOPLEFT", antiTitleFrame, "TOPLEFT", 0, 0)
    antiTitleLbl:SetText("Death alert anti-spam")
    AddModule(antiTitleFrame, 20)

    -- Wipe detection
    local wipeFrame = CreateFrame("Frame", nil, content)
    wipeFrame:SetHeight(40)
    local wipeCb = Unbunk_CreateCheckbox({
        parent  = wipeFrame,
        label   = "Wipe detection: silence ALL death alerts when many people die at once",
        checked = UnbunkUtilityDB.wipe.enabled == true,
        onClick = function(val) UnbunkUtilityDB.wipe.enabled = val end,
    })
    wipeCb.frame:SetPoint("TOPLEFT", wipeFrame, "TOPLEFT", 0, 0)
    local wipeDesc = wipeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wipeDesc:SetPoint("TOPLEFT", wipeFrame, "TOPLEFT", 26, -20)
    wipeDesc:SetText(string.format(
        "|cffaaaaaa%d+ deaths in %ds, silence for %ds|r",
        UnbunkUtilityDB.wipe.deathThreshold or 8,
        UnbunkUtilityDB.wipe.timeWindow or 3,
        UnbunkUtilityDB.wipe.suppressDuration or 15
    ))
    AddModule(wipeFrame, 40)

    -- DPS spam guard
    local dpsFrame = CreateFrame("Frame", nil, content)
    dpsFrame:SetHeight(40)
    local dpsCb = Unbunk_CreateCheckbox({
        parent  = dpsFrame,
        label   = "DPS spam guard: silence DPS death alerts on burst DPS deaths",
        checked = UnbunkUtilityDB.dpsSpam.enabled == true,
        onClick = function(val) UnbunkUtilityDB.dpsSpam.enabled = val end,
    })
    dpsCb.frame:SetPoint("TOPLEFT", dpsFrame, "TOPLEFT", 0, 0)
    local dpsDesc = dpsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpsDesc:SetPoint("TOPLEFT", dpsFrame, "TOPLEFT", 26, -20)
    dpsDesc:SetText(string.format(
        "|cffaaaaaa%d+ DPS deaths in %ds, silence DPS alerts for %ds|r",
        UnbunkUtilityDB.dpsSpam.deathThreshold or 3,
        UnbunkUtilityDB.dpsSpam.timeWindow or 3,
        UnbunkUtilityDB.dpsSpam.suppressDuration or 6
    ))
    AddModule(dpsFrame, 40)

    -- ── OnShow refresh ───────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        comboMasterCb.SetChecked(UnbunkUtilityDB.combo.enabled == true)
        blComboPicker.Refresh()
        potionComboPicker.Refresh()
        wipeCb.SetChecked(UnbunkUtilityDB.wipe.enabled == true)
        dpsCb.SetChecked(UnbunkUtilityDB.dpsSpam.enabled == true)
    end)
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initGS = CreateFrame("Frame")
initGS:RegisterEvent("ADDON_LOADED")
initGS:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule("General Settings", nil, CreateGeneralSettingsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
