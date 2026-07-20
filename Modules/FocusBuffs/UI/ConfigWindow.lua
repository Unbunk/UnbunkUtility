-- Modules/FocusBuffs/UI/ConfigWindow.lua
-- The owner-only "Focus Freezing" tab (under "Personal utilities", gated in Core.lua by debug-unlock
-- AND IsAccountOwner). Draws a big number above your Cooldown Manager buff icon showing a focus debuff's
-- stack count (secret-safe) — see ns.FocusBuffs.

local _, ns = ...
local L = ns.L
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local function FB() return ns.FocusBuffs end

local function CreateFocusFreezingPanel(parent)
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Focus Freezing"] },
        { type = "group", build = function()
            return {
                { type = "checkbox", label = L["Show focus freezing stacks"],
                  get = function() return FB() and FB().Enabled() end,
                  set = function(v) if FB() then FB().Set("enabled", v and true or false) end end },
                { type = "textinput", label = L["CDM buff to anchor above (spell ID)"], width = 200, numeric = true,
                  get = function() local f = FB(); return f and tostring(f.Get("spellID") or "") or "" end,
                  set = function(v) local n = tonumber(v); if n and FB() then FB().Set("spellID", n) end end },
                { type = "slider", label = L["Stack number size"], min = 1, max = 5, step = 0.1, decimals = 1, width = 240, editBox = true,
                  get = function() local f = FB(); return (f and f.Get("countScale")) or 2 end,
                  set = function(v) if FB() then FB().Set("countScale", v) end end },
                { type = "textEditor", label = L["Number style"],
                  showText = false, showSize = false, showFont = true, showColor = true, showOutline = true,
                  getFontKey  = function() local f = FB(); local k = f and f.Get("fontKey"); if k and k ~= "" then return k end return ns.GetAddonFontKey and ns.GetAddonFontKey() or nil end,
                  getFontPath = function() local f = FB(); local p = f and f.Get("fontPath"); return (p and p ~= "" and p) or nil end,
                  getColor    = function() local f = FB(); local c = (f and f.Get("color")) or { r = 0, g = 145/255, b = 1, a = 1 }; return { r = c.r, g = c.g, b = c.b, a = c.a } end,
                  getOutline  = function() local f = FB(); return (f and f.Get("outline")) or "THICKOUTLINE" end,
                  onFontChange = function(key, path) local f = FB(); if not f then return end local c = f.Cfg(); if c then c.fontKey = key or ""; c.fontPath = path or "" end f.Apply() end,
                  onColorChange = function(r, g, b, a) local f = FB(); if f then f.Set("color", { r = r, g = g, b = b, a = a }) end end,
                  onOutlineChange = function(v) local f = FB(); if f then f.Set("outline", v or "") end end },
                { type = "textinput", label = L["Minimum stacks to show"], width = 160, numeric = true,
                  get = function() local f = FB(); return f and tostring(f.Get("minCount") or 1) or "1" end,
                  set = function(v) local n = tonumber(v); if n and FB() then FB().Set("minCount", math.max(1, math.floor(n))) end end },
                { type = "group", title = L["Position"],
                  -- Auto-follow ON ⇒ the number tracks the CDM buff icon, so the manual anchor buttons are
                  -- greyed. The gate greys the box's controls except its master checkbox when enabled()=false.
                  gate = { enabled = function() return not (FB() and FB().Get("autoFollow") == true) end, master = "autoFollow" },
                  build = function()
                      return {
                          { type = "checkbox", label = L["Try to follow the CDM buff icon automatically"], ref = "autoFollow",
                            get = function() return FB() and FB().Get("autoFollow") == true end,
                            set = function(v) if FB() then FB().Set("autoFollow", v and true or false) end end },
                          { type = "custom", build = function(host)
                              local unlock = ns.ui.CreateButton({ parent = host, height = 22, width = 245,
                                  label = L["Unlock anchor (drag to position)"],
                                  onClick = function() if FB() then FB().SetUnlocked(not FB().IsUnlocked()) end end })
                              unlock.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                              local reset = ns.ui.CreateButton({ parent = host, height = 22, width = 180,
                                  label = L["Reset anchor position"],
                                  onClick = function() if FB() then FB().ResetPos() end end })
                              reset.frame:SetPoint("LEFT", unlock.frame, "RIGHT", 8, 0)
                              host:SetHeight(26)
                              return { frame = host, height = 26 }
                          end },
                      }
                  end },
            }
        end },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Focus Freezing"], nil, CreateFocusFreezingPanel)
end)
