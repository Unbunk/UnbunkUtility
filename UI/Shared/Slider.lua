-- UI/Shared/Slider.lua
-- Reusable styled horizontal slider (integer values) with the value shown to its right — either a static
-- readout, or (config.editBox) a linked text box that stays in sync BOTH ways: drag the slider and the box
-- updates; type in the box and the slider snaps to it. Built on the native "Slider" frame.
--
-- Usage:
--   local s = ns.ui.CreateSlider({
--       parent   = panel,
--       width    = 200,
--       min      = 1, max = 10, step = 1,
--       value    = 2,
--       editBox  = true,        -- optional: add an editable box (two-way); editWidth sets its width (50)
--       format   = function(v) return tostring(v) end,   -- readout formatter (static readout only)
--       onChange = function(v) ... end,                  -- fired on USER change only (drag OR box commit)
--   })
--   s.frame ; s.SetValue(n) [no onChange] ; s.GetValue() ; s.input [the box, or nil]

local _, ns = ...
ns.ui = ns.ui or {}

function ns.ui.CreateSlider(config)
    local parent    = config.parent
    local width     = config.width or 200
    local minV      = config.min   or 0
    local maxV      = config.max   or 100
    local step      = config.step  or 1
    local value     = config.value or minV
    local fmt       = config.format
    local onChange  = config.onChange
    local withInput = config.editBox and true or false
    local inputW    = config.editWidth or 50

    local result = {}

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 24)

    local slider = CreateFrame("Slider", nil, container)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetHitRectInsets(0, 0, -8, -8)   -- a taller grab zone than the 4px track

    -- Track (thin dark line) + brand-blue thumb.
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT",  slider, "LEFT",  0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetColorTexture(0.20, 0.20, 0.20, 0.95)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(ns.GetBrandColor())
    slider:SetThumbTexture(thumb)

    -- Value display on the right: an editable box (two-way) or a static readout. The slider fills the rest.
    local input, valFs
    local suppress = true   -- guards onChange during programmatic / echo updates
    if withInput then
        input = ns.ui.CreateTextInput({
            parent = container, width = inputW, numeric = true, min = minV, max = maxV,
            onEnter = function(v)
                if v == nil then return end
                v = math.max(minV, math.min(maxV, math.floor(v + 0.5)))
                slider:SetValue(v)          -- fires OnValueChanged -> onChange (only if the value CHANGED)
                if input then input.SetText(tostring(v)) end   -- reflect the clamped value even if unchanged
            end,
        })
        input.frame:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        slider:SetPoint("LEFT",  container, "LEFT",  0, 0)
        slider:SetPoint("RIGHT", input.frame, "LEFT", -8, 0)
    else
        valFs = container:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        valFs:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        slider:SetPoint("LEFT",  container, "LEFT",  0, 0)
        slider:SetPoint("RIGHT", valFs, "LEFT", -8, 0)
    end

    local function Readout(v)
        if input then input.SetText(tostring(v))
        else valFs:SetText(fmt and fmt(v) or tostring(v)) end
    end

    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        Readout(v)
        if not suppress and onChange then onChange(v) end
    end)
    slider:SetValue(value)
    Readout(value)
    suppress = false

    -- Re-tint the thumb live when the brand colour changes; weak-keyed by the container (like the checkbox).
    if ns.RegisterBrandRefresh then
        ns.RegisterBrandRefresh(container, function() thumb:SetColorTexture(ns.GetBrandColor()) end)
    end

    function result.SetValue(v)
        suppress = true
        slider:SetValue(v)
        Readout(math.floor((slider:GetValue() or minV) + 0.5))
        suppress = false
    end
    function result.GetValue() return math.floor((slider:GetValue() or minV) + 0.5) end

    result.frame  = container
    result.slider = slider
    result.input  = input   -- the linked box, or nil
    return result
end
