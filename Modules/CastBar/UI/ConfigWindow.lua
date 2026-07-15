-- Modules/CastBar/UI/ConfigWindow.lua
-- "Cast bar" panel (top of Extra Utilities): enable, hide-Blizzard toggle, placement,
-- size, text style + colours for the custom player cast bar (ns.CastBar).

local _, ns = ...
local L  = ns.L
local CB = ns.CastBar

local function CreateCastBarPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu
    -- Whole panel greys out (every group except the Enable checkbox) when the cast bar is off.
    local function moduleOn() return CB.CfgGet("enabled") ~= false end

    local function colorGroupEntry(label, key)
        return { type = "textEditor", label = label,
            showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
            getColor = function() return CB.CfgGet(key) end,
            onColorChange = function(r, g, b, a) CB.CfgSet(key, { r = r, g = g, b = b, a = a }); CB.ApplyConfig() end }
    end

    local function sizeInput(label, key, mn, mx)
        return { type = "textinput", label = label, width = 60, numeric = true, min = mn, max = mx, maxLetters = 4,
            get = function() return CB.CfgGet(key) end,
            set = function(v) if v and v >= mn then CB.CfgSet(key, v); CB.ApplyConfig() end end }
    end

    -- A numeric x/y offset input (negatives allowed; 0 is valid).
    local function offsetInput(label, key)
        return { type = "textinput", label = label, width = 60, numeric = true, allowNegative = true,
            min = -1000, max = 1000, maxLetters = 5,
            get = function() return CB.CfgGet(key) end,
            set = function(v) CB.CfgSet(key, v or 0); CB.ApplyConfig() end }
    end

    -- A font / size / colour / outline editor bound to a key prefix ("name" | "timer").
    local function textStyleEntry(prefix)
        return { type = "textEditor", LSM = LSM, label = L["Text"],
            showLabel = false, showText = false, showFont = true, showSize = true, showColor = true, showOutline = true,
            getFontKey  = function() return CB.CfgGet(prefix .. "FontKey")  end,
            getFontPath = function() return CB.CfgGet(prefix .. "FontPath") end,
            getFontSize = function() return CB.CfgGet(prefix .. "FontSize") end,
            getColor    = function() return CB.CfgGet(prefix .. "Color")    end,
            getOutline  = function() return CB.CfgGet(prefix .. "Outline")  end,
            onFontChange    = function(key, path) CB.CfgSet(prefix .. "FontKey", key); CB.CfgSet(prefix .. "FontPath", path); CB.ApplyConfig() end,
            onSizeChange    = function(size)       CB.CfgSet(prefix .. "FontSize", size); CB.ApplyConfig() end,
            onColorChange   = function(r, g, b, a) CB.CfgSet(prefix .. "Color", { r = r, g = g, b = b, a = a }); CB.ApplyConfig() end,
            onOutlineChange = function(outline)    CB.CfgSet(prefix .. "Outline", outline); CB.ApplyConfig() end }
    end

    -- A CDM-destination dropdown (essential / utility / below player) for a config key.
    local function ResBarTargets() return (ns.ResourceBarAnchorTargets and ns.ResourceBarAnchorTargets()) or {} end
    local function cdmDestDropdown(label, key, onChange, whenFn)
        return { type = "dropdown", label = label, width = 220, height = 50, when = whenFn,
            -- Plain 3-way dest picker (no front/end split) + the class-resource bars (+ "Last bar"): the cast
            -- bar stores a raw cdmDest or "resbar:*" key, so map labels against both sets.
            getList = function()
                local t = ns.CDMDestKeyList()
                for _, tgt in ipairs(ResBarTargets()) do t[#t + 1] = tgt.label end
                return t
            end,
            getCurrentKey = function()
                local k = CB.CfgGet(key) or "essential"
                if ns.IsResourceBarAnchorKey and ns.IsResourceBarAnchorKey(k) then
                    for _, tgt in ipairs(ResBarTargets()) do if tgt.key == k then return tgt.label end end
                    return (ns.L and ns.L["Last bar"]) or k
                end
                return ns.CDMDestLabel(k)
            end,
            onSelect = function(lbl)
                local k
                for _, tgt in ipairs(ResBarTargets()) do if tgt.label == lbl then k = tgt.key break end end
                if not k and ns.CDM_DEST_ORDER then
                    for _, d in ipairs(ns.CDM_DEST_ORDER) do if ns.CDMDestLabel(d) == lbl then k = d break end end
                end
                -- No match -> KEEP the current value. CDMDestKeyFromLabel defaults to "essential", so a resbar
                -- label that missed above (target list momentarily empty) would otherwise silently reset the anchor.
                if not k then return end
                CB.CfgSet(key, k)
                if onChange then onChange() end
            end }
    end

    -- A statusbar-texture dropdown (LibSharedMedia) for a config key. Shows the EFFECTIVE key
    -- (the saved one if registered, else "Blizzard") so the label matches what's rendered.
    local function textureDropdown(label, key)
        return { type = "dropdown", label = label, width = 220, height = 50, searchable = true,
            getList       = function() return LSM and LSM:List("statusbar") or {} end,
            getCurrentKey = function() return CB.EffectiveTexture(CB.CfgGet(key)) end,
            onSelect      = function(lbl) CB.CfgSet(key, lbl); CB.ApplyConfig() end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Cast bar"] },

        -- ════════════ General: enable + test + hide Blizzard ════════════
        { type = "group", title = L["General"],
          gate = { enabled = moduleOn, master = "enable" },
          build = function() return {
            { type = "checkbox", ref = "enable", label = L["Enable cast bar"],
              get = function() return CB.CfgGet("enabled") ~= false end,
              set = function(v) CB.CfgSet("enabled", v); CB.ApplyEnabled(); if menu then menu.Refresh() end end },
            { type = "button", width = 160, height = 26,
              label = CB.IsTesting() and L["Stop test"] or L["Test"],
              onClick = function()
                  if CB.IsTesting() then CB.StopTest() else CB.StartTest() end
                  if menu then menu.Rebuild() end
              end },
            { type = "checkbox", label = L["Hide Blizzard cast bar"],
              get = function() return CB.CfgGet("hideBlizzard") ~= false end,
              set = function(v) CB.CfgSet("hideBlizzard", v); CB.ApplyBlizzard() end },
        } end },

        -- ════════════ Placement: anchor to a CDM viewer + relative position + offset ════════════
        { type = "group", title = L["Placement"], enabledBy = moduleOn, build = function() return {
            cdmDestDropdown(L["Anchor to"], "anchorTo",
                function() CB.ApplyPosition(); if CB.pe then CB.pe.Refresh() end end),
            { type = "dropdown", label = L["Position relative to anchor"], width = 220, height = 50,
              getList       = function() return CB.RelList() end,
              getCurrentKey = function() return CB.RelLabel(CB.CfgGet("positionRelative") or "bottom") end,
              onSelect      = function(lbl)
                  CB.CfgSet("positionRelative", CB.RelKeyFromLabel(lbl))
                  CB.ApplyPosition(); if CB.pe then CB.pe.Refresh() end
              end },
            { type = "position", ref = "pe", label = "",
              onBuilt = function(w) CB.pe = w end,
              getX = function() return CB.CfgGet("posX") end,
              getY = function() return CB.CfgGet("posY") end,
              onApply = function(x, yv)
                  if x  then CB.CfgSet("posX", x)  end
                  if yv then CB.CfgSet("posY", yv) end
                  CB.ApplyPosition()
              end,
              onUnlock   = function() CB.SetUnlocked(true) end,
              onLock     = function() CB.SetUnlocked(false); if CB.pe then CB.pe.Refresh() end end,
              isUnlocked = function() return CB.IsUnlocked() end },
        } end },

        -- ════════════ Bar size: adapt-to-CDM (greys Width) + width / height ════════════
        { type = "group", title = L["Bar size"], enabledBy = moduleOn, build = function() return {
            { type = "checkbox", label = L["Adapt width to"],
              get = function() return CB.CfgGet("adaptWidth") == true end,
              set = function(v) CB.CfgSet("adaptWidth", v); CB.ApplyConfig(); if menu then menu.Rebuild() end end },
            cdmDestDropdown("", "adaptWidthTo",
                function() CB.ApplyConfig() end,
                function() return CB.CfgGet("adaptWidth") == true end),
            -- Width keeps showing the saved value (not the auto-adapted size); greyed while
            -- "Adapt width to" is on.
            { type = "textinput", label = L["Width"], width = 60, numeric = true, min = 20, max = 1024, maxLetters = 4,
              enabledBy = function() return CB.CfgGet("adaptWidth") ~= true end,
              get = function() return CB.CfgGet("width") end,
              set = function(v) if v and v >= 20 then CB.CfgSet("width", v); CB.ApplyConfig() end end },
            sizeInput(L["Height"], "height", 6, 256),
        } end },

        -- ════════════ Icon: show / side / gap ════════════
        { type = "group", title = L["Icon"], enabledBy = moduleOn, build = function() return {
            { type = "checkbox", label = L["Show icon"],
              get = function() return CB.CfgGet("showIcon") ~= false end,
              set = function(v) CB.CfgSet("showIcon", v); CB.ApplyConfig() end },
            { type = "dropdown", label = L["Icon position"], width = 160, height = 50,
              getList       = function() return { L["Left"], L["Right"] } end,
              getCurrentKey = function() return CB.CfgGet("iconPosition") == "right" and L["Right"] or L["Left"] end,
              onSelect      = function(lbl) CB.CfgSet("iconPosition", lbl == L["Right"] and "right" or "left"); CB.ApplyConfig() end },
            sizeInput(L["Icon and bar gap"], "iconGap", 0, 100),
        } end },

        -- ════════════ Text: spell-name sub-cadre + timer sub-cadre + spark ════════════
        { type = "group", title = L["Text"], enabledBy = moduleOn, build = function() return {
            { type = "group", title = L["Spell name"], build = function() return {
                { type = "checkbox", label = L["Show spell name"],
                  get = function() return CB.CfgGet("showSpellName") ~= false end,
                  set = function(v) CB.CfgSet("showSpellName", v); CB.ApplyConfig() end },
                textStyleEntry("name"),
                offsetInput(L["Name x offset"], "nameXOffset"),
                offsetInput(L["Name y offset"], "nameYOffset"),
            } end },
            { type = "group", title = L["Timer"], build = function() return {
                { type = "checkbox", label = L["Show timer"],
                  get = function() return CB.CfgGet("showTimer") ~= false end,
                  set = function(v) CB.CfgSet("showTimer", v); CB.ApplyConfig() end },
                textStyleEntry("timer"),
                offsetInput(L["Timer x offset"], "timerXOffset"),
                offsetInput(L["Timer y offset"], "timerYOffset"),
            } end },
            { type = "checkbox", label = L["Show spark"],
              get = function() return CB.CfgGet("showSpark") ~= false end,
              set = function(v) CB.CfgSet("showSpark", v); CB.ApplyConfig(); if menu then menu.Refresh() end end },
            { type = "textinput", label = L["Spark thickness"], width = 60, numeric = true, min = 1, max = 64, maxLetters = 3,
              enabledBy = function() return CB.CfgGet("showSpark") ~= false end,
              get = function() return CB.CfgGet("sparkThickness") end,
              set = function(v) if v and v >= 1 then CB.CfgSet("sparkThickness", v); CB.ApplyConfig() end end },
        } end },

        -- ════════════ Bar texture ════════════
        { type = "group", title = L["Bar texture"], enabledBy = moduleOn, build = function() return {
            textureDropdown(L["Bar texture"],        "barTexture"),
            textureDropdown(L["Background texture"], "bgTexture"),
        } end },

        -- ════════════ Bar colors ════════════
        { type = "group", title = L["Bar colors"], enabledBy = moduleOn, build = function() return {
            colorGroupEntry(L["Cast color"],            "castColor"),
            colorGroupEntry(L["Channel color"],         "channelColor"),
            colorGroupEntry(L["Uninterruptible color"], "uninterruptibleColor"),
        } end },

        -- ════════════ End feedback (brief coloured hold on cast end) ════════════
        { type = "group", title = L["End feedback"], enabledBy = moduleOn, build = function()
            local function feedbackOn() return CB.CfgGet("showEndFeedback") ~= false end
            local function gatedColor(label, key)
                local e = colorGroupEntry(label, key); e.enabledBy = feedbackOn; return e
            end
            return {
                { type = "checkbox", label = L["Show cast end feedback"],
                  get = function() return feedbackOn() end,
                  set = function(v) CB.CfgSet("showEndFeedback", v); if menu then menu.Refresh() end end },
                gatedColor(L["Success color"],     "completeColor"),
                gatedColor(L["Interrupted color"], "interruptedColor"),
            }
        end },

        -- ════════════ Border (Enable greys colour + thickness) ════════════
        { type = "group", title = L["Border"], enabledBy = moduleOn, build = function() return {
            { type = "checkbox", label = L["Enable"],
              get = function() return CB.CfgGet("borderEnabled") ~= false end,
              set = function(v) CB.CfgSet("borderEnabled", v); CB.ApplyConfig(); if menu then menu.Refresh() end end },
            { type = "textEditor", label = L["Color"],
              enabledBy = function() return CB.CfgGet("borderEnabled") ~= false end,
              showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
              getColor = function() return CB.CfgGet("borderColor") end,
              onColorChange = function(r, g, b, a) CB.CfgSet("borderColor", { r = r, g = g, b = b, a = a }); CB.ApplyConfig() end },
            { type = "textinput", label = L["Border thickness"], width = 60, numeric = true, min = 1, max = 16, maxLetters = 2,
              enabledBy = function() return CB.CfgGet("borderEnabled") ~= false end,
              get = function() return CB.CfgGet("borderThickness") end,
              set = function(v) if v and v >= 1 then CB.CfgSet("borderThickness", v); CB.ApplyConfig() end end },
        } end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    return menu
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Cast bar"], nil, CreateCastBarPanel)
end)
