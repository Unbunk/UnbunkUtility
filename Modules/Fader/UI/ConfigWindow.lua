-- Modules/Fader/UI/ConfigWindow.lua
-- Extra Utilities -> Fading: two sub-tabs (Cooldown Manager + Player frame), one cadre each, with sub-cadres
-- for reveal conditions and the "Active in" instance filter. The player cadre also holds the "Link" toggle.
-- Backed by ns.db.profile.fader (per-profile) via ns.Fader.

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

-- The CDM hover-reveal categories, each shown as a COLLAPSIBLE cadre (header checkbox = the whole category,
-- per-group checkboxes inside). "resources" (Class resources) is a hover trigger only. Order = the user's.
local CDM_CATS = {
    { comp = "essentials",  label = L["Essential"]       },
    { comp = "utility",     label = L["Utility"]         },
    { comp = "belowPlayer", label = L["Below player"]    },
    { comp = "buffs",       label = L["Buffs"]           },
    { comp = "bars",        label = L["Bars"]            },
    { comp = "resources",   label = L["Class resources"] },
}

-- One collapsible cadre for a hover category: a header checkbox (the category enable — greys the body when off),
-- collapsed by default, refolded on tab re-entry (the panel's OnShow wipes collapsedState + rebuilds). Body =
-- one checkbox per GROUP of the category (ns.Fader.HoverGroups); onCheck re-applies the fade driver.
-- "hover" and "fade" share the same per-category / per-group cadre structure; only the config store and the
-- side-effect on change differ (hover -> restart driver; fade -> restore then re-fade the selected).
local SECTION_KIND = {
    hover = { catStore = "hover", groupStore = "hoverGroups",
              apply = function() if ns.Fader and ns.Fader.Apply then ns.Fader.Apply() end end },
    fade  = { catStore = "fade",  groupStore = "fadeGroups",
              apply = function() if ns.Fader and ns.Fader.RefreshFadeScope then ns.Fader.RefreshFadeScope() end end },
}
-- One collapsible cadre for a category (kind = "hover" | "fade"): header checkbox = the category flag (greys the
-- body when off), one checkbox per GROUP inside. Collapsed by default; onCollapse re-flows the parent cadres.
local function CategorySection(cat, kind, collapsedState, rebuild)
    local k = SECTION_KIND[kind]
    local ckey = kind .. ":" .. cat.comp   -- unique collapse-state key per (kind, category)
    return {
        type = "section", label = cat.label, heading = "UnbunkUtilityH4",
        showCheckbox = true,
        isChecked = function() return ns.Fader.GetCatFlag(k.catStore, cat.comp) end,
        onCheck   = function(v) ns.Fader.SetCatFlag(k.catStore, cat.comp, v); k.apply() end,
        getCollapsed = function() return collapsedState[ckey] ~= false end,   -- default collapsed (nil -> true)
        onCollapse   = function(state)
            collapsedState[ckey] = state and true or false
            if rebuild then rebuild() end   -- re-flow the parent cadres to fit (rebuild is coalesced + deferred)
        end,
        build = function()
            local rows = {}
            local groups = (ns.Fader and ns.Fader.HoverGroups and ns.Fader.HoverGroups(cat.comp)) or {}
            if #groups == 0 then
                rows[#rows + 1] = { type = "label", font = "UnbunkUtilityH6", height = 18, text = L["No groups"] }
            else
                for _, grp in ipairs(groups) do
                    local gkey = grp.key
                    rows[#rows + 1] = { type = "checkbox", label = grp.label,
                        get = function() return ns.Fader.GetGroupFlag(k.groupStore, cat.comp, gkey) end,
                        set = function(v) ns.Fader.SetGroupFlag(k.groupStore, cat.comp, gkey, v); k.apply() end }
                end
            end
            return rows
        end,
    }
end

-- The "Hovering with mouse" cadre (CDM only): the hover-reveal master checkbox + one per-category sub-cadre with
-- per-group checkboxes. Lives at the BOTTOM of the "Reveal when" group. Collapsed by default; refolds on tab switch.
local function HoveringSection(cs, rebuild)
    return {
        type = "section", label = L["Hovering with mouse"], heading = "UnbunkUtilityH4",
        showCheckbox = true,   -- master: enable/disable the whole hover-reveal (greys the body when off)
        isChecked = function() local c = ns.Fader.GroupCfg and ns.Fader.GroupCfg("cdm"); return not (c and c.hoverEnabled == false) end,
        onCheck   = function(v)
            local c = ns.Fader.GroupCfg and ns.Fader.GroupCfg("cdm")
            if c then c.hoverEnabled = v and true or false end
            if ns.Fader.Apply then ns.Fader.Apply() end
        end,
        getCollapsed = function() return cs["hover"] ~= false end,
        onCollapse   = function(state) cs["hover"] = state and true or false; if rebuild then rebuild() end end,
        build = function()
            local rows = {}
            for _, cat in ipairs(CDM_CATS) do rows[#rows + 1] = CategorySection(cat, "hover", cs, rebuild) end
            return rows
        end,
    }
end

local function FaderGroup(key, title, refresh, collapsedState, rebuild)
    local isCDM = (key == "cdm")
    local master = "faderEnable_" .. key   -- Enable-fade checkbox ref; the gate greys the WHOLE tab when it's off
    return {
        type = "group", title = title,
        -- Grey (dim + mouse-block) everything in this tab EXCEPT the Enable-fade checkbox while the fade is off.
        gate = { enabled = function() local c = gcfg(key); return c and c.enabled end, master = master },
        build = function()
            local cs = collapsedState or {}   -- CDM sub-cadre collapse states; used by "Reveal when" (hover) + "Fade applies to"
            local entries = {
                { type = "checkbox", ref = master, label = L["Enable fade"],
                  get = function() local c = gcfg(key); return c and c.enabled end,
                  set = function(v) setEnabled(key, v); if refresh then refresh() end end },   -- master onClick re-applies the gate

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
                { type = "group", title = L["Reveal when"], build = function()
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
                    else                -- CDM: the collapsible per-category "Hovering with mouse" cadre, at the BOTTOM
                        rev[#rev + 1] = HoveringSection(cs, rebuild)
                    end
                    return rev
                end },
            }

            -- Player cadre only: the "Link CDM and player frame fading" toggle sits right UNDER Enable fade,
            -- greyed while this frame's own fade is off (linking is meaningless with no fade).
            if not isCDM then
                table.insert(entries, 2, { type = "checkbox", label = L["Link CDM and player frame fading"],
                  disabled = function() local c = gcfg(key); return not (c and c.enabled) end,
                  get = function() local c = ns.Fader and ns.Fader.Cfg and ns.Fader.Cfg(); return c and c.link end,
                  set = function(v)
                      local c = ns.Fader and ns.Fader.Cfg and ns.Fader.Cfg()
                      if c then c.link = v and true or false end
                      if ns.Fader and ns.Fader.Apply then ns.Fader.Apply() end
                  end })
            end

            -- CDM only: "Fade applies to" (which CDM parts fade) sits ABOVE the reveal conditions — table.insert
            -- before the LAST current entry, the "Reveal when" group. (The hover cadre now lives INSIDE "Reveal
            -- when", added by that group's own build via HoveringSection.)
            if isCDM then
                table.insert(entries, #entries, {
                    type = "section", label = L["Fade applies to"], heading = "UnbunkUtilityH4",
                    showCheckbox = false,   -- no master toggle: the per-category / per-group checkboxes ARE the scope
                    getCollapsed = function() return cs["fade"] ~= false end,
                    onCollapse   = function(state) cs["fade"] = state and true or false; if rebuild then rebuild() end end,
                    build = function()
                        local rows = {}
                        for _, cat in ipairs(CDM_CATS) do rows[#rows + 1] = CategorySection(cat, "fade", cs, rebuild) end
                        return rows
                    end,
                })
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

-- Two tabs under Extra Utilities -> Fading: one cadre each. The "Link" toggle lives INSIDE the player cadre
-- (under Enable fade); each panel forward-declares its menu so Enable fade's set can re-grey that toggle live.
local function CreateCDMFadingPanel(parent)
    local menu
    local collapsedState = {}   -- [category] = collapsed bool; wiped (all refolded) each time the tab is (re)shown
    local rebuildPending = false
    -- Coalesced + deferred full rebuild: re-flows every cadre to fit (BuildMenu group boxes don't auto-resize on
    -- a nested section collapse) without tearing a section down mid-click, and folds rapid clicks into one build.
    local function rebuild()
        if rebuildPending then return end
        rebuildPending = true
        C_Timer.After(0, function() rebuildPending = false; if menu then menu.Rebuild() end end)
    end
    parent:HookScript("OnShow", function()
        if next(collapsedState) then   -- a cadre was touched -> refold + re-flow on re-entering the tab
            wipe(collapsedState)
            rebuild()
        end
    end)
    local options = { FaderGroup("cdm", L["Cooldown Manager"],
        function() if menu then menu.Refresh() end end, collapsedState, rebuild) }
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

local function CreatePlayerFadingPanel(parent)
    local menu
    local options = { FaderGroup("player", L["Player frame"], function() if menu then menu.Refresh() end end) }
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Cooldown Manager"], nil, CreateCDMFadingPanel)
    UnbunkUtility.RegisterModule(L["Player frame"],     nil, CreatePlayerFadingPanel)
end)
