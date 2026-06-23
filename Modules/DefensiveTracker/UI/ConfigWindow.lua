-- Modules/DefensiveTracker/UI/ConfigWindow.lua
-- Item/Spell Trackers > Defensive Tracker. A General cadre (enable + active-in filter)
-- then one collapsible section per class defensive (header = spell icon + name). Each
-- section reuses the custom-CDM-icon config template, reordered: Sound first, then an
-- "Icon" sub-cadre ("Show icon" + Placement, Border, Timer, Title, Stacks).

local ADDON, ns = ...
local L  = ns.L
local DT = ns.DefensiveTracker

local function panelRebuild() if DT.configMenu then DT.configMenu.Rebuild() end end

-- ── Cadre builders (each a BuildMenu group entry) ─────────────────────────────
local function SoundGroup(sid, LSM)
    return { type = "group", title = L["Sound alert"], build = function() return {
        { type = "sound", LSM = LSM, label = L["Sound on use"],
          getKey = function() return DT.Get(sid, "soundKeyUse") end,
          getEnable = function() return DT.Get(sid, "soundOnUse") end,
          onSelect = function(key, path) DT.Set(sid, "soundKeyUse", key); DT.Set(sid, "soundPathUse", path) end,
          onToggle = function(v) DT.Set(sid, "soundOnUse", v) end,
          onTest = function() DT.TestSound(sid, "use") end },
        { type = "sound", LSM = LSM, label = L["Sound when ready"],
          getKey = function() return DT.Get(sid, "soundKeyReady") end,
          getEnable = function() return DT.Get(sid, "soundOnReady") end,
          onSelect = function(key, path) DT.Set(sid, "soundKeyReady", key); DT.Set(sid, "soundPathReady", path) end,
          onToggle = function(v) DT.Set(sid, "soundOnReady", v) end,
          onTest = function() DT.TestSound(sid, "ready") end },
    } end }
end

-- The "Icon" sub-cadre: built by the shared ns.CDMGroups.TrackerIconGroup (same as every other tracker),
-- with a per-spell (sid-scoped) accessor. Free holds this defensive's own position / size / Border /
-- Timer / Title / Stacks; Override holds the per-icon look that governs the icon while it is in the CDM.
-- Defensive specifics: the Show-icon toggle and the free Position onApply don't re-apply (DT.ApplyIcon
-- runs on the next refresh), and the Placement controls rebuild the menu + the active module (no ApplySize).
local function IconGroup(sid, LSM)
    local pe
    local function get(k) return DT.Get(sid, k) end
    local function set(k, v) DT.Set(sid, k, v) end
    local function applyIcon() DT.ApplyIcon(sid) end  -- already forces a CDMAnchor re-pin
    local function afterPlacement() panelRebuild(); if ns.RebuildActiveModule then ns.RebuildActiveModule() end end
    return ns.CDMGroups.TrackerIconGroup({
        get = get, set = set,
        frameName = "UnbunkUtilityDefensive" .. sid, defaultDest = "belowPlayer", LSM = LSM,
        rebuild = panelRebuild, applyIcon = applyIcon, sizeApply = applyIcon,
        afterInclude = afterPlacement,
        seedValues = function() return DT.OverrideSeed(sid) end,
        pos = {
            getX = function() return DT.Get(sid, "posX") end,
            getY = function() return DT.Get(sid, "posY") end,
            onApply = function(x, yv) if x then DT.Set(sid, "posX", x) end if yv then DT.Set(sid, "posY", yv) end end,
            onUnlock = function() DT.SetUnlocked(sid, true) end,
            onLock   = function() DT.SetUnlocked(sid, false); if pe then pe.Refresh() end end,
            isUnlocked = function() return DT.IsUnlocked(sid) end,
            onBuilt = function(w) pe = w end,
        },
    })
end

-- One collapsible section per defensive: header = spell icon + name; body = Sound, Icon.
local function DefensiveSection(sid, LSM)
    return {
        type      = "section",
        heading   = "UnbunkUtilityH3",
        label     = DT.SpellName(sid),
        showCheckbox = true,   -- header checkbox = enable this defensive globally
        isChecked    = function() return DT.Get(sid, "enabled") ~= false end,
        onCheck      = function(v) DT.Set(sid, "enabled", v) end,
        getCollapsed = function() return DT._uiCollapsed and DT._uiCollapsed[sid] end,
        onCollapse   = function(v) DT._uiCollapsed = DT._uiCollapsed or {}; DT._uiCollapsed[sid] = v end,
        headerExtra  = function(headerBtn, headerLabel)
            local icon = headerBtn:CreateTexture(nil, "OVERLAY")
            icon:SetSize(18, 18); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(DT.SpellTexture(sid))
            local p, rel, rp, x, y = headerLabel:GetPoint()
            icon:SetPoint(p or "LEFT", rel or headerBtn, rp or "LEFT", x or 0, y or 0)
            headerLabel:ClearAllPoints()
            headerLabel:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            return function() icon:SetTexture(DT.SpellTexture(sid)); headerLabel:SetText(DT.SpellName(sid)) end
        end,
        build = function() return {
            SoundGroup(sid, LSM),
            IconGroup(sid, LSM),
        } end,
    }
end

local function CreateDefensiveTrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Defensive Tracker"] },

        -- General: enable + active-in filter (greys the filter when disabled).
        { type = "group", title = L["General"],
          gate = { enabled = function() return DT.Enabled() end, master = "enable" },
          build = function() return {
            { type = "checkbox", ref = "enable", label = L["Enable Defensive Tracker"], height = 24,
              get = function() return DT.Enabled() end,
              set = function(v) DT.SetEnabled(v) end },
            { type = "instanceFilter",
              getConfig = function() return DT.GetFilter() end,
              setConfig = function(k, v) DT.SetFilter(k, v) end },
        } end },
    }

    -- One section per tracked defensive (class + current spec).
    for _, sid in ipairs(DT.ActiveIds()) do
        options[#options + 1] = DefensiveSection(sid, LSM)
    end

    DT.configMenu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })

    -- Every defensive's Override / Free sections start collapsed and re-collapse on tab show.
    parent:HookScript("OnHide", function()
        local c = ns.db and ns.db.profile and ns.db.profile.defensiveTracker
        if c and c.spells then
            for _, e in pairs(c.spells) do e.ovCollapsed = true; e.freeCollapsed = true end
        end
    end)
    parent:HookScript("OnShow", function() if DT.configMenu then DT.configMenu.Rebuild() end end)
    return DT.configMenu
end

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["Defensive Tracker"], nil, CreateDefensiveTrackerPanel)
end)
