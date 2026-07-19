-- Modules/ImportKeybinds/UI/ConfigWindow.lua
-- The owner-only "Import keybinds" tab (Personal utilities; gated in Core.lua by debug-unlock
-- AND IsAccountOwner). Capture the current character's action-bar contents into one account-
-- wide template, then apply it to a fresh character with one click. Drives ns.ImportKeybinds.

local _, ns = ...
local L = ns.L

local function IK() return ns.ImportKeybinds end

-- Class-coloured character name for the status line (falls back to plain text).
local function ClassColored(name, class)
    if not name then return "?" end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) end
    return name
end

-- Map an action slot <-> (bar, position). BAR_BASES lists the first slot of each bar across 1-180
-- (every 12 slots); each bar covers 12 positions. Bars 11-12 (slots 121-144) include the bonus /
-- mounted-override bar. The bar numbers are native (not the user's Dominos numbering, which uses
-- custom paging we can't read).
local BAR_BASES = { 1, 13, 25, 37, 49, 61, 73, 85, 97, 109, 121, 133, 145, 157, 169 }
local NUM_BARS  = #BAR_BASES
local function BarPosOf(slot)
    for i = 1, NUM_BARS do
        local base = BAR_BASES[i]
        if slot >= base and slot <= base + 11 then return i, slot - base + 1 end
    end
    return 1, 1
end
local function SlotFromBarPos(bar, pos)
    local base = BAR_BASES[bar] or 1
    return base + (pos - 1)
end
local function BarLabel(b)  return (L["Bar"]  or "Bar")  .. " " .. b end
local function SlotLabel(p) return (L["Slot"] or "Slot") .. " " .. p end

local function CreateImportKeybindsPanel(parent)
    local menu
    local function rebuild() if menu then menu.Rebuild() end end

    -- Grey wrapped description line.
    -- Current template status (who it was captured on + slot count, or an orange "none yet").
    local function StatusLine()
        return { type = "custom", build = function(host)
            local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            fs:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
            fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
            local info = IK() and IK().TemplateInfo()
            if info then
                fs:SetTextColor(0.75, 0.75, 0.75)
                fs:SetText(string.format(L["Template: %s — %d slots saved."],
                    ClassColored(info.char or "?", info.class), info.count or 0))
            else
                fs:SetTextColor(1, 0.5, 0.2)
                fs:SetText(L["No template captured yet — capture your main character's bars first."])
            end
            local h = math.max(16, math.ceil((fs:GetStringHeight() or 14) + 4))
            host:SetHeight(h)
            return { frame = host, height = h }
        end }
    end

    local function doCapture()
        local ok, a = IK().Capture()
        if ok then
            ns.Print(string.format(L["Captured %d action-bar slots into the template."], a or 0))
            rebuild()
        elseif a == "combat" then ns.Print(L["Can't do that in combat."])
        else ns.Print(L["Capture failed."]) end
    end

    local function doImport()
        local ok, a, b = IK().Import()
        if ok then
            ns.Print(string.format(L["Imported: %d placed, %d skipped (unknown spell / missing macro)."], a or 0, b or 0))
        elseif a == "combat" then ns.Print(L["Can't do that in combat."])
        elseif a == "empty"  then ns.Print(L["No template captured yet — capture your main character's bars first."])
        else ns.Print(L["Import failed."]) end
    end

    -- One slot row: [checkbox] [icon] [name] [bar v] [slot v]. A real Texture renders the icon
    -- reliably (an inline |T fileID |t escape in a checkbox label did not show). Checked = include on
    -- import; the two dropdowns REMAP the destination (which bar / which position) by mutating e.slot.
    local ROW_H = 26
    local function SlotRow(e)
        return { type = "custom", height = ROW_H, build = function(host)
            host:SetHeight(ROW_H)
            local cb = ns.ui.CreateCheckbox({
                parent  = host,
                label   = "",
                checked = e.enabled ~= false,
                onClick = function(v) e.enabled = v and true or false end,
            })
            cb.frame:SetPoint("LEFT", host, "LEFT", 0, 0)
            cb.frame:SetWidth(22)

            local icon = host:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", cb.frame, "RIGHT", 4, 0)
            if e.icon then
                icon:SetTexture(e.icon)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the default icon border
            else
                icon:SetColorTexture(0, 0, 0, 0.3)
            end

            -- Slot (position 1-12) dropdown, far right.
            local slotDD = ns.ui.CreateDropdown({
                parent = host, anchorFrame = host, width = 66, visibleItems = 12,
                getList       = function() local t = {}; for p = 1, 12 do t[p] = SlotLabel(p) end; return t end,
                getCurrentKey = function() local _, pos = BarPosOf(e.slot); return SlotLabel(pos) end,
                onSelect      = function(nameKey)
                    local p = tonumber(tostring(nameKey):match("%d+"))
                    if p then local bar = BarPosOf(e.slot); e.slot = SlotFromBarPos(bar, p) end
                end,
            })
            slotDD.toggleBtn:ClearAllPoints()
            slotDD.toggleBtn:SetPoint("RIGHT", host, "RIGHT", 0, 0)

            -- Bar dropdown, left of the slot dropdown.
            local barDD = ns.ui.CreateDropdown({
                parent = host, anchorFrame = host, width = 66, visibleItems = 13,
                getList       = function() local t = {}; for b = 1, NUM_BARS do t[b] = BarLabel(b) end; return t end,
                getCurrentKey = function() return BarLabel((BarPosOf(e.slot))) end,
                onSelect      = function(nameKey)
                    local b = tonumber(tostring(nameKey):match("%d+"))
                    if b then local _, pos = BarPosOf(e.slot); e.slot = SlotFromBarPos(b, pos) end
                end,
            })
            barDD.toggleBtn:ClearAllPoints()
            barDD.toggleBtn:SetPoint("RIGHT", slotDD.toggleBtn, "LEFT", -6, 0)

            local name = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetPoint("RIGHT", barDD.toggleBtn, "LEFT", -8, 0)
            name:SetJustifyH("LEFT"); name:SetWordWrap(false)
            name:SetText(e.name or ("[" .. tostring(e.kind or "?") .. "]"))

            return { frame = host, height = ROW_H, dropFrames = { barDD.dropFrame, slotDD.dropFrame } }
        end }
    end

    -- Collapsible "Edit template" list: one checkbox per captured slot (checked = include on
    -- import). Collapse state persists account-wide; toggling a box just flips e.enabled.
    local function EditTemplateSection()
        return { type = "section", label = L["Edit template"], heading = "UnbunkUtilityH4",
            showCheckbox = false,
            getCollapsed = function()
                local s = ns.db and ns.db.global and ns.db.global.importKeybinds
                return not (s and s.editExpanded)   -- default collapsed
            end,
            onCollapse = function(c)
                local s = ns.db and ns.db.global and ns.db.global.importKeybinds
                if s then s.editExpanded = not c end
                -- Rebuild (deferred) so the enclosing Template box re-measures around the section.
                if C_Timer and C_Timer.After then C_Timer.After(0, rebuild) else rebuild() end
            end,
            build = function()
                local s = ns.db and ns.db.global and ns.db.global.importKeybinds
                local rows = {
                    { type = "custom", build = function(host)
                        local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                        fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                        fs:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
                        fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetTextColor(0.6, 0.6, 0.6)
                        fs:SetText(L["Uncheck a slot to leave it out of the import."])
                        local h = math.max(16, math.ceil((fs:GetStringHeight() or 14) + 4))
                        host:SetHeight(h)
                        return { frame = host, height = h }
                    end },
                }
                -- Build the (potentially 100+) checkbox rows ONLY when expanded: CollapsibleSection
                -- calls this at construction regardless of collapse state, so gating on editExpanded
                -- avoids creating hundreds of hidden frames while the section is collapsed (default).
                -- Expanding flips editExpanded then rebuilds (onCollapse), which re-runs this with rows.
                if s and s.editExpanded then
                    for _, e in ipairs(s.template or {}) do
                        rows[#rows + 1] = SlotRow(e)
                    end
                end
                return rows
            end }
    end

    -- ── Key bindings (separate section) ────────────────────────────────────────
    local function doCaptureBindings()
        local ok, a = IK().CaptureBindings()
        if ok then ns.Print(string.format(L["Captured %d key bindings."], a or 0)); rebuild()
        elseif a == "combat" then ns.Print(L["Can't do that in combat."])
        else ns.Print(L["Capture failed."]) end
    end
    local function doImportBindings()
        local ok, a = IK().ImportBindings()
        if ok then ns.Print(string.format(L["Imported %d key bindings."], a or 0))
        elseif a == "combat" then ns.Print(L["Can't do that in combat."])
        elseif a == "empty"  then ns.Print(L["No key bindings captured yet."])
        else ns.Print(L["Import failed."]) end
    end

    -- Saved-key-bindings status line (count, or an orange "none yet").
    local function BindStatusLine()
        return { type = "custom", build = function(host)
            local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
            fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            fs:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
            fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
            local info = IK() and IK().BindingsInfo()
            if info then
                fs:SetTextColor(0.75, 0.75, 0.75)
                fs:SetText(string.format(L["%d key bindings saved."], info.count or 0))
            else
                fs:SetTextColor(1, 0.5, 0.2)
                fs:SetText(L["No key bindings captured yet."])
            end
            local h = math.max(16, math.ceil((fs:GetStringHeight() or 14) + 4))
            host:SetHeight(h)
            return { frame = host, height = h }
        end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Import keybinds"] },

        { type = "group", title = L["Action bars slots content"], build = function()
            return {
                { type = "group", title = L["Template"], build = function()
                    local items = {
                        StatusLine(),
                        { type = "button", label = L["Capture current bars"], width = 200, hostHeight = 30,
                          onClick = function()
                              if not (IK() and IK().Capture) then return end
                              if IK().HasTemplate() then
                                  ns.ui.ShowConfirm({
                                      title    = L["Replace template?"],
                                      text     = L["A template already exists. Replace it with this character's current bars?"],
                                      onAccept = doCapture,
                                  })
                              else
                                  doCapture()
                              end
                          end },
                    }
                    if IK() and IK().HasTemplate() then
                        items[#items + 1] = EditTemplateSection()
                    end
                    return items
                end },

                { type = "group", title = L["Apply to this character"], build = function()
                    return {
                        { type = "button", label = L["Import basic keybinds"], width = 200, hostHeight = 30,
                          onClick = function()
                              if not (IK() and IK().Import) then return end
                              if not IK().HasTemplate() then
                                  ns.Print(L["No template captured yet — capture your main character's bars first."])
                                  return
                              end
                              ns.ui.ShowConfirm({
                                  title    = L["Import keybinds"],
                                  text     = L["Place the saved bar template onto this character now?"],
                                  onAccept = doImport,
                              })
                          end },
                    }
                end },
            }
        end },

        { type = "group", title = L["Keybinds"], build = function()
            return {
                { type = "group", title = L["Capture"], build = function()
                    return {
                        BindStatusLine(),
                        { type = "button", label = L["Capture current keybinds"], width = 200, hostHeight = 30,
                          onClick = function()
                              if not (IK() and IK().CaptureBindings) then return end
                              if IK().HasBindings() then
                                  ns.ui.ShowConfirm({
                                      title    = L["Replace keybinds?"],
                                      text     = L["Key bindings already saved. Replace them with this character's current bindings?"],
                                      onAccept = doCaptureBindings,
                                  })
                              else
                                  doCaptureBindings()
                              end
                          end },
                    }
                end },

                { type = "group", title = L["Import"], build = function()
                    return {
                        { type = "button", label = L["Apply saved keybinds"], width = 200, hostHeight = 30,
                          onClick = function()
                              if not (IK() and IK().ImportBindings) then return end
                              if not IK().HasBindings() then
                                  ns.Print(L["No key bindings captured yet."])
                                  return
                              end
                              ns.ui.ShowConfirm({
                                  title    = L["Apply saved keybinds"],
                                  text     = L["Apply your saved key bindings to this character now?"],
                                  onAccept = doImportBindings,
                              })
                          end },
                    }
                end },
            }
        end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Import keybinds"], nil, CreateImportKeybindsPanel)
end)
