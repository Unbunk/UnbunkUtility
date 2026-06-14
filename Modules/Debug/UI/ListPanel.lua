-- Modules/Debug/UI/ListPanel.lua
-- Debug Utilities > Addon usage > List.
--
-- A live, sortable table of every addon's CPU and memory, modelled on Blizzard's
-- Addon Profiler (studied the "!!AddonProfiler" addon):
--   CPU    = C_AddOnProfiler recent-average ms per frame (Enum.AddOnProfilerMetric.
--            RecentAverageTime) — gated by the `addonProfilerEnabled` CVar, which is
--            toggled live (NO reload, unlike scriptProfile).
--   Memory = GetAddOnMemoryUsage (KB), refreshed each tick.
-- A "Total" row mirrors C_AddOnProfiler.GetOverallMetric + the summed memory. Click a
-- column header to sort; the table refreshes ~1/s while the sub-tab is shown.

local _, ns = ...
local L = ns.L

-- Defensive API shims (Interface 120005: C_AddOns.* is canonical, keep a fallback).
local getNum  = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo

local RECENT = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime

local function ProfilerOn()
    return RECENT ~= nil and C_AddOnProfiler and C_AddOnProfiler.IsEnabled and C_AddOnProfiler.IsEnabled()
end

local function clean(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")   -- legacy |cAARRGGBB colour
    s = s:gsub("|cn.-:", "")               -- modern named colour |cnCOLOR:
    s = s:gsub("|r", ""):gsub("|T.-|t", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function fmtMem(kb)
    if not kb or kb < 0.5 then return "0 KB" end
    if kb >= 1024 then return string.format("%.2f MB", kb / 1024) end
    return string.format("%.0f KB", kb)
end
local function fmtCPU(ms)
    if ms == nil then return "—" end
    return string.format("%.2f ms", ms)
end

-- Layout (right edges of the numeric columns; the name column fills the left).
local COL_CPU, COL_MEM = 348, 478
local ROW_H, LIST_TOP  = 18, 108

local function CreateListPanel(parent)
    local sortKey, sortDir = "cpu", true   -- "cpu" | "mem" | "name"; dir true = descending
    local rows, builtRows  = {}, 0
    local headers          = {}
    local ticker
    local refreshing       = true
    local startTicker, stopTicker, setRefreshing   -- forward-declared (defined below)

    local title = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -14)
    title:SetText(L["List"])

    -- Start/Stop refresh toggle (top-right): pause the live updates to inspect a frozen
    -- snapshot, resume to track live again.
    local refreshBtn = ns.ui.CreateButton({
        parent = parent, label = L["Stop refresh"], width = 110, height = 20,
        onClick = function() if setRefreshing then setRefreshing(not refreshing) end end,
    })
    refreshBtn.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -12)

    -- Notice / hint line (y=44): enable prompt when profiling is off, else a sort hint.
    local notice = parent:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
    notice:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -46)
    notice:SetWidth(300); notice:SetJustifyH("LEFT")
    local enableBtn = ns.ui.CreateButton({
        parent = parent, label = L["Enable addon profiling"], width = 170, height = 20,
        onClick = function()
            local setc = (C_CVar and C_CVar.SetCVar) or SetCVar
            if setc then setc("addonProfilerEnabled", "1") end   -- live, no reload
        end,
    })
    enableBtn.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 320, -44)

    -- ── Sortable column headers (y=66) ──────────────────────────────────────────
    local function updateHeaders()
        for _, h in ipairs(headers) do
            local arrow = (sortKey == h.key) and (sortDir and "  v" or "  ^") or ""
            h.fs:SetText(h.base .. arrow)
            if sortKey == h.key then h.fs:SetTextColor(ns.GetBrandColor())
            else h.fs:SetTextColor(0.7, 0.7, 0.7) end
        end
    end
    local refresh   -- fwd
    local function makeHeader(text, key, justify, leftX, rightX, width)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(16)
        if justify == "RIGHT" then
            btn:SetPoint("TOPRIGHT", parent, "TOPLEFT", rightX, -66)
            btn:SetWidth(width)
        else
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", leftX, -66)
            btn:SetWidth(width)
        end
        local fs = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        fs:SetAllPoints(btn); fs:SetJustifyH(justify)
        btn.fs = fs
        btn:SetScript("OnClick", function()
            if sortKey == key then sortDir = not sortDir
            else sortKey, sortDir = key, (key ~= "name") end   -- numbers default desc, name asc
            updateHeaders()
            if refresh then refresh() end
        end)
        headers[#headers + 1] = { fs = fs, key = key, base = text }
    end
    makeHeader(L["Addon"],  "name", "LEFT",  16,  nil, COL_CPU - 70)
    makeHeader(L["CPU"],    "cpu",  "RIGHT", nil, COL_CPU, 70)
    makeHeader(L["Memory"], "mem",  "RIGHT", nil, COL_MEM, 90)

    -- ── Total row (y=86) ────────────────────────────────────────────────────────
    local totName = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
    totName:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -88); totName:SetText(L["Total"])
    totName:SetTextColor(ns.GetBrandColor())
    local totCPU = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
    totCPU:SetPoint("TOPRIGHT", parent, "TOPLEFT", COL_CPU, -88); totCPU:SetWidth(70); totCPU:SetJustifyH("RIGHT")
    totCPU:SetTextColor(ns.GetBrandColor())
    local totMem = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
    totMem:SetPoint("TOPRIGHT", parent, "TOPLEFT", COL_MEM, -88); totMem:SetWidth(90); totMem:SetJustifyH("RIGHT")
    totMem:SetTextColor(ns.GetBrandColor())

    -- ── Row pool ────────────────────────────────────────────────────────────────
    local function ensureRow(i)
        local r = rows[i]; if r then return r end
        r = {}
        local y = LIST_TOP + (i - 1) * ROW_H
        r.name = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        r.name:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
        r.name:SetWidth(COL_CPU - 70 - 16); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.cpu = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        r.cpu:SetPoint("TOPRIGHT", parent, "TOPLEFT", COL_CPU, -y); r.cpu:SetWidth(70); r.cpu:SetJustifyH("RIGHT")
        r.mem = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
        r.mem:SetPoint("TOPRIGHT", parent, "TOPLEFT", COL_MEM, -y); r.mem:SetWidth(90); r.mem:SetJustifyH("RIGHT")
        rows[i] = r
        return r
    end

    -- ── Gather + sort + paint ───────────────────────────────────────────────────
    local function gather()
        UpdateAddOnMemoryUsage()
        local on = ProfilerOn()   -- evaluate the gate once per refresh, not per addon
        local list, totMemKb, totCpuMs = {}, 0, nil
        for i = 1, (getNum and getNum() or 0) do
            local name, ttl = getInfo(i)
            if name then
                local disp = clean(ttl); if disp == "" then disp = name end
                local mem  = GetAddOnMemoryUsage(name) or 0
                local cpu  = on and (C_AddOnProfiler.GetAddOnMetric(name, RECENT) or 0) or nil
                totMemKb = totMemKb + mem
                if cpu then totCpuMs = (totCpuMs or 0) + cpu end
                list[#list + 1] = { title = disp, cpu = cpu, mem = mem }
            end
        end
        local key, dir = sortKey, sortDir
        table.sort(list, function(a, b)
            if key == "name" then
                if dir then return a.title:lower() > b.title:lower() end
                return a.title:lower() < b.title:lower()
            end
            local av = (key == "cpu") and (a.cpu or -1) or a.mem
            local bv = (key == "cpu") and (b.cpu or -1) or b.mem
            if av == bv then return a.title:lower() < b.title:lower() end
            if dir then return av > bv end
            return av < bv
        end)
        return list, totCpuMs, totMemKb
    end

    function refresh()
        -- Notice line: enable prompt while profiling is off, sort hint otherwise.
        if ProfilerOn() then
            notice:SetTextColor(0.6, 0.6, 0.6)
            notice:SetText(L["CPU = recent average ms per frame. Click a column to sort."])
            enableBtn.frame:Hide()
        else
            notice:SetTextColor(1, 0.5, 0.2)
            notice:SetText(L["Addon CPU profiling is off."])
            enableBtn.frame:Show()
        end

        local list, totCpuMs, totMemKb = gather()
        totCPU:SetText(fmtCPU(totCpuMs))
        totMem:SetText(fmtMem(totMemKb))

        for i, a in ipairs(list) do
            local r = ensureRow(i)
            r.name:SetText(a.title); r.cpu:SetText(fmtCPU(a.cpu)); r.mem:SetText(fmtMem(a.mem))
            r.name:Show(); r.cpu:Show(); r.mem:Show()
        end
        for i = #list + 1, #rows do
            rows[i].name:Hide(); rows[i].cpu:Hide(); rows[i].mem:Hide()
        end

        -- Re-measure for the outer scroll only when the row count grows (stable after
        -- the first paint, since the addon roster is fixed for the session).
        if #list > builtRows then
            builtRows = #list
            if ns.ResizeActiveModule then ns.ResizeActiveModule() end
        end
    end

    function startTicker()
        if refreshing and not ticker and parent:IsShown() then
            ticker = C_Timer.NewTicker(1, refresh)
        end
    end
    function stopTicker()
        if ticker then ticker:Cancel(); ticker = nil end
    end
    function setRefreshing(on)
        refreshing = on and true or false
        refreshBtn.SetText(refreshing and L["Stop refresh"] or L["Start refresh"])
        if refreshing then refresh(); startTicker() else stopTicker() end
    end

    updateHeaders()
    refresh()   -- initial paint (creates rows so the outer scroll measures the height)

    -- Keep the brand-blue Total row + active header tinted live when the brand colour
    -- changes (weak-keyed by the panel frame; built once, so a refresh hook is needed).
    if ns.RegisterBrandRefresh then
        ns.RegisterBrandRefresh(parent, function()
            totName:SetTextColor(ns.GetBrandColor())
            totCPU:SetTextColor(ns.GetBrandColor())
            totMem:SetTextColor(ns.GetBrandColor())
            updateHeaders()
        end)
    end

    -- Live refresh only while the sub-tab is shown AND refresh is not paused.
    parent:HookScript("OnShow", function() if refreshing then refresh() end; startTicker() end)
    parent:HookScript("OnHide", stopTicker)

    return nil
end

-- Register the panel once the addon (and ns.db) have loaded.
local initLP = CreateFrame("Frame")
initLP:RegisterEvent("ADDON_LOADED")
initLP:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["List"], nil, CreateListPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
