-- UI/Shared/ColorPicker.lua
-- Addon-styled colour picker (replaces Blizzard's ColorPickerFrame everywhere) plus a
-- reusable colour-swatch button. The picker is a single dark, brand-styled window with an
-- HSV saturation/value box, a hue bar, an optional alpha bar, R/G/B + hex (+ alpha) inputs,
-- a live preview and OK / Cancel. It calls onChange(r,g,b,a) LIVE while dragging/typing
-- (like the native swatchFunc) and reverts to the opening colour on Cancel / X / Escape.
--
-- Usage:
--   ns.ui.OpenColorPicker({ r=, g=, b=, a=, hasOpacity=bool, onChange=function(r,g,b,a) end })
--   local sw = ns.ui.CreateColorSwatch({ parent=, width=, height=, hasOpacity=bool,
--                  getColor=function() return {r=,g=,b=,a=} end, onChange=function(r,g,b,a) end })
--   sw.frame ; sw.Refresh()

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

-- ── Colour maths ────────────────────────────────────────────────────────────────
local floor, max, min = math.floor, math.max, math.min

local function hsvToRgb(h, s, v)
    local i = floor(h * 6); local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v else return v, p, q end
end

local function rgbToHsv(r, g, b)
    local mx, mn = max(r, g, b), min(r, g, b)
    local v, d = mx, mx - mn
    local s = (mx == 0) and 0 or d / mx
    local h = 0
    if d ~= 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6; if h < 0 then h = h + 1 end
    end
    return h, s, v
end

local function col(r, g, b, a) return CreateColor(r, g, b, a or 1) end
local function byte(x) return floor(x * 255 + 0.5) end

-- Cursor position inside `frame` as fractions: fx (0=left,1=right), fy (0=top,1=bottom).
local function cursorFrac(frame)
    local l, b, wdt, hgt = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not l or not b or wdt == 0 or hgt == 0 then return 0, 0 end
    local sc = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / sc, my / sc
    local fx = (mx - l) / wdt
    local fy = 1 - (my - b) / hgt
    return max(0, min(1, fx)), max(0, min(1, fy))
end

-- ── Geometry ──────────────────────────────────────────────────────────────────
local WIN_W, WIN_H = 304, 332
local BOX          = 176          -- SV box + bar height
local BAR_W        = 16

local picker   -- the single, reused window (built lazily)

-- Recompute RGB from H/S/V and refresh every visual (does NOT fire onChange).
local function redraw(f)
    local r, g, b = hsvToRgb(f.h, f.s, f.v)
    f.r, f.g, f.b = r, g, b

    f.svBg:SetColorTexture(hsvToRgb(f.h, 1, 1))            -- pure hue behind the S/V overlays
    f.svCursor:ClearAllPoints()
    f.svCursor:SetPoint("CENTER", f.svBox, "TOPLEFT", f.s * BOX, -(1 - f.v) * BOX)

    f.hueCursor:ClearAllPoints()
    f.hueCursor:SetPoint("CENTER", f.hueBar, "TOP", 0, -f.h * BOX)

    if f.hasOpacity then
        f.alphaGrad:SetGradient("VERTICAL", col(r, g, b, 0), col(r, g, b, 1))   -- bottom transparent -> top opaque
        f.alphaCursor:ClearAllPoints()
        f.alphaCursor:SetPoint("CENTER", f.alphaBar, "TOP", 0, -(1 - f.a) * BOX)
    end

    f.preview:SetColorTexture(r, g, b, f.hasOpacity and f.a or 1)
    f.inR.SetText(tostring(byte(r))); f.inG.SetText(tostring(byte(g))); f.inB.SetText(tostring(byte(b)))
    f.inHex.SetText(string.format("%02X%02X%02X", byte(r), byte(g), byte(b)))
    if f.inA then f.inA.SetText(tostring(floor(f.a * 100 + 0.5))) end
end

-- Refresh + fire the live callback (used by every interactive change).
local function commit(f)
    redraw(f)
    if f.onChange then f.onChange(f.r, f.g, f.b, f.hasOpacity and f.a or 1) end
end

-- Wire a frame as a click-and-drag area: onFrac(fx, fy) gets called on press and on every
-- subsequent frame until release.
local function makeDragArea(frame, onFrac)
    frame:EnableMouse(true)
    local function upd() onFrac(cursorFrac(frame)) end
    frame:SetScript("OnMouseDown", function() upd(); frame:SetScript("OnUpdate", upd) end)
    frame:SetScript("OnMouseUp",   function() frame:SetScript("OnUpdate", nil) end)
    frame:SetScript("OnHide",      function() frame:SetScript("OnUpdate", nil) end)
end

local function buildPicker()
    local f = CreateFrame("Frame", "UnbunkUtilityColorPicker", UIParent, "BackdropTemplate")
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.96)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()
    table.insert(UISpecialFrames, "UnbunkUtilityColorPicker")   -- Escape closes (= cancel)

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText(L["Color picker"])

    local closeBtn = ns.ui.CreateButton({ parent = f, label = "X", width = 22, height = 20 })
    closeBtn.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn.frame:SetScript("OnClick", function() f:Hide() end)   -- not confirmed -> revert on hide

    -- Live preview swatch (left of the close button).
    local prevHolder = CreateFrame("Frame", nil, f, "BackdropTemplate")
    prevHolder:SetSize(46, 20)
    prevHolder:SetPoint("TOPRIGHT", closeBtn.frame, "TOPLEFT", -8, 0)
    prevHolder:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    prevHolder:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f.preview = prevHolder:CreateTexture(nil, "ARTWORK")
    f.preview:SetPoint("TOPLEFT", prevHolder, "TOPLEFT", 1, -1)
    f.preview:SetPoint("BOTTOMRIGHT", prevHolder, "BOTTOMRIGHT", -1, 1)

    -- ── Saturation / Value box ──────────────────────────────────────────────────
    local svBox = CreateFrame("Frame", nil, f)
    svBox:SetSize(BOX, BOX)
    svBox:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -42)
    f.svBox = svBox
    f.svBg = svBox:CreateTexture(nil, "BACKGROUND")
    f.svBg:SetAllPoints(svBox)
    local svWhite = svBox:CreateTexture(nil, "ARTWORK", nil, 0)
    svWhite:SetAllPoints(svBox)
    svWhite:SetColorTexture(1, 1, 1, 1)
    svWhite:SetGradient("HORIZONTAL", col(1, 1, 1, 1), col(1, 1, 1, 0))   -- white(left) -> transparent(right)
    local svBlack = svBox:CreateTexture(nil, "ARTWORK", nil, 1)
    svBlack:SetAllPoints(svBox)
    svBlack:SetColorTexture(0, 0, 0, 1)
    svBlack:SetGradient("VERTICAL", col(0, 0, 0, 1), col(0, 0, 0, 0))     -- black(bottom) -> transparent(top)
    -- thin border
    local svBorder = CreateFrame("Frame", nil, svBox, "BackdropTemplate")
    svBorder:SetAllPoints(svBox)
    svBorder:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    svBorder:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    -- crosshair cursor
    local svCursor = CreateFrame("Frame", nil, svBox, "BackdropTemplate")
    svCursor:SetSize(10, 10)
    svCursor:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    svCursor:SetBackdropBorderColor(1, 1, 1, 1)
    f.svCursor = svCursor
    makeDragArea(svBox, function(fx, fy) f.s = fx; f.v = 1 - fy; commit(f) end)

    -- ── Hue bar ───────────────────────────────────────────────────────────────
    local hueBar = CreateFrame("Frame", nil, f)
    hueBar:SetSize(BAR_W, BOX)
    hueBar:SetPoint("TOPLEFT", svBox, "TOPRIGHT", 12, 0)
    f.hueBar = hueBar
    for k = 0, 5 do
        local seg = hueBar:CreateTexture(nil, "ARTWORK")
        seg:SetPoint("TOPLEFT", hueBar, "TOPLEFT", 0, -k / 6 * BOX)
        seg:SetPoint("TOPRIGHT", hueBar, "TOPRIGHT", 0, -k / 6 * BOX)
        seg:SetHeight(BOX / 6)
        local tr, tg, tb = hsvToRgb(k / 6, 1, 1)          -- top of this segment
        local br, bg, bb = hsvToRgb((k + 1) / 6, 1, 1)    -- bottom of this segment
        seg:SetColorTexture(1, 1, 1, 1)
        seg:SetGradient("VERTICAL", col(br, bg, bb, 1), col(tr, tg, tb, 1))
    end
    local hueBorder = CreateFrame("Frame", nil, hueBar, "BackdropTemplate")
    hueBorder:SetAllPoints(hueBar)
    hueBorder:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    hueBorder:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local hueCursor = hueBar:CreateTexture(nil, "OVERLAY")
    hueCursor:SetSize(BAR_W + 6, 3); hueCursor:SetColorTexture(1, 1, 1, 1)
    f.hueCursor = hueCursor
    makeDragArea(hueBar, function(_, fy) f.h = fy; commit(f) end)

    -- ── Alpha bar (only shown when hasOpacity) ──────────────────────────────────
    local alphaBar = CreateFrame("Frame", nil, f)
    alphaBar:SetSize(BAR_W, BOX)
    alphaBar:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", 10, 0)
    f.alphaBar = alphaBar
    local alphaBg = alphaBar:CreateTexture(nil, "BACKGROUND")
    alphaBg:SetAllPoints(alphaBar); alphaBg:SetColorTexture(0.3, 0.3, 0.3, 1)
    f.alphaGrad = alphaBar:CreateTexture(nil, "ARTWORK")
    f.alphaGrad:SetAllPoints(alphaBar); f.alphaGrad:SetColorTexture(1, 1, 1, 1)
    local alphaBorder = CreateFrame("Frame", nil, alphaBar, "BackdropTemplate")
    alphaBorder:SetAllPoints(alphaBar)
    alphaBorder:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    alphaBorder:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local alphaCursor = alphaBar:CreateTexture(nil, "OVERLAY")
    alphaCursor:SetSize(BAR_W + 6, 3); alphaCursor:SetColorTexture(1, 1, 1, 1)
    f.alphaCursor = alphaCursor
    makeDragArea(alphaBar, function(_, fy) f.a = 1 - fy; commit(f) end)

    -- ── R / G / B + hex (+ alpha) inputs ────────────────────────────────────────
    local function labelled(text, x, y, w, numeric, mn, mx, mxl, onset)
        local lbl = f:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        lbl:SetText(text)
        local inp = ns.ui.CreateTextInput({
            parent = f, width = w, height = 20, numeric = numeric, min = mn, max = mx, maxLetters = mxl,
            onEnter = onset,
        })
        inp.frame:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        return inp, lbl
    end

    local IY = -42 - BOX - 14
    local function setChannel(which, v255)
        if not v255 then return end
        local r, g, b = f.r, f.g, f.b
        local v = max(0, min(255, v255)) / 255
        if which == "r" then r = v elseif which == "g" then g = v else b = v end
        f.h, f.s, f.v = rgbToHsv(r, g, b); commit(f)
    end
    f.inR = labelled("R", 16, IY, 36, true, 0, 255, 3, function(v) setChannel("r", v) end)
    f.inG = labelled("G", 96, IY, 36, true, 0, 255, 3, function(v) setChannel("g", v) end)
    f.inB = labelled("B", 176, IY, 36, true, 0, 255, 3, function(v) setChannel("b", v) end)

    f.inHex = labelled("#", 16, IY - 28, 70, false, nil, nil, 6, function(txt)
        local hex = tostring(txt):gsub("[^%x]", "")
        if #hex == 6 then
            local r = tonumber(hex:sub(1, 2), 16) / 255
            local g = tonumber(hex:sub(3, 4), 16) / 255
            local b = tonumber(hex:sub(5, 6), 16) / 255
            f.h, f.s, f.v = rgbToHsv(r, g, b); commit(f)
        else
            redraw(f)   -- reject malformed input: restore the displayed value
        end
    end)

    local inA, lblA = labelled("A", 124, IY - 28, 36, true, 0, 100, 3, function(v)
        if v then f.a = max(0, min(100, v)) / 100; commit(f) end
    end)
    f.inA, f.alphaLbl = inA, lblA

    -- ── OK / Cancel ───────────────────────────────────────────────────────────
    local okBtn = ns.ui.CreateButton({
        parent = f, label = L["OK"], width = 80, height = 22,
        onClick = function() f.confirmed = true; f:Hide() end,
    })
    okBtn.frame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    local cancelBtn = ns.ui.CreateButton({
        parent = f, label = L["Cancel"], width = 80, height = 22,
        onClick = function() f:Hide() end,   -- not confirmed -> revert on hide
    })
    cancelBtn.frame:SetPoint("RIGHT", okBtn.frame, "LEFT", -8, 0)

    -- Closing without OK reverts to the colour the picker opened with.
    f:SetScript("OnHide", function(self)
        if not self.confirmed and self.initial and self.onChange then
            local i = self.initial
            self.onChange(i.r, i.g, i.b, self.hasOpacity and i.a or 1)
        end
    end)

    picker = f
    return f
end

function ns.ui.OpenColorPicker(opts)
    opts = opts or {}
    local f = picker or buildPicker()
    -- If a previous swatch is still open, flush it first so its OnHide revert
    -- runs against the old onChange/initial before we re-arm for the new swatch.
    if f:IsShown() then f:Hide() end
    f.onChange   = opts.onChange
    f.hasOpacity = opts.hasOpacity and true or false
    local r, g, b = opts.r or 1, opts.g or 1, opts.b or 1
    local a = opts.a or 1
    f.initial = { r = r, g = g, b = b, a = a }
    f.h, f.s, f.v = rgbToHsv(r, g, b)
    f.a = a
    f.confirmed = false

    -- Alpha widgets only when the caller wants opacity.
    f.alphaBar:SetShown(f.hasOpacity)
    f.inA.frame:SetShown(f.hasOpacity)
    f.alphaLbl:SetShown(f.hasOpacity)

    redraw(f)   -- initial paint, no onChange
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:Show(); f:Raise()
    return f
end

-- ── Reusable colour-swatch button ───────────────────────────────────────────────
function ns.ui.CreateColorSwatch(opts)
    opts = opts or {}
    local parent = opts.parent
    local wdt, hgt = opts.width or 24, opts.height or 22
    local result = {}

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(wdt, hgt)
    btn:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)

    local function curColor()
        local c = opts.getColor and opts.getColor()
        if not c then return 1, 1, 1, 1 end
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end
    local function refresh()
        local r, g, b, a = curColor()
        tex:SetColorTexture(r, g, b, opts.hasOpacity and a or 1)
    end
    refresh()
    result.Refresh = refresh

    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(ns.GetBrandColor()) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end)
    btn:SetScript("OnClick", function()
        local r, g, b, a = curColor()
        ns.ui.OpenColorPicker({
            r = r, g = g, b = b, a = a, hasOpacity = opts.hasOpacity,
            onChange = function(nr, ng, nb, na)
                if opts.onChange then opts.onChange(nr, ng, nb, na) end
                refresh()
            end,
        })
    end)

    result.frame = btn
    return result
end
