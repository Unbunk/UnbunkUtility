-- UI/Shared/GroupBox.lua
-- A non-collapsible bordered box that visually groups a set of controls under an
-- optional title. Unlike CollapsibleSection (which only borders its header), this
-- draws a frame AROUND the whole content so related options read as one block.
--
-- The border is drawn INSIDE the container bounds (box:SetAllPoints) and the
-- child content is inset by `sidePad` on each side. This means:
--   * Both left and right borders stay within the container, so they are never
--     clipped by the scroll viewport (the panel adds a left/right margin via the
--     outer BuildMenu originX so the top-level box is centred).
--   * Boxes nest cleanly: each nesting level indents its content by `sidePad`,
--     so an inner sub-box sits visibly inset from its parent box.
-- The hardcoded-518 shared widgets (SoundPicker/TextEditor/IconPicker/Position
-- Editor) left-align their visible content well under ~360px, so their invisible
-- bounding frame overflowing a narrower inner box never clips anything visible.
--
-- Usage:
--   local g = ns.ui.CreateGroupBox({
--       parent = content,
--       title  = "Sound",                       -- optional title shown top-left
--       width  = 518,                           -- OUTER width (container width)
--       sidePad = 10,                           -- horizontal inset for content
--       createContent = function(cf)            -- build children into cf
--           ...
--           return innerHeight                  -- height consumed by children
--       end,
--   })
--   g.frame          -- container frame (stacked by BuildMenu)
--   g.height         -- total height (title + content + padding)
--   g.contentFrame   -- frame the children were built into
--   g.Refresh()      -- no-op by default; BuildMenu's "group" type replaces it

local _, ns = ...
ns.ui = ns.ui or {}

function ns.ui.CreateGroupBox(config)
    local parent  = config.parent
    local title   = config.title
    local heading = config.heading or "UnbunkUtilityH2"   -- title tier (H2 root / H3 nested)
    local width   = config.width                 -- outer/container width
    local sidePad = config.sidePad or 10
    local titleH  = title and 18 or 0
    local topPad  = config.topPad or (titleH + 8)
    local botPad  = config.botPad or 10

    local result    = {}
    local container = CreateFrame("Frame", nil, parent)
    if width then container:SetWidth(width) end

    -- Bordered box fills the container; the edge texture is drawn within bounds.
    local box = CreateFrame("Frame", nil, container, "BackdropTemplate")
    box:SetAllPoints(container)
    box:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0.10, 0.10, 0.10, 0.5)
    box:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    result.box = box

    if title then
        local fs = box:CreateFontString(nil, "OVERLAY", heading)
        fs:SetPoint("TOPLEFT", box, "TOPLEFT", sidePad, -6)
        fs:SetText(title)
        result.title = fs
    end

    -- Content host, inset by sidePad on both sides (children stay inside the box).
    local contentFrame = CreateFrame("Frame", nil, container)
    contentFrame:SetPoint("TOPLEFT",  container, "TOPLEFT",   sidePad, -topPad)
    contentFrame:SetPoint("TOPRIGHT", container, "TOPRIGHT", -sidePad, -topPad)
    if width then contentFrame:SetWidth(width - 2 * sidePad) end

    local innerHeight = 0
    if config.createContent then
        innerHeight = config.createContent(contentFrame) or 0
    end
    contentFrame:SetHeight(innerHeight)

    local total = topPad + innerHeight + botPad
    container:SetHeight(total)

    result.frame        = container
    result.height       = total
    result.contentFrame = contentFrame
    function result.Refresh() end   -- replaced by BuildMenu's "group" wiring
    return result
end
