-- Modules/BResTracker/Core/PlayerList.lua
-- Optional list of BRes-capable players in the group/raid, with a green check
-- icon when ready or a red mm:ss timer when on cooldown. Per-player cooldowns
-- are inferred heuristically: see the comment block above BR.AttributeBResCast.

local _, ns = ...
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

-- Dedicated AceEvent embed for this file's event listeners. BResTracker.lua
-- already embeds AceEvent on the shared BR table and registers
-- PLAYER_ENTERING_WORLD / GROUP_ROSTER_UPDATE on it; AceEvent (via
-- CallbackHandler) keys callbacks by (object, event), so registering those same
-- events on BR again here would OVERWRITE BResTracker's handlers. A separate
-- object keeps both handlers live, matching the two independent CreateFrame
-- frames the original code used.
local AceEvent = LibStub("AceEvent-3.0")
local plEvents = {}
AceEvent:Embed(plEvents)

-- Fallback per-player cooldown estimate (seconds). The actual cooldown of
-- another player can't be read reliably (see the AttributeBResCast note below),
-- so a single heuristic value is used across all BRes classes; the real spell
-- cooldowns (Rebirth / Raise Ally / Intercession) are all 600s. Overridable via
-- BR.CfgGet("listCooldownEstimate").
local BRES_CD = 600

-- Classes that can BRes (any spec).
local BRES_CLASSES = {
    DRUID       = true,   -- Rebirth
    DEATHKNIGHT = true,   -- Raise Ally
    WARLOCK     = true,   -- Soulstone
    PALADIN     = true,   -- Intercession
}

local CHECK_TEXTURE = ns.GREEN_CHECK_TEXTURE

-- ── Internal state ───────────────────────────────────────────────────────────

local listFrame
local rows = {}                 -- pool of reusable row frames
local cooldownEnds = {}         -- [guid] = GetTime()-based expiration
local lastCastByGUID = {}       -- [guid] = last successful cast time (cast pairing)
local membersOrdered = {}       -- ordered list used to render rows

-- Cache of unit class indexed by GUID. Built from the current roster on
-- GROUP_ROSTER_UPDATE so the hot UNIT_SPELLCAST_SUCCEEDED handler can do an
-- O(1) lookup instead of calling UnitClass() on every cast.
local classByGUID = {}

-- Cached cell dimensions for RefreshList. Invalidated whenever the values
-- the layout depends on change (font size/outline, roster, status side).
local layoutCache = {
    cellWidth  = nil,
    cellHeight = nil,
    key        = nil,
}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Build the ordered list of BRes-capable group members. Also rebuilds the
-- classByGUID cache for ALL group members (not just BRes-capable ones), so
-- the cast listener can filter casts without calling UnitClass().
local function RefreshRoster()
    wipe(membersOrdered)
    wipe(classByGUID)

    local function add(unit)
        if not UnitExists(unit) then return end
        local _, class = UnitClass(unit)
        local guid = UnitGUID(unit)
        if not guid then return end
        if class then classByGUID[guid] = class end
        if not class or not BRES_CLASSES[class] then return end
        local name = UnitName(unit)
        if not name then return end
        table.insert(membersOrdered, { guid = guid, name = name, class = class })
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    elseif IsInGroup() then
        add("player")
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    else
        add("player")
    end

    -- Drop cooldowns and cached cast timestamps for players who left the group.
    -- classByGUID covers all group members (not just BRes-capable ones), so it
    -- is the correct membership set for pruning the cast-pairing table.
    local seen = {}
    for _, m in ipairs(membersOrdered) do seen[m.guid] = true end
    for guid in pairs(cooldownEnds) do
        if not seen[guid] then cooldownEnds[guid] = nil end
    end
    for guid in pairs(lastCastByGUID) do
        if not classByGUID[guid] then lastCastByGUID[guid] = nil end
    end

    -- Force a layout recompute on next RefreshList: roster shape changed.
    layoutCache.key = nil
end

-- ── Row pool ─────────────────────────────────────────────────────────────────

local function CreateRow()
    local row = CreateFrame("Frame", nil, listFrame)
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.timer = row:CreateFontString(nil, "OVERLAY")
    row.timer:SetTextColor(1, 0.2, 0.2, 1)
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetTexture(CHECK_TEXTURE)
    return row
end

local function GetRow(idx)
    if not rows[idx] then rows[idx] = CreateRow() end
    return rows[idx]
end

-- ── Rendering ────────────────────────────────────────────────────────────────

local CELL_PAD = 1   -- inset from the cell edge
local CELL_GAP = 2   -- gap between name and status

-- Layout the name + status inside a single cell. statusObj is either the timer
-- FontString or the check Texture (both support SetPoint identically). For
-- Left/Right modes the name auto-sizes to its text width so the status sits
-- right next to the pseudo. For Above/Below the cell is stacked on two
-- center-aligned lines.
local function LayoutCell(row, nameFS, statusObj, statusSide, cellWidth)
    if statusSide == "Right" then
        nameFS:SetWidth(0)  -- auto-size to text
        nameFS:SetPoint("LEFT", row, "LEFT", CELL_PAD, 0)
        nameFS:SetJustifyH("LEFT")
        statusObj:SetPoint("LEFT", nameFS, "RIGHT", CELL_GAP, 0)
        if statusObj.SetJustifyH then statusObj:SetJustifyH("LEFT") end
    elseif statusSide == "Left" then
        nameFS:SetWidth(0)
        statusObj:SetPoint("LEFT", row, "LEFT", CELL_PAD, 0)
        nameFS:SetPoint("LEFT", statusObj, "RIGHT", CELL_GAP, 0)
        nameFS:SetJustifyH("LEFT")
        if statusObj.SetJustifyH then statusObj:SetJustifyH("LEFT") end
    elseif statusSide == "Above" then
        statusObj:SetPoint("TOP", row, "TOP", 0, -CELL_PAD)
        nameFS:SetPoint("BOTTOM", row, "BOTTOM", 0, CELL_PAD)
        nameFS:SetWidth(cellWidth)
        nameFS:SetJustifyH("CENTER")
        if statusObj.SetJustifyH then statusObj:SetJustifyH("CENTER") end
    else -- "Below"
        nameFS:SetPoint("TOP", row, "TOP", 0, -CELL_PAD)
        statusObj:SetPoint("BOTTOM", row, "BOTTOM", 0, CELL_PAD)
        nameFS:SetWidth(cellWidth)
        nameFS:SetJustifyH("CENTER")
        if statusObj.SetJustifyH then statusObj:SetJustifyH("CENTER") end
    end
end

function BR.RefreshList()
    if not listFrame then return end

    -- While the icon is unlocked for positioning, show only the clean icon
    -- preview (ApplyVisuals early-returns then), not the player list.
    if BR.IsUnlocked and BR.IsUnlocked() then
        listFrame:Hide()
        return
    end

    -- Never a list without the icon: gate on the same icon-visibility decision
    -- (enabled + showIcon + relevant group/instance context) plus listEnabled.
    if not (BR.CfgGet("listEnabled") and BR.IconShouldShow()) then
        listFrame:Hide()
        return
    end

    -- Source of the roster/cooldowns: real data or fake test values.
    local members, cooldowns
    if BR.testMode then
        members   = BR.testMembers      or {}
        cooldowns = BR.testCooldownEnds or {}
    else
        members   = membersOrdered
        cooldowns = cooldownEnds
    end

    if #members == 0 then
        listFrame:Hide()
        return
    end

    local listSide   = BR.CfgGet("listSide")      or "Left"
    local statusSide = BR.CfgGet("rowStatusSide") or "Left"
    local rowHeight  = BR.CfgGet("listRowHeight") or 18
    local fontSize   = BR.CfgGet("listFontSize")  or 12
    local outline    = BR.CfgGet("listOutline")   or "OUTLINE"
    local fontPath   = ns.ResolveFontPath(BR.CfgGet("listFontPath"), BR.CfgGet("listFontKey"))
    local checkSize  = math.max(10, math.floor(rowHeight * 0.7))

    -- Compute cell sizing only when the inputs that drive it actually change.
    -- The cooldown timers tick every 0.5s but never affect cell dimensions.
    local cacheKey = table.concat({
        fontPath, fontSize, outline, statusSide,
        rowHeight, tostring(#members),
        BR.testMode and "T" or "R",
    }, "|")

    local cellWidth, cellHeight = layoutCache.cellWidth, layoutCache.cellHeight
    if layoutCache.key ~= cacheKey or not cellWidth or not cellHeight then
        local measureFS = listFrame.measureFS
        if not measureFS then
            measureFS = listFrame:CreateFontString(nil, "OVERLAY")
            listFrame.measureFS = measureFS
        end
        measureFS:SetFont(fontPath, fontSize, outline)

        local maxNameWidth = 0
        for _, m in ipairs(members) do
            measureFS:SetText(m.name)
            local w = measureFS:GetStringWidth()
            if w > maxNameWidth then maxNameWidth = w end
        end

        measureFS:SetText("9:59")
        local timerWidth = measureFS:GetStringWidth()
        local maxStatusWidth = math.max(checkSize, timerWidth)

        local statusStacked = (statusSide == "Above" or statusSide == "Below")
        if statusStacked then
            cellHeight = rowHeight * 2
            cellWidth  = math.max(maxNameWidth, maxStatusWidth) + CELL_PAD * 2
        else
            cellHeight = rowHeight
            cellWidth  = maxNameWidth + CELL_GAP + maxStatusWidth + CELL_PAD * 2
        end

        layoutCache.cellWidth  = cellWidth
        layoutCache.cellHeight = cellHeight
        layoutCache.key        = cacheKey
    end

    -- Layout direction: horizontal when the list is above/below the icon.
    -- Primary axis is bounded by the icon dimension; the secondary axis wraps
    -- and is unbounded.
    local horizontal = (listSide == "Above" or listSide == "Below")

    local iconFrame = BR.GetFrame()
    local iconW = iconFrame and iconFrame:GetWidth()  or 0
    local iconH = iconFrame and iconFrame:GetHeight() or 0

    -- primaryCap = how many cells fit along the primary axis (min 1).
    local primaryCap
    if horizontal then
        primaryCap = math.max(1, math.floor(iconW / cellWidth))
    else
        primaryCap = math.max(1, math.floor(iconH / cellHeight))
    end

    -- secondaryCount = number of wrap-around columns/rows we need (min 1).
    local total = #members
    local secondaryCount = math.max(1, math.ceil(total / primaryCap))

    -- Frame size: primary axis is capped, secondary grows with wrap.
    if horizontal then
        listFrame:SetSize(cellWidth * primaryCap, cellHeight * secondaryCount)
    else
        listFrame:SetSize(cellWidth * secondaryCount, cellHeight * primaryCap)
    end
    listFrame:Show()

    local now = GetTime()

    for i = 1, total do
        local m = members[i]
        local row = GetRow(i)

        -- Status: green check when ready, red timer when on cooldown.
        local cdEnd = cooldowns[m.guid]
        local remain = cdEnd and (cdEnd - now) or 0
        local onCD = remain > 0

        -- Structural signature for this row. Everything that drives the per-row
        -- SetSize / SetPoint / SetFont / SetText / check-size / LayoutCell work is
        -- folded in: cacheKey (font/size/outline/statusSide/rowHeight/#members),
        -- the member identity, its position (i/primaryCap/listSide), and the
        -- status mode (timer vs check). On a pure 0.5s timer tick none of these
        -- change — only the timer's mm:ss text — so we skip all the layout calls
        -- and just refresh row.timer below.
        local sig = cacheKey .. "|" .. i .. "|" .. primaryCap .. "|" .. listSide
            .. "|" .. m.guid .. "|" .. (onCD and "t" or "c")

        if row.layoutSig ~= sig then
            row.layoutSig = sig

            row:SetSize(cellWidth, cellHeight)
            row:ClearAllPoints()

            -- 0-based index of the cell within its primary track, and the index of
            -- the wrap (column for vertical, row for horizontal).
            local primaryIdx   = (i - 1) % primaryCap
            local secondaryIdx = math.floor((i - 1) / primaryCap)

            -- Cells grow AWAY from the icon along the secondary axis, so the first
            -- member is always closest to the icon.
            if horizontal then
                if listSide == "Above" then
                    -- Rows grow upward from the BOTTOMLEFT of the list.
                    row:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMLEFT",
                        primaryIdx * cellWidth,
                        secondaryIdx * cellHeight)
                else  -- "Below"
                    row:SetPoint("TOPLEFT", listFrame, "TOPLEFT",
                        primaryIdx * cellWidth,
                        -secondaryIdx * cellHeight)
                end
            else
                if listSide == "Left" then
                    -- Columns grow leftward from the TOPRIGHT of the list.
                    row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT",
                        -secondaryIdx * cellWidth,
                        -primaryIdx * cellHeight)
                else  -- "Right"
                    row:SetPoint("TOPLEFT", listFrame, "TOPLEFT",
                        secondaryIdx * cellWidth,
                        -primaryIdx * cellHeight)
                end
            end
            row:Show()

            -- Name, colored by class.
            local r, g, b = ClassColor(m.class)
            row.name:SetFont(fontPath, fontSize, outline)
            row.name:SetText(m.name)
            row.name:SetTextColor(r, g, b, 1)
            row.name:ClearAllPoints()

            row.timer:ClearAllPoints()
            row.check:ClearAllPoints()
            row.check:SetSize(checkSize, checkSize)

            if onCD then
                row.check:Hide()
                row.timer:SetFont(fontPath, fontSize, outline)
                row.timer:SetText(ns.FormatMMSS(remain))
                row.timer:Show()
                LayoutCell(row, row.name, row.timer, statusSide, cellWidth)
            else
                row.timer:Hide()
                row.check:Show()
                LayoutCell(row, row.name, row.check, statusSide, cellWidth)
            end
        elseif onCD then
            -- Pure timer tick: structure is unchanged, only the countdown text moves.
            row.timer:SetText(ns.FormatMMSS(remain))
        end
    end

    -- Hide leftover rows from the pool (members count may have decreased).
    -- Clear layoutSig so a later reuse of the same row always re-runs the
    -- structural pass (which re-Shows it) even if its signature would match.
    for i = total + 1, #rows do
        rows[i]:Hide()
        rows[i].layoutSig = nil
    end
end

-- ── List positioning relative to the icon frame ──────────────────────────────

function BR.ApplyListPosition()
    if not listFrame then return end
    local anchorFrame = BR.GetFrame()
    if not anchorFrame then return end

    local side   = BR.CfgGet("listSide")   or "Left"
    local offset = BR.CfgGet("listOffset") or 8

    listFrame:ClearAllPoints()
    if side == "Left" then
        listFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -offset, 0)
    elseif side == "Above" then
        listFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, offset)
    elseif side == "Below" then
        listFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -offset)
    else -- "Right"
        listFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", offset, 0)
    end
end

-- ── Per-player cooldown tracking (heuristic) ────────────────────────────────
-- COMBAT_LOG_EVENT_UNFILTERED is blocked for this addon on Interface 120005
-- (Frame:RegisterEvent triggers ADDON_ACTION_FORBIDDEN). The spellId from
-- another player's UNIT_SPELLCAST_SUCCEEDED is also a "secret value" and
-- can't be matched against our BRes spell table.
--
-- Workaround: track the timestamp of the latest successful cast by each
-- BRes-capable group member (any spell — we can't tell which one). When the
-- shared pool's currentCharges decreases, attribute the BRes to whichever
-- of those members cast most recently within a small time window. Not
-- perfect (a spell spammer can steal attribution), but accurate in the
-- common case.

local CAST_PAIRING_WINDOW = 1.5  -- seconds
-- lastCastByGUID is declared in the internal-state block above so RefreshRoster
-- can prune entries for players who leave the group (same as cooldownEnds).

-- Called by BResTracker.ApplyVisuals when it detects a pool decrease.
function BR.AttributeBResCast()
    local now = GetTime()
    local bestGUID, bestT = nil, 0
    for guid, t in pairs(lastCastByGUID) do
        if t > bestT and (now - t) <= CAST_PAIRING_WINDOW then
            bestT = t
            bestGUID = guid
        end
    end
    if bestGUID then
        cooldownEnds[bestGUID] = now + (BR.CfgGet("listCooldownEstimate") or BRES_CD)
    end
end

-- Single-pass classifier for the hot UNIT_SPELLCAST_SUCCEEDED path.
-- Returns the owning group unit token (remapping a pet to its owner so e.g.
-- Hunter Eternal Guardian is attributed to the hunter), or nil for any token
-- that is not the player / a group member / one of their pets.
-- Rejecting non-group tokens matters: nameplates / targets / focus / mouseover
-- also fire this event and UnitGUID() on a non-group unit can return a Blizzard
-- "secret value" that crashes when used as a table key.
local function ResolveGroupOwnerUnit(unit)
    if not unit then return nil end
    if unit == "player" then return "player" end
    if unit == "pet"    then return "player" end
    local n = unit:match("^party(%d+)$")
    if n then return "party" .. n end
    n = unit:match("^partypet(%d+)$")
    if n then return "party" .. n end
    n = unit:match("^raid(%d+)$")
    if n then return "raid" .. n end
    n = unit:match("^raidpet(%d+)$")
    if n then return "raid" .. n end
    return nil
end

-- Track the most recent successful cast time per BRes-capable group member.
-- We ignore the spellId argument entirely (it's secret for other players).
-- Hot path in raids (hundreds of casts/sec): the class lookup is served from
-- the cached classByGUID map populated on GROUP_ROSTER_UPDATE.
local function OnCastSucceeded(event, unit)
    -- Defensive early-out: this is the single hottest event in the addon. The
    -- listener is unregistered entirely when the module is disabled (see
    -- BR.StopListDrivers), so this guard only matters across a tiny race window.
    if not BR.CfgGet("enabled") then return end
    -- Classify + remap pet→owner in a single pass; nil means "not a group unit".
    unit = ResolveGroupOwnerUnit(unit)
    if not unit then return end

    local guid = UnitGUID(unit)
    if not guid then return end
    local class = classByGUID[guid]
    if not class or not BRES_CLASSES[class] then return end
    lastCastByGUID[guid] = GetTime()
end

-- ── Roster events ────────────────────────────────────────────────────────────

local function OnRosterRefresh(event)
    if not BR.CfgGet("enabled") then return end
    RefreshRoster()
    BR.RefreshList()
end

-- Start/stop the player-list event listeners (hot cast path + roster), driven by
-- the module's enable toggle via BResTracker's StartDrivers/StopDrivers. Fully
-- unregistering the UNIT_SPELLCAST_SUCCEEDED listener is the big win: a disabled
-- module does ZERO work on every cast in a raid. Idempotent.
local listDriversOn = false
function BR.StartListDrivers()
    if listDriversOn then return end
    listDriversOn = true
    plEvents:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", OnCastSucceeded)
    plEvents:RegisterEvent("GROUP_ROSTER_UPDATE", OnRosterRefresh)
    plEvents:RegisterEvent("PLAYER_ENTERING_WORLD", OnRosterRefresh)
    -- Rebuild the roster now so re-enabling mid-session repopulates immediately.
    RefreshRoster()
    BR.RefreshList()
end

function BR.StopListDrivers()
    if not listDriversOn then return end
    listDriversOn = false
    plEvents:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    plEvents:UnregisterEvent("GROUP_ROSTER_UPDATE")
    plEvents:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if listFrame then listFrame:Hide() end
end

-- ── Init ─────────────────────────────────────────────────────────────────────

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    -- Parented to UIParent (NOT the icon frame) so the list can render even when
    -- "Show icon" is off: ApplyListPosition anchors it to the icon frame via
    -- SetPoint (which works regardless of the anchor's shown state), and
    -- BR.RefreshList independently governs visibility (listEnabled + members).
    listFrame = CreateFrame("Frame", "BResTrackerPlayerList", UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(listFrame) end
    listFrame:Hide()
    BR.list = { frame = listFrame }

    BR.ApplyListPosition()
    -- If the enable toggle already started the list drivers before this frame
    -- created listFrame (PLAYER_LOGIN order between the two init frames is
    -- undefined), re-run roster/list now that listFrame exists. Otherwise the
    -- drivers (started by BResTracker.StartDrivers when enabled) own this.
    if BR.CfgGet("enabled") then
        RefreshRoster()
        BR.RefreshList()
    end
    self:UnregisterEvent("PLAYER_LOGIN")
end)
