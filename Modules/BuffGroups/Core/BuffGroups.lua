-- Modules/BuffGroups/Core/BuffGroups.lua
-- Engine for the custom "Buff groups". We REUSE the native Buff cooldown viewer
-- (BuffIconCooldownViewer) item frames — re-sized, re-styled and re-anchored into
-- user-defined GROUPS (movable containers), exactly like the reference addon Ayije_CDM.
-- The native viewer is NOT hidden; we drive its frames (so Blizzard keeps rendering the
-- cooldown swipe / charges / combat-safe aura state for us). Masque is not an obstacle:
-- we SetSize the native frame directly + refix its .Icon, then re-impose on the viewer's
-- RefreshLayout so we always write AFTER Blizzard/Masque.
--
-- Buffs are split across user-defined GROUPS via ns.db.profile.buffGroups (drag in the
-- config). A buff with no explicit assignment defaults to Group 1; group 0 ("Unused") is
-- hidden. Per-group settings apply to every icon in the group; a sparse per-icon override
-- (the pencil) wins over the group. Custom (cast-triggered) buffs are the one exception:
-- those are DRAWN by the addon (no native frame) and packed alongside the natives.
--
-- The hard parts (resize that sticks under Masque, the raw-metamethod SetPoint anti-relayout
-- hook, scale lock, combat deferral, the addon-drawn border edges) are shared with the CDM
-- rows and live in ns.CDMAnchor: PinNativeTo / ReleaseNativePin / ApplyFrameBorder.

local _, ns = ...
ns.BuffGroups = ns.BuffGroups or {}
local BG = ns.BuffGroups

local FALLBACK_ICON = 134400   -- question mark, when a spell texture can't resolve

-- In combat the player's own aura/charge fields can come back as "secret values": reading
-- or comparing one taints + errors. Guard EVERY numeric read off a native frame. The local
-- fallback keeps a client without the system loading (the guard then passes everything).
local canaccessvalue = canaccessvalue or function() return true end
local issecretvalue  = issecretvalue  or function() return false end

local containers = {}   -- containers[groupId] = Frame (one movable anchor target per group)
local trackedCache      -- array of the CDM TrackedBuff spellIds (refreshed on spec change)

-- ── Per-icon sound alert (start / stop) state ───────────────────────────────────
-- soundPrev[spellId] = was-active last pass. A buff is "active" when it has a live
-- displayed frame this RefreshLayout (frameOf[sid] ~= nil — the native pool holds the
-- ACTIVE buffs, like Ayije's BuildActiveSpellSet). On a CHANGE we fire the configured
-- start/stop sound. soundSeeded gates the FIRST pass to SEED-only (no firing) so buffs
-- already up at login/reload don't blast their start sound.
local soundPrev   = {}
local soundSeeded = false

-- Seed readiness. The native buff viewer only fills its itemFramePool (= the buffs the user
-- configured to DISPLAY, the EditMode "Tracked Buffs" section) after its first layout. Until then
-- CollectTrackedSplit returns nil and RefreshTracked DEFERS, setting pendingSeed; the viewer's
-- RefreshLayout hook (and a login fallback timer) flip viewerLaidOut and replay the deferred seed
-- once the pool is real — so a displayed buff is never seeded into Unused on a transient empty pool.
local viewerLaidOut = false
local pendingSeed   = false

-- The set of buffs currently in the native viewer's DISPLAYED pool (the EditMode "Tracked Buffs"),
-- refreshed by CollectTrackedSplit. A buff NOT in here (and not a custom) has no native frame, so it
-- cannot render — the config flags it red when it is placed in a real group. displayedKnown gates the
-- flag so we never red-flag before the pool has been read at least once.
local displayedCache = {}
local displayedKnown = false

-- ── Spell helpers ─────────────────────────────────────────────────────────────
local function SpellTexture(spellId)
    local custom = BG.GetCustom(spellId)
    if custom and custom.icon then return custom.icon end
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
    return tex or FALLBACK_ICON
end
BG.SpellTexture = SpellTexture

function BG.SpellName(spellId)
    local custom = BG.GetCustom(spellId)
    if custom and custom.name then return custom.name end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    return (info and info.name) or ("[" .. tostring(spellId) .. "]")
end

-- ── Tracked-buff enumeration (the SOURCE of which buffs exist) ─────────────────
-- The buffs we can place are the CDM's TrackedBuff category. We read the category set so
-- the CONFIG list is populated even before a buff procs; the per-frame mapping at layout
-- time uses the live pool frames. Each cooldownID resolves to a DISPLAY spell id
-- (overrideTooltipSpellID -> overrideSpellID -> spellID, the native viewer's precedence)
-- which we key everything by. All C_CooldownViewer calls are guarded — the API is nil
-- while the Cooldown Manager is disabled.
local function CooldownInfoSpellId(id)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
    if type(info) ~= "table" then return nil end
    local sid = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
    if sid and not issecretvalue(sid) and sid > 0 then return sid end
    return nil
end

-- Resolve a category id list into deduped DISPLAY spell ids (preserving the call's order).
local function ResolveCategorySet(ids, seen, out)
    if type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do
        local sid = CooldownInfoSpellId(id)
        if sid and not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
    end
end

-- The full tracked-buff set (used by AllBuffs / RefreshTracked's cache): every TrackedBuff
-- cooldown the CDM knows, displayed or not, in its native order.
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

-- The DISPLAY spell id of a native buff item frame (overrideTooltipSpellID > overrideSpellID >
-- spellID > linkedSpellIDs, the native viewer's precedence). Reads are guarded so a secret value
-- in combat never taints. Reuses ns.CDMAnchor's resolver, then the frame's own getters / linked
-- ids. Defined HERE (above CollectTrackedSplit) because the split keys the pool frames by it.
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
        if type(ci.linkedSpellIDs) == "table" then
            local lid = ci.linkedSpellIDs[1]
            if lid and not issecretvalue(lid) and lid > 0 then return lid end
        end
    end
    return nil
end

-- Split the tracked buffs into DISPLAYED (the EditMode "Tracked Buffs" section the user actually
-- shows) and NOT-displayed, both in the category's canonical order. The displayed set is the
-- native viewer's POOL — the frames Blizzard acquires for the configured buffs. (categorySet(.., false)
-- is NOT the displayed set: it filters by a different flag and returns far more than the user shows
-- — confirmed live: pool=5 vs categorySet(false)=21.) full = categorySet(.., true);
-- displayed = full ∩ pool; not-displayed = full \ pool.
-- Returns (nil, nil) until the viewer has laid out at least once (its pool reflects the user's
-- choice) so the caller DEFERS seeding rather than dumping displayed buffs into Unused.
local function CollectTrackedSplit(allowEmpty)
    local vw = _G.BuffIconCooldownViewer
    if not (viewerLaidOut and vw and vw.itemFramePool and vw.itemFramePool.EnumerateActive) then
        return nil, nil
    end
    local inPool, poolCount = {}, 0
    for f in vw.itemFramePool:EnumerateActive() do
        local sid = FrameSpellId(f)
        if sid then inPool[sid] = true; poolCount = poolCount + 1 end
    end
    -- An empty active pool right after a spec/talent change (or login) usually means Blizzard has not
    -- rebuilt the pool for the CURRENT spec yet -> defer rather than dump every displayed buff into
    -- Unused. The FORCED pass (the fallback timer) overrides this so a spec that genuinely displays
    -- nothing still seeds (everything -> Unused).
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

-- The DISPLAYED native buffs in NATIVE ON-SCREEN ORDER (the user's EditMode "Tracked Buffs"
-- arrangement). Authoritative source, matching the reference addon Ayije_CDM: each active
-- itemFramePool frame carries a numeric `layoutIndex` Blizzard assigns from the EditMode layout;
-- sorting the active frames by it ascending reproduces the on-screen order (Ayije's
-- CompareByLayoutIndex / CompareIconPositionRecords). categorySet(TrackedBuff, true/false) order
-- is NOT this order — that flag drives the spell-id set, not the displayed arrangement.
-- Every native read is guarded (the API is nil while the CDM is disabled; layoutIndex/spell ids
-- can be secret values in combat). Returns nil when the viewer hasn't laid out its pool yet, an
-- empty table when laid out but holding nothing — so callers can tell "not ready" from "nothing".
local function FrameLayoutIndex(nf)
    local li = nf and nf.layoutIndex
    if type(li) ~= "number" then return nil end
    if issecretvalue(li) or not canaccessvalue(li) then return nil end
    return li
end

function BG.NativeOrder()
    local vw = _G.BuffIconCooldownViewer
    if not (viewerLaidOut and vw and vw.itemFramePool and vw.itemFramePool.EnumerateActive) then
        return nil
    end
    -- Collect the active pool frames with their (display spellId, layoutIndex). A frame without a
    -- resolvable spell id is skipped; one without a usable layoutIndex falls to the end (huge key)
    -- but keeps a stable order via its enumeration position so it never errors / shuffles randomly.
    local entries, n = {}, 0
    for f in vw.itemFramePool:EnumerateActive() do
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

-- Reorder ONE group's saved order so its NATIVE members follow BG.NativeOrder() and its CUSTOM
-- members keep their current relative order AFTER all the natives. Operates ONLY on the group's
-- CURRENT members (BG.GetGroupBuffs) — never adds, removes, or reassigns a buff (no cross-group
-- move). A native member missing from NativeOrder (or read while the CDM is unavailable) keeps its
-- current relative order among the natives. No-op (and harmless) when NativeOrder is unavailable.
function BG.SortGroupNativeOrder(groupId)
    local members = BG.GetGroupBuffs(groupId)
    if #members == 0 then return end
    local nativeRank, rank = {}, 0
    for _, sid in ipairs(BG.NativeOrder() or {}) do
        if nativeRank[sid] == nil then rank = rank + 1; nativeRank[sid] = rank end
    end
    -- Stable split: natives first (by native rank, then current relative order as the tiebreaker),
    -- customs after (in their current relative order). Each member's current index is the tiebreaker.
    local natives, customs = {}, {}
    for i, sid in ipairs(members) do
        if BG.IsCustom(sid) then customs[#customs + 1] = { sid = sid, idx = i }
        else natives[#natives + 1] = { sid = sid, idx = i, rank = nativeRank[sid] or math.huge } end
    end
    table.sort(natives, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.idx < b.idx
    end)
    local o = BG.GroupOrder(groupId)
    wipe(o)
    for _, e in ipairs(natives) do o[#o + 1] = e.sid end
    for _, e in ipairs(customs) do o[#o + 1] = e.sid end
end

-- Can this buff actually render in a group? Customs are addon-drawn (always); a tracked buff renders
-- only if it's in the native viewer's DISPLAYED pool (its EditMode "Tracked Buffs" section). The config
-- uses these to flag a not-displayed buff dropped into a real group RED (no native frame -> never shows).
-- DisplayedKnown() lets callers avoid flagging before the pool has been read at least once.
function BG.IsDisplayed(sid) return displayedCache[sid] == true end
function BG.DisplayedKnown() return displayedKnown end
function BG.IsDisplayable(sid) return BG.IsCustom(sid) or displayedCache[sid] == true end

-- Optional callback the config UI registers (nil-safe). Fired ONLY when the DISPLAYED set actually
-- changes (the diff in BG.RefreshDisplayedCache), so the strip's red flags / tooltips / the open
-- editor's red message re-evaluate after the user edits the CDM "Tracked Buffs" in EditMode.
BG.onDisplayedChanged = nil

-- Recompute the DISPLAYED set (the same pool ∩ category logic CollectTrackedSplit builds `displayed`
-- from) straight into displayedCache, set displayedKnown, and return true if the set CHANGED vs the
-- previous (cheap diff: count + keys). Standalone from CollectTrackedSplit so it never disturbs the
-- seeding / defer logic — the ticker calls it to catch EditMode edits to the tracked-buff set.
function BG.RefreshDisplayedCache()
    local vw = _G.BuffIconCooldownViewer
    if not (viewerLaidOut and vw and vw.itemFramePool and vw.itemFramePool.EnumerateActive) then
        return false
    end
    local inPool, poolCount = {}, 0
    for f in vw.itemFramePool:EnumerateActive() do
        local sid = FrameSpellId(f)
        if sid then inPool[sid] = true; poolCount = poolCount + 1 end
    end
    -- An empty pool right after a spec change usually means Blizzard hasn't rebuilt it yet — don't
    -- clobber the known set with an empty one (matches CollectTrackedSplit's defer on poolCount == 0).
    if poolCount == 0 then return false end
    local newSet, newCount, seen = {}, 0, {}
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        and Enum and Enum.CooldownViewerCategory then
        local full = C_CooldownViewer.GetCooldownViewerCategorySet(Enum.CooldownViewerCategory.TrackedBuff, true)
        if type(full) == "table" then
            for _, id in ipairs(full) do
                local sid = CooldownInfoSpellId(id)
                if sid and not seen[sid] and inPool[sid] then
                    seen[sid] = true; newSet[sid] = true; newCount = newCount + 1
                end
            end
        end
    end
    -- Diff vs the current cache: same size AND every new key already present == unchanged.
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

function BG.RefreshTracked(force)
    trackedCache = CollectTracked()
    -- Prune Group 1's saved order of AUTO-seeded ids that are no longer tracked (keeping
    -- customs and any explicitly-assigned buffs). Without this, the seed loop below makes
    -- order[1] accumulate the union of every buff tracked-while-unassigned across all specs.
    local shown = {}
    for _, sid in ipairs(trackedCache) do shown[sid] = true end
    local o1 = BG.GroupOrder(1)
    for i = #o1, 1, -1 do
        local sid = o1[i]
        if not shown[sid] and not BG.IsCustom(sid) and BG.RawAssign(sid) == nil then
            table.remove(o1, i)
        end
    end
    -- Default seeding. Membership is no longer stored here: an UNASSIGNED buff (RawAssign == nil)
    -- resolves its group DYNAMICALLY in BG.GroupOf (displayed -> Group 1, else Unused), self-healing
    -- as the displayed set changes. So the seed's only remaining job is ORDER: append the DISPLAYED
    -- tracked buffs (native "Tracked Buffs") into order[1] in native on-screen order so Group 1 shows
    -- them in the user's EditMode arrangement. We never SetGroup(sid, 0) here any more — those sticky
    -- writes parked still-loading procs in Unused permanently (the bug). With more displayed buffs
    -- than GROUP_CAP they all simply default to Group 1 (the config strip still caps the visible row);
    -- the user can move some out manually.
    -- CollectTrackedSplit returns nil until the native viewer's pool is ready; DEFER until then
    -- (the RefreshLayout hook / a login fallback replay this) so we don't seed order off a transient
    -- empty pool.
    local displayed, notDisplayed = CollectTrackedSplit(force)
    if not displayed then pendingSeed = true; return trackedCache end
    pendingSeed = false
    -- Seed in the NATIVE ON-SCREEN order (the user's EditMode "Tracked Buffs" arrangement), not the
    -- category-set order: re-sort `displayed` by BG.NativeOrder() (the displayed set ∩ the native
    -- layout order). Any displayed buff missing from NativeOrder (or read while it's unavailable)
    -- falls to the end in its existing relative order.
    local nativeOrder = BG.NativeOrder()
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
    -- ORDER only: append each unassigned displayed buff to order[1] (idempotent — AppendOrder skips
    -- duplicates) so Group 1 lists them in native order. Membership comes from the dynamic GroupOf,
    -- so we never write an assignment here; not-displayed buffs default to Unused via GroupOf and
    -- need no order seeding (Unused has no on-screen order). `notDisplayed` stays read here only so
    -- CollectTrackedSplit's return contract is unchanged.
    local _ = notDisplayed
    for _, sid in ipairs(displayed) do
        if BG.RawAssign(sid) == nil then BG.AppendOrder(1, sid) end
    end
    -- Run the deferred V10 native-order migration now that NativeOrder is readable (the pool is up).
    BG.MigrateNativeOrder()
    return trackedCache
end

-- One-shot V10 migration (the flag is set in CfgInit; the reorder runs HERE because the native
-- order isn't readable until the viewer's pool is laid out). Re-sort EVERY group's saved order so
-- its natives follow BG.NativeOrder() with customs kept after — exactly BG.SortGroupNativeOrder per
-- group, which only reorders within a group (never moves a buff between groups). Skips silently when
-- there's nothing pending or NativeOrder is unavailable, and only flips classifyNativeOrderV10 (so
-- it stops retrying) once it has actually run against a real native order.
function BG.MigrateNativeOrder()
    local s = BG.Store()
    if not (s and s.classifyNativeOrderPending) then return end
    if BG.NativeOrder() == nil then return end   -- pool not ready yet; retry on the next seed
    for _, g in ipairs(BG.GroupList()) do BG.SortGroupNativeOrder(g.id) end
    s.classifyNativeOrderPending = nil
    s.classifyNativeOrderV10 = true
end

-- All buffs the config knows about: the tracked (CDM) buffs + user-added customs (deduped),
-- computed live so the list always reflects the current CDM tracked set.
function BG.AllBuffs()
    local out = CollectTracked()
    local seen = {}
    for _, sid in ipairs(out) do seen[sid] = true end
    for _, sid in ipairs(BG.CustomList()) do
        if not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
    end
    return out
end

-- (FrameSpellId is defined earlier, above CollectTrackedSplit, since the split keys pool frames by it.)

-- ── Aspect-preserving icon texcoord (so a non-square icon isn't stretched) ──────
-- Mirrors Ayije's GetAspectPreservingTexCoord: when w~=h we crop the longer axis instead of
-- squashing the art (our "bigger icons" use non-square sizes). A small zoom trims the ugly
-- default-icon green border.
local ICON_ZOOM = 0.07
local function IconTexCoord(w, h)
    if not (w and h) or h <= 0 or w <= 0 then return ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM end
    local texW = 1 - ICON_ZOOM * 2
    local aspect = w / h
    local xR = aspect < 1 and aspect or 1
    local yR = aspect > 1 and 1 / aspect or 1
    return -0.5 * texW * xR + 0.5,  0.5 * texW * xR + 0.5,
           -0.5 * texW * yR + 0.5,  0.5 * texW * yR + 0.5
end

-- ── Per-icon CreateFont objects for the native countdown (one per spell) ────────
-- Cooldown:SetCountdownFont wants a NAMED font object; we keep one per spell and re-point
-- its SetFont from the icon's effective timer config (icon override -> group -> default).
local cdFonts = {}
local function CountdownFont(spellId)
    local name = "UnbunkUtilityBGTimer_" .. spellId
    local f = cdFonts[spellId] or _G[name] or CreateFont(name)
    cdFonts[spellId] = f
    return f, name
end

-- ── Time thresholds: scale + recolour the countdown as the buff's time drops ────
-- Remaining seconds on a native (or custom-drawn) frame's Cooldown, read via
-- GetCooldownTimes() (start/duration in MS). In combat the player's own cooldown fields
-- can be "secret values": reading/comparing one taints, so wrap in pcall AND guard every
-- numeric with canaccessvalue / issecretvalue. Returns nil on any failure → caller keeps
-- the base style (no threshold applied).
local function FrameRemaining(nf)
    local cd = nf and nf.Cooldown
    if not (cd and cd.GetCooldownTimes) then return nil end
    local ok, startMs, durationMs = pcall(cd.GetCooldownTimes, cd)
    if not ok then return nil end
    if startMs == nil or durationMs == nil then return nil end
    if issecretvalue(startMs) or issecretvalue(durationMs) then return nil end
    if not (canaccessvalue(startMs) and canaccessvalue(durationMs)) then return nil end
    if type(startMs) ~= "number" or type(durationMs) ~= "number" then return nil end
    if durationMs <= 0 then return nil end
    return (startMs + durationMs) / 1000 - GetTime()
end

-- Is a native pool frame currently VISIBLE? The viewer keeps one pool frame per displayed buff
-- and toggles its shown state as the aura comes/goes — so "the buff is active" = its frame is
-- present in frameOf AND IsShown() is true. Guarded (IsShown returns a bool, but stay safe vs a
-- combat secret / a non-frame): a non-true result reads as inactive.
local function FrameShown(nf)
    if not nf then return false end
    local ok, s = pcall(nf.IsShown, nf)
    return ok and s and true or false
end

-- Most-urgent matching tier for `remaining` seconds: the entry with the SMALLEST `time`
-- such that remaining <= time. Returns nil when none apply (→ base size/colour).
local function MatchThreshold(list, remaining)
    if type(list) ~= "table" or remaining == nil then return nil end
    local best
    for _, t in ipairs(list) do
        local at = t.time or 0
        if remaining <= at and (not best or at < (best.time or 0)) then best = t end
    end
    return best
end

-- ── Custom (cast-triggered) buffs = frames DRAWN by the addon ───────────────────
-- A custom buff has no native frame (we can't track arbitrary auras in combat); it lives in
-- the CustomBuffs module (Core/CustomBuffs.lua), which owns activation (cast-triggered),
-- the fixed-duration swipe and the drawn-frame POOL. RefreshLayout below packs an ACTIVE
-- custom buff's drawn frame into its group alongside the natives, fetching it through the
-- module's getters: BG.CustomActive / BG.GetCustomFrame / BG.EnumActiveCustomFrames /
-- BG.HideInactiveCustomFrames (BG.CustomActive is a fallback no-op until that file loads).
if not BG.CustomActive then function BG.CustomActive() return false end end

-- ── Group containers (anchor target only — native frames are NOT reparented) ────
local function GetContainer(groupId)
    if containers[groupId] then return containers[groupId] end
    local f = CreateFrame("Frame", "UnbunkUtilityBuffGroup" .. groupId, UIParent, "BackdropTemplate")
    f:SetSize(1, 1)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    if f.SetPreventSecretValues then f:SetPreventSecretValues(true) end
    containers[groupId] = f
    return f
end
BG.GetContainer = GetContainer

-- Position a group's container per its anchorTo + posX/posY. Anchor targets:
--   essential / utility -> the native CooldownViewer (ns.GetCDMViewer), CENTERed on it;
--   belowPlayer         -> below the player frame's content;
--   screen (default)    -> UIParent CENTER.
-- Only run out of combat for the player-frame resolve safety; the container itself is ours.
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

-- Screen-space (effective-scale-normalised) coordinates of a frame's named anchor point.
-- Used by the drag-stop to measure the dropped container against its target regardless of
-- either frame's scale. Returns nil when the frame hasn't been laid out yet.
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
    return cx, cy   -- CENTER
end

-- The 8 placements (relPos) -> the (containerPoint, anchorFramePoint) pair that puts the group on
-- that side/corner of its anchor frame. e.g. "above" anchors the container's BOTTOM to the anchor's
-- TOP, so the group sits above it (the saved posX/posY then offset from there).
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

-- The anchor relationship for a group's container: (selfPoint, relativeFrame, relativePoint).
-- relPos picks WHICH side/corner of the anchor frame the group sits on; the saved posX/posY are the
-- offset on top of it. Both PositionContainer and the drag-stop read this so a drop reproduces
-- exactly (the offset is measured against the same pair it'll be re-applied with). Falls back to the
-- screen (UIParent) with the same placement when the target frame is missing.
local function ContainerAnchor(g)
    local anchorTo = g.anchorTo or "essential"
    local pts = RELPOS_POINTS[g.relPos or "above"] or RELPOS_POINTS.above
    local rel
    if anchorTo == "essential" or anchorTo == "utility" then
        rel = ns.GetCDMViewer and ns.GetCDMViewer(anchorTo)
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

-- ── Native-frame restyle (the recipe's RESIZE + RESTYLE pass) ───────────────────
-- Apply OUR size + style to a native (or custom-drawn) frame from the icon's effective
-- config. Reads off the native frame are guarded with canaccessvalue. SetSize / SetPoint /
-- SetFont with OUR numbers always work; we re-impose them after Blizzard via the RefreshLayout
-- hook and ns.CDMAnchor's per-frame SetPoint/SetSize raw hook.
local function StyleFontString(fs, fontPath, size, outline, color, init)
    if not fs or not fs.SetFont then return end
    if init then
        fs:SetIgnoreParentScale(true)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        fs:SetShadowOffset(0, 0)
        fs:SetDrawLayer("OVERLAY", 7)
    end
    fs:SetFont(fontPath, size or 12, outline or "")
    color = color or { r = 1, g = 1, b = 1, a = 1 }
    fs:SetTextColor(color.r, color.g, color.b, color.a or 1)
end

-- Best-effort anchor of a countdown FontString to the frame per the timer position config.
-- Wrapped in pcall: a region we can't touch (secret/protected) is silently skipped so the
-- font/colour application that ran before us is never undone.
local function AnchorTimerFS(fs, nf, pos, ox, oy)
    if not (fs and fs.SetPoint and ns.AnchorFS) then return end
    pcall(ns.AnchorFS, fs, nf, pos or "CENTER", ox, oy)
end

-- Re-impose OUR stack-text anchor whenever Blizzard re-anchors the native Applications FontString
-- (it drifts the count a few px on stack updates). Reads the icon's CURRENT config (stored on the FS)
-- so a per-icon position override sticks. The _uuReanchoring guard keeps the SetPoint hook from
-- recursing into itself.
local function ReanchorStack(appl)
    local nf, sid = appl._uuStackNF, appl._uuStackSid
    if not (nf and sid and ns.AnchorFS) then return end
    appl._uuReanchoring = true
    pcall(ns.AnchorFS, appl, nf, BG.IconGet(sid, "stackPos") or "BOTTOMRIGHT",
        BG.IconGet(sid, "stackOffX"), BG.IconGet(sid, "stackOffY"))
    appl._uuReanchoring = false
end

-- Re-font every FontString among a Cooldown's regions (the countdown number lives there),
-- then position them per the timer config (pos/ox/oy nil = leave SetAllPoints CENTER default).
local function StyleCooldownRegions(cd, fontPath, size, outline, color, nf, pos, ox, oy)
    if not cd then return end
    local t = cd.Text or cd.text
    StyleFontString(t, fontPath, size, outline, color, true)
    if pos then AnchorTimerFS(t, nf, pos, ox, oy) end
    for _, region in ipairs({ cd:GetRegions() }) do
        if region and region.IsObjectType and region:IsObjectType("FontString") then
            StyleFontString(region, fontPath, size, outline, color, true)
            if pos then AnchorTimerFS(region, nf, pos, ox, oy) end
        end
    end
end

-- The native title FontString we attach to a frame (Ayije draws no title; this is ours).
local function FrameTitle(nf)
    if nf.Title then return nf.Title end
    local fs = nf:CreateFontString(nil, "OVERLAY", nil, 7)
    nf.Title = fs
    return fs
end

-- Apply OUR border edges via the shared CDMAnchor helper (raw hooks, scale lock, combat-safe).
local function ApplyBorder(nf, spellId)
    if not ns.CDMAnchor or not ns.CDMAnchor.ApplyFrameBorder then return end
    local enabled = BG.IconGet(spellId, "borderEnabled") ~= false
    ns.CDMAnchor.ApplyFrameBorder(nf, enabled,
        BG.IconGet(spellId, "borderColor"), BG.IconGet(spellId, "borderSize") or 1, true)
end

-- ── Glow: a marching-dots overlay (LibCustomGlow not bundled — a self-drawn dot style)
-- enable + colour come from the icon's effective glow config. Hides the native
-- SpellActivationAlert so Blizzard's proc glow doesn't fight ours.
local function EnsureGlow(nf)
    if nf._uuGlow then return nf._uuGlow end
    local DOT_COUNT, DOT_SIZE, CYCLE = 8, 3, 1.5
    local glow = CreateFrame("Frame", nil, nf)
    glow:SetAllPoints(nf)
    glow:SetFrameLevel((nf:GetFrameLevel() or 1) + 6)
    glow:Hide()
    local dots = {}
    for i = 1, DOT_COUNT do
        local dot = glow:CreateTexture(nil, "OVERLAY", nil, 7)
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        dots[i] = dot
    end
    glow.dots = dots
    local elapsed = 0
    glow:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = (elapsed % CYCLE) / CYCLE
        local w, h = nf:GetWidth(), nf:GetHeight()
        -- Width/height are OUR pinned numbers, but guard anyway: never compare a secret.
        if not (w and h) or not canaccessvalue(w) or not canaccessvalue(h) or w == 0 or h == 0 then return end
        local perimeter = 2 * (w + h)
        for i, dot in ipairs(dots) do
            local p = (progress + (i - 1) / DOT_COUNT) % 1
            local d = p * perimeter
            local x, y
            if d < w then x, y = d, 0
            elseif d < w + h then x, y = w, -(d - w)
            elseif d < 2 * w + h then x, y = w - (d - w - h), -h
            else x, y = 0, -(perimeter - d) end
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", nf, "TOPLEFT", x, y)
        end
    end)
    nf._uuGlow = glow
    return glow
end

local function ApplyGlow(nf, spellId)
    local enabled = BG.IconGet(spellId, "glowEnabled") == true
    -- Suppress Blizzard's own proc glow on the native frame either way (it would overlap ours).
    local alert = nf.SpellActivationAlert
    if alert and alert.Hide then alert:Hide(); if alert.SetAlpha then alert:SetAlpha(0) end end
    if not enabled then
        if nf._uuGlow then nf._uuGlow:Hide() end
        return
    end
    local glow = EnsureGlow(nf)
    local c = BG.IconGet(spellId, "glowColor") or { r = 1, g = 1, b = 1, a = 1 }
    for _, dot in ipairs(glow.dots) do dot:SetColorTexture(c.r, c.g, c.b, c.a or 1) end
    glow:Show()
end

-- Hide Blizzard's native debuff border on a buff frame so only OUR border shows.
local function HideDebuffBorder(nf)
    local db = nf.DebuffBorder
    if not db then return end
    if not nf._uuDebuffBorderHooked then
        nf._uuDebuffBorderHooked = true
        hooksecurefunc(db, "Show", function(self) self:Hide() end)
    end
    db:Hide()
end

-- Resize + restyle a native (or custom) frame: SetSize -> refix .Icon -> countdown font ->
-- text regions -> stacks -> title -> border -> glow. Every native read is guarded.
local function StyleFrame(nf, spellId)
    local iconW = BG.IconGet(spellId, "iconW") or 32
    local iconH = BG.IconGet(spellId, "iconH") or 32

    -- Refix the icon texture so a non-square size doesn't stretch the art. (SetSize itself
    -- is re-imposed by PinNative's raw SetSize hook; we set it here for the custom-drawn path
    -- and to make the texcoord correct immediately.)
    nf:SetSize(iconW, iconH)
    local tex = nf.Icon
    local hasTex = tex ~= nil and (type(tex) ~= "number" or canaccessvalue(tex))
    if hasTex and tex.SetTexCoord then
        tex:ClearAllPoints()
        tex:SetAllPoints(nf)
        tex:SetTexCoord(IconTexCoord(iconW, iconH))
    end

    HideDebuffBorder(nf)

    -- Countdown: a per-spell CreateFont fed from the timer config, applied via SetCountdownFont,
    -- and the visible FontStrings (cd.Text / cd regions / frame.Time / frame.Duration) re-fonted.
    local showTimer = BG.IconGet(spellId, "showTimer") ~= false
    local fontPath  = ns.ResolveFontPath(BG.IconGet(spellId, "timerFontPath"), BG.IconGet(spellId, "timerFontKey"))
    local fontSize  = BG.IconGet(spellId, "timerFontSize") or 18
    local outline   = BG.IconGet(spellId, "timerOutline") or "OUTLINE"
    local timerColor = BG.IconGet(spellId, "timerColor")
    local timerPos  = BG.IconGet(spellId, "timerPos") or "CENTER"
    local timerOffX = BG.IconGet(spellId, "timerOffX")
    local timerOffY = BG.IconGet(spellId, "timerOffY")

    -- Time thresholds: when enabled, scale + recolour the countdown from the most-urgent
    -- matching tier of remaining time. effSize/effColor default to the base values and only
    -- diverge when a tier matches, so they feed the SAME styling below (font path / outline /
    -- position unchanged). Any secret-value / read failure leaves them at the base style.
    -- Re-evaluated every RefreshLayout (the 0.2s ticker + UNIT_AURA drive it), so the size/
    -- colour update as the buff expires.
    local effSize, effColor = fontSize, timerColor
    if BG.IconGet(spellId, "timerThresholdsEnabled") then
        local remaining = FrameRemaining(nf)
        local tier = MatchThreshold(BG.IconGet(spellId, "timerThresholds") or BG.DEFAULT_TIMER_THRESHOLDS, remaining)
        if tier then
            effSize  = fontSize * (tier.size or 1)
            effColor = tier.color or timerColor
        end
    end

    local cd = nf.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(nf)
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not showTimer) end
        local fontObj, fontName = CountdownFont(spellId)
        fontObj:SetFont(fontPath, effSize, outline)
        if effColor then fontObj:SetTextColor(effColor.r, effColor.g, effColor.b, effColor.a or 1) end
        if cd.SetCountdownFont then cd:SetCountdownFont(fontName) end
        StyleCooldownRegions(cd, fontPath, effSize, outline, effColor, nf, timerPos, timerOffX, timerOffY)
    end
    if nf.Time     then StyleFontString(nf.Time,     fontPath, effSize, outline, effColor, true); AnchorTimerFS(nf.Time,     nf, timerPos, timerOffX, timerOffY) end
    if nf.Duration then StyleFontString(nf.Duration, fontPath, effSize, outline, effColor, true); AnchorTimerFS(nf.Duration, nf, timerPos, timerOffX, timerOffY) end

    -- Stacks: the native Applications.Applications FontString, re-fonted + re-anchored per the
    -- stack config (group-level only; per-icon override is just showStack).
    local showStack = BG.IconGet(spellId, "showStack") ~= false
    local appl = nf.Applications and nf.Applications.Applications
    if appl then
        if showStack then
            local sPath = ns.ResolveFontPath(BG.IconGet(spellId, "stackFontPath"), BG.IconGet(spellId, "stackFontKey"))
            appl:SetIgnoreParentScale(true)
            appl:SetFont(sPath, BG.IconGet(spellId, "stackFontSize") or 14, BG.IconGet(spellId, "stackOutline") or "OUTLINE")
            local sc = BG.IconGet(spellId, "stackColor") or { r = 1, g = 1, b = 1, a = 1 }
            appl:SetTextColor(sc.r, sc.g, sc.b, sc.a or 1)
            appl:SetDrawLayer("OVERLAY", 7)
            -- Blizzard re-anchors this native FontString on stack updates (drifting the count). Store
            -- the icon's current config on the FS, anchor it now, and hook SetPoint ONCE to re-impose
            -- our anchor whenever Blizzard moves it — so a per-icon position override stays put.
            appl._uuStackNF, appl._uuStackSid = nf, spellId
            ReanchorStack(appl)
            if not appl._uuStackHooked then
                appl._uuStackHooked = true
                hooksecurefunc(appl, "SetPoint", function(self)
                    if not self._uuReanchoring then ReanchorStack(self) end
                end)
            end
            appl:SetShown(true)
        else
            appl:Hide()
        end
    end

    -- Title: OUR free label over the icon (group-level config; per-icon override is showTitle).
    local showTitle = BG.IconGet(spellId, "showTitle") == true
    local titleFS = FrameTitle(nf)
    if showTitle then
        titleFS:SetFont(ns.ResolveFontPath(BG.IconGet(spellId, "titleFontPath"), BG.IconGet(spellId, "titleFontKey")),
            BG.IconGet(spellId, "titleFontSize") or 12, BG.IconGet(spellId, "titleOutline") or "OUTLINE")
        local tc = BG.IconGet(spellId, "titleColor") or { r = 1, g = 1, b = 1, a = 1 }
        titleFS:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
        titleFS:SetDrawLayer("OVERLAY", 7)
        ns.AnchorFS(titleFS, nf, BG.IconGet(spellId, "titlePos") or "TOP",
            BG.IconGet(spellId, "titleOffX"), BG.IconGet(spellId, "titleOffY"))
        titleFS:SetText(BG.IconGet(spellId, "titleText") or "")
        titleFS:Show()
    else
        titleFS:Hide()
    end

    ApplyBorder(nf, spellId)
    ApplyGlow(nf, spellId)
end

-- Hide every container + drop every native/custom pin (module off / disabled). Native frames
-- are not ours to destroy; we just release our pin so Blizzard repositions them normally.
local function ReleaseNative(nf)
    if ns.CDMAnchor and ns.CDMAnchor.ReleaseNativePin then ns.CDMAnchor.ReleaseNativePin(nf) end
    if nf._uuGlow then nf._uuGlow:Hide() end
end

-- HideAll is defined just BELOW the placeholder pool (it releases placeholders), so its
-- placeholderActive / ReleasePlaceholder upvalues resolve to the real locals, not nil globals.

-- ── Placeholder frames (per-icon "Show placeholder") ───────────────────────────
-- A minimal pool of addon-drawn frames, keyed by spellId, mirroring Ayije's
-- BuffGroupPlaceholders but pared down: when an icon has its per-icon `placeholder` flag on
-- and its buff is INACTIVE (no live frame this pass), we draw a dimmed, desaturated copy of
-- the spell icon in the reserved slot (with OUR border if the group has one). Active buffs use
-- their real native/custom frame instead, so a placeholder is only ever shown in an empty slot.
local placeholderPool   = {}   -- released frames, ready to reuse
local placeholderActive = {}   -- placeholderActive[spellId] = the frame currently shown
local PLACEHOLDER_ALPHA = 0.35

local function AcquirePlaceholder(spellId)
    local f = placeholderActive[spellId]
    if f then return f end
    f = table.remove(placeholderPool)
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f.isPlaceholder = true
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(f)
        f.Icon = icon
    end
    placeholderActive[spellId] = f
    return f
end

-- Draw the dim icon + size + (optional) border into the slot, then anchor it.
local function ShowPlaceholderAt(spellId, container, x, y, w, h)
    local f = AcquirePlaceholder(spellId)
    if f:GetParent() ~= container then f:SetParent(container) end
    f:SetSize(w, h)
    f:SetFrameLevel((container:GetFrameLevel() or 1) + 1)
    local tex = f.Icon
    tex:SetTexture(SpellTexture(spellId))
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tex:SetDesaturated(true)
    tex:SetAlpha(PLACEHOLDER_ALPHA)
    -- Our border (same CDMAnchor helper the native frames use), honouring the icon's effective
    -- border config; a placeholder frame is plain (not protected) so this never taints. DrawFrameBorder
    -- stores its edge textures on f._uuBorderEdges; dim them too so the whole placeholder reads faint.
    if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then
        local enabled = BG.IconGet(spellId, "borderEnabled") ~= false
        ns.CDMAnchor.ApplyFrameBorder(f, enabled,
            BG.IconGet(spellId, "borderColor"), BG.IconGet(spellId, "borderSize") or 1, true)
        if enabled and f._uuBorderEdges then
            for _, t in pairs(f._uuBorderEdges) do t:SetAlpha(PLACEHOLDER_ALPHA) end
        end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
    f:Show()
end

local function ReleasePlaceholder(spellId)
    local f = placeholderActive[spellId]
    if not f then return end
    f:Hide()
    f:ClearAllPoints()
    if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then ns.CDMAnchor.ApplyFrameBorder(f, false) end
    if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
    placeholderActive[spellId] = nil
    placeholderPool[#placeholderPool + 1] = f
end

-- Hide every container + drop every native/custom pin + release placeholders (module off /
-- disabled). Native frames aren't ours to destroy; we just release our pin so Blizzard
-- repositions them normally.
local function HideAll()
    for _, nf in ipairs(ns.CDMAnchor and ns.CDMAnchor.EnumBuffIcons and ns.CDMAnchor.EnumBuffIcons() or {}) do
        ReleaseNative(nf)
    end
    if BG.HideInactiveCustomFrames then BG.HideInactiveCustomFrames() end
    for sid in pairs(placeholderActive) do ReleasePlaceholder(sid) end
    for _, c in pairs(containers) do c:Hide() end
end

-- ── Public refresh / layout ────────────────────────────────────────────────────
-- Enumerate the native buff frames, key each by spellId, map to a group; gather active
-- custom-buff frames the same way; then per group pack its members (in BG.GetGroupBuffs
-- order) per growDir + spacing into the group's positioned container, restyling each.
-- Frames not in a SHOWN group (group 0 Unused, or whose group was deleted) are pinned
-- offscreen so the native viewer's relayout can't re-show them in place.
local OFFSCREEN = -10000

local HORIZONTAL_GROW = { RIGHT = true, LEFT = true, CENTER_H = true }
local function IsHorizontal(grow) return grow == nil or HORIZONTAL_GROW[grow] or false end

-- Play a per-icon alert sound. Resolves the LSM "sound" key (icon override -> group ->
-- default) to a file and PlaySoundFile(..., "Master") — the same path > LSM-key logic as
-- ns.PlaySoundFromCfg, but reading through BG.IconGet rather than a flat cfg table. Guarded
-- (never errors): a missing LSM / unresolved key is a silent no-op.
local function PlayIconSound(spellId, pathKey, soundKey)
    local path = BG.IconGet(spellId, pathKey)
    if path then PlaySoundFile(path, "Master"); return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local key = BG.IconGet(spellId, soundKey)
    local resolved = key and LSM:Fetch("sound", key)
    if resolved then PlaySoundFile(resolved, "Master") end
end

-- Fire per-icon start/stop sounds off the buff's active transition. Called from RefreshLayout
-- AFTER frameOf is built; `frameOf` keys are the currently-displayed (active) buffs, so a buff
-- "becoming active" = its frame appearing. To stay cheap we only scan iconCfg entries that have
-- a start/stop sound enabled (the common case is none). On the FIRST pass we only SEED soundPrev
-- (no firing) so already-active buffs at login/reload don't blast their start sound.
-- LIMITATION: this fires off the NATIVE displayed frame's active state, so it only works for
-- buffs shown in a group (a buff parked in Unused / not displayed has no frame and is never seen
-- as active). Wrapped so a bad config or a combat secret-value can never error.
local function UpdateSounds(frameOf)
    local s = BG.Store and BG.Store()
    local iconCfg = s and s.iconCfg
    if type(iconCfg) ~= "table" then return end
    for spellId, ic in pairs(iconCfg) do
        if type(ic) == "table" and (ic.soundStartEnabled or ic.soundStopEnabled) then
            local active = frameOf[spellId] ~= nil
            if soundSeeded and active ~= soundPrev[spellId] then
                if active then
                    if BG.IconGet(spellId, "soundStartEnabled") then
                        pcall(PlayIconSound, spellId, "soundStartPath", "soundStartSound")
                    end
                else
                    if BG.IconGet(spellId, "soundStopEnabled") then
                        pcall(PlayIconSound, spellId, "soundStopPath", "soundStopSound")
                    end
                end
            end
            soundPrev[spellId] = active
        end
    end
    soundSeeded = true
end

function BG.RefreshLayout()
    if not BG.Enabled() then
        HideAll()
        return
    end

    -- Build spellId -> native frame (the live displayed set). Custom buffs have no native
    -- frame; their drawn frame stands in.
    local frameOf = {}
    for _, nf in ipairs(ns.CDMAnchor and ns.CDMAnchor.EnumBuffIcons and ns.CDMAnchor.EnumBuffIcons() or {}) do
        local sid = FrameSpellId(nf)
        if sid then frameOf[sid] = nf end
    end
    if BG.EnumActiveCustomFrames then
        for spellId, f in pairs(BG.EnumActiveCustomFrames()) do frameOf[spellId] = f end
    end

    -- Per-icon start/stop sound alerts off the active transition (frameOf = the active set).
    UpdateSounds(frameOf)

    -- Hide containers of deleted groups so a removed group's box doesn't linger.
    for gid, c in pairs(containers) do
        if not BG.GetGroup(gid) then c:Hide() end
    end

    -- Unused (group 0) + any frame whose group no longer exists: hide them. Custom (drawn)
    -- frames just Hide. Native frames are PINNED offscreen (not released) so the viewer's
    -- relayout can't reveal them in place — the re-impose hook keeps fighting Blizzard, which
    -- is taint-free (item frames aren't protected). Their own visuals/border/glow go too.
    local placed = {}
    -- Which spellIds want a dim placeholder this pass (effective `placeholder` on + inactive, in a
    -- real shown group). Drawn in the per-slot walk; any active placeholder NOT in here is released
    -- at the end (covers buffs that became active, lost the flag, moved to Unused or a deleted group).
    local placeholderNeeded = {}
    for _, sid in ipairs(BG.GetGroupBuffs(0)) do
        local nf = frameOf[sid]
        if nf then
            placed[sid] = true
            if nf.isCustomBuff then
                nf:Hide()
            else
                if nf.Title then nf.Title:Hide() end
                if nf._uuGlow then nf._uuGlow:Hide() end
                if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then ns.CDMAnchor.ApplyFrameBorder(nf, false) end
                if ns.CDMAnchor and ns.CDMAnchor.PinNativeTo then
                    ns.CDMAnchor.PinNativeTo(nf, UIParent, OFFSCREEN, OFFSCREEN)
                end
            end
        end
    end

    -- Pack each existing group's members into its positioned container.
    for _, g in ipairs(BG.GroupList()) do
        local container = GetContainer(g.id)
        if not g.unlocked then PositionContainer(g, container) end

        local members = BG.GetGroupBuffs(g.id)
        local spacing = g.spacing or 2
        local grow    = g.growDir or "RIGHT"
        local horizontal = IsHorizontal(grow)

        -- Default (reflow): lay out only members with a LIVE frame — the buffs the native viewer is
        -- currently showing (its itemFramePool holds the ACTIVE buffs) plus active customs — packed by
        -- grow direction so they reflow / re-centre as buffs proc & expire. Static Display: lay out
        -- EVERY assigned member so each keeps a FIXED slot; an inactive member (no live frame) reserves
        -- its slot but pins nothing, leaving an empty gap. A member with its per-icon `placeholder` flag
        -- on ALWAYS reserves its slot too (even in reflow mode): inactive, it draws a dim placeholder.
        -- Each frame's EFFECTIVE size is its own per-icon override (-> group -> default), so we measure
        -- up front to size the box and pack a variable cursor.
        local staticDisplay = g.staticDisplay == true
        local layoutMembers, sizes = {}, {}
        for _, sid in ipairs(members) do
            if staticDisplay or frameOf[sid] or BG.IconGet(sid, "placeholder") == true then
                layoutMembers[#layoutMembers + 1] = sid
                sizes[sid] = { w = BG.IconGet(sid, "iconW") or 36, h = BG.IconGet(sid, "iconH") or 36 }
            end
        end
        local count = #layoutMembers

        -- Box = SUM of per-slot sizes along the flow axis (+ spacing between), the max of the cross
        -- axis. The container is CENTER-anchored to the target, so sizing it to the whole strip lets
        -- CENTER_H/CENTER_V centre the strip as a unit (the strip flows from the TOPLEFT corner).
        local sumMain, maxCross = 0, 0
        for i, sid in ipairs(layoutMembers) do
            local sz = sizes[sid]
            local main  = horizontal and sz.w or sz.h
            local cross = horizontal and sz.h or sz.w
            sumMain = sumMain + main + (i > 1 and spacing or 0)
            if cross > maxCross then maxCross = cross end
        end
        if count == 0 then sumMain, maxCross = (g.iconW or 36), (g.iconH or 36) end
        local boxW = horizontal and sumMain or maxCross
        local boxH = horizontal and maxCross or sumMain
        container:SetSize(math.max(1, boxW), math.max(1, boxH))

        -- A running cursor advances by each slot's own (size + spacing) so resized icons don't overlap.
        -- RIGHT/CENTER_H/DOWN/CENTER_V flow forward from the TOPLEFT corner; LEFT/UP fill the box but run
        -- in reverse (last member nearest the corner). The pin always writes TOPLEFT->container TOPLEFT.
        local reverse = (grow == "LEFT" or grow == "UP")
        -- Cross-axis alignment for differently-sized icons in a horizontal group: line them up on the
        -- BOTTOM edge of the group, EXCEPT when the group sits below its anchor (relPos below /
        -- bottom-left / bottom-right) → line them up on the TOP, so a bigger icon always grows AWAY
        -- from the anchor. (Cross axis = height here; equal-sized icons are unaffected.)
        local rp = g.relPos or "above"
        local alignTop = (rp == "below" or rp == "bottomleft" or rp == "bottomright")
        local cursor = reverse and sumMain or 0   -- distance of the next slot's leading edge
        for idx, sid in ipairs(layoutMembers) do
            local nf = frameOf[sid]
            local sz = sizes[sid]
            local main = horizontal and sz.w or sz.h
            if reverse then cursor = cursor - main end
            local x, y
            if horizontal then x, y = cursor, (alignTop and 0 or -(maxCross - sz.h)) else x, y = 0, -cursor end
            -- An inactive member's slot is reserved (the cursor still advances below) but nothing is
            -- pinned, leaving an empty gap so the active icons stay in fixed positions — UNLESS the icon
            -- has its per-icon `placeholder` flag on, in which case a dim placeholder fills the gap.
            if nf then
                placed[sid] = true
                StyleFrame(nf, sid)
                if nf.isCustomBuff then
                    nf:ClearAllPoints()
                    nf:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
                    nf:SetSize(sz.w, sz.h)
                    nf:Show()
                elseif ns.CDMAnchor and ns.CDMAnchor.PinNativeTo then
                    -- PinNativeTo anchors nf TOPLEFT->container TOPLEFT and re-imposes both the point and
                    -- our size on Blizzard's relayout (its built-in raw SetPoint hook). Pass the PER-ICON
                    -- effective size so a resized icon keeps its override.
                    ns.CDMAnchor.PinNativeTo(nf, container, x, y, sz.w, sz.h)
                end
                -- The native viewer keeps a pool frame for every DISPLAYED buff and only IsShown()s it
                -- while the aura is up — so the frame is ALWAYS in frameOf, active or not. When the icon
                -- has its `placeholder` flag on and the buff is currently INACTIVE (native frame present
                -- but not shown), draw the ghost over the slot the (invisible) native frame occupies; when
                -- the buff procs IsShown() flips true and the end-of-pass release loop drops the ghost.
                -- Custom buffs are only ever in frameOf while ACTIVE, so they never want a ghost here.
                if not nf.isCustomBuff and BG.IconGet(sid, "placeholder") == true and not FrameShown(nf) then
                    placeholderNeeded[sid] = true
                    ShowPlaceholderAt(sid, container, x, y, sz.w, sz.h)
                end
            elseif BG.IconGet(sid, "placeholder") == true then
                placeholderNeeded[sid] = true
                ShowPlaceholderAt(sid, container, x, y, sz.w, sz.h)
            end
            if reverse then cursor = cursor - spacing else cursor = cursor + main + spacing end
        end

        container:SetShown(count > 0 or g.unlocked)
    end

    -- Any displayed buff we didn't place (its group resolved to something with no container,
    -- shouldn't happen, but be safe) is released so it isn't left mis-pinned.
    for sid, nf in pairs(frameOf) do
        if not placed[sid] then ReleaseNative(nf) end
    end

    -- Release placeholder frames no longer wanted (buff became active, lost the flag, moved to
    -- Unused / a deleted group). Collect first, then release, so we don't mutate while iterating.
    local toRelease
    for sid in pairs(placeholderActive) do
        if not placeholderNeeded[sid] then
            toRelease = toRelease or {}
            toRelease[#toRelease + 1] = sid
        end
    end
    if toRelease then for _, sid in ipairs(toRelease) do ReleasePlaceholder(sid) end end
end
-- The config's touch() calls this after every edit.
BG.ApplyAll = BG.RefreshLayout

-- Full rebuild after spec/profile change: refresh the tracked set, drop stale containers
-- for deleted groups, re-layout.
function BG.Rebuild()
    BG.RefreshTracked()
    for gid, c in pairs(containers) do
        if not BG.GetGroup(gid) then c:Hide() end
    end
    BG.RefreshLayout()
end

-- ── Per-group unlock / drag ───────────────────────────────────────────────────
function BG.IsGroupUnlocked(groupId)
    local c = containers[groupId]
    return c and c:IsMovable() and c:IsMouseEnabled() or false
end

function BG.SetGroupUnlocked(groupId, val)
    local g = BG.GetGroup(groupId); if not g then return end
    local c = GetContainer(groupId)
    if val then
        g.unlocked = true
        PositionContainer(g, c)
        c:SetSize(math.max(g.iconW or 32, 32), math.max(g.iconH or 32, 32))
        c:SetMovable(true); c:EnableMouse(true)
        c:RegisterForDrag("LeftButton")
        c:SetScript("OnDragStart", function(self) self:StartMoving() end)
        c:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Convert the dropped position back into a posX/posY offset against the SAME anchor
            -- pair PositionContainer uses, so re-applying it reproduces the drop exactly.
            local selfPt, rel, relPt = ContainerAnchor(g)
            local sx, sy = FramePointCoords(self, selfPt)
            local rx, ry = FramePointCoords(rel, relPt)
            local es = self:GetEffectiveScale() or 1
            if not (sx and rx) or es <= 0 then return end
            -- FramePointCoords is screen-space; SetPoint's offset is in the container's own
            -- (effective-scale) units, so divide the screen delta back by the container scale.
            local x = math.floor((sx - rx) / es + 0.5)
            local y = math.floor((sy - ry) / es + 0.5)
            BG.GSet(groupId, "posX", x)
            BG.GSet(groupId, "posY", y)
            self:ClearAllPoints()
            self:SetPoint(selfPt, rel, relPt, x, y)
            if BG.pe and BG.pe[groupId] then BG.pe[groupId].Refresh() end
        end)
        c:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        ns.SetBrandBorder(c, 0.8)
        c:Show()
    else
        g.unlocked = false
        c:SetMovable(false); c:EnableMouse(false)
        c:SetScript("OnDragStart", nil); c:SetScript("OnDragStop", nil)
        c:SetBackdrop(nil)
        BG.RefreshLayout()
    end
end

-- ── Re-impose on the native viewer's relayout + a light ticker ──────────────────
-- The native viewer constantly RefreshLayouts (cooldown swipes); each pass would reset our
-- size / position, so re-impose after it. The ticker also packs buffs that proc / expire
-- (their pool frame shows/hides without a layout event) within ~0.2s.
-- Make the NEXT seed wait for the native viewer to (re)build its pool for the CURRENT spec, then run
-- it. Used at login and on spec/talent change (the pool is stale/empty for the new spec until Blizzard
-- relayouts). The 3s timer guarantees a seed even if the viewer never relayouts (a spec that displays
-- zero tracked buffs -> no swipe -> the RefreshLayout hook never fires); that forced pass accepts an
-- empty pool and correctly sends everything to Unused.
local function DeferSeedUntilViewerReady()
    viewerLaidOut = false
    pendingSeed   = true
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            viewerLaidOut = true
            if BG.Enabled() and pendingSeed then BG.RefreshTracked(true); BG.RefreshLayout() end
        end)
    end
end

local refreshHooked = false
local function HookNativeViewer()
    if refreshHooked then return end
    local v = _G.BuffIconCooldownViewer
    if not v or not v.RefreshLayout then return end
    refreshHooked = true
    hooksecurefunc(v, "RefreshLayout", function()
        -- The viewer just laid out -> its itemFramePool now reflects the displayed set. Flip the
        -- readiness flag ALWAYS (even when the module is disabled) so the config's displayed-set
        -- detection works on any profile; the seed replay + our relayout stay gated on Enabled.
        viewerLaidOut = true
        if not BG.Enabled() then return end
        if pendingSeed then BG.RefreshTracked() end
        BG.RefreshLayout()
    end)
    -- Lock the viewer's scale to 1 so native frame offsets match our coordinate space
    -- (EditMode can apply a scale ~= 1). Our containers/pins assume scale 1.
    if v.SetScale and not v._uuScaleHooked then
        v._uuScaleHooked = true
        hooksecurefunc(v, "SetScale", function(self, s)
            if (s or 1) ~= 1 and BG.Enabled() then self:SetScale(1) end
        end)
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────
-- The tracked-buff SET changes on spec / talent change (and at load). UNIT_AURA "player"
-- triggers an immediate refresh for snappiness; the ticker re-imposes + packs procs.
-- The custom-buff cast trigger + PLAYER_DEAD deactivation live in the CustomBuffs module.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")   -- replay native writes deferred during combat
ev:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" or event == "PLAYER_REGEN_ENABLED" then
        if BG.Enabled() then HookNativeViewer(); BG.RefreshLayout() end
    else
        HookNativeViewer()
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
            DeferSeedUntilViewerReady()   -- the pool is stale for the new spec; re-seed once it rebuilds
        end
        BG.RefreshTracked()
        BG.RefreshLayout()
    end
end)

local accum = 0
ev:SetScript("OnUpdate", function(_, dt)
    accum = accum + dt
    if accum < 0.2 then return end
    accum = accum - 0.2
    -- Keep the displayed set fresh on EVERY profile, even when the module is DISABLED: the config's
    -- dynamic GroupOf + red flags read it, so a profile with the module off must still classify
    -- Group 1 vs Unused correctly (otherwise the strip looks frozen/empty). Also catches EditMode
    -- "Tracked Buffs" edits (which don't fire RefreshTracked); notify the config only on a real change.
    if BG.RefreshDisplayedCache() and BG.onDisplayedChanged then BG.onDisplayedChanged() end
    if not BG.Enabled() then return end
    -- Replay a seed that had to defer (e.g. enabled mid-session after a disabled-at-login defer) once
    -- the viewer is ready; harmless no-op otherwise (pendingSeed clears after one successful seed).
    if pendingSeed and viewerLaidOut then BG.RefreshTracked() end
    BG.RefreshLayout()
end)

ns.RegisterReloadHook(function() BG.Rebuild() end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    HookNativeViewer()
    BG.Rebuild()
    self:UnregisterEvent("PLAYER_LOGIN")
    DeferSeedUntilViewerReady()   -- wait for the viewer's first layout, then seed (forced after 3s)
end)
