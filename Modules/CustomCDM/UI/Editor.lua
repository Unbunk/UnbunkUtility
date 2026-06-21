-- Modules/CustomCDM/UI/Editor.lua
-- The per-icon editor window opened by a custom CDM icon's "pen" control. A movable,
-- scrollable popup hosting a ns.ui.BuildMenu scoped to one icon's config entry (read
-- via ns.CustomCDM.Get / written via ns.CustomCDM.Set, which re-applies the icon live):
-- Spell (ID or name), Timer (show + text style + configurable time thresholds), Title
-- (show + text + anchor + style), Stacks (show + show-at-0 + anchor + style), Border,
-- Icon size, and Sound alerts (on use / when ready).

local ADDON, ns = ...
local L  = ns.L
local CC = ns.CustomCDM

local editor      -- singleton { frame, scroll, content, sb, menu } for the Spell/Item editor
local buffEditor  -- singleton for the dedicated Buff-icon editor (same scaffolding, buff option tree)
local choiceWin   -- the Free-icons "+" chooser (Spell/Item vs Buff), built lazily
-- The id each window is currently editing lives on its own `ed.currentId` (set by OpenEditorWindow).

-- ── Cadre builders (each returns a BuildMenu group entry, bound to an icon id) ─
-- The spell/item-id input row + its Add / Modify / Delete lifecycle buttons. Shared by the
-- Spell/Item group and the Buff group — `entryKind` (spell/item/buff) drives which value it shows
-- (buff resolves as a spell, so the same row works for it).
-- Shared async hook: GET_ITEM_INFO_RECEIVED re-runs the current spell/item field's live feedback once a
-- not-yet-cached item's name arrives (only one editor field is live at a time, so one pending callback).
local itemInfoListener, pendingItemCheck
local function ensureItemInfoListener()
    if itemInfoListener then return end
    itemInfoListener = CreateFrame("Frame")
    itemInfoListener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    -- Capture-and-nil: fire the pending recheck ONCE per request, not on every game-wide item event
    -- (GET_ITEM_INFO_RECEIVED fires constantly from bags/tooltips). The recheck re-arms itself only if the
    -- field is still showing "…", so a resolved/closed field stops re-running.
    itemInfoListener:SetScript("OnEvent", function()
        local cb = pendingItemCheck; pendingItemCheck = nil
        if cb then cb() end
    end)
end

local function SpellInputEntry(id, rebuild)
    -- spell / item / buff all resolve to a spell or item id/name, so they share ONE layout: a grey H6 hint,
    -- the id/name input + lifecycle buttons, and a live green/red match feedback line under the field.
    return { type = "custom", height = 64, build = function(host)
        local function curId()
            return (CC.Get(id, "entryKind") == "item") and CC.Get(id, "itemId") or CC.Get(id, "spellId")
        end
        -- The input shows the current spell/item id, or BLANK for a not-yet-set draft.
        local function spellText()
            local rawId = curId()
            return (rawId and rawId ~= 0) and tostring(rawId) or ""
        end

        -- Row 1: a grey H6 hint above the field. A buff resolves as a spell, so it reads "Spell ID or name".
        local fbFS
        local hintFS = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
        hintFS:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        hintFS:SetTextColor(0.6, 0.6, 0.6)
        local function setHint()
            hintFS:SetText(CC.Get(id, "entryKind") == "item" and L["Item ID or name"] or L["Spell ID or name"])
        end

        local input  -- forward-declared so updateFeedback can read the live field text
        -- Live match feedback (spell/item/buff), refreshed on every keystroke: green = the resolved spell/
        -- item name, red = "No match"; "…" while an item's name is still loading from the server.
        local function updateFeedback()
            if not fbFS then return end
            local text = strtrim(input and input.GetText() or "")
            if text == "" then fbFS:SetText(""); return end
            local q = tonumber(text) or text
            if CC.Get(id, "entryKind") == "item" then
                local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(q)
                if name then
                    fbFS:SetTextColor(0.35, 0.9, 0.35); fbFS:SetText(name); pendingItemCheck = nil
                else
                    -- GetItemInfoInstant resolves an id/itemString/link (NOT a plain name); a not-yet-cached
                    -- item name therefore reads as "No match" (same limit as the commit path's ResolveItem).
                    local iid = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(q)
                    if iid then
                        -- Valid item id, name not cached yet: show "…" and re-check on GET_ITEM_INFO_RECEIVED.
                        fbFS:SetTextColor(0.6, 0.6, 0.6); fbFS:SetText("…")
                        pendingItemCheck = updateFeedback; ensureItemInfoListener()
                        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(iid) end
                    else
                        fbFS:SetTextColor(0.95, 0.3, 0.3); fbFS:SetText(L["No match"])
                    end
                end
            else
                -- One-shot GetSpellInfo (same check the commit path uses). A valid spell outside the
                -- spellbook can briefly read nil right after /reload → "No match" until the next keystroke
                -- re-runs this; acceptable for purely cosmetic feedback.
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(q)
                if info and info.name then
                    fbFS:SetTextColor(0.35, 0.9, 0.35); fbFS:SetText(info.name)
                else
                    fbFS:SetTextColor(0.95, 0.3, 0.3); fbFS:SetText(L["No match"])
                end
            end
        end

        -- A draft shows one "Add Icon" button; a committed icon shows "Modify icon" + "Delete icon".
        local addBtn, modBtn, delBtn
        local function updateBtns()
            local draft = CC.IsDraft(id)
            if addBtn then addBtn.frame:SetShown(draft) end
            if modBtn then modBtn.frame:SetShown(not draft) end
            if delBtn then delBtn.frame:SetShown(not draft) end
        end
        local function commitOrApply()
            local ok = true
            if CC.IsDraft(id) then ok = CC.CommitDraft(id) end
            updateFeedback()
            updateBtns()
            -- Rebuild the editor so a now-committed / re-resolved spell re-binds the cadres that key off it.
            if ok and rebuild then C_Timer.After(0, rebuild) end
        end

        -- The spell-id/name input + the lifecycle buttons.
        input = ns.ui.CreateTextInput({
            parent = host, width = 200, height = 22, maxLetters = 64,
            text = spellText(),
            onEnter = function(v) if CC.SetSpellInput(id, v) then commitOrApply() end end,
        })
        input.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -18)

        addBtn = ns.ui.CreateButton({ parent = host, width = 100, height = 22, label = L["Add Icon"],
            onClick = function() if CC.SetSpellInput(id, input.GetText() or "") then commitOrApply() end end })
        addBtn.frame:SetPoint("LEFT", input.frame, "RIGHT", 8, 0)
        modBtn = ns.ui.CreateButton({ parent = host, width = 100, height = 22, label = L["Modify icon"],
            onClick = function() if CC.SetSpellInput(id, input.GetText() or "") then commitOrApply() end end })
        modBtn.frame:SetPoint("LEFT", input.frame, "RIGHT", 8, 0)
        delBtn = ns.ui.CreateButton({ parent = host, width = 100, height = 22, label = L["Delete Icon"],
            onClick = function() CC.ConfirmRemove(id) end })
        delBtn.frame:SetPoint("LEFT", modBtn.frame, "RIGHT", 6, 0)

        fbFS = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
        fbFS:SetPoint("TOPLEFT", input.frame, "BOTTOMLEFT", 0, -4)
        fbFS:SetJustifyH("LEFT")
        input.editBox:HookScript("OnTextChanged", function() updateFeedback() end)
        setHint(); updateFeedback()

        updateBtns()
        return { frame = host, height = 64, Refresh = function()
            input.SetText(spellText())
            updateBtns()
            setHint(); updateFeedback()
        end }
    end }
end

local function SpellGroup(id, rebuild)
    return { type = "group", title = L["Spell / Item"], build = function() return {
            -- Kind: track a Spell or an Item (on-use trinket / potion). Changing it re-renders the cadre so
            -- the name + input reflect the new kind's value (each kind keeps its own id).
            { type = "dropdown", label = L["Kind"], width = 160, height = 50,
              getList = function() return { L["Spell"], L["Item"] } end,
              getCurrentKey = function() return (CC.Get(id, "entryKind") == "item") and L["Item"] or L["Spell"] end,
              onSelect = function(label)
                  CC.Set(id, "entryKind", (label == L["Item"]) and "item" or "spell")
                  if rebuild then rebuild() end
              end },
            SpellInputEntry(id, rebuild),
    } end }
end

local function SoundGroup(id, LSM)
    return { type = "group", title = L["Sound alert"], build = function() return {
        { type = "sound", LSM = LSM, label = L["Sound on use"],
          getKey    = function() return CC.Get(id, "soundKeyUse") end,
          getEnable = function() return CC.Get(id, "soundOnUse") end,
          onSelect  = function(key, path) CC.Set(id, "soundKeyUse", key); CC.Set(id, "soundPathUse", path) end,
          onToggle  = function(v) CC.Set(id, "soundOnUse", v) end,
          onTest    = function() CC.TestSound(id, "use") end },
        { type = "sound", LSM = LSM, label = L["Sound when ready"],
          getKey    = function() return CC.Get(id, "soundKeyReady") end,
          getEnable = function() return CC.Get(id, "soundOnReady") end,
          onSelect  = function(key, path) CC.Set(id, "soundKeyReady", key); CC.Set(id, "soundPathReady", path) end,
          onToggle  = function(v) CC.Set(id, "soundOnReady", v) end,
          onTest    = function() CC.TestSound(id, "ready") end },
    } end }
end

local function BorderGroup(id, refresh, whenFn)
    return { type = "group", title = L["Border"], when = whenFn, build = function() return {
        { type = "checkbox", label = L["Show border"],
          get = function() return CC.Get(id, "borderEnabled") == true end,
          set = function(v) CC.Set(id, "borderEnabled", v); refresh() end },
        { type = "textEditor", label = L["Border color"],
          enabledBy = function() return CC.Get(id, "borderEnabled") == true end,
          showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
          getColor = function() return CC.Get(id, "borderColor") end,
          onColorChange = function(r, g, b, a) CC.Set(id, "borderColor", { r = r, g = g, b = b, a = a }) end },
        { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
          enabledBy = function() return CC.Get(id, "borderEnabled") == true end,
          get = function() return CC.Get(id, "borderSize") or 1 end,
          set = function(v) if v and v > 0 then CC.Set(id, "borderSize", v) end end },
    } end }
end

-- Placement sub-cadre: WHERE the icon lives — Include-in-CDM + (when in CDM) the Anchor-to dest. The
-- free-look and in-CDM override appearance are the two collapsible sections below it (SpellCdmCadres).
local function PlacementGroup(id, rebuild)
    return { type = "group", title = L["Placement"], build = function() return {
        { type = "checkbox", label = L["Include in cdm"],
          disabled = function() return not ns.IsCDMEnabled() end,
          get = function() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          set = function(v)
              CC.Set(id, "includeInCdm", v)
              rebuild()
              if ns.RebuildActiveModule then ns.RebuildActiveModule() end
          end },
        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
          when = function() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
          getList = function() return ns.CDMDestList() end,
          -- CC.Get/Set take an extra `id`; adapt them to the (key)/(key,val) signatures
          -- the central choice helpers expect.
          getCurrentKey = function() return ns.CDMDestChoiceLabel(function(k) return CC.Get(id, k) end) end,
          onSelect = function(label)
              ns.CDMApplyDestChoice(label, function(k, v) CC.Set(id, k, v) end)
              rebuild()
              if ns.RebuildActiveModule then ns.RebuildActiveModule() end
          end },
    } end }
end

-- EditorOptions (Spell/Item) is defined further down, after the shared FreeLookCadres + collapsed-state
-- helpers + SpellCdmCadres it depends on.

-- ── Buff editor (entryKind == "buff") ─────────────────────────────────────────
-- A cast-triggered, fixed-duration buff. Same layout as the addon trackers: Spell + Duration, Sound,
-- then Icon { Placement (Include-in-CDM only, no Anchor-to — a buff can only go to the Buffs viewer),
-- Override settings (the BuffGroups per-icon override on the bridged mirror), Free icon settings }.
-- No Stacks (a cast-triggered buff has no charges).
local function BuffSpellGroup(id, rebuild)
    return { type = "group", title = L["Buff"], build = function() return {
        SpellInputEntry(id, rebuild),
        { type = "textinput", label = L["Duration (s)"], width = 80, numeric = true, min = 1, max = 3600, maxLetters = 4,
          get = function() return CC.Get(id, "duration") or 30 end,
          set = function(v) if v and v > 0 then CC.Set(id, "duration", v) end end },
    } end }
end

-- A small grey header note ("(When in CDM)") after a section title, keeping the gear glyph far-right.
local function HeaderHint(text)
    return function(headerBtn, headerLabel)
        local fs = headerBtn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
        fs:SetPoint("LEFT", headerLabel, "RIGHT", 6, 0)
        fs:SetText(text); fs:SetTextColor(0.6, 0.6, 0.6)
        if ns.ui.SettingsHeaderIcon then ns.ui.SettingsHeaderIcon(headerBtn) end
    end
end

-- Collapsed-state on the icon entry (default collapsed; written WITHOUT CC.Set so toggling a cadre
-- doesn't re-apply the whole icon). Shared by both editors.
local function GetCollapsed(id, key) return CC.Get(id, key) ~= false end
local function SetCollapsed(id, key, c)
    local e = CC.GetEntry(id); if e then e[key] = c and true or false end
end
local function DeferRebuild(rebuild)
    if C_Timer and C_Timer.After then C_Timer.After(0, rebuild) else rebuild() end
end

-- Placement sub-cadre for a buff: just WHERE it lives. A buff can only go to the Buffs viewer (no
-- "Anchor to"); ticking Include-in-CDM mirrors it into a Buff-groups group, unticking frees it.
local function BuffPlacementGroup(id, rebuild)
    local function inCdm() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end
    return { type = "group", title = L["Placement"], build = function() return {
        { type = "checkbox", label = L["Include in cdm"],
          disabled = function() return not ns.IsCDMEnabled() end,
          get = function() return inCdm() end,
          set = function(v)
              CC.Set(id, "includeInCdm", v)
              rebuild()
              if ns.RebuildActiveModule then ns.RebuildActiveModule() end
          end },
        { type = "label", font = "UnbunkUtilityH6", height = 30, color = { 0.6, 0.6, 0.6 },
          when = inCdm,
          text = L["Shown in the Buffs viewer (Buff groups). Set its in-CDM look in Override settings."] },
    } end }
end

-- A W/H "Icon size" custom row for a free icon (size is seeded per kind: spell/item 44, buff 36).
local function FreeSizeCustom(id)
    return { type = "custom", height = 46, build = function(host)
        local sLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
        sLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sLbl:SetText(L["Icon size"])
        local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
        wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20); wLbl:SetText(L["W"])
        local wInput = ns.ui.CreateTextInput({
            parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
            text = tostring(CC.Get(id, "iconWidth") or 44),
            onEnter = function(v) if v and v > 0 then CC.Set(id, "iconWidth", v) end end,
        })
        wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
        local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
        hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
        local hInput = ns.ui.CreateTextInput({
            parent = host, width = 46, height = 22, numeric = true, min = 8, max = 512, maxLetters = 3,
            text = tostring(CC.Get(id, "iconHeight") or 44),
            onEnter = function(v) if v and v > 0 then CC.Set(id, "iconHeight", v) end end,
        })
        hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
        return { frame = host, height = 46, Refresh = function()
            wInput.SetText(tostring(CC.Get(id, "iconWidth") or 44))
            hInput.SetText(tostring(CC.Get(id, "iconHeight") or 44))
        end }
    end }
end

-- Glow cadre for a free icon. kind "proc" = spell/item glow-ON-PROC (Show + type + colour; rendered by
-- TimerIcon.ApplyDestGlow on a Blizzard spell-activation proc). kind "active" = buff while-active glow
-- (Show + colour, no type; rendered by TimerIcon.SetColorGlow while the swipe runs).
local function FreeGlowGroup(id, refresh, rebuild, kind)
    return { type = "group", title = L["Glow"], build = function()
        local e = {
            { type = "checkbox", label = (kind == "proc") and L["Show glow on proc"] or L["Show glow"],
              get = function() return CC.Get(id, "glowEnabled") == true end,
              set = function(v) CC.Set(id, "glowEnabled", v and true or false); refresh() end },
        }
        if kind == "proc" then
            local CDG = ns.CDMGroups
            e[#e + 1] = { type = "dropdown", label = L["Glow type"], width = 200, height = 50,
              enabledBy = function() return CC.Get(id, "glowEnabled") == true end,
              getList = function() return (CDG and CDG.GlowTypeList and CDG.GlowTypeList()) or {} end,
              getCurrentKey = function() return CDG and CDG.GlowTypeLabel and CDG.GlowTypeLabel(CC.Get(id, "glowType")) end,
              onSelect = function(label)
                  CC.Set(id, "glowType", (CDG and CDG.GlowTypeFromLabel and CDG.GlowTypeFromLabel(label)) or "pixel")
                  rebuild()   -- rebuild so the colour swatch's `when` re-evaluates for the new type
              end }
        end
        e[#e + 1] = { type = "textEditor", label = L["Glow color"],
          showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
          -- button/proc glows are a fixed native look that ignores colour (mirror the Override cadre):
          -- hide the swatch for those, always show it for the buff "active" glow.
          when = (kind == "proc") and function()
              local gt = CC.Get(id, "glowType"); return gt ~= "proc" and gt ~= "button"
          end or nil,
          enabledBy = function() return CC.Get(id, "glowEnabled") == true end,
          getColor = function() return CC.Get(id, "glowColor") end,
          onColorChange = function(r, g, b, a) CC.Set(id, "glowColor", { r = r, g = g, b = b, a = a }) end }
        return e
    end }
end

-- "CDM settings" cadre (spell/item free icons only): the same Cooldown-Manager-bar integration the addon
-- trackers expose — flash the icon while its action-bar keybind is HELD (press overlay) and draw that
-- keybind's text on the icon. Both opt-in (default off); rendered by TimerIcon.ApplyKeybind reading these
-- keys from the icon's own config (see the free branch of CdmFlag).
local function FreeCdmGroup(id)
    return { type = "group", title = L["CDM settings"], build = function() return {
        { type = "checkbox", label = L["Show press overlay"],
          get = function() return CC.Get(id, "showPressOverlay") == true end,
          set = function(v) CC.Set(id, "showPressOverlay", v and true or false) end },
        { type = "checkbox", label = L["Show Keybinds"],
          get = function() return CC.Get(id, "showKeybinds") == true end,
          set = function(v) CC.Set(id, "showKeybinds", v and true or false) end },
    } end }
end

-- The "Free icon settings" cadres for a custom icon: Position → [CDM settings (spell/item)] → Border →
-- Glow → Icon { size + the SHARED CDMGroups Timer/Title/Stacks sections } — same rich structure
-- (Style → Anchor, timer threshold toggle) as the Override cadres, bound here to the icon's OWN CC config
-- (no override store → no "Override group settings" box; each section's show-checkbox greys its controls).
-- The render reads this same schema (timerPos / timerThresholds(+Enabled) via TimerIcon; titlePos /
-- stackPos via ApplyTitle/ApplyStack). opts.glow = "proc" (spell/item) | "active" (buff); opts.cdm adds
-- the CDM settings cadre (spell/item).
local function FreeLookCadres(id, rebuild, refresh, LSM, opts)
    opts = opts or {}
    local bundle = {
        get     = function(k) return CC.Get(id, k) end,
        set     = function(k, v) local e = CC.GetEntry(id); if e then e[k] = v end end,
        touch   = function() CC.ApplyIcon(id) end,
        refresh = rebuild,
    }
    local function sections()
        local CDG = ns.CDMGroups
        if not (CDG and CDG.TimerSection and CDG.TitleSection and CDG.StacksSection) then return {} end
        return { CDG.TimerSection(bundle), CDG.TitleSection(bundle), CDG.StacksSection(bundle) }
    end
    local pe   -- free-mode position editor widget (captured via onBuilt)
    local out = {
        { type = "position", ref = "pe",
          onBuilt = function(w) pe = w end,
          label = L["Icon position (offset from screen center)"],
          getX = function() return CC.Get(id, "posX") end,
          getY = function() return CC.Get(id, "posY") end,
          onApply = function(x, yv)
              if x  then CC.Set(id, "posX", x)  end
              if yv then CC.Set(id, "posY", yv) end
          end,
          onUnlock = function() CC.SetUnlocked(id, true) end,
          onLock   = function() CC.SetUnlocked(id, false); if pe then pe.Refresh() end end,
          isUnlocked = function() return CC.IsUnlocked(id) end },
    }
    if opts.cdm then out[#out + 1] = FreeCdmGroup(id) end   -- above Border (spell/item)
    out[#out + 1] = BorderGroup(id, refresh)
    out[#out + 1] = FreeGlowGroup(id, refresh, rebuild, opts.glow or "active")
    out[#out + 1] = { type = "group", title = L["Icon"], build = function()
        local e = { FreeSizeCustom(id) }
        for _, x in ipairs(sections()) do e[#e + 1] = x end
        return e
    end }
    return out
end

-- The Override settings + Free icon settings collapsible pair for a BUFF (mirror of the tracker
-- TrackerCdmCadres, but the in-CDM override is the BuffGroups per-icon store on the bridged mirror,
-- keyed by the buff's spellId — read live since the spell is editable).
local function BuffCdmCadres(id, rebuild, refresh, LSM)
    -- Gate on whether the mirror is the LIVE render owner (CC.BuffMirrored), not the bare includeInCdm:
    -- a buff in Unused / with no spell / with BuffGroups off renders FREE, so the Free section governs.
    local function mirrored() return CC.BuffMirrored and CC.BuffMirrored(id) and true or false end
    return {
        { type = "label", font = "UnbunkUtilityH6", height = 18, color = { 0.6, 0.6, 0.6 },
          when = function() return not mirrored() end,
          text = L["Check Free icon settings to setup icon"] },

        -- Override = the buff's in-CDM (Buff groups) look. Gated on `mirrored`: editable ONLY when the buff
        -- is actually mirrored into a group; otherwise the cadres still SHOW (greyed-out preview) so you can
        -- see the look before committing. With no resolved spell we preview the group defaults (sid 0 →
        -- GROUP_TEMPLATE via IconGet/GGet); the gate keeps it read-only, so iconCfg[0] is never written
        -- (a spell-less buff can't be mirrored, hence is always gated off).
        { type = "section", label = L["Override settings"], showCheckbox = false,
          headerExtra = HeaderHint(L["(When in CDM)"]),
          gate = { enabled = mirrored },
          getCollapsed = function() return GetCollapsed(id, "ovCollapsed") end,
          onCollapse   = function(c) SetCollapsed(id, "ovCollapsed", c); DeferRebuild(rebuild) end,
          build = function()
              local BG  = ns.BuffGroups
              if not (BG and BG.IconOverrideSections and BG.MakeIconBundle) then
                  return { { type = "label", font = "UnbunkUtilityBody", height = 36,
                      text = L["These apply when the buff is shown in the Buffs viewer (Buff groups)."] } }
              end
              local sid = CC.Get(id, "spellId") or 0
              local function touch() if BG.ApplyAll then BG.ApplyAll() end end
              local bundle = BG.MakeIconBundle(sid, touch, rebuild)
              return BG.IconOverrideSections(sid, bundle, {
                  omit = { label = true, sound = true, placeholder = true },
                  touch = touch, rebuild = rebuild, refreshLight = refresh,
              })
          end },

        { type = "section", label = L["Free icon settings"], showCheckbox = false,
          headerExtra = HeaderHint(L["(When not in CDM)"]),
          gate = { enabled = function() return not mirrored() end },
          getCollapsed = function() return GetCollapsed(id, "freeCollapsed") end,
          onCollapse   = function(c) SetCollapsed(id, "freeCollapsed", c); DeferRebuild(rebuild) end,
          build = function() return FreeLookCadres(id, rebuild, refresh, LSM, { glow = "active" }) end },
    }
end

local function BuffEditorOptions(id, LSM, refresh, rebuild)
    return {
        { type = "label", font = "UnbunkUtilityH6", height = 30,
          text = L["A buff icon shows a fixed-duration swipe started by your own cast of the spell."] },
        BuffSpellGroup(id, rebuild),
        SoundGroup(id, LSM),
        { type = "group", title = L["Icon"],
          gate = { enabled = function() return CC.Get(id, "showIcon") ~= false end, master = "showicon" },
          build = function()
            local e = {
                { type = "checkbox", ref = "showicon", label = L["Show icon"],
                  get = function() return CC.Get(id, "showIcon") ~= false end,
                  set = function(v) CC.Set(id, "showIcon", v) end },
                { type = "checkbox", label = L["Only show when buff is active"],
                  get = function() return CC.Get(id, "onlyWhenActive") ~= false end,
                  set = function(v) CC.Set(id, "onlyWhenActive", v and true or false) end },
                BuffPlacementGroup(id, rebuild),
            }
            -- Override settings (in-CDM look via the BuffGroups mirror) + Free icon settings (free look).
            for _, x in ipairs(BuffCdmCadres(id, rebuild, refresh, LSM)) do e[#e + 1] = x end
            return e
          end },
    }
end

-- The Override settings + Free icon settings collapsible pair for a Spell/Item icon — reuses the addon
-- trackers' shared cadre pair (ns.CDMGroups.TrackerCdmCadres): Override = the per-icon CDMGroups/below
-- override (governs the in-CDM look once seeded+migrated; see CustomCDM.lua), Free = the CC free look.
local function SpellCdmCadres(id, rebuild, refresh, LSM)
    local function freeBuild() return FreeLookCadres(id, rebuild, refresh, LSM, { glow = "proc", cdm = true }) end
    if not (ns.CDMGroups and ns.CDMGroups.TrackerCdmCadres) then
        return freeBuild()   -- CDMGroups unavailable: just the free look
    end
    local fn = (CC.FrameName and CC.FrameName(id)) or ("UnbunkUtilityCustomCDM" .. id)
    return ns.CDMGroups.TrackerCdmCadres({
        frameName  = fn,
        getDest    = function() return CC.Get(id, "cdmDest") end,
        cdmAtEnd   = function() return CC.Get(id, "cdmAtEnd") end,
        inCdm      = function() return ns.CDMIncludedVal(CC.Get(id, "includeInCdm")) end,
        applyIcon  = function() CC.ApplyIcon(id) end,
        rebuild    = rebuild,
        seedValues = function() return ns.DefaultTrackerTimerSeed and ns.DefaultTrackerTimerSeed() or {} end,
        freeBuild  = freeBuild,
        getOv      = function() return GetCollapsed(id, "ovCollapsed") end,
        setOv      = function(c) SetCollapsed(id, "ovCollapsed", c) end,
        getFree    = function() return GetCollapsed(id, "freeCollapsed") end,
        setFree    = function(c) SetCollapsed(id, "freeCollapsed", c) end,
    })
end

-- Spell/Item editor option tree: Spell/Item, Sound, then Icon { Show icon, Placement, Override + Free }.
local function EditorOptions(id, LSM, refresh, rebuild)
    return {
        SpellGroup(id, rebuild),
        SoundGroup(id, LSM),
        { type = "group", title = L["Icon"],
          gate = { enabled = function() return CC.Get(id, "showIcon") ~= false end, master = "showicon" },
          build = function()
            local e = {
                { type = "checkbox", ref = "showicon", label = L["Show icon"],
                  get = function() return CC.Get(id, "showIcon") ~= false end,
                  set = function(v) CC.Set(id, "showIcon", v) end },
                PlacementGroup(id, rebuild),
            }
            for _, x in ipairs(SpellCdmCadres(id, rebuild, refresh, LSM)) do e[#e + 1] = x end
            return e
          end },
    }
end

-- ── Window scaffolding ────────────────────────────────────────────────────────
local EDITOR_BACKDROP = {
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- A white close cross that tints to the brand colour on hover, shared by every popup here.
local function AddCloseCross(parent, onClick)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -6, -6)
    local cb = close:CreateTexture(nil, "BACKGROUND"); cb:SetAllPoints(close); cb:SetColorTexture(0.4, 0.4, 0.4, 1)
    local cf = close:CreateTexture(nil, "BACKGROUND", nil, 1)
    cf:SetPoint("TOPLEFT", 1, -1); cf:SetPoint("BOTTOMRIGHT", -1, 1); cf:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    local cx = close:CreateTexture(nil, "OVERLAY"); cx:SetSize(12, 12); cx:SetPoint("CENTER"); cx:SetTexture(UNBUNK_ICON_CROSS_WHITE)
    close:SetScript("OnEnter", function() local r, g, b = ns.GetBrandColor(); cb:SetColorTexture(r, g, b, 1); cx:SetVertexColor(r, g, b) end)
    close:SetScript("OnLeave", function() cb:SetColorTexture(0.4, 0.4, 0.4, 1); cx:SetVertexColor(1, 1, 1) end)
    close:SetScript("OnClick", onClick)
    return close
end

-- Build a movable, scrollable editor window (one singleton per kind). `ed.currentId` (set by
-- OpenEditorWindow) is the icon being edited; OnHide re-locks its drag + drops an uncommitted draft.
local function BuildEditorWindow(globalName, titleText)
    local f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    f:SetSize(580, 600)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")          -- above the main config window; below TOOLTIP drop-frames
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop(EDITOR_BACKDROP)
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()
    tinsert(UISpecialFrames, globalName)   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText(titleText)

    local ed = { frame = f, title = title }
    AddCloseCross(f, function() f:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -44)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 10)
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
    -- Re-lock any free-drag unlock when the editor closes (mirrors the main window),
    -- and drop an uncommitted draft (the "+" was clicked but "Add Icon" never was).
    f:HookScript("OnHide", function()
        local id = ed.currentId
        if id then
            CC.SetUnlocked(id, false)
            if CC.IsDraft and CC.IsDraft(id) then CC.DiscardDraft(id) end
        end
    end)

    ed.scroll, ed.content, ed.sb = scroll, content, sb
    return ed
end

local function EnsureWindow()
    if not editor then editor = BuildEditorWindow("UnbunkUtilityCustomCDMEditor", L["Custom CDM icon"]) end
    return editor
end

local function EnsureBuffWindow()
    if not buffEditor then buffEditor = BuildEditorWindow("UnbunkUtilityCustomCDMBuffEditor", L["Buff icon"]) end
    return buffEditor
end

-- Tear down the previously-built menu's frames so a re-open (or another icon) starts clean.
local function ClearMenu(ed)
    if not ed.menu then return end
    if ed.menu.content then ed.menu.content:Hide(); ed.menu.content:ClearAllPoints(); ed.menu.content:SetParent(nil) end
    for _, fr in ipairs(ed.menu.auxFrames or {}) do fr:Hide(); fr:ClearAllPoints(); fr:SetParent(nil) end
    ed.menu = nil
end

-- Shared open routine: (re)build `optionsFn`'s option tree into `ed` and show it for icon `id`.
local function OpenEditorWindow(ed, id, optionsFn)
    if not CC.GetEntry(id) then return end
    ed.currentId = id
    -- Start the Override / Free collapsible sections collapsed on each open (mirrors the trackers'
    -- re-collapse-on-tab-show). Written directly on the entry so it doesn't re-apply the icon.
    do local e = CC.GetEntry(id); if e then e.ovCollapsed = true; e.freeCollapsed = true end end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

    local function syncHeight()
        if ed.menu then ed.content:SetHeight(math.max(1, ed.menu.height + 12)) end
        ed.sb.Update()
    end
    local function refresh() if ed.menu then ed.menu.Refresh() end end
    local function rebuild() if ed.menu then ed.menu.Rebuild() end; syncHeight() end

    ClearMenu(ed)
    ed.menu = ns.ui.BuildMenu(ed.content, optionsFn(id, LSM, refresh, rebuild), {
        gap = 10, width = 518, originX = 8, originY = 0, autoHook = false, LSM = LSM,
    })
    syncHeight()
    ed.menu.Refresh()

    ed.frame:Show()
    ed.frame:Raise()
    ed.scroll:SetVerticalScroll(0)
    C_Timer.After(0, function() ed.sb.Update() end)
end

function CC.OpenEditor(id)     OpenEditorWindow(EnsureWindow(),     id, EditorOptions)     end
function CC.OpenBuffEditor(id) OpenEditorWindow(EnsureBuffWindow(), id, BuffEditorOptions) end

-- Close whichever editor is currently showing the given icon (called when it is removed).
function CC.CloseEditorFor(id)
    for _, ed in ipairs({ editor, buffEditor }) do
        if ed and ed.currentId == id and ed.frame:IsShown() then ed.frame:Hide() end
    end
end

-- ── Free-icons "+" chooser: Spell/Item vs Buff ────────────────────────────────
-- A small movable dialog (brand close cross + ESC) routing to the two free-icon templates.
function CC.PromptAddFreeChoice()
    if not choiceWin then
        local f = CreateFrame("Frame", "UnbunkUtilityFreeIconChoice", UIParent, "BackdropTemplate")
        f:SetSize(320, 200)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)
        f:SetBackdrop(EDITOR_BACKDROP)
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
        f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        f:Hide()
        tinsert(UISpecialFrames, "UnbunkUtilityFreeIconChoice")   -- ESC closes

        local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
        title:SetPoint("TOP", f, "TOP", 0, -14); title:SetText(L["Choose icon type"])
        AddCloseCross(f, function() f:Hide() end)

        local hint = f:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -12); hint:SetWidth(280)
        hint:SetText(L["What kind of free icon do you want to create?"])

        local b1 = ns.ui.CreateButton({ parent = f, width = 260, height = 32, label = L["Spell / Item"],
            onClick = function() f:Hide(); CC.PromptAddFree() end })
        b1.frame:SetPoint("TOP", hint, "BOTTOM", 0, -16)
        local b2 = ns.ui.CreateButton({ parent = f, width = 260, height = 32, label = L["Buff"],
            onClick = function() f:Hide(); CC.PromptAddFreeBuff() end })
        b2.frame:SetPoint("TOP", b1.frame, "BOTTOM", 0, -10)

        choiceWin = f
    end
    choiceWin:Show()
    choiceWin:Raise()
end
