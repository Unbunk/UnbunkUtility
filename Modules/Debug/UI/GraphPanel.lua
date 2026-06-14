-- Modules/Debug/UI/GraphPanel.lua
-- Debug Utilities > Addon usage > Graph.
--
-- A config panel (own selection, independent of the Print panel) plus two live graph
-- windows — one for CPU, one for Memory — each plotting the selected addons as coloured
-- polylines, one sample every `interval` seconds:
--   CPU    = C_AddOnProfiler recent-average ms/frame (Enum.AddOnProfilerMetric.RecentAverageTime).
--   Memory = GetAddOnMemoryUsage (KB).
-- Each addon's line gets a random colour, except UnbunkUtility which always takes the
-- live brand colour. The X axis never auto-rescales: every sample since the window was
-- opened is kept (capped), at a fixed per-sample spacing — the mouse wheel zooms that
-- spacing and a scrollbar below pans. "Show differential" prints the coloured ± change
-- vs the previous point under each point (same tiers as the Print panel). Rendering is
-- virtualised (only the samples inside the viewport are drawn) so long sessions stay light.

local _, ns = ...
local L = ns.L

local function GUCfg() return ns.db and ns.db.profile and ns.db.profile.graphUsage end

-- Defensive API shims (Interface 120005: C_AddOns.* is canonical, keep a fallback).
local getNum  = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo

local RECENT = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
local function ProfilerOn()
    return RECENT ~= nil and C_AddOnProfiler and C_AddOnProfiler.IsEnabled and C_AddOnProfiler.IsEnabled()
end

local function clean(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn.-:", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local addonCache
local function AddonList()
    if addonCache then return addonCache end
    local list = {}
    for i = 1, (getNum and getNum() or 0) do
        local name, title = getInfo(i)
        if name then
            local disp = clean(title); if disp == "" then disp = name end
            list[#list + 1] = { name = name, title = disp }
        end
    end
    table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
    addonCache = list
    return list
end

-- ── Value formatting + differential colour tiers (mirrors the Print panel) ──────
local function fmtMem(kb)
    if not kb or kb < 0.5 then return "0 KB" end
    if kb >= 1024 then return string.format("%.2f MB", kb / 1024) end
    return string.format("%.0f KB", kb)
end
local function fmtCPUaxis(ms) return string.format("%.1f ms", ms or 0) end

local function round1(x) return math.floor(math.abs(x) * 10 + 0.5) / 10 * (x < 0 and -1 or 1) end

-- Per-unit tiers: |Δ| below GREY = very low fluctuation -> grey; a decrease -> green; an
-- increase up to BIG -> yellow; past BIG -> red. The grey fourchette keeps near-zero
-- noise (e.g. "+0.0 ms") from showing as a real change. Returns r,g,b for a FontString.
local CPU_GREY, CPU_BIG = 0.1, 1.0
local MEM_GREY, MEM_BIG = 5,   200
local function diffTier(d, greyT, bigT)
    if math.abs(d) < greyT then return 0.6, 0.6, 0.6 end   -- grey
    if d < 0          then return 0.33, 1, 0.33 end          -- green (decrease)
    if d >= bigT      then return 1, 0.33, 0.33 end          -- red (big increase)
    return 1, 0.82, 0.2                                      -- yellow (medium increase)
end
local function fmtDiffCPU(d) return string.format("%+.1f", round1(d)) end
local function fmtDiffMem(d)
    if math.abs(d) >= 1024 then return string.format("%+.1fM", d / 1024) end
    return string.format("%+.0fK", d)
end

-- Random-but-distinct colour: HSV with a golden-ratio hue walk from a random seed.
local function hsv(h, s, v)
    local i = math.floor(h * 6); local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v else return v, p, q end
end

-- ── Graph window geometry ───────────────────────────────────────────────────────
local WIN_W, WIN_H     = 760, 480
local PLOT_L, PLOT_R   = 76, 150   -- left margin (Y labels + Y scrollbar + zoom) / right (legend)
local PLOT_T, PLOT_B   = 44, 58    -- top (title) / bottom (X scrollbar + X zoom row)
local PAD_X            = 16        -- horizontal padding inside the canvas
local PAD_T2, PAD_B2   = 16, 22    -- vertical headroom (top) / footroom for diff labels (bottom)
local LEGEND_W         = 130
local DOT              = 5
local DEFAULT_SP, MIN_SP, MAX_SP = 36, 6, 160
local Y_MIN_ZOOM, Y_MAX_ZOOM     = 0.2, 20   -- vertical (value-axis) zoom bounds; 1 = auto-fit
local SAMPLE_CAP       = 600       -- keep the last N samples (drop oldest beyond this)

local windows = {}   -- ["cpu"] / ["mem"] -> window table (built lazily, reused)

-- Live colour for an addon's line/legend: UnbunkUtility follows the brand colour, the
-- rest use the random colour assigned when the window was (re)opened.
local function colorOf(w, name)
    if name == "UnbunkUtility" then return ns.GetBrandColor() end
    local c = w.colors[name]
    if c then return c[1], c[2], c[3] end
    return 0.8, 0.8, 0.8
end

-- ── Pools (children of the scrolling canvas, reused across redraws) ─────────────
local function acquireLine(w, i)
    local p = w.lines[i]
    if not p then p = w.canvas:CreateLine(nil, "ARTWORK"); p:SetThickness(2); w.lines[i] = p end
    return p
end
local function acquireDot(w, i)
    local p = w.dots[i]
    if not p then p = w.canvas:CreateTexture(nil, "OVERLAY"); p:SetSize(DOT, DOT); w.dots[i] = p end
    return p
end
local function acquireLabel(w, i)
    local p = w.labels[i]
    if not p then p = w.canvas:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6"); w.labels[i] = p end
    return p
end

local function updateHBar(w, contentW, vpW)
    local hb = w.hbar
    local maxScroll = math.max(0, contentW - vpW)
    if maxScroll <= 0 then hb.thumb:Hide(); return end
    hb.thumb:Show()
    local trackW = hb.track:GetWidth()
    local thumbW = math.max(20, trackW * vpW / contentW)
    local frac   = (w.scroll:GetHorizontalScroll() or 0) / maxScroll
    hb.thumb:SetWidth(thumbW)
    hb.thumb:ClearAllPoints()
    hb.thumb:SetPoint("LEFT", hb.track, "LEFT", frac * (trackW - thumbW), 0)
end

-- Generic vertical scrollbar (track + draggable thumb). The owner calls sb.update(posFrac,
-- sizeFrac) each refresh (posFrac 0 = top; sizeFrac >= 1 hides the thumb) and assigns
-- sb.onDrag(frac) to map a [0,1] drag position back to its own scroll value.
local function makeVScroll(parent)
    local sb = { _pos = 0, onDrag = function() end }
    local track = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    track:SetWidth(8)
    track:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    track:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8); thumb:SetHeight(16)
    local tex = thumb:CreateTexture(nil, "OVERLAY"); tex:SetAllPoints(); tex:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    sb.track, sb.thumb = track, thumb

    function sb.update(posFrac, sizeFrac)
        if sizeFrac >= 1 then thumb:Hide(); return end
        thumb:Show()
        sb._pos = posFrac
        local trackH = track:GetHeight()
        local thumbH = math.max(16, math.min(trackH, trackH * sizeFrac))
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -posFrac * (trackH - thumbH))
    end

    thumb:EnableMouse(true)
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local sc = UIParent:GetEffectiveScale()
        local startY   = select(2, GetCursorPosition()) / sc
        local startPos = sb._pos
        thumb:SetScript("OnUpdate", function()
            local span = track:GetHeight() - thumb:GetHeight()
            if span <= 0 then return end
            local cy = select(2, GetCursorPosition()) / sc
            sb.onDrag(math.max(0, math.min(1, startPos + (startY - cy) / span)))  -- drag down -> toward bottom
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local sc = UIParent:GetEffectiveScale()
        local cy = select(2, GetCursorPosition()) / sc
        local top, trackH = track:GetTop(), track:GetHeight()
        if top and trackH > 0 then sb.onDrag(math.max(0, math.min(1, (top - cy) / trackH))) end
    end)
    return sb
end

-- Sync the legend's scrollbar thumb to its current scroll (uses the freshly-measured
-- content height w._legendContentH, since GetVerticalScrollRange lags one layout pass).
local function updateLegendBar(w)
    if not w.legendSB then return end
    local view    = w.legend:GetHeight() or 0
    local content = w._legendContentH or 0
    local range   = math.max(0, content - view)
    local sizeFrac = (content > 0) and math.min(1, view / content) or 1
    local posFrac  = (range > 0) and ((w.legend:GetVerticalScroll() or 0) / range) or 0
    w.legendSB.update(posFrac, sizeFrac)
end

-- Repaint the visible slice of the plot (virtualised: only samples inside the viewport).
local function draw(w)
    if w._drawing then return end
    w._drawing = true
    local sf, canvas = w.scroll, w.canvas
    local vpW, vpH = sf:GetWidth(), sf:GetHeight()
    if vpW and vpW > 1 and vpH and vpH > 1 then
        local n  = w.sampleCount or 0
        local sp = w.xSpacing
        canvas:SetHeight(vpH)
        local contentW = math.max(vpW, PAD_X * 2 + math.max(0, n - 1) * sp)
        canvas:SetWidth(contentW)

        -- Auto Y-scale to the largest value across every plotted series.
        local maxV = 0
        for _, name in ipairs(w.selected) do
            local s = w.series[name]
            if s then for k = 1, #s do local v = s[k]; if v and v > maxV then maxV = v end end end
        end
        if maxV <= 0 then maxV = (w.metric == "cpu") and 1 or 1024 end
        local innerH = vpH - PAD_T2 - PAD_B2; if innerH < 10 then innerH = 10 end
        local yz = w.yZoom or 1
        -- Y panning: with yz>1 only a maxV/yz slice is visible; yScroll is the value at the
        -- BOTTOM of that slice, clamped so the slice stays inside [0, maxV].
        local yMaxScroll = math.max(0, maxV - maxV / yz)
        local yScroll = math.max(0, math.min(yMaxScroll, w.yScroll or 0))
        w.yScroll, w._maxV2, w._yMaxScroll = yScroll, maxV, yMaxScroll
        local function yOf(v) return PAD_B2 + ((v - yScroll) / maxV) * innerH * yz end
        local function xOf(i) return PAD_X + (i - 1) * sp end
        -- Labels reflect the visible value window (bottom = yScroll, top = yScroll+maxV/yz).
        w.yTop:SetText(w.fmtY(yScroll + maxV / yz)); w.yBot:SetText(w.fmtY(yScroll))
        -- Y scrollbar: thumb size = visible fraction (1/yz); top of track = high values.
        w.ybar.update((yMaxScroll > 0) and (1 - yScroll / yMaxScroll) or 0, 1 / yz)

        -- Visible sample range (one extra each side so clipped lines still connect).
        local scrollX = sf:GetHorizontalScroll() or 0
        local i0 = math.floor((scrollX - PAD_X) / sp) + 1 - 1
        local i1 = math.ceil((scrollX + vpW - PAD_X) / sp) + 1 + 1
        if i0 < 1 then i0 = 1 end
        if i1 > n then i1 = n end
        w._maxV, w._innerH, w._i0, w._i1 = maxV, innerH, i0, i1   -- for the hover overlay

        local showDiff = (GUCfg() or {}).showDiff == true
        local li, di, lbi = 0, 0, 0
        for _, name in ipairs(w.selected) do
            local s = w.series[name]
            if s and #s > 0 then
                local cr, cg, cb = colorOf(w, name)
                for i = i0, i1 do
                    local v = s[i]
                    if v ~= nil then
                        local x, y = xOf(i), yOf(v)
                        if i > 1 and s[i - 1] ~= nil then
                            li = li + 1
                            local ln = acquireLine(w, li)
                            ln:SetStartPoint("BOTTOMLEFT", canvas, xOf(i - 1), yOf(s[i - 1]))
                            ln:SetEndPoint("BOTTOMLEFT", canvas, x, y)
                            ln:SetColorTexture(cr, cg, cb, 0.9)
                            ln:Show()
                        end
                        di = di + 1
                        local dot = acquireDot(w, di)
                        dot:ClearAllPoints(); dot:SetPoint("CENTER", canvas, "BOTTOMLEFT", x, y)
                        dot:SetColorTexture(cr, cg, cb, 1); dot:Show()
                        if showDiff and i > 1 and s[i - 1] ~= nil then
                            local d = v - s[i - 1]
                            lbi = lbi + 1
                            local lb = acquireLabel(w, lbi)
                            lb:ClearAllPoints(); lb:SetPoint("TOP", canvas, "BOTTOMLEFT", x, y - 3)
                            lb:SetText(w.fmtDiff(d))
                            lb:SetTextColor(diffTier(d, w.greyT, w.bigT))
                            lb:Show()
                        end
                    end
                end
            end
        end
        for k = li + 1,  #w.lines  do w.lines[k]:Hide()  end
        for k = di + 1,  #w.dots   do w.dots[k]:Hide()   end
        for k = lbi + 1, #w.labels do w.labels[k]:Hide() end

        updateHBar(w, contentW, vpW)
    end
    w._drawing = false
end

-- Rebuild the colour/name legend on the right (called on open + on brand/resize change).
local function rebuildLegend(w)
    local childW = w.legend:GetWidth(); if not childW or childW < 1 then childW = LEGEND_W end
    w.legendChild:SetWidth(childW)
    local ly = 0
    for idx, name in ipairs(w.selected) do
        local row = w.legendRows[idx]
        if not row then
            row = {}
            row.swatch = w.legendChild:CreateTexture(nil, "OVERLAY")
            row.swatch:SetSize(10, 10)
            row.text = w.legendChild:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
            row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
            row.text:SetPoint("LEFT", row.swatch, "RIGHT", 5, 0)
            w.legendRows[idx] = row
        end
        row.text:SetWidth(childW - 18)
        row.swatch:ClearAllPoints(); row.swatch:SetPoint("TOPLEFT", w.legendChild, "TOPLEFT", 0, -ly)
        row.swatch:SetColorTexture(colorOf(w, name)); row.swatch:Show()
        row.text:SetText(w.titles[name] or name); row.text:Show()
        ly = ly + 16
    end
    for k = #w.selected + 1, #w.legendRows do
        w.legendRows[k].swatch:Hide(); w.legendRows[k].text:Hide()
    end
    w.legendChild:SetHeight(math.max(1, ly))
    w._legendContentH = ly
    -- Clamp against the freshly-computed content height, not GetVerticalScrollRange()
    -- (which lags one layout pass after SetHeight), so shrinking/enlarging never leaves
    -- the legend scrolled past its content. Clamping to maxScroll also keeps position.
    local maxScroll = math.max(0, ly - (w.legend:GetHeight() or 0))
    if (w.legend:GetVerticalScroll() or 0) > maxScroll then w.legend:SetVerticalScroll(maxScroll) end
    updateLegendBar(w)
    w.empty:SetShown(#w.selected == 0)
end

-- Take one reading for every plotted addon and append it to its series.
local function sample(w)
    -- Defence in depth: if the debug suite was re-locked while a window is open, shut it
    -- down (hiding fires OnHide -> stopTicker) so nothing keeps polling once locked.
    if not ns.IsDebugUnlocked() then
        if w.ticker then w.ticker:Cancel(); w.ticker = nil end
        w.frame:Hide(); return
    end
    if #w.selected == 0 then return end
    if w.metric == "cpu" then
        local on = ProfilerOn()
        w.notice:SetShown(not on)
        w.enableBtn.frame:SetShown(not on)
        for _, name in ipairs(w.selected) do
            local v = on and (C_AddOnProfiler.GetAddOnMetric(name, RECENT) or 0) or 0
            local s = w.series[name]; s[#s + 1] = v
            if #s > SAMPLE_CAP then table.remove(s, 1) end
        end
    else
        UpdateAddOnMemoryUsage()
        for _, name in ipairs(w.selected) do
            local v = GetAddOnMemoryUsage(name) or 0
            local s = w.series[name]; s[#s + 1] = v
            if #s > SAMPLE_CAP then table.remove(s, 1) end
        end
    end
    w.sampleCount = math.min((w.sampleCount or 0) + 1, SAMPLE_CAP)

    -- Follow the newest sample only if the view was already pinned to the right edge.
    local sf   = w.scroll
    local vpW  = sf:GetWidth() or 0
    local oldMax = math.max(0, (w.canvas:GetWidth() or 0) - vpW)
    local atEdge = (sf:GetHorizontalScroll() or 0) >= oldMax - 1
    draw(w)
    if atEdge then
        local newMax = math.max(0, (w.canvas:GetWidth() or 0) - vpW)
        sf:SetHorizontalScroll(newMax)
    end
end

local function startTicker(w)
    if w.ticker or not w.refreshing then return end   -- paused via the Stop refresh toggle
    local iv = tonumber((GUCfg() or {}).interval) or 5; if iv < 1 then iv = 1 end
    w.ticker = C_Timer.NewTicker(iv, function() sample(w) end)
end
local function stopTicker(w)
    if w.ticker then w.ticker:Cancel(); w.ticker = nil end
end

-- Snapshot the current selection (for this metric) into fresh series + colours.
local function resetData(w)
    wipe(w.series); wipe(w.colors); wipe(w.titles)
    w.selected   = {}
    w.sampleCount = 0
    w.xSpacing   = DEFAULT_SP
    w.yZoom      = 1
    w.yScroll    = 0
    local sel    = (GUCfg() or {})[w.metric] or {}
    local hueSeed = math.random()
    local ci = 0
    for _, a in ipairs(AddonList()) do
        if sel[a.name] then
            w.selected[#w.selected + 1] = a.name
            w.series[a.name] = {}
            w.titles[a.name] = a.title
            if a.name ~= "UnbunkUtility" then
                ci = ci + 1
                w.colors[a.name] = { hsv((hueSeed + ci * 0.61803) % 1, 0.72, 0.95) }
            end
        end
    end
    w.scroll:SetHorizontalScroll(0)
end

local function BuildWindow(metric)
    local isCPU   = (metric == "cpu")
    local frameName = "UnbunkUtilityGraph" .. (isCPU and "CPU" or "Mem")
    local w = {
        metric = metric, series = {}, colors = {}, titles = {}, selected = {},
        lines = {}, dots = {}, labels = {}, legendRows = {}, sampleCount = 0, xSpacing = DEFAULT_SP,
        yZoom = 1, yScroll = 0, refreshing = true,
        fmtY    = isCPU and fmtCPUaxis or fmtMem,
        fmtDiff = isCPU and fmtDiffCPU or fmtDiffMem,
        greyT   = isCPU and CPU_GREY or MEM_GREY,
        bigT    = isCPU and CPU_BIG  or MEM_BIG,
    }

    local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    w.frame = f
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER", UIParent, "CENTER", isCPU and -30 or 30, isCPU and 30 or -30)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(480, 320)
    elseif f.SetMinResize then f:SetMinResize(480, 320) end
    -- Restore the per-profile saved size (set by the resize grip; see below).
    local gv0 = GUCfg(); local savedSize = gv0 and gv0.win and gv0.win[metric]
    if savedSize and savedSize.w and savedSize.h then f:SetSize(savedSize.w, savedSize.h) end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()
    table.insert(UISpecialFrames, frameName)   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH1")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText(isCPU and L["CPU usage graph"] or L["Memory usage graph"])

    local closeBtn = ns.ui.CreateButton({ parent = f, label = "X", width = 24, height = 22 })
    closeBtn.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    closeBtn.frame:SetScript("OnClick", function() f:Hide() end)

    -- Start/Stop refresh toggle: pause the sampling ticker to inspect a frozen graph,
    -- resume to keep plotting (data is kept, not reset — reopen for a fresh graph).
    local refreshBtn = ns.ui.CreateButton({ parent = f, label = L["Stop refresh"], width = 110, height = 22 })
    refreshBtn.frame:SetPoint("RIGHT", closeBtn.frame, "LEFT", -6, 0)
    w.refreshBtn = refreshBtn
    refreshBtn.frame:SetScript("OnClick", function()
        w.refreshing = not w.refreshing
        refreshBtn.SetText(w.refreshing and L["Stop refresh"] or L["Start refresh"])
        if w.refreshing then startTicker(w) else stopTicker(w) end
    end)

    -- CPU-profiling-off notice + a live enable button (no reload).
    w.notice = f:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
    w.notice:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
    w.notice:SetTextColor(1, 0.5, 0.2); w.notice:SetText(L["Addon CPU profiling is off."])
    w.notice:Hide()
    w.enableBtn = ns.ui.CreateButton({
        parent = f, label = L["Enable addon profiling"], width = 170, height = 18,
        onClick = function()
            local setc = (C_CVar and C_CVar.SetCVar) or SetCVar
            if setc then setc("addonProfilerEnabled", "1") end
        end,
    })
    w.enableBtn.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 230, -32)
    w.enableBtn.frame:Hide()

    -- Plot background (border + dark fill); the scroll frame sits just inside it.
    local plotBG = CreateFrame("Frame", nil, f, "BackdropTemplate")
    plotBG:SetPoint("TOPLEFT", f, "TOPLEFT", PLOT_L, -PLOT_T)
    plotBG:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PLOT_R, PLOT_B)
    plotBG:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    plotBG:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
    plotBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", plotBG, "TOPLEFT", 1, -1)
    scroll:SetPoint("BOTTOMRIGHT", plotBG, "BOTTOMRIGHT", -1, 1)
    w.scroll = scroll
    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(10, 10)
    scroll:SetScrollChild(canvas)
    w.canvas = canvas

    -- "select addons" placeholder, shown when nothing is plotted.
    w.empty = plotBG:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    w.empty:SetPoint("CENTER", plotBG, "CENTER", 0, 0)
    w.empty:SetTextColor(0.7, 0.7, 0.7)
    w.empty:SetText(isCPU and L["Tick addons in the CPU column, then reopen."]
                          or L["Tick addons in the Memory column, then reopen."])

    -- Y-axis labels (top of visible window at top, bottom at the baseline), left margin.
    -- Right edge sits left of the Y scrollbar (which hugs the plot's left border).
    w.yTop = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
    w.yTop:SetPoint("RIGHT", plotBG, "TOPLEFT", -13, -PAD_T2)
    w.yTop:SetJustifyH("RIGHT"); w.yTop:SetWidth(PLOT_L - 18)
    w.yBot = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
    w.yBot:SetPoint("RIGHT", plotBG, "BOTTOMLEFT", -13, PAD_B2)
    w.yBot:SetJustifyH("RIGHT"); w.yBot:SetWidth(PLOT_L - 18)

    -- Legend column (top-right). A ScrollFrame so a long addon list never spills out of
    -- the window — the rows live on a scroll child, scrolled by the wheel or its scrollbar.
    local legend = CreateFrame("ScrollFrame", nil, f)
    legend:SetPoint("TOPLEFT", plotBG, "TOPRIGHT", 12, 0)
    legend:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, PLOT_B)   -- room for its scrollbar
    local legendChild = CreateFrame("Frame", nil, legend)
    legendChild:SetSize(LEGEND_W, 10)
    legend:SetScrollChild(legendChild)
    w.legend = legend
    w.legendChild = legendChild

    local legendSB = makeVScroll(f)
    legendSB.track:ClearAllPoints()
    legendSB.track:SetPoint("TOPLEFT", legend, "TOPRIGHT", 4, 0)
    legendSB.track:SetPoint("BOTTOMLEFT", legend, "BOTTOMRIGHT", 4, 0)
    legendSB.onDrag = function(frac)
        local range = math.max(0, (w._legendContentH or 0) - (legend:GetHeight() or 0))
        legend:SetVerticalScroll(frac * range)
    end
    w.legendSB = legendSB
    local function legendScroll(delta)
        local range = math.max(0, (w._legendContentH or 0) - (legend:GetHeight() or 0))
        legend:SetVerticalScroll(math.max(0, math.min(range, (legend:GetVerticalScroll() or 0) - delta * 16)))
    end
    legend:EnableMouseWheel(true)
    legend:SetScript("OnMouseWheel", function(_, delta) legendScroll(delta) end)
    legend:SetScript("OnVerticalScroll", function() updateLegendBar(w) end)

    scroll:SetScript("OnHorizontalScroll", function() draw(w) end)

    -- X zoom: change the per-sample spacing, keeping the viewport centre fixed.
    local function applyZoom(delta)
        local old = w.xSpacing
        local nw  = math.max(MIN_SP, math.min(MAX_SP, old * (delta > 0 and 1.25 or 0.8)))
        if nw == old then return end
        local vpW     = scroll:GetWidth() or 0
        local centerS = ((scroll:GetHorizontalScroll() or 0) + vpW / 2 - PAD_X) / old
        w.xSpacing = nw
        draw(w)
        local newMax    = math.max(0, (canvas:GetWidth() or 0) - vpW)
        local newScroll = PAD_X + centerS * nw - vpW / 2
        scroll:SetHorizontalScroll(math.max(0, math.min(newMax, newScroll)))
    end

    -- Y zoom: scale the value->pixel mapping (anchored at the 0 baseline). >1 magnifies low
    -- values (top label becomes maxV/yZoom; points above clip at the top), <1 adds headroom.
    local function applyZoomY(delta)
        local old = w.yZoom or 1
        local nw  = math.max(Y_MIN_ZOOM, math.min(Y_MAX_ZOOM, old * (delta > 0 and 1.25 or 0.8)))
        if nw == old then return end
        w.yZoom = nw
        draw(w)
    end

    -- Shift+wheel pans the X (time) axis; Alt+wheel pans the Y (value) axis.
    local function panX(delta)
        local vpW = scroll:GetWidth() or 0
        local maxScroll = math.max(0, (canvas:GetWidth() or 0) - vpW)
        if maxScroll <= 0 then return end
        local step = math.max(vpW * 0.2, w.xSpacing * 2)
        scroll:SetHorizontalScroll(math.max(0, math.min(maxScroll, (scroll:GetHorizontalScroll() or 0) - delta * step)))
    end
    local function panY(delta)
        local yMax = w._yMaxScroll or 0
        if yMax <= 0 then return end
        local step = ((w._maxV2 or 1) / (w.yZoom or 1)) * 0.15   -- 15% of the visible window
        w.yScroll = math.max(0, math.min(yMax, (w.yScroll or 0) + delta * step))
        draw(w)
    end

    -- Auto buttons: reset an axis to its default view.
    local function autoX() w.xSpacing = DEFAULT_SP; draw(w); scroll:SetHorizontalScroll(math.max(0, (canvas:GetWidth() or 0) - (scroll:GetWidth() or 0))) end
    local function autoY() w.yZoom = 1; w.yScroll = 0; draw(w) end

    -- Transparent hit overlay over the plot: textures/lines can't take the mouse, so this
    -- frame (above the canvas) owns the wheel zoom AND, while hovered, tracks the cursor to
    -- show the addon name (+ value) of the nearest plotted point or line segment.
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 5)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    -- Plain wheel = X zoom; Ctrl = Y zoom; Shift = X pan; Alt = Y pan.
    overlay:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() then applyZoomY(delta)
        elseif IsShiftKeyDown() then panX(delta)
        elseif IsAltKeyDown() then panY(delta)
        else applyZoom(delta) end
    end)

    local HIT2 = 100   -- squared pixel radius (10px) for "close enough" to a point/segment
    local function hoverUpdate()
        local maxV, innerH = w._maxV, w._innerH
        if not maxV or not innerH or #w.selected == 0 then GameTooltip:Hide(); return end
        local cl, cb = canvas:GetLeft(), canvas:GetBottom()
        if not cl or not cb then return end
        local sc = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        local px, py = mx / sc - cl, my / sc - cb   -- cursor in canvas coords (y from bottom)
        local sp = w.xSpacing
        local yz = w.yZoom or 1   -- must match draw()'s yOf so the hit-test lands on the dots
        local ys = w.yScroll or 0
        local i0, i1 = (w._i0 or 1), (w._i1 or 0)
        local bestD, bestName, bestVal = HIT2, nil, nil
        for _, name in ipairs(w.selected) do
            local s = w.series[name]
            if s then
                for i = i0, i1 do
                    local v = s[i]
                    if v ~= nil then
                        local x, y = PAD_X + (i - 1) * sp, PAD_B2 + ((v - ys) / maxV) * innerH * yz
                        local dx, dy = px - x, py - y
                        local d = dx * dx + dy * dy
                        if d < bestD then bestD, bestName, bestVal = d, name, v end
                        if i > 1 and s[i - 1] ~= nil then   -- distance to the segment too
                            local ax, ay = PAD_X + (i - 2) * sp, PAD_B2 + ((s[i - 1] - ys) / maxV) * innerH * yz
                            local vx, vy = x - ax, y - ay
                            local len2 = vx * vx + vy * vy
                            local t = (len2 > 0) and ((px - ax) * vx + (py - ay) * vy) / len2 or 0
                            if t < 0 then t = 0 elseif t > 1 then t = 1 end
                            local sdx, sdy = px - (ax + t * vx), py - (ay + t * vy)
                            local sd = sdx * sdx + sdy * sdy
                            -- report the value of whichever endpoint the cursor is nearer
                            -- (t toward 0 = left point s[i-1], toward 1 = right point v).
                            if sd < bestD then bestD, bestName, bestVal = sd, name, (t < 0.5) and s[i - 1] or v end
                        end
                    end
                end
            end
        end
        if bestName then
            GameTooltip:SetOwner(overlay, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(w.titles[bestName] or bestName, colorOf(w, bestName))
            GameTooltip:AddLine(w.fmtY(bestVal), 1, 1, 1)
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end
    overlay:SetScript("OnEnter", function() overlay:SetScript("OnUpdate", hoverUpdate) end)
    overlay:SetScript("OnLeave", function() overlay:SetScript("OnUpdate", nil); GameTooltip:Hide() end)
    w.overlay = overlay

    -- Vertical scrollbar for the Y (value) axis: hugs the plot's left border, pans the
    -- visible value window when zoomed in. Top of the track = high values.
    local ybar = makeVScroll(f)
    ybar.track:ClearAllPoints()
    ybar.track:SetPoint("TOPRIGHT", plotBG, "TOPLEFT", -3, 0)
    ybar.track:SetPoint("BOTTOMRIGHT", plotBG, "BOTTOMLEFT", -3, 0)
    ybar.onDrag = function(frac)   -- frac 0 = top (high values) -> yScroll = yMaxScroll
        local yMax = w._yMaxScroll or 0
        w.yScroll = (1 - frac) * yMax
        draw(w)
    end
    w.ybar = ybar

    -- Axis zoom + auto buttons (same effect as the wheel, no modifier key needed).
    local function smallBtn(label, wdt, onClick)
        local b = ns.ui.CreateButton({ parent = f, label = label, width = wdt, height = 16, onClick = onClick })
        b.frame:SetFrameLevel(overlay:GetFrameLevel() + 2)   -- above the hit overlay
        return b
    end
    -- Y: stacked +/- in the left margin (beside the value axis), and an "Auto" button
    -- under the max-value label that restores automatic Y scaling.
    local yPlus  = smallBtn("+", 18, function() applyZoomY(1) end)
    yPlus.frame:SetPoint("BOTTOM", plotBG, "LEFT", -22, 2)
    local yMinus = smallBtn("-", 18, function() applyZoomY(-1) end)
    yMinus.frame:SetPoint("TOP", plotBG, "LEFT", -22, -2)
    local autoYBtn = smallBtn(L["Auto"], PLOT_L - 18, autoY)
    autoYBtn.frame:SetPoint("TOPRIGHT", w.yTop, "BOTTOMRIGHT", 0, -3)

    -- X: +/- centred under the X scrollbar, and an "Auto" button at the far right of
    -- that same row that restores the default time-axis zoom.
    local xMinus = smallBtn("-", 18, function() applyZoom(-1) end)
    xMinus.frame:SetPoint("RIGHT", plotBG, "BOTTOM", -2, -34)
    local xPlus  = smallBtn("+", 18, function() applyZoom(1) end)
    xPlus.frame:SetPoint("LEFT", plotBG, "BOTTOM", 2, -34)
    local autoXBtn = smallBtn(L["Auto"], 44, autoX)
    autoXBtn.frame:SetPoint("RIGHT", plotBG, "BOTTOMRIGHT", 0, -34)

    -- Horizontal scrollbar below the plot (track + draggable thumb).
    local track = CreateFrame("Frame", nil, f, "BackdropTemplate")
    track:SetHeight(10)
    track:SetPoint("BOTTOMLEFT", plotBG, "BOTTOMLEFT", 0, -16)
    track:SetPoint("BOTTOMRIGHT", plotBG, "BOTTOMRIGHT", 0, -16)
    track:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    track:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetHeight(10)
    local ttex = thumb:CreateTexture(nil, "OVERLAY"); ttex:SetAllPoints(); ttex:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    w.hbar = { track = track, thumb = thumb }
    thumb:EnableMouse(true)
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local startX = GetCursorPosition() / UIParent:GetEffectiveScale()
        local startScroll = scroll:GetHorizontalScroll() or 0
        thumb:SetScript("OnUpdate", function()
            local cw = canvas:GetWidth() or 0; local vpW = scroll:GetWidth() or 0
            local maxScroll = math.max(0, cw - vpW)
            local span = track:GetWidth() - thumb:GetWidth()
            if span <= 0 or maxScroll <= 0 then return end
            local curX = GetCursorPosition() / UIParent:GetEffectiveScale()
            scroll:SetHorizontalScroll(math.max(0, math.min(maxScroll, startScroll + ((curX - startX) / span) * maxScroll)))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local cw = canvas:GetWidth() or 0; local vpW = scroll:GetWidth() or 0
        local maxScroll = math.max(0, cw - vpW); if maxScroll <= 0 then return end
        local frac = math.max(0, math.min(1, (GetCursorPosition() / UIParent:GetEffectiveScale() - track:GetLeft()) / track:GetWidth()))
        scroll:SetHorizontalScroll(frac * maxScroll)
    end)

    -- Bottom-right resize triangle: drag to size the window freely (matches the Console).
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    local gNorm = grip:GetNormalTexture(); if gNorm then gNorm:SetVertexColor(0.7, 0.7, 0.7) end
    local gHi   = grip:GetHighlightTexture(); if gHi then ns.SetBrandVertex(gHi) end
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        -- Persist the new size per profile (so it restores on reopen / per profile).
        local gv = GUCfg()
        if gv then
            gv.win = gv.win or {}
            gv.win[metric] = { w = math.floor(f:GetWidth() + 0.5), h = math.floor(f:GetHeight() + 0.5) }
        end
        draw(w); rebuildLegend(w)
    end)

    -- Keep the UnbunkUtility line/legend swatch in sync with a live brand-colour change
    -- (the window chrome stays grey to match the Console window).
    if ns.RegisterBrandRefresh then
        ns.RegisterBrandRefresh(f, function() rebuildLegend(w); draw(w) end)
    end

    f:SetScript("OnSizeChanged", function() draw(w); rebuildLegend(w) end)
    f:HookScript("OnShow", function() draw(w) end)
    f:HookScript("OnHide", function() stopTicker(w) end)
    return w
end

local function GetWindow(metric)
    if not windows[metric] then windows[metric] = BuildWindow(metric) end
    return windows[metric]
end

-- Open (or re-open) a metric's graph: fresh data, snapshot the current selection, plot.
local function ShowGraph(metric)
    if not ns.IsDebugUnlocked() then return end
    local w = GetWindow(metric)
    w.frame:Show(); w.frame:Raise()
    stopTicker(w)
    w.refreshing = true   -- a fresh open always resumes live sampling
    if w.refreshBtn then w.refreshBtn.SetText(L["Stop refresh"]) end
    resetData(w)
    rebuildLegend(w)
    sample(w)        -- first point immediately
    draw(w)
    startTicker(w)
end

-- Force-close every open graph window (used by the debug re-lock path in ConfigWindow.lua).
-- Hiding each frame fires its OnHide hook, which cancels the sampling ticker.
function ns.Debug_CloseGraphs()
    for _, w in pairs(windows) do
        if w.frame then w.frame:Hide() end
    end
end

-- Re-apply the (per-profile) saved window sizes to any open graph windows — called on a
-- profile switch so an open graph adopts the new profile's saved size.
function ns.Debug_ReapplyGraphSizes()
    local gv = GUCfg(); local wins = gv and gv.win or {}
    for metric, w in pairs(windows) do
        if w.frame and w.frame:IsShown() then
            local s = wins[metric]
            if s and s.w and s.h then
                w.frame:SetSize(s.w, s.h)         -- this profile's saved size
            else
                w.frame:SetSize(WIN_W, WIN_H)     -- new profile has none -> default
            end                                   -- (OnSizeChanged re-draws + relays the legend)
        end
    end
end

-- ── Config panel ─────────────────────────────────────────────────────────────
local BOX_W   = 504
local COL_CPU = 330
local COL_MEM = 422
local ROW_H   = 24

local function CreateCadre(parent, ww, hh)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(ww, hh)
    box:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    return box
end

local function CreateGraphPanel(parent)
    local c = GUCfg() or {}
    local cpuChecks, memChecks, rowNames = {}, {}, {}
    local y = 14

    local title = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
    title:SetText(L["Graph"])
    y = y + 30

    -- ── Cadre 1: interval, then show differential, then the Show Graph buttons ───
    local ctrl = CreateCadre(parent, BOX_W, 122)
    ctrl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)

    local ilabel = ctrl:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    ilabel:SetPoint("TOPLEFT", ctrl, "TOPLEFT", 14, -16)
    ilabel:SetText(L["Refresh every"])
    local interval = ns.ui.CreateTextInput({
        parent = ctrl, width = 46, height = 22, numeric = true, min = 1, max = 3600,
        maxLetters = 4, text = tostring(c.interval or 5),
        onEnter = function(val)
            local cc = GUCfg()
            if cc and val and val > 0 then cc.interval = val end
            -- Re-arm the ticker of any open window so the new cadence applies live.
            for _, w in pairs(windows) do
                if w.frame:IsShown() then stopTicker(w); startTicker(w) end
            end
        end,
    })
    interval.frame:SetPoint("LEFT", ilabel, "RIGHT", 8, 0)
    local isec = ctrl:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    isec:SetPoint("LEFT", interval.frame, "RIGHT", 6, 0)
    isec:SetText(L["seconds"])

    -- Row 2: show differential (between the interval row and the Show Graph buttons).
    local diffCB = ns.ui.CreateCheckbox({
        parent  = ctrl,
        label   = L["Show differential"],
        checked = c.showDiff ~= false,
        onClick = function(v)
            local cc = GUCfg(); if cc then cc.showDiff = v and true or false end
            -- re-paint any open window so the change shows without reopening
            for _, w in pairs(windows) do if w.frame:IsShown() then draw(w) end end
        end,
    })
    diffCB.frame:SetPoint("TOPLEFT", ctrl, "TOPLEFT", 12, -48)

    -- Row 3: the Show Graph buttons.
    local cpuBtn = ns.ui.CreateButton({
        parent = ctrl, label = L["Show CPU Graph"], width = 150, height = 22,
        onClick = function() ShowGraph("cpu") end,
    })
    cpuBtn.frame:SetPoint("TOPLEFT", ctrl, "TOPLEFT", 14, -82)
    local memBtn = ns.ui.CreateButton({
        parent = ctrl, label = L["Show Memory Graph"], width = 170, height = 22,
        onClick = function() ShowGraph("mem") end,
    })
    memBtn.frame:SetPoint("LEFT", cpuBtn.frame, "RIGHT", 8, 0)

    y = y + 122 + 14

    -- ── Cadre 2: addon list with CPU / Memory columns ───────────────────────────
    local rows = AddonList()
    local HEAD_Y, BTN_Y, LIST_Y = 10, 30, 58
    local list = CreateCadre(parent, BOX_W, LIST_Y + #rows * ROW_H + 10)
    list:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)

    local hcpu = list:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    hcpu:SetPoint("TOPLEFT", list, "TOPLEFT", COL_CPU - 4, -HEAD_Y); hcpu:SetText(L["CPU"])
    local hmem = list:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    hmem:SetPoint("TOPLEFT", list, "TOPLEFT", COL_MEM - 4, -HEAD_Y); hmem:SetText(L["Memory"])

    local function setColumn(checks, key, value)
        local cc = GUCfg(); if not cc then return end
        cc[key] = cc[key] or {}
        for i, cb in ipairs(checks) do
            cb.SetChecked(value)
            cc[key][rowNames[i]] = value and true or nil
        end
    end
    local function bulkButtons(colX, checks, key)
        local all = ns.ui.CreateButton({ parent = list, label = L["All"], width = 36, height = 18,
            onClick = function() setColumn(checks, key, true) end })
        all.frame:SetPoint("TOPLEFT", list, "TOPLEFT", colX - 8, -BTN_Y)
        local none = ns.ui.CreateButton({ parent = list, label = L["None"], width = 40, height = 18,
            onClick = function() setColumn(checks, key, false) end })
        none.frame:SetPoint("LEFT", all.frame, "RIGHT", 2, 0)
    end
    bulkButtons(COL_CPU, cpuChecks, "cpu")
    bulkButtons(COL_MEM, memChecks, "mem")

    local ly = LIST_Y
    for _, a in ipairs(rows) do
        rowNames[#rowNames + 1] = a.name
        local idx = #rowNames

        local nameFS = list:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
        nameFS:SetPoint("TOPLEFT", list, "TOPLEFT", 14, -ly - 3)
        nameFS:SetWidth(COL_CPU - 26); nameFS:SetJustifyH("LEFT"); nameFS:SetWordWrap(false)
        nameFS:SetText(a.title)

        local cpuCB = ns.ui.CreateCheckbox({
            parent = list, label = "", checked = (c.cpu or {})[a.name] == true,
            onClick = function(v)
                local cc = GUCfg()
                if cc then cc.cpu = cc.cpu or {}; cc.cpu[a.name] = v and true or nil end
            end,
        })
        cpuCB.frame:SetWidth(24)
        cpuCB.frame:SetPoint("TOPLEFT", list, "TOPLEFT", COL_CPU, -ly)
        cpuChecks[idx] = cpuCB

        local memCB = ns.ui.CreateCheckbox({
            parent = list, label = "", checked = (c.mem or {})[a.name] == true,
            onClick = function(v)
                local cc = GUCfg()
                if cc then cc.mem = cc.mem or {}; cc.mem[a.name] = v and true or nil end
            end,
        })
        memCB.frame:SetWidth(24)
        memCB.frame:SetPoint("TOPLEFT", list, "TOPLEFT", COL_MEM, -ly)
        memChecks[idx] = memCB

        ly = ly + ROW_H
    end

    return nil
end

-- Register the panel once the addon (and ns.db) have loaded.
local initGP = CreateFrame("Frame")
initGP:RegisterEvent("ADDON_LOADED")
initGP:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Graph"], nil, CreateGraphPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
