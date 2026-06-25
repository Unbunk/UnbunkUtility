-- Modules/CDMGroups/UI/ConfigWindow.lua
-- "Essential (groups)" / "Utility (groups)" panel — a GENERALIZED, dest-parameterized clone of
-- Modules/BuffGroups/UI/ConfigWindow.lua. CreatePanel(I) builds the panel bound to ONE Config
-- instance (ns.CDMGroups.essential + ns.CDMGroups.utility each get one CreatePanel call).
--
-- Layout (same template as Buffs): an enable checkbox under the title (DEFAULT OFF — the new engine
-- only takes over the native Essential viewer when this is ON; until then the OLD bucket system runs),
-- then a "Cooldown groups" cadre holding one sub-cadre per group, an "Unused" sub-cadre and a
-- "Create group" button. Each group cadre: name input, a draggable icon strip (reorder / move between
-- groups), and a collapsible "Group settings" (Position / Border / Glow / Icons). A PENCIL on each
-- tile opens the per-ICON override editor (the same shared SUBSET as Buffs).
--
-- DIFFERENCES from the Buffs panel: NO "+" add tile / custom-buff prompt (natives only this phase).
-- The red "Not displayed" flag IS present: a cooldown placed in a real group that isn't in the native
-- CDM's tracked (displayed) set can't show there, so its tile is flagged red (port of BuffGroups).

local _, ns = ...
local L = ns.L

local ICON, PAD = 30, 4
local STEP = ICON + 6
local GAP_BG = 6
local PER_ROW = 12

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ── anchorTo / growDir / relPos option maps (label <-> stored key) — identical to Buffs ──
local ANCHOR_ORDER = { "essential", "utility", "belowPlayer", "screen" }
local function AnchorLabel(key)
    if key == "essential"   then return L["Essential"]    end
    if key == "screen"      then return L["Screen"]       end
    if key == "belowPlayer" then return L["Below player"] end
    return L["Utility"]
end
local function AnchorList()
    local t = {}
    for _, k in ipairs(ANCHOR_ORDER) do t[#t + 1] = AnchorLabel(k) end
    return t
end
local function AnchorFromLabel(label)
    for _, k in ipairs(ANCHOR_ORDER) do
        if AnchorLabel(k) == label then return k end
    end
    return "essential"
end

local GROW_ORDER = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER_H", "CENTER_V" }
local function GrowLabel(key)
    if key == "LEFT"     then return L["Left"]                  end
    if key == "UP"       then return L["Up"]                    end
    if key == "DOWN"     then return L["Down"]                  end
    if key == "CENTER_H" then return L["Center (horizontal)"]   end
    if key == "CENTER_V" then return L["Center (vertical)"]     end
    return L["Right"]
end
local function GrowList()
    local t = {}
    for _, k in ipairs(GROW_ORDER) do t[#t + 1] = GrowLabel(k) end
    return t
end
local function GrowFromLabel(label)
    for _, k in ipairs(GROW_ORDER) do
        if GrowLabel(k) == label then return k end
    end
    return "RIGHT"
end

-- Glow-type enum now lives in ns.ui.IconCadres (single source); alias the locals this panel uses.
local GlowTypeLabel     = ns.ui.IconCadres.GlowTypeLabel
local GlowTypeList      = ns.ui.IconCadres.GlowTypeList
local GlowTypeFromLabel = ns.ui.IconCadres.GlowTypeFromLabel

local RELPOS_ORDER = { "above", "below", "left", "right", "topleft", "topright", "bottomleft", "bottomright" }
local function RelPosLabel(key)
    if key == "below"       then return L["Below"]        end
    if key == "left"        then return L["Left"]         end
    if key == "right"       then return L["Right"]        end
    if key == "topleft"     then return L["Top-left"]     end
    if key == "topright"    then return L["Top-right"]    end
    if key == "bottomleft"  then return L["Bottom-left"]  end
    if key == "bottomright" then return L["Bottom-right"] end
    return L["Above"]
end
local function RelPosList()
    local t = {}
    for _, k in ipairs(RELPOS_ORDER) do t[#t + 1] = RelPosLabel(k) end
    return t
end
local function RelPosFromLabel(label)
    for _, k in ipairs(RELPOS_ORDER) do
        if RelPosLabel(k) == label then return k end
    end
    return "above"
end

-- ── Shared icon-customization cadres now live in ns.ui.IconCadres (UI/Shared/IconCadres.lua),
-- bundle-driven and reused across CDMGroups / BuffGroups / CustomCDM / the trackers. The local
-- aliases below keep the rest of this file (the Essential/Utility group panel + the exports)
-- reading the same names it always has.
local IC            = ns.ui.IconCadres
local TimerSection  = IC.Timer
local TitleSection  = IC.Title
local StacksSection = IC.Stacks

-- Exposed so the below-player panel (and later the shared custom-icon window) can reuse the SAME
-- Timer/Title/Stacks sections fed a per-dest bundle — pixel-identical to essential, with the show-gate
-- greying handled by the section's own `gate` (active when the bundle has no `has`, i.e. not an override).
ns.CDMGroups = ns.CDMGroups or {}
ns.CDMGroups.TimerSection  = TimerSection
ns.CDMGroups.TitleSection  = TitleSection
ns.CDMGroups.StacksSection = StacksSection
ns.CDMGroups.SectionKeys   = IC.SectionKeys
ns.CDMGroups.GrowList      = GrowList
ns.CDMGroups.GrowLabel     = GrowLabel
ns.CDMGroups.GrowFromLabel = GrowFromLabel
ns.CDMGroups.GlowTypeList      = GlowTypeList
ns.CDMGroups.GlowTypeLabel     = GlowTypeLabel
ns.CDMGroups.GlowTypeFromLabel = GlowTypeFromLabel

-- ════════════════════════════════════════════════════════════════════════════════
-- Per-ICON override editor (the pencil), bound to a Config instance `I`. One singleton editor is
-- shared across panels (re-pointed to the active I + sid on open).
-- ════════════════════════════════════════════════════════════════════════════════
local iconEditor
local editingI, editingSid
local onIconEditChange
local OpenIconEditor   -- fwd decl

-- The per-ICON "Override settings" cadre set (Sound + CDM settings + Icon size + Border + Glow +
-- Timer/Title/Stacks + Copy all). Now a thin wrapper over the shared assembler
-- ns.ui.IconCadres.OverrideSet (spell/item variant) — the SAME body backs the per-icon pencil editor
-- and the standalone CustomCDM editor (each supplies its own bundle + ctx). `I`/`sid` are unused here
-- (kept for call-site compatibility); opts.omit drops chrome entries (trackers omit
-- sound/placeholder/label; below-player omits size).
local function IconSections(I, sid, bundle, ctx, opts)
    opts = opts or {}
    return IC.OverrideSet(bundle, ctx, { type = "spellitem", omit = opts.omit })
end
ns.CDMGroups.IconSections = IconSections

-- Build the (bundle, ctx) a TRACKER's "Override settings" cadre feeds to IconSections: bound to the
-- icon's PER-ICON override in its essential/utility CDMGroups group (keyed by frameName; override →
-- group default). `onApply` re-applies the icon in-game after a value change; `onRebuild` re-renders the
-- tracker's config menu (the section gates use `when`). Returns nil for a dest with no group instance
-- (below-player / screen / free) so the caller can grey the cadre.
function ns.CDMGroups.MakeTrackerOverride(dest, frameName, onApply, onRebuild)
    local I = ns.CDMGroups.instances and ns.CDMGroups.instances[dest]
    if not I then return nil end
    local function apply()   if onApply   then onApply()   end end
    local function rebuild() if onRebuild then onRebuild() end end
    local function stashGet(key) return I.IconStashGet(frameName, key) end
    local function stashSet(key, val) I.IconStashSet(frameName, key, val) end
    local bundle = {
        -- Display value: the active override, else the value stashed when this section was disabled (so the
        -- cadre keeps SHOWING your override settings while greyed/inheriting), else the group default.
        get      = function(key)
            if I.IconHasOverride(frameName, key) then return I.IconGet(frameName, key) end
            local s = stashGet(key); if s ~= nil then return s end
            return I.GGet(I.GroupOf(frameName), key)
        end,
        groupGet = function(key) return I.GGet(I.GroupOf(frameName), key) end,
        set      = function(key, val) I.IconSet(frameName, key, val) end,
        reset    = function(key) I.IconReset(frameName, key) end,
        has      = function(keys)
            for _, k in ipairs(keys) do if I.IconHasOverride(frameName, k) then return true end end
            return false
        end,
        touch    = apply,
        refresh  = rebuild,   -- shared section helpers expect a full menu re-render
        stashGet = stashGet, stashSet = stashSet,
    }
    local ctx = { refresh = rebuild, rebuild = rebuild, reopen = rebuild }
    return bundle, ctx
end

-- A section headerExtra that puts a small grey note right after the section title AND keeps the gear
-- glyph on the far right (e.g. "Override settings  (When in CDM)").
local function HeaderHint(text)
    return function(headerBtn, headerLabel)
        local fs = headerBtn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
        fs:SetPoint("LEFT", headerLabel, "RIGHT", 6, 0)
        fs:SetText(text); fs:SetTextColor(0.6, 0.6, 0.6)
        if ns.ui.SettingsHeaderIcon then ns.ui.SettingsHeaderIcon(headerBtn) end
    end
end

-- Build the shared "Override settings" + "Free icon settings" cadre pair every tracker module exposes in
-- its config. Returns a LIST of menu entries (a free-mode hint, then the two collapsible sections) to
-- splice into the module's Icon options. Both sections start collapsed, re-collapse on tab show (the
-- module wires the OnHide/OnShow via cfg.setCollapsed), and grey out for the wrong mode. The Override
-- section is the shared IconSections (minus Sound/placeholder/label) bound to the icon's PER-ICON override
-- in its current dest — essential/utility group OR below-player — seeded once from the Free look so the
-- in-CDM appearance starts identical, then is governed here.
-- cfg = {
--   frameName, getDest()->dest, inCdm()->bool, applyIcon(), rebuild(),
--   seedValues()->{group-schema overrides}, freeBuild()->{free cadres},
--   getOv()/setOv(bool), getFree()/setFree(bool),   -- collapsed state persistence
-- }
function ns.CDMGroups.TrackerCdmCadres(cfg)
    local dest = cfg.getDest()
    local ovBundle, ovCtx
    -- The Override cadre omits Sound (the trackers keep their own), and the placeholder / section-label
    -- chrome. Below-player keeps Icon size as a PER-ICON override: ticked, the icon uses its own iconW/iconH
    -- (honoured by CDMAnchor.LayoutBelowPlayer); unticked, it inherits the bucket's uniform width/height.
    local omit = { sound = true, placeholder = true, label = true }
    if dest == "belowPlayer" then
        local CA = ns.CDMAnchor
        if CA and CA.BelowIconGet then
            local fn     = cfg.frameName
            local bucket = (CA.IsAtEnd(cfg.cdmAtEnd and cfg.cdmAtEnd())) and "belowEnd" or "belowFront"
            if CA.SeedBelowIconOverride then CA.SeedBelowIconOverride(fn, cfg.seedValues()) end
            local function stashGet(key) return CA.BelowIconStashGet(fn, key) end
            local function stashSet(key, val) CA.BelowIconStashSet(fn, key, val) end
            -- The bucket stores its uniform size under width/height, but the shared Icon size section
            -- reads/writes iconW/iconH — map them to the bucket's real width/height (default 36) for the
            -- inherited value, so the section shows/copies the actual below-player size (not a stale 44).
            local function bucketGet(key)
                if key == "iconW" then return CA.GetDestCfg(bucket, "width", 36) end
                if key == "iconH" then return CA.GetDestCfg(bucket, "height", 36) end
                return CA.GetDestCfg(bucket, key)
            end
            ovBundle = {
                -- Display value: active override → stash (shown while disabled/greyed) → bucket default.
                get      = function(key)
                    if CA.BelowIconHasOverride(fn, key) then return CA.BelowIconGet(fn, bucket, key) end
                    local s = stashGet(key); if s ~= nil then return s end
                    return bucketGet(key)
                end,
                groupGet = function(key) return bucketGet(key) end,
                set      = function(key, val) CA.BelowIconSet(fn, key, val) end,
                reset    = function(key) CA.BelowIconReset(fn, key) end,
                has      = function(keys)
                    for _, k in ipairs(keys) do if CA.BelowIconHasOverride(fn, k) then return true end end
                    return false
                end,
                touch    = cfg.applyIcon,
                refresh  = cfg.rebuild,
                stashGet = stashGet, stashSet = stashSet,
            }
            ovCtx = { refresh = cfg.rebuild, rebuild = cfg.rebuild, reopen = cfg.rebuild }
        end
    else
        local inst = ns.CDMGroups.instances and ns.CDMGroups.instances[dest]
        if inst and inst.SeedIconOverride and ns.CDMGroups.MakeTrackerOverride then
            inst.SeedIconOverride(cfg.frameName, cfg.seedValues())
            ovBundle, ovCtx = ns.CDMGroups.MakeTrackerOverride(dest, cfg.frameName, cfg.applyIcon, cfg.rebuild)
        end
    end
    local function deferRebuild()
        if C_Timer and C_Timer.After then C_Timer.After(0, cfg.rebuild) else cfg.rebuild() end
    end
    return {
        { type = "label", font = "UnbunkUtilityH6", height = 18, color = { 0.6, 0.6, 0.6 },
          when = function() return not cfg.inCdm() end,
          text = L["Check Free icon settings to setup icon"] },

        { type = "section", label = L["Override settings"], showCheckbox = false,
          headerExtra = HeaderHint(L["(When in CDM)"]),
          gate = { enabled = function() return cfg.inCdm() end },
          getCollapsed = cfg.getOv,
          onCollapse   = function(c) cfg.setOv(c and true or false); deferRebuild() end,
          build = function()
              if ovBundle then
                  return ns.CDMGroups.IconSections(nil, cfg.frameName, ovBundle, ovCtx, { omit = omit })
              end
              return { { type = "label", font = "UnbunkUtilityBody", height = 36,
                  text = L["These apply when the icon is in the Essential or Utility Cooldown Manager group."] } }
          end },

        { type = "section", label = L["Free icon settings"], showCheckbox = false,
          headerExtra = HeaderHint(L["(When not in CDM)"]),
          gate = { enabled = function() return not cfg.inCdm() end },
          getCollapsed = cfg.getFree,
          onCollapse   = function(c) cfg.setFree(c and true or false); deferRebuild() end,
          build = cfg.freeBuild },
    }
end

-- Shared "Free icon settings" body for an addon TRACKER icon — the on-screen (not-in-CDM) look, matching
-- the CustomCDM free layout: Position → CDM settings (press overlay / keybinds) → Border → Glow (on-proc)
-- → Icon { Icon size, Timer, Title, Stacks/Charges } where Timer/Title/Stacks are the shared sections
-- (Style → Anchor). All bound to the tracker's OWN config (no override store). The render reuses TimerIcon:
-- it draws timer/border/glow/keybind from this config, and title/stacks from it too once the tracker
-- passes config.freeExtras=true to CreateTimerIcon. cfg = {
--   get(key)->val, set(key,val) (write only), touch() (re-apply), rebuild() (rebuild the menu),
--   sizeApply() (optional; called after an icon-size edit, else touch), LSM,
--   pos = { getX, getY, onApply(x,y), onUnlock, onLock, isUnlocked, onBuilt(w) },
-- }
function ns.CDMGroups.TrackerFreeCadres(cfg)
    local bundle = {
        get     = function(key) return cfg.get(key) end,
        set     = function(key, val) cfg.set(key, val) end,
        touch   = cfg.touch,
        refresh = cfg.rebuild,
    }
    local function sizeApply() if cfg.sizeApply then cfg.sizeApply() elseif cfg.touch then cfg.touch() end end
    return IC.FreeSet(bundle, {
        type      = "spellitem",
        sizeApply = sizeApply,
        position  = {
            onBuilt    = cfg.pos and cfg.pos.onBuilt,
            label      = L["Icon position (offset from screen center)"],
            getX       = cfg.pos and cfg.pos.getX,     getY = cfg.pos and cfg.pos.getY,
            onApply    = cfg.pos and cfg.pos.onApply,
            onUnlock   = cfg.pos and cfg.pos.onUnlock, onLock = cfg.pos and cfg.pos.onLock,
            isUnlocked = cfg.pos and cfg.pos.isUnlocked,
        },
    })
end

-- Build a tracker module's whole "Icon" group — the boilerplate every tracker used to copy-paste: the
-- "Show icon" checkbox (+ optional inline extra), the "Placement" group (Include-in-CDM checkbox +
-- Anchor-to dropdown), then the shared Override/Free cadre pair (TrackerCdmCadres). Returns ONE group
-- entry to splice into a module's options (top-level) or a per-section build list. Everything that varies
-- between trackers is injected via `b`; the structure here is identical to the hand-written copies it
-- replaces (same widgets, order, gate master, and TrackerCdmCadres cfg). b = {
--   get(key)->val, set(key,val),                 -- config accessor (caller binds its sid/prefix)
--   frameName, defaultDest ("essential"/"belowPlayer"), LSM, rebuild(),  -- rebuild = the menu's Rebuild
--   applyIcon(),                                 -- cold-path full re-apply (Override edits + free touch)
--   sizeApply(),                                 -- free icon-size apply (TrackerFreeCadres falls back to touch)
--   seedValues()->{override seed}, pos = { getX,getY,onApply,onUnlock,onLock,isUnlocked,onBuilt },
--   afterInclude(), afterAnchor()|=afterInclude, -- the apply+rebuild tail of the two Placement controls
--   onShowIcon()|nil,                            -- optional; fired by the Show-icon checkbox set
--   title=L["Icon"], enabledBy()|nil, showIconHeight|nil, showIconInline|nil,  -- optional chrome
-- }
function ns.CDMGroups.TrackerIconGroup(b)
    local function inCdm()   return ns.CDMIncludedVal(b.get("includeInCdm")) end
    local function curDest() return b.get("cdmDest") or b.defaultDest end
    return {
        type = "group", title = b.title or L["Icon"], enabledBy = b.enabledBy,
        -- Unchecking "Show icon" greys the rest of the Icon box; the checkbox itself stays live.
        gate = { enabled = function() return b.get("showIcon") ~= false end, master = "showicon" },
        build = function()
            local e = {
                { type = "checkbox", ref = "showicon", label = L["Show icon"], height = b.showIconHeight,
                  get = function() return b.get("showIcon") ~= false end,
                  set = function(v) b.set("showIcon", v); if b.onShowIcon then b.onShowIcon() end end,
                  inline = b.showIconInline },

                { type = "group", title = L["Placement"], build = function() return {
                    { type = "checkbox", label = L["Include in cdm"],
                      disabled = function() return not ns.IsCDMEnabled() end,
                      get = function() return inCdm() end,
                      set = function(v) b.set("includeInCdm", v); b.afterInclude() end },
                    { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                      when = function() return inCdm() end,
                      getList = function() return ns.CDMDestList() end,
                      getCurrentKey = function() return ns.CDMDestChoiceLabel(b.get) end,
                      onSelect = function(label) ns.CDMApplyDestChoice(label, b.set); (b.afterAnchor or b.afterInclude)() end },
                } end },
            }

            local cfg = {
                frameName  = b.frameName,
                getDest    = curDest,
                cdmAtEnd   = function() return b.get("cdmAtEnd") end,
                inCdm      = inCdm,
                applyIcon  = b.applyIcon,
                rebuild    = b.rebuild,
                getOv      = function() return b.get("ovCollapsed") ~= false end,
                setOv      = function(c) b.set("ovCollapsed", c) end,
                getFree    = function() return b.get("freeCollapsed") ~= false end,
                setFree    = function(c) b.set("freeCollapsed", c) end,
                seedValues = b.seedValues,
                freeBuild  = function()
                    return ns.CDMGroups.TrackerFreeCadres({
                        get = b.get, set = b.set, touch = b.applyIcon, rebuild = b.rebuild,
                        sizeApply = b.sizeApply, LSM = b.LSM, pos = b.pos,
                    })
                end,
            }
            for _, x in ipairs(ns.CDMGroups.TrackerCdmCadres(cfg)) do e[#e + 1] = x end
            return e
        end,
    }
end

-- The per-icon override editor's option tree: binds IconSections to the Config instance `I` + the
-- singleton pencil editor. bundle.* reads/writes the per-icon override store; bundle.refresh is the full
-- Rebuild the shared section helpers expect (the override gates use `when`); ctx routes the editor's own
-- light refresh / full rebuild / reopen.
local function IconOptions(I, sid)
    local function menuRefresh() if iconEditor and iconEditor.menu then iconEditor.menu.Refresh() end end
    local function menuRebuild() if iconEditor and iconEditor.menu then iconEditor.menu.Rebuild() end end
    local function stashGet(key) return I.IconStashGet(sid, key) end
    local function stashSet(key, val) I.IconStashSet(sid, key, val) end
    local bundle = {
        -- Display value: active override → stash (shown while disabled/greyed) → group default.
        get      = function(key)
            if I.IconHasOverride(sid, key) then return I.IconGet(sid, key) end
            local s = stashGet(key); if s ~= nil then return s end
            return I.GGet(I.GroupOf(sid), key)
        end,
        groupGet = function(key) return I.GGet(I.GroupOf(sid), key) end,
        set      = function(key, val) I.IconSet(sid, key, val) end,
        reset    = function(key) I.IconReset(sid, key) end,
        has      = function(keys)
            for _, key in ipairs(keys) do if I.IconHasOverride(sid, key) then return true end end
            return false
        end,
        touch    = function() I.ApplyAll(); if onIconEditChange then onIconEditChange() end end,
        refresh  = menuRebuild,   -- shared helpers (OverrideToggle/Copy/Timer…) re-render via a full Rebuild
        stashGet = stashGet, stashSet = stashSet,
    }
    local ctx = { refresh = menuRefresh, rebuild = menuRebuild, reopen = function() OpenIconEditor(I, sid, onIconEditChange) end }
    return IconSections(I, sid, bundle, ctx)
end

local function EnsureIconEditor()
    if iconEditor then return iconEditor end

    local f = CreateFrame("Frame", "UnbunkUtilityCDGIconEditor", UIParent, "BackdropTemplate")
    f:SetSize(600, 620)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()
    tinsert(UISpecialFrames, "UnbunkUtilityCDGIconEditor")

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    f.title = title

    local titleIconL = f:CreateTexture(nil, "OVERLAY")
    titleIconL:SetSize(20, 20)
    titleIconL:SetPoint("RIGHT", title, "LEFT", -8, 0)
    titleIconL:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.titleIconL = titleIconL

    local titleIconR = f:CreateTexture(nil, "OVERLAY")
    titleIconR:SetSize(20, 20)
    titleIconR:SetPoint("LEFT", title, "RIGHT", 8, 0)
    titleIconR:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.titleIconR = titleIconR

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -6, -6)
    local cb = close:CreateTexture(nil, "BACKGROUND"); cb:SetAllPoints(close); cb:SetColorTexture(0.4, 0.4, 0.4, 1)
    local cf = close:CreateTexture(nil, "BACKGROUND", nil, 1)
    cf:SetPoint("TOPLEFT", 1, -1); cf:SetPoint("BOTTOMRIGHT", -1, 1); cf:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    local cx = close:CreateTexture(nil, "OVERLAY"); cx:SetSize(12, 12); cx:SetPoint("CENTER"); cx:SetTexture(UNBUNK_ICON_CROSS_WHITE)
    close:SetScript("OnEnter", function() local r, g, b = ns.GetBrandColor(); cb:SetColorTexture(r, g, b, 1); cx:SetVertexColor(r, g, b) end)
    close:SetScript("OnLeave", function() cb:SetColorTexture(0.4, 0.4, 0.4, 1); cx:SetVertexColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -44)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)

    local sb = ns.ui.CreateScrollBar({
        parent = f, scrollFrame = scroll, itemHeight = 30, visibleItems = 10,
        getListSize = function()
            local h = content:GetHeight() or 300
            return math.max(10, math.ceil(h / 30))
        end,
    })
    sb.track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 22, 0)
    sb.track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 22, 0)

    f:HookScript("OnShow", function() C_Timer.After(0, function() sb.Update() end) end)

    iconEditor = { frame = f, title = title, titleIconL = titleIconL, titleIconR = titleIconR,
                   scroll = scroll, content = content, sb = sb }
    return iconEditor
end

local function ClearIconMenu(ed)
    if not ed.menu then return end
    if ed.menu.content then ed.menu.content:Hide(); ed.menu.content:ClearAllPoints(); ed.menu.content:SetParent(nil) end
    for _, fr in ipairs(ed.menu.auxFrames or {}) do fr:Hide(); fr:ClearAllPoints(); fr:SetParent(nil) end
    ed.menu = nil
end

function OpenIconEditor(I, sid, onChange)
    local ed = EnsureIconEditor()
    editingI, editingSid = I, sid
    onIconEditChange = onChange
    ed.title:SetText(I.SpellName(sid) or L["Edit icon"])
    local tex = I.SpellTexture(sid)
    if ed.titleIconL then ed.titleIconL:SetTexture(tex) end
    if ed.titleIconR then ed.titleIconR:SetTexture(tex) end

    local function measureContentBottom()
        local top = ed.content:GetTop()
        if not top then return nil end
        local maxDepth = 0
        for i = 1, ed.content:GetNumChildren() do
            local child = select(i, ed.content:GetChildren())
            local bottom = child and child.GetBottom and child:GetBottom()
            if bottom then
                local depth = top - bottom
                if depth > maxDepth then maxDepth = depth end
            end
        end
        return maxDepth
    end
    local function syncHeight()
        if ed.menu then ed.content:SetHeight(math.max(1, ed.menu.height + 12)) end
        ed.sb.Update()
        C_Timer.After(0, function()
            if not (iconEditor and iconEditor.content == ed.content) then return end
            local measured = measureContentBottom()
            if measured then
                local want = math.max(1, measured + 12, (ed.menu and ed.menu.height + 12) or 0)
                if math.abs((ed.content:GetHeight() or 0) - want) > 0.5 then ed.content:SetHeight(want) end
            end
            ed.sb.Update()
        end)
    end
    local rawBuild
    ClearIconMenu(ed)
    ed.menu = ns.ui.BuildMenu(ed.content, IconOptions(I, sid), {
        gap = 10, width = 540, originX = 8, originY = 0, autoHook = false, LSM = LSM,
    })
    rawBuild = ed.menu.Rebuild
    ed.menu.Rebuild = function() rawBuild(); syncHeight() end
    syncHeight()
    ed.menu.Refresh()

    ed.frame:Show()
    ed.frame:Raise()
    ed.scroll:SetVerticalScroll(0)
    C_Timer.After(0, function() ed.sb.Update() end)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- The panel factory, bound to a Config instance `I`. `titleText` / `enableLabel` / `cadreTitle`
-- localise the dest (Essential now).
-- ════════════════════════════════════════════════════════════════════════════════
local function CreatePanel(I, titleText, enableLabel, cadreTitle)
    return function(parent)
        local menu
        local function rebuild() if menu then menu.Rebuild() end end
        local function touch() I.ApplyAll() end

        I.pe = I.pe or {}
        local strips = {}
        local dragTile, dragSid, dragHovered, dragHole
        local dragLayer
        local stopDrag

        local function ensureDragLayer()
            if dragLayer then return dragLayer end
            dragLayer = CreateFrame("Frame", nil, UIParent)
            dragLayer:SetFrameStrata("TOOLTIP")
            dragLayer:SetAllPoints(UIParent)
            return dragLayer
        end

        local function cursorOver(f)
            local l, b, w, h = f:GetRect()
            if not l then return false end
            local s = f:GetEffectiveScale()
            if not (s and s > 0) then return false end
            local mx, my = GetCursorPosition()
            mx, my = mx / s, my / s
            return mx >= l and mx < l + w and my >= b and my < b + h
        end

        local function dragOnUpdate()
            if not dragTile then return end
            if not IsMouseButtonDown("LeftButton") then stopDrag(); return end
            local scale = UIParent:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            if scale and scale > 0 and mx then
                dragTile:ClearAllPoints()
                dragTile:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / scale, my / scale)
            end
            -- The hovered strip yields a DESTINATION: for a real group a table { row, col } or
            -- { newRow = true }; for Unused a plain numeric index. relayout opens the hole there.
            local hovered, hole
            for _, s in ipairs(strips) do
                if s.frame:IsVisible() and cursorOver(s.frame) then
                    hovered = s; hole = s.slotAt(dragSid); break
                end
            end
            dragHovered, dragHole = hovered, hole
            for _, s in ipairs(strips) do s.relayout(dragSid, s == hovered and hole or nil) end
        end

        local driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", dragOnUpdate)

        local function startDrag(tile, spellId)
            dragTile, dragSid, dragHovered, dragHole = tile, spellId, nil, nil
            tile._origParent = tile:GetParent()
            tile:SetParent(ensureDragLayer())
            tile:SetFrameStrata("TOOLTIP")
            tile:Raise()
            driver:Show()
        end

        stopDrag = function()
            local tile = dragTile
            if not tile then return end
            driver:Hide()
            tile:SetParent(tile._origParent or UIParent)
            tile:SetFrameStrata("MEDIUM")
            local sid, hovered, hole = dragSid, dragHovered, dragHole
            dragTile, dragSid, dragHovered, dragHole = nil, nil, nil, nil
            if sid and hovered and hole ~= nil then
                local gid = hovered.groupId
                local full = gid ~= 0 and I.GroupOf(sid) ~= gid
                    and #I.GetGroupBuffs(gid) >= I.GROUP_CAP
                if not full then
                    if gid == 0 then
                        -- Unused stays flat: hole is a numeric index. MoveBuff into its single row.
                        I.MoveBuff(sid, 0, 1, hole)
                    elseif type(hole) == "table" then
                        if hole.newRow then
                            -- Forced new row: a row index past the last starts a brand-new row.
                            I.MoveBuff(sid, gid, math.huge, 0)
                        elseif hole.full then
                            -- Dropped on a maxPerRow-full row: reject (no move) — the icon snaps back.
                        else
                            I.MoveBuff(sid, gid, hole.row, hole.col)
                        end
                    end
                    touch()
                end
            end
            rebuild()
        end

        -- (The old cast-only "+" quick-add picker + its CustomCooldowns.lua engine were removed in
        -- Partie 3 phase F. The essential/utility "+" tiles now open the shared CustomCDM editor via
        -- ns.CustomCDM.PromptAddToGroup, and customs track the real cooldown.)

        -- Build one icon tile button for `spellId` in `frame`. Shared by both strip paths. `undisplayable`
        -- flags a non-displayable cooldown (red); custom icons get an X remove button + a duration-tooltip.
        local function MakeIconTile(frame, groupId, spellId)
            local b = CreateFrame("Button", nil, frame)
            b:SetSize(ICON, ICON)
            local bord = b:CreateTexture(nil, "BACKGROUND")
            bord:SetPoint("TOPLEFT", -1, 1); bord:SetPoint("BOTTOMRIGHT", 1, -1); bord:SetColorTexture(0.4, 0.4, 0.4, 1)
            local tex = b:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); tex:SetTexture(I.SpellTexture(spellId))
            b:RegisterForDrag("LeftButton")
            b:SetScript("OnDragStart", function() startDrag(b, spellId) end)
            b:SetScript("OnDragStop", function() stopDrag() end)

            -- An addon-TRACKER member (BL Tracker, Trinket, …) is keyed by its frame NAME (a string),
            -- not a spellId: it's an addon-drawn icon, always displayable, and has no spell tooltip.
            local isTracker = (type(spellId) == "string") and I.IsTracker and I.IsTracker(spellId)

            -- A NATIVE cooldown that isn't in the CDM's tracked (DISPLAYED) set has no native frame, so in
            -- a real group it can never show: flag the tile RED. A CUSTOM / TRACKER is always displayable;
            -- the Unused strip is never flagged; only flag once the displayed cache is known.
            local undisplayable = groupId ~= 0 and not isTracker and I.DisplayedKnown and I.DisplayedKnown()
                and not (I.IsDisplayable and I.IsDisplayable(spellId))
            if undisplayable then
                tex:SetVertexColor(1, 0.35, 0.35)
                bord:SetColorTexture(0.9, 0.15, 0.15, 1)
                local warn = b:CreateFontString(nil, "OVERLAY")
                warn:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
                warn:SetPoint("CENTER", b, "CENTER", 0, 0)
                warn:SetWordWrap(true)
                warn:SetJustifyH("CENTER")
                warn:SetTextColor(1, 0.45, 0.45)
                warn:SetText((L["Not displayed"]:gsub("%s+", "\n")))
            end

            local isCustom = I.IsCustom and I.IsCustom(spellId)
            -- A CustomCDM icon folded into this group is a tracker member keyed by its frame-name STRING.
            -- It's edited/removed via the shared CustomCDM editor, not the group's per-icon override.
            local isCC = ns.CustomCDM and ns.CustomCDM.IsCustom and ns.CustomCDM.IsCustom(spellId)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local shown = false
                -- A tile keys on the STABLE BASE spellId; resolve the CURRENT display form (keyToDisplay)
                -- so the tooltip matches the tile's live icon/name (Glacial Spike while transformed). Falls
                -- back to the base when the cooldown isn't currently in the pool. Tracker keys (strings) are
                -- untouched.
                local dispSid = spellId
                if type(spellId) == "number" and I.KeyToDisplay and I.KeyToDisplay[spellId] then
                    dispSid = I.KeyToDisplay[spellId]
                end
                -- Skip the spell tooltip for a CUSTOM and a TRACKER (a tracker's key is a frame name, not
                -- a spellId — SetSpellByID would be wrong/error). Both show just the display name instead.
                if not isCustom and not isTracker and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(dispSid) then
                    shown = pcall(GameTooltip.SetSpellByID, GameTooltip, dispSid)
                end
                if not shown then GameTooltip:SetText(I.SpellName(spellId), 1, 1, 1) end
                if isCustom then
                    local def = I.GetCustom and I.GetCustom(spellId)
                    GameTooltip:AddLine(L["Custom cooldown"] .. " (" .. tostring((def and def.duration) or 0) .. "s)", 0.6, 0.8, 1)
                end
                if undisplayable then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["Not in the Cooldown Manager's tracked buffs — it won't display."], 1, 0.3, 0.3, true)
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Pencil: per-icon override editor (hidden on Unused). Tinted brand colour when overridden.
            if groupId ~= 0 then
                local pb = CreateFrame("Button", nil, b)
                pb:SetSize(14, 14); pb:SetPoint("CENTER", b, "TOPLEFT", 4, -4)
                pb:SetFrameLevel(b:GetFrameLevel() + 5)
                local pbg = pb:CreateTexture(nil, "BACKGROUND"); pbg:SetAllPoints(); pbg:SetColorTexture(0, 0, 0, 0.6)
                local pg = pb:CreateTexture(nil, "OVERLAY"); pg:SetPoint("CENTER"); pg:SetSize(10, 10)
                pg:SetTexture(UNBUNK_ICON_PEN_WHITE)
                local function paint() if I.IconHasOverride(spellId) then pg:SetVertexColor(ns.GetBrandColor()) else pg:SetVertexColor(1, 1, 1) end end
                paint()
                pb:SetScript("OnEnter", function() pg:SetVertexColor(ns.GetBrandColor()) end)
                pb:SetScript("OnLeave", paint)
                pb:SetScript("OnClick", function()
                    if isCC and ns.CustomCDM then ns.CustomCDM.PromptEdit(ns.CustomCDM.IdFromFrameName(spellId))
                    else
                        -- An ADDON TRACKER (BL / trinket / …) keys on its frame NAME, which maps to its own
                        -- config tab — jump there (matching the below-player / Free-icons strips; the tab carries
                        -- the same Override settings). A NATIVE cooldown (number key) or unmapped icon → nil →
                        -- the per-icon OVERRIDE editor as before.
                        local panel = ns.PanelForTrackerFrame and ns.PanelForTrackerFrame(spellId)
                        if panel and ns.NavigateToPanel then ns.NavigateToPanel(panel)
                        else OpenIconEditor(I, spellId, rebuild) end
                    end
                end)
            end

            -- An old CDMGroups cast-only custom, OR a CustomCDM icon, gets an X (top-right) that removes it.
            -- A CustomCDM frame routes to CC.ConfirmRemove (deletes the entry + cleans up its group member-
            -- ship via CC.Remove); a legacy custom that survived migration uses I.RemoveCustom.
            if isCustom or isCC then
                local xb = CreateFrame("Button", nil, b)
                xb:SetSize(14, 14); xb:SetPoint("CENTER", b, "TOPRIGHT", -7, -3)
                xb:SetFrameLevel(b:GetFrameLevel() + 5)
                local xbg = xb:CreateTexture(nil, "BACKGROUND"); xbg:SetAllPoints(); xbg:SetColorTexture(0, 0, 0, 0.6)
                local xg = xb:CreateTexture(nil, "OVERLAY"); xg:SetPoint("CENTER"); xg:SetSize(10, 10); xg:SetTexture(UNBUNK_ICON_CROSS_WHITE)
                xb:SetScript("OnEnter", function() xg:SetVertexColor(ns.GetBrandColor()) end)
                xb:SetScript("OnLeave", function() xg:SetVertexColor(1, 1, 1) end)
                xb:SetScript("OnClick", function()
                    if isCC and ns.CustomCDM then
                        ns.CustomCDM.ConfirmRemove(ns.CustomCDM.IdFromFrameName(spellId))
                    else
                        if I.RemoveCustom then I.RemoveCustom(spellId) end
                        touch(); rebuild()
                    end
                end)
            end
            return b
        end

        -- Build one "+" add tile in `frame`, styled like BuffGroups' add tile. onDrop(dest) commits a
        -- dragged icon onto it; onClick adds a custom there. `dest` is the destination passed to MoveBuff.
        local function MakeAddTile(frame, onClick)
            local addb = CreateFrame("Button", nil, frame)
            addb:SetSize(ICON, ICON)
            local abord = addb:CreateTexture(nil, "BACKGROUND")
            abord:SetPoint("TOPLEFT", -1, 1); abord:SetPoint("BOTTOMRIGHT", 1, -1); abord:SetColorTexture(0.4, 0.4, 0.4, 1)
            local afill = addb:CreateTexture(nil, "BACKGROUND", nil, 1); afill:SetAllPoints(); afill:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            local aplus = addb:CreateTexture(nil, "ARTWORK"); aplus:SetPoint("CENTER"); aplus:SetSize(ICON - 12, ICON - 12); aplus:SetTexture(UNBUNK_ICON_PLUS_GREEN)
            addb:SetScript("OnEnter", function() afill:SetColorTexture(0.2, 0.2, 0.2, 0.95) end)
            addb:SetScript("OnLeave", function() afill:SetColorTexture(0.12, 0.12, 0.12, 0.9) end)
            addb:SetScript("OnClick", onClick)
            return addb
        end

        -- ── The strip ─────────────────────────────────────────────────────────────
        -- groupId 0 = Unused: a FLAT wrap (PER_ROW=12), no "+" tiles, never flagged. A REAL group renders
        -- EXPLICIT ROWS (I.GroupRows) of maxPerRow; each row with room gets an END-of-row "+" tile and a
        -- persistent "new row" "+" sits below the last row. A non-displayable cooldown is flagged RED.
        local function CDStripEntry(groupId)
            local wrap = (groupId == 0)
            return {
                type  = "custom",
                build = function(host)
                    local frame = CreateFrame("Frame", nil, host)
                    frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                    frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)

                    local obj = { frame = frame, groupId = groupId, tiles = {}, wrap = wrap }
                    strips[#strips + 1] = obj

                    -- Place a frame at a (row, col) grid cell (0-based col, 0-based row).
                    local function placeRC(f, row, col)
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * STEP, -(PAD + row * (ICON + GAP_BG)))
                    end

                    if wrap then
                        -- ── Unused: flat wrap, numeric slotAt/relayout (unchanged behaviour) ──
                        for _, sid in ipairs(I.GetGroupBuffs(groupId)) do
                            obj.tiles[#obj.tiles + 1] = { frame = MakeIconTile(frame, groupId, sid), spellId = sid }
                        end

                        local function placeAt(f, slot)
                            placeRC(f, math.floor(slot / PER_ROW), slot % PER_ROW)
                        end

                        function obj.slotAt(dragSpell)
                            local scale = frame:GetEffectiveScale()
                            if not (scale and scale > 0) then return 0 end
                            local mx, my = GetCursorPosition()
                            mx, my = mx / scale, my / scale
                            local idx = 0
                            for _, t in ipairs(obj.tiles) do
                                if t.spellId ~= dragSpell then
                                    local tl, tb = t.frame:GetLeft(), t.frame:GetBottom()
                                    if tl then
                                        local before
                                        if tb then
                                            local tcy  = tb + ICON / 2
                                            local band = (ICON + GAP_BG) / 2
                                            if tcy > my + band then before = true
                                            elseif tcy < my - band then before = false
                                            else before = (tl + ICON / 2) < mx end
                                        else
                                            before = (tl + ICON / 2) < mx
                                        end
                                        if not before then return idx end
                                    end
                                    idx = idx + 1
                                end
                            end
                            return idx
                        end

                        function obj.relayout(dragSpell, holeIndex)
                            local seq = {}
                            for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then seq[#seq + 1] = t end end
                            local slot = 0
                            for i, t in ipairs(seq) do
                                if holeIndex and (i - 1) == holeIndex then slot = slot + 1 end
                                placeAt(t.frame, slot); t.frame:Show()
                                slot = slot + 1
                            end
                        end

                        obj.relayout(nil, nil)

                        local items = #obj.tiles
                        local rows  = math.max(1, math.ceil(math.max(1, items) / PER_ROW))
                        local h = PAD * 2 + rows * ICON + math.max(0, rows - 1) * GAP_BG
                        host:SetHeight(h)
                        return { frame = host, height = h }
                    end

                    -- ── Real group: explicit ROWS + "+" tiles ──────────────────────────────
                    local per = I.MaxPerRow(groupId)
                    local groupRows = I.GroupRows(groupId)
                    -- obj.tiles[i] = { frame, spellId, row (0-based), col (0-based) } for icon tiles.
                    -- obj.addTiles[r] = the end-of-row "+" for row r (0-based); obj.newRowTile = below-rows "+".
                    obj.addTiles = {}
                    obj.rowCount = #groupRows
                    for ri, rowSids in ipairs(groupRows) do
                        for ci, sid in ipairs(rowSids) do
                            obj.tiles[#obj.tiles + 1] = { frame = MakeIconTile(frame, groupId, sid),
                                spellId = sid, row = ri - 1, col = ci - 1 }
                        end
                    end

                    -- The "new row" "+" below the last row: dropping forces a new row; clicking adds a custom there.
                    obj.newRowTile = MakeAddTile(frame, function()
                        if ns.CustomCDM and ns.CustomCDM.PromptAddToGroup then ns.CustomCDM.PromptAddToGroup(I.dest, groupId, math.huge, 0) end
                    end)

                    -- An end-of-row "+" per row that has room (< maxPerRow): dropping appends to that row's
                    -- end; clicking adds a custom there. Rebuilt each relayout to track the live counts.
                    local function ensureRowAddTile(r)
                        if not obj.addTiles[r] then
                            obj.addTiles[r] = MakeAddTile(frame, function()
                                if ns.CustomCDM and ns.CustomCDM.PromptAddToGroup then ns.CustomCDM.PromptAddToGroup(I.dest, groupId, r + 1, math.huge) end
                            end)
                        end
                        return obj.addTiles[r]
                    end

                    -- Row layout: a small "Row N" caption sits ABOVE each row; the icon grid is placed
                    -- below it, so each row is pitched to include the caption band.
                    local ROW_LABEL_H = 13
                    local rowPitch = ROW_LABEL_H + ICON + GAP_BG
                    local function placeCell(f, row, col)   -- 0-based row/col; icons sit BELOW the caption
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * STEP, -(PAD + ROW_LABEL_H + row * rowPitch))
                    end
                    obj.rowLabels = {}
                    local function placeRowLabel(row, text)   -- 0-based row; caption at the band top
                        local fs = obj.rowLabels[row]
                        if not fs then
                            fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            fs:SetTextColor(0.66, 0.66, 0.66)
                            obj.rowLabels[row] = fs
                        end
                        fs:ClearAllPoints()
                        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 1, -(PAD + row * rowPitch))
                        fs:SetText(text); fs:Show()
                    end

                    -- Red "Row is full" caption CENTRED over a row — drawn on a HIGH-level overlay frame
                    -- (above the icon tiles, which are child Buttons that would otherwise hide a plain
                    -- FontString). Shown only while a drag hovers a maxed-out row.
                    local function EnsureFullFrame()
                        if obj.fullFrame then return obj.fullFrame end
                        local f = CreateFrame("Frame", nil, frame)
                        f:SetAllPoints(frame)
                        f:SetFrameLevel((frame:GetFrameLevel() or 1) + 50)
                        obj.fullFrame = f
                        return f
                    end
                    obj.fullLabels = {}
                    local function SetRowFull(row, on)   -- 0-based row
                        local fs = obj.fullLabels[row]
                        if not on then if fs then fs:Hide() end return end
                        if not fs then
                            fs = EnsureFullFrame():CreateFontString(nil, "OVERLAY")
                            fs:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
                            fs:SetTextColor(1, 0.45, 0.45)
                            fs:SetText(L["Row is full"])
                            obj.fullLabels[row] = fs
                        end
                        fs:ClearAllPoints()
                        -- Centre of the row's icon span, vertically centred on the icon band.
                        fs:SetPoint("CENTER", frame, "TOPLEFT", PAD + ((per - 1) * STEP + ICON) / 2,
                            -(PAD + ROW_LABEL_H + row * rowPitch + ICON / 2))
                        fs:Show()
                    end

                    -- Destination cell under the cursor — computed from the SLOT geometry (PAD/STEP/rowPitch),
                    -- NOT the live tile positions, so the preview gap lines up exactly with where the drop
                    -- lands (no off-by-one as tiles shift around). Returns { row, col } (1-based row, 0-based
                    -- col), { newRow = true } when the cursor is below the last row, or { row, full = true }
                    -- when the hovered row is already at maxPerRow.
                    function obj.slotAt(dragSpell)
                        local scale = frame:GetEffectiveScale()
                        local fl, ft = frame:GetLeft(), frame:GetTop()
                        if not (scale and scale > 0 and fl and ft) then return { newRow = true } end
                        local mx, my = GetCursorPosition()
                        mx, my = mx / scale, my / scale
                        local liveRows = obj.layoutRows or {}
                        local nRows = #liveRows
                        -- Row band under the cursor (each row spans rowPitch downward from the frame top).
                        local rowIdx = math.floor((ft - my - PAD) / rowPitch) + 1
                        if rowIdx > nRows then
                            -- Below the last row → a NEW row, UNLESS the last row is still empty (then just
                            -- target that empty row — no point forcing a second empty row below it).
                            if nRows >= 1 and #(liveRows[nRows] or {}) == 0 then return { row = nRows, col = 0 } end
                            return { newRow = true }
                        end
                        if rowIdx < 1 then rowIdx = 1 end
                        local rowTiles = liveRows[rowIdx] or {}
                        -- maxPerRow: a full row can't take another (the dragged icon's OWN row is short one,
                        -- so reordering within a full row still works). Flag it so relayout shows "Row is full".
                        if #rowTiles >= per then return { row = rowIdx, full = true } end
                        -- Insertion column = number of slots whose CENTRE is left of the cursor (geometry).
                        local col = 0
                        while col < #rowTiles and (fl + PAD + col * STEP + ICON / 2) < mx do col = col + 1 end
                        return { row = rowIdx, col = col }
                    end

                    -- Reflow the 2D grid: lay the (non-dragged) tiles out row by row from I.GroupRows. If a
                    -- hole-dest is given, open a one-cell gap at (row, col) (an extra trailing row for
                    -- newRow). Position the per-row end "+" after each non-full row, and the new-row "+"
                    -- below the last row. tileBySid lets us resolve a row's spellId to its tile frame.
                    function obj.relayout(dragSpell, hole)
                        local tileBySid = {}
                        for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then tileBySid[t.spellId] = t end end

                        local holeRow, holeCol, forceNewRow, fullRow
                        if type(hole) == "table" then
                            if hole.newRow then forceNewRow = true
                            elseif hole.full then fullRow = hole.row
                            else holeRow, holeCol = hole.row, hole.col end
                        end

                        local dragging = dragSpell ~= nil
                        -- The stored row the dragged icon came from — counted as still present in that row
                        -- so lifting an icon from a FULL row never pops its "+" (you may drop it right back).
                        local draggedRow
                        if dragSpell then
                            for ri, rowSids in ipairs(groupRows) do
                                for _, sid in ipairs(rowSids) do if sid == dragSpell then draggedRow = ri; break end end
                                if draggedRow then break end
                            end
                        end

                        -- Position the real rows (one per stored row), opening a one-cell GAP at the hole:
                        -- the gap reserves an empty slot so the tiles after it visibly shift to show where
                        -- the dragged icon will land (no marker needed now the slot lines up with the drop).
                        obj.layoutRows = {}
                        for ri, rowSids in ipairs(groupRows) do
                            local liveSids = {}
                            for _, sid in ipairs(rowSids) do
                                if sid ~= dragSpell and tileBySid[sid] then liveSids[#liveSids + 1] = sid end
                            end
                            local gapCol
                            if holeRow == ri then
                                if holeCol == nil or holeCol > #liveSids then gapCol = #liveSids
                                else gapCol = math.max(0, holeCol) end
                            end
                            -- Output cells = the live tiles with a one-slot GAP inserted at 0-based column
                            -- `gapCol` (the empty slot the dragged icon drops into — MoveBuff inserts at that
                            -- same 0-based col, so the visible shift lines up with the real landing).
                            local cells = {}
                            for i = 1, #liveSids do cells[i] = liveSids[i] end
                            if gapCol then table.insert(cells, gapCol + 1, false) end   -- false = the gap
                            local liveRow = {}
                            for c0 = 1, #cells do
                                local cell = cells[c0]
                                if cell ~= false then   -- a `false` cell is the gap: leave that column empty
                                    local t = tileBySid[cell]
                                    placeCell(t.frame, ri - 1, c0 - 1); t.frame:Show()
                                    liveRow[#liveRow + 1] = t
                                end
                            end
                            obj.layoutRows[#obj.layoutRows + 1] = liveRow
                            placeRowLabel(ri - 1, L["Row %d"]:format(ri))   -- "Row N" caption above the row
                            SetRowFull(ri - 1, fullRow == ri)               -- red "Row is full" while hovered
                            -- End-of-row "+" — kept visible during a drag too. The row counts the LIFTED
                            -- icon as still its own (draggedRow), so a full row you're reordering within
                            -- never pops a "+". Positioned after the live cells (incl. the gap).
                            local at = ensureRowAddTile(ri - 1)
                            local rowCount = #liveRow + ((draggedRow == ri) and 1 or 0)
                            if rowCount < per then placeCell(at, ri - 1, #cells); at:Show()
                            else at:Hide() end
                        end
                        if #obj.layoutRows == 0 then obj.layoutRows[1] = {} end
                        local nRows = #obj.layoutRows

                        -- Hide any stale end-"+" / captions / full-labels beyond the live row count.
                        for rk, t in pairs(obj.addTiles) do if rk + 1 > nRows then t:Hide() end end
                        for rk, fs in pairs(obj.rowLabels) do if rk + 1 > nRows then fs:Hide() end end
                        for rk, fs in pairs(obj.fullLabels) do if rk + 1 > nRows then fs:Hide() end end

                        -- New-row "+": below the last row — but ONLY when that last row already has icons.
                        -- An empty last row (e.g. a brand-new group) already accepts the next icon via its
                        -- own row "+", so a second "+" below it is pointless. On a forced new row the icon
                        -- lands at col 0, so SHIFT the "+" right to col 1.
                        -- Use the STORED last row (the dragged icon still belongs to it) so the new-row "+"
                        -- doesn't vanish while you drag the last row's only icon out of it.
                        local lastEmpty = #(groupRows[#groupRows] or {}) == 0
                        if lastEmpty then
                            obj.newRowTile:Hide()
                        else
                            placeCell(obj.newRowTile, nRows, forceNewRow and 1 or 0)
                            obj.newRowTile:Show()
                        end
                    end

                    obj.relayout(nil, nil)

                    -- Height: each captioned row band + one trailing band for the new-row "+".
                    local nRows = math.max(1, #obj.layoutRows)
                    local h = PAD * 2 + (nRows + 1) * rowPitch
                    host:SetHeight(h)
                    return { frame = host, height = h }
                end,
            }
        end

        -- ── Per-group Icon size (W / H) ────────────────────────────────────────────
        -- Group icon size (W/H) — the shared IC.IconSize fed a plain group bundle (no override
        -- toggle); IconsGroup prints its own "Icon size" label above, so opts.label = false.
        local function IconSizeEntry(id)
            return IC.IconSize({
                get   = function(key) return I.GGet(id, key) end,
                set   = function(key, val) I.GSet(id, key, val) end,
                touch = touch,
            }, { bare = true, label = false, kw = "iconW", kh = "iconH", max = 256 })
        end

        local function GroupBundle(id)
            return {
                get   = function(key) return I.GGet(id, key) end,
                set   = function(key, val) I.GSet(id, key, val) end,
                reset = nil,
                touch = touch,
                refresh = rebuild,
            }
        end

        -- Light vs full menu re-render for the shared Border/Glow cadres in the GROUP panel:
        -- a checkbox toggle re-greys via Refresh; a glow-type change rebuilds so the colour
        -- picker's `when` re-evaluates (mirrors what these inline cadres did before).
        local groupCtx = {
            refresh = function() if menu then menu.Refresh() end end,
            rebuild = function() if menu then menu.Rebuild() end end,
        }

        -- The X / Y numeric inputs + Unlock/Lock toggle (the `position` widget). Lives at the TOP of the
        -- Position sub-cadre now. Drag writes posX/posY (the group's screen-center offset).
        local function PositionBlock(id)
            return { type = "position", ref = "pe",
                onBuilt = function(w) I.pe[id] = w end,
                label = L["Position (offset from screen center)"],
                getX = function() return I.GGet(id, "posX") end,
                getY = function() return I.GGet(id, "posY") end,
                onApply = function(x, yv)
                    if x  then I.GSet(id, "posX", x)  end
                    if yv then I.GSet(id, "posY", yv) end
                    touch()
                end,
                onUnlock   = function() I.SetGroupUnlocked(id, true) end,
                onLock     = function() I.SetGroupUnlocked(id, false); if I.pe[id] then I.pe[id].Refresh() end end,
                isUnlocked = function() return I.IsGroupUnlocked(id) end }
        end

        -- The CDM settings sub-cadre (FIRST in Group settings): the two CDM-display toggles (press overlay
        -- + keybinds), then the group LAYOUT controls (grow direction, static display, spacing). Those
        -- three are per-GROUP (the engine reads them per group in RefreshLayout), so they live here, not in
        -- the per-icon override editor.
        local function CDMSettingsGroup(id)
            return { type = "group", title = L["CDM settings"], build = function() return {
                { type = "checkbox", label = L["Show press overlay"],
                  get = function() return I.GGet(id, "showPressOverlay") == true end,
                  set = function(v) I.GSet(id, "showPressOverlay", v and true or false); touch() end },
                { type = "checkbox", label = L["Show Keybinds"],
                  get = function() return I.GGet(id, "showKeybinds") == true end,
                  set = function(v) I.GSet(id, "showKeybinds", v and true or false); touch() end },
                { type = "dropdown", label = L["Grow direction"], width = 180, height = 50,
                  getList = GrowList,
                  getCurrentKey = function() return GrowLabel(I.GGet(id, "growDir")) end,
                  onSelect = function(label) I.GSet(id, "growDir", GrowFromLabel(label)); touch() end },
                { type = "checkbox", label = L["Static Display"],
                  get = function() return I.GGet(id, "staticDisplay") == true end,
                  set = function(v) I.GSet(id, "staticDisplay", v and true or false); touch() end },
                { type = "textinput", label = L["Spacing"], width = 46, numeric = true, min = 0, max = 64, maxLetters = 2,
                  get = function() return I.GGet(id, "spacing") or 1 end,
                  set = function(v) if v ~= nil then I.GSet(id, "spacing", v); touch() end end },
            } end }
        end

        -- The Rows sub-cadre: "Max icon per row" → the group's maxPerRow. Changing it re-chunks the strip
        -- + the in-game layout (rebuild re-derives I.GroupRows). 1..20.
        local function RowsGroup(id)
            return { type = "group", title = L["Rows"], build = function() return {
                { type = "textinput", label = L["Max icon per row"], width = 46, numeric = true, min = 1, max = 20, maxLetters = 2,
                  get = function() return I.GGet(id, "maxPerRow") or 6 end,
                  set = function(v) if v and v >= 1 then I.GSet(id, "maxPerRow", math.floor(v)); touch(); rebuild() end end },
            } end }
        end

        -- The Position sub-cadre: just X/Y(/Unlock). Grow direction / Static Display / Spacing moved up to
        -- the CDM settings sub-cadre. NO "Anchor to" / Placement dropdowns (groups are screen-center).
        local function PositionGroup(id)
            return { type = "group", title = L["Position"], build = function() return {
                PositionBlock(id),
            } end }
        end

        -- Group Border / Glow — shared IC builders fed a plain group bundle. Border default ON
        -- (~= false); Glow = proc variant (type dropdown + colour hidden for proc/button looks).
        local function BorderGroup(id) return IC.Border(GroupBundle(id), { defaultOn = true, ctx = groupCtx }) end
        local function GlowGroup(id)   return IC.Glow(GroupBundle(id), { variant = "proc", ctx = groupCtx }) end

        local function IconsGroup(id)
            return { type = "group", title = L["Icons"], build = function()
                local b = GroupBundle(id)
                return {
                    { type = "label", font = "UnbunkUtilityH6", height = 18, text = L["Icon size"] },
                    IconSizeEntry(id),
                    TimerSection(b),
                    TitleSection(b),
                    StacksSection(b, { cd = true }),
                }
            end }
        end

        local function GroupSettingsSection(id)
            return { type = "section", label = L["Group settings"], showCheckbox = false,
              headerExtra = ns.ui.SettingsHeaderIcon,
              getCollapsed = function() return I.GGet(id, "cfgCollapsed") ~= false end,
              onCollapse   = function(c)
                  I.GSet(id, "cfgCollapsed", c and true or false)
                  if C_Timer and C_Timer.After then C_Timer.After(0, rebuild) else rebuild() end
              end,
              build = function() return {
                CDMSettingsGroup(id),
                RowsGroup(id),
                PositionGroup(id),
                BorderGroup(id),
                GlowGroup(id),
                IconsGroup(id),
            } end }
        end

        local function GroupCadre(id)
            local title = (I.GGet(id, "name") or ("Group " .. id))
            return { type = "group", title = title, build = function()
                local e = {
                    { type = "textinput", label = L["Group name"], width = 200, maxLetters = 32,
                      get = function() return I.GGet(id, "name") or "" end,
                      set = function(v) I.GSet(id, "name", v or ""); rebuild() end },
                    CDStripEntry(id),
                    { type = "button", label = L["Copy native CDM order"], width = 200, hostHeight = 30,
                      onClick = function() I.SortGroupNativeOrder(id); touch(); rebuild() end },
                    GroupSettingsSection(id),
                }
                if id ~= 1 then
                    e[#e + 1] = { type = "button", label = L["Delete group"], width = 160, hostHeight = 30,
                        onClick = function() I.RemoveGroup(id); touch(); rebuild() end }
                end
                return e
            end }
        end

        local function UnusedCadre()
            return { type = "group", title = L["Unused"], build = function() return {
                { type = "label", font = "UnbunkUtilityH6", height = 18,
                  text = L["Cooldowns here are hidden. Drag them onto a group to show them."] },
                CDStripEntry(0),
            } end }
        end

        local options = {
            { type = "label", font = "UnbunkUtilityH2", height = 26, text = titleText },
            -- The engine enable, OUTSIDE the cadre. Default ON. Greys the whole cadre below when off;
            -- Refresh() re-applies on toggle, forcing a CDMAnchor refresh so the OLD bucket system
            -- releases / re-takes the Essential viewer immediately.
            { type = "checkbox", label = enableLabel,
              get = function() return I.Enabled() end,
              set = function(v)
                  I.SetEnabled(v)
                  if I.HookNativeViewer then I.HookNativeViewer() end
                  touch()
                  -- Drive OUR engine on the toggle: enabling re-pins/re-styles; disabling runs HideAll
                  -- which releases our pins AND restores the native viewer (M1 — otherwise Unused
                  -- members pinned offscreen stay there until Blizzard next relayouts).
                  if I.RefreshLayout then I.RefreshLayout() end
                  if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                  if menu then menu.Refresh() end
              end },
            { type = "group", title = cadreTitle,
              enabledBy = function() return I.Enabled() end,
              build = function()
                wipe(strips)
                local entries = {}
                for _, g in ipairs(I.GroupList()) do
                    entries[#entries + 1] = GroupCadre(g.id)
                end
                entries[#entries + 1] = { type = "button", label = L["Create group"], width = 160, hostHeight = 30,
                    onClick = function() I.NewGroup(); touch(); rebuild() end }
                entries[#entries + 1] = UnusedCadre()
                return entries
            end },
        }

        menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })

        -- When the user edits the CDM tracked cooldowns in EditMode the engine's ticker / viewer hook
        -- detects the DISPLAYED-set (pool) change and calls this. Rebuild the strip so a tile's red flag
        -- + its tooltip's red line re-evaluate (both derive from I.DisplayedKnown()/I.IsDisplayed), and
        -- re-open the per-icon editor for the same icon if it's open. Cheap no-op when the panel isn't
        -- shown (the engine only fires this on an actual change, never every tick). Mirrors BuffGroups.
        I.onDisplayedChanged = function()
            if menu and parent and parent:IsShown() then rebuild() end
            if iconEditor and iconEditor.frame and iconEditor.frame:IsShown()
                and editingI == I and editingSid then
                OpenIconEditor(I, editingSid, onIconEditChange)
            end
        end

        parent:HookScript("OnHide", function()
            for _, g in ipairs(I.GroupList()) do
                I.GSet(g.id, "cfgCollapsed", true)
            end
        end)
        parent:HookScript("OnShow", function()
            if menu then menu.Rebuild() end
        end)

        return menu
    end
end

UnbunkUtility.OnAddonLoaded(function()
    local E = ns.CDMGroups and ns.CDMGroups.essential
    if E then
        -- ESSENTIAL groups tab: registered as L["Essential"] (distinct from the OLD bucket panel's
        -- L["Essentials"], so no clash) — the nav points its single "Essential" entry here.
        UnbunkUtility.RegisterModule(
            L["Essential"], nil,
            CreatePanel(E, L["Essential"], L["Enable custom CDM Essential"], L["Cooldown groups"]))
    end
    local U = ns.CDMGroups and ns.CDMGroups.utility
    if U then
        -- UTILITY groups tab. Unlike Essential there's no spare plural to avoid the name clash with the
        -- OLD bucket panel (also L["Utility"]). CDMGroups loads AFTER GeneralSettings (see the .toc), so
        -- registering under L["Utility"] here SUPERSEDES the old bucket panel in the registry — exactly
        -- the intent: the nav's single { panel = L["Utility"] } entry now resolves to THIS groups panel
        -- (the old bucket createFn is harmlessly dropped; nothing else references it). The CDMGroups
        -- engine OwnsDest("utility") so the old CDMAnchor utility bucket yields automatically.
        UnbunkUtility.RegisterModule(
            L["Utility"], nil,
            CreatePanel(U, L["Utility"], L["Enable custom CDM Utility"], L["Cooldown groups"]))
    end
end)
