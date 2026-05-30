-- UI/Shared/IconPicker.lua
-- Reusable icon picker widget.
--
-- Usage:
--   local ip = ns.ui.CreateIconPicker({
--       parent    = panel,
--       getConfig = function() return MyCfg_Get("icon") end,
--       setConfig = function(key, val) MyCfg_Set("icon."..key, val) end,
--       icons     = {
--           { label = "My Icon", path = "Interface\\AddOns\\UnbunkUtility\\Media\\Icons\\myicon.tga" },
--       },
--   })
--   ip.frame
--   ip.height
--   ip.Refresh()

local _, ns = ...
local L = ns.L

local POSITIONS = {
    { key = "TOP_LEFT",      label = L["Top Left"]      },
    { key = "TOP_CENTER",    label = L["Top Center"]     },
    { key = "TOP_RIGHT",     label = L["Top Right"]      },
    { key = "LEFT",          label = L["Left"]           },
    { key = "RIGHT",         label = L["Right"]          },
    { key = "BOTTOM_LEFT",   label = L["Bottom Left"]    },
    { key = "BOTTOM_CENTER", label = L["Bottom Center"]  },
    { key = "BOTTOM_RIGHT",  label = L["Bottom Right"]   },
}

ns.ui = ns.ui or {}

function ns.ui.CreateIconPicker(config)
    local parent    = config.parent
    local getConfig = config.getConfig
    local setConfig = config.setConfig
    local icons     = config.icons or {}

    local result = {}
    local height = 0

    -- Snapshot for the construction-time reads below; closures re-read getConfig()
    -- live. Guard against a getConfig that can return nil before its DB is init'd.
    local initCfg = getConfig() or {}

    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(518)

    -- ── Enable checkbox ───────────────────────────────────────────────────────

    local enableCb = ns.ui.CreateCheckbox({
        parent  = container,
        label   = L["Show icon"],
        checked = initCfg.enabled ~= false,
        onClick = function(val) setConfig("enabled", val) end,
    })
    enableCb.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    height = height + 28

    -- ── Icon preview ──────────────────────────────────────────────────────────

    local previewFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    previewFrame:SetSize(40, 40)
    previewFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    previewFrame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    previewFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    previewFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local previewTex = previewFrame:CreateTexture(nil, "ARTWORK")
    previewTex:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 4, -4)
    previewTex:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", -4, 4)

    local function RefreshPreview()
        local cfg = getConfig()
        if cfg.useCustom and cfg.customId and tonumber(cfg.customId) then
            previewTex:SetTexture(tonumber(cfg.customId))
        elseif cfg.iconPath then
            previewTex:SetTexture(cfg.iconPath)
        else
            previewTex:SetTexture(nil)
        end
    end

    -- ── Icon dropdown ─────────────────────────────────────────────────────────

    local iconLabel = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    iconLabel:SetPoint("LEFT", previewFrame, "RIGHT", 10, 8)
    iconLabel:SetText(L["Icon"])

    local iconAnchor = container:CreateFontString(nil, "ARTWORK")
    iconAnchor:SetPoint("TOPLEFT", previewFrame, "TOPRIGHT", 10, 4)

    local iconList = {}
    for _, ic in ipairs(icons) do
        table.insert(iconList, ic.label)
    end
    if #iconList == 0 then
        table.insert(iconList, L["(no icons available)"])
    end

    local iconDD = ns.ui.CreateDropdown({
        parent        = container,
        anchorFrame   = iconAnchor,
        width         = 200,
        itemHeight    = 20,
        visibleItems  = 6,
        getList       = function() return iconList end,
        getCurrentKey = function()
            local cfg = getConfig()
            if not cfg or not cfg.iconPath then return iconList[1] end
            for _, ic in ipairs(icons) do
                if ic.path == cfg.iconPath then return ic.label end
            end
            return iconList[1]
        end,
        onSelect      = function(label)
            for _, ic in ipairs(icons) do
                if ic.label == label then
                    setConfig("iconPath", ic.path)
                    RefreshPreview()
                    break
                end
            end
        end,
    })

    height = height + 48

    -- ── Custom icon checkbox + input ──────────────────────────────────────────

    local customCb = ns.ui.CreateCheckbox({
        parent  = container,
        label   = L["Custom icon ID"],
        checked = initCfg.useCustom or false,
        onClick = function(val)
            setConfig("useCustom", val)
            RefreshPreview()
        end,
    })
    customCb.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    height = height + 28

    local customInput = ns.ui.CreateTextInput({
        parent     = container,
        width      = 120,
        height     = 22,
        numeric    = true,
        maxLetters = 10,
        text       = tostring(initCfg.customId or ""),
        onEnter    = function(val)
            setConfig("customId", val)
            RefreshPreview()
        end,
    })
    customInput.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    height = height + 30

    -- ── Position dropdown ─────────────────────────────────────────────────────

    local posLabel = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    posLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    posLabel:SetText(L["Position"])
    height = height + 18

    local posAnchor = container:CreateFontString(nil, "ARTWORK")
    posAnchor:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)

    local posList = {}
    for _, p in ipairs(POSITIONS) do table.insert(posList, p.label) end

    local posDD = ns.ui.CreateDropdown({
        parent        = container,
        anchorFrame   = posAnchor,
        width         = 180,
        itemHeight    = 20,
        visibleItems  = 8,
        getList       = function() return posList end,
        getCurrentKey = function()
            local cfg = getConfig()
            for _, p in ipairs(POSITIONS) do
                if p.key == cfg.position then return p.label end
            end
            return L["Top Center"]
        end,
        onSelect      = function(label)
            for _, p in ipairs(POSITIONS) do
                if p.label == label then
                    setConfig("position", p.key)
                    break
                end
            end
        end,
    })
    height = height + 30

    -- ── Size inputs ───────────────────────────────────────────────────────────

    local sizeLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sizeLbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    sizeLbl:SetText(L["Size"])
    height = height + 18

    local wLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wLbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    wLbl:SetText(L["W"])

    local wInput = ns.ui.CreateTextInput({
        parent     = container,
        width      = 46,
        height     = 22,
        numeric    = true,
        maxLetters = 3,
        text       = tostring(initCfg.width or 32),
        onEnter    = function(val)
            if val and val > 0 then setConfig("width", val) end
        end,
    })
    wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)

    local hLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0)
    hLbl:SetText(L["H"])

    local hInput = ns.ui.CreateTextInput({
        parent     = container,
        width      = 46,
        height     = 22,
        numeric    = true,
        maxLetters = 3,
        text       = tostring(initCfg.height or 32),
        onEnter    = function(val)
            if val and val > 0 then setConfig("height", val) end
        end,
    })
    hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)

    height = height + 30

    container:SetHeight(height)
    result.frame  = container
    result.height = height

    function result.Refresh()
        local cfg = getConfig()
        enableCb.SetChecked(cfg.enabled ~= false)
        customCb.SetChecked(cfg.useCustom or false)
        if cfg.customId then customInput.SetText(tostring(cfg.customId)) end
        wInput.SetText(tostring(cfg.width or 32))
        hInput.SetText(tostring(cfg.height or 32))
        if cfg.iconPath then
            for _, ic in ipairs(icons) do
                if ic.path == cfg.iconPath then
                    iconDD.selectedText:SetText(ic.label)
                    break
                end
            end
        end
        RefreshPreview()
    end

    RefreshPreview()

    return result
end