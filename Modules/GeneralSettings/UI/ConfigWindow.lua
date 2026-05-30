-- Modules/GeneralSettings/UI/ConfigWindow.lua
-- Global addon-wide options: combo sounds + death-alert anti-spam toggles.
-- Profile management lives in its own tab (Modules/Profiles/UI/ConfigWindow.lua).

local _, ns = ...
local L = ns.L

local function CreateGeneralSettingsPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints(parent)

    local GAP = 12
    local lastFrame = nil

    -- Stacks each section frame under the previous one. Heights are not tracked
    -- here; Core.lua's ComputeModuleHeight measures child bottoms at runtime.
    local function AddModule(frame)
        frame:SetWidth(518)
        if lastFrame then
            frame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, -GAP)
        else
            frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        end
        lastFrame = frame
    end

    -- ── Minimap icon section ─────────────────────────────────────────────────

    local minimapTitleFrame = CreateFrame("Frame", nil, content)
    minimapTitleFrame:SetHeight(20)
    local minimapTitleLbl = minimapTitleFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    minimapTitleLbl:SetPoint("TOPLEFT", minimapTitleFrame, "TOPLEFT", 0, 0)
    minimapTitleLbl:SetText(L["Minimap icon"])
    AddModule(minimapTitleFrame)

    local minimapFrame = CreateFrame("Frame", nil, content)
    minimapFrame:SetHeight(24)
    local minimapCb = ns.ui.CreateCheckbox({
        parent  = minimapFrame,
        label   = L["Show minimap button (left-click to open settings, drag to reposition)"],
        checked = not (ns.MinimapIcon_IsHidden and ns.MinimapIcon_IsHidden()),
        onClick = function(val)
            if ns.MinimapIcon_SetHidden then ns.MinimapIcon_SetHidden(not val) end
        end,
    })
    minimapCb.frame:SetPoint("TOPLEFT", minimapFrame, "TOPLEFT", 0, 0)
    AddModule(minimapFrame)

    -- ── Combo sounds section ─────────────────────────────────────────────────

    local comboTitleFrame = CreateFrame("Frame", nil, content)
    comboTitleFrame:SetHeight(20)
    local comboTitleLbl = comboTitleFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    comboTitleLbl:SetPoint("TOPLEFT", comboTitleFrame, "TOPLEFT", 0, 0)
    comboTitleLbl:SetText(L["Multi-alert combo sounds"])
    AddModule(comboTitleFrame)

    local comboMasterFrame = CreateFrame("Frame", nil, content)
    comboMasterFrame:SetHeight(24)
    local comboMasterCb = ns.ui.CreateCheckbox({
        parent  = comboMasterFrame,
        label   = L["Enable combo sounds (collapse near-simultaneous tracker sounds into one)"],
        checked = UnbunkUtilityDB.combo.enabled == true,
        onClick = function(val) UnbunkUtilityDB.combo.enabled = val end,
    })
    comboMasterCb.frame:SetPoint("TOPLEFT", comboMasterFrame, "TOPLEFT", 0, 0)
    AddModule(comboMasterFrame)

    -- BL combo sound picker
    local blComboPicker = ns.ui.CreateSoundPicker(content, LSM, {
        label          = L["BL combo (Bloodlust + Potion / Trinket)"],
        getSoundKey    = function() return UnbunkUtilityDB.combo.blKey end,
        getSoundEnable = function() return UnbunkUtilityDB.combo.blEnabled end,
        onSoundSelect  = function(key, path)
            UnbunkUtilityDB.combo.blKey  = key
            UnbunkUtilityDB.combo.blPath = path
        end,
        onEnableToggle = function(val) UnbunkUtilityDB.combo.blEnabled = val end,
        onTest         = function() ns.combo.PlayBLCombo() end,
    })
    AddModule(blComboPicker.frame)

    -- Potion combo sound picker
    local potionComboPicker = ns.ui.CreateSoundPicker(content, LSM, {
        label          = L["Potion combo (Potion + Trinket, without BL)"],
        getSoundKey    = function() return UnbunkUtilityDB.combo.potionKey end,
        getSoundEnable = function() return UnbunkUtilityDB.combo.potionEnabled end,
        onSoundSelect  = function(key, path)
            UnbunkUtilityDB.combo.potionKey  = key
            UnbunkUtilityDB.combo.potionPath = path
        end,
        onEnableToggle = function(val) UnbunkUtilityDB.combo.potionEnabled = val end,
        onTest         = function() ns.combo.PlayPotionCombo() end,
    })
    AddModule(potionComboPicker.frame)

    -- ── Death-alert anti-spam section ────────────────────────────────────────

    local antiTitleFrame = CreateFrame("Frame", nil, content)
    antiTitleFrame:SetHeight(20)
    local antiTitleLbl = antiTitleFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    antiTitleLbl:SetPoint("TOPLEFT", antiTitleFrame, "TOPLEFT", 0, 0)
    antiTitleLbl:SetText(L["Death alert anti-spam"])
    AddModule(antiTitleFrame)

    -- Wipe detection
    local wipeFrame = CreateFrame("Frame", nil, content)
    wipeFrame:SetHeight(40)
    local wipeCb = ns.ui.CreateCheckbox({
        parent  = wipeFrame,
        label   = L["Wipe detection: silence ALL death alerts when many people die at once"],
        checked = UnbunkUtilityDB.wipe.enabled == true,
        onClick = function(val) UnbunkUtilityDB.wipe.enabled = val end,
    })
    wipeCb.frame:SetPoint("TOPLEFT", wipeFrame, "TOPLEFT", 0, 0)
    local wipeDesc = wipeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wipeDesc:SetPoint("TOPLEFT", wipeFrame, "TOPLEFT", 26, -20)
    wipeDesc:SetText(string.format(
        L["|cffaaaaaa%d+ deaths in %ds, silence for %ds|r"],
        UnbunkUtilityDB.wipe.deathThreshold or 8,
        UnbunkUtilityDB.wipe.timeWindow or 3,
        UnbunkUtilityDB.wipe.suppressDuration or 15
    ))
    AddModule(wipeFrame)

    -- DPS spam guard
    local dpsFrame = CreateFrame("Frame", nil, content)
    dpsFrame:SetHeight(40)
    local dpsCb = ns.ui.CreateCheckbox({
        parent  = dpsFrame,
        label   = L["DPS spam guard: silence DPS death alerts on burst DPS deaths"],
        checked = UnbunkUtilityDB.dpsSpam.enabled == true,
        onClick = function(val) UnbunkUtilityDB.dpsSpam.enabled = val end,
    })
    dpsCb.frame:SetPoint("TOPLEFT", dpsFrame, "TOPLEFT", 0, 0)
    local dpsDesc = dpsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dpsDesc:SetPoint("TOPLEFT", dpsFrame, "TOPLEFT", 26, -20)
    dpsDesc:SetText(string.format(
        L["|cffaaaaaa%d+ DPS deaths in %ds, silence DPS alerts for %ds|r"],
        UnbunkUtilityDB.dpsSpam.deathThreshold or 3,
        UnbunkUtilityDB.dpsSpam.timeWindow or 3,
        UnbunkUtilityDB.dpsSpam.suppressDuration or 6
    ))
    AddModule(dpsFrame)

    -- ── OnShow refresh ───────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        minimapCb.SetChecked(not (ns.MinimapIcon_IsHidden and ns.MinimapIcon_IsHidden()))
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
    UnbunkUtility.RegisterModule(L["General Settings"], nil, CreateGeneralSettingsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
