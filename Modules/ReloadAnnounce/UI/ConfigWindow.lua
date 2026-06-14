-- Modules/ReloadAnnounce/UI/ConfigWindow.lua
-- Extra Utilities > Reloading announcement. A master enable, the message, a vertical
-- drag-to-reorder list of the say/party/raid channels (each toggleable; order = priority),
-- and an "Active in" instance filter. Backed by ns.db.profile.reloadAnnounce via ns.ReloadAnnounce.

local _, ns = ...
local L = ns.L
local RA = ns.ReloadAnnounce

local function cfg() return RA and RA.Cfg() end

-- The vertical drag-reorder list of channel rows (checkbox + label per row). Dragging a
-- row up/down rewrites the priority order; the checkbox toggles whether that channel is used.
local ROW_H = 26
local function ChannelList(host)
    local rows   = {}            -- rows[key] = { frame = }
    local order  = RA.CurrentOrder()
    local dragKey

    local function indexOf(key) for i, k in ipairs(order) do if k == key then return i end end end
    local function slotY(i) return -(i - 1) * ROW_H end
    local function placeRows()
        for key, r in pairs(rows) do
            if key ~= dragKey then
                local i = indexOf(key)
                if i then r.frame:ClearAllPoints(); r.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, slotY(i)) end
            end
        end
    end

    local function onDragUpdate(key, f)
        local scale, top = host:GetEffectiveScale(), host:GetTop()
        if not (scale and scale > 0 and top) then return end
        local cy = select(2, GetCursorPosition()) / scale   -- the Y return (vertical drag)
        local offsetY = cy - top + ROW_H / 2          -- follow the cursor (row centred on it)
        local minOff = slotY(#order)
        if offsetY > 0 then offsetY = 0 elseif offsetY < minOff then offsetY = minOff end
        f:ClearAllPoints(); f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, offsetY)
        local newIdx = math.floor(-offsetY / ROW_H + 0.5) + 1
        if newIdx < 1 then newIdx = 1 elseif newIdx > #order then newIdx = #order end
        local cur = indexOf(key)
        if cur and newIdx ~= cur then
            table.remove(order, cur); table.insert(order, newIdx, key); placeRows()
        end
    end
    local function startDrag(key, f)
        dragKey = key
        f:SetFrameLevel(host:GetFrameLevel() + 10)
        f:SetScript("OnUpdate", function() onDragUpdate(key, f) end)
    end
    local function stopDrag(key, f)
        f:SetScript("OnUpdate", nil)
        f:SetFrameLevel(host:GetFrameLevel() + 1)
        dragKey = nil
        placeRows()
        local i = indexOf(key)
        if i then f:ClearAllPoints(); f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, slotY(i)) end
        RA.SaveOrder(order)
    end

    for _, key in ipairs(order) do
        local f = CreateFrame("Frame", nil, host)
        f:SetSize(300, ROW_H - 2)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.16, 0.16, 0.16, 0.6)
        local cb = ns.ui.CreateCheckbox({
            parent  = f, label = "",
            checked = ((cfg() and cfg().channels and cfg().channels[key]) ~= false),
            onClick = function(v)
                local c = cfg(); if c then c.channels = c.channels or {}; c.channels[key] = v and true or false end
            end,
        })
        cb.frame:SetPoint("LEFT", f, "LEFT", 4, 0)
        local lbl = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        lbl:SetPoint("LEFT", cb.frame, "RIGHT", 6, 0)
        lbl:SetText(RA.CHANNELS[key] and RA.CHANNELS[key].label or key)
        local grip = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        grip:SetPoint("RIGHT", f, "RIGHT", -8, 0); grip:SetTextColor(0.5, 0.5, 0.5); grip:SetText("= =")
        f:SetScript("OnDragStart", function() startDrag(key, f) end)
        f:SetScript("OnDragStop",  function() stopDrag(key, f) end)
        f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, slotY(indexOf(key)))
        rows[key] = { frame = f }
    end
end

local function CreateReloadAnnouncePanel(parent)
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Reloading announcement"] },

        -- Master enable (top).
        { type = "checkbox", label = L["Announce a reload in group chat"],
          get = function() local c = cfg(); return c and c.enabled end,
          set = function(v) local c = cfg(); if c then c.enabled = v and true or false end end },

        { type = "group", title = L["Reloading announcement"], build = function()
            return {
                -- Sub-cadre: the message.
                { type = "group", title = L["Message"], build = function() return {
                    { type = "textinput", label = L["Message sent on reload"], width = 280, maxLetters = 120,
                      get = function() local c = cfg(); return c and c.message or "" end,
                      set = function(v) local c = cfg(); if c then c.message = v or "" end end },
                } end },

                -- Sub-cadre: the channels, with a header explaining the drag priority.
                { type = "group", title = L["Channels"], build = function() return {
                    { type = "label", font = "UnbunkUtilityH6", height = 32,
                      text = L["Drag a row up/down to set priority. The message is sent to the highest CHECKED channel available in your group."] },
                    { type = "custom", height = 3 * ROW_H + 4, build = function(host)
                        ChannelList(host)
                        return { frame = host, height = 3 * ROW_H + 4 }
                    end },
                } end },

                -- Sub-cadre: where it is active.
                { type = "group", title = L["Active in instances"], build = function() return {
                    { type = "instanceFilter",
                      getConfig = function() local c = cfg(); return c and c.instanceFilter end,
                      setConfig = function(fk, fv)
                          local c = cfg()
                          if c then c.instanceFilter = c.instanceFilter or {}; c.instanceFilter[fk] = fv end
                      end },
                } end },
            }
        end },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

local initRA = CreateFrame("Frame")
initRA:RegisterEvent("ADDON_LOADED")
initRA:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Reloading announcement"], nil, CreateReloadAnnouncePanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
