-- Modules/CDMGroups/Core/Engine.lua
-- Engine for the custom "Cooldown groups" — a GENERALIZED, dest-parameterized clone of the
-- Modules/BuffGroups/Core/BuffGroups.lua engine. We REUSE the native cooldown viewer item frames
-- (re-sized, re-styled, re-anchored into user-defined GROUPS), exactly like BuffGroups / the reference CDM addon.
-- The native viewer is NOT hidden; we drive its frames so Blizzard keeps rendering the cooldown
-- swipe / charges / combat-safe state. The hard parts (resize that sticks under Masque, the raw
-- SetPoint anti-relayout hook, scale lock, combat deferral, the addon-drawn border) are SHARED with
-- the CDM rows and the buff groups — they live in ns.CDMAnchor (PinNativeTo / ReleaseNativePin /
-- ApplyFrameBorder / NativeFrameSpellId). We add only an Essential-specific enumerator here.
--
-- DEST-PARAMETERIZATION: ns.CDMGroups.Make(dest) (in Config.lua) returns an INSTANCE table `I` with
-- the data accessors; EngineFor(I) attaches the runtime methods (AllBuffs, NativeOrder, RefreshLayout,
-- Rebuild, group drag) onto the SAME `I`, capturing the per-dest viewer global + Enum category. So a
-- second dest ("utility", later) is one EngineFor(ns.CDMGroups.Make("utility")) call — no engine code
-- changes. Only "essential" is instantiated this phase.
--
-- RUNTIME MODEL (confirmed by a live diagnostic — the category set is the WRONG source):
--   * SOURCE OF TRUTH = the viewer's itemFramePool, exactly like BuffGroups. The pool's active frames
--     ARE the set the viewer actually displays (10 Essential cooldowns incl. defensives, with stable
--     layoutIndex 1..N; IsShown just toggles per cooldown state). GetCooldownViewerCategorySet does
--     NOT match it: categorySet(Essential,false)=6 (frost damage only); (true)=11 (adds not-displayed
--     spells, no defensives). So we DROP the category set entirely and read the pool.
--   * UNIVERSE (I.AllBuffs) = the displayed set (spellIds resolved from the pool via EnumNativeFrames)
--     UNION any explicitly-assigned spellId in the store (so a manual assignment persists even if a
--     cooldown momentarily leaves the pool). Mirrors BuffGroups' "displayed ∪ assigned ∪ custom".
--   * DISPLAYED set = the spellIds currently in the pool. I.IsDisplayed/RefreshDisplayedCache/
--     DisplayedKnown mirror BuffGroups: an UNASSIGNED cooldown defaults to Group 1 only if displayed,
--     else Unused, and the config flags a not-displayed cooldown dropped into a real group RED.
--   * LIVE frames to POSITION = the same pool's active frames, keyed by spellId. The pool is DYNAMIC:
--     a grouped cooldown shows when its frame is present (reflow; default). Native order = layoutIndex.

local _, ns = ...
ns.CDMGroups = ns.CDMGroups or {}
local CDG = ns.CDMGroups

local FALLBACK_ICON = 134400   -- question mark

-- Combat secret-value guards (mirror BuffGroups). The local fallbacks keep a client without the
-- system loading working (the guard then passes everything).
local canaccessvalue = canaccessvalue or function() return true end
local issecretvalue  = issecretvalue  or function() return false end

-- Per-dest -> viewer global frame name. Only "essential" is built this phase. (The Enum category is no
-- longer read: the displayed set / universe come from the viewer's frame pool, not the category set.)
local DEST_VIEWER = { essential = "EssentialCooldownViewer", utility = "UtilityCooldownViewer" }

-- ── Spell helpers ────────────────────────────────────────────────────────────
local function SpellTexture(spellId)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
    return tex or FALLBACK_ICON
end

local function SpellName(spellId)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    return (info and info.name) or ("[" .. tostring(spellId) .. "]")
end

-- ── Aspect-preserving icon texcoord (so a non-square icon isn't stretched) ─────
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

-- Most-urgent matching tier for `remaining` seconds (smallest `time` such that remaining <= time).
local function MatchThreshold(list, remaining)
    if type(list) ~= "table" or remaining == nil then return nil end
    local best
    for _, t in ipairs(list) do
        local at = t.time or 0
        if remaining <= at and (not best or at < (best.time or 0)) then best = t end
    end
    return best
end

-- ════════════════════════════════════════════════════════════════════════════════
-- EngineFor(I): attach the runtime onto a Config instance, capturing the dest's viewer + category.
-- ════════════════════════════════════════════════════════════════════════════════
local function EngineFor(I)
    local dest      = I.dest
    local viewerName = DEST_VIEWER[dest]

    -- Per-instance runtime state (NOT shared between dests).
    local containers   = {}     -- containers[groupId] = Frame (one movable anchor target per group)
    local soundPrev    = {}
    local soundSeeded  = false
    local cdFonts      = {}      -- per-spell CreateFont for the native countdown
    local placeholderPool   = {}
    local placeholderActive = {}
    local PLACEHOLDER_ALPHA = 0.35
    -- Frames THIS engine has pinned (nf -> true), so a disabled/inert engine never touches a native
    -- the OLD CDMAnchor bucket system owns. Unlike BuffGroups (whose buff viewer the old system never
    -- manages), the Essential natives are shared, so we only ever release / restyle frames WE pinned.
    local pinnedFrames = {}

    -- ── The live viewer + enumerator (Essential-specific; EnumBuffIcons is buff-only) ──
    local function Viewer() return viewerName and _G[viewerName] or nil end

    -- The DISPLAY spell id of a native cooldown item frame (overrideTooltipSpellID > overrideSpellID >
    -- spellID), via the shared CDMAnchor resolver, then the frame's own getters / cooldownInfo.
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
    I.FrameSpellId = FrameSpellId

    -- Enumerate the dest's native item frames (the pool's ACTIVE frames; like CDMAnchor.EnumBuffIcons
    -- but for THIS viewer). Returns every active pool frame regardless of IsShown — a not-currently-up
    -- cooldown's frame is shown=false but still needs positioning; the caller resolves the spell id.
    local function EnumNativeFrames()
        local v = Viewer()
        if not v then return {} end
        local out = {}
        local pool = v.itemFramePool
        if pool and pool.EnumerateActive then
            for f in pool:EnumerateActive() do
                if f then out[#out + 1] = f end
            end
        end
        if #out == 0 then
            for _, c in ipairs({ v:GetChildren() }) do
                if c and (c.cooldownInfo or c.GetCooldownInfo or c.GetSpellID) then out[#out + 1] = c end
            end
        end
        return out
    end
    I.EnumNativeFrames = EnumNativeFrames

    -- ── DISPLAYED set = the viewer's POOL (the SOURCE OF TRUTH, mirroring BuffGroups) ──
    -- The category set (GetCooldownViewerCategorySet) is the WRONG source: a live diagnostic showed it
    -- does NOT match what the viewer displays (missing the defensives, leaking not-displayed spells).
    -- The real displayed set is the viewer's itemFramePool active frames — exactly the source
    -- BuffGroups uses for its buff viewer. We resolve each pool frame to its DISPLAY spellId via the
    -- shared FrameSpellId (overrideTooltipSpellID > overrideSpellID > spellID). displayedCache /
    -- displayedKnown mirror BuffGroups; refreshed from the engine's OnUpdate ticker + the viewer
    -- relayout hook, run even while the engine is disabled so the default classification is correct the
    -- instant the user enables it.
    local displayedCache = {}
    local displayedKnown = false

    -- The pool's deduped DISPLAY spellIds + the pool's active-frame count. Reads are guarded (the spell
    -- ids can be secret values in combat; FrameSpellId already drops those). Returns the spellIds in
    -- enumeration order (NativeOrder sorts by layoutIndex for on-screen order) and the raw count so a
    -- transient EMPTY pool (login / spec change before Blizzard rebuilds it) can be told from "nothing
    -- displayed" and DEFERRED rather than clobbering a known cache — matching BuffGroups' poolCount == 0
    -- defer.
    local function CollectDisplayed()
        local out, seen, count = {}, {}, 0
        for _, nf in ipairs(EnumNativeFrames()) do
            count = count + 1
            local sid = FrameSpellId(nf)
            if sid and not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
        end
        return out, count
    end

    -- Recompute the displayed set straight into displayedCache from the POOL, set displayedKnown, and
    -- return true if the set CHANGED vs the previous (cheap diff: count + keys) so the ticker can notify
    -- the config (onDisplayedChanged) only on a real change. An EMPTY pool right after a spec change /
    -- login usually means Blizzard hasn't rebuilt it yet — don't clobber the known set with an empty one
    -- (matches BuffGroups' defer on poolCount == 0); leave the cache untouched and report no change.
    function I.RefreshDisplayedCache()
        local displayed, poolCount = CollectDisplayed()
        if poolCount == 0 then return false end
        local newSet, newCount = {}, 0
        for _, sid in ipairs(displayed) do
            if not newSet[sid] then newSet[sid] = true; newCount = newCount + 1 end
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

    -- Optional callback the config UI registers (nil-safe). Fired by the ticker ONLY when the DISPLAYED
    -- set actually changes (I.RefreshDisplayedCache's diff), so the strip's red flags / tooltips
    -- re-evaluate after the user edits the CDM tracked cooldowns in EditMode.
    I.onDisplayedChanged = nil

    -- True once the displayed cache has been populated at least once (so GroupOf / the red flag can
    -- avoid acting before the first refresh).
    function I.DisplayedKnown() return displayedKnown end

    -- Is `sid` in the viewer's DISPLAYED pool? An unassigned cooldown that IS displayed defaults to
    -- Group 1; one that is NOT defaults to Unused (the config flags it red in a real group). Before the
    -- cache is known nothing is "not displayed". A TRACKER member key (addon frame) is always treated
    -- as displayed — it's an addon-drawn icon whose own module controls visibility, never a pool entry.
    function I.IsDisplayed(sid)
        if I.IsTracker and I.IsTracker(sid) then return true end
        return displayedCache[sid] == true
    end

    -- Can `sid` ever show in a real group? A CUSTOM (addon-drawn) cooldown always can; a TRACKER member
    -- (addon frame) always can; a native one only if it's in the displayed pool. The config strip's red
    -- "Not displayed" flag uses this so a custom / tracker icon is never flagged. Mirrors BuffGroups.
    function I.IsDisplayable(sid)
        if I.IsTracker and I.IsTracker(sid) then return true end
        return I.IsCustom(sid) or displayedCache[sid] == true
    end

    -- ── Addon-tracker MEMBERS (BL Tracker, Trinket, …) folded in as full group members ──
    -- A tracker is an addon-drawn icon frame that opted into the CDM with cdmDest == THIS dest. The
    -- groups engine OWNS this dest (CDMGroups.OwnsDest), so instead of letting the old CDMAnchor bucket
    -- system free-place these icons, we make each a full group MEMBER keyed by its frame's global NAME
    -- (a STRING — the same DescId the reorder map uses). The data model (Config.lua) already accepts
    -- string keys alongside native spellId numbers. The engine never Show/Hides a tracker (the module
    -- owns that) — it only SetPoints/SIZES the frame when shown (RefreshLayout) and keeps the tracker
    -- key in the universe so the config strip renders a draggable tile with the pencil.
    --   I.TrackerMembers() -> { { key=name, frame, getIcon, setSize, getCfg }, ... } for THIS dest.
    --   trackerKeys / IsTracker(key) -> a name->descriptor map, refreshed each TrackerMembers() call.
    -- CACHED so AllBuffs (called per group, per 0.2s tick, and per drag frame) doesn't rebuild the list
    -- on every call. Rebuilt at most ~5x/sec; a just-registered tracker / dest change is picked up within
    -- 0.2s. The returned table is READ-ONLY to callers (they only iterate it). Avoids the per-lookup
    -- allocation churn this addon has fought before.
    local trackerKeys, trackerList, trackerBuiltAt = {}, {}, -1
    function I.TrackerMembers(force)
        local now = (GetTime and GetTime()) or 0
        if not force and trackerBuiltAt >= 0 and (now - trackerBuiltAt) < 0.2 then return trackerList end
        wipe(trackerKeys); wipe(trackerList)
        trackerBuiltAt = now
        if not (ns.CDMAnchor and ns.CDMAnchor.GetIconDescriptors) then return trackerList end
        for _, td in ipairs(ns.CDMAnchor.GetIconDescriptors(dest)) do
            if td.name then
                td.key = td.name          -- the member key (the design's { key=name, ... } shape)
                trackerKeys[td.name] = td
                trackerList[#trackerList + 1] = td
            end
        end
        return trackerList
    end

    -- Is `key` an addon-tracker member of THIS dest? A tracker key is ALWAYS a string (the frame name);
    -- a native/custom key is a number — short-circuit those so a native-cooldown lookup never rebuilds
    -- the tracker list. Used by Config.GroupOf (default to Group 1, never the red flag) + the strip.
    function I.IsTracker(key)
        if type(key) ~= "string" then return false end
        if trackerKeys[key] then return true end
        I.TrackerMembers()
        return trackerKeys[key] ~= nil
    end

    -- The descriptor for a tracker member key (nil for a native/custom = a number key). Refreshes lazily.
    function I.TrackerDesc(key)
        if type(key) ~= "string" then return nil end
        if trackerKeys[key] then return trackerKeys[key] end
        I.TrackerMembers()
        return trackerKeys[key]
    end

    -- All cooldowns the config knows about: the displayed (pool) set UNION any explicitly-assigned
    -- spellId in the store (so a manual assignment persists even if a cooldown momentarily leaves the
    -- pool) UNION customs (none this phase) UNION the addon-tracker member keys (strings) for this
    -- dest. Mirrors BuffGroups' "displayed ∪ assigned ∪ custom". The displayed set comes first, in pool
    -- enumeration order; GetGroupBuffs re-ranks Group 1 by NativeOrder (natives first, then trackers).
    function I.AllBuffs()
        local out, seen = CollectDisplayed(), {}
        for _, sid in ipairs(out) do seen[sid] = true end
        local s = I.Store and I.Store()
        if s and type(s.assign) == "table" then
            for sid, gid in pairs(s.assign) do
                if gid ~= nil and not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
            end
        end
        for _, sid in ipairs(I.CustomList()) do
            if not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
        end
        for _, td in ipairs(I.TrackerMembers()) do
            if not seen[td.key or td.name] then seen[td.key or td.name] = true; out[#out + 1] = td.name end
        end
        return out
    end
    -- Public icon/name resolvers used by the config strip + the pencil editor. A NUMBER key is a
    -- native/custom spellId (resolve via C_Spell). A STRING key is an addon-TRACKER member: there is no
    -- spell to resolve, so fall back to the tracker descriptor's getIcon() for the tile texture, and use
    -- the frame name as the display name (the config skips the spell tooltip for trackers anyway).
    function I.SpellTexture(key)
        if type(key) == "string" then
            local td = I.TrackerDesc(key)
            local tex = td and td.getIcon and td.getIcon()
            return tex or FALLBACK_ICON
        end
        return SpellTexture(key)
    end
    function I.SpellName(key)
        if type(key) == "string" then return key end
        return SpellName(key)
    end

    -- ── Native on-screen order (the EditMode arrangement), via layoutIndex (guarded) ──
    local function FrameLayoutIndex(nf)
        local li = nf and nf.layoutIndex
        if type(li) ~= "number" then return nil end
        if issecretvalue(li) or not canaccessvalue(li) then return nil end
        return li
    end

    function I.NativeOrder()
        local v = Viewer()
        if not (v and v.itemFramePool and v.itemFramePool.EnumerateActive) then return nil end
        local entries, n = {}, 0
        for f in v.itemFramePool:EnumerateActive() do
            local sid = FrameSpellId(f)
            if sid then
                n = n + 1
                entries[n] = { sid = sid, li = FrameLayoutIndex(f) or math.huge, seq = n }
            end
        end
        if n == 0 then return nil end
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

    -- Re-sort ONE group's saved order so its members follow NativeOrder() (members missing from it
    -- keep their relative order at the end), then RE-CHUNK into rows of the group's maxPerRow.
    -- Reorders within the group only; writes the explicit-row store.
    function I.SortGroupNativeOrder(groupId)
        local members = I.GetGroupBuffs(groupId)
        if #members == 0 then return end
        local nativeRank, rank = {}, 0
        for _, sid in ipairs(I.NativeOrder() or {}) do
            if nativeRank[sid] == nil then rank = rank + 1; nativeRank[sid] = rank end
        end
        local ordered = {}
        for i, sid in ipairs(members) do
            ordered[#ordered + 1] = { sid = sid, idx = i, rank = nativeRank[sid] or math.huge }
        end
        table.sort(ordered, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.idx < b.idx
        end)
        local per = I.MaxPerRow(groupId)
        local rows, row = {}, {}
        for _, e in ipairs(ordered) do
            if #row >= per then rows[#rows + 1] = row; row = {} end
            row[#row + 1] = e.sid
        end
        if #row > 0 then rows[#rows + 1] = row end
        local s = I.Store and I.Store()
        if s then s.order = s.order or {}; s.order[groupId] = rows end
    end

    -- ── Per-spell CreateFont objects for the native countdown ──────────────────
    local function CountdownFont(spellId)
        local name = "UnbunkUtilityCDG_" .. dest .. "_Timer_" .. spellId
        local f = cdFonts[spellId] or _G[name] or CreateFont(name)
        cdFonts[spellId] = f
        return f, name
    end

    -- Remaining seconds on a native frame's Cooldown (guarded; nil on any secret/failure).
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

    local function FrameShown(nf)
        if not nf then return false end
        local ok, s = pcall(nf.IsShown, nf)
        return ok and s and true or false
    end

    -- ── Group containers (anchor target only — native frames are NOT reparented) ──
    local function GetContainer(groupId)
        if containers[groupId] then return containers[groupId] end
        local f = CreateFrame("Frame", "UnbunkUtilityCDG_" .. dest .. "_Group" .. groupId, UIParent, "BackdropTemplate")
        f:SetSize(1, 1)
        f:SetFrameStrata("MEDIUM")
        f:SetClampedToScreen(true)
        if f.SetPreventSecretValues then f:SetPreventSecretValues(true) end
        containers[groupId] = f
        return f
    end
    I.GetContainer = GetContainer

    -- ── Container placement (anchorTo + relPos + posX/posY) ─────────────────────
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
        local anchorTo = g.anchorTo or dest
        -- Screen-center: CENTER-to-CENTER of UIParent; posX/posY then offset from screen center
        -- (relPos is irrelevant here — the config hides the Placement dropdown for this anchor).
        if anchorTo == "screen" then return "CENTER", UIParent, "CENTER" end
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

    -- ── Native-frame restyle (the recipe's RESIZE + RESTYLE pass) ───────────────
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

    local function AnchorTimerFS(fs, nf, pos, ox, oy)
        if not (fs and fs.SetPoint and ns.AnchorFS) then return end
        pcall(ns.AnchorFS, fs, nf, pos or "CENTER", ox, oy)
    end

    local function ReanchorStack(appl)
        local nf, sid = appl._uuStackNF, appl._uuStackSid
        if not (nf and sid and ns.AnchorFS) then return end
        appl._uuReanchoring = true
        pcall(ns.AnchorFS, appl, nf, I.IconGet(sid, "stackPos") or "BOTTOMRIGHT",
            I.IconGet(sid, "stackOffX"), I.IconGet(sid, "stackOffY"))
        appl._uuReanchoring = false
    end

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

    local function FrameTitle(nf)
        if nf.Title then return nf.Title end
        local fs = nf:CreateFontString(nil, "OVERLAY", nil, 7)
        nf.Title = fs
        return fs
    end

    local function ApplyBorder(nf, spellId)
        if not ns.CDMAnchor or not ns.CDMAnchor.ApplyFrameBorder then return end
        local enabled = I.IconGet(spellId, "borderEnabled") ~= false
        ns.CDMAnchor.ApplyFrameBorder(nf, enabled,
            I.IconGet(spellId, "borderColor"), I.IconGet(spellId, "borderSize") or 1, true)
    end

    -- ── Glow: a marching-dots overlay (self-drawn) ──────────────────────────────
    local function EnsureGlow(nf)
        if nf._uuCdgGlow then return nf._uuCdgGlow end
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
        nf._uuCdgGlow = glow
        return glow
    end

    local function ApplyGlow(nf, spellId)
        local enabled = I.IconGet(spellId, "glowEnabled") == true
        local alert = nf.SpellActivationAlert
        if alert and alert.Hide then alert:Hide(); if alert.SetAlpha then alert:SetAlpha(0) end end
        if not enabled then
            if nf._uuCdgGlow then nf._uuCdgGlow:Hide() end
            return
        end
        local glow = EnsureGlow(nf)
        local c = I.IconGet(spellId, "glowColor") or { r = 1, g = 1, b = 1, a = 1 }
        for _, dot in ipairs(glow.dots) do dot:SetColorTexture(c.r, c.g, c.b, c.a or 1) end
        glow:Show()
    end

    -- Resize + restyle a native frame: SetSize -> refix .Icon -> countdown font -> text regions ->
    -- stacks -> title -> border -> glow. Every native read is guarded.
    local function StyleFrame(nf, spellId)
        local iconW = I.IconGet(spellId, "iconW") or 44
        local iconH = I.IconGet(spellId, "iconH") or 44

        nf:SetSize(iconW, iconH)
        local tex = nf.Icon
        local hasTex = tex ~= nil and (type(tex) ~= "number" or canaccessvalue(tex))
        if hasTex and tex.SetTexCoord then
            tex:ClearAllPoints()
            tex:SetAllPoints(nf)
            tex:SetTexCoord(IconTexCoord(iconW, iconH))
        end

        local showTimer = I.IconGet(spellId, "showTimer") ~= false
        local fontPath  = ns.ResolveFontPath(I.IconGet(spellId, "timerFontPath"), I.IconGet(spellId, "timerFontKey"))
        local fontSize  = I.IconGet(spellId, "timerFontSize") or 14
        local outline   = I.IconGet(spellId, "timerOutline") or "OUTLINE"
        local timerColor = I.IconGet(spellId, "timerColor")
        local timerPos  = I.IconGet(spellId, "timerPos") or "CENTER"
        local timerOffX = I.IconGet(spellId, "timerOffX")
        local timerOffY = I.IconGet(spellId, "timerOffY")

        local effSize, effColor = fontSize, timerColor
        if I.IconGet(spellId, "timerThresholdsEnabled") then
            local remaining = FrameRemaining(nf)
            local tier = MatchThreshold(I.IconGet(spellId, "timerThresholds") or I.DEFAULT_TIMER_THRESHOLDS, remaining)
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

        local showStack = I.IconGet(spellId, "showStack") ~= false
        local appl = nf.Applications and nf.Applications.Applications
        if appl then
            if showStack then
                local sPath = ns.ResolveFontPath(I.IconGet(spellId, "stackFontPath"), I.IconGet(spellId, "stackFontKey"))
                appl:SetIgnoreParentScale(true)
                appl:SetFont(sPath, I.IconGet(spellId, "stackFontSize") or 10, I.IconGet(spellId, "stackOutline") or "OUTLINE")
                local sc = I.IconGet(spellId, "stackColor") or { r = 1, g = 1, b = 1, a = 1 }
                appl:SetTextColor(sc.r, sc.g, sc.b, sc.a or 1)
                appl:SetDrawLayer("OVERLAY", 7)
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

        local showTitle = I.IconGet(spellId, "showTitle") == true
        local titleFS = FrameTitle(nf)
        if showTitle then
            titleFS:SetFont(ns.ResolveFontPath(I.IconGet(spellId, "titleFontPath"), I.IconGet(spellId, "titleFontKey")),
                I.IconGet(spellId, "titleFontSize") or 12, I.IconGet(spellId, "titleOutline") or "OUTLINE")
            local tc = I.IconGet(spellId, "titleColor") or { r = 1, g = 1, b = 1, a = 1 }
            titleFS:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
            titleFS:SetDrawLayer("OVERLAY", 7)
            ns.AnchorFS(titleFS, nf, I.IconGet(spellId, "titlePos") or "TOP",
                I.IconGet(spellId, "titleOffX"), I.IconGet(spellId, "titleOffY"))
            titleFS:SetText(I.IconGet(spellId, "titleText") or "")
            titleFS:Show()
        else
            titleFS:Hide()
        end

        ApplyBorder(nf, spellId)
        ApplyGlow(nf, spellId)
    end

    -- Pin a native frame (and remember we own it) via the shared CDMAnchor re-impose hook.
    local function PinNative(nf, anchor, x, y, w, h)
        if ns.CDMAnchor and ns.CDMAnchor.PinNativeTo then
            ns.CDMAnchor.PinNativeTo(nf, anchor, x, y, w, h)
            pinnedFrames[nf] = true
        end
    end

    -- Release a native we pinned: drop our pin + our added visuals, and forget it. Never called on a
    -- frame we didn't pin (so the OLD bucket system's pins on Essential natives are untouched).
    local function ReleaseNative(nf)
        if ns.CDMAnchor and ns.CDMAnchor.ReleaseNativePin then ns.CDMAnchor.ReleaseNativePin(nf) end
        if nf._uuCdgGlow then nf._uuCdgGlow:Hide() end
        if nf.Title then nf.Title:Hide() end
        pinnedFrames[nf] = nil
    end

    -- ── Placeholder frames (per-icon "Show placeholder") ────────────────────────
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
        if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then
            local enabled = I.IconGet(spellId, "borderEnabled") ~= false
            ns.CDMAnchor.ApplyFrameBorder(f, enabled,
                I.IconGet(spellId, "borderColor"), I.IconGet(spellId, "borderSize") or 1, true)
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

    -- Restore the native viewer after we release our pins (M1). ReleaseNativePin only drops OUR
    -- offset — a member we'd pinned offscreen (Unused, ~-10000) or into a container stays where it
    -- was until Blizzard next relayouts the viewer. So when we disable, ask the viewer to relayout
    -- itself: out of combat call its RefreshLayout() to snap every frame back to its native slot
    -- immediately; in combat the viewer's relayout is unsafe (protected), so defer to a one-shot
    -- PLAYER_REGEN_ENABLED. ReleaseViewer (the OLD CDMAnchor takeover) likewise bails in combat, so
    -- this is the same deferral contract — disabling cleanly returns the viewer to the old system
    -- without leaving frames hidden/offscreen.
    local restorePending = false
    local restoreEv
    local function RestoreNativeViewer()
        local v = Viewer()
        if not (v and v.RefreshLayout) then return end
        if InCombatLockdown and InCombatLockdown() then
            if not restorePending then
                restorePending = true
                restoreEv = restoreEv or CreateFrame("Frame")
                restoreEv:RegisterEvent("PLAYER_REGEN_ENABLED")
                restoreEv:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    restorePending = false
                    if not I.Enabled() then RestoreNativeViewer() end
                end)
            end
            return
        end
        pcall(v.RefreshLayout, v)
    end
    I.RestoreNativeViewer = RestoreNativeViewer

    -- Release ONLY the natives WE pinned (so a disabled engine, or one that's just been toggled off,
    -- never clears the OLD bucket system's pins on shared Essential frames), hide our placeholders +
    -- containers. Collect first so we don't mutate pinnedFrames while iterating. If we actually
    -- released any native, restore the viewer (M1) so nothing is stranded offscreen.
    local function HideAll()
        local toRelease
        for nf in pairs(pinnedFrames) do
            toRelease = toRelease or {}
            toRelease[#toRelease + 1] = nf
        end
        if toRelease then for _, nf in ipairs(toRelease) do ReleaseNative(nf) end end
        if I.HideInactiveCustomFrames then I.HideInactiveCustomFrames() end
        for sid in pairs(placeholderActive) do ReleasePlaceholder(sid) end
        for _, c in pairs(containers) do c:Hide() end
        -- Only heal the viewer when we had pins to drop — avoids hammering the native RefreshLayout
        -- every 0.2s tick while the engine sits disabled (HideAll runs from RefreshLayout's
        -- disabled-early-return on each tick, but pinnedFrames is empty after the first pass).
        if toRelease then RestoreNativeViewer() end
    end
    I.HideAll = HideAll

    -- ── Per-icon start/stop sound alerts (off the active transition) ────────────
    local function PlayIconSound(spellId, pathKey, soundKey)
        local path = I.IconGet(spellId, pathKey)
        if path then PlaySoundFile(path, "Master"); return end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if not LSM then return end
        local key = I.IconGet(spellId, soundKey)
        local resolved = key and LSM:Fetch("sound", key)
        if resolved then PlaySoundFile(resolved, "Master") end
    end

    local function UpdateSounds(activeOf)
        local s = I.Store and I.Store()
        local iconCfg = s and s.iconCfg
        if type(iconCfg) ~= "table" then return end
        for spellId, ic in pairs(iconCfg) do
            if type(ic) == "table" and (ic.soundStartEnabled or ic.soundStopEnabled) then
                local active = activeOf[spellId] == true
                if soundSeeded and active ~= soundPrev[spellId] then
                    if active then
                        if I.IconGet(spellId, "soundStartEnabled") then
                            pcall(PlayIconSound, spellId, "soundStartPath", "soundStartSound")
                        end
                    else
                        if I.IconGet(spellId, "soundStopEnabled") then
                            pcall(PlayIconSound, spellId, "soundStopPath", "soundStopSound")
                        end
                    end
                end
                soundPrev[spellId] = active
            end
        end
        soundSeeded = true
    end

    -- ── Public refresh / layout ─────────────────────────────────────────────────
    local OFFSCREEN = -10000
    local HORIZONTAL_GROW = { RIGHT = true, LEFT = true, CENTER_H = true }
    local function IsHorizontal(grow) return grow == nil or HORIZONTAL_GROW[grow] or false end

    function I.RefreshLayout()
        if not I.Enabled() then
            HideAll()
            return
        end

        -- Build spellId -> native frame (the live pool) and spellId -> active(shown) for sounds.
        local frameOf, activeOf = {}, {}
        for _, nf in ipairs(EnumNativeFrames()) do
            local sid = FrameSpellId(nf)
            if sid then
                frameOf[sid] = nf
                if FrameShown(nf) then activeOf[sid] = true end
            end
        end
        -- Fold the active CUSTOM (addon-drawn) cooldown frames in alongside the natives. A custom frame
        -- carries .isCustomBuff/.Icon/.Cooldown/.Title/.Stack so StyleFrame treats it uniformly; it's
        -- only ever present while ACTIVE, so each is also "active" for the sound transition.
        if I.EnumActiveCustomFrames then
            for sid, f in pairs(I.EnumActiveCustomFrames()) do
                frameOf[sid] = f
                activeOf[sid] = true
            end
        end
        -- Fold the addon-TRACKER frames (BL Tracker, Trinket, …) keyed by their global NAME (string).
        -- A tracker is its module's own frame: the engine NEVER Show/Hides it — it only positions +
        -- sizes it WHEN SHOWN. So a tracker counts as ACTIVE for reflow only while frame:IsShown()
        -- (mirrors a native whose pool frame is absent → it simply takes no slot when hidden). We
        -- record it in trackerOf so the placement branches treat it as a tracker (SetPoint + setSize,
        -- NO StyleFrame / PinNative / border / placeholder — a tracker keeps its own look).
        local trackerOf = {}
        for _, td in ipairs(I.TrackerMembers()) do
            local f = td.frame
            trackerOf[td.name] = td
            local shown = false
            if f and f.IsShown then local ok, s = pcall(f.IsShown, f); shown = ok and s and true or false end
            if shown then
                frameOf[td.name] = f
                activeOf[td.name] = true
            end
        end
        UpdateSounds(activeOf)

        -- Hide containers of deleted groups.
        for gid, c in pairs(containers) do
            if not I.GetGroup(gid) then c:Hide() end
        end

        -- Unused (group 0) + frames whose group was deleted: a native is pinned offscreen so the
        -- viewer's relayout can't reveal it in place (native item frames aren't protected → taint-free);
        -- a custom (addon-drawn) frame is just hidden.
        local placed = {}
        local placeholderNeeded = {}
        for _, sid in ipairs(I.GetGroupBuffs(0)) do
            local nf = frameOf[sid]
            if trackerOf[sid] then
                -- A TRACKER parked in Unused: the engine never hides it (its module owns visibility +
                -- the defer in TimerIcon/BResTracker now early-returns out of free placement when this
                -- dest is owned, so the tracker isn't re-anchored elsewhere either). Just mark it placed
                -- so the release pass below doesn't try to touch it; leave the frame exactly as-is.
                placed[sid] = true
            elseif nf then
                placed[sid] = true
                if nf.isCustomBuff then
                    nf:Hide()
                else
                    if nf.Title then nf.Title:Hide() end
                    if nf._uuCdgGlow then nf._uuCdgGlow:Hide() end
                    if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then ns.CDMAnchor.ApplyFrameBorder(nf, false) end
                    PinNative(nf, UIParent, OFFSCREEN, OFFSCREEN)
                end
            end
        end

        -- Pack each existing group's members into its positioned container.
        for _, g in ipairs(I.GroupList()) do
            local container = GetContainer(g.id)
            if not g.unlocked then PositionContainer(g, container) end

            local groupRows = I.GroupRows(g.id)
            local spacing = g.spacing or 1
            local grow    = g.growDir or "CENTER_H"
            local horizontal = IsHorizontal(grow)
            local reverse = (grow == "LEFT" or grow == "UP")
            local rp = g.relPos or "above"
            local alignTop = (rp == "below" or rp == "bottomleft" or rp == "bottomright")

            -- Default (reflow): a row lays out only members with a LIVE frame present in the pool (or an
            -- active custom). Static Display: every member takes a slot (an absent member reserves its
            -- slot but pins nothing). A per-icon `placeholder` member always reserves its slot and draws
            -- a dim ghost while absent. Build, per ROW, the laid-out members + their sizes, the row's
            -- MAIN extent (packed along the grow axis) and its CROSS extent (max icon size across the axis).
            local staticDisplay = g.staticDisplay == true
            local sizes = {}
            local laidRows = {}     -- { { members = {sid,...}, mainExt, crossExt }, ... }
            local count = 0
            for _, srcRow in ipairs(groupRows) do
                local rowMembers = {}
                for _, sid in ipairs(srcRow) do
                    if staticDisplay or frameOf[sid] or I.IconGet(sid, "placeholder") == true then
                        rowMembers[#rowMembers + 1] = sid
                        sizes[sid] = { w = I.IconGet(sid, "iconW") or 44, h = I.IconGet(sid, "iconH") or 44 }
                    end
                end
                local mainExt, crossExt = 0, 0
                for i, sid in ipairs(rowMembers) do
                    local sz = sizes[sid]
                    local main  = horizontal and sz.w or sz.h
                    local cross = horizontal and sz.h or sz.w
                    mainExt = mainExt + main + (i > 1 and spacing or 0)
                    if cross > crossExt then crossExt = cross end
                end
                count = count + #rowMembers
                -- An EMPTY row contributes NO height (skip it entirely from the layout extent + stack).
                if #rowMembers > 0 then
                    laidRows[#laidRows + 1] = { members = rowMembers, mainExt = mainExt, crossExt = crossExt }
                end
            end

            -- Box: MAIN axis = the widest row's main extent; CROSS axis = the sum of row cross extents
            -- (+ spacing between rows). The container is CENTER-anchored to the target, so sizing it to
            -- the whole block lets CENTER_H/CENTER_V centre the block as a unit.
            local maxMain, sumCross = 0, 0
            for i, lr in ipairs(laidRows) do
                if lr.mainExt > maxMain then maxMain = lr.mainExt end
                sumCross = sumCross + lr.crossExt + (i > 1 and spacing or 0)
            end
            if count == 0 then maxMain, sumCross = (g.iconW or 44), (g.iconH or 44) end
            local boxW = horizontal and maxMain or sumCross
            local boxH = horizontal and sumCross or maxMain
            container:SetSize(math.max(1, boxW), math.max(1, boxH))

            -- Stack successive rows along the CROSS axis: horizontal grow stacks DOWN (y negative);
            -- vertical grow stacks RIGHT (x positive). Within a row, pack along the MAIN axis (reversed
            -- for LEFT/UP). The per-row cross alignment matches the single-row alignTop rule.
            local crossCursor = 0
            for _, lr in ipairs(laidRows) do
                local mainCursor = reverse and lr.mainExt or 0
                for _, sid in ipairs(lr.members) do
                    local nf = frameOf[sid]
                    local sz = sizes[sid]
                    local main = horizontal and sz.w or sz.h
                    if reverse then mainCursor = mainCursor - main end
                    local x, y
                    if horizontal then
                        local crossOff = alignTop and 0 or -(lr.crossExt - sz.h)
                        x = mainCursor
                        y = -(crossCursor) + crossOff
                    else
                        local crossOff = alignTop and 0 or (lr.crossExt - sz.w)
                        x = crossCursor + crossOff
                        y = -mainCursor
                    end
                    local td = trackerOf[sid]
                    if td then
                        -- TRACKER member: position + SIZE it like a custom frame, but DON'T StyleFrame it
                        -- (no timer/border/stack restyle — a tracker keeps its own look), DON'T PinNative
                        -- it, and DON'T Show/Hide it (its module owns that). It's in frameOf (nf) only when
                        -- already shown; place the shown frame into its slot. Under Static Display a hidden
                        -- tracker (nf nil) still RESERVES its slot but positions nothing (like an absent
                        -- native), so the grid doesn't collapse when the tracker is down.
                        placed[sid] = true
                        if nf then
                            nf:ClearAllPoints()
                            nf:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
                            if td.setSize then td.setSize(sz.w, sz.h) else nf:SetSize(sz.w, sz.h) end
                        end
                    elseif nf then
                        placed[sid] = true
                        StyleFrame(nf, sid)
                        if nf.isCustomBuff then
                            nf:ClearAllPoints()
                            nf:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
                            nf:SetSize(sz.w, sz.h)
                            nf:Show()
                        else
                            PinNative(nf, container, x, y, sz.w, sz.h)
                        end
                        -- A `placeholder` NATIVE whose pool frame is present but NOT shown (cooldown not
                        -- currently up) gets a ghost over its slot; cleared when it shows. Customs never want one.
                        if not nf.isCustomBuff and I.IconGet(sid, "placeholder") == true and not FrameShown(nf) then
                            placeholderNeeded[sid] = true
                            ShowPlaceholderAt(sid, container, x, y, sz.w, sz.h)
                        end
                    elseif I.IconGet(sid, "placeholder") == true then
                        placeholderNeeded[sid] = true
                        ShowPlaceholderAt(sid, container, x, y, sz.w, sz.h)
                    end
                    if reverse then mainCursor = mainCursor - spacing else mainCursor = mainCursor + main + spacing end
                end
                crossCursor = crossCursor + lr.crossExt + spacing
            end

            container:SetShown(count > 0 or g.unlocked)
        end

        -- Any frame WE previously pinned that isn't placed this pass is released (it dropped from the
        -- pool / moved to a deleted group). Guarded to frames we own so the old system's pins are safe.
        local toReleaseNF
        for nf in pairs(pinnedFrames) do
            local sid = FrameSpellId(nf)
            if not (sid and placed[sid]) then
                toReleaseNF = toReleaseNF or {}
                toReleaseNF[#toReleaseNF + 1] = nf
            end
        end
        if toReleaseNF then for _, nf in ipairs(toReleaseNF) do ReleaseNative(nf) end end

        local toRelease
        for sid in pairs(placeholderActive) do
            if not placeholderNeeded[sid] then
                toRelease = toRelease or {}
                toRelease[#toRelease + 1] = sid
            end
        end
        if toRelease then for _, sid in ipairs(toRelease) do ReleasePlaceholder(sid) end end
    end
    I.ApplyAll = I.RefreshLayout

    function I.Rebuild()
        for gid, c in pairs(containers) do
            if not I.GetGroup(gid) then c:Hide() end
        end
        I.RefreshLayout()
    end

    -- ── Per-group unlock / drag ─────────────────────────────────────────────────
    I.pe = I.pe or {}

    function I.IsGroupUnlocked(groupId)
        local c = containers[groupId]
        return c and c:IsMovable() and c:IsMouseEnabled() or false
    end

    function I.SetGroupUnlocked(groupId, val)
        local g = I.GetGroup(groupId); if not g then return end
        local c = GetContainer(groupId)
        if val then
            g.unlocked = true
            PositionContainer(g, c)
            c:SetSize(math.max(g.iconW or 44, 32), math.max(g.iconH or 44, 32))
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
                I.GSet(groupId, "posX", x)
                I.GSet(groupId, "posY", y)
                self:ClearAllPoints()
                self:SetPoint(selfPt, rel, relPt, x, y)
                if I.pe and I.pe[groupId] then I.pe[groupId].Refresh() end
            end)
            c:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
            if ns.SetBrandBorder then ns.SetBrandBorder(c, 0.8) end
            c:Show()
        else
            g.unlocked = false
            c:SetMovable(false); c:EnableMouse(false)
            c:SetScript("OnDragStart", nil); c:SetScript("OnDragStop", nil)
            c:SetBackdrop(nil)
            I.RefreshLayout()
        end
    end

    -- ── Coalesced relayout (H2) ─────────────────────────────────────────────────
    -- The Essential viewer fires RefreshLayout EVERY FRAME during a cooldown-swipe animation (the
    -- Buff viewer never does). Calling I.RefreshLayout() synchronously from that hook re-pinned +
    -- re-styled every native at ~60 Hz — the exact 200-300 KB/s allocation storm CDMAnchor.RefreshAll
    -- already kills via REFRESH_THROTTLE coalescing. Mirror that: debounce so a real relayout runs at
    -- most ~10 Hz. Route the per-frame viewer hook (and any high-frequency caller) through this; the
    -- 0.2s state ticker below stays a direct RefreshLayout (already coarse).
    local relayoutScheduled = false
    local RELAYOUT_THROTTLE = 0.1
    local function ScheduleRelayout()
        if relayoutScheduled then return end
        relayoutScheduled = true
        C_Timer.After(RELAYOUT_THROTTLE, function()
            relayoutScheduled = false
            -- Refresh the displayed cache HERE (a fresh, untainted timer execution) rather than in the
            -- RefreshLayout hook — reading secret cooldownInfo inside that hook taints Blizzard's RefreshData.
            if I.RefreshDisplayedCache() and I.onDisplayedChanged then I.onDisplayedChanged() end
            if not I.Enabled() then return end
            I.RefreshLayout()
        end)
    end
    I.ScheduleRelayout = ScheduleRelayout

    -- ── Re-impose on the native viewer's relayout + a light ticker ──────────────
    local refreshHooked = false
    local function HookNativeViewer()
        if refreshHooked then return end
        local v = Viewer()
        if not v or not v.RefreshLayout then return end
        refreshHooked = true
        hooksecurefunc(v, "RefreshLayout", function()
            -- CRITICAL: this hook runs INSIDE Blizzard's CooldownViewer:RefreshData (which calls
            -- RefreshLayout, then refreshes aura/totem data with secret comparisons). Reading the pool's
            -- secret cooldownInfo HERE taints that secure execution → Blizzard's own aura/totem compares
            -- then error ("tainted by UnbunkUtility"). So do NOTHING secret here: just schedule a DEFERRED
            -- relayout (a fresh, untainted C_Timer execution, which also refreshes the displayed cache).
            -- The 0.2s ticker refreshes the cache in its own clean context even while disabled.
            if I.Enabled() then ScheduleRelayout() end
        end)
        -- Lock the viewer scale to 1 so native offsets match our coordinate space.
        if v.SetScale and not v._uuCdgScaleHooked then
            v._uuCdgScaleHooked = true
            hooksecurefunc(v, "SetScale", function(self, s)
                if (s or 1) ~= 1 and I.Enabled() then self:SetScale(1) end
            end)
        end
    end
    I.HookNativeViewer = HookNativeViewer

    -- ── Events ──────────────────────────────────────────────────────────────────
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterUnitEvent("UNIT_AURA", "player")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        HookNativeViewer()
        if I.Enabled() then I.RefreshLayout() end
    end)

    local accum = 0
    ev:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 0.2 then return end
        accum = accum - 0.2
        -- Keep the displayed-set cache fresh from the pool (catches EditMode tracked-cooldown edits /
        -- spec change) even while the engine is disabled, so GroupOf's unassigned default + the red flag
        -- stay correct the moment the user enables it; notify the config only on an actual change.
        if I.RefreshDisplayedCache() and I.onDisplayedChanged then I.onDisplayedChanged() end
        if not I.Enabled() then return end
        I.RefreshLayout()
    end)

    ns.RegisterReloadHook(function() I.Rebuild() end)

    local init = CreateFrame("Frame")
    init:RegisterEvent("PLAYER_LOGIN")
    init:SetScript("OnEvent", function(self)
        HookNativeViewer()
        I.Rebuild()
        self:UnregisterEvent("PLAYER_LOGIN")
    end)

    return I
end

CDG.EngineFor = EngineFor

-- Attach the engine to the "essential" instance now (the only dest this phase).
if CDG.essential then EngineFor(CDG.essential) end
