-- Modules/DisableKeybinds/UI/ConfigWindow.lua
-- The owner-only "Disable keybinds" tab (under the "Personal utilities" sub-category,
-- gated in Core.lua by debug-unlock AND IsAccountOwner). It drives ns.DisableKeybinds:
-- a module-wide Enable plus a dynamic list of profile cadres. Each profile cadre has its
-- own Enable, a "Conditions" cadre holding three sub-cadres ("Instance type", "Group
-- type", "Combat state"), an "Add keybind" button (captures the next key chord) and the
-- list of captured chords — each removable or re-bindable.

local _, ns = ...
local L = ns.L

local function dcfg() return ns.DisableKeybinds and ns.DisableKeybinds.Cfg() end
local function touch() if ns.DisableKeybinds and ns.DisableKeybinds.Apply then ns.DisableKeybinds.Apply() end end

-- Pure-modifier keys are ignored during capture so the chord waits for a real key.
local MOD_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

-- Build a binding string from a base key + the live modifier state, in WoW's canonical
-- ALT-CTRL-SHIFT order (so it matches GetBindingKey / SetOverrideBindingClick).
local function BuildChord(key)
    local prefix = (IsAltKeyDown()     and "ALT-"   or "")
                .. (IsControlKeyDown() and "CTRL-"  or "")
                .. (IsShiftKeyDown()   and "SHIFT-" or "")
    return prefix .. key
end

-- Human-readable label for a stored chord (localised key names when available).
local function DisplayChord(chord)
    if GetBindingText then
        local t = GetBindingText(chord)
        if t and t ~= "" then return t end
    end
    return chord
end

-- ── Key-capture overlay ────────────────────────────────────────────────────────
-- A small modal that grabs the keyboard and reports the next non-modifier chord to its
-- callback. Every key is swallowed (SetPropagateKeyboardInput(false)) so the key being
-- bound doesn't ALSO fire its game action while capturing; Escape cancels.
local captureFrame
local function CaptureChord(onCapture)
    if not captureFrame then
        local f = CreateFrame("Frame", "UnbunkDisableKeybindCapture", UIParent, "BackdropTemplate")
        f:SetSize(380, 110)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile   = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
        f:Hide()

        local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
        title:SetPoint("TOP", f, "TOP", 0, -18)
        title:SetText(L["Press a key to disable"])

        local hint = f:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -10)
        hint:SetWidth(340); hint:SetJustifyH("CENTER"); hint:SetTextColor(0.6, 0.6, 0.6)
        hint:SetText(L["Press a key combination, or Escape to cancel."])

        f:EnableKeyboard(true)
        f:SetScript("OnKeyDown", function(self, key)
            self:SetPropagateKeyboardInput(false)   -- swallow everything while capturing
            if MOD_KEYS[key] then return end         -- wait for a real key
            local cb = self.cb
            self:Hide()
            if key ~= "ESCAPE" and cb then cb(BuildChord(key)) end
        end)
        f:SetScript("OnHide", function(self) self.cb = nil end)
        captureFrame = f
    end
    captureFrame.cb = onCapture
    captureFrame:SetBackdropBorderColor(ns.GetBrandColor())
    captureFrame:Show()
    captureFrame:Raise()
end

local function CreateDisableKeybindsPanel(parent)
    local menu                                   -- forward ref so closures can rebuild
    local function rebuild() if menu then menu.Rebuild() end end

    -- A delete cross at the top-right of a profile cadre's box (white, brand-tinted on
    -- hover), matching the Details! / custom-icon crosses. Confirms before removing.
    local function AttachDeleteX(boxFrame, p)
        if not boxFrame then return end
        local close = CreateFrame("Button", nil, boxFrame)
        close:SetSize(18, 18)
        close:SetFrameLevel(boxFrame:GetFrameLevel() + 10)
        close:SetPoint("TOPRIGHT", boxFrame, "TOPRIGHT", -4, -4)
        local bg = close:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(close); bg:SetColorTexture(0, 0, 0, 0.5)
        local x = close:CreateTexture(nil, "OVERLAY")
        x:SetSize(10, 10); x:SetPoint("CENTER"); x:SetTexture(UNBUNK_ICON_CROSS_WHITE)
        close:SetScript("OnEnter", function() x:SetVertexColor(ns.GetBrandColor()) end)
        close:SetScript("OnLeave", function() x:SetVertexColor(1, 1, 1) end)
        close:SetScript("OnClick", function()
            ns.ui.ShowConfirm({
                title    = L["Delete profile"],
                text     = L["Delete this keybind profile?"],
                name     = L["Profile"],
                onAccept = function()
                    if ns.DisableKeybinds and ns.DisableKeybinds.RemoveProfile then
                        ns.DisableKeybinds.RemoveProfile(p)
                    end
                    rebuild()
                end,
            })
        end)
    end

    -- A condition checkbox bound to boolean field `key` on table `t`.
    local function CondCheckbox(label, t, key)
        return { type = "checkbox", label = label,
            get = function() return t[key] == true end,
            set = function(v) t[key] = v and true or false; touch() end }
    end

    -- "Instance type" / "Group type" / "Combat state" sub-cadre.
    local function InstanceCadre(p)
        local ins = p.instance
        return { type = "group", title = L["Instance type"], build = function()
            return {
                CondCheckbox(L["Dungeon"],      ins, "dungeon"),
                CondCheckbox(L["Raid"],         ins, "raid"),
                CondCheckbox(L["Battleground"], ins, "battleground"),
                CondCheckbox(L["Outdoor"],      ins, "outdoor"),
            }
        end }
    end
    local function GroupCadre(p)
        local g = p.group
        return { type = "group", title = L["Group type"], build = function()
            return {
                CondCheckbox(L["Group"],      g, "group"),
                CondCheckbox(L["Raid Group"], g, "raid"),
                CondCheckbox(L["Solo"],       g, "solo"),
            }
        end }
    end
    local function CombatCadre(p)
        local cmb = p.combat
        return { type = "group", title = L["Combat state"], build = function()
            return {
                CondCheckbox(L["In combat"],     cmb, "inCombat"),
                CondCheckbox(L["Out of combat"], cmb, "outOfCombat"),
            }
        end }
    end

    -- The captured-chord list: one row each of [chord text] [Modify] [X], self-sizing.
    -- Modify re-captures into the same slot; X removes it. Empty -> a grey placeholder.
    local ROW_H = 26
    local function KeyListEntry(p)
        return { type = "custom", build = function(host)
            local keys = p.keys or {}
            if #keys == 0 then
                local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                fs:SetTextColor(0.6, 0.6, 0.6)
                fs:SetText(L["No keybinds added yet."])
                host:SetHeight(18)
                return { frame = host, height = 18 }
            end
            local y = 0
            for i = 1, #keys do
                local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                fs:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -y - 4)
                fs:SetWidth(170); fs:SetJustifyH("LEFT")
                fs:SetText(DisplayChord(keys[i]))

                local mod = ns.ui.CreateButton({
                    parent = host, label = L["Modify"], width = 80, height = 22,
                    onClick = function()
                        CaptureChord(function(chord) keys[i] = chord; touch(); rebuild() end)
                    end,
                })
                mod.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 184, -y)

                local del = ns.ui.CreateButton({
                    parent = host, label = "X", width = 24, height = 22,
                    onClick = function() table.remove(keys, i); touch(); rebuild() end,
                })
                del.frame:SetPoint("LEFT", mod.frame, "RIGHT", 8, 0)
                y = y + ROW_H
            end
            host:SetHeight(math.max(1, y))
            return { frame = host, height = math.max(1, y) }
        end }
    end

    -- One profile entry cadre: a delete X, the per-profile Enable, the "Conditions"
    -- cadre (three sub-cadres), then "Add keybind" + the captured-chord list.
    local function ProfileCadre(p, idx)
        return { type = "group", title = L["Profile"] .. " " .. idx,
            onBuilt = function(widget) AttachDeleteX(widget and widget.frame, p) end,
            build = function()
                return {
                    { type = "checkbox", label = L["Enable"],
                      get = function() return p.enabled ~= false end,
                      set = function(v) p.enabled = v and true or false; touch() end },
                    { type = "group", title = L["Conditions"], build = function()
                        return { InstanceCadre(p), GroupCadre(p), CombatCadre(p) }
                    end },
                    { type = "button", label = L["Add keybind"], width = 160, hostHeight = 30,
                      onClick = function()
                          CaptureChord(function(chord)
                              p.keys = p.keys or {}
                              p.keys[#p.keys + 1] = chord
                              touch(); rebuild()
                          end)
                      end },
                    KeyListEntry(p),
                }
            end }
    end

    -- The dynamic body: a description, the module Enable, every profile cadre, then the
    -- "Create profile" button. Returned by the group's build so Rebuild regenerates it.
    local function BuildBody()
        local entries = {
            { type = "custom", build = function(host)
                local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                fs:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
                fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetTextColor(0.6, 0.6, 0.6)
                fs:SetText(L["Create profiles that disable the chosen keybinds based on the instance, group and combat state you are in."])
                local h = math.max(16, math.ceil((fs:GetStringHeight() or 14) + 4))
                host:SetHeight(h)
                return { frame = host, height = h }
            end },
            { type = "checkbox", label = L["Enable"],
              get = function() local c = dcfg(); return c and c.enabled end,
              set = function(v) local c = dcfg(); if c then c.enabled = v and true or false end; touch() end },
        }

        local c = dcfg()
        if c and c.profiles then
            for i, p in ipairs(c.profiles) do
                entries[#entries + 1] = ProfileCadre(p, i)
            end
        end

        entries[#entries + 1] = { type = "button", label = L["Create profile"], width = 160, hostHeight = 30,
            onClick = function()
                if ns.DisableKeybinds and ns.DisableKeybinds.NewProfile then ns.DisableKeybinds.NewProfile() end
                rebuild()
            end }
        return entries
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Disable keybinds"] },
        { type = "group", build = BuildBody },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Disable keybinds"], nil, CreateDisableKeybindsPanel)
end)
