-- Modules/CastBar/UI/ConfigWindow.lua
-- "Cast bar" panel (top of Extra Utilities): enable, hide-Blizzard toggle, placement,
-- size, text style + colours for the custom player cast bar (ns.CastBar).

local _, ns = ...
local L  = ns.L
local CB = ns.CastBar

local function CreateCastBarPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu

    local function colorGroupEntry(label, key)
        return { type = "textEditor", label = label,
            showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
            getColor = function() return CB.CfgGet(key) end,
            onColorChange = function(r, g, b, a) CB.CfgSet(key, { r = r, g = g, b = b, a = a }); CB.ApplyConfig() end }
    end

    local function sizeInput(label, key, mn, mx)
        return { type = "textinput", label = label, width = 60, numeric = true, min = mn, max = mx, maxLetters = 4,
            get = function() return CB.CfgGet(key) end,
            set = function(v) if v and v > 0 then CB.CfgSet(key, v); CB.ApplyConfig() end end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Cast bar"] },

        -- ════════════ General: enable + hide Blizzard ════════════
        { type = "group", title = L["General"], build = function() return {
            { type = "checkbox", label = L["Enable cast bar"],
              get = function() return CB.CfgGet("enabled") ~= false end,
              set = function(v) CB.CfgSet("enabled", v); CB.ApplyEnabled(); if menu then menu.Refresh() end end },
            { type = "checkbox", label = L["Hide Blizzard cast bar"],
              get = function() return CB.CfgGet("hideBlizzard") ~= false end,
              set = function(v) CB.CfgSet("hideBlizzard", v); CB.ApplyBlizzard() end },
        } end },

        -- ════════════ Placement ════════════
        { type = "group", title = L["Placement"], build = function() return {
            { type = "position", ref = "pe",
              onBuilt = function(w) CB.pe = w end,
              label = L["Bar position (offset from screen center)"],
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

        -- ════════════ Size ════════════
        { type = "group", title = L["Bar size"], build = function() return {
            sizeInput(L["Width"],  "width",  20, 1024),
            sizeInput(L["Height"], "height", 6,  256),
        } end },

        -- ════════════ Icon ════════════
        { type = "group", title = L["Icon"], build = function() return {
            { type = "checkbox", label = L["Show icon"],
              get = function() return CB.CfgGet("showIcon") ~= false end,
              set = function(v) CB.CfgSet("showIcon", v); CB.ApplyConfig() end },
        } end },

        -- ════════════ Text ════════════
        { type = "group", title = L["Text"], build = function() return {
            { type = "checkbox", label = L["Show spell name"],
              get = function() return CB.CfgGet("showSpellName") ~= false end,
              set = function(v) CB.CfgSet("showSpellName", v); CB.ApplyConfig() end },
            { type = "checkbox", label = L["Show timer"],
              get = function() return CB.CfgGet("showTimer") ~= false end,
              set = function(v) CB.CfgSet("showTimer", v); CB.ApplyConfig() end },
            { type = "checkbox", label = L["Show spark"],
              get = function() return CB.CfgGet("showSpark") ~= false end,
              set = function(v) CB.CfgSet("showSpark", v); CB.ApplyConfig() end },
            { type = "textEditor", LSM = LSM, label = L["Text"],
              showLabel = false, showText = false, showFont = true, showSize = true, showColor = true, showOutline = true,
              getFontKey  = function() return CB.CfgGet("fontKey")  end,
              getFontPath = function() return CB.CfgGet("fontPath") end,
              getFontSize = function() return CB.CfgGet("fontSize") end,
              getColor    = function() return CB.CfgGet("textColor") end,
              getOutline  = function() return CB.CfgGet("outline")  end,
              onFontChange    = function(key, path) CB.CfgSet("fontKey", key); CB.CfgSet("fontPath", path); CB.ApplyConfig() end,
              onSizeChange    = function(size)       CB.CfgSet("fontSize", size); CB.ApplyConfig() end,
              onColorChange   = function(r, g, b, a) CB.CfgSet("textColor", { r = r, g = g, b = b, a = a }); CB.ApplyConfig() end,
              onOutlineChange = function(outline)    CB.CfgSet("outline", outline); CB.ApplyConfig() end },
        } end },

        -- ════════════ Bar colours ════════════
        { type = "group", title = L["Bar colours"], build = function() return {
            colorGroupEntry(L["Cast color"],            "castColor"),
            colorGroupEntry(L["Channel color"],         "channelColor"),
            colorGroupEntry(L["Uninterruptible color"], "uninterruptibleColor"),
        } end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })
    return menu
end

local initCB = CreateFrame("Frame")
initCB:RegisterEvent("ADDON_LOADED")
initCB:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Cast bar"], nil, CreateCastBarPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
