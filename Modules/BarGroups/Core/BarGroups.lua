-- Modules/BarGroups/Core/BarGroups.lua
-- Engine for the custom "Bar groups". We REUSE the native BAR cooldown viewer
-- (BuffBarCooldownViewer) item frames — re-sized, re-styled and re-anchored into user-defined
-- GROUPS (movable containers), exactly like the Buff-groups module does for the buff ICON
-- viewer. The native viewer is NOT hidden; we drive its frames (so Blizzard keeps filling the
-- bar value / name / duration for us). Each native bar frame is a compound widget:
--   frame.Bar   = the StatusBar (its .BarBG / .Pip we hide, .Name / .Duration we keep),
--   frame.Icon  = the spell-icon frame (its .Icon texture),
-- and frame:SetBarContent is the Blizzard refresh that re-fills the bar — we hook it so our
-- style re-applies after every refresh (the the reference addon ApplyBarStyle recipe).
--
-- Bars draw from the SAME tracked-buff set as the buff ICON viewer (the CDM's TrackedBuff
-- category), so the universe + displayed-set logic mirrors Buff-groups, just pointed at the
-- BuffBarCooldownViewer pool. The hard parts (resize/anchor that sticks under Blizzard's
-- relayout, scale lock, combat deferral) are shared via ns.CDMAnchor.PinNativeTo.

local _, ns = ...
ns.BarGroups = ns.BarGroups or {}
local BR = ns.BarGroups

local FALLBACK_ICON = 134400

-- ── Pass-level layout early-out ───────────────────────────────────────────────
-- RefreshLayout runs on every driver pass (0.2s ticker + every coalesced player-aura + the native
-- viewer RefreshLayout hook), but in steady-state combat the membership + config are unchanged and
-- only each bar's VALUE animates (driven by Blizzard, not us). lastLayoutSig caches a cheap signature
-- of the NATIVE state (which bars are present + shown); a non-dirty pass whose sig is unchanged returns
-- immediately — the PinNative re-impose hooks hold every bar's geometry across skipped passes.
-- layoutDirty forces a full pass after any CONFIG change: set by ApplyAll (the UI touch choke point),
-- RefreshTracked (universe / spec), and SetGroupUnlocked (unlock + the drag reposition that follows).
local layoutDirty   = true
local lastLayoutSig = nil
local rlSigParts    = {}

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- In combat the player's own aura fields can be "secret values": reading/comparing one taints +
-- errors. Guard EVERY numeric read off a native frame. The local fallback keeps a client without
-- the system loading (the guard then passes everything).
local canaccessvalue = canaccessvalue or function() return true end
local issecretvalue  = issecretvalue  or function() return false end

local containers = {}   -- containers[groupId] = Frame (one movable anchor target per group)

-- Seed/displayed readiness (the native bar viewer fills its itemFramePool only after its first
-- layout). Until then CollectTrackedSplit returns nil and the seed DEFERS (pendingSeed); the
-- viewer's RefreshLayout hook + a login fallback timer flip viewerLaidOut and replay the seed.
local viewerLaidOut = false
local pendingSeed   = false
local displayedCache = {}
local displayedKnown = false

local BAR_VIEWER = "BuffBarCooldownViewer"

-- ── Spell helpers ─────────────────────────────────────────────────────────────
local function SpellTexture(spellId)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
    return tex or FALLBACK_ICON
end
BR.SpellTexture = SpellTexture

function BR.SpellName(spellId)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    return (info and info.name) or ("[" .. tostring(spellId) .. "]")
end

-- ── Tracked-buff enumeration (the SOURCE of which bars exist) ───────────────────
-- The bars we can place are the CDM's TrackedBuff category (the same set the buff icon viewer
-- draws, rendered as bars). All C_CooldownViewer calls are guarded — the API is nil while the
-- Cooldown Manager is disabled.
local function CooldownInfoSpellId(id)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
    if type(info) ~= "table" then return nil end
    local sid = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
    if sid and not issecretvalue(sid) and sid > 0 then return sid end
    return nil
end

local function ResolveCategorySet(ids, seen, out)
    if type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do
        local sid = CooldownInfoSpellId(id)
        if sid and not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
    end
end

local function CollectTracked()
    local out, seen = {}, {}
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        and Enum and Enum.CooldownViewerCategory) then
        return out
    end
    ResolveCategorySet(
        C_CooldownViewer.GetCooldownViewerCategorySet(Enum.CooldownViewerCategory.TrackedBuff, true),
        seen, out)
    return out
end

-- Cached resolved TrackedBuff category (the ordered {sid,...}), CONSTANT per spec/talents. The
-- displayed-cache ticker (BR.RefreshDisplayedCache, 5/s) re-fetched the category set + a per-id
-- GetCooldownViewerCooldownInfo (a fresh C table EACH) every pass = the dominant Bars churn (~215+ kB/s;
-- the pool keeps a shown=false frame per configured bar, so it runs even out of combat / unshown).
-- Cache it; invalidated by RefreshTracked (spec/talent/data-loaded). Only the per-tick POOL scan stays live.
local trackedCategory = nil
local function GetTrackedCategory()
    if trackedCategory then return trackedCategory end
    local out = {}
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        and Enum and Enum.CooldownViewerCategory then
        local seen = {}
        ResolveCategorySet(C_CooldownViewer.GetCooldownViewerCategorySet(Enum.CooldownViewerCategory.TrackedBuff, true), seen, out)
    end
    if #out > 0 then trackedCategory = out end   -- don't cache an empty (not-yet-loaded) result
    return out
end

-- The DISPLAY spell id of a native bar frame (overrideTooltipSpellID > overrideSpellID > spellID
-- > linkedSpellIDs, the native viewer's precedence). Reads are guarded so a secret value never
-- taints. Reuses ns.CDMAnchor's resolver, then the frame's own getters / linked ids.
local function FrameSpellId(nf)
    if not nf then return nil end
    local sid = ns.CDMAnchor and ns.CDMAnchor.NativeFrameSpellId and ns.CDMAnchor.NativeFrameSpellId(nf)
    if sid then return sid end
    if nf.GetSpellID then
        local ok, id = pcall(nf.GetSpellID, nf)
        if ok and id and not issecretvalue(id) and id > 0 then return id end
    end
    local ci = nf.cooldownInfo
    if type(ci) ~= "table" and nf.GetCooldownInfo then
        local ok, info = pcall(nf.GetCooldownInfo, nf)
        if ok then ci = info end
    end
    if type(ci) == "table" then
        local id = ci.overrideTooltipSpellID or ci.overrideSpellID or ci.spellID
        if id and not issecretvalue(id) and id > 0 then return id end
    end
    return nil
end

-- Active pool frames of the native bar viewer (one per DISPLAYED bar; the viewer toggles each
-- frame's shown state as the buff comes / goes, so we must NOT filter on IsShown here).
-- `out` (optional): a caller-supplied scratch array to fill (wiped here) so a hot caller can reuse
-- one table instead of allocating per call. Omitted (the exported BR.EnumBarFrames path) -> a fresh
-- table. The two internal hot callers each pass their OWN dedicated scratch (never live at once).
local function EnumBarFrames(out)
    out = out or {}
    wipe(out)
    local v = _G[BAR_VIEWER]
    if not v then return out end
    local pool = v.itemFramePool
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do if f then out[#out + 1] = f end end
    end
    if #out == 0 then
        for _, c in ipairs({ v:GetChildren() }) do
            if c and (c.cooldownInfo or c.GetCooldownInfo or c.GetSpellID) then out[#out + 1] = c end
        end
    end
    return out
end
BR.EnumBarFrames = EnumBarFrames

-- Split the tracked buffs into DISPLAYED (the ones the bar viewer actually shows) and the rest,
-- in the category's canonical order. The displayed set is the bar viewer's POOL. Returns nil
-- until the viewer has laid out at least once so the caller DEFERS seeding.
local function CollectTrackedSplit(allowEmpty)
    local v = _G[BAR_VIEWER]
    if not (viewerLaidOut and v and v.itemFramePool and v.itemFramePool.EnumerateActive) then
        return nil, nil
    end
    local inPool, poolCount = {}, 0
    for f in v.itemFramePool:EnumerateActive() do
        local sid = FrameSpellId(f)
        if sid then inPool[sid] = true; poolCount = poolCount + 1 end
    end
    if poolCount == 0 and not allowEmpty then return nil, nil end
    local displayed, notDisplayed, seen = {}, {}, {}
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        and Enum and Enum.CooldownViewerCategory then
        local full = C_CooldownViewer.GetCooldownViewerCategorySet(Enum.CooldownViewerCategory.TrackedBuff, true)
        if type(full) == "table" then
            for _, id in ipairs(full) do
                local sid = CooldownInfoSpellId(id)
                if sid and not seen[sid] then
                    seen[sid] = true
                    if inPool[sid] then displayed[#displayed + 1] = sid
                    else notDisplayed[#notDisplayed + 1] = sid end
                end
            end
        end
    end
    wipe(displayedCache)
    for _, s in ipairs(displayed) do displayedCache[s] = true end
    displayedKnown = true
    return displayed, notDisplayed
end

-- The DISPLAYED native bars in NATIVE ON-SCREEN ORDER (the user's EditMode arrangement): each
-- active pool frame carries a numeric layoutIndex Blizzard assigns; sorting by it ascending
-- reproduces the on-screen order. Guarded (the API is nil while the CDM is disabled).
local function FrameLayoutIndex(nf)
    local li = nf and nf.layoutIndex
    if type(li) ~= "number" then return nil end
    if issecretvalue(li) or not canaccessvalue(li) then return nil end
    return li
end

function BR.NativeOrder()
    local v = _G[BAR_VIEWER]
    if not (viewerLaidOut and v and v.itemFramePool and v.itemFramePool.EnumerateActive) then
        return nil
    end
    local entries, n = {}, 0
    for f in v.itemFramePool:EnumerateActive() do
        local sid = FrameSpellId(f)
        if sid then
            n = n + 1
            entries[n] = { sid = sid, li = FrameLayoutIndex(f) or math.huge, seq = n }
        end
    end
    table.sort(entries, function(a, b)
        if a.li ~= b.li then return a.li < b.li end
        return a.seq < b.seq
    end)
    local out, seen = {}, {}
    for _, e in ipairs(entries) do
        if not seen[e.sid] then seen[e.sid] = true; out[#out + 1] = e.sid end
    end
    return out
end

-- Reorder ONE group's saved order so its members follow BR.NativeOrder(). Operates only on the
-- group's CURRENT members; a member missing from NativeOrder keeps its current relative order.
function BR.SortGroupNativeOrder(groupId)
    local members = BR.GetGroupBuffs(groupId)
    if #members == 0 then return end
    local nativeRank, rank = {}, 0
    for _, sid in ipairs(BR.NativeOrder() or {}) do
        if nativeRank[sid] == nil then rank = rank + 1; nativeRank[sid] = rank end
    end
    local ranked = {}
    for i, sid in ipairs(members) do
        ranked[#ranked + 1] = { sid = sid, idx = i, rank = nativeRank[sid] or math.huge }
    end
    table.sort(ranked, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.idx < b.idx
    end)
    local o = BR.GroupOrder(groupId)
    wipe(o)
    for _, e in ipairs(ranked) do o[#o + 1] = e.sid end
end

function BR.IsDisplayed(sid) return displayedCache[sid] == true end
function BR.DisplayedKnown() return displayedKnown end
function BR.IsDisplayable(sid) return displayedCache[sid] == true end

-- Optional callback the config UI registers (nil-safe). Fired ONLY when the DISPLAYED set
-- actually changes, so the strip's red flags / tooltips re-evaluate after EditMode edits.
BR.onDisplayedChanged = nil

-- Recompute the DISPLAYED set straight into displayedCache; return true if it CHANGED.
function BR.RefreshDisplayedCache()
    local v = _G[BAR_VIEWER]
    if not (viewerLaidOut and v and v.itemFramePool and v.itemFramePool.EnumerateActive) then
        return false
    end
    local inPool, poolCount = {}, 0
    for f in v.itemFramePool:EnumerateActive() do
        local sid = FrameSpellId(f)
        if sid then inPool[sid] = true; poolCount = poolCount + 1 end
    end
    if poolCount == 0 then return false end
    -- Use the CACHED resolved category instead of re-fetching the category set + per-id cooldownInfo C
    -- tables every 0.2s tick (the ~215+ kB/s churn — runs even out of combat since poolCount > 0 above).
    local newSet, newCount, seen = {}, 0, {}
    for _, sid in ipairs(GetTrackedCategory()) do
        if not seen[sid] and inPool[sid] then
            seen[sid] = true; newSet[sid] = true; newCount = newCount + 1
        end
    end
    local oldCount = 0
    for _ in pairs(displayedCache) do oldCount = oldCount + 1 end
    local changed = (oldCount ~= newCount)
    if not changed then
        for sid in pairs(newSet) do if not displayedCache[sid] then changed = true; break end end
    end
    wipe(displayedCache)
    for sid in pairs(newSet) do displayedCache[sid] = true end
    displayedKnown = true
    return changed
end

-- One-shot V1 native-order seed (the flag is set in CfgInit; runs here because the native order
-- isn't readable until the viewer's pool is laid out). Re-sort every group's saved order so its
-- bars follow BR.NativeOrder().
function BR.MigrateNativeOrder()
    local s = BR.Store()
    if not (s and s.nativeOrderPending) then return end
    if BR.NativeOrder() == nil then return end
    for _, g in ipairs(BR.GroupList()) do BR.SortGroupNativeOrder(g.id) end
    s.nativeOrderPending = nil
    s.nativeOrderV1 = true
end

function BR.RefreshTracked(force)
    layoutDirty = true       -- the tracked universe / order may have changed -> force a full relayout pass
    trackedCategory = nil    -- spec/talent/data-loaded changed the category -> recompute the cache
    -- ORDER seed: append each unassigned DISPLAYED bar to order[1] in native on-screen order so
    -- Group 1 lists them in the user's EditMode arrangement. Membership comes from the dynamic
    -- GroupOf (never written here), so a not-displayed bar defaults to Unused and needs no order.
    local displayed = CollectTrackedSplit(force)
    if not displayed then pendingSeed = true; return end
    pendingSeed = false
    local nativeOrder = BR.NativeOrder()
    if nativeOrder then
        local rank, r = {}, 0
        for _, sid in ipairs(nativeOrder) do if rank[sid] == nil then r = r + 1; rank[sid] = r end end
        local ordered = {}
        for i, sid in ipairs(displayed) do ordered[i] = { sid = sid, idx = i, rank = rank[sid] or math.huge } end
        table.sort(ordered, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.idx < b.idx
        end)
        local out = {}
        for _, e in ipairs(ordered) do out[#out + 1] = e.sid end
        displayed = out
    end
    for _, sid in ipairs(displayed) do
        if BR.RawAssign(sid) == nil then BR.AppendOrder(1, sid) end
    end
    BR.MigrateNativeOrder()
end

-- All bars the config knows about: the tracked (CDM) buffs, computed live so the list always
-- reflects the current CDM tracked set.
-- Per-pass memo: RefreshLayout calls GetGroupBuffs once per group plus once for Unused (G+1 times),
-- and each GetGroupBuffs walks AllBuffs() -> CollectTracked() (a full CDM category scan + table
-- alloc). Within a single synchronous layout pass the tracked set is stable, so the engine ARMS this
-- memo around the group loop (BeginPass/EndPass) and AllBuffs returns the cached list instead of
-- re-scanning per group. The memo is OFF outside a pass (passMemo == nil) so every other caller
-- (config UI, RefreshTracked, drag) still gets a fresh read. The memoized list is read-only to
-- callers (GetGroupBuffs only iterates it), so sharing it across the pass is safe.
local passMemo
function BR.BeginPass() passMemo = {} end
function BR.EndPass()   passMemo = nil end

function BR.AllBuffs()
    if passMemo and passMemo.allBuffs then return passMemo.allBuffs end
    local out = CollectTracked()
    if passMemo then passMemo.allBuffs = out end
    return out
end

-- ── Group containers (anchor target only — native frames are NOT reparented) ────
local function GetContainer(groupId)
    if containers[groupId] then return containers[groupId] end
    local f = CreateFrame("Frame", "UnbunkUtilityBarGroup" .. groupId, UIParent, "BackdropTemplate")
    f:SetSize(1, 1)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    if f.SetPreventSecretValues then f:SetPreventSecretValues(true) end
    containers[groupId] = f
    return f
end
BR.GetContainer = GetContainer

local PLAYER_FRAME_CANDIDATES = {
    "ElvUF_Player", "SUFUnitplayer", "UUF_Player",
    "EllesmereUIUnitFrames_Player", "MSUF_player", "EQOLUFPlayerFrame", "oUF_Player",
}
local function ResolvePlayerFrame()
    for _, name in ipairs(PLAYER_FRAME_CANDIDATES) do
        local pf = _G[name]
        if pf and pf.IsShown and pf:IsShown() then return pf end
    end
    local pf = _G["PlayerFrame"]
    if pf then
        local content = pf.PlayerFrameContent
        local main = content and content.PlayerFrameContentMain
        return main or pf
    end
    return nil
end

-- Screen-space (effective-scale-normalised) coordinates of a frame's named anchor point — used
-- by the drag-stop to measure the dropped container against its target regardless of scale.
local function FramePointCoords(frame, point)
    if not (frame and frame.GetLeft) then return nil, nil end
    local es = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil, nil end
    l, r, t, b = l * es, r * es, t * es, b * es
    local cx, cy = (l + r) / 2, (t + b) / 2
    if point == "TOP" then return cx, t
    elseif point == "BOTTOM" then return cx, b
    elseif point == "LEFT" then return l, cy
    elseif point == "RIGHT" then return r, cy
    elseif point == "TOPLEFT" then return l, t
    elseif point == "TOPRIGHT" then return r, t
    elseif point == "BOTTOMLEFT" then return l, b
    elseif point == "BOTTOMRIGHT" then return r, b end
    return cx, cy
end

local RELPOS_POINTS = {
    above       = { "BOTTOM",      "TOP" },
    below       = { "TOP",         "BOTTOM" },
    left        = { "RIGHT",       "LEFT" },
    right       = { "LEFT",        "RIGHT" },
    topleft     = { "BOTTOMRIGHT", "TOPLEFT" },
    topright    = { "BOTTOMLEFT",  "TOPRIGHT" },
    bottomleft  = { "TOPRIGHT",    "BOTTOMLEFT" },
    bottomright = { "TOPLEFT",     "BOTTOMRIGHT" },
}

local function ContainerAnchor(g)
    local anchorTo = g.anchorTo or "essential"
    -- "screen" ignores relPos: the group is always centred on the screen (the config hides the
    -- Placement dropdown for it), so posX/posY read as an offset from UIParent's centre.
    if anchorTo == "screen" then
        return "CENTER", UIParent, "CENTER"
    end
    local pts = RELPOS_POINTS[g.relPos or "below"] or RELPOS_POINTS.below
    local rel
    if anchorTo == "essential" or anchorTo == "utility" then
        rel = (ns.CDMGroups and ns.CDMGroups.AnchorFrame and ns.CDMGroups.AnchorFrame(anchorTo))
            or (ns.GetCDMViewer and ns.GetCDMViewer(anchorTo))
    elseif anchorTo == "belowPlayer" then
        rel = ResolvePlayerFrame()
    end
    return pts[1], rel or UIParent, pts[2]
end

local function PositionContainer(g, container)
    local selfPt, rel, relPt = ContainerAnchor(g)
    container:ClearAllPoints()
    container:SetPoint(selfPt, rel, relPt, g.posX or 0, g.posY or 0)
end

-- ── Native bar restyle (the the reference addon ApplyBarStyle recipe) ─────────────────────────
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

-- Re-impose OUR custom name whenever Blizzard re-sets the bar's name FontString (it rewrites it
-- on every refresh). Hooked ONCE per frame; the apply-guard keeps the hook from recursing.
local function InstallBarNameHook(nf, nameFS)
    if not nameFS or nf._uuNameHooked then return end
    nf._uuNameHooked = true
    hooksecurefunc(nameFS, "SetText", function(self, text)
        if nf._uuNameApplyGuard then return end
        local custom = nf._uuCustomName
        if not custom or custom == "" then return end
        if text == custom then return end
        nf._uuNameApplyGuard = true
        self:SetText(custom)
        nf._uuNameApplyGuard = false
    end)
end

-- Make the gauge DRAIN (empty over time) instead of filling up: mirror Blizzard's value around its
-- min/max range on every SetValue. Hooked ONCE per StatusBar; the apply-guard stops the re-set from
-- recursing, and `nf._uuInvertFill` (read live) gates it so toggling the option just takes effect on
-- the next value tick. In combat the value can be a secret value (reading/mirroring it would taint) —
-- guarded, so an inverted bar simply falls back to Blizzard's native direction there.
local function InstallBarInvertHook(nf, bar)
    if not bar or not bar.SetValue or not bar.GetMinMaxValues or nf._uuInvertHooked then return end
    nf._uuInvertHooked = true
    hooksecurefunc(bar, "SetValue", function(self, v)
        if self._uuInvertGuard or not nf._uuInvertFill then return end
        if v == nil or issecretvalue(v) or not canaccessvalue(v) then return end
        local mn, mx = self:GetMinMaxValues()
        if mn == nil or mx == nil then return end
        if issecretvalue(mn) or issecretvalue(mx) or not (canaccessvalue(mn) and canaccessvalue(mx)) then return end
        local mirrored = mx + mn - v
        if mirrored == v then return end
        self._uuInvertGuard = true
        self:SetValue(mirrored)
        self._uuInvertGuard = false
    end)
end

-- Resize + restyle a native bar frame from the bar's effective config (per-bar override -> group
-- -> default). The outer frame IS the whole row (icon + gauge); the StatusBar fills the width not
-- taken by the icon. SetReverseFill maps our fill direction; the background texture is OUR own
-- (Blizzard's bar.BarBG is hidden). Every native read is guarded.
local function StyleBarFrame(nf, spellId)
    local barW   = BR.IconGet(spellId, "barWidth")  or 150
    local barH   = BR.IconGet(spellId, "barHeight") or 15
    local iconPos = BR.IconGet(spellId, "iconPosition")  or "LEFT"
    local fillDir = BR.IconGet(spellId, "fillDirection") or "LEFT"
    local barColor = BR.IconGet(spellId, "barColor") or { r = 1, g = 1, b = 1, a = 1 }
    local bgColor  = BR.IconGet(spellId, "bgColor")  or { r = 1, g = 1, b = 1, a = 1 }
    local iconGap  = BR.IconGet(spellId, "iconGap") or 1
    local texKey   = BR.IconGet(spellId, "barTexture")
    local barTex   = (LSM and texKey and LSM:Fetch("statusbar", texKey)) or BAR_TEXTURE
    local invertFill = BR.IconGet(spellId, "invertFill") == true   -- default false (fill); only an explicit true drains
    local nameOverride = BR.IconGet(spellId, "nameOverride") == true
    local customName   = BR.IconGet(spellId, "customName")

    nf:SetSize(barW, barH)

    local bar  = nf.Bar
    local icon = nf.Icon

    -- One-time hides + the re-style-on-refresh hook.
    if not nf._uuBarHidesDone then
        nf._uuBarHidesDone = true
        if nf.DebuffBorder then nf.DebuffBorder:Hide() end
        if bar then
            if bar.BarBG then bar.BarBG:Hide(); bar.BarBG:SetAlpha(0) end
            if bar.Pip then
                bar.Pip:Hide(); bar.Pip:SetAlpha(0)
                if not nf._uuPipHooked then
                    nf._uuPipHooked = true
                    hooksecurefunc(bar.Pip, "Show", function(self) self:Hide(); self:SetAlpha(0) end)
                end
            end
        end
    end
    if not nf._uuBarContentHooked and nf.SetBarContent then
        nf._uuBarContentHooked = true
        -- Blizzard re-fills the bar on a refresh; mark it dirty so the next layout pass re-styles.
        hooksecurefunc(nf, "SetBarContent", function(self) self._uuBarStyled = false end)
    end

    -- Spell icon: square (height = bar height), on the chosen side, or hidden.
    if icon then
        if iconPos == "HIDDEN" then
            icon:Hide()
        else
            icon:Show()
            icon:SetSize(barH, barH)
            icon:ClearAllPoints()
            if iconPos == "RIGHT" then
                icon:SetPoint("RIGHT", nf, "RIGHT", 0, 0)
            else
                icon:SetPoint("LEFT", nf, "LEFT", 0, 0)
            end
            local tex = icon.Icon
            if tex and tex.SetTexCoord then
                tex:ClearAllPoints(); tex:SetAllPoints(icon); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            end
        end
    end

    -- StatusBar: fills the frame width minus the icon + gap.
    if bar then
        bar:ClearAllPoints()
        bar:SetHeight(barH)
        if iconPos == "HIDDEN" or not icon then
            bar:SetPoint("LEFT", nf, "LEFT", 0, 0)
            bar:SetPoint("RIGHT", nf, "RIGHT", 0, 0)
        elseif iconPos == "RIGHT" then
            bar:SetPoint("LEFT", nf, "LEFT", 0, 0)
            bar:SetPoint("RIGHT", icon, "LEFT", -iconGap, 0)
        else
            bar:SetPoint("LEFT", icon, "RIGHT", iconGap, 0)
            bar:SetPoint("RIGHT", nf, "RIGHT", 0, 0)
        end
        bar:SetStatusBarTexture(barTex)
        bar:SetStatusBarColor(barColor.r, barColor.g, barColor.b, barColor.a or 1)
        -- fillDirection "RIGHT" = gauge anchored left, grows rightward (SetReverseFill false);
        -- "LEFT" = anchored right, drains/grows leftward (SetReverseFill true). The exact visual
        -- is confirmed in-game; flip this single mapping if it reads reversed.
        if bar.SetReverseFill then bar:SetReverseFill(fillDir == "LEFT") end
        -- Drain-vs-fill: mirror Blizzard's value when invertFill is on (read live by the hook).
        nf._uuInvertFill = invertFill
        InstallBarInvertHook(nf, bar)
        -- OUR background texture (Blizzard's bar.BarBG is hidden above).
        if not nf._uuBarBG then nf._uuBarBG = bar:CreateTexture(nil, "BACKGROUND", nil, -1) end
        nf._uuBarBG:ClearAllPoints(); nf._uuBarBG:SetAllPoints(bar)
        nf._uuBarBG:SetTexture(barTex)
        nf._uuBarBG:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 1)

        -- Custom name override: hook the name FontString so it survives Blizzard's refresh.
        if bar.Name then
            nf._uuCustomName = (nameOverride and type(customName) == "string" and customName ~= "") and customName or nil
            InstallBarNameHook(nf, bar.Name)
            if nf._uuCustomName then bar.Name:SetText(nf._uuCustomName) end
        end
    end

    nf._uuBarStyled = true
    nf._uuStyleVer  = BR.StyleVersion()
end

-- Drop our pin on a native bar (module off / bar moved out): Blizzard repositions it normally.
local function ReleaseNative(nf)
    if ns.CDMAnchor and ns.CDMAnchor.ReleaseNativePin then ns.CDMAnchor.ReleaseNativePin(nf) end
end

local hideAllScratch = {}
local function HideAll()
    for _, nf in ipairs(EnumBarFrames(hideAllScratch)) do ReleaseNative(nf) end
    for _, c in pairs(containers) do c:Hide() end
    -- Un-park: when we ran while enabled we parked Unused/unassigned bars OFFSCREEN, so on a runtime
    -- toggle-off we must ask the viewer to re-lay-out to bring them back to their EditMode positions.
    -- BUT only when WE actually drove the viewer this session — `viewerLaidOut` is set true ONLY by the
    -- native viewer's RefreshLayout hook, which is installed only by HookNativeViewer() (enabled path).
    -- On a fresh /reload while DISABLED that hook was never installed (viewerLaidOut == false) and nothing
    -- was ever pinned, so poking Blizzard's not-yet-laid-out viewer would COLLAPSE the native bars. A
    -- disabled module must do zero work and hand the viewer fully back to Blizzard (matches BuffGroups).
    -- Combat-guarded — a protected relayout could taint.
    if viewerLaidOut then
        local v = _G[BAR_VIEWER]
        if v and v.RefreshLayout and not InCombatLockdown() then pcall(v.RefreshLayout, v) end
    end
end

-- Is a native bar frame currently VISIBLE (its buff is active)? Unlike the buff ICON viewer (which
-- releases a pool frame when the buff falls off), the bar viewer keeps a pool frame per DISPLAYED
-- bar and just toggles its shown state — so "active" = IsShown true, and reflow must filter on it
-- (otherwise every displayed bar always takes a slot, i.e. it looks static). Guarded: a combat
-- secret / non-frame reads as inactive.
local function FrameShown(nf)
    if not nf then return false end
    local ok, s = pcall(nf.IsShown, nf)
    return ok and s and true or false
end

-- ── Public refresh / layout ─────────────────────────────────────────────────────
-- Enumerate the native bar frames, key each by spellId, map to a group, then per group stack its
-- members vertically (DOWN/UP) into the group's positioned container, restyling each. Bars not in
-- a SHOWN group (Unused / deleted) are pinned offscreen so the viewer can't re-show them in place.
local OFFSCREEN = -10000

-- Reused scratch tables for RefreshLayout (it is NOT re-entrant — it is only ever called from the
-- event/timer handlers and the deferred relayout, never nested within itself, and none of the
-- helpers it calls re-enter it), so we wipe() and refill these instead of allocating per pass.
-- `rlFrameOf`/`rlPlaced` span the whole pass; `rlLayout`/`rlWidths`/`rlHeights` are per-group (wiped
-- at the top of each group iteration). `rlEnum` is RefreshLayout's own EnumBarFrames scratch.
local rlEnum    = {}
local rlFrameOf = {}
local rlPlaced  = {}
local rlLayout  = {}
local rlWidths  = {}
local rlHeights = {}

function BR.RefreshLayout()
    if not BR.Enabled() then
        HideAll()
        return
    end

    local frameOf = rlFrameOf
    wipe(frameOf)
    local sp = rlSigParts; wipe(sp)
    for _, nf in ipairs(EnumBarFrames(rlEnum)) do
        local sid = FrameSpellId(nf)
        if sid then
            frameOf[sid] = nf
            sp[#sp + 1] = sid .. (FrameShown(nf) and "+" or "-")
        end
    end
    -- Pass-level early-out: when not dirtied by a config change AND the native bar set (which bars are
    -- present + shown) is unchanged since the last full pass, the whole grouping/layout/pin body below
    -- is a no-op — the PinNative hooks hold every bar's geometry. Sorted so pool iteration order can't
    -- spoof a change. (A bar VALUE tick changes neither membership nor shown-state, so it skips.)
    table.sort(sp)
    local sig = table.concat(sp, ",")
    if not layoutDirty and sig == lastLayoutSig then
        -- Layout unchanged, but Blizzard's SetBarContent refill clears _uuBarStyled on a still-present
        -- bar; re-style just the dirtied bars (no layout / no re-pin) so the refill can't revert our
        -- texture/colour. The StyleBarFrame gate skips bars already styled at the current StyleVersion.
        for sid, nf in pairs(frameOf) do
            if not nf._uuBarStyled or nf._uuStyleVer ~= BR.StyleVersion() then
                StyleBarFrame(nf, sid)
            end
        end
        return
    end
    layoutDirty   = false
    lastLayoutSig = sig

    -- Hide containers of deleted groups.
    for gid, c in pairs(containers) do
        if not BR.GetGroup(gid) then c:Hide() end
    end

    -- Unused (group 0) + any bar whose group no longer exists: pin offscreen (not released) so
    -- the viewer's relayout can't reveal them in place.
    local placed = rlPlaced
    wipe(placed)
    -- Arm the per-pass AllBuffs memo: the tracked set is read ONCE here and reused by every
    -- GetGroupBuffs below (Unused + each group) instead of a full CDM scan per group. Dropped at the
    -- end of the group loop (no AllBuffs reads after it).
    BR.BeginPass()
    for _, sid in ipairs(BR.GetGroupBuffs(0)) do
        local nf = frameOf[sid]
        if nf then
            placed[sid] = true
            if ns.CDMAnchor and ns.CDMAnchor.PinNativeTo then
                ns.CDMAnchor.PinNativeTo(nf, UIParent, OFFSCREEN, OFFSCREEN)
            end
        end
    end

    -- Pack each existing group's members into its positioned container.
    for _, g in ipairs(BR.GroupList()) do
        local container = GetContainer(g.id)
        if not g.unlocked then PositionContainer(g, container) end

        local members = BR.GetGroupBuffs(g.id)
        local spacing = g.spacing or 2
        local up = (g.growDir == "UP")
        local staticDisplay = g.staticDisplay == true

        -- Reflow (default): lay out only members whose bar is currently SHOWN (the buff is active),
        -- so the active bars pack together and re-flow as buffs proc / expire. Static Display: lay out
        -- EVERY assigned member so each keeps a fixed slot (an inactive one reserves its slot but stays
        -- invisible). Each bar's effective width/height is its own per-bar override (-> group -> default).
        local layoutMembers, widths, heights = rlLayout, rlWidths, rlHeights
        wipe(layoutMembers); wipe(widths); wipe(heights)
        local maxW, sumH = 0, 0
        for _, sid in ipairs(members) do
            local nf = frameOf[sid]
            local show = nf and FrameShown(nf)
            if staticDisplay or show then
                layoutMembers[#layoutMembers + 1] = sid
                local w = BR.IconGet(sid, "barWidth")  or 150
                local h = BR.IconGet(sid, "barHeight") or 15
                widths[sid], heights[sid] = w, h
                if w > maxW then maxW = w end
                sumH = sumH + h + (#layoutMembers > 1 and spacing or 0)
            elseif nf then
                -- Reflow + inactive: pin the (hidden) native frame offscreen so it neither reserves a
                -- slot here nor reappears at the native bar viewer's position when its pin is dropped.
                placed[sid] = true
                if ns.CDMAnchor and ns.CDMAnchor.PinNativeTo then
                    ns.CDMAnchor.PinNativeTo(nf, UIParent, OFFSCREEN, OFFSCREEN)
                end
            end
        end
        local count = #layoutMembers
        if count == 0 then maxW = (g.barWidth or 150); sumH = (g.barHeight or 15) end
        container:SetSize(math.max(1, maxW), math.max(1, sumH))

        -- Position each bar by its TOPLEFT within the container (the pin re-imposes TOPLEFT). DOWN:
        -- first member at the top, growing down. UP: first member at the BOTTOM, growing up.
        local fromBottom = 0   -- only used for UP
        local cursor = 0       -- only used for DOWN
        for _, sid in ipairs(layoutMembers) do
            local nf = frameOf[sid]
            local w, h = widths[sid], heights[sid]
            local yTop
            if up then
                yTop = -(sumH - (fromBottom + h))
                fromBottom = fromBottom + h + spacing
            else
                yTop = -cursor
                cursor = cursor + h + spacing
            end
            if nf then
                placed[sid] = true
                -- Re-style only when something changed: the bar is dirty (Blizzard re-filled it, which
                -- clears _uuBarStyled via the SetBarContent hook) OR the config moved on (StyleVersion
                -- bumped by any per-bar/group write). Per aura tick neither changes, so the bar keeps its
                -- style and only Blizzard's own fill/value updates — the pin below re-imposes geometry
                -- every pass regardless, so a skipped restyle never leaves the size wrong.
                if not nf._uuBarStyled or nf._uuStyleVer ~= BR.StyleVersion() then
                    StyleBarFrame(nf, sid)
                end
                if ns.CDMAnchor and ns.CDMAnchor.PinNativeTo then
                    ns.CDMAnchor.PinNativeTo(nf, container, 0, yTop, w, h)
                end
            end
        end

        container:SetShown(count > 0 or g.unlocked)
    end
    BR.EndPass()  -- done consuming the universe; drop the memo so other callers read fresh

    -- Any displayed bar we didn't place is released so it isn't left mis-pinned.
    for sid, nf in pairs(frameOf) do
        if not placed[sid] then ReleaseNative(nf) end
    end
end
-- The config UI's touch() calls this after every edit; force a full relayout pass since config
-- changes are not in the native-state signature.
function BR.ApplyAll() layoutDirty = true; BR.RefreshLayout() end

function BR.Rebuild()
    BR.RefreshTracked()
    for gid, c in pairs(containers) do
        if not BR.GetGroup(gid) then c:Hide() end
    end
    BR.RefreshLayout()
end

-- ── Per-group unlock / drag ───────────────────────────────────────────────────
function BR.IsGroupUnlocked(groupId)
    local c = containers[groupId]
    return c and c:IsMovable() and c:IsMouseEnabled() or false
end

function BR.SetGroupUnlocked(groupId, val)
    local g = BR.GetGroup(groupId); if not g then return end
    layoutDirty = true   -- unlock/lock + the resulting drag reposition need a full relayout pass
    local c = GetContainer(groupId)
    if val then
        g.unlocked = true
        PositionContainer(g, c)
        c:SetSize(math.max(g.barWidth or 150, 20), math.max(g.barHeight or 15, 10))
        c:SetMovable(true); c:EnableMouse(true)
        c:RegisterForDrag("LeftButton")
        c:SetScript("OnDragStart", function(self) self:StartMoving() end)
        c:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local selfPt, rel, relPt = ContainerAnchor(g)
            local sx, sy = FramePointCoords(self, selfPt)
            local rx, ry = FramePointCoords(rel, relPt)
            local es = self:GetEffectiveScale() or 1
            if not (sx and rx) or es <= 0 then return end
            local x = math.floor((sx - rx) / es + 0.5)
            local y = math.floor((sy - ry) / es + 0.5)
            BR.GSet(groupId, "posX", x)
            BR.GSet(groupId, "posY", y)
            self:ClearAllPoints()
            self:SetPoint(selfPt, rel, relPt, x, y)
            if BR.pe and BR.pe[groupId] then BR.pe[groupId].Refresh() end
        end)
        c:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        ns.SetBrandBorder(c, 0.8)
        c:Show()
    else
        g.unlocked = false
        c:SetMovable(false); c:EnableMouse(false)
        c:SetScript("OnDragStart", nil); c:SetScript("OnDragStop", nil)
        c:SetBackdrop(nil)
        BR.RefreshLayout()
    end
end

-- ── Re-impose on the native viewer's relayout + a light ticker ──────────────────
local function DeferSeedUntilViewerReady()
    viewerLaidOut = false
    pendingSeed   = true
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            viewerLaidOut = true
            if BR.Enabled() and pendingSeed then BR.RefreshTracked(true); BR.RefreshLayout() end
        end)
    end
end

-- Coalesced, DEFERRED relayout. The RefreshLayout hook runs INSIDE Blizzard's RefreshData; doing
-- the read-heavy relayout (which touches the pool's secret cooldownInfo / layoutIndex) there
-- taints that secure execution. So the hook only flips the readiness bool + schedules this.
local barRelayoutScheduled = false
local function ScheduleRelayout()
    if barRelayoutScheduled then return end
    barRelayoutScheduled = true
    C_Timer.After(0, function()
        barRelayoutScheduled = false
        if not BR.Enabled() then return end
        if pendingSeed then BR.RefreshTracked() end
        BR.RefreshLayout()
    end)
end

-- Player-aura relayouts are the HIGH-FREQUENCY driver (UNIT_AURA "player" fires ~every frame in raid
-- combat). They get their OWN 0.1s throttle so this engine's aura relayout doesn't run every frame inside
-- the shared AuraDispatch flush (which also runs the two CDMGroups engines + BuffGroups back-to-back -- four
-- full relayouts at ~60Hz saturated the frame's insecure-execution budget = "script ran too long"). The
-- viewer-hook ScheduleRelayout above stays next-frame so a Blizzard bar refill is re-styled promptly.
local barAuraRelayoutScheduled = false
local function ScheduleAuraRelayout()
    if barAuraRelayoutScheduled then return end
    barAuraRelayoutScheduled = true
    C_Timer.After(0.1, function()
        barAuraRelayoutScheduled = false
        if not BR.Enabled() then return end
        if pendingSeed then BR.RefreshTracked() end
        BR.RefreshLayout()
    end)
end

local refreshHooked = false
local function HookNativeViewer()
    if refreshHooked then return end
    local v = _G[BAR_VIEWER]
    if not v or not v.RefreshLayout then return end
    refreshHooked = true
    hooksecurefunc(v, "RefreshLayout", function()
        viewerLaidOut = true
        if BR.Enabled() then ScheduleRelayout() end
    end)
    if v.SetScale and not v._uuScaleHooked then
        v._uuScaleHooked = true
        hooksecurefunc(v, "SetScale", function(self, s)
            if (s or 1) ~= 1 and BR.Enabled() then self:SetScale(1) end
        end)
    end
end

-- Exported so the enable toggle can (re)install the native-viewer hooks on re-enable. Idempotent
-- (refreshHooked / _uuScaleHooked guards), so a repeat call is a no-op. Login + events now skip the
-- bring-up while disabled, so this is the restart path together with BR.Rebuild.
function BR.HookNativeViewerPublic() HookNativeViewer() end

-- Full bring-up when the module (re)gains control of the native bar viewer: install the viewer hooks,
-- rebuild the tracked set + layout, then ARM THE 3s SEED FALLBACK. The fallback is essential when we were
-- DISABLED at login (so HookNativeViewer never ran and viewerLaidOut stayed false): without it the seed
-- DEFERS forever (pendingSeed) and unassigned bars stay "Unused" -> pinned OFFSCREEN -> invisible. Shared by
-- login AND the CDM engine->native mode switch (BarGroups re-enabled). Mirrors the proven login sequence.
function BR.Activate()
    HookNativeViewer()
    BR.Rebuild()
    DeferSeedUntilViewerReady()
end

-- ── Events ────────────────────────────────────────────────────────────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
ev:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")   -- an EditMode "Tracked Buffs" edit changes the category set
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
-- UNIT_AURA goes through the shared coalescing dispatcher, then our 0.1s aura throttle so a 60Hz combat
-- aura stream drives at most ~10Hz of full relayouts (not one per frame inside the AuraDispatch flush).
ns.AuraDispatch.Register("player", function()
    if BR.Enabled() then HookNativeViewer(); ScheduleAuraRelayout() end
end)
ev:SetScript("OnEvent", function(_, event)
    -- Disabled module does ZERO event work: the secure hooks / seed are (re)installed by the enable
    -- toggle's set handler (BR.HookNativeViewerPublic + BR.Rebuild) and by login when enabled, so a
    -- spec/zone change while off needs no handling. Re-enable is UI-driven, so skipping here is safe.
    if not BR.Enabled() then return end
    if event == "PLAYER_REGEN_ENABLED" then
        HookNativeViewer(); BR.RefreshLayout()
    else
        HookNativeViewer()
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
            DeferSeedUntilViewerReady()
        end
        BR.RefreshTracked()
        BR.RefreshLayout()
    end
end)

local accum = 0
ev:SetScript("OnUpdate", function(_, dt)
    -- Gate: the only consumer of this poll while the module is DISABLED is the config strip's
    -- displayed-set red flags, which read displayedCache via BR.onDisplayedChanged. When the module
    -- is off AND no config consumer is registered (the panel was never opened), there is nothing to
    -- keep fresh — skip ALL work (no accum bookkeeping, no native pool scan) so a disabled module is
    -- truly idle.
    if not (BR.Enabled() or BR.onDisplayedChanged) then return end
    accum = accum + dt
    if accum < 0.2 then return end
    accum = accum - 0.2
    -- Keep the displayed set fresh on EVERY profile (the config's GroupOf + red flags read it),
    -- even when the module is DISABLED. Notify the config only on a real change.
    if BR.RefreshDisplayedCache() and BR.onDisplayedChanged then BR.onDisplayedChanged() end
    if not BR.Enabled() then return end
    if pendingSeed and viewerLaidOut then BR.RefreshTracked() end
    BR.RefreshLayout()
end)

ns.RegisterReloadHook(function() BR.Rebuild() end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Only stand up the engine (native-viewer hooks, tracked seed, layout) at login if currently
    -- enabled. When disabled, the re-enable paths (enable toggle / CDM engine->native switch) do this
    -- via BR.Activate.
    if not BR.Enabled() then return end
    BR.Activate()
end)
