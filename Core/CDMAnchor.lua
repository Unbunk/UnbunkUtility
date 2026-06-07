-- Core/CDMAnchor.lua
-- Optional integration of tracker icons with Blizzard's Cooldown Manager.
--
-- A tracker icon can be:
--   * free  (includeInCdm = false): positioned on screen (posX/posY + drag).
--   * a slot in a native CooldownViewer row (cdmDest = "essential" | "utility"):
--       placed at the start/end (cdmAtEnd) of a chosen wrapped row (cdmRow), sized
--       to the native icons. We NEVER move the protected viewer or its natives — we
--       only SetPoint OUR (unprotected) frames relative to the row's edge icon and
--       re-apply on the viewer's relayout (hooksecurefunc) — so no taint.
--   * in an artificial row below the PlayerFrame (cdmDest = "belowPlayer"): our own
--       left-to-right row; icons are ordered by a per-profile order map and can be
--       reordered with the config arrows.

local ADDON, ns = ...

-- destination key -> native CooldownViewer global frame name (belowPlayer = none).
ns.CDM_VIEWER = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
}

-- Ordered destination options for the dropdown (keys; labels localized below).
ns.CDM_DEST_ORDER = { "essential", "utility", "belowPlayer" }

function ns.CDMDestLabel(key)
    local L = ns.L
    if key == "utility"     then return L["Cooldown Manager: Utility"] end
    if key == "belowPlayer" then return L["Below player frame"]        end
    return L["Cooldown Manager: Essential"]
end

function ns.CDMDestList()
    local t = {}
    for _, k in ipairs(ns.CDM_DEST_ORDER) do t[#t + 1] = ns.CDMDestLabel(k) end
    return t
end

function ns.CDMDestKeyFromLabel(label)
    for _, k in ipairs(ns.CDM_DEST_ORDER) do
        if ns.CDMDestLabel(k) == label then return k end
    end
    return "essential"
end

-- Live viewer frame for a destination, or nil (belowPlayer / CDM off / not loaded).
function ns.GetCDMViewer(dest)
    local name = ns.CDM_VIEWER[dest]
    return name and _G[name] or nil
end

-- ── Native row helpers ───────────────────────────────────────────────────────
local function EnumNativeIcons(viewer)
    local out = {}
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do
            if f and f.IsShown and f:IsShown() and (f.Icon or f.cooldownInfo) then
                out[#out + 1] = f
            end
        end
    end
    if #out == 0 then
        for _, c in ipairs({ viewer:GetChildren() }) do
            if c.IsShown and c:IsShown() and (c.Icon or c.layoutIndex or c.cooldownInfo) then
                out[#out + 1] = c
            end
        end
    end
    return out
end

-- Group the viewer's native icons into visual rows (top→bottom), each sorted L→R.
local function ComputeRows(viewer)
    local natives = EnumNativeIcons(viewer)
    table.sort(natives, function(a, b)
        local at, bt = a:GetTop() or 0, b:GetTop() or 0
        if math.abs(at - bt) > 4 then return at > bt end       -- higher row first
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)         -- then left→right
    end)
    local rows, cur, curTop = {}, nil, nil
    for _, f in ipairs(natives) do
        local t = f:GetTop() or 0
        if not cur or math.abs(t - curTop) > 4 then
            cur = {}; rows[#rows + 1] = cur; curTop = t
        end
        cur[#cur + 1] = f
    end
    return rows
end

-- Number of rows available for a destination's viewer (for the Row dropdown). >=1.
function ns.CDMRowCount(dest)
    local v = ns.GetCDMViewer(dest)
    if not v then return 1 end
    local n = #ComputeRows(v)
    return n > 0 and n or 1
end

-- Row dropdown helpers (the Dropdown widget keys items by their display text).
function ns.CDMRowLabel(i)
    return string.format(ns.L["Row %d"], i)
end
function ns.CDMRowList(dest)
    local t = {}
    for i = 1, ns.CDMRowCount(dest) do t[i] = ns.CDMRowLabel(i) end
    return t
end
function ns.CDMRowFromLabel(label)
    return tonumber(tostring(label):match("(%d+)")) or 1
end
-- Clamp a stored row index to the destination's available rows (>=1). Used when
-- switching anchor so a "Row 2" saved for Essential collapses to the highest
-- real row of a Utility viewer that only wraps to one row (and the dropdown then
-- displays that real row instead of a phantom out-of-range entry).
function ns.CDMClampRow(dest, row)
    local n = ns.CDMRowCount(dest)
    row = row or 1
    if row < 1 then return 1 end
    if row > n then return n end
    return row
end

-- ── Registry ─────────────────────────────────────────────────────────────────
ns.CDMAnchor = ns.CDMAnchor or {}
-- descriptor: { apply=fn, frame=Frame, getCfg=fn, setSize=fn(w,h) }
local appliers = {}
local byFrame  = {}
local regCount = 0

function ns.CDMAnchor.Register(desc)
    if type(desc) == "function" then desc = { apply = desc } end
    if type(desc) ~= "table" then return end
    regCount = regCount + 1
    desc.regIndex = regCount
    appliers[#appliers + 1] = desc
    if desc.frame then byFrame[desc.frame] = desc end
end

-- ── Below-player artificial row ──────────────────────────────────────────────
local BELOW_GAP = 0   -- icons placed flush against each other (no spacing)
local belowRow
local belowUnlocked = false   -- transient (per-session) manual-drag mode

-- Account-wide manual offset of the row from PlayerFrame's BOTTOMLEFT.
local function BelowOffset()
    local c = ns.db and ns.db.global and ns.db.global.cdmBelowRow
    return (c and c.offsetX) or 0, (c and c.offsetY) or 0
end

-- Resolve the frame to stick to: a supported custom unit-frame addon's player
-- frame if present (its bounds ARE the visible art), else Blizzard's PlayerFrame
-- — but anchored to its inner bars content (PlayerFrameContentMain) so the row
-- sits flush under the VISIBLE frame, not PlayerFrame's padded geometric bottom.
-- (Same custom-frame candidate approach Ayije_CDM uses for its trackers.)
local PLAYER_FRAME_CANDIDATES = {
    "ElvUF_Player", "SUFUnitplayer", "UUF_Player",
    "EllesmereUIUnitFrames_Player", "MSUF_player", "EQOLUFPlayerFrame", "oUF_Player",
}
local function ResolvePlayerFrame()
    for _, name in ipairs(PLAYER_FRAME_CANDIDATES) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return f end
    end
    local pf = _G["PlayerFrame"]
    if pf then
        local content = pf.PlayerFrameContent
        local main = content and content.PlayerFrameContentMain
        return main or pf
    end
    return nil
end

-- Anchor the row's TOPLEFT to the player frame's BOTTOMLEFT (+ manual offset);
-- default offset 0,0 -> flush under the visible frame.
local function AnchorBelowRow()
    if not belowRow then return end
    local ox, oy = BelowOffset()
    local anchor = ResolvePlayerFrame()
    belowRow.anchorFrame = anchor
    belowRow:ClearAllPoints()
    if anchor then
        belowRow:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ox, oy)
    else
        belowRow:SetPoint("CENTER", UIParent, "CENTER", ox, oy - 160)
    end
end

local function GetBelowRow()
    if not belowRow then
        belowRow = CreateFrame("Frame", "UnbunkUtilityCDMBelowRow", UIParent)
        belowRow:SetSize(1, 1)
        belowRow:SetMovable(true)
        belowRow:EnableMouse(false)
        belowRow:RegisterForDrag("LeftButton")
        local bg = belowRow:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(belowRow)
        bg:SetColorTexture(0.1, 0.6, 1, 0.25)
        bg:Hide()
        belowRow.dragBG = bg
        belowRow:SetScript("OnDragStart", function(self)
            if belowUnlocked then self:StartMoving() end
        end)
        belowRow:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local anchor = self.anchorFrame or _G["PlayerFrame"]
            local c = ns.db and ns.db.global and ns.db.global.cdmBelowRow
            if anchor and c and self:GetLeft() and anchor:GetLeft() then
                c.offsetX = self:GetLeft() - anchor:GetLeft()
                c.offsetY = self:GetTop()  - anchor:GetBottom()
            end
            AnchorBelowRow()
            if ns.OnBelowRowMoved then ns.OnBelowRowMoved() end
        end)
    end
    AnchorBelowRow()
    return belowRow
end

-- Unlock / lock the below-player row for manual dragging (General Settings).
-- When unlocked the row is raised above the (flush, gap-0) icons so its whole
-- area is grabbable; locking restores the normal strata.
function ns.CDMAnchor.SetBelowUnlocked(val)
    belowUnlocked = val and true or false
    local row = GetBelowRow()
    row:EnableMouse(belowUnlocked)
    row:SetFrameStrata(belowUnlocked and "DIALOG" or "MEDIUM")
    if row.dragBG then
        if belowUnlocked then row.dragBG:Show() else row.dragBG:Hide() end
    end
    ns.CDMAnchor.RefreshAll()
end
function ns.CDMAnchor.IsBelowUnlocked() return belowUnlocked end

-- Per-profile order map for reorderable CDM icons. ONE map (id = frame name ->
-- order number) drives ordering both for the below-player row AND for the
-- start/end bucket of an essential/utility native row — each icon belongs to a
-- single bucket at a time, so a single map keyed by frame name is unambiguous.
local function OrderMap()
    if not ns.db or not ns.db.profile then return nil end
    ns.db.profile.cdmOrder = ns.db.profile.cdmOrder or {}
    return ns.db.profile.cdmOrder
end

local function DescId(d)
    return (d.frame and d.frame.GetName and d.frame:GetName()) or tostring(d.frame)
end

-- Sort a descriptor list in place by saved order (registration order is the
-- stable fallback for not-yet-ordered icons).
local function SortByOrder(list)
    local map = OrderMap()
    table.sort(list, function(a, b)
        local ao = (map and map[DescId(a)]) or (1000 + a.regIndex)
        local bo = (map and map[DescId(b)]) or (1000 + b.regIndex)
        if ao ~= bo then return ao < bo end
        return a.regIndex < b.regIndex
    end)
    return list
end

-- Rewrite the saved order to a contiguous 1..n for exactly the icons in `list`.
local function NormalizeOrder(list)
    local map = OrderMap()
    if not map then return end
    for i, d in ipairs(list) do map[DescId(d)] = i end
end

-- Active below-player descriptors, sorted by saved order.
local function BelowList()
    local list = {}
    for _, d in ipairs(appliers) do
        if d.frame and d.getCfg and d.getCfg("includeInCdm") and d.getCfg("cdmDest") == "belowPlayer" then
            list[#list + 1] = d
        end
    end
    return SortByOrder(list)
end

-- Account-wide size of the below-player row icons (configured in General Settings).
local function BelowRowSize()
    local c = ns.db and ns.db.global and ns.db.global.cdmBelowRow
    return (c and c.width) or 36, (c and c.height) or 36
end

local function LayoutBelowPlayer(list)
    NormalizeOrder(list)
    local w, h = BelowRowSize()
    local row = GetBelowRow()
    local prev, count = nil, 0
    for _, d in ipairs(list) do
        local f = d.frame
        if f and f:IsShown() then
            if d.setSize then d.setSize(w, h) end
            f:ClearAllPoints()
            if prev then
                f:SetPoint("LEFT", prev, "RIGHT", BELOW_GAP, 0)
            else
                f:SetPoint("LEFT", row, "LEFT", 0, 0)
            end
            prev = f
            count = count + 1
        end
    end
    -- Size the row to bound its icons so it presents a grabbable area when unlocked.
    local totalW = count * w + math.max(0, count - 1) * BELOW_GAP
    row:SetSize(math.max(1, totalW), math.max(1, h))
    if row.dragBG then
        if belowUnlocked then row.dragBG:Show() else row.dragBG:Hide() end
    end
end

-- Effective number of rows the layout will actually render for a destination,
-- mirroring LayoutCDMRow's nRows = ceil((natives + our shown icons) / iconLimit).
-- The reorder bucketing MUST use this (not the native-only CDMRowCount) so an icon
-- that renders on an extra row our icons created is bucketed on that same row.
local function EffectiveRowCount(dest)
    local v = ns.GetCDMViewer(dest)
    if not v then return 1 end
    local nNat = #EnumNativeIcons(v)
    local nMine = 0
    for _, d in ipairs(appliers) do
        if d.frame and d.frame.IsShown and d.frame:IsShown() and d.getCfg
            and d.getCfg("includeInCdm") and (d.getCfg("cdmDest") or "essential") == dest then
            nMine = nMine + 1
        end
    end
    local iconLimit = v.iconLimit or 0
    if iconLimit <= 0 then
        local rows = ComputeRows(v)
        iconLimit = (rows[1] and #rows[1]) or math.max(nNat, 1)
    end
    if iconLimit < 1 then iconLimit = 1 end
    return math.max(1, math.ceil((nNat + nMine) / iconLimit))
end

-- The (row, side) bucket key an essential/utility icon falls into — kept in sync
-- with LayoutCDMRow's bucketing so the reorder arrows act on the right siblings.
local function RowBucketKey(d, nRows)
    local ri = d.getCfg("cdmRow") or 1
    if nRows and nRows > 0 then ri = math.max(1, math.min(nRows, ri)) end
    local atEnd = d.getCfg("cdmAtEnd") ~= false
    return ri .. (atEnd and "E" or "S")
end

-- Reorderable siblings of `frame`: the OUR icons it shares a bucket with — the
-- below-player row, or the same start/end of the same essential/utility row.
local function SiblingList(frame)
    local d0 = byFrame[frame]
    if not d0 or not d0.getCfg or not d0.getCfg("includeInCdm") then return {} end
    local dest = d0.getCfg("cdmDest")
    if dest == "belowPlayer" then return BelowList() end
    if not ns.GetCDMViewer(dest) then return {} end
    local nRows = EffectiveRowCount(dest)
    local k0 = RowBucketKey(d0, nRows)
    local list = {}
    for _, d in ipairs(appliers) do
        if d.frame and d.frame:IsShown() and d.getCfg and d.getCfg("includeInCdm")
            and d.getCfg("cdmDest") == dest and RowBucketKey(d, nRows) == k0 then
            list[#list + 1] = d
        end
    end
    return SortByOrder(list)
end

-- Reorder API used by the config arrows. `frame` is the tracker's icon frame.
function ns.CDMAnchor.GetMoveState(frame)
    local list = SiblingList(frame)
    if #list <= 1 then return false, false end
    for i, d in ipairs(list) do
        if d.frame == frame then return i > 1, i < #list end
    end
    return false, false
end

function ns.CDMAnchor.Move(frame, dir)
    local list = SiblingList(frame)
    if #list <= 1 then return end
    NormalizeOrder(list)
    local map = OrderMap()
    if not map then return end
    local idx
    for i, d in ipairs(list) do if d.frame == frame then idx = i break end end
    if not idx then return end
    local target = idx + dir
    if target < 1 or target > #list then return end
    local a, b = DescId(list[idx]), DescId(list[target])
    map[a], map[b] = map[b], map[a]
    ns.CDMAnchor.RefreshAll()
end

-- ── Native-row "slot" layout (essential / utility) — Ayije-style takeover ─────
-- A coexisting post-hook can't win: Blizzard re-anchors its item frames and self-
-- sizes the viewer on every layout pass. So (like Ayije_CDM) we take ownership of
-- the viewer for as long as we host icons in it:
--   * a proxy CONTAINER (our frame) is the source of truth for position + size;
--   * the protected viewer is GLUED to fill the container (TOPLEFT+BOTTOMRIGHT),
--     re-imposed via a SetPoint hook whenever Blizzard/EditMode moves it;
--   * native item frames AND our icons are positioned relative to the viewer and
--     PINNED with a per-frame SetPoint hook (raw re-impose, no recursion), so
--     Blizzard's relayout can't push them back;
--   * the container is sized to the combined content and kept centred on the
--     viewer's captured EditMode anchor, so adding icons keeps the row centred.
-- Protected ops (viewer/container SetPoint+SetSize) run OUT of combat only; the
-- per-item native re-imposes are taint-free (item frames are not protected).
-- Needs NO other CDM layout addon (Ayije / CooldownManagerCentered) on the same
-- viewer — two owners fight over the same frames.

local _proxy            = CreateFrame("Frame")
local RawSetPoint       = _proxy.SetPoint
local RawClearAllPoints = _proxy.ClearAllPoints

local containers     = {}     -- dest -> our container frame
local editModeActive = false

local function GetContainer(dest)
    local c = containers[dest]
    if not c then
        c = CreateFrame("Frame", "UnbunkUtilityCDM_" .. dest .. "_Container", UIParent)
        c:SetSize(80, 40)
        if c.SetPreventSecretValues then pcall(c.SetPreventSecretValues, c, true) end
        containers[dest] = c
    end
    return c
end

-- Capture the viewer's own (EditMode) anchor ONCE so the container can sit there
-- and stay centred as it grows. Re-captured only after the viewer is released.
local function CaptureBase(viewer, container)
    if container._uuBase then return end
    -- Anchor by the TOP-CENTRE of the viewer's current position: the row stays
    -- horizontally centred AND keeps its top edge fixed, so when adding our icons
    -- pushes the natives onto an extra row the block grows DOWNWARD instead of
    -- shifting everything up (which read as the CDM being "raised"). Works whatever
    -- point EditMode used (TOP/CENTER/...).
    local cx = viewer:GetCenter()
    local top = viewer:GetTop()
    if cx and top then
        local ucx, ucy = UIParent:GetCenter()
        container._uuBase = { p = "TOP", rel = UIParent, rp = "CENTER", x = cx - ucx, y = top - ucy }
    else
        container._uuBase = { p = "TOP", rel = UIParent, rp = "CENTER", x = 0, y = 0 }
    end
end

-- Glue the viewer to fill the container; re-impose if Blizzard/EditMode moves it.
local function GlueViewer(viewer, container)
    viewer._uuContainer = container
    viewer._uuGlued = true
    if not viewer._uuGlueHook then
        viewer._uuGlueHook = true
        hooksecurefunc(viewer, "SetPoint", function(self, _, relTo)
            if not self._uuGlued or editModeActive or InCombatLockdown() then return end
            -- Recursion is prevented by RawSetPoint (raw C method, bypasses this
            -- hook); this test is just a cheap short-circuit when Blizzard already
            -- anchored to our container.
            if relTo == self._uuContainer then return end
            RawClearAllPoints(self)
            RawSetPoint(self, "TOPLEFT",     self._uuContainer, "TOPLEFT",     0, 0)
            RawSetPoint(self, "BOTTOMRIGHT", self._uuContainer, "BOTTOMRIGHT", 0, 0)
        end)
    end
    RawClearAllPoints(viewer)
    RawSetPoint(viewer, "TOPLEFT",     container, "TOPLEFT",     0, 0)
    RawSetPoint(viewer, "BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
end

-- Pin a native item frame at a TOPLEFT offset from the viewer and keep it there.
-- EditMode/Blizzard can apply a scale ~= 1 to item frames, which breaks our
-- frame-local offsets (icons render mis-sized AND mis-aligned vs our own icons).
-- Lock the scale to 1 like Ayije does, so natives match our icons' coordinate space.
-- Defensive: today the CooldownViewer item frames are NOT protected (SetPoint on
-- them in combat is fine — confirmed by Ayije/CMC), but if a future build marks
-- them protected, writing in combat would error. Skip the write then (cosmetic
-- only — it just defers our alignment to the next out-of-combat refresh).
local function CanWrite(f)
    return not (InCombatLockdown() and f.IsProtected and f:IsProtected())
end

local function PinNative(nf, viewer, x, y)
    nf._uuPin = { viewer = viewer, x = x, y = y }
    if not CanWrite(nf) then return end
    if nf:GetScale() ~= 1 then nf:SetScale(1) end
    if not nf._uuPinHook then
        nf._uuPinHook = true
        hooksecurefunc(nf, "SetPoint", function(self)
            local pin = self._uuPin
            if not pin or self._uuPinApplying or not CanWrite(self) then return end
            self._uuPinApplying = true
            RawClearAllPoints(self)
            RawSetPoint(self, "TOPLEFT", pin.viewer, "TOPLEFT", pin.x, pin.y)
            self._uuPinApplying = false
        end)
        hooksecurefunc(nf, "SetScale", function(self, s)
            if (s or 1) ~= 1 and self._uuPin and CanWrite(self) then self:SetScale(1) end
        end)
    end
    nf._uuPinApplying = true
    RawClearAllPoints(nf)
    RawSetPoint(nf, "TOPLEFT", viewer, "TOPLEFT", x, y)
    nf._uuPinApplying = false
end

local function UnpinNatives(viewer)
    if viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
        for nf in viewer.itemFramePool:EnumerateActive() do nf._uuPin = nil end
    end
    -- Also clear any frame we pinned via the GetChildren fallback in EnumNativeIcons.
    for _, c in ipairs({ viewer:GetChildren() }) do c._uuPin = nil end
end

-- Hand the viewer back to Blizzard/EditMode (icons removed, or entering EditMode).
local function ReleaseViewer(viewer, container)
    if not viewer._uuGlued or InCombatLockdown() then return end
    viewer._uuGlued = false
    UnpinNatives(viewer)
    local b = container and container._uuBase
    RawClearAllPoints(viewer)
    if b then RawSetPoint(viewer, b.p, b.rel, b.rp, b.x, b.y) end
    if container then container._uuBase = nil end
    if viewer.Layout then pcall(viewer.Layout, viewer) end
end

local function ReleaseAll()
    for dest, vname in pairs(ns.CDM_VIEWER) do
        local v = _G[vname]
        if v then pcall(ReleaseViewer, v, containers[dest]) end
    end
end

local function LayoutCDMRow(viewer, dest, list)
    if not viewer.IsShown or not viewer:IsShown() then
        for _, d in ipairs(list) do if d.apply then pcall(d.apply) end end
        return
    end
    if editModeActive then return end
    -- The ONLY protected op is gluing the viewer (viewer:SetPoint). The container
    -- (our frame), the native pins and our icons are all unprotected, so we can
    -- keep the reflow in sync DURING combat (when natives appear/disappear) — the
    -- glued viewer follows the container automatically via its anchors. We just
    -- can't (re)glue or (re)capture in combat; if we don't even own the viewer yet,
    -- defer the whole take-over until combat ends.
    local incombat = InCombatLockdown()
    if incombat and not viewer._uuGlued then return end

    local padX = viewer.childXPadding or 3
    local padY = viewer.childYPadding or 3
    local rows = ComputeRows(viewer)

    -- Flat native item frames in visual order (rows top->bottom, then L->R).
    local natives = {}
    for _, row in ipairs(rows) do
        for _, nf in ipairs(row) do natives[#natives + 1] = nf end
    end
    local nNat = #natives

    -- Reference (native) slot size.
    local refW, refH = 30, 30
    if natives[1] then
        local w, h = natives[1]:GetSize()
        refW = (w and w > 0) and w or 30
        refH = (h and h > 0) and h or 30
    end

    -- Per-row cap so our icons "count as slots" and push natives to the next row.
    local iconLimit = viewer.iconLimit or 0
    if iconLimit <= 0 then iconLimit = (rows[1] and #rows[1]) or math.max(nNat, 1) end
    if iconLimit < 1 then iconLimit = 1 end

    -- Our shown icons with their desired (row, side).
    local mine = {}
    for _, d in ipairs(list) do
        if d.frame and d.frame:IsShown() then
            mine[#mine + 1] = { d = d, row = math.max(1, d.getCfg("cdmRow") or 1),
                                atEnd = (d.getCfg("cdmAtEnd") ~= false) }
        end
    end

    -- Total rows once our icons take their slots; clamp our requested rows to it.
    local nRows = math.max(1, math.ceil((nNat + #mine) / iconLimit))
    for _, m in ipairs(mine) do if m.row > nRows then m.row = nRows end end

    -- Reflow into a grid: our icons take their slot (atEnd from the right, atStart
    -- from the left, in saved reorder order), then natives fill the rest row-major.
    local map = OrderMap()
    local function ov(d) return (map and map[DescId(d)]) or (1000 + d.regIndex) end
    table.sort(mine, function(a, b)
        if a.row ~= b.row then return a.row < b.row end
        if a.atEnd ~= b.atEnd then return not a.atEnd end   -- start before end
        return ov(a.d) < ov(b.d)
    end)

    -- Split our icons per row + side (mine is already sorted by row, side, order).
    -- BOTH sides are laid order-ascending LEFT->RIGHT so the saved order matches the
    -- visual order — otherwise the "Move in row" arrows (which assume index 1 = left)
    -- read inverted for end-anchored icons.
    local startByRow, endByRow = {}, {}
    for _, m in ipairs(mine) do
        local t = m.atEnd and endByRow or startByRow
        t[m.row] = t[m.row] or {}
        t[m.row][#t[m.row] + 1] = m.d
    end

    local grid = {}
    for r = 1, nRows do
        grid[r] = {}
        local s = startByRow[r] or {}
        local e = endByRow[r] or {}
        -- Start icons fill cols 1.. left-to-right.
        for i = 1, #s do grid[r][i] = { d = s[i] } end
        -- End icons fill from the rightmost FREE column leftwards, skipping cells
        -- already taken by start icons. Right-aligned and still ordered L->R, but
        -- collision-safe: when #start + #end > iconLimit no start descriptor is
        -- silently overwritten/dropped (the genuine overflow simply can't fit).
        local ec = iconLimit
        for i = #e, 1, -1 do
            while ec >= 1 and grid[r][ec] do ec = ec - 1 end
            if ec < 1 then break end
            grid[r][ec] = { d = e[i] }
            ec = ec - 1
        end
    end
    local ni = 1
    for r = 1, nRows do
        for c = 1, iconLimit do
            if ni > nNat then break end
            if not grid[r][c] then grid[r][c] = { native = natives[ni] }; ni = ni + 1 end
        end
    end

    -- Build per-row item lists + measure content (max row width, all slots = refW).
    local rowItems, rowW, contentW = {}, {}, 0
    for r = 1, nRows do
        local items = {}
        for c = 1, iconLimit do if grid[r][c] then items[#items + 1] = grid[r][c] end end
        rowItems[r] = items
        local w = #items * refW + math.max(0, #items - 1) * padX
        rowW[r] = w
        if w > contentW then contentW = w end
    end
    local contentH = nRows * refH + math.max(0, nRows - 1) * padY

    -- Take ownership: container at the viewer's anchor, sized to content, centred.
    -- Capturing the anchor and gluing the viewer touch the protected viewer, so do
    -- them out of combat only; the container resize/move (our frame) is always safe
    -- and the glued viewer follows it.
    local container = GetContainer(dest)
    if not incombat then CaptureBase(viewer, container) end
    if not container._uuBase then return end
    container:SetSize(math.max(1, contentW), math.max(1, contentH))
    local b = container._uuBase
    container:ClearAllPoints()
    container:SetPoint(b.p, b.rel, b.rp, b.x, b.y)
    if not incombat then GlueViewer(viewer, container) end

    -- Clear every existing pin first, then re-pin only the current grid: a native
    -- that dropped out of the active set (cooldown used mid-combat) must not keep
    -- re-imposing its old offset and overlap our icon.
    UnpinNatives(viewer)

    -- Place each row centred within contentW, anchored to the viewer's TOPLEFT.
    for r = 1, nRows do
        local items = rowItems[r]
        local x = (contentW - rowW[r]) / 2
        local y = -(r - 1) * (refH + padY)
        for _, c in ipairs(items) do
            if c.native then
                PinNative(c.native, viewer, x, y)
            elseif c.d and c.d.frame then
                if c.d.setSize then c.d.setSize(refW, refH) end
                c.d.frame:ClearAllPoints()
                c.d.frame:SetPoint("TOPLEFT", viewer, "TOPLEFT", x, y)
            end
            x = x + refW + padX
        end
    end
end

-- ── Refresh ──────────────────────────────────────────────────────────────────
local refreshing = false
function ns.CDMAnchor.RefreshAll()
    if refreshing then return end  -- re-entrancy guard (ApplyPosition calls back)
    -- We DON'T bail in combat: only the viewer glue is protected (skipped in combat
    -- inside LayoutCDMRow); everything else (container/pins/our icons) updates live
    -- so the slot row stays in sync when natives appear/disappear mid-fight.
    refreshing = true
    -- Whole body in a pcall so a throwing getCfg can never leave `refreshing`
    -- stuck true (which would soft-lock every later refresh until /reload).
    local rok, rerr = pcall(function()
    local groups, hasBelow = {}, false
    for _, d in ipairs(appliers) do
        local inc  = d.getCfg and d.getCfg("includeInCdm")
        local dest = (d.getCfg and d.getCfg("cdmDest")) or "essential"
        if d.frame and inc and dest == "belowPlayer" then
            hasBelow = true
        elseif d.frame and inc and ns.GetCDMViewer(dest) then
            local g = groups[dest]
            if not g then g = { viewer = ns.GetCDMViewer(dest), list = {} }; groups[dest] = g end
            g.list[#g.list + 1] = d
        elseif d.apply then
            local ok, err = pcall(d.apply)
            if not ok then ns.Print("CDM anchor error: " .. tostring(err)) end
        end
    end
    for dest, g in pairs(groups) do
        local ok, err = pcall(LayoutCDMRow, g.viewer, dest, g.list)
        if not ok then ns.Print("CDM row error: " .. tostring(err)) end
    end
    -- Release any owned viewer that no longer hosts our icons.
    for dest, vname in pairs(ns.CDM_VIEWER) do
        if not groups[dest] then
            local v = _G[vname]
            if v and v._uuGlued then pcall(ReleaseViewer, v, containers[dest]) end
        end
    end
    if hasBelow then
        local okB, errB = pcall(LayoutBelowPlayer, BelowList())
        if not okB then ns.Print("CDM below error: " .. tostring(errB)) end
    end
    end)  -- pcall body
    refreshing = false
    if not rok then ns.Print("CDM refresh error: " .. tostring(rerr)) end
end

-- ── Follow the native viewers' relayout / move ───────────────────────────────
local hooked = {}
local function HookViewers()
    for _, name in pairs(ns.CDM_VIEWER) do
        local v = _G[name]
        if v and not hooked[name] then
            hooked[name] = true
            if v.RefreshLayout then hooksecurefunc(v, "RefreshLayout", function() ns.CDMAnchor.RefreshAll() end) end
            if v.Layout       then hooksecurefunc(v, "Layout",       function() ns.CDMAnchor.RefreshAll() end) end
            -- Drop our pin when the pool recycles an item frame for new content, so
            -- a stale offset is never re-imposed before the next LayoutCDMRow.
            if v.OnAcquireItemFrame then
                hooksecurefunc(v, "OnAcquireItemFrame", function(_, itemFrame)
                    if itemFrame then itemFrame._uuPin = nil end
                end)
            end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Reconcile EditMode state that may have flipped during combat so it can't
        -- get stuck (which would freeze all re-imposition).
        editModeActive = (EditModeManagerFrame and EditModeManagerFrame:IsShown()) or false
        if not editModeActive then ns.CDMAnchor.RefreshAll() end
        return
    end
    HookViewers()
    C_Timer.After(0.1, function() ns.CDMAnchor.RefreshAll() end)
end)

-- While EditMode is open we release the viewers (so the user can drag them
-- normally); on close we re-capture their new position and take ownership again.
local function EnterEditMode()
    editModeActive = true
    if not InCombatLockdown() then ReleaseAll() end
end
local function ExitEditMode()
    editModeActive = false
    -- Drop the captured anchors so the next refresh re-reads the (possibly moved)
    -- EditMode position instead of restoring the stale one.
    for _, c in pairs(containers) do c._uuBase = nil end
    C_Timer.After(0.1, function() ns.CDMAnchor.RefreshAll() end)
end

if _G.EditModeManagerFrame then
    EditModeManagerFrame:HookScript("OnShow", EnterEditMode)
    EditModeManagerFrame:HookScript("OnHide", ExitEditMode)
end
if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", EnterEditMode, ns)
    EventRegistry:RegisterCallback("EditMode.Exit",  ExitEditMode,  ns)
end
