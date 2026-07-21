-- Modules/NewCharacter/UI/ConfigWindow.lua
-- The owner-only "New character" tab (Personal utilities; gated in Core.lua by debug-unlock AND
-- IsAccountOwner). A single "Configure new character" button that sets up a fresh character in one shot:
--   1) Clear all action bar slots        (ns.ImportKeybinds.ClearAll)
--   2) Import basic keybinds (bar template) (ns.ImportKeybinds.Import)
--   3) Select all addon profiles          (ns.AddonProfiles.SelectAll)
-- then offers a UI reload (Yes / Later). It only DRIVES actions the ImportKeybinds / AddonProfiles tabs
-- already own — no new capture/import logic lives here.

local _, ns = ...
local L = ns.L

local function CreateNewCharacterPanel(parent)
    -- Run the whole fresh-character setup in one shot. Every step is synchronous and out-of-combat only,
    -- so a single upfront combat guard covers them all; each sub-action still no-ops safely if its module
    -- isn't present. Behind a confirm because step 1 wipes ALL action bars irreversibly.
    local function configure()
        if InCombatLockdown() then ns.Print(L["Can't do that in combat."]); return end
        local IK = ns.ImportKeybinds

        -- Guard BEFORE wiping anything: with no saved bar template there is nothing to restore, so clearing
        -- every bar would just leave the character empty. Abort and tell the user to capture one first.
        if not (IK and IK.HasTemplate and IK.HasTemplate()) then
            ns.Print(L["No template captured yet — capture your main character's bars first."])
            return
        end

        -- 1) Clear all action bar slots.
        if IK.ClearAll then
            local ok, n = IK.ClearAll()
            if ok then ns.Print(string.format(L["Cleared %d action-bar slots."], n or 0)) end
        end

        -- 2) Import basic keybinds (the saved action-bar template) onto the now-empty bars.
        if IK.Import then
            local ok, placed, skipped = IK.Import()
            if ok then ns.Print(string.format(L["Imported: %d placed, %d skipped (unknown spell / missing macro)."], placed or 0, skipped or 0)) end
        end

        -- 3) Select all addon profiles (switch each detected addon to its saved profile when present).
        local AP = ns.AddonProfiles
        if AP and AP.SelectAll then
            local r = AP.SelectAll()
            ns.Print(string.format(L["Select all: %d switched, %d already active, %d skipped."], r.switched, r.already, r.skipped))
        end

        -- 4) Offer a reload (Yes / Later) — a reload cleanly settles the bar/keybind changes and the
        -- reload-based addon switches. Shown unconditionally: this is a full one-shot character setup.
        ns.ui.ShowConfirm({
            title      = L["Reload UI?"],
            text       = L["New character configured. Reload the UI now to fully apply everything?"],
            acceptText = L["Yes"],
            cancelText = L["Later"],
            onAccept   = function() ReloadUI() end,
        })
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["New character"] },
        { type = "group", title = L["New character"], build = function()
            return {
                { type = "button", label = L["Configure new character"], width = 220, hostHeight = 32,
                  onClick = function()
                      if InCombatLockdown() then ns.Print(L["Can't do that in combat."]); return end
                      ns.ui.ShowConfirm({
                          title    = L["Configure new character"],
                          text     = L["Clear ALL action bars, import your saved bar template, and activate every addon's saved profile on this character? (bars are wiped first — meant for a fresh character.)"],
                          onAccept = configure,
                      })
                  end },
            }
        end },
    }

    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["New character"], nil, CreateNewCharacterPanel)
end)
