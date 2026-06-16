-- Modules/BuffGroups/UI/ConfigWindow.lua
-- "Buffs" panel (between Utility and Below player frame): a "Buff groups" cadre holding one
-- sub-cadre per group (Placement / Border / Icon size + a draggable icon strip), an
-- "Unused" sub-cadre, a "Create group" button, and per-strip "+" to add a custom buff.
--
-- Drag-to-reorder: dragging an icon lifts it (a ghost follows the cursor) and the strips
-- live-reflow — the strip under the cursor opens a gap at the insertion slot, others close
-- theirs — so you can reorder within a group AND move between groups (rows). On release the
-- buff is reassigned + reordered (ns.BuffGroups.MoveBuff) and the panel rebuilds.

local _, ns = ...
local L  = ns.L
local BG = ns.BuffGroups

local ICON, PAD = 30, 4
local STEP = ICON + 6       -- horizontal step (icon + 6px gap)
local GAP_BG = 6            -- vertical gap between wrapped rows
local PER_ROW = 12          -- icons per row (groups cap here; Unused wraps to more rows)
local GROUP_CAP = 12        -- max icons per group

local function CreateBuffsPanel(parent)
    local menu
    local function rebuild() if menu then menu.Rebuild() end end
    local function touch() BG.ApplyAll() end

    BG.pe = {}
    local strips = {}                 -- current strip objects, rebuilt each render
    local dragTile, dragSid, dragHovered, dragHole
    local ghost                       -- reused top-level icon that follows the cursor

    local function ensureGhost()
        if ghost then return ghost end
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetSize(ICON, ICON)
        ghost:SetFrameStrata("TOOLTIP")
        ghost.tex = ghost:CreateTexture(nil, "OVERLAY")
        ghost.tex:SetAllPoints(); ghost.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ghost:Hide()
        return ghost
    end

    -- While dragging, a top-level GHOST follows the cursor (not clipped); the real tile stays
    -- in place but invisible (alpha 0, still "shown" so OnDragStop always fires — even on a
    -- release into empty space). The strips reflow live: the hovered strip opens a gap, others
    -- close theirs. relayout() skips the dragged spell so its tile isn't repositioned.
    local function dragOnUpdate(self)
        local scale = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        if scale and scale > 0 and mx then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / scale, my / scale)
        end
        local hovered, hole
        for _, s in ipairs(strips) do
            if s.frame:IsShown() and s.frame:IsMouseOver() then
                hovered = s; hole = s.slotAt(dragSid); break
            end
        end
        dragHovered, dragHole = hovered, hole
        for _, s in ipairs(strips) do s.relayout(dragSid, s == hovered and hole or nil) end
    end

    local function startDrag(tile, spellId)
        dragTile, dragSid, dragHovered, dragHole = tile, spellId, nil, nil
        tile:SetAlpha(0)
        local gh = ensureGhost()
        gh.tex:SetTexture(BG.SpellTexture(spellId))
        gh:Show()
        gh:SetScript("OnUpdate", dragOnUpdate)
    end
    local function stopDrag()
        local gh = ensureGhost()
        gh:SetScript("OnUpdate", nil); gh:Hide()
        if dragTile then dragTile:SetAlpha(1) end
        local sid, hovered, hole = dragSid, dragHovered, dragHole
        dragTile, dragSid, dragHovered, dragHole = nil, nil, nil, nil
        -- Dropped onto a strip -> reassign/reorder; dropped into empty space -> nothing moves
        -- (the rebuild below puts the lifted tile straight back).
        if sid and hovered then
            local full = hovered.groupId ~= 0 and BG.GroupOf(sid) ~= hovered.groupId
                and #BG.GetGroupBuffs(hovered.groupId) >= GROUP_CAP
            if not full then BG.MoveBuff(sid, hovered.groupId, hole); touch() end
        end
        rebuild()
    end

    local function promptAddCustom(groupId)
        ns.ui.ShowPrompt({
            title      = L["Add a buff"],
            text       = L["Enter a spell ID:"],
            maxLetters = 8,
            onAccept   = function(val)
                local sid = tonumber(val)
                if sid and sid > 0 then BG.AddCustom(sid, groupId); touch(); rebuild() end
            end,
        })
    end

    -- A draggable icon strip for one group (groupId 0 = Unused). Shows ALL buffs assigned to
    -- the group (active or not) so they can be reordered; the in-game layout only draws the
    -- active ones. Groups are a single row capped at GROUP_CAP; Unused wraps to many rows.
    -- The strip object exposes relayout/slotAt used by the drag driver.
    local function BuffStripEntry(groupId)
        local wrap = (groupId == 0)
        local cap  = wrap and nil or GROUP_CAP
        return {
            type  = "custom",
            build = function(host)
                local frame = CreateFrame("Frame", nil, host)
                frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)

                local obj = { frame = frame, groupId = groupId, tiles = {}, wrap = wrap, cap = cap }
                strips[#strips + 1] = obj

                -- Slot -> position (a wrapping grid for Unused, a single row for a group).
                local function placeAt(f, slot)
                    f:ClearAllPoints()
                    if wrap then
                        local col, row = slot % PER_ROW, math.floor(slot / PER_ROW)
                        f:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * STEP, -(PAD + row * (ICON + GAP_BG)))
                    else
                        f:SetPoint("LEFT", frame, "LEFT", PAD + slot * STEP, 0)
                    end
                end

                -- Trailing "+" tile.
                local addb = CreateFrame("Button", nil, frame)
                addb:SetSize(ICON, ICON)
                local abord = addb:CreateTexture(nil, "BACKGROUND")
                abord:SetPoint("TOPLEFT", -1, 1); abord:SetPoint("BOTTOMRIGHT", 1, -1); abord:SetColorTexture(0.4, 0.4, 0.4, 1)
                local afill = addb:CreateTexture(nil, "BACKGROUND", nil, 1); afill:SetAllPoints(); afill:SetColorTexture(0.12, 0.12, 0.12, 0.9)
                local aplus = addb:CreateTexture(nil, "ARTWORK"); aplus:SetPoint("CENTER"); aplus:SetSize(ICON - 12, ICON - 12); aplus:SetTexture(UNBUNK_ICON_PLUS_GREEN)
                addb:SetScript("OnEnter", function() afill:SetColorTexture(0.2, 0.2, 0.2, 0.95) end)
                addb:SetScript("OnLeave", function() afill:SetColorTexture(0.12, 0.12, 0.12, 0.9) end)
                addb:SetScript("OnClick", function() promptAddCustom(groupId) end)
                obj.addBtn = addb

                for _, sid in ipairs(BG.GetGroupBuffs(groupId)) do
                    local spellId = sid
                    local b = CreateFrame("Button", nil, frame)
                    b:SetSize(ICON, ICON)
                    local bord = b:CreateTexture(nil, "BACKGROUND")
                    bord:SetPoint("TOPLEFT", -1, 1); bord:SetPoint("BOTTOMRIGHT", 1, -1); bord:SetColorTexture(0.4, 0.4, 0.4, 1)
                    local tex = b:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints(); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); tex:SetTexture(BG.SpellTexture(spellId))
                    b:RegisterForDrag("LeftButton")
                    b:SetScript("OnDragStart", function() startDrag(b, spellId) end)
                    b:SetScript("OnDragStop", function() stopDrag() end)

                    if BG.IsCustom(spellId) then
                        local xb = CreateFrame("Button", nil, b)
                        xb:SetSize(14, 14); xb:SetPoint("CENTER", b, "TOPRIGHT", -7, -3)
                        xb:SetFrameLevel(b:GetFrameLevel() + 5)
                        local xbg = xb:CreateTexture(nil, "BACKGROUND"); xbg:SetAllPoints(); xbg:SetColorTexture(0, 0, 0, 0.6)
                        local xg = xb:CreateTexture(nil, "OVERLAY"); xg:SetPoint("CENTER"); xg:SetSize(10, 10); xg:SetTexture(UNBUNK_ICON_CROSS_WHITE)
                        xb:SetScript("OnEnter", function() xg:SetVertexColor(ns.GetBrandColor()) end)
                        xb:SetScript("OnLeave", function() xg:SetVertexColor(1, 1, 1) end)
                        xb:SetScript("OnClick", function() BG.RemoveCustom(spellId); touch(); rebuild() end)
                    end

                    obj.tiles[#obj.tiles + 1] = { frame = b, spellId = spellId }
                end

                -- Insertion slot under the cursor (0 .. number of non-dragged tiles).
                function obj.slotAt(dragSpell)
                    local scale = frame:GetEffectiveScale()
                    local left, top = frame:GetLeft(), frame:GetTop()
                    if not (scale and scale > 0 and left) then return 0 end
                    local mx, my = GetCursorPosition()
                    local cx = (mx / scale) - left
                    local n = 0
                    for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then n = n + 1 end end
                    local col = math.floor((cx - PAD) / STEP + 0.5)
                    if col < 0 then col = 0 end
                    local row = 0
                    if wrap and top then
                        row = math.floor((top - (my / scale) - PAD) / (ICON + GAP_BG))
                        if row < 0 then row = 0 end
                        if col > PER_ROW then col = PER_ROW end
                    end
                    local idx = row * PER_ROW + col
                    if idx < 0 then idx = 0 elseif idx > n then idx = n end
                    return idx
                end

                -- Reflow: skip the lifted tile (it follows the cursor), place the rest in order,
                -- leaving a one-slot gap at holeIndex (the hovered strip only).
                function obj.relayout(dragSpell, holeIndex)
                    local seq = {}
                    for _, t in ipairs(obj.tiles) do if t.spellId ~= dragSpell then seq[#seq + 1] = t end end
                    local slot = 0
                    for i, t in ipairs(seq) do
                        if holeIndex and (i - 1) == holeIndex then slot = slot + 1 end
                        placeAt(t.frame, slot); t.frame:Show()
                        slot = slot + 1
                    end
                    if holeIndex and holeIndex >= #seq then slot = slot + 1 end
                    if wrap or (#seq < (cap or math.huge)) then
                        placeAt(addb, slot); addb:Show()
                    else
                        addb:Hide()
                    end
                end

                obj.relayout(nil, nil)

                -- Height: one row for a group, ceil(items / PER_ROW) rows for Unused.
                local items = #obj.tiles + 1   -- + the "+" tile
                local rows  = wrap and math.max(1, math.ceil(items / PER_ROW)) or 1
                local h = PAD * 2 + rows * ICON + math.max(0, rows - 1) * GAP_BG
                host:SetHeight(h)
                return { frame = host, height = h }
            end,
        }
    end

    -- Per-group Icon size (W / H) — single row, no per-row split.
    local function IconSizeEntry(id)
        return {
            type = "custom", height = 46,
            build = function(host)
                local sLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
                sLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0); sLbl:SetText(L["Icon size"])
                local wLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                wLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -20); wLbl:SetText(L["W"])
                local wInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(BG.GGet(id, "iconW") or 32),
                    onEnter = function(v) if v and v > 0 then BG.GSet(id, "iconW", v); touch() end end,
                })
                wInput.frame:SetPoint("LEFT", wLbl, "RIGHT", 4, 0)
                local hLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                hLbl:SetPoint("LEFT", wInput.frame, "RIGHT", 12, 0); hLbl:SetText(L["H"])
                local hInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 8, max = 256, maxLetters = 3,
                    text = tostring(BG.GGet(id, "iconH") or 32),
                    onEnter = function(v) if v and v > 0 then BG.GSet(id, "iconH", v); touch() end end,
                })
                hInput.frame:SetPoint("LEFT", hLbl, "RIGHT", 4, 0)
                return { frame = host, height = 46, Refresh = function()
                    wInput.SetText(tostring(BG.GGet(id, "iconW") or 32))
                    hInput.SetText(tostring(BG.GGet(id, "iconH") or 32))
                end }
            end,
        }
    end

    local function GroupCadre(id)
        local title = (BG.GGet(id, "name") or ("Group " .. id))
        return { type = "group", title = title, build = function()
            local e = {
                { type = "textinput", label = L["Group name"], width = 200, maxLetters = 32,
                  get = function() return BG.GGet(id, "name") or "" end,
                  set = function(v) BG.GSet(id, "name", v or ""); rebuild() end },
                { type = "position", ref = "pe",
                  onBuilt = function(w) BG.pe[id] = w end,
                  label = L["Group position (offset from screen center)"],
                  getX = function() return BG.GGet(id, "posX") end,
                  getY = function() return BG.GGet(id, "posY") end,
                  onApply = function(x, yv)
                      if x  then BG.GSet(id, "posX", x)  end
                      if yv then BG.GSet(id, "posY", yv) end
                      touch()
                  end,
                  onUnlock   = function() BG.SetGroupUnlocked(id, true) end,
                  onLock     = function() BG.SetGroupUnlocked(id, false); if BG.pe[id] then BG.pe[id].Refresh() end end,
                  isUnlocked = function() return BG.IsGroupUnlocked(id) end },
                { type = "group", title = L["Border"], build = function() return {
                    { type = "checkbox", label = L["Show border"],
                      get = function() return BG.GGet(id, "borderEnabled") ~= false end,
                      set = function(v) BG.GSet(id, "borderEnabled", v); touch(); if menu then menu.Refresh() end end },
                    { type = "textEditor", label = L["Border color"],
                      showText = false, showFont = false, showSize = false, showOutline = false, showColor = true,
                      enabledBy = function() return BG.GGet(id, "borderEnabled") ~= false end,
                      getColor = function() return BG.GGet(id, "borderColor") end,
                      onColorChange = function(r, g, b, a) BG.GSet(id, "borderColor", { r = r, g = g, b = b, a = a }); touch() end },
                    { type = "textinput", label = L["Border thickness"], width = 46, numeric = true, min = 1, max = 16, maxLetters = 2,
                      enabledBy = function() return BG.GGet(id, "borderEnabled") ~= false end,
                      get = function() return BG.GGet(id, "borderSize") or 1 end,
                      set = function(v) if v and v > 0 then BG.GSet(id, "borderSize", v); touch() end end },
                } end },
                IconSizeEntry(id),
                BuffStripEntry(id),
            }
            if id ~= 1 then
                e[#e + 1] = { type = "button", label = L["Delete group"], width = 160, hostHeight = 30,
                    onClick = function() BG.RemoveGroup(id); touch(); rebuild() end }
            end
            return e
        end }
    end

    local function UnusedCadre()
        return { type = "group", title = L["Unused"], build = function() return {
            { type = "label", font = "UnbunkUtilityH6", height = 18,
              text = L["Buffs here are hidden. Drag them onto a group to show them."] },
            BuffStripEntry(0),
        } end }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Buffs"] },
        { type = "group", title = L["General"], build = function() return {
            { type = "checkbox", label = L["Enable buff groups"],
              get = function() return BG.Enabled() end,
              set = function(v) BG.SetEnabled(v); touch(); if menu then menu.Refresh() end end },
            { type = "label", font = "UnbunkUtilityH6", height = 30,
              text = L["A custom layout built from the native buff Cooldown Manager. Drag buff icons between groups; each group has its own placement, border and icon size."] },
        } end },
        { type = "group", title = L["Buff groups"], build = function()
            wipe(strips)
            local entries = {}
            for _, g in ipairs(BG.GroupList()) do
                entries[#entries + 1] = GroupCadre(g.id)
            end
            entries[#entries + 1] = UnusedCadre()
            entries[#entries + 1] = { type = "button", label = L["Create group"], width = 160, hostHeight = 30,
                onClick = function() BG.NewGroup(); touch(); rebuild() end }
            return entries
        end },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

local initBG = CreateFrame("Frame")
initBG:RegisterEvent("ADDON_LOADED")
initBG:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Buffs"], nil, CreateBuffsPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
