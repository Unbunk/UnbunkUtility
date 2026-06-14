-- Modules/Fader/UI/ConfigWindow.lua
-- BETA sub-tab: configure the customizable fade for the Cooldown Manager + Player Frame.
-- One cadre per group, each with two sub-cadres: reveal conditions and the "Active in"
-- instance filter. Backed by ns.db.profile.fader (per-profile) via ns.Fader.

local _, ns = ...
local L = ns.L

local function gcfg(key) return ns.Fader and ns.Fader.GroupCfg(key) end

-- enabled toggling starts/stops the fade driver (+ restores full alpha when off); the
-- other fields are picked up live by the running driver, so they need no explicit apply.
local function setEnabled(key, v)
    local c = gcfg(key); if c then c.enabled = v and true or false end
    if ns.Fader and ns.Fader.Apply then ns.Fader.Apply() end
end
local function setField(key, field, v)
    local c = gcfg(key); if c then c[field] = v end
end
local function getHover(key, comp)
    local c = gcfg(key); return c and c.hover and c.hover[comp]
end
local function setHover(key, comp, v)
    local c = gcfg(key)
    if c then c.hover = c.hover or {}; c.hover[comp] = v and true or false end
end

-- CDM sub-components offered as per-component hover-reveal toggles.
local CDM_HOVER = {
    { comp = "essentials",  label = L["Essentials"]   },
    { comp = "utility",     label = L["Utility"]      },
    { comp = "belowPlayer", label = L["Below player"] },
    { comp = "buffs",       label = L["Buffs"]        },
    { comp = "bars",        label = L["Bars"]         },
}

local function FaderGroup(key, title)
    local isCDM = (key == "cdm")
    return {
        type = "group", title = title, build = function()
            local entries = {
                { type = "checkbox", label = L["Enable fade"],
                  get = function() local c = gcfg(key); return c and c.enabled end,
                  set = function(v) setEnabled(key, v) end },

                -- Faded opacity: inline "label  [NN] %" row.
                { type = "custom", height = 26, build = function(host)
                    local function curPct()
                        local c = gcfg(key)
                        return c and math.floor((c.fadedAlpha or 0.3) * 100 + 0.5) or 30
                    end
                    local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                    lbl:SetPoint("LEFT", host, "LEFT", 0, 0)
                    lbl:SetText(L["Opacity when faded (%)"])
                    local inp = ns.ui.CreateTextInput({
                        parent = host, width = 50, height = 22, numeric = true, min = 0, max = 100, maxLetters = 3,
                        text = tostring(curPct()),
                        onEnter = function(v)
                            if v then setField(key, "fadedAlpha", math.max(0, math.min(100, v)) / 100) end
                        end,
                    })
                    inp.frame:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                    return { frame = host, height = 26, Refresh = function() inp.SetText(tostring(curPct())) end }
                end },

                -- Sub-cadre: reveal (un-fade) conditions (combat / target; mouseover for player).
                { type = "group", title = L["Reveal (show fully) when"], build = function()
                    local rev = {
                        { type = "checkbox", label = L["In combat"],
                          get = function() local c = gcfg(key); return c and c.revealCombat end,
                          set = function(v) setField(key, "revealCombat", v) end },
                        { type = "checkbox", label = L["A target is selected"],
                          get = function() local c = gcfg(key); return c and c.revealTarget end,
                          set = function(v) setField(key, "revealTarget", v) end },
                    }
                    if not isCDM then   -- the player frame is a single component
                        rev[#rev + 1] = { type = "checkbox", label = L["Hovering it with the mouse"],
                          get = function() return getHover(key, "player") end,
                          set = function(v) setHover(key, "player", v) end }
                    end
                    return rev
                end },
            }

            -- CDM only: a sub-cadre of per-component hover-reveal checkboxes.
            if isCDM then
                entries[#entries + 1] = { type = "group", title = L["Reveal on hover of"], build = function()
                    local hs = {}
                    for _, h in ipairs(CDM_HOVER) do
                        hs[#hs + 1] = { type = "checkbox", label = h.label,
                          get = function() return getHover(key, h.comp) end,
                          set = function(v) setHover(key, h.comp, v) end }
                    end
                    return hs
                end }
            end

            -- Sub-cadre: where the fade is active at all (instance filter).
            entries[#entries + 1] = { type = "group", title = L["Active in instances"], build = function() return {
                { type = "instanceFilter",
                  getConfig = function() local c = gcfg(key); return c and c.instanceFilter end,
                  setConfig = function(fk, fv)
                      local c = gcfg(key)
                      if c then c.instanceFilter = c.instanceFilter or {}; c.instanceFilter[fk] = fv end
                  end },
            } end }

            return entries
        end,
    }
end

local function CreateFaderPanel(parent)
    local options = {
        { type = "label", text = L["Beta"], font = "UnbunkUtilityH2", height = 28 },
        { type = "label", font = "UnbunkUtilityH6", height = 24,
          text = L["Experimental fade for the Cooldown Manager and Player Frame."] },
        FaderGroup("cdm",    L["Cooldown Manager"]),
        FaderGroup("player", L["Player frame"]),
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

-- Register the Beta sub-tab (the nav entry is gated by the debug unlock in Core.lua).
local initF = CreateFrame("Frame")
initF:RegisterEvent("ADDON_LOADED")
initF:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Beta"], nil, CreateFaderPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
