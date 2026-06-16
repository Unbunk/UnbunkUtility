-- UI/Shared/IconConfigEntries.lua
-- Reusable BuildMenu "custom" entries shared by every icon config (custom CDM
-- icons, defensives, native icons, and the item trackers — potions, trinkets,
-- racials, etc.) so they all expose the same controls:
--   * ns.ui.AnchorOffsetEntry  — an "Anchor" dropdown (Center / edges / 4 inside
--     corners, from ns.AnchorList) plus X / Y nudge inputs, for a stack/title text.
--   * ns.ui.TiersEntry         — the "time thresholds" list editor (one row per
--     tier: At seconds / size mult / colour / remove + an "Add threshold" button).
-- Both are driven entirely by getter/setter closures so any module can wire them
-- to its own config store.

local _, ns = ...
ns.ui = ns.ui or {}

local function L(key) return (ns.L and ns.L[key]) or key end

-- Anchor dropdown + X/Y offsets. opts:
--   label      (optional, defaults to "Anchor")
--   getAnchor  () -> mode      setAnchor(mode)
--   getX/getY  () -> number    setX(v) / setY(v)
function ns.ui.AnchorOffsetEntry(opts)
    return {
        type   = "custom",
        height = 48,
        build  = function(host)
            local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
            lbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            lbl:SetText(opts.label or L("Anchor"))

            local ddAnchor = host:CreateFontString(nil, "ARTWORK")
            ddAnchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -18)
            local dd
            dd = ns.ui.CreateDropdown({
                parent = host, anchorFrame = ddAnchor, width = 150, itemHeight = 20, visibleItems = 6,
                getList = ns.AnchorList,
                getCurrentKey = function() return ns.AnchorLabel(opts.getAnchor()) end,
                onSelect = function(label)
                    opts.setAnchor(ns.AnchorFromLabel(label))
                    dd.selectedText:SetText(label)
                end,
            })
            dd.selectedText:SetText(ns.AnchorLabel(opts.getAnchor()))

            local function offInput(after, gap, axisText, get, set)
                local axis = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                axis:SetPoint("LEFT", after, "RIGHT", gap, 0)
                axis:SetText(axisText)
                local inp = ns.ui.CreateTextInput({
                    parent = host, width = 44, height = 22, numeric = true, allowNegative = true,
                    min = -512, max = 512, maxLetters = 4,
                    text = tostring(get() or 0),
                    onEnter = function(v) if v ~= nil then set(v) end end,
                })
                inp.frame:SetPoint("LEFT", axis, "RIGHT", 4, 0)
                return inp
            end
            local xInput = offInput(dd.toggleBtn, 14, "X", opts.getX, opts.setX)
            local yInput = offInput(xInput.frame, 10, "Y", opts.getY, opts.setY)

            return {
                frame     = host,
                height    = 48,
                dropFrame = dd.dropFrame,
                Refresh   = function()
                    dd.selectedText:SetText(ns.AnchorLabel(opts.getAnchor()))
                    xInput.SetText(tostring(opts.getX() or 0))
                    yInput.SetText(tostring(opts.getY() or 0))
                end,
            }
        end,
    }
end

-- Time-threshold tiers editor. opts:
--   getTiers () -> array of { at, scale, color }   (the LIVE array — mutated in place)
--   apply    ()   re-apply the icon after a change
--   rebuild  ()   re-render the menu (row count changes on add/remove)
function ns.ui.TiersEntry(opts)
    return {
        type   = "custom",
        height = 60,
        build  = function(host)
            local tiers = opts.getTiers() or {}
            local ROW_H = 30

            local hdr = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
            hdr:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            hdr:SetText(L("Time thresholds (size + colour as the timer drops)"))

            local y = 22
            for i, tier in ipairs(tiers) do
                local atLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                atLbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
                atLbl:SetText(L("At (s)"))
                local atInput = ns.ui.CreateTextInput({
                    parent = host, width = 42, height = 22, numeric = true, min = 0, max = 3600, maxLetters = 4,
                    text = tostring(tier.at or 0),
                    onEnter = function(v) if v ~= nil then tier.at = v; opts.apply() end end,
                })
                atInput.frame:SetPoint("LEFT", atLbl, "RIGHT", 4, 0)

                local szLbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                szLbl:SetPoint("LEFT", atInput.frame, "RIGHT", 12, 0)
                szLbl:SetText(L("Size x"))
                local szInput = ns.ui.CreateTextInput({
                    parent = host, width = 46, height = 22, numeric = true, min = 0, max = 10, maxLetters = 4,
                    text = tostring(tier.scale or 1),
                    onEnter = function(v) if v and v > 0 then tier.scale = v; opts.apply() end end,
                })
                szInput.frame:SetPoint("LEFT", szLbl, "RIGHT", 4, 0)

                local swatch = ns.ui.CreateColorSwatch({
                    parent = host, width = 24, height = 22,
                    getColor = function() return tier.color end,
                    onChange = function(r, g, b, a) tier.color = { r = r, g = g, b = b, a = a }; opts.apply() end,
                })
                swatch.frame:SetPoint("LEFT", szInput.frame, "RIGHT", 12, 0)

                local rm = ns.ui.CreateButton({
                    parent = host, label = "X", width = 24, height = 22,
                    onClick = function() table.remove(tiers, i); opts.apply(); opts.rebuild() end,
                })
                rm.frame:SetPoint("LEFT", swatch.frame, "RIGHT", 12, 0)

                y = y + ROW_H
            end

            local add = ns.ui.CreateButton({
                parent = host, label = L("Add threshold"), width = 140, height = 22,
                onClick = function()
                    local list = opts.getTiers()
                    if list then
                        list[#list + 1] = { at = 10, scale = 1, color = { r = 1, g = 1, b = 1, a = 1 } }
                        opts.apply(); opts.rebuild()
                    end
                end,
            })
            add.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
            y = y + 30

            host:SetHeight(math.max(60, y))
            return { frame = host, height = math.max(60, y) }
        end,
    }
end
