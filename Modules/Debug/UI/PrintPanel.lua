-- Modules/Debug/UI/PrintPanel.lua
-- Debug Utilities > Addon usage > Print.
--
-- Lists every addon with two checkboxes — CPU usage and Memory usage — and prints
-- the selected addons' usage to chat on a timer (interval in seconds). Per-column
-- "All" / "None" buttons bulk-toggle one metric. Memory works out of the box; CPU
-- needs the `scriptProfile` CVar (enable + reload). The background ticker is gated by
-- ns.IsDebugUnlocked() exactly like the rest of the debug suite — it prints nothing
-- while locked and is cancelled on re-lock.

local _, ns = ...
local L = ns.L

local function PUCfg() return ns.db and ns.db.profile and ns.db.profile.printUsage end

-- Interface 120005: C_AddOns.* is canonical; keep a legacy fallback (codebase idiom).
local getNum  = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo

local function cvarBool(name)
    local f = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
    return f and f(name) and true or false
end
local function CPUProfiling() return cvarBool("scriptProfile") end

-- Strip colour / texture escapes from a title for display + sorting.
local function clean(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn.-:", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Cached, alphabetically-sorted [{name=folder, title=display}] of all addons.
local addonCache
local function AddonList()
    if addonCache then return addonCache end
    local list = {}
    for i = 1, (getNum and getNum() or 0) do
        local name, title = getInfo(i)
        if name then
            local disp = clean(title)
            if disp == "" then disp = name end
            list[#list + 1] = { name = name, title = disp }
        end
    end
    table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
    addonCache = list
    return list
end

-- ── Periodic print ────────────────────────────────────────────────────────────
local ticker
local lastCPU  = {}   -- [name] = last cumulative ms (for the per-interval CPU rate)
local lastRate = {}   -- [name] = last per-interval CPU rate (for the "show differential" delta)
local lastMem  = {}   -- [name] = last memory reading in KB (for the "show differential" delta)

local function fmtMem(kb)
    if kb >= 1024 then return string.format("%.2f MB", kb / 1024) end
    return string.format("%.0f KB", kb)
end

-- "Show differential" colouring tiers vs the previous tick: BIG increase red, medium
-- increase yellow, decrease green, ~no change grey. The colour is decided on the value
-- ROUNDED to its displayed precision, so anything that shows as 0 stays grey (a "+0.0
-- ms" never shows red).
local DIFF_RED, DIFF_YELLOW, DIFF_GREEN, DIFF_GREY = "ffff5555", "ffffcc33", "ff55ff55", "ff999999"
-- Tiers per unit: |Δ| below GREY = very low fluctuation -> grey; a decrease past GREY
-- -> green; an increase up to BIG -> yellow; an increase past BIG -> red. The grey
-- fourchette avoids tagging near-zero noise (e.g. "+0.0 ms") as a real change.
local CPU_GREY_MS, CPU_BIG_MS = 0.1, 1.0
local MEM_GREY_KB, MEM_BIG_KB = 5,   200

local function round1(x)   -- round to 0.1, symmetric about 0
    return math.floor(math.abs(x) * 10 + 0.5) / 10 * (x < 0 and -1 or 1)
end

local function diffColor(d, greyT, bigT)
    if math.abs(d) < greyT then return DIFF_GREY end   -- very low fluctuation
    if d < 0           then return DIFF_GREEN end       -- decrease
    if d >= bigT       then return DIFF_RED end         -- big increase
    return DIFF_YELLOW                                  -- medium increase
end

local function cpuDelta(d)
    return string.format("|c%s(%+.1f ms)|r", diffColor(d, CPU_GREY_MS, CPU_BIG_MS), round1(d))
end

local function memDelta(kb)
    local s = (math.abs(kb) >= 1024) and string.format("%+.2f MB", kb / 1024) or string.format("%+.0f KB", kb)
    return string.format("|c%s(%s)|r", diffColor(kb, MEM_GREY_KB, MEM_BIG_KB), s)
end

-- Scratch reused for each addon's segments (DoUsagePrint runs on the ticker, not
-- re-entrant): wiped per addon instead of allocating a fresh table every row/interval.
local printParts = {}
local function DoUsagePrint()
    if not ns.IsDebugUnlocked() then return end   -- locked: print nothing
    local c = PUCfg(); if not c then return end
    local cpuSel, memSel = c.cpu or {}, c.mem or {}

    UpdateAddOnMemoryUsage()
    local profiling = CPUProfiling()
    if profiling then UpdateAddOnCPUUsage() end

    -- Header prints every tick while started, even with nothing selected.
    print(string.format("|cff338cff[Printing Addon usage]|r (%ds):", c.interval or 5))
    local showDiff = c.showDiff == true
    for _, a in ipairs(AddonList()) do
        local wantCpu = cpuSel[a.name] and profiling
        local wantMem = memSel[a.name]
        if wantCpu or wantMem then
            local parts = printParts; wipe(parts)
            if wantCpu then
                local cur  = GetAddOnCPUUsage(a.name) or 0
                local prev = lastCPU[a.name]
                lastCPU[a.name] = cur
                -- Emit only a real per-interval delta; the first tick after a (re)baseline
                -- just records `cur` (cumulative since profiling start isn't an interval).
                if prev and cur >= prev then
                    local rate = cur - prev
                    local seg  = string.format("CPU %.1f ms", rate)
                    if showDiff then
                        local pr = lastRate[a.name]
                        if pr then seg = seg .. " " .. cpuDelta(rate - pr) end   -- change vs last tick
                        lastRate[a.name] = rate
                    end
                    parts[#parts + 1] = seg
                end
            end
            if wantMem then
                local mem = GetAddOnMemoryUsage(a.name) or 0
                local seg = "Mem " .. fmtMem(mem)
                if showDiff then
                    local pm = lastMem[a.name]
                    if pm then seg = seg .. " " .. memDelta(mem - pm) end   -- change vs last tick
                    lastMem[a.name] = mem
                end
                parts[#parts + 1] = seg
            end
            if #parts > 0 then
                print(string.format("|cff338cff%s|r  %s", a.title, table.concat(parts, "  ·  ")))
            end
        end
    end
end

-- (Re)start or stop the background ticker. Arms when unlocked AND printing is toggled
-- ON (c.active — via the Start button or /ubu debug print start). Ticking a checkbox
-- alone no longer starts printing; once started the header prints every interval even
-- with nothing selected.
function ns.Debug_ApplyUsageOptions()
    if ticker then ticker:Cancel(); ticker = nil end
    if not ns.IsDebugUnlocked() then return end
    local c = PUCfg(); if not c then return end
    if not c.active then return end
    local interval = tonumber(c.interval) or 5
    if interval < 1 then interval = 1 end
    wipe(lastCPU); wipe(lastRate); wipe(lastMem)   -- re-baseline on every (re)arm so a stale gap can't spike
    ticker = C_Timer.NewTicker(interval, DoUsagePrint)
end

-- The panel's Start/Stop toggle button (module-level so it can be refreshed anytime).
local usageButton
local function RefreshUsageButton()
    if not usageButton then return end
    local c = PUCfg() or {}
    usageButton.SetText(c.active and L["Stop print"] or L["Start print"])
end

-- Anything that mirrors the active state (the panel button, the console-mode toggle)
-- registers a refresher here; ns.Debug_SetUsageActive re-syncs them all so the two
-- buttons + the slash commands stay in lock-step.
ns._usageRefreshers = ns._usageRefreshers or {}
function ns.Debug_RegisterUsageRefresh(fn)
    if type(fn) ~= "function" then return end
    ns._usageRefreshers[#ns._usageRefreshers + 1] = fn
    fn()   -- sync immediately to the current state
end
function ns.Debug_IsUsageActive()
    local c = PUCfg(); return c and c.active == true
end

-- Turn periodic printing on/off (panel button, console toggle, /ubu debug print start|stop).
function ns.Debug_SetUsageActive(on)
    local c = PUCfg(); if not c then return end
    c.active = on and true or false
    if ns.Debug_ApplyUsageOptions then ns.Debug_ApplyUsageOptions() end
    for _, fn in ipairs(ns._usageRefreshers) do pcall(fn) end
end

-- The panel button's refresher, registered once (reads the live module-level usageButton).
ns.Debug_RegisterUsageRefresh(RefreshUsageButton)

-- ── Panel ─────────────────────────────────────────────────────────────────────
local BOX_W   = 504   -- cadre width
local COL_CPU = 330   -- CPU checkbox x INSIDE the list cadre (only the 22px box clicks)
local COL_MEM = 422   -- Memory checkbox x INSIDE the list cadre
local ROW_H   = 24

local function CreateCadre(parent, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    return box
end

local function CreatePrintPanel(parent)
    local c = PUCfg() or {}
    local cpuChecks, memChecks, rowNames = {}, {}, {}
    local y = 14

    local title = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
    title:SetText(L["Print"])
    y = y + 30

    -- CPU profiling notice (CPU usage reads 0 until the CVar is on + a reload).
    if not CPUProfiling() then
        local warn = parent:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
        warn:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y - 2)
        warn:SetWidth(300); warn:SetJustifyH("LEFT"); warn:SetTextColor(1, 0.5, 0.2)
        warn:SetText(L["CPU profiling is off — CPU usage will read 0 until enabled."])
        local enable = ns.ui.CreateButton({
            parent = parent, label = L["Enable CPU profiling (reload)"], width = 190, height = 22,
            onClick = function()
                local setc = (C_CVar and C_CVar.SetCVar) or SetCVar
                if setc then setc("scriptProfile", "1") end
                ReloadUI()
            end,
        })
        enable.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 324, -y)
        y = y + 30
    end

    -- ── Cadre 1: interval + Start/Stop + show differential ──────────────────────
    local ctrl = CreateCadre(parent, BOX_W, 86)
    ctrl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)

    -- Row 1: "Print every [N] seconds" + Start/Stop.
    local ilabel = ctrl:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    ilabel:SetPoint("TOPLEFT", ctrl, "TOPLEFT", 14, -16)
    ilabel:SetText(L["Print every"])
    local interval = ns.ui.CreateTextInput({
        parent = ctrl, width = 46, height = 22, numeric = true, min = 1, max = 3600,
        maxLetters = 4, text = tostring(c.interval or 5),
        onEnter = function(val)
            local cc = PUCfg()
            if cc and val and val > 0 then cc.interval = val end
            if ns.Debug_ApplyUsageOptions then ns.Debug_ApplyUsageOptions() end
        end,
    })
    interval.frame:SetPoint("LEFT", ilabel, "RIGHT", 8, 0)
    local isec = ctrl:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    isec:SetPoint("LEFT", interval.frame, "RIGHT", 6, 0)
    isec:SetText(L["seconds"])

    usageButton = ns.ui.CreateButton({
        parent = ctrl, label = L["Start print"], width = 120, height = 22,
        onClick = function()
            local cc = PUCfg()
            ns.Debug_SetUsageActive(not (cc and cc.active))
        end,
    })
    usageButton.frame:SetPoint("TOPRIGHT", ctrl, "TOPRIGHT", -14, -13)
    RefreshUsageButton()

    -- Open the Console Mode window (left of Start print) — same toggle as the Debug panel.
    local consoleBtn = ns.ui.CreateButton({
        parent = ctrl, label = L["Open Console Mode"], width = 150, height = 22,
        onClick = function() if ns.Debug_ToggleConsole then ns.Debug_ToggleConsole() end end,
    })
    consoleBtn.frame:SetPoint("RIGHT", usageButton.frame, "LEFT", -6, 0)

    -- Row 2: show differential (coloured ± change vs the previous tick). On by default.
    local diffCB = ns.ui.CreateCheckbox({
        parent  = ctrl,
        label   = L["Show differential"],
        checked = c.showDiff ~= false,
        onClick = function(v)
            local cc = PUCfg(); if cc then cc.showDiff = v and true or false end
        end,
    })
    diffCB.frame:SetPoint("TOPLEFT", ctrl, "TOPLEFT", 12, -50)

    y = y + 86 + 14

    -- ── Cadre 2: addon list with CPU / Memory columns ───────────────────────────
    local rows = AddonList()
    local HEAD_Y, BTN_Y, LIST_Y = 10, 30, 58   -- y offsets inside the cadre
    local list = CreateCadre(parent, BOX_W, LIST_Y + #rows * ROW_H + 10)
    list:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)

    local hcpu = list:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    hcpu:SetPoint("TOPLEFT", list, "TOPLEFT", COL_CPU - 4, -HEAD_Y)
    hcpu:SetText(L["CPU"])
    local hmem = list:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
    hmem:SetPoint("TOPLEFT", list, "TOPLEFT", COL_MEM - 4, -HEAD_Y)
    hmem:SetText(L["Memory"])

    -- Per-column bulk toggle. SetChecked() never fires onClick, so we ALSO write the
    -- config ourselves, then re-apply.
    local function setColumn(checks, key, value)
        if key == "cpu" and not CPUProfiling() then return end   -- CPU boxes disabled while off
        local cc = PUCfg(); if not cc then return end
        cc[key] = cc[key] or {}
        for i, cb in ipairs(checks) do
            cb.SetChecked(value)
            cc[key][rowNames[i]] = value and true or nil
        end
        if ns.Debug_ApplyUsageOptions then ns.Debug_ApplyUsageOptions() end
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

    -- One row per addon: name + CPU box + Memory box (all parented to the list cadre).
    local ly = LIST_Y
    for _, a in ipairs(rows) do
        rowNames[#rowNames + 1] = a.name
        local idx = #rowNames

        local nameFS = list:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH5")
        nameFS:SetPoint("TOPLEFT", list, "TOPLEFT", 14, -ly - 3)
        nameFS:SetWidth(COL_CPU - 26); nameFS:SetJustifyH("LEFT"); nameFS:SetWordWrap(false)
        nameFS:SetText(a.title)

        local cpuCB = ns.ui.CreateCheckbox({
            parent  = list, label = "",
            checked = (c.cpu or {})[a.name] == true,
            disabled = function() return not CPUProfiling() end,
            onClick = function(v)
                local cc = PUCfg()
                if cc then cc.cpu = cc.cpu or {}; cc.cpu[a.name] = v and true or nil end
                if ns.Debug_ApplyUsageOptions then ns.Debug_ApplyUsageOptions() end
            end,
        })
        cpuCB.frame:SetWidth(24)
        cpuCB.frame:SetPoint("TOPLEFT", list, "TOPLEFT", COL_CPU, -ly)
        cpuChecks[idx] = cpuCB

        local memCB = ns.ui.CreateCheckbox({
            parent  = list, label = "",
            checked = (c.mem or {})[a.name] == true,
            onClick = function(v)
                local cc = PUCfg()
                if cc then cc.mem = cc.mem or {}; cc.mem[a.name] = v and true or nil end
                if ns.Debug_ApplyUsageOptions then ns.Debug_ApplyUsageOptions() end
            end,
        })
        memCB.frame:SetWidth(24)
        memCB.frame:SetPoint("TOPLEFT", list, "TOPLEFT", COL_MEM, -ly)
        memChecks[idx] = memCB

        ly = ly + ROW_H
    end

    return nil
end

-- Register the panel + start the background ticker once the addon (and ns.db) loaded.
local initPP = CreateFrame("Frame")
initPP:RegisterEvent("ADDON_LOADED")
initPP:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Print"], nil, CreatePrintPanel)
    if ns.Debug_ApplyUsageOptions then ns.Debug_ApplyUsageOptions() end
    self:UnregisterEvent("ADDON_LOADED")
end)
