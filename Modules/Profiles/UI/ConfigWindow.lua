-- Modules/Profiles/UI/ConfigWindow.lua
-- Profile management tab (extracted from General Settings). Wraps the
-- ns.profiles.* API (defined in Core/Profiles.lua) with a UI.
--
-- Migrated to ns.ui.BuildMenu: the simple labels/dropdowns/inputs/buttons are
-- declarative entries; the cross-widget syncing (current-profile label + the two
-- dropdown toggle labels) is preserved verbatim via captured upvalues. The
-- export/import boxes are ns.ui.CreateTextInput fields (maxLetters = 0 so the
-- blob isn't truncated) the user copies from / pastes into, kept inside "custom"
-- blocks so the AceSerializer round-trip is untouched.

local _, ns = ...
local L = ns.L

local function CreateProfilesPanel(parent)
    -- Captured widgets the cross-block callbacks need to keep in sync. These are
    -- filled in by onBuilt / custom-build closures as BuildMenu walks the list.
    local currentLbl   -- FontString: "Current profile: <name>"
    local profileDD    -- Switch-profile dropdown (need .selectedText)
    local deleteDD     -- Delete dropdown (need .selectedText + .toggleBtn)

    local function SetCurrentText(name)
        if currentLbl then
            currentLbl:SetText(string.format(L["Current profile: |cff338cff%s|r"], name))
        end
    end

    local options = {
        -- ── Title ─────────────────────────────────────────────────────────────
        {
            type   = "label",
            font   = "UnbunkUtilityH2",
            height = 20,
            text   = L["Profile Management"],
        },

        -- ── Current profile (custom: captured FontString + OnShow re-sync) ────
        {
            type   = "custom",
            height = 24,
            build  = function(host)
                local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                lbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                lbl:SetText(string.format(L["Current profile: |cff338cff%s|r"], ns.profiles.GetCurrent()))
                currentLbl = lbl
                return {
                    frame   = host,
                    height  = 24,
                    Refresh = function()
                        lbl:SetText(string.format(L["Current profile: |cff338cff%s|r"], ns.profiles.GetCurrent()))
                    end,
                }
            end,
        },

        -- ── Switch profile dropdown ───────────────────────────────────────────
        {
            type          = "dropdown",
            height        = 50,
            label         = L["Switch profile"],
            font          = "UnbunkUtilityH4",  -- match sibling labels (Create/Delete/…)
            labelGap      = 20,                -- original anchored the box to a -20 spacer
            width         = 200,
            itemHeight    = 20,
            visibleItems  = 8,
            getList       = function() return ns.profiles.GetList() end,
            getCurrentKey = function() return ns.profiles.GetCurrent() end,
            onSelect      = function(name)
                if name == ns.profiles.GetCurrent() then return end
                -- AceDB writes live, so there is no snapshot step before switching;
                -- Load() switches the profile and re-applies every module.
                ns.profiles.Load(name)
                SetCurrentText(name)
                ns.Print(string.format(L["Profile loaded: %s"], name))
            end,
            onBuilt       = function(w)
                profileDD = w
                profileDD.selectedText:SetText(ns.profiles.GetCurrent())
            end,
        },

        -- ── Create profile (label + input + Create button) ────────────────────
        {
            type   = "custom",
            height = 50,
            build  = function(host)
                local createLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                createLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                createLbl:SetText(L["Create new profile"])

                local createInput = ns.ui.CreateTextInput({
                    parent     = host,
                    width      = 200,
                    height     = 22,
                    maxLetters = 32,
                    text       = "",
                })
                createInput.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -22)

                local createBtn = ns.ui.CreateButton({
                    parent  = host,
                    label   = L["Create"],
                    width   = 70,
                    height  = 22,
                    onClick = function()
                        local name = createInput.GetText()
                        if name and name ~= "" then
                            if ns.profiles.Create(name) then
                                if profileDD then profileDD.selectedText:SetText(name) end
                                SetCurrentText(name)
                                createInput.SetText("")
                                ns.Print(string.format(L["Profile created: %s"], name))
                            else
                                ns.Print(string.format(L["Profile already exists: %s"], name))
                            end
                        end
                    end,
                })
                createBtn.frame:SetPoint("LEFT", createInput.frame, "RIGHT", 8, 0)

                return { frame = host, height = 50 }
            end,
        },

        -- ── Delete profile (label + dropdown + Delete button) ─────────────────
        {
            type   = "custom",
            height = 50,
            build  = function(host)
                local deleteLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                deleteLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                deleteLbl:SetText(L["Delete profile"])

                local deleteAnchor = host:CreateFontString(nil, "ARTWORK")
                deleteAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20)

                deleteDD = ns.ui.CreateDropdown({
                    parent        = host,
                    anchorFrame   = deleteAnchor,
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
                    parent  = host,
                    label   = L["Delete"],
                    width   = 70,
                    height  = 22,
                    onClick = function()
                        local name = deleteDD.selectedText:GetText()
                        if name and name ~= "" and name ~= "Default" then
                            if ns.profiles.Delete(name) then
                                deleteDD.selectedText:SetText("")
                                SetCurrentText(ns.profiles.GetCurrent())
                                if profileDD then profileDD.selectedText:SetText(ns.profiles.GetCurrent()) end
                                ns.Print(string.format(L["Profile deleted: %s"], name))
                            end
                        end
                    end,
                })
                deleteBtn.frame:SetPoint("LEFT", deleteDD.toggleBtn, "RIGHT", 8, 0)

                return { frame = host, height = 50 }
            end,
        },

        -- ── Export (label + EditBox + Export button) ──────────────────────────
        {
            type   = "custom",
            height = 80,
            build  = function(host)
                local exportLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                exportLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                exportLbl:SetText(L["Export current profile"])

                local exportInput = ns.ui.CreateTextInput({
                    parent = host, width = 400, height = 22, maxLetters = 0,
                })
                exportInput.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -22)
                local exportBox = exportInput.editBox

                -- Read-only: the box only displays the exported blob for copying, so
                -- reject any typing/pasting by snapping back to the exported string
                -- (it stays selectable for Ctrl+C).
                local exportValue = ""
                exportBox:SetScript("OnTextChanged", function(self)
                    if self:GetText() ~= exportValue then
                        self:SetText(exportValue)
                        self:HighlightText()
                    end
                end)

                local exportBtn = ns.ui.CreateButton({
                    parent  = host,
                    label   = L["Export"],
                    width   = 70,
                    height  = 22,
                    onClick = function()
                        exportValue = ns.profiles.Export()
                        exportBox:SetText(exportValue)
                        exportBox:SetFocus()
                        exportBox:HighlightText()   -- select all; the user copies with Ctrl+C
                    end,
                })
                exportBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -50)

                return { frame = host, height = 80 }
            end,
        },

        -- ── Import (label + EditBox + Import button) ──────────────────────────
        {
            type   = "custom",
            height = 80,
            build  = function(host)
                local importLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                importLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                importLbl:SetText(L["Import profile (creates a new profile)"])

                local importInput = ns.ui.CreateTextInput({
                    parent = host, width = 400, height = 22, maxLetters = 0,
                })
                importInput.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -22)
                local importBox = importInput.editBox

                local importBtn = ns.ui.CreateButton({
                    parent  = host,
                    label   = L["Import"],
                    width   = 70,
                    height  = 22,
                    onClick = function()
                        local str = importBox:GetText()
                        if not str or str:gsub("%s", "") == "" then return end
                        -- Prompt for a name and import INTO A NEW profile instead of
                        -- overwriting the current one. ImportAs validates the blob +
                        -- name, creates the profile and switches to it (then ReloadAll
                        -- rebuilds this panel, so the current-profile label updates).
                        ns.ui.ShowPrompt({
                            title      = L["Import profile"],
                            text       = L["Name the new profile:"],
                            acceptText = L["Import"],
                            maxLetters = 32,
                            onAccept   = function(name)
                                name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
                                if name == "" then return end
                                local ok, err = ns.profiles.ImportAs(name, str)
                                if ok then
                                    ns.Print(string.format(L["Profile imported as: %s"], name))
                                else
                                    ns.Print(string.format(L["Import failed: %s"], tostring(err)))
                                end
                            end,
                        })
                    end,
                })
                importBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -50)

                return { frame = host, height = 80 }
            end,
        },

        -- ── Reset profile (label + Reset button) ──────────────────────────────
        {
            type   = "custom",
            height = 50,
            build  = function(host)
                local resetLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                resetLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                resetLbl:SetText(L["Reset current profile to defaults"])

                local resetBtn = ns.ui.CreateButton({
                    parent  = host,
                    label   = L["Reset"],
                    width   = 70,
                    height  = 22,
                    onClick = function()
                        local name = ns.profiles.GetCurrent()
                        -- Resets the active profile to defaults via ns.db:ResetProfile,
                        -- which fires OnProfileReset -> every module's CfgInit hook re-merges
                        -- its DEFAULTS, then the panel rebuilds. No module can be missed.
                        ns.profiles.ResetCurrent()
                        ns.Print(string.format(L["Profile reset to defaults: %s"], name))
                    end,
                })
                resetBtn.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -22)

                return { frame = host, height = 50 }
            end,
        },
    }

    -- gap=12, width=518, autoHook=true. The OnShow re-sync runs every registered
    -- Refresh: the current-profile custom block re-reads GetCurrent(), and the
    -- switch dropdown's auto-refresher (getCurrentKey -> SetCurrent) re-syncs its
    -- toggle label — together they reproduce the old hand-written HookScript.
    local menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

-- ── Registration ──────────────────────────────────────────────────────────────

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Profiles"], nil, CreateProfilesPanel)
end)
