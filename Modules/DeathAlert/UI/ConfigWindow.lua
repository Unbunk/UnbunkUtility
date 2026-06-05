-- Modules/DeathAlert/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.DeathAlert = ns.DeathAlert or {}
local DA = ns.DeathAlert

-- Build the ordered BuildMenu options for one role section (tank/healer/dps).
-- The widgets, their order, get/set/callbacks and config keys are identical to
-- the previous imperative CreateAlertSection: Test button, InstanceFilter,
-- IconPicker, SoundPicker, TextEditor ("Alert text"), PositionEditor, Duration,
-- and (DPS only) the "unassigned role" checkbox.
local function BuildSectionOptions(prefix)
    local options = {
        -- ── Test button ───────────────────────────────────────────────────────
        -- testFrame height 26, button at TOPLEFT (0,-2), 100x22.
        {
            type       = "button",
            label      = L["Test Alert"],
            width      = 100,
            height     = 22,
            hostHeight = 26,
            btnOffsetY = -2,
            onClick    = function()
                local getFrame = prefix == "tank" and DA.GetTankFrame or
                             prefix == "healer" and DA.GetHealerFrame or
                             DA.GetDpsFrame
                local setTest  = prefix == "tank" and DA.SetTankTesting or
                             prefix == "healer" and DA.SetHealerTesting or
                             DA.SetDpsTesting
                setTest(true)
                getFrame():Show()
                DA.PlaySound(prefix)
                local duration = DA.CfgGet(prefix .. "AlertDuration")
                C_Timer.After(duration, function()
                    setTest(false)
                    getFrame():Hide()
                end)
            end,
        },

        -- ── Instance filter ───────────────────────────────────────────────────
        {
            type      = "instanceFilter",
            getConfig = function() return DA.CfgGet(prefix .. "InstanceFilter") end,
            setConfig = function(key, val)
                local filter = DA.CfgGet(prefix .. "InstanceFilter")
                filter[key] = val
                DA.CfgSet(prefix .. "InstanceFilter", filter)
            end,
        },

        -- ── Icon picker ───────────────────────────────────────────────────────
        {
            type      = "iconPicker",
            getConfig = function() return DA.CfgGet(prefix .. "Icon") end,
            setConfig = function(key, val)
                local cfg = DA.CfgGet(prefix .. "Icon")
                cfg[key] = val
                DA.CfgSet(prefix .. "Icon", cfg)
                if prefix == "tank" then DA.ApplyTankIcon()
                elseif prefix == "healer" then DA.ApplyHealerIcon()
                else DA.ApplyDpsIcon() end
            end,
            icons = UNBUNK_ICONS or {},
        },

        -- ── Sound picker ──────────────────────────────────────────────────────
        {
            type      = "sound",
            getKey    = function() return DA.CfgGet(prefix .. "SoundKey") end,
            getEnable = function() return DA.CfgGet(prefix .. "EnableSound") end,
            onSelect  = function(key, path)
                DA.CfgSet(prefix .. "SoundKey", key)
                DA.CfgSet(prefix .. "SoundPath", path)
            end,
            onToggle  = function(val)
                DA.CfgSet(prefix .. "EnableSound", val)
            end,
            onTest    = function()
                DA.PlaySound(prefix)
            end,
        },

        -- ── Text editor ───────────────────────────────────────────────────────
        {
            type            = "textEditor",
            label           = L["Alert text"],
            getText         = function() return DA.CfgGet(prefix .. "Message") end,
            getFontKey      = function() return DA.CfgGet(prefix .. "FontKey") end,
            getFontPath     = function() return DA.CfgGet(prefix .. "FontPath") end,
            getFontSize     = function() return DA.CfgGet(prefix .. "FontSize") end,
            getColor        = function() return DA.CfgGet(prefix .. "Color") end,
            getOutline      = function() return DA.CfgGet(prefix .. "Outline") end,
            onTextChange    = function(txt)
                DA.CfgSet(prefix .. "Message", txt)
                if prefix == "tank" then DA.ApplyTankMessage()
                elseif prefix == "healer" then DA.ApplyHealerMessage()
                else DA.ApplyDpsMessage() end
            end,
            onFontChange    = function(key, path)
                DA.CfgSet(prefix .. "FontKey", key)
                DA.CfgSet(prefix .. "FontPath", path)
                if prefix == "tank" then DA.ApplyTankFont()
                elseif prefix == "healer" then DA.ApplyHealerFont()
                else DA.ApplyDpsFont() end
            end,
            onSizeChange    = function(size)
                DA.CfgSet(prefix .. "FontSize", size)
                if prefix == "tank" then DA.ApplyTankFont()
                elseif prefix == "healer" then DA.ApplyHealerFont()
                else DA.ApplyDpsFont() end
            end,
            onColorChange   = function(r, g, b, a)
                DA.CfgSet(prefix .. "Color", { r=r, g=g, b=b, a=a })
                if prefix == "tank" then DA.ApplyTankColor()
                elseif prefix == "healer" then DA.ApplyHealerColor()
                else DA.ApplyDpsColor() end
            end,
            onOutlineChange = function(outline)
                DA.CfgSet(prefix .. "Outline", outline)
                if prefix == "tank" then DA.ApplyTankFont()
                elseif prefix == "healer" then DA.ApplyHealerFont()
                else DA.ApplyDpsFont() end
            end,
        },

        -- ── Position editor ───────────────────────────────────────────────────
        -- Registered into _G["DeathAlert_PE_"..prefix] so Core/Alert.lua's
        -- onDragStop can call .Refresh() on it (see Alert.lua).
        {
            type       = "position",
            onBuilt    = function(w) _G["DeathAlert_PE_" .. prefix] = w end,
            label      = L["Alert position (offset from screen center)"],
            getX       = function() return DA.CfgGet(prefix .. "PosX") end,
            getY       = function() return DA.CfgGet(prefix .. "PosY") end,
            onApply    = function(x, yv)
                if x  then DA.CfgSet(prefix .. "PosX", x)  end
                if yv then DA.CfgSet(prefix .. "PosY", yv) end
                if prefix == "tank" then DA.ApplyTankPosition()
                elseif prefix == "healer" then DA.ApplyHealerPosition()
                else DA.ApplyDpsPosition() end
            end,
            onUnlock   = function()
                if prefix == "tank" then DA.SetTankUnlocked(true)
                elseif prefix == "healer" then DA.SetHealerUnlocked(true)
                else DA.SetDpsUnlocked(true) end
            end,
            onLock     = function()
                if prefix == "tank" then DA.SetTankUnlocked(false)
                elseif prefix == "healer" then DA.SetHealerUnlocked(false)
                else DA.SetDpsUnlocked(false) end
            end,
            isUnlocked = function()
                if prefix == "tank" then return DA.IsTankUnlocked()
                elseif prefix == "healer" then return DA.IsHealerUnlocked()
                else return DA.IsDpsUnlocked() end
            end,
        },

        -- ── Duration editor ───────────────────────────────────────────────────
        {
            type = "duration",
            get  = function() return DA.CfgGet(prefix .. "AlertDuration") end,
            set  = function(val) DA.CfgSet(prefix .. "AlertDuration", val) end,
        },
    }

    -- ── Unassigned-role option (DPS section only) ─────────────────────────────
    -- Routes deaths of members with no assigned group role to the DPS alert
    -- (and the dpsSpam counter). See DA.CfgGet("dpsAlertUnassigned").
    if prefix == "dps" then
        table.insert(options, {
            type   = "checkbox",
            label  = L["Also alert deaths with no assigned role (treat as DPS)"],
            height = 24,
            get    = function() return DA.CfgGet("dpsAlertUnassigned") == true end,
            set    = function(val) DA.CfgSet("dpsAlertUnassigned", val) end,
        })
    end

    -- Trailing spacer reproducing the original section height padding.
    -- The previous AddWidget added GAP(10) before EVERY widget (including the
    -- first) plus a final `height = height + 16`. BuildMenu's inner stack adds
    -- GAP only BETWEEN widgets, so it is short by one leading gap (10) plus the
    -- trailing 16. A 16px spacer (itself preceded by the 10px inter-widget gap)
    -- restores the exact section height: 10 + 16 = 26.
    table.insert(options, { type = "custom", height = 16 })

    return options
end

local function CreateDeathAlertPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    -- Three collapsible role sections (tank / healer / dps), each a nested
    -- BuildMenu drawn at innerWidth 518 so the embedded InstanceFilter /
    -- IconPicker / SoundPicker / TextEditor render without clipping.
    local options = {
        {
            type      = "section",
            label     = L["Tank Death Alert"],
            isChecked = function() return DA.CfgGet("tankEnabled") end,
            onCheck   = function(val) DA.CfgSet("tankEnabled", val) end,
            build     = function() return BuildSectionOptions("tank") end,
        },
        {
            type      = "section",
            label     = L["Healer Death Alert"],
            isChecked = function() return DA.CfgGet("healerEnabled") end,
            onCheck   = function(val) DA.CfgSet("healerEnabled", val) end,
            build     = function() return BuildSectionOptions("healer") end,
        },
        {
            type      = "section",
            label     = L["DPS Death Alert"],
            isChecked = function() return DA.CfgGet("dpsEnabled") end,
            onCheck   = function(val) DA.CfgSet("dpsEnabled", val) end,
            build     = function() return BuildSectionOptions("dps") end,
        },
    }

    -- Outer sections stack with gap=8 (matches the previous AddSection GAP).
    -- innerWidth=518 propagates to each section's nested BuildMenu so the
    -- embedded shared widgets draw at full width. autoHook generates the OnShow
    -- re-sync (refreshes every widget + section checkbox) automatically.
    return ns.ui.BuildMenu(parent, options, {
        gap        = 8,
        width      = 518,
        innerWidth = 518,
        LSM        = LSM,
    })
end

-- ── Enregistrement ────────────────────────────────────────────────────────────

local initDA = CreateFrame("Frame")
initDA:RegisterEvent("ADDON_LOADED")
initDA:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Death Alert"], nil, CreateDeathAlertPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
