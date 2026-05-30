-- Modules/Profiles/UI/ConfigWindow.lua
-- Profile management tab (extracted from General Settings). Wraps the
-- ns.profiles.* API (defined in Core/Profiles.lua) with a UI.

local _, ns = ...
local L = ns.L

local function CreateProfilesPanel(parent)
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

    -- ── Title ─────────────────────────────────────────────────────────────────

    local titleFrame = CreateFrame("Frame", nil, content)
    titleFrame:SetHeight(20)
    local titleLbl = titleFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleLbl:SetPoint("TOPLEFT", titleFrame, "TOPLEFT", 0, 0)
    titleLbl:SetText(L["Profile Management"])
    AddModule(titleFrame, 20)

    -- ── Current profile ──────────────────────────────────────────────────────

    local currentFrame = CreateFrame("Frame", nil, content)
    currentFrame:SetHeight(24)
    local currentLbl = currentFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    currentLbl:SetPoint("TOPLEFT", currentFrame, "TOPLEFT", 0, 0)
    currentLbl:SetText(string.format(L["Current profile: |cffffd700%s|r"], ns.profiles.GetCurrent()))
    AddModule(currentFrame, 24)

    -- ── Switch profile dropdown ──────────────────────────────────────────────

    local ddFrame = CreateFrame("Frame", nil, content)
    ddFrame:SetHeight(50)

    local ddLbl = ddFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ddLbl:SetPoint("TOPLEFT", ddFrame, "TOPLEFT", 0, 0)
    ddLbl:SetText(L["Switch profile"])

    local ddAnchor = ddFrame:CreateFontString(nil, "ARTWORK")
    ddAnchor:SetPoint("TOPLEFT", ddFrame, "TOPLEFT", 0, -20)

    local profileDD = ns.ui.CreateDropdown({
        parent        = ddFrame,
        anchorFrame   = ddAnchor,
        width         = 200,
        itemHeight    = 20,
        visibleItems  = 8,
        getList       = function() return ns.profiles.GetList() end,
        getCurrentKey = function() return ns.profiles.GetCurrent() end,
        onSelect      = function(name)
            if name == ns.profiles.GetCurrent() then return end
            ns.profiles.SaveCurrent()
            ns.profiles.Load(name)
            currentLbl:SetText(string.format(L["Current profile: |cffffd700%s|r"], name))
            print(string.format(L["|cffff4444[UnbunkUtility]|r Profile loaded: %s"], name))
        end,
    })
    profileDD.selectedText:SetText(ns.profiles.GetCurrent())

    AddModule(ddFrame, 50)

    -- ── Create profile ───────────────────────────────────────────────────────

    local createFrame = CreateFrame("Frame", nil, content)
    createFrame:SetHeight(50)

    local createLbl = createFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    createLbl:SetPoint("TOPLEFT", createFrame, "TOPLEFT", 0, 0)
    createLbl:SetText(L["Create new profile"])

    local createInput = ns.ui.CreateTextInput({
        parent     = createFrame,
        width      = 200,
        height     = 22,
        maxLetters = 32,
        text       = "",
    })
    createInput.frame:SetPoint("TOPLEFT", createFrame, "TOPLEFT", 0, -22)

    local createBtn = ns.ui.CreateButton({
        parent  = createFrame,
        label   = L["Create"],
        width   = 70,
        height  = 22,
        onClick = function()
            local name = createInput.GetText()
            if name and name ~= "" then
                if ns.profiles.Create(name) then
                    profileDD.selectedText:SetText(name)
                    currentLbl:SetText(string.format(L["Current profile: |cffffd700%s|r"], name))
                    createInput.SetText("")
                    print(string.format(L["|cffff4444[UnbunkUtility]|r Profile created: %s"], name))
                else
                    print(string.format(L["|cffff4444[UnbunkUtility]|r Profile already exists: %s"], name))
                end
            end
        end,
    })
    createBtn.frame:SetPoint("LEFT", createInput.frame, "RIGHT", 8, 0)

    AddModule(createFrame, 50)

    -- ── Delete profile ───────────────────────────────────────────────────────

    local deleteFrame = CreateFrame("Frame", nil, content)
    deleteFrame:SetHeight(50)

    local deleteLbl = deleteFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    deleteLbl:SetPoint("TOPLEFT", deleteFrame, "TOPLEFT", 0, 0)
    deleteLbl:SetText(L["Delete profile"])

    local deleteDD = ns.ui.CreateDropdown({
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
            local list = ns.profiles.GetList()
            -- Remove Default from the list
            for i, v in ipairs(list) do
                if v == "Default" then table.remove(list, i) break end
            end
            return list
        end,
        getCurrentKey = function() return "" end,
        onSelect      = function(name) end,
    })

    local deleteBtn = ns.ui.CreateButton({
        parent  = deleteFrame,
        label   = L["Delete"],
        width   = 70,
        height  = 22,
        onClick = function()
            local name = deleteDD.selectedText:GetText()
            if name and name ~= "" and name ~= "Default" then
                if ns.profiles.Delete(name) then
                    deleteDD.selectedText:SetText("")
                    currentLbl:SetText(string.format(L["Current profile: |cffffd700%s|r"], ns.profiles.GetCurrent()))
                    profileDD.selectedText:SetText(ns.profiles.GetCurrent())
                    print(string.format(L["|cffff4444[UnbunkUtility]|r Profile deleted: %s"], name))
                end
            end
        end,
    })
    deleteBtn.frame:SetPoint("LEFT", deleteDD.toggleBtn, "RIGHT", 8, 0)

    AddModule(deleteFrame, 50)

    -- ── Export ───────────────────────────────────────────────────────────────

    local exportFrame = CreateFrame("Frame", nil, content)
    exportFrame:SetHeight(80)

    local exportLbl = exportFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    exportLbl:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 0, 0)
    exportLbl:SetText(L["Export current profile"])

    local exportBox = CreateFrame("EditBox", nil, exportFrame, "InputBoxTemplate")
    exportBox:SetSize(400, 22)
    exportBox:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 0, -22)
    exportBox:SetAutoFocus(false)
    exportBox:SetMaxLetters(0)

    local exportBtn = ns.ui.CreateButton({
        parent  = exportFrame,
        label   = L["Export"],
        width   = 70,
        height  = 22,
        onClick = function()
            local str = ns.profiles.Export()
            exportBox:SetText(str)
            exportBox:SetFocus()
            exportBox:HighlightText()
        end,
    })
    exportBtn.frame:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 0, -50)

    AddModule(exportFrame, 80)

    -- ── Import ───────────────────────────────────────────────────────────────

    local importFrame = CreateFrame("Frame", nil, content)
    importFrame:SetHeight(80)

    local importLbl = importFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importLbl:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 0, 0)
    importLbl:SetText(L["Import profile (overwrites current)"])

    local importBox = CreateFrame("EditBox", nil, importFrame, "InputBoxTemplate")
    importBox:SetSize(400, 22)
    importBox:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 0, -22)
    importBox:SetAutoFocus(false)
    importBox:SetMaxLetters(0)

    local importBtn = ns.ui.CreateButton({
        parent  = importFrame,
        label   = L["Import"],
        width   = 70,
        height  = 22,
        onClick = function()
            local str = importBox:GetText()
            if str and str ~= "" then
                local ok, err = ns.profiles.Import(str)
                if ok then
                    currentLbl:SetText(string.format(L["Current profile: |cffffd700%s|r"], ns.profiles.GetCurrent()))
                    print(L["|cffff4444[UnbunkUtility]|r Profile imported successfully."])
                else
                    print(string.format(L["|cffff4444[UnbunkUtility]|r Import failed: %s"], tostring(err)))
                end
            end
        end,
    })
    importBtn.frame:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 0, -50)

    AddModule(importFrame, 80)

    -- ── Reset profile ────────────────────────────────────────────────────────

    local resetFrame = CreateFrame("Frame", nil, content)
    resetFrame:SetHeight(50)

    local resetLbl = resetFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    resetLbl:SetPoint("TOPLEFT", resetFrame, "TOPLEFT", 0, 0)
    resetLbl:SetText(L["Reset current profile to defaults"])

    local resetBtn = ns.ui.CreateButton({
        parent  = resetFrame,
        label   = L["Reset"],
        width   = 70,
        height  = 22,
        onClick = function()
            local name = ns.profiles.GetCurrent()
            -- Resets EVERY module (including PlayerDeath) generically off
            -- ALL_SETTERS + the CfgInit hook registry, then snapshots + reloads.
            -- Replaces the old hand-maintained per-DB block that silently
            -- omitted any module not listed here.
            ns.profiles.ResetCurrent()
            print(string.format(L["|cffff4444[UnbunkUtility]|r Profile reset to defaults: %s"], name))
        end,
    })
    resetBtn.frame:SetPoint("TOPLEFT", resetFrame, "TOPLEFT", 0, -22)
    AddModule(resetFrame, 50)

    -- ── OnShow refresh ───────────────────────────────────────────────────────

    parent:HookScript("OnShow", function()
        currentLbl:SetText(string.format(L["Current profile: |cffffd700%s|r"], ns.profiles.GetCurrent()))
        profileDD.selectedText:SetText(ns.profiles.GetCurrent())
    end)
end

-- ── Registration ──────────────────────────────────────────────────────────────

local initP = CreateFrame("Frame")
initP:RegisterEvent("ADDON_LOADED")
initP:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Profiles"], nil, CreateProfilesPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
