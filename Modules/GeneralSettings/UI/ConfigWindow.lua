-- Modules/GeneralSettings/UI/ConfigWindow.lua

local _, ns = ...

local function CreateGeneralSettingsPanel(parent)
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

    -- ── Titre ─────────────────────────────────────────────────────────────────

    local titleFrame = CreateFrame("Frame", nil, content)
    titleFrame:SetHeight(20)
    local titleLbl = titleFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleLbl:SetPoint("TOPLEFT", titleFrame, "TOPLEFT", 0, 0)
    titleLbl:SetText("Profile Management")
    AddModule(titleFrame, 20)

    -- ── Profil actuel ─────────────────────────────────────────────────────────

    local currentFrame = CreateFrame("Frame", nil, content)
    currentFrame:SetHeight(24)
    local currentLbl = currentFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    currentLbl:SetPoint("TOPLEFT", currentFrame, "TOPLEFT", 0, 0)
    currentLbl:SetText("Current profile: |cffffd700" .. UnbunkProfiles_GetCurrent() .. "|r")
    AddModule(currentFrame, 24)

    -- ── Dropdown sélection profil ─────────────────────────────────────────────

    local ddFrame = CreateFrame("Frame", nil, content)
    ddFrame:SetHeight(50)

    local ddLbl = ddFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ddLbl:SetPoint("TOPLEFT", ddFrame, "TOPLEFT", 0, 0)
    ddLbl:SetText("Switch profile")

    local ddAnchor = ddFrame:CreateFontString(nil, "ARTWORK")
    ddAnchor:SetPoint("TOPLEFT", ddFrame, "TOPLEFT", 0, -20)

    local profileDD = HealerRange_CreateDropdown({
        parent        = ddFrame,
        anchorFrame   = ddAnchor,
        width         = 200,
        itemHeight    = 20,
        visibleItems  = 8,
        getList       = function() return UnbunkProfiles_GetList() end,
        getCurrentKey = function() return UnbunkProfiles_GetCurrent() end,
        onSelect      = function(name)
            if name == UnbunkProfiles_GetCurrent() then return end
            UnbunkProfiles_SaveCurrent()
            UnbunkProfiles_Load(name)
            currentLbl:SetText("Current profile: |cffffd700" .. name .. "|r")
            print("|cffff4444[UnbunkUtility]|r Profile loaded: " .. name)
        end,
    })
    profileDD.selectedText:SetText(UnbunkProfiles_GetCurrent())

    AddModule(ddFrame, 50)

    -- ── Créer un profil ───────────────────────────────────────────────────────

    local createFrame = CreateFrame("Frame", nil, content)
    createFrame:SetHeight(50)

    local createLbl = createFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    createLbl:SetPoint("TOPLEFT", createFrame, "TOPLEFT", 0, 0)
    createLbl:SetText("Create new profile")

    local createInput = Unbunk_CreateTextInput({
        parent     = createFrame,
        width      = 200,
        height     = 22,
        maxLetters = 32,
        text       = "",
    })
    createInput.frame:SetPoint("TOPLEFT", createFrame, "TOPLEFT", 0, -22)

    local createBtn = Unbunk_CreateButton({
        parent  = createFrame,
        label   = "Create",
        width   = 70,
        height  = 22,
        onClick = function()
            local name = createInput.GetText()
            if name and name ~= "" then
                if UnbunkProfiles_Create(name) then
                    profileDD.selectedText:SetText(name)
                    currentLbl:SetText("Current profile: |cffffd700" .. name .. "|r")
                    createInput.SetText("")
                    print("|cffff4444[UnbunkUtility]|r Profile created: " .. name)
                else
                    print("|cffff4444[UnbunkUtility]|r Profile already exists: " .. name)
                end
            end
        end,
    })
    createBtn.frame:SetPoint("LEFT", createInput.frame, "RIGHT", 8, 0)

    AddModule(createFrame, 50)

    -- ── Supprimer un profil ───────────────────────────────────────────────────

    local deleteFrame = CreateFrame("Frame", nil, content)
    deleteFrame:SetHeight(50)

    local deleteLbl = deleteFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    deleteLbl:SetPoint("TOPLEFT", deleteFrame, "TOPLEFT", 0, 0)
    deleteLbl:SetText("Delete profile")

    local deleteDD = HealerRange_CreateDropdown({
        parent        = deleteFrame,
        anchorFrame   = (function()
            local a = deleteFrame:CreateFontString(nil, "ARTWORK")
            a:SetPoint("TOPLEFT", deleteFrame, "TOPLEFT", 0, -20)
            return a
        end)(),
        width         = 200,
        itemHeight    = 20,
        visibleItems  = 8,
        getList       = function()
            local list = UnbunkProfiles_GetList()
            -- Retire Default de la liste
            for i, v in ipairs(list) do
                if v == "Default" then table.remove(list, i) break end
            end
            return list
        end,
        getCurrentKey = function() return "" end,
        onSelect      = function(name) end,
    })

    local deleteBtn = Unbunk_CreateButton({
        parent  = deleteFrame,
        label   = "Delete",
        width   = 70,
        height  = 22,
        onClick = function()
            local name = deleteDD.selectedText:GetText()
            if name and name ~= "" and name ~= "Default" then
                if UnbunkProfiles_Delete(name) then
                    deleteDD.selectedText:SetText("")
                    currentLbl:SetText("Current profile: |cffffd700" .. UnbunkProfiles_GetCurrent() .. "|r")
                    profileDD.selectedText:SetText(UnbunkProfiles_GetCurrent())
                    print("|cffff4444[UnbunkUtility]|r Profile deleted: " .. name)
                end
            end
        end,
    })
    deleteBtn.frame:SetPoint("LEFT", deleteDD.toggleBtn, "RIGHT", 8, 0)

    AddModule(deleteFrame, 50)

    -- ── Export ────────────────────────────────────────────────────────────────

    local exportFrame = CreateFrame("Frame", nil, content)
    exportFrame:SetHeight(80)

    local exportLbl = exportFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    exportLbl:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 0, 0)
    exportLbl:SetText("Export current profile")

    local exportBox = CreateFrame("EditBox", nil, exportFrame, "InputBoxTemplate")
    exportBox:SetSize(400, 22)
    exportBox:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 0, -22)
    exportBox:SetAutoFocus(false)
    exportBox:SetMaxLetters(0)

    local exportBtn = Unbunk_CreateButton({
        parent  = exportFrame,
        label   = "Export",
        width   = 70,
        height  = 22,
        onClick = function()
            local str = UnbunkProfiles_Export()
            exportBox:SetText(str)
            exportBox:SetFocus()
            exportBox:HighlightText()
        end,
    })
    exportBtn.frame:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 0, -50)

    AddModule(exportFrame, 80)

    -- ── Import ────────────────────────────────────────────────────────────────

    local importFrame = CreateFrame("Frame", nil, content)
    importFrame:SetHeight(80)

    local importLbl = importFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importLbl:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 0, 0)
    importLbl:SetText("Import profile (overwrites current)")

    local importBox = CreateFrame("EditBox", nil, importFrame, "InputBoxTemplate")
    importBox:SetSize(400, 22)
    importBox:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 0, -22)
    importBox:SetAutoFocus(false)
    importBox:SetMaxLetters(0)

    local importBtn = Unbunk_CreateButton({
        parent  = importFrame,
        label   = "Import",
        width   = 70,
        height  = 22,
        onClick = function()
            local str = importBox:GetText()
            if str and str ~= "" then
                local ok, err = UnbunkProfiles_Import(str)
                if ok then
                    currentLbl:SetText("Current profile: |cffffd700" .. UnbunkProfiles_GetCurrent() .. "|r")
                    print("|cffff4444[UnbunkUtility]|r Profile imported successfully.")
                else
                    print("|cffff4444[UnbunkUtility]|r Import failed: " .. tostring(err))
                end
            end
        end,
    })
    importBtn.frame:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 0, -50)

    AddModule(importFrame, 80)

    -- ── Reset profil ──────────────────────────────────────────────────────────

    local resetFrame = CreateFrame("Frame", nil, content)
    resetFrame:SetHeight(50)

    local resetLbl = resetFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    resetLbl:SetPoint("TOPLEFT", resetFrame, "TOPLEFT", 0, 0)
    resetLbl:SetText("Reset current profile to defaults")

    local resetBtn = Unbunk_CreateButton({
        parent  = resetFrame,
        label   = "Reset",
        width   = 70,
        height  = 22,
        onClick = function()
            local name = UnbunkProfiles_GetCurrent()
            HealerRangeDB    = {}
            DeathAlertDB     = {}
            BLTrackerDB      = {}
            PotionTrackerDB  = {}
            TrinketTrackerDB = {}
            PITrackerDB      = {}
            HealerRangeCfg_Init()
            DeathAlertCfg_Init()
            BLTrackerCfg_Init()
            PotionTrackerCfg_Init()
            TrinketTrackerCfg_Init()
            ns.PITracker.CfgInit()
            UnbunkProfiles_SaveCurrent()
            UnbunkProfiles_ReloadAll()
            print("|cffff4444[UnbunkUtility]|r Profile reset to defaults: " .. name)
        end,
    })
    resetBtn.frame:SetPoint("TOPLEFT", resetFrame, "TOPLEFT", 0, -22)
    AddModule(resetFrame, 50)

    -- ── OnShow refresh ────────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        currentLbl:SetText("Current profile: |cffffd700" .. UnbunkProfiles_GetCurrent() .. "|r")
        profileDD.selectedText:SetText(UnbunkProfiles_GetCurrent())
    end)
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initGS = CreateFrame("Frame")
initGS:RegisterEvent("ADDON_LOADED")
initGS:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule("General Settings", nil, CreateGeneralSettingsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)