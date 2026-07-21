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

-- Ordered destination options for the dropdown (keys; labels localized below). belowPlayer = the MIDDLE of the
-- two below-player rows; belowFront / belowEnd = the individual rows (they have no native viewer, so the taint /
-- signature loops that key off ns.CDM_VIEWER simply skip them).
ns.CDM_DEST_ORDER = { "essential", "utility", "belowPlayer", "belowFront", "belowEnd" }

-- ── Standalone CDM engine ownership (Level 2) ────────────────────────────────
-- When the standalone engine (ns.CDMMode "engine") is active it HOSTS the essential/utility trackers in
-- its own group layout and MASKS the native viewers. Every ownership/taint guard below therefore treats
-- those two dests as "taken": the old bucket system must not pin our frames into — or write geometry on —
-- the masked native viewer (writing a registered Edit Mode viewer is the 12.1.0 taint vector). Runtime-only
-- probe (ns.CDMMode is set by a later-loading module), so referencing it here is a forward reference by design.
local function EngineOwnsDest(dest)
    return ns.CDMMode and ns.CDMMode.IsEngine and ns.CDMMode.IsEngine()
        and (dest == "essential" or dest == "utility") or false
end

function ns.CDMDestLabel(key)
    local L = ns.L
    if key == "utility"     then return L["Cooldown Manager: Utility"] end
    if key == "belowPlayer" then return L["Below player frame"]        end
    if key == "belowFront"  then return L["Below player frame (front)"] end
    if key == "belowEnd"    then return L["Below player frame (end)"]   end
    return L["Cooldown Manager: Essential"]
end

function ns.CDMDestKeyFromLabel(label)
    for _, k in ipairs(ns.CDM_DEST_ORDER) do
        if ns.CDMDestLabel(k) == label then return k end
    end
    return "essential"
end

-- Plain 3-option dest-key label list (essential / utility / below player). Callers
-- that store a raw cdmDest key WITHOUT the front/end split (e.g. the Cast bar's
-- "anchor to" picker) use this with CDMDestLabel/CDMDestKeyFromLabel; the per-tracker
-- placement dropdowns instead use the 4-option choice list below.
function ns.CDMDestKeyList()
    local t = {}
    for _, k in ipairs(ns.CDM_DEST_ORDER) do t[#t + 1] = ns.CDMDestLabel(k) end
    return t
end

-- ── Destination CHOICE (the 4-option dropdown shown in every tracker) ─────────
-- The data model stays (cdmDest ∈ essential/utility/belowPlayer + cdmAtEnd bool),
-- but the below-player destination is presented as TWO virtual options encoding
-- front/end into cdmAtEnd, so the dropdown has 4 entries:
--   "Cooldown Manager: Essential" → cdmDest=essential,  cdmAtEnd=true (after natives)
--   "Cooldown Manager: Utility"   → cdmDest=utility,    cdmAtEnd=true (after natives)
--   "Below player frame (front)"  → cdmDest=belowPlayer, cdmAtEnd=false
--   "Below player frame (end)"    → cdmDest=belowPlayer, cdmAtEnd=true
-- No new dest values and no migration: the bucket layout reads cdmDest/cdmAtEnd
-- exactly as before.
function ns.CDMDestChoiceList()
    local L = ns.L
    return {
        ns.CDMDestLabel("essential"),
        ns.CDMDestLabel("utility"),
        L["Below player frame (front)"],
        L["Below player frame (end)"],
    }
end

-- The dropdown still calls ns.CDMDestList in legacy spots; alias it to the 4-option
-- choice list so every dropdown shows the same options.
function ns.CDMDestList()
    return ns.CDMDestChoiceList()
end

-- Current virtual label for a tracker, derived from its (cdmDest, cdmAtEnd).
function ns.CDMDestChoiceLabel(getCfg)
    local L = ns.L
    local dest = getCfg("cdmDest") or "essential"
    if dest == "belowPlayer" then
        if getCfg("cdmAtEnd") == true then return L["Below player frame (end)"] end
        return L["Below player frame (front)"]
    end
    return ns.CDMDestLabel(dest)
end

-- Apply a chosen virtual label back to (cdmDest, cdmAtEnd) via setCfg.
function ns.CDMApplyDestChoice(label, setCfg)
    local L = ns.L
    if label == L["Below player frame (front)"] then
        setCfg("cdmDest", "belowPlayer"); setCfg("cdmAtEnd", false)
    elseif label == L["Below player frame (end)"] then
        setCfg("cdmDest", "belowPlayer"); setCfg("cdmAtEnd", true)
    elseif label == ns.CDMDestLabel("utility") then
        setCfg("cdmDest", "utility");     setCfg("cdmAtEnd", true)
    else
        setCfg("cdmDest", "essential");   setCfg("cdmAtEnd", true)
    end
end

-- ── Per-group anchor targets (shared by every positional "Anchor to" / "Adapt to" dropdown) ─────────
-- The four groupable CDM dests. Each positional anchor/adapt dropdown offers one entry PER GROUP of each
-- type, labelled "<Type> (<group name>)", keyed "dest:groupId" — the engine's own catKey, resolvable by
-- E.Layout.GroupFrame (engine mode) or the module's GetContainer(id) (native mode). The list is DYNAMIC: it
-- re-reads each module's GroupList() every time it is built, so a created / deleted group appears / disappears.
local GROUP_DESTS = {
    { dest = "essential", label = "Essential", inst = function() return ns.CDMGroups and ns.CDMGroups.essential end },
    { dest = "utility",   label = "Utility",   inst = function() return ns.CDMGroups and ns.CDMGroups.utility   end },
    { dest = "buff",      label = "Buffs",     inst = function() return ns.BuffGroups end },
    { dest = "bar",       label = "Bars",      inst = function() return ns.BarGroups  end },
}
local function GroupDestInstance(dest)
    for _, gd in ipairs(GROUP_DESTS) do if gd.dest == dest then return gd.inst() end end
    return nil
end
local function GroupTypeLabel(dest)
    for _, gd in ipairs(GROUP_DESTS) do if gd.dest == dest then return (ns.L and ns.L[gd.label]) or gd.label end end
    return nil
end
-- Normalise a stored anchor key to (dest, id): "essential:2" -> "essential",2 ; a legacy plain type key
-- "essential" -> "essential",1. Returns nil for non-group keys (below*, screen, resbar, ...).
local function ParseGroupKey(key)
    if type(key) ~= "string" then return nil end
    local dest, id = key:match("^(%a+):(%d+)$")
    if not dest then dest, id = key:match("^(%a+)$"), "1" end
    if dest == "essential" or dest == "utility" or dest == "buff" or dest == "bar" then
        return dest, tonumber(id)
    end
    return nil
end
ns.ParseCDMGroupKey = ParseGroupKey

-- Ordered { {key=,label=}, ... } per-group targets. `dests` = a set like {essential=true,buff=true} (nil = all
-- four types). `excludeKey` omits one entry (a group must not offer ITSELF as a target). Dynamic.
function ns.CDMGroupAnchorTargets(dests, excludeKey)
    local out = {}
    for _, gd in ipairs(GROUP_DESTS) do
        if not dests or dests[gd.dest] then
            local I = gd.inst()
            local list = I and I.GroupList and I.GroupList()
            if type(list) == "table" then
                for _, grp in ipairs(list) do
                    local id = grp.id
                    if id and id ~= 0 then
                        local key = gd.dest .. ":" .. id
                        if key ~= excludeKey then
                            out[#out + 1] = { key = key,
                                label = GroupTypeLabel(gd.dest) .. " (" .. (grp.name or ("Group " .. id)) .. ")" }
                        end
                    end
                end
            end
        end
    end
    return out
end
-- Label for a stored per-group (or legacy plain-type) key, or nil if `key` is not a CDM-group key.
function ns.CDMGroupAnchorLabel(key)
    local dest, id = ParseGroupKey(key)
    if not dest then return nil end
    local I = GroupDestInstance(dest)
    local name = I and I.GGet and I.GGet(id, "name")
    return GroupTypeLabel(dest) .. " (" .. (name or ("Group " .. id)) .. ")"
end
function ns.IsCDMGroupAnchorKey(key) return (ParseGroupKey(key)) ~= nil end
-- Resolve a per-group (or legacy plain-type) key to a LIVE frame: the engine group frame in engine mode, else
-- the native module's per-group container. nil if that group's frame isn't up yet (caller keeps its fallback).
function ns.ResolveCDMGroupFrame(key)
    local dest, id = ParseGroupKey(key)
    if not dest then return nil end
    if ns.CDMMode and ns.CDMMode.IsEngine() then
        local E = ns.CDMEngine
        local f = E and E.Layout and E.Layout.GroupFrame and E.Layout.GroupFrame(dest .. ":" .. id)
        if f then return f end
    end
    local I = GroupDestInstance(dest)
    return (I and I.GetContainer and I.GetContainer(id)) or nil
end

-- Live viewer frame for a destination, or nil (belowPlayer / CDM off / not loaded).
function ns.GetCDMViewer(dest)
    local name = ns.CDM_VIEWER[dest]
    return name and _G[name] or nil
end

-- True when Blizzard's Cooldown Manager is enabled in the game options
-- (Options > Gameplay > Cooldown Manager, i.e. the cooldownViewerEnabled CVar,
-- "1" = on). When it is OFF the integration is inert: every tracker icon is placed
-- freely and the "Include in cdm" checkbox is greyed out + uncheckable. Defaults to
-- ON if the CVar can't be queried (should never happen on a CDM-capable client),
-- so the integration is never disabled by a failed lookup.
function ns.IsCDMEnabled()
    local getBool = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
    if not getBool then return true end
    return getBool("cooldownViewerEnabled") and true or false
end

-- Effective "this icon belongs in the CDM": the Cooldown Manager is enabled AND
-- the icon opted in. Config windows + TimerIcon's CDMActive use this instead of
-- reading includeInCdm directly, so a disabled Cooldown Manager forces every icon
-- to free placement without rewriting any saved config.
function ns.CDMIncludedVal(includeInCdm)
    return ns.IsCDMEnabled() and includeInCdm == true
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

-- Cheap, ALLOCATION-FREE structural signature of a viewer's native icons: how many
-- are shown and a positional accumulator of where they sit. Used by the relayout
-- hook to tell a genuine native CONTENT change (icon added / removed / moved → our
-- grid shifts, re-pin needed) from the viewer's constant cosmetic RefreshLayout
-- churn (cooldown-swipe frames — same icons in the same spots, nothing for us to do).
-- Positions are floored to whole pixels so sub-pixel jitter can't spoof a change.
local function NativeSig(viewer)
    local n, acc = 0, 0
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do
            if f and f.IsShown and f:IsShown() and (f.Icon or f.cooldownInfo) then
                n = n + 1
                acc = acc + math.floor((f:GetLeft() or 0) + 0.5) * 100000
                          + math.floor((f:GetTop() or 0) + 0.5)
            end
        end
    end
    return n, acc
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

-- These native helpers live above the file's main `ns.CDMAnchor = ns.CDMAnchor or {}`
-- init, so ensure the table exists before assigning into it (the later init no-ops).
ns.CDMAnchor = ns.CDMAnchor or {}

-- A native CooldownViewer item frame's spell id. The item frame carries a
-- `cooldownInfo` table (Blizzard's GetCooldownViewerCooldownInfo result); the DISPLAY
-- spell is overrideTooltipSpellID -> overrideSpellID -> spellID (same precedence the
-- native viewer + Ayije_CDM use). Returns nil when the frame has no cooldown info.
function ns.CDMAnchor.NativeFrameSpellId(nf)
    local ci = nf and nf.cooldownInfo
    if type(ci) ~= "table" then return nil end
    local id = ci.overrideTooltipSpellID or ci.overrideSpellID or ci.spellID
    if id and (not issecretvalue or not issecretvalue(id)) and id > 0 then return id end
    return nil
end

-- The STABLE BASE spell id of a native CooldownViewer item frame: cooldownInfo.spellID, the spell that
-- does NOT change when the cooldown transforms (Frostbolt 116 <-> Glacial Spike 199786 keep base 116).
-- Unlike NativeFrameSpellId (the DISPLAY resolver, which follows override(Tooltip)SpellID), this returns
-- ONLY the base, so the groups engine can key a transforming cooldown by an identity that survives the
-- transform. Reads are guarded for nil / secret (issecretvalue/canaccessvalue/pcall) and > 0, mirroring
-- NativeFrameSpellId; returns nil when the base is unreadable so the caller falls back to display.
function ns.CDMAnchor.NativeFrameBaseSpellId(nf)
    local ci = nf and nf.cooldownInfo
    if type(ci) ~= "table" then return nil end
    local ok, id = pcall(function() return ci.spellID end)
    if not ok or id == nil then return nil end
    if issecretvalue and issecretvalue(id) then return nil end
    if canaccessvalue and not canaccessvalue(id) then return nil end
    if type(id) ~= "number" or id <= 0 then return nil end
    return id
end

-- The native BUFF cooldown viewer's icon frames (BuffIconCooldownViewer). The Buff-groups
-- module redistributes these into its own movable group containers (reusing the real native
-- frames so Blizzard keeps rendering their cooldown / charges / combat state).
--
-- The viewer keeps one POOL frame per DISPLAYED buff and toggles each frame's shown state as
-- the aura comes and goes — so we must NOT filter on IsShown (an inactive buff's frame is
-- shown=false but still needs pre-positioning in its group; Blizzard reveals it in place when
-- the buff procs). Every active pool frame is returned; the caller resolves the spell id.
-- `out` (optional): a caller-supplied scratch reused across passes instead of allocating a fresh
-- array each call (the BuffGroups RefreshLayout enum runs ~60 Hz on cooldown-swipe frames). Mirrors
-- BarGroups.EnumBarFrames(out). Callers that pass no scratch still get a fresh table.
function ns.CDMAnchor.EnumBuffIcons(out)
    out = out or {}
    wipe(out)
    local v = _G.BuffIconCooldownViewer
    if not v then return out end
    local pool = v.itemFramePool
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do
            if f then out[#out + 1] = f end
        end
    end
    if #out == 0 then
        for _, c in ipairs({ v:GetChildren() }) do
            if c and (c.cooldownInfo or c.GetCooldownInfo or c.GetSpellID) then
                out[#out + 1] = c
            end
        end
    end
    return out
end

-- Per-row list of the native cooldowns currently shown in a dest's viewer, each
-- { spellId, texture, name }, in visual order. Used by the "Native icons" config cadre.
function ns.CDMAnchor.GetNativeRows(dest)
    local viewer = ns.GetCDMViewer(dest)
    if not viewer then return {} end
    local out = {}
    for ri, row in ipairs(ComputeRows(viewer)) do
        local list = {}
        for _, nf in ipairs(row) do
            local sid = ns.CDMAnchor.NativeFrameSpellId(nf)
            if sid then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                list[#list + 1] = {
                    spellId = sid,
                    texture = (nf.Icon and nf.Icon.GetTexture and nf.Icon:GetTexture())
                              or (info and info.iconID) or (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)),
                    name    = info and info.name,
                }
            end
        end
        out[ri] = list
    end
    return out
end

-- Synchronously hide any native frame matching this spell, used right after adopting so
-- the native doesn't flash next to our replacement icon before the next layout pass.
function ns.CDMAnchor.HideNativeForSpell(spellId)
    for _, dest in ipairs({ "essential", "utility" }) do
        local v = ns.GetCDMViewer(dest)
        if v then
            for _, nf in ipairs(EnumNativeIcons(v)) do
                if ns.CDMAnchor.NativeFrameSpellId(nf) == spellId
                    and nf.Hide and nf:IsShown()
                    and not (InCombatLockdown() and nf.IsProtected and nf:IsProtected()) then
                    nf:Hide()
                end
            end
        end
    end
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

-- OUR tracker-icon frames currently placed in a CDM destination ("essential" |
-- "utility" | "belowPlayer"), only while the Cooldown Manager is enabled and the icon
-- opted in. Used by the Beta fader: our icons are ANCHORED to (not children of) the
-- native viewer, so the viewer's alpha does not propagate to them — they must be faded
-- directly. A nil cdmDest counts as "essential" (matches the layout default).
function ns.CDMAnchor.GetIconFrames(dest)
    local out = {}
    for _, d in ipairs(appliers) do
        if d.frame and d.getCfg and ns.CDMIncludedVal(d.getCfg("includeInCdm"))
            and (d.getCfg("cdmDest") or "essential") == dest then
            out[#out + 1] = d.frame
        end
    end
    return out
end

-- Descriptors (not just frames) for every registered tracker icon that opted into the CDM
-- (includeInCdm) and targets `dest`. The NEW "Cooldown groups" engine consumes this to discover
-- the tracker icons it must fold into its group layout as full members (a member key = the frame's
-- global NAME, the same DescId the reorder map uses). Each entry exposes just what the engine needs:
--   name    = the frame's global name (the string member key)
--   frame   = the tracker's icon frame (the engine SetPoint/SIZES it; the module owns Show/Hide)
--   getIcon = the icon texture getter (the config strip draws the tile from this)
--   setSize = the descriptor's size hook (w,h) — the engine sizes the frame to the group's iconW/H
--   getCfg  = the tracker's config getter (so the engine can read the dest, etc.)
-- Unlike GetIconFrames this ignores the Cooldown-Manager-enabled CVar gate: the groups engine has
-- its own enable + OwnsDest gate, and an owned dest positions trackers regardless of that legacy CVar.
function ns.CDMAnchor.GetIconDescriptors(dest)
    local out = {}
    for _, d in ipairs(appliers) do
        if d.frame and d.getCfg and d.getCfg("includeInCdm")
            and (d.getCfg("cdmDest") or "essential") == dest
            -- Skip a tracker that has nothing trackable right now (optional predicate): a PASSIVE or empty
            -- trinket slot has no on-use cooldown, so it must not fold into a group as a "?" member.
            and (not d.cdmEligible or d.cdmEligible()) then
            -- The member key is the frame's global name (DescId is declared later in the file, so
            -- this closure can't capture that local — inline the same frame:GetName() resolution).
            local name = (d.frame.GetName and d.frame:GetName()) or tostring(d.frame)
            out[#out + 1] = {
                name    = name,
                frame   = d.frame,
                getIcon = d.getIcon,
                setSize = d.setSize,
                getCfg  = d.getCfg,
            }
        end
    end
    return out
end

-- ── Below-player artificial row (two buckets) ────────────────────────────────
-- The below-player destination renders as TWO buckets under the player frame:
--   * FRONT — anchored to the frame's BOTTOM-LEFT, icons laid left->right;
--   * END   — anchored to the frame's BOTTOM-RIGHT, the whole group right-aligned
--             so its last icon touches the frame's right edge.
-- Each bucket has its own manual offset AND its own appearance/layout config (size, grow,
-- static, spacing, border, glow, CDM flags, Timer/Title/Stacks) on cdmBelowRow.front / .end.
local BELOW_GAP = 0   -- icons placed flush against each other (no spacing)
local belowFront, belowEnd
local belowUnlocked = false   -- transient (per-session) manual-drag mode

-- Per-bucket config sub-table for the below-player row (bucket = "front" | "end"). Auto-creates
-- the sub-table. The dests "belowFront"/"belowEnd" route here, so every per-dest accessor
-- (GetDestCfg/Border/Glow/CdmFlag) reads/writes the right bucket without signature changes.
local function BelowBucketCfg(bucket)
    local p = ns.db and ns.db.profile
    if not p then return nil end
    p.cdmBelowRow = p.cdmBelowRow or {}
    p.cdmBelowRow[bucket] = p.cdmBelowRow[bucket] or {}
    return p.cdmBelowRow[bucket]
end
ns.CDMAnchor.BelowBucketCfg = BelowBucketCfg

-- Effective per-bucket layout (icon size, gap, grow, static) WITH defaults applied. Read-only (does
-- not auto-create the sub-table) and nil-safe so it can run from the change-signature. Shared by
-- LayoutBelowPlayer.place and ComputeSig so both see the SAME effective values — and honours spacing=0
-- (the UI's minimum) instead of folding it to the default via an `or 1` falsy-zero trap.
local function BelowBucketLayout(bucket)
    local p = ns.db and ns.db.profile
    local c = p and p.cdmBelowRow and p.cdmBelowRow[bucket]
    local gap = c and c.spacing
    if gap == nil then gap = 0 end   -- default: icons flush (no spacing)
    return (c and c.width) or 36, (c and c.height) or 36, gap,
           (c and c.growDir) or "RIGHT", (c and c.staticDisplay) == true
end

-- Whether an icon's cdmAtEnd value puts it in the END-of-row bucket: nil/true -> end, false -> front.
-- Single source of truth for that sentinel — the layout bucketing, the reorder strips, the grid
-- metadata (here) and TimerIcon.CfgDest all route through it so they can never disagree.
local function IsAtEnd(atEnd) return atEnd ~= false end
ns.CDMAnchor.IsAtEnd = IsAtEnd

-- Account-wide manual offset of a bucket. Only honoured in manual mode; otherwise the
-- bucket stays flush under the frame (offset 0,0). side=="end" -> the end bucket's own
-- offset (from BOTTOMRIGHT); otherwise the front bucket's (from BOTTOMLEFT).
local function BelowOffset(side)
    local c = ns.db and ns.db.profile and ns.db.profile.cdmBelowRow
    if not (c and c.manualEnabled) then return 0, 0 end
    if side == "end" then return c.endOffsetX or 0, c.endOffsetY or 0 end
    return c.offsetX or 0, c.offsetY or 0
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
ns.ResolvePlayerFrame = ResolvePlayerFrame   -- shared: the engine's "belowPlayer" anchor resolves through this

-- ── Below-player anchor rows (shared across resource bars / cast bar / Buff+Bar groups) ──────────────
-- The below-player CDM layout draws TWO icon rows: FRONT (UnbunkUtilityCDMBelowRow) and END
-- (UnbunkUtilityCDMBelowRowEnd). Anything can ride them via three keys, mirroring the resource-bar targets:
--   belowFront  -> the front row
--   belowEnd    -> the end row
--   belowPlayer -> the MIDDLE of the two (a helper frame spanning front top-left .. end bottom-right, so its
--                  centre is the row centre; follows both rows live via SetPoint)
-- When the below-player rows don't exist (that layout isn't populated) we fall back to the PLAYER FRAME, so
-- "Below player frame" keeps working literally. Returns nil only if even the player frame is unavailable.
local belowMiddle
function ns.IsBelowAnchorKey(key)
    return key == "belowPlayer" or key == "belowFront" or key == "belowEnd"
end
function ns.ResolveBelowFrame(key)
    local front = _G["UnbunkUtilityCDMBelowRow"]
    local endf  = _G["UnbunkUtilityCDMBelowRowEnd"]
    if key == "belowFront" and front then return front end
    if key == "belowEnd"   and endf  then return endf  end
    if key == "belowPlayer" and front and endf then
        if not belowMiddle then belowMiddle = CreateFrame("Frame", nil, UIParent) end
        belowMiddle:ClearAllPoints()
        belowMiddle:SetPoint("TOPLEFT",     front, "TOPLEFT",     0, 0)
        belowMiddle:SetPoint("BOTTOMRIGHT", endf,  "BOTTOMRIGHT", 0, 0)
        return belowMiddle
    end
    return ResolvePlayerFrame()   -- rows absent -> the player frame itself
end

-- Every player-frame frame the BETA fader should fade: any loaded custom unit-frame
-- addon's player frame (ElvUI's ElvUF_Player, Unhalted's UUF_Player, …) PLUS Blizzard's
-- whole PlayerFrame (NOT its content-main; we want to fade the entire frame). Hidden
-- ones are harmless (alpha on a hidden frame is invisible) — only the visible one shows
-- the fade. Reuses the same candidate list as the below-player anchor.
function ns.CDMAnchor.GetPlayerFrames()
    local out = {}
    for _, name in ipairs(PLAYER_FRAME_CANDIDATES) do
        local f = _G[name]
        if f then out[#out + 1] = f end
    end
    local pf = _G["PlayerFrame"]
    if pf then out[#out + 1] = pf end
    return out
end

-- Anchor each bucket to the player frame (+ its manual offset): the FRONT bucket's
-- TOPLEFT to BOTTOMLEFT, the END bucket's TOPRIGHT to BOTTOMRIGHT (so it grows to the
-- left and stays right-aligned). Default offset 0,0 -> flush under the visible frame.
local function AnchorBelowBuckets()
    local anchor = ResolvePlayerFrame()
    if belowFront then
        local ox, oy = BelowOffset("front")
        belowFront.anchorFrame = anchor
        belowFront:ClearAllPoints()
        if anchor then
            belowFront:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ox, oy)
        else
            belowFront:SetPoint("CENTER", UIParent, "CENTER", ox - 80, oy - 160)
        end
    end
    if belowEnd then
        local ox, oy = BelowOffset("end")
        belowEnd.anchorFrame = anchor
        belowEnd:ClearAllPoints()
        if anchor then
            belowEnd:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", ox, oy)
        else
            belowEnd:SetPoint("CENTER", UIParent, "CENTER", ox + 80, oy - 160)
        end
    end
end

-- Build one draggable bucket frame. side decides which edge it anchors by and which
-- offset keys a drag writes back (front -> offsetX/Y from the left; end -> endOffsetX/Y
-- from the right). Dragging is gated by belowUnlocked; the blue overlay marks it.
local function MakeBelowBucket(name, side)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(1, 1)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.1, 0.6, 1, 0.25)
    bg:Hide()
    f.dragBG = bg
    f:SetScript("OnDragStart", function(self)
        if belowUnlocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local anchor = self.anchorFrame or _G["PlayerFrame"]
        local c = ns.db and ns.db.profile and ns.db.profile.cdmBelowRow
        if anchor and c and self:GetTop() and anchor:GetBottom() then
            if side == "end" then
                if self:GetRight() and anchor:GetRight() then
                    c.endOffsetX = self:GetRight() - anchor:GetRight()
                    c.endOffsetY = self:GetTop()   - anchor:GetBottom()
                end
            elseif self:GetLeft() and anchor:GetLeft() then
                c.offsetX = self:GetLeft() - anchor:GetLeft()
                c.offsetY = self:GetTop()  - anchor:GetBottom()
            end
        end
        AnchorBelowBuckets()
        if ns.OnBelowRowMoved then ns.OnBelowRowMoved() end
    end)
    return f
end

-- Create both bucket frames (lazily) and (re)anchor them. The front keeps the original
-- frame name for back-compat; the end bucket gets its own.
local function EnsureBelowBuckets()
    if not belowFront then belowFront = MakeBelowBucket("UnbunkUtilityCDMBelowRow",    "front") end
    if not belowEnd   then belowEnd   = MakeBelowBucket("UnbunkUtilityCDMBelowRowEnd", "end")   end
    AnchorBelowBuckets()
    return belowFront, belowEnd
end

-- Unlock / lock the below-player row for manual dragging (General Settings).
-- When unlocked the row is raised above the (flush, gap-0) icons so its whole
-- area is grabbable; locking restores the normal strata.
function ns.CDMAnchor.SetBelowUnlocked(val)
    belowUnlocked = val and true or false
    local f1, f2 = EnsureBelowBuckets()
    for _, row in ipairs({ f1, f2 }) do
        row:EnableMouse(belowUnlocked)
        row:SetFrameStrata(belowUnlocked and "DIALOG" or "MEDIUM")
        if row.dragBG then
            if belowUnlocked then row.dragBG:Show() else row.dragBG:Hide() end
        end
    end
    ns.CDMAnchor.RefreshAll()
end
function ns.CDMAnchor.IsBelowUnlocked() return belowUnlocked end

-- Master toggle for the entire below-player row. Default ON: nil/true -> enabled, only an explicit
-- false disables it (mirrors IsAtEnd's `~= false` default-true sentinel + the Essential/Utility/Buffs
-- engines' default-ON convention). When disabled, the row's icons simply DON'T render — you can still
-- assign icons to the row, they just won't show while it's off (NOT reverted to free placement). The
-- hide is enforced by the DoRefreshBody dispatch (immediate) + each tracker's own Show/ApplyVisuals
-- gate (TimerIcon.ContextHidden, BResTracker.ApplyVisuals) so the owner can't re-show them.
function ns.CDMAnchor.IsBelowEnabled()
    local c = ns.db and ns.db.profile and ns.db.profile.cdmBelowRow
    return not c or c.enabled ~= false
end
function ns.CDMAnchor.SetBelowEnabled(val)
    local p = ns.db and ns.db.profile
    if not p then return end
    p.cdmBelowRow = p.cdmBelowRow or {}
    p.cdmBelowRow.enabled = val and true or false
end

-- Master toggle for FREE icons (those taken OUT of the Cooldown Manager, placed by their own
-- posX/posY — the "Free icons" tab). Same default-ON / hide-when-off semantics as the below-player
-- row: OFF -> every free icon simply doesn't render (you can still add / configure them). Stored flat
-- on the profile (no containing table); the hide is enforced by TimerIcon.ContextHidden +
-- BResTracker.ApplyVisuals, with the free icons' own ApplyPosition (run via the dispatch's d.apply)
-- hiding them on a forced RefreshAll.
function ns.CDMAnchor.IsFreeEnabled()
    local p = ns.db and ns.db.profile
    return not p or p.cdmFreeEnabled ~= false
end
function ns.CDMAnchor.SetFreeEnabled(val)
    local p = ns.db and ns.db.profile
    if not p then return end
    p.cdmFreeEnabled = val and true or false
end

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

local function LayoutBelowPlayer(list)
    -- Split the (order-sorted) below list into front / end-of-row buckets by the
    -- per-icon "Icon at the end of the row" flag (cdmAtEnd), then lay the front
    -- bucket out left-to-right followed by the end bucket — same start/end
    -- semantics as the essential/utility native rows. Filtering an already
    -- order-sorted list keeps each bucket in saved order, so no per-bucket re-sort
    -- is needed (and each bucket is reordered independently via SetBucketOrder, so
    -- we no longer normalize the combined list to one contiguous run).
    local front, tail = {}, {}
    for _, d in ipairs(list) do
        if d.getCfg and IsAtEnd(d.getCfg("cdmAtEnd")) then tail[#tail + 1] = d
        else front[#front + 1] = d end
    end
    local frontRow, endRow = EnsureBelowBuckets()

    -- Lay a bucket's members along its grow axis with `gap` between them, then size the frame to bound
    -- them. Every layout option (icon size, spacing, grow direction, static display) is read PER-BUCKET
    -- from cdmBelowRow.front / .end (the "Front/End of the row settings" cadres). Defaults: size 36,
    -- gap 1, grow RIGHT, static off. Static display also reserves a slot for HIDDEN members (positioned
    -- but left invisible) so the shown icons keep their absolute slots; otherwise only shown icons take
    -- a slot (reflow).
    local function place(bucket, row, side)
        local w, h, gap, grow, static = BelowBucketLayout(side)
        local bucketDest = (side == "end") and "belowEnd" or "belowFront"
        local vertical = (grow == "UP" or grow == "DOWN" or grow == "CENTER_V")
        local reverse  = (grow == "LEFT" or grow == "UP")

        local members = {}
        for _, d in ipairs(bucket) do
            local f = d.frame
            if f and (static or f:IsShown()) then members[#members + 1] = d end
        end
        if reverse then
            for i = 1, math.floor(#members / 2) do
                members[i], members[#members - i + 1] = members[#members - i + 1], members[i]
            end
        end
        -- Per-icon size: an icon whose "Icon size" override cadre is ticked (iconW/iconH override stored
        -- via BelowIconSet) uses its OWN size; otherwise it inherits the bucket's uniform width/height. The
        -- row advances by each icon's real size (relative SetPoint), so a mixed-size row stays aligned.
        local function iconSize(d)
            local fn = d.frame and d.frame.GetName and d.frame:GetName()
            local iw, ih = w, h
            if fn and ns.CDMAnchor.BelowIconHasOverride then
                if ns.CDMAnchor.BelowIconHasOverride(fn, "iconW") then iw = ns.CDMAnchor.BelowIconGet(fn, bucketDest, "iconW") or w end
                if ns.CDMAnchor.BelowIconHasOverride(fn, "iconH") then ih = ns.CDMAnchor.BelowIconGet(fn, bucketDest, "iconH") or h end
            end
            return iw, ih
        end
        local prev, count, mainTotal, crossMax = nil, 0, 0, 0
        for _, d in ipairs(members) do
            local f = d.frame
            local iw, ih = iconSize(d)
            if d.setSize then d.setSize(iw, ih) end
            f:ClearAllPoints()
            if prev then
                if vertical then f:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
                else f:SetPoint("LEFT", prev, "RIGHT", gap, 0) end
            elseif vertical then
                f:SetPoint("TOP", row, "TOP", 0, 0)
            else
                f:SetPoint("LEFT", row, "LEFT", 0, 0)
            end
            prev = f
            count = count + 1
            if vertical then mainTotal = mainTotal + ih; crossMax = math.max(crossMax, iw)
            else            mainTotal = mainTotal + iw; crossMax = math.max(crossMax, ih) end
        end
        if vertical then
            row:SetSize(math.max(1, crossMax), math.max(1, mainTotal + math.max(0, count - 1) * gap))
        else
            row:SetSize(math.max(1, mainTotal + math.max(0, count - 1) * gap), math.max(1, crossMax))
        end
        if row.dragBG then
            if belowUnlocked then row.dragBG:Show() else row.dragBG:Hide() end
        end
    end

    place(front, frontRow, "front")
    place(tail,  endRow,   "end")
end

-- Effective number of rows the layout will actually render for a destination,
-- mirroring LayoutCDMRow's nRows = ceil((natives + our shown icons) / iconLimit).
-- The reorder bucketing MUST use this (not the native-only CDMRowCount) so an icon
-- that renders on an extra row our icons created is bucketed on that same row.
local function EffectiveRowCount(dest)
    local v = ns.GetCDMViewer(dest)
    if not v then return 1 end
    local nNat = 0
    for _ in ipairs(EnumNativeIcons(v)) do
        nNat = nNat + 1
    end
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
    local atEnd = IsAtEnd(d.getCfg("cdmAtEnd"))
    return ri .. (atEnd and "E" or "S")
end

-- Reorderable siblings of `frame`: the OUR icons it shares a bucket with — the
-- same start/end of the same essential/utility row, or the start/end bucket of the
-- single below-player row.
local function SiblingList(frame)
    local d0 = byFrame[frame]
    if not d0 or not d0.getCfg or not d0.getCfg("includeInCdm") then return {} end
    local dest = d0.getCfg("cdmDest")
    local nRows
    if dest == "belowPlayer" then
        nRows = 1                              -- one row; buckets split only by start/end
    else
        if not ns.GetCDMViewer(dest) then return {} end
        nRows = EffectiveRowCount(dest)
    end
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

-- ── CDM row buckets (config drag-reorder strips: essential / utility / below) ─
-- How many rows the destination renders (so the config can show one front/end pair
-- per row). Mirrors the layout's row count. The below-player destination is a
-- single row (only its start/end buckets differ), so it always reports one row.
function ns.CDMAnchor.GetRowCount(dest)
    if dest == "belowPlayer" then return 1 end
    if not ns.GetCDMViewer(dest) then return 0 end
    return EffectiveRowCount(dest)
end

-- Max number of OUR icons (tracker + custom) allowed in one row, combining the front
-- and end buckets. This is the cap the "+" add tile is gated against; native Blizzard
-- icons are NOT counted (they are not part of the front/end buckets).
local ROW_CAP = { essential = 6, utility = 6, belowPlayer = 8 }
function ns.CDMAnchor.RowCap(dest) return ROW_CAP[dest] or 6 end

-- Our shown icons in one (dest, row, atEnd) bucket, in order — same membership the
-- layout uses (RowBucketKey), sorted by saved order.
local function BucketList(dest, row, atEnd)
    local nRows
    if dest == "belowPlayer" then
        nRows = 1                                 -- single row, no native viewer
    else
        if not ns.GetCDMViewer(dest) then return {} end
        nRows = EffectiveRowCount(dest)
    end
    local key = row .. (atEnd and "E" or "S")
    local list = {}
    for _, d in ipairs(appliers) do
        if d.frame and d.frame.IsShown and d.frame:IsShown() and d.getCfg
            and d.getCfg("includeInCdm") and d.getCfg("cdmDest") == dest
            and RowBucketKey(d, nRows) == key then
            list[#list + 1] = d
        end
    end
    return SortByOrder(list)
end

function ns.CDMAnchor.GetBucketIcons(dest, row, atEnd)
    local out = {}
    for _, d in ipairs(BucketList(dest, row, atEnd)) do
        local id = DescId(d)
        out[#out + 1] = {
            id      = id,
            texture = d.getIcon and d.getIcon() or nil,
            custom  = ns.CustomCDM and ns.CustomCDM.IsCustom(id) or nil,
        }
    end
    return out
end

-- How many of OUR icons currently occupy a row (front + end combined), used to gate
-- the "+" add tile against ns.CDMAnchor.RowCap(dest).
function ns.CDMAnchor.RowIconCount(dest, row)
    return #BucketList(dest, row, false) + #BucketList(dest, row, true)
end

-- Per-BUCKET cap + count. The below-player front/end buckets are each capped INDEPENDENTLY (the user's
-- "4 icons per part of the row"); the "+" add tile, the cross-bucket drop, and the custom-add path all
-- gate against these. Other dests fall back to the combined RowCap.
local BUCKET_CAP = { belowPlayer = 4 }
function ns.CDMAnchor.BucketCap(dest) return BUCKET_CAP[dest] or ns.CDMAnchor.RowCap(dest) end
function ns.CDMAnchor.BucketIconCount(dest, row, atEnd) return #BucketList(dest, row, atEnd) end

-- Addon TRACKER icons (not custom) that are CDM-capable but taken OUT of the CDM
-- (includeInCdm false) and currently shown — for the "Free icons" tab, where clicking
-- one jumps to its own config panel. Custom free icons come from ns.CustomCDM instead.
function ns.CDMAnchor.GetFreeTrackerIcons()
    local out = {}
    for _, d in ipairs(appliers) do
        local name = d.frame and DescId(d)
        if name and d.getCfg and d.frame.IsShown and d.frame:IsShown()
            and d.getCfg("cdmDest")                 -- a CDM-capable tracker (excludes alert frames)
            and not d.getCfg("includeInCdm")        -- the user took it out of the CDM
            and not (ns.CustomCDM and ns.CustomCDM.IsCustom(name)) then
            out[#out + 1] = { id = name, texture = d.getIcon and d.getIcon() or nil, custom = false }
        end
    end
    return out
end

-- Persist a new order for one bucket. The order map is keyed by frame name and each
-- icon belongs to a single bucket, and SortByOrder only ever compares within a
-- bucket, so writing 1..n for these ids can't disturb other buckets/rows.
function ns.CDMAnchor.SetBucketOrder(dest, row, atEnd, idList)
    local map = OrderMap()
    if not map then return end
    for i, id in ipairs(idList) do map[id] = i end
    ns.CDMAnchor.RefreshAll()
end

-- Move an icon (by its frame-name id) between the FRONT and END bucket of its row, by
-- flipping the owning descriptor's cdmAtEnd config. Used by the config reorder strips when a
-- tile is dragged from the Front strip to the End strip (or back) — bucket membership is
-- driven by cdmAtEnd (RowBucketKey), so a cross-strip drag must flip it. Each module that can
-- live in a CDM row registers a setCfg with its descriptor; modules that don't (e.g. native
-- icons, which aren't in these strips) simply can't be flipped. Returns true on success.
function ns.CDMAnchor.SetIconAtEnd(frameId, atEnd)
    for _, d in ipairs(appliers) do
        if d.frame and DescId(d) == frameId then
            if d.setCfg then
                d.setCfg("cdmAtEnd", atEnd and true or false)
                return true
            end
            return false
        end
    end
    return false
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
-- Raw C size/scale setters (same idea as RawSetPoint): the per-item re-impose hooks below fire
-- SYNCHRONOUSLY from inside Blizzard's secure CooldownViewer:RefreshLayout (during RefreshData).
-- A normal frame:SetSize/SetScale from that tainted hook context taints the ongoing secure refresh,
-- making Blizzard's own aura/totem SECRET comparisons error ("tainted by UnbunkUtility"). Going
-- through the raw C method (like SetPoint already did) re-imposes our geometry without taint AND
-- without re-triggering our own hooks.
local RawSetSize        = _proxy.SetSize
local RawSetScale       = _proxy.SetScale
local RawSetParent      = _proxy.SetParent   -- raw C reparent for the SetParent-ADOPT path (AdoptNativeTo below)

local containers     = {}     -- dest -> our container frame
local editModeActive = false

-- ── Per-viewer (essential / utility) placement + per-row icon size ────────────
-- Per-profile override (ns.db.profile.cdmViewer[dest]) of the NATIVE CooldownViewer:
--   * offsetX/offsetY nudge the whole viewer from its captured EditMode anchor;
--   * rows[r] = { width, height } resize that row's icons (native AND ours).
-- The addon only TAKES OVER a viewer once an override exists (or it is unlocked for
-- dragging) — with no override Blizzard / EditMode keeps full ownership.
local viewerUnlocked = {}     -- dest -> transient (per-session) manual-drag mode

local function ViewerCfg(dest)
    local p = ns.db and ns.db.profile
    if not p then return nil end
    p.cdmViewer = p.cdmViewer or {}
    p.cdmViewer[dest] = p.cdmViewer[dest] or {}
    return p.cdmViewer[dest]
end
ns.CDMAnchor.ViewerCfg = ViewerCfg

-- Placed position of the viewer's TOP-centre, measured from the SCREEN centre (the same
-- reference EditMode uses). nil on an axis = not placed -> fall back to the EditMode base.
local function ViewerPos(dest)
    local c = ViewerCfg(dest)
    return c and c.x, c and c.y
end

-- Per-dest default icon size (the code-level fallback for any row with no explicit
-- override) — Essentials / Utility default to 44x44.
local DEFAULT_VIEWER_ICON = { essential = 44, utility = 44 }

-- A row's icon size: the saved override if set (>0), else this dest's default (44 for
-- essential/utility), else the native slot size nw/nh passed in.
local function ViewerRowSize(dest, r, nw, nh)
    local c = ViewerCfg(dest)
    local rs = c and c.rows and c.rows[r]
    local dw = DEFAULT_VIEWER_ICON[dest]
    local w = (rs and rs.width  and rs.width  > 0) and rs.width  or dw or nw
    local h = (rs and rs.height and rs.height > 0) and rs.height or dw or nh
    return w, h
end

-- The size the layout would actually use for a row (override / default / native), so the
-- config panel can show the current effective value (44 by default).
function ns.CDMAnchor.EffectiveRowSize(dest, r)
    local nw, nh = ns.CDMAnchor.NativeIconSize(dest)
    return ViewerRowSize(dest, r, nw, nh)
end

-- ── Per-dest border (shared by EVERY icon that is IN that dest) ───────────────
-- Stored on the dest's config (cdmViewer[dest] for essential/utility, cdmBelowRow.front / .end
-- for the below-player buckets); defaults to a 1px black border. TimerIcon.ApplyBorder reads this
-- for any icon in the CDM, so the dest's Border cadre governs them all; free icons keep their own.
-- The below-player row is two buckets: "belowFront"/"belowEnd" route to cdmBelowRow.front / .end
-- (the icon's bucket is resolved by TimerIcon.CfgDest from cdmAtEnd before it reaches here).
local function DestBorderCfg(dest)
    if dest == "belowFront" then return BelowBucketCfg("front") end
    if dest == "belowEnd"   then return BelowBucketCfg("end") end
    return ViewerCfg(dest)
end
ns.CDMAnchor.DestBorderCfg = DestBorderCfg

function ns.CDMAnchor.GetDestBorder(dest)
    local c = DestBorderCfg(dest)
    local enabled = (not c) or (c.borderEnabled ~= false)   -- default ON
    local color   = (c and c.borderColor) or { r = 0, g = 0, b = 0, a = 1 }
    local size    = (c and c.borderSize) or 1
    return enabled, color, size
end

function ns.CDMAnchor.SetDestBorder(dest, key, val)
    local c = DestBorderCfg(dest)
    if not c then return end
    c[key] = val
    -- Cold-path config edit. The forced relayout repaints icons via setSize -> the GATED
    -- ApplyDerivedSizing, which would skip a style-only (border) change; bump the shared style epoch so
    -- every tracker icon's gate re-derives once and re-reads this border.
    if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end
    ns.CDMAnchor.RefreshAll(true)
end

-- ── Per-dest CDM display flags: "Show press overlay" / "Show Keybinds" ────────
-- Per-dest opt-in (default OFF), stored alongside the dest's config. Read by TimerIcon for an icon
-- pinned in that dest. Only the BELOW-PLAYER buckets use this store (their own "CDM settings" cadres,
-- one per bucket); essential/utility groups read their GROUP's per-icon flags via the CDMGroups engine
-- instead. The below-player row is two buckets: "belowFront"/"belowEnd" route to cdmBelowRow.front /
-- .end (the icon's bucket is resolved by TimerIcon.CfgDest from cdmAtEnd before it reaches here).
local function DestFlagCfg(dest)
    if dest == "belowFront" then return BelowBucketCfg("front") end
    if dest == "belowEnd"   then return BelowBucketCfg("end") end
    return ViewerCfg(dest)
end

function ns.CDMAnchor.GetDestCdmFlag(dest, key)
    local c = DestFlagCfg(dest)
    return (c and c[key] == true) or false
end

function ns.CDMAnchor.SetDestCdmFlag(dest, key, val)
    local c = DestFlagCfg(dest)
    if not c then return end
    c[key] = val and true or false
    -- Cold-path config edit: bump the shared style epoch so the gated ApplyDerivedSizing re-runs
    -- ApplyKeybind for every below-player icon (the forced relayout's setSize alone is gated), then relayout.
    if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end
    ns.CDMAnchor.RefreshAll(true)
end

-- ── Per-dest GLOW (below-player) ─────────────────────────────────────────────
-- enabled / type (pixel|autocast|button) / colour {r,g,b,a}. TimerIcon draws a LibCustomGlow halo on
-- the icon while it is ACTIVE (green/buff-up) when enabled. Stored on cdmBelowRow. Default ON (matches SeedTrackerFreeLook).
function ns.CDMAnchor.GetDestGlow(dest)
    local c = DestFlagCfg(dest)
    local enabled = (not c) or (c.glowEnabled ~= false)   -- default ON; OFF only when explicitly unchecked
    local gtype   = (c and c.glowType) or "pixel"
    local color   = (c and c.glowColor) or { r = 0.96, g = 1, b = 0, a = 1 }
    return enabled, gtype, color
end
function ns.CDMAnchor.SetDestGlow(dest, key, val)
    local c = DestFlagCfg(dest)
    if not c then return end
    c[key] = val
    if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- cold-path edit: re-derive the gated tracker icons
    ns.CDMAnchor.RefreshAll(true)
end

-- ── Generic per-dest icon config (below-player Title / Stacks / Timer cadres) ──
-- Stored on the dest's config (cdmBelowRow). GetDestCfg returns `default` when unset. TimerIcon reads
-- these for any icon pinned in that dest; the cadres write them.
function ns.CDMAnchor.GetDestCfg(dest, key, default)
    local c = DestFlagCfg(dest)
    local v = c and c[key]
    if v == nil then return default end
    return v
end
function ns.CDMAnchor.SetDestCfg(dest, key, val)
    local c = DestFlagCfg(dest)
    if not c then return end
    c[key] = val
    if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- cold-path edit: re-derive the gated tracker icons
    ns.CDMAnchor.RefreshAll(true)
end

-- ── Per-ICON override for below-player icons (the tracker "Override settings" cadre) ──────────────
-- Mirrors the essential/utility group's per-icon override (CDMGroups I.IconGet): a MIGRATED below-player
-- icon reads its OWN value, falling back to its bucket's value (cdmBelowRow.front / .end). Stored flat per
-- frame name on cdmBelowRow.iconCfg[frameName]; `__ovMigrated` marks an icon that has been seeded so the
-- read path stays bucket-only (unchanged) for every icon that never opened the new cadre. Size is NOT
-- overridden here — the below-player row is laid out at a uniform per-bucket size, so the Override cadre
-- omits its Icon-size section for this dest.
local function BelowIconStore()
    local p = ns.db and ns.db.profile
    if not p then return nil end
    p.cdmBelowRow = p.cdmBelowRow or {}
    p.cdmBelowRow.iconCfg = p.cdmBelowRow.iconCfg or {}
    return p.cdmBelowRow.iconCfg
end

function ns.CDMAnchor.BelowIconMigrated(frameName)
    local s = BelowIconStore()
    local ic = s and frameName and s[frameName]
    -- Seeded at any version (new __ovSeedV) or the legacy __ovMigrated marker.
    return (ic and (ic.__ovSeedV ~= nil or ic.__ovMigrated == true)) or false
end

-- override (only when migrated) -> bucket value (GetDestCfg). bucketDest = "belowFront" | "belowEnd".
function ns.CDMAnchor.BelowIconGet(frameName, bucketDest, key, default)
    local s = BelowIconStore()
    local ic = s and frameName and s[frameName]
    if ic and (ic.__ovSeedV ~= nil or ic.__ovMigrated) then
        local v = ic[key]
        if v ~= nil then return v end
    end
    return ns.CDMAnchor.GetDestCfg(bucketDest, key, default)
end

function ns.CDMAnchor.BelowIconSet(frameName, key, val)
    local s = BelowIconStore()
    if not s or not frameName then return end
    s[frameName] = s[frameName] or {}
    s[frameName][key] = val
    if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- cold-path per-icon below override edit
    ns.CDMAnchor.RefreshAll(true)
end

function ns.CDMAnchor.BelowIconReset(frameName, key)
    local s = BelowIconStore()
    local ic = s and frameName and s[frameName]
    if ic then
        ic[key] = nil
        if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- cold-path per-icon below override reset
        ns.CDMAnchor.RefreshAll(true)
    end
end

function ns.CDMAnchor.BelowIconHasOverride(frameName, key)
    local s = BelowIconStore()
    local ic = s and frameName and s[frameName]
    return ic ~= nil and ic[key] ~= nil
end

-- Seed the per-icon override from the tracker's default override-set. Versioned: skipped once seeded at the
-- CURRENT version; otherwise the override is WIPED and re-seeded so a changed default-set fully replaces a
-- stale one (and the legacy full seed). Keys not in `values` inherit the bucket. Maps are deep-copied.
function ns.CDMAnchor.SeedBelowIconOverride(frameName, values)
    local s = BelowIconStore()
    if not s or not frameName then return end
    local ver = ns.OVERRIDE_SEED_VERSION or 1
    local ic = s[frameName]
    if ic and ic.__ovSeedV == ver then return end
    ic = {}
    for k, v in pairs(values or {}) do
        ic[k] = (type(v) == "table") and ns.DeepCopy(v) or v
    end
    ic.__ovSeedV = ver
    s[frameName] = ic
end

-- True once the below-player icon is seeded at the CURRENT default version (cheap re-seed skip).
function ns.CDMAnchor.BelowIconSeededCurrent(frameName)
    local s = BelowIconStore()
    local ic = s and frameName and s[frameName]
    return (ic and ic.__ovSeedV == (ns.OVERRIDE_SEED_VERSION or 1)) or false
end

-- Per-section "remembered while disabled" stash (persisted under the icon's __ovStash). The cadre shows
-- these greyed when a section's override is OFF; the render ignores them (disabled section inherits the
-- bucket). Survives /reload.
function ns.CDMAnchor.BelowIconStashGet(frameName, key)
    local s = BelowIconStore()
    local ic = s and frameName and s[frameName]
    local st = ic and ic.__ovStash
    return st and st[key]
end
function ns.CDMAnchor.BelowIconStashSet(frameName, key, val)
    local s = BelowIconStore()
    if not s or not frameName then return end
    s[frameName] = s[frameName] or {}
    s[frameName].__ovStash = s[frameName].__ovStash or {}
    s[frameName].__ovStash[key] = val
end

-- ── Per-icon-aware below-player getters (used by TimerIcon) ───────────────────────────────────────
-- Each returns the per-icon override value when the icon is migrated, otherwise the bucket value — so an
-- un-migrated icon reads EXACTLY as before. TimerIcon passes the icon's frame name + resolved bucket dest.
function ns.CDMAnchor.GetDestCfgFor(frameName, bucketDest, key, default)
    return ns.CDMAnchor.BelowIconGet(frameName, bucketDest, key, default)
end

function ns.CDMAnchor.GetDestBorderFor(frameName, bucketDest)
    if not (frameName and ns.CDMAnchor.BelowIconMigrated(frameName)) then
        return ns.CDMAnchor.GetDestBorder(bucketDest)
    end
    local g = function(k, d) return ns.CDMAnchor.BelowIconGet(frameName, bucketDest, k, d) end
    local enabled = g("borderEnabled", true) ~= false
    local color   = g("borderColor", nil) or { r = 0, g = 0, b = 0, a = 1 }
    local size    = g("borderSize", 1) or 1
    return enabled, color, size
end

function ns.CDMAnchor.GetDestGlowFor(frameName, bucketDest)
    if not (frameName and ns.CDMAnchor.BelowIconMigrated(frameName)) then
        return ns.CDMAnchor.GetDestGlow(bucketDest)
    end
    local g = function(k, d) return ns.CDMAnchor.BelowIconGet(frameName, bucketDest, k, d) end
    local enabled = g("glowEnabled", true) ~= false
    local gtype   = g("glowType", "pixel") or "pixel"
    local color   = g("glowColor", nil) or { r = 0.96, g = 1, b = 0, a = 1 }
    return enabled, gtype, color
end

function ns.CDMAnchor.GetDestCdmFlagFor(frameName, bucketDest, key)
    if not (frameName and ns.CDMAnchor.BelowIconMigrated(frameName)) then
        return ns.CDMAnchor.GetDestCdmFlag(bucketDest, key)
    end
    return ns.CDMAnchor.BelowIconGet(frameName, bucketDest, key, false) == true
end

-- ── Tracker title/stacks: own-draw suppression + lazy seed (F4) ───────────────────────────────────
-- The trackers (Defensive/Potion/Healthstone) draw their OWN title/stacks FontStrings. When an icon is in
-- the Cooldown Manager the shared TimerIcon draws those instead (from the per-icon override), so the module
-- must hide its own to avoid a double-draw. These helpers tell a module when to suppress, and seed the
-- override so the in-CDM look starts from the tracker's own config (not the bucket / group default).

-- Has this icon been migrated to the per-icon override for its dest?
function ns.TrackerOverrideMigrated(frameName, cdmDest)
    if not frameName then return false end
    if cdmDest == "belowPlayer" then
        return (ns.CDMAnchor.BelowIconMigrated and ns.CDMAnchor.BelowIconMigrated(frameName)) or false
    end
    local I = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[cdmDest or "essential"]
    return (I and I.IconOverrideMigrated and I.IconOverrideMigrated(frameName)) or false
end

-- Seed the per-icon override (below-player store OR essential/utility group), version-checked internally.
function ns.SeedTrackerOverride(frameName, cdmDest, values)
    if not frameName then return end
    if cdmDest == "belowPlayer" then
        if ns.CDMAnchor.SeedBelowIconOverride then ns.CDMAnchor.SeedBelowIconOverride(frameName, values) end
    else
        local I = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[cdmDest or "essential"]
        if I and I.SeedIconOverride then I.SeedIconOverride(frameName, values) end
    end
end

-- Re-seed an icon's override to the CURRENT default version if it's stale or unseeded; cheap no-op once
-- current (the seed table `seedThunk` is built ONLY when actually needed). Called by the login reload hooks
-- and the render guard so a default-set change applies without opening each tracker's config.
function ns.ReseedTrackerOverride(frameName, cdmDest, seedThunk)
    if not frameName or not seedThunk then return end
    if cdmDest == "belowPlayer" then
        if ns.CDMAnchor.BelowIconSeededCurrent and ns.CDMAnchor.BelowIconSeededCurrent(frameName) then return end
    else
        local I = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[cdmDest or "essential"]
        if not (I and I.SeedIconOverride) then return end
        if I.IconSeededCurrent and I.IconSeededCurrent(frameName) then return end
    end
    ns.SeedTrackerOverride(frameName, cdmDest, seedThunk())
end

-- Should the module hide its own title/stacks (because TimerIcon draws the replacement)? True when the icon
-- is in the CDM AND TimerIcon will draw: below-player always (re-seeding the override to the current default
-- version so it shows the tracker's look, not the bucket default), essential/utility only once migrated.
-- seedValues is an optional thunk returning the {override schema} table — built only when a (re)seed is due.
function ns.TrackerSuppressOwnExtras(icon, frameName, cdmDest, seedValues)
    if not (icon and icon.CDMActive and icon.CDMActive()) then return false end
    if cdmDest == "belowPlayer" then
        if seedValues then ns.ReseedTrackerOverride(frameName, "belowPlayer", seedValues) end
        return true
    end
    -- Essential/Utility: only suppress when the groups engine actually OWNS the dest (TimerIcon draws the
    -- replacement only then). With the engine disabled but the icon migrated + the native viewer shown,
    -- suppressing would blank the title/stacks in both places, so keep our own draw instead.
    return (ns.TrackerOverrideMigrated(frameName, cdmDest)
        and ns.CDMGroups and ns.CDMGroups.OwnsDest and ns.CDMGroups.OwnsDest(cdmDest)) and true or false
end

-- Any reason to own this viewer (an offset, any row size, or an active unlock-drag)?
-- Lets us take it over even when it hosts no icons of ours; with none, Blizzard keeps it.
local function ViewerHasOverride(dest)
    if viewerUnlocked[dest] then return true end
    local c = ViewerCfg(dest)
    if not c then return false end
    if c.x ~= nil or c.y ~= nil then return true end
    if c.rows then
        for _, rs in pairs(c.rows) do
            if (rs.width or 0) > 0 or (rs.height or 0) > 0 then return true end
        end
    end
    return false
end
ns.CDMAnchor.ViewerHasOverride = ViewerHasOverride

function ns.CDMAnchor.IsViewerUnlocked(dest) return viewerUnlocked[dest] == true end

-- Position accessors for the config panel. Coordinates are the viewer's top-centre
-- relative to the SCREEN centre. GetViewerPos reports the placed value, or (when unplaced)
-- the current on-screen position so the inputs always show where it actually is.
function ns.CDMAnchor.GetViewerPos(dest)
    local c = ViewerCfg(dest)
    if c and (c.x ~= nil or c.y ~= nil) then return c.x or 0, c.y or 0 end
    local cont = containers[dest]
    if cont and cont._uuBase then return cont._uuBase.x, cont._uuBase.y end
    local v = ns.GetCDMViewer and ns.GetCDMViewer(dest)
    if v and v.GetCenter then
        local ucx, ucy = UIParent:GetCenter()
        local cx, top = v:GetCenter(), v:GetTop()
        if ucx and cx and top then return cx - ucx, top - ucy end
    end
    return 0, 0
end
-- Setting one axis pins BOTH (the other to its current value) so the viewer is "placed".
function ns.CDMAnchor.SetViewerPos(dest, x, y)
    local c = ViewerCfg(dest); if not c then return end
    local curX, curY = ns.CDMAnchor.GetViewerPos(dest)
    c.x = (x ~= nil) and x or (c.x ~= nil and c.x) or curX
    c.y = (y ~= nil) and y or (c.y ~= nil and c.y) or curY
end
-- Clear the placement (and any legacy offset) -> hands the viewer back to Edit Mode.
function ns.CDMAnchor.ResetViewerPos(dest)
    local c = ViewerCfg(dest); if not c then return end
    c.x, c.y, c.offsetX, c.offsetY = nil, nil, nil, nil
    ns.CDMAnchor.RefreshAll(true)
end

-- Per-row size accessors for the config panel (0 = "use the native size").
function ns.CDMAnchor.GetViewerRowSize(dest, r)
    local c = ViewerCfg(dest)
    local rs = c and c.rows and c.rows[r]
    return (rs and rs.width) or 0, (rs and rs.height) or 0
end
function ns.CDMAnchor.SetViewerRowSize(dest, r, w, h)
    local c = ViewerCfg(dest); if not c then return end
    c.rows = c.rows or {}
    c.rows[r] = c.rows[r] or {}
    if w ~= nil then c.rows[r].width  = w end
    if h ~= nil then c.rows[r].height = h end
end

-- The native CooldownViewer's current per-icon size, so the panel can show it as the
-- starting point before any override. Falls back to the layout's 30x30 default.
function ns.CDMAnchor.NativeIconSize(dest)
    local v = ns.GetCDMViewer and ns.GetCDMViewer(dest)
    if v and v.itemFramePool and v.itemFramePool.EnumerateActive then
        for nf in v.itemFramePool:EnumerateActive() do
            local w, h = nf:GetSize()
            if w and w > 0 then return math.floor(w + 0.5), math.floor((h or w) + 0.5) end
        end
    end
    return 30, 30
end

local function GetContainer(dest)
    local c = containers[dest]
    if not c then
        c = CreateFrame("Frame", "UnbunkUtilityCDM_" .. dest .. "_Container", UIParent)
        c:SetSize(80, 40)
        c:SetMovable(true)
        if c.SetPreventSecretValues then pcall(c.SetPreventSecretValues, c, true) end

        -- Unlock-drag overlay: hidden + click-through by default. When unlocked it sits
        -- above the glued viewer to catch the drag; moving it moves the container (the
        -- viewer follows its anchor) and the dragged delta is folded into the saved
        -- offset on release, after which RefreshAll re-imposes base + offset.
        local ovl = CreateFrame("Frame", nil, c)
        ovl:SetAllPoints(c)
        ovl:SetFrameStrata("DIALOG")
        ovl:EnableMouse(false)
        ovl:Hide()
        ovl:RegisterForDrag("LeftButton")
        local bg = ovl:CreateTexture(nil, "OVERLAY")
        bg:SetAllPoints(ovl)
        bg:SetColorTexture(0.20, 0.55, 1, 0.30)
        ovl:SetScript("OnDragStart", function()
            c._uuDragging = true   -- the layout leaves the anchor alone while we drag
            c:StartMoving()
        end)
        ovl:SetScript("OnDragStop", function()
            c:StopMovingOrSizing()
            c._uuDragging = false
            -- Store the ABSOLUTE top-centre relative to the screen centre (not a delta),
            -- guarded so a momentarily-nil rect can't half-update one axis (the old delta
            -- form errored after setting X, leaving Y stale).
            local cfg = ViewerCfg(dest)
            local ucx, ucy = UIParent:GetCenter()
            local cx, top = c:GetCenter(), c:GetTop()
            if cfg and ucx and cx and top then
                cfg.x = cx - ucx
                cfg.y = top - ucy
            end
            ns.CDMAnchor.RefreshAll(true)
            if ns.OnViewerMoved and ns.OnViewerMoved[dest] then ns.OnViewerMoved[dest]() end
        end)
        c._uuDragOvl = ovl

        containers[dest] = c
    end
    return c
end

-- Unlock / lock a native viewer for manual dragging (Essentials / Utility panels).
-- Unlocking forces a refresh so the addon takes the viewer over right away (even with
-- no icons of ours); locking with a zeroed offset lets it release back to Blizzard.
function ns.CDMAnchor.SetViewerUnlocked(dest, val)
    viewerUnlocked[dest] = val and true or false
    local c = GetContainer(dest)
    if c._uuDragOvl then
        c._uuDragOvl:EnableMouse(viewerUnlocked[dest])
        c._uuDragOvl:SetShown(viewerUnlocked[dest])
    end
    ns.CDMAnchor.RefreshAll(true)
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

-- x,y = TOPLEFT offset from the viewer; w,h (optional) = the row's icon-size override,
-- re-imposed alongside the position so Blizzard's relayout can't reset it.
local function PinNative(nf, viewer, x, y, w, h)
    -- Reuse the pin table in place (this runs per member per tick from BarGroups +
    -- BuffGroups — a fresh table each call was a steady allocation drip). If nothing
    -- placement-relevant changed since last pin, we can also skip the raw re-anchor /
    -- SetSize entirely (the hooks already keep Blizzard from moving it).
    local p = nf._uuPin or {}
    local unchanged = p.viewer == viewer and p.x == x and p.y == y and p.w == w and p.h == h
    p.viewer, p.x, p.y, p.w, p.h = viewer, x, y, w, h
    nf._uuPin = p
    if not CanWrite(nf) then return end
    if unchanged and nf._uuPinHook then return end
    if nf:GetScale() ~= 1 then RawSetScale(nf, 1) end
    if not nf._uuPinHook then
        nf._uuPinHook = true
        hooksecurefunc(nf, "SetPoint", function(self)
            local pin = self._uuPin
            if not pin or self._uuPinApplying or not CanWrite(self) then return end
            self._uuPinApplying = true
            RawClearAllPoints(self)
            RawSetPoint(self, "TOPLEFT", pin.viewer, "TOPLEFT", pin.x, pin.y)
            if pin.w and pin.h then RawSetSize(self, pin.w, pin.h) end
            self._uuPinApplying = false
        end)
        hooksecurefunc(nf, "SetScale", function(self, s)
            if (s or 1) ~= 1 and self._uuPin and CanWrite(self) then RawSetScale(self, 1) end
        end)
        -- Re-impose our pinned size whenever Blizzard resizes the frame (the viewer's relayout can
        -- SetSize/SetWidth/SetHeight WITHOUT a SetPoint, which would otherwise leave some icons at
        -- their larger native size while the rest are at ours). Raw setter: this hook fires from
        -- inside the secure refresh, so a normal SetSize here would taint it (see RawSetSize above).
        local function reimposeSize(self)
            local pin = self._uuPin
            if not (pin and pin.w and pin.h) or self._uuPinSizing or not CanWrite(self) then return end
            if self:GetWidth() ~= pin.w or self:GetHeight() ~= pin.h then
                self._uuPinSizing = true
                RawSetSize(self, pin.w, pin.h)
                self._uuPinSizing = false
            end
        end
        hooksecurefunc(nf, "SetSize", reimposeSize)
        hooksecurefunc(nf, "SetWidth", reimposeSize)
        hooksecurefunc(nf, "SetHeight", reimposeSize)
    end
    nf._uuPinApplying = true
    RawClearAllPoints(nf)
    RawSetPoint(nf, "TOPLEFT", viewer, "TOPLEFT", x, y)
    if w and h then RawSetSize(nf, w, h) end
    nf._uuPinApplying = false
end

-- Hide the addon-drawn CDM border edges on a native frame (used when it drops out of the
-- active set so a stale border doesn't linger; ApplyNativeBorder re-shows it if re-pinned).
local function HideNativeBorder(nf)
    -- A frame ADOPTED by the standalone engine (nf._uuAdopt) owns its border via the engine's StyleFrame pass;
    -- BuffGroups' disabled-mode HideAll runs ReleaseNativePin on the SAME frames every ~0.2s tick, so without
    -- this guard it would strip the engine-drawn border right after each build. Leave adopted frames alone.
    if nf._uuAdopt then return end
    if nf._uuBorderEdges then
        for _, t in pairs(nf._uuBorderEdges) do t:Hide() end
    end
end

local function UnpinNatives(viewer)
    if viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
        for nf in viewer.itemFramePool:EnumerateActive() do nf._uuPin = nil; HideNativeBorder(nf) end
    end
    -- Also clear any frame we pinned via the GetChildren fallback in EnumNativeIcons.
    for _, c in ipairs({ viewer:GetChildren() }) do c._uuPin = nil; HideNativeBorder(c) end
end

-- Draw 4 addon-owned border edge textures on a native frame (display-only regions — safe to
-- create/show even on a protected frame in combat). Shared by the CDM rows (per-dest border)
-- and the Buff-groups module (per-group border). enabled=false hides the edges.
local function DrawFrameBorder(nf, enabled, color, size, outset)
    local edges = nf._uuBorderEdges
    if not enabled then
        if edges then for _, t in pairs(edges) do t:Hide() end end
        return
    end
    if not edges then
        edges = {
            top    = nf:CreateTexture(nil, "OVERLAY", nil, 7),
            bottom = nf:CreateTexture(nil, "OVERLAY", nil, 7),
            left   = nf:CreateTexture(nil, "OVERLAY", nil, 7),
            right  = nf:CreateTexture(nil, "OVERLAY", nil, 7),
        }
        -- Disable texel snapping so a sub-UI-unit (pixel-snapped) edge stays crisp instead of blurring.
        for _, t in pairs(edges) do
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
            if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        end
        nf._uuBorderEdges = edges
    end
    size = math.max(1, math.min(16, size or 1))
    -- Snap the thickness to a whole number of physical pixels so the border stays crisp on fractional UI
    -- scale (the icon frames sit at UIParent scale). Falls back to the raw size if the pixel size isn't
    -- ready. Mirrors Ayije_CDM's Border.lua pixel snapping; the edges also have texel-snap disabled above.
    local px = ns.PixelSize and ns.PixelSize()
    local thickness = (px and px > 0) and (math.max(1, math.floor(size / px)) * px) or size
    color = color or { r = 0, g = 0, b = 0, a = 1 }
    local r, g, b, a = color.r, color.g, color.b, color.a or 1
    -- outset: the edges sit just OUTSIDE the frame so the border frames the icon (used by the
    -- buff groups, where an inset 1px border looked tiny / drawn inside the icon). Default (o=0)
    -- keeps the legacy inset look on the native CDM rows.
    local o = outset and thickness or 0
    edges.top:ClearAllPoints()
    edges.top:SetPoint("TOPLEFT",  nf, "TOPLEFT",  -o,  o)
    edges.top:SetPoint("TOPRIGHT", nf, "TOPRIGHT",  o,  o)
    edges.top:SetHeight(thickness)
    edges.bottom:ClearAllPoints()
    edges.bottom:SetPoint("BOTTOMLEFT",  nf, "BOTTOMLEFT",  -o, -o)
    edges.bottom:SetPoint("BOTTOMRIGHT", nf, "BOTTOMRIGHT",  o, -o)
    edges.bottom:SetHeight(thickness)
    edges.left:ClearAllPoints()
    edges.left:SetPoint("TOPLEFT",    nf, "TOPLEFT",    -o,  o)
    edges.left:SetPoint("BOTTOMLEFT", nf, "BOTTOMLEFT", -o, -o)
    edges.left:SetWidth(thickness)
    edges.right:ClearAllPoints()
    edges.right:SetPoint("TOPRIGHT",    nf, "TOPRIGHT",     o,  o)
    edges.right:SetPoint("BOTTOMRIGHT", nf, "BOTTOMRIGHT",  o, -o)
    edges.right:SetWidth(thickness)
    for _, t in pairs(edges) do t:SetColorTexture(r, g, b, a); t:Show() end
end
ns.CDMAnchor.ApplyFrameBorder = DrawFrameBorder

-- The dest's CDM border around a NON-adopted native row icon (every icon in the dest shares it).
local function ApplyNativeBorder(nf, dest)
    DrawFrameBorder(nf, ns.CDMAnchor.GetDestBorder(dest))
end

-- Pin a native frame to an ARBITRARY anchor (not just a CDM viewer) + release it again —
-- used by the Buff-groups module to move native buff icons into its custom group containers,
-- with the same re-impose hook so Blizzard's relayout can't pull them back.
ns.CDMAnchor.PinNativeTo = PinNative
function ns.CDMAnchor.ReleaseNativePin(nf)
    if nf then nf._uuPin = nil; HideNativeBorder(nf) end
end

-- ── SetParent-ADOPT hosting (buffs) ───────────────────────────────────────────
-- Unlike PinNative (which re-anchors a frame WHILE it stays a child of the live viewer, so the viewer must
-- be kept VISIBLE), AdoptNativeTo REPARENTS the native pool frame onto an engine-owned host frame — so the
-- native viewer can be alpha-0-masked and the adopted frame still renders (it now inherits the HOST's alpha,
-- not the masked viewer's). This is Coolinator's buff model (AuraIconRetail.lua:31), confirmed taint-safe on
-- 12.1.0. Every write is a RAW C method (bypasses taint AND our own hooks); the re-impose
-- hooks re-force parent+point+size when Blizzard's secure RefreshData re-pools the frame back under the viewer.
local function AdoptNativeTo(nf, host, x, y, w, h)
    local a = nf._uuAdopt or {}
    local unchanged = a.host == host and a.x == x and a.y == y and a.w == w and a.h == h
    a.host, a.x, a.y, a.w, a.h = host, x, y, w, h
    nf._uuAdopt = a
    if not CanWrite(nf) then return end
    if unchanged and nf._uuAdoptHook and nf:GetParent() == host then return end   -- nothing to re-impose
    if not nf._uuAdoptHook then
        nf._uuAdoptHook = true
        -- Re-impose PARENT: Blizzard re-pools/reparents frames under the viewer on RefreshData; force them
        -- back to our host so the alpha-0 viewer can never reclaim (and thus hide) an adopted buff. Raw
        -- setters bypass this same hook (no recursion) and bypass taint from inside the secure refresh.
        hooksecurefunc(nf, "SetParent", function(self)
            local ad = self._uuAdopt
            if not ad or self._uuAdoptApplying or not CanWrite(self) then return end
            if self:GetParent() ~= ad.host then
                self._uuAdoptApplying = true
                RawSetParent(self, ad.host)
                RawClearAllPoints(self)
                RawSetPoint(self, "TOPLEFT", ad.host, "TOPLEFT", ad.x, ad.y)
                if ad.w and ad.h then RawSetSize(self, ad.w, ad.h) end
                self._uuAdoptApplying = false
            end
        end)
        hooksecurefunc(nf, "SetPoint", function(self)   -- re-impose POINT (relative to host)
            local ad = self._uuAdopt
            if not ad or self._uuAdoptApplying or not CanWrite(self) then return end
            self._uuAdoptApplying = true
            RawClearAllPoints(self)
            RawSetPoint(self, "TOPLEFT", ad.host, "TOPLEFT", ad.x, ad.y)
            self._uuAdoptApplying = false
        end)
        local function reSize(self)                      -- re-impose SIZE (mirrors PinNative)
            local ad = self._uuAdopt
            if not (ad and ad.w and ad.h) or self._uuAdoptSizing or not CanWrite(self) then return end
            if self:GetWidth() ~= ad.w or self:GetHeight() ~= ad.h then
                self._uuAdoptSizing = true; RawSetSize(self, ad.w, ad.h); self._uuAdoptSizing = false
            end
        end
        hooksecurefunc(nf, "SetSize",   reSize)
        hooksecurefunc(nf, "SetWidth",  reSize)
        hooksecurefunc(nf, "SetHeight", reSize)
        hooksecurefunc(nf, "SetScale", function(self, s)
            if (s or 1) ~= 1 and self._uuAdopt and CanWrite(self) then RawSetScale(self, 1) end
        end)
    end
    nf._uuAdoptApplying = true
    RawSetParent(nf, host)
    RawClearAllPoints(nf)
    RawSetPoint(nf, "TOPLEFT", host, "TOPLEFT", x, y)
    if w and h then RawSetSize(nf, w, h) end
    if nf:GetScale() ~= 1 then RawSetScale(nf, 1) end
    nf._uuAdoptApplying = false
end
ns.CDMAnchor.AdoptNativeTo = AdoptNativeTo

-- Hand an adopted native frame BACK to its viewer (switch-to-native / group release). RawSetParent back so
-- the viewer's own layout re-owns it; clear _uuAdopt so the re-impose hooks go inert. NEVER Hide/Show it
-- (those are the durable-state taint vectors) — it keeps Blizzard's shown-state; the viewer re-lays-it-out.
function ns.CDMAnchor.ReleaseNativeAdopt(nf, viewer)
    if not nf then return end
    local had = nf._uuAdopt
    nf._uuAdopt = nil
    if had and CanWrite(nf) then
        nf._uuAdoptApplying = true
        RawSetParent(nf, viewer or _G.BuffIconCooldownViewer or UIParent)
        RawClearAllPoints(nf)
        nf._uuAdoptApplying = false
    end
    HideNativeBorder(nf)
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
    -- OWNERSHIP GUARD (defensive): when the "Cooldown groups" engine OR the standalone engine owns this
    -- dest it drives the frames itself — never lay out the old bucket grid here. DoRefresh already keeps
    -- an owned dest out of `groups`, so this is normally unreached; it protects any direct caller.
    if (ns.CDMGroups and ns.CDMGroups.OwnsDest and ns.CDMGroups.OwnsDest(dest)) or EngineOwnsDest(dest) then
        for _, d in ipairs(list) do if d.apply then pcall(d.apply) end end
        return
    end
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

    -- Native SEQUENCE in visual order (top->bottom, L->R).
    local natives = {}        -- sequence of { native = nf }
    local refW, refH, gotRef = 30, 30, false
    for _, row in ipairs(rows) do
        for _, nf in ipairs(row) do
            if not gotRef then
                local w, h = nf:GetSize()
                if w and w > 0 then refW, refH, gotRef = w, h, true end
            end
            natives[#natives + 1] = { native = nf }
        end
    end
    local nNat = #natives

    -- Per-row cap so our icons "count as slots" and push natives to the next row.
    local iconLimit = viewer.iconLimit or 0
    if iconLimit <= 0 then iconLimit = (rows[1] and #rows[1]) or math.max(nNat, 1) end
    if iconLimit < 1 then iconLimit = 1 end

    -- Our shown icons with their desired (row, side).
    local mine = {}
    for _, d in ipairs(list) do
        if d.frame and d.frame:IsShown() then
            mine[#mine + 1] = { d = d, row = math.max(1, d.getCfg("cdmRow") or 1),
                                atEnd = IsAtEnd(d.getCfg("cdmAtEnd")) }
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
    -- BOTH sides are laid order-ascending LEFT->RIGHT so the stored order matches the on-screen order
    -- (index 1 = leftmost), keeping end-anchored icons consistent in this bucket-fallback layout.
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
            -- natives[ni] is already a descriptor ({ native = nf } | { d = applier }).
            if not grid[r][c] then grid[r][c] = natives[ni]; ni = ni + 1 end
        end
    end

    -- Build per-row item lists + measure content. Each row uses its own icon size
    -- (the saved override for this dest/row, else the native slot refW/refH), so rows
    -- can differ in height and the natives are resized to match in PinNative below.
    local rowItems, rowW, rowSzW, rowSzH, contentW, contentH = {}, {}, {}, {}, 0, 0
    for r = 1, nRows do
        local items = {}
        for c = 1, iconLimit do if grid[r][c] then items[#items + 1] = grid[r][c] end end
        rowItems[r] = items
        local rw, rh = ViewerRowSize(dest, r, refW, refH)
        rowSzW[r], rowSzH[r] = rw, rh
        local w = #items * rw + math.max(0, #items - 1) * padX
        rowW[r] = w
        if w > contentW then contentW = w end
        contentH = contentH + rh
    end
    contentH = contentH + math.max(0, nRows - 1) * padY

    -- Take ownership: container at the viewer's anchor (+ our placement offset), sized
    -- to content. Capturing the anchor and gluing the viewer touch the protected viewer,
    -- so do them out of combat only; the container resize/move (our frame) is always safe
    -- and the glued viewer follows it.
    local container = GetContainer(dest)
    if not incombat then CaptureBase(viewer, container) end
    if not container._uuBase then return end
    container:SetSize(math.max(1, contentW), math.max(1, contentH))
    local b = container._uuBase
    -- Anchor the top-centre at the placed screen-centre position (else the captured
    -- EditMode base). b.rp is CENTER, so the saved x/y read straight off the screen
    -- centre. Skipped only DURING an active unlock-drag (StartMoving owns it then); the
    -- drag writes the absolute position on release, re-imposed here next pass.
    if not container._uuDragging then
        local px, py = ViewerPos(dest)
        container:ClearAllPoints()
        container:SetPoint(b.p, b.rel, b.rp, px or b.x, py or b.y)
    end
    if not incombat then GlueViewer(viewer, container) end

    -- Clear every existing pin first, then re-pin only the current grid: a native
    -- that dropped out of the active set (cooldown used mid-combat) must not keep
    -- re-imposing its old offset and overlap our icon.
    UnpinNatives(viewer)

    -- Place each row centred within contentW, anchored to the viewer's TOPLEFT, using
    -- the row's own icon size for both natives (resized in PinNative) and our icons.
    local yTop = 0
    for r = 1, nRows do
        local items = rowItems[r]
        local rw, rh = rowSzW[r], rowSzH[r]
        local x = (contentW - rowW[r]) / 2
        local y = -yTop
        for _, c in ipairs(items) do
            if c.native then
                PinNative(c.native, viewer, x, y, rw, rh)
                ApplyNativeBorder(c.native, dest)
            elseif c.d and c.d.frame then
                if c.d.setSize then c.d.setSize(rw, rh) end
                c.d.frame:ClearAllPoints()
                c.d.frame:SetPoint("TOPLEFT", viewer, "TOPLEFT", x, y)
            end
            x = x + rw + padX
        end
        yTop = yTop + rh + padY
    end
end

-- ── Fade-along with Ayije_CDM ────────────────────────────────────────────────
-- Ayije fades the native CooldownViewer item frames; our injected icons are
-- separate frames (parented to UIParent), so they wouldn't fade with them. Ayije
-- exposes a public extension point — CDM.Fading:RegisterTarget(dbKey, fn) calls
-- fn(alpha) on every fade step — so we register our icons there. Essential AND the
-- below-player row follow the Essential viewer's fade; Utility follows Utility's.
local function SetDestAlpha(dest, a)
    -- L2: in engine mode the engine hosts the essential/utility trackers and keeps them fully visible;
    -- the native fade (viewer masked) must not drive OUR frames' alpha down.
    if EngineOwnsDest(dest) then return end
    a = a or 1   -- defensive: never pass nil to SetAlpha if an external alpha is missing
    for _, d in ipairs(appliers) do
        if d.frame and d.getCfg and d.getCfg("includeInCdm")
            and (d.getCfg("cdmDest") or "essential") == dest then
            d.frame:SetAlpha(a)
        end
    end
end

local function AyijeFading()
    local A = _G.Ayije_CDM
    local F = A and A.Fading
    return (F and F.RegisterTarget) and F or nil
end

-- Re-apply Ayije's CURRENT fade alpha to our icons after a layout pass, so an icon
-- that just appeared mid-fade matches the faded state instead of popping to full.
local function ReapplyFade()
    -- Cooldown Manager off -> icons are free (TimerIcon's free ApplyPosition resets
    -- their alpha to 1), so never apply the native viewer's fade to them.
    if not ns.IsCDMEnabled() then return end
    local F = AyijeFading()
    if not (F and F.GetAlpha) then return end
    local essA = F:GetAlpha("fadingEssential")
    SetDestAlpha("essential", essA)
    SetDestAlpha("belowPlayer", essA)
    SetDestAlpha("utility", F:GetAlpha("fadingUtility"))
end

local fadeHooked = false
local function HookAyijeFading()
    if fadeHooked then return end
    local F = AyijeFading()
    if not F then return end
    fadeHooked = true
    F:RegisterTarget("fadingEssential", function(a)
        SetDestAlpha("essential", a)
        SetDestAlpha("belowPlayer", a)
    end)
    F:RegisterTarget("fadingUtility", function(a)
        SetDestAlpha("utility", a)
    end)
    ReapplyFade()   -- sync immediately in case fading is already active
end

-- ── Refresh ──────────────────────────────────────────────────────────────────
-- Layout signature of everything that affects OUR placement (which icons are
-- shown + their dest/row/atEnd, reorder map, below-row geometry, viewer shown
-- state). A non-forced refresh whose signature is unchanged is a no-op: this is
-- what kills the steady-state cost of the 0.5s trackers poking RefreshAll ~ every
-- tick. Native cooldown changes are NOT in the signature — they arrive via the
-- viewer Layout/RefreshLayout hooks, which pass force=true so a re-pin still runs.
local lastSig = nil
local sigParts = {}                       -- reused scratch: built then table.concat'd to a fresh string each pass
local SIG_BELOW_BUCKETS = { "front", "end" }
local SIG_VIEWERS = { "essential", "utility" }
local function ComputeSig()
    local p = sigParts; wipe(p)
    for _, d in ipairs(appliers) do
        if d.frame and d.getCfg and d.getCfg("includeInCdm")
            and d.frame.IsShown and d.frame:IsShown() then
            p[#p + 1] = (d.frame:GetName() or tostring(d.frame))
                .. "/" .. tostring(d.getCfg("cdmDest"))
                .. "/" .. tostring(d.getCfg("cdmRow"))
                .. "/" .. tostring(d.getCfg("cdmAtEnd"))
        end
    end
    table.sort(p)
    -- Stable order (NOT pairs()) so identical state always yields the identical
    -- signature string — otherwise the no-op skip could be defeated by hash order.
    for _, k in ipairs(ns.CDM_DEST_ORDER) do
        local vname = ns.CDM_VIEWER[k]
        if vname then
            local v = _G[vname]
            p[#p + 1] = vname .. ((v and v.IsShown and v:IsShown()) and "=1" or "=0")
        end
    end
    local map = ns.db and ns.db.profile and ns.db.profile.cdmOrder
    if map then
        local mk = {}
        for k, val in pairs(map) do mk[#mk + 1] = tostring(k) .. ":" .. tostring(val) end
        table.sort(mk)
        p[#p + 1] = "O" .. table.concat(mk, ",")
    end
    local c = ns.db and ns.db.profile and ns.db.profile.cdmBelowRow
    if c then
        -- Bucket-agnostic placement (manual offsets), then each bucket's layout-affecting keys
        -- (size / spacing / grow / static) so a per-bucket edit re-lays-out on a non-forced refresh.
        p[#p + 1] = "B" .. tostring(c.offsetX) .. "," .. tostring(c.offsetY)
            .. "," .. tostring(c.endOffsetX) .. "," .. tostring(c.endOffsetY)
            .. "," .. (c.enabled ~= false and "1" or "0")   -- master row toggle (default-true)
        for _, bucket in ipairs(SIG_BELOW_BUCKETS) do
            local w, h, gap, grow, static = BelowBucketLayout(bucket)
            p[#p + 1] = bucket:sub(1, 1) .. tostring(w) .. "x" .. tostring(h)
                .. "," .. tostring(gap) .. "," .. tostring(grow) .. "," .. tostring(static)
        end
    end
    p[#p + 1] = belowUnlocked and "U1" or "U0"
    -- Per-viewer (essential/utility) placement + size overrides + unlock state, so a
    -- config edit (or unlock) re-lays-out — taking over or releasing the viewer.
    local cv = ns.db and ns.db.profile and ns.db.profile.cdmViewer
    for _, dn in ipairs(SIG_VIEWERS) do
        local v = cv and cv[dn]
        local s = dn .. (viewerUnlocked[dn] and "U" or "L")
        if v then
            s = s .. "=" .. tostring(v.x) .. "," .. tostring(v.y)
            if v.rows then
                local rk = {}
                for r, rs in pairs(v.rows) do
                    rk[#rk + 1] = r .. ":" .. tostring(rs.width) .. "x" .. tostring(rs.height)
                end
                table.sort(rk)
                s = s .. ";" .. table.concat(rk, ",")
            end
        end
        p[#p + 1] = s
    end
    -- Whether the game's Cooldown Manager is on: toggling it in the options must
    -- change the signature so a (non-forced) refresh re-lays-out every icon.
    p[#p + 1] = ns.IsCDMEnabled() and "CDM1" or "CDM0"
    return table.concat(p, "|")
end

-- Hoisted out of DoRefresh so the per-pass pcall doesn't allocate a fresh closure
-- (this runs up to ~10x/sec). owned() is likewise module-level — it captured nothing.
-- OWNERSHIP GUARD: when the NEW "Cooldown groups" engine is enabled for a dest
-- (ns.CDMGroups.OwnsDest), it takes over that native viewer (e.g. EssentialCooldownViewer)
-- and drives its frames into movable group containers. The OLD bucket system here must then
-- NOT also route icons into that viewer or take it over.
-- The standalone CDM ENGINE (ns.CDMMode "engine") likewise OWNS essential/utility: it hosts the CDM
-- trackers in its own group layout, so this old bucket system must not pin/route them into the (masked)
-- native viewer. Symmetric with CDMGroups.OwnsDest — see EngineOwnsDest near the top of the file.
local function owned(dest)
    return (ns.CDMGroups and ns.CDMGroups.OwnsDest and ns.CDMGroups.OwnsDest(dest))
        or EngineOwnsDest(dest) or false
end

local function DoRefreshBody(force)
    -- L2 bridge (must run BEFORE the no-change early-out below): in engine mode, poke the engine to
    -- re-collect its hosted trackers on EVERY refresh. A tracker becoming CDM-eligible/shown AFTER the last
    -- engine rebuild — e.g. an equipped trinket's on-use spell resolving (cdmEligible flips nil→true), or a
    -- tracker showing/hiding on its own 0.5s tick — does NOT move CDMAnchor's own native-row signature, so
    -- it would be missed here until a REBUILD event or a manual mode switch (which is why it only folded in
    -- "on the 2nd try"). ScheduleRebuild is coalesced and the engine's own ComputeSig gate keeps this cheap
    -- (a full BuildLayout runs only on a real membership change); the tracker's tick calls RefreshAll ~2Hz.
    if ns.CDMMode and ns.CDMMode.IsEngine and ns.CDMMode.IsEngine()
        and ns.CDMEngine and ns.CDMEngine.Layout and ns.CDMEngine.Layout.ScheduleRebuild then
        ns.CDMEngine.Layout.ScheduleRebuild()
    end
    if force then
        -- Forced pass re-pins unconditionally; its ComputeSig result is unused, so skip
        -- the cost. Drop the baseline too: the next non-forced pass recomputes from scratch.
        lastSig = nil
    else
        local sig = ComputeSig()
        if sig == lastSig then return end  -- nothing placement-relevant changed
        lastSig = sig
    end
    local groups, hasBelow = {}, false
    -- Cooldown Manager off in the options -> treat every icon as free (inc=false),
    -- so they all fall to the d.apply free-placement branch and any owned viewer is
    -- released below. Evaluated once per pass.
    local cdmOn = ns.IsCDMEnabled()
    -- owned() (module-level): an icon destined for an owned dest falls through to free
    -- placement (d.apply), and the override-takeover below skips it. The release loop
    -- further down still gives a one-time clean handoff (UnpinNatives) the first time
    -- ownership flips, after which the viewer is no longer _uuGlued and the loop is inert.
    for _, d in ipairs(appliers) do
        local inc  = cdmOn and d.getCfg and d.getCfg("includeInCdm")
        local dest = (d.getCfg and d.getCfg("cdmDest")) or "essential"
        if d.frame and d.getCfg and d.getCfg("includeInCdm") and owned(dest) then
            -- The NEW groups engine OWNS this dest and folds this opted-in tracker into its group
            -- layout as a full member (it SetPoints/SIZES the frame in RefreshLayout). So SKIP it
            -- entirely here: do NOT route it to d.apply free placement (which would re-anchor it to
            -- a free CENTER point and fight the engine 2x/sec). The engine positions it; out of that
            -- ownership it falls through to the branches below exactly as before. (Tested against
            -- includeInCdm directly, not cdmOn — the engine ignores the legacy CDM-enabled CVar.)
        elseif d.frame and inc and not owned(dest) and dest == "belowPlayer" then
            if ns.CDMAnchor.IsBelowEnabled() then
                hasBelow = true
            else
                -- Master below-player toggle OFF: the row is disabled, so its icons simply DON'T
                -- render (you can still assign them; they just won't show). Hide immediately for a
                -- snappy toggle; each tracker's own Show/ApplyVisuals gate keeps them hidden after.
                d.frame:Hide()
            end
        elseif d.frame and inc and not owned(dest) and ns.GetCDMViewer(dest) then
            local g = groups[dest]
            if not g then g = { viewer = ns.GetCDMViewer(dest), list = {} }; groups[dest] = g end
            g.list[#g.list + 1] = d
        elseif d.apply then
            local ok, err = pcall(d.apply)
            if not ok then ns.Print("CDM anchor error: " .. tostring(err)) end
        end
    end
    -- Take over essential/utility even with NO icons of ours when the user set a
    -- placement offset / per-row size (or unlocked it to drag) — so those overrides
    -- actually apply. With no override the viewer is left to Blizzard and released below.
    -- Skipped for a dest the new groups engine owns (it manages that viewer itself).
    if cdmOn then
        for _, dest in ipairs({ "essential", "utility" }) do
            if not groups[dest] and not owned(dest) and ns.CDMAnchor.ViewerHasOverride(dest) then
                local v = ns.GetCDMViewer(dest)
                if v and v.IsShown and v:IsShown() then
                    groups[dest] = { viewer = v, list = {} }
                end
            end
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
    -- Keep our icons matching Ayije's current fade alpha (icons just (re)laid out
    -- would otherwise pop to full opacity mid-fade).
    pcall(ReapplyFade)
    -- (The L2 engine re-collect bridge runs at the TOP of this function, before the no-change early-out.)
end

local refreshing = false
local function DoRefresh(force)
    if refreshing then return end  -- re-entrancy guard (ApplyPosition calls back)
    -- We DON'T bail in combat: only the viewer glue is protected (skipped in combat
    -- inside LayoutCDMRow); everything else (container/pins/our icons) updates live
    -- so the slot row stays in sync when natives appear/disappear mid-fight.
    refreshing = true
    -- Body in a pcall so a throwing getCfg can never leave `refreshing` stuck true
    -- (which would soft-lock every later refresh until /reload).
    local rok, rerr = pcall(DoRefreshBody, force)
    refreshing = false
    if not rok then ns.Print("CDM refresh error: " .. tostring(rerr)) end
end

-- Public entry point. Coalesces every caller within a short window (the 0.5s
-- trackers, viewer Layout/RefreshLayout hooks, show/hide, config edits, fade) into
-- ONE layout pass instead of running the heavy re-pin/re-glue per call.
-- force=true (native relayout / combat-end / login / EditMode-exit) bypasses the
-- no-change signature skip so a real re-pin always happens.
--
-- THROTTLE: a native viewer fires Layout/RefreshLayout every frame (cooldown swipe
-- animation) while one of our icons is pinned to its row, and each fire forces a
-- RefreshAll. Coalescing only to the next frame (After 0) therefore still ran a
-- full forced DoRefresh at ~60 Hz — a 200-300 KB/s allocation storm from a single
-- CDM-row icon (e.g. the trinket). Coalescing over REFRESH_THROTTLE instead caps
-- that at ~10 Hz: a real native-row change is still re-pinned within 0.1s
-- (imperceptible — our icons anchor RELATIVE to the native edge icon, so pure
-- movement is followed for free between passes), but the per-frame storm is gone.
local refreshScheduled = false
local forceNext = false
local REFRESH_THROTTLE = 0.1
function ns.CDMAnchor.RefreshAll(force)
    if force then forceNext = true end
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(REFRESH_THROTTLE, function()
        refreshScheduled = false
        local fn = forceNext
        forceNext = false
        DoRefresh(fn)
    end)
end

-- ── Follow the native viewers' relayout / move ───────────────────────────────
-- The native viewers fire RefreshLayout/Layout CONSTANTLY (on every cooldown-swipe
-- frame while anything is on cooldown), but our placement only needs to change when
-- the native icon SET changes (one added / removed / moved → the grid shifts). Gate
-- the forced re-pin on the cheap content signature so cosmetic ticks (same icons,
-- same spots) cost nothing, instead of rebuilding the whole grid 10-60x/sec — that
-- redundant rebuild was a 100-300 KB/s allocation storm whenever a CDM-row icon
-- (e.g. a trinket pinned to the Essential row) was shown.
local function OnNativeRelayout(viewer)
    -- TAINT + redundancy guard: this hook fires from INSIDE Blizzard's secure CooldownViewer:RefreshData.
    -- When the CDMGroups engine OR the standalone engine OWNS this dest it drives the viewer's frames itself,
    -- so the old bucket re-pin is redundant — and the NativeSig + RefreshAll(true) below run a LOT of insecure
    -- work inside Blizzard's secure refresh, tainting its subsequent aura/totem secret reads ("tainted by
    -- UnbunkUtility"). Bail out for an owned dest so none of that heavy work runs in the secure path.
    if ns.CDM_VIEWER then
        local nm = viewer.GetName and viewer:GetName()
        if nm then
            for dest, vname in pairs(ns.CDM_VIEWER) do
                if vname == nm then
                    if owned(dest) then return end   -- CDMGroups OR standalone engine owns it: skip the secure-pass re-pin
                    break
                end
            end
        end
    end
    local n, acc = NativeSig(viewer)
    if n ~= viewer._uuNatN or acc ~= viewer._uuNatAcc then
        viewer._uuNatN, viewer._uuNatAcc = n, acc
        ns.CDMAnchor.RefreshAll(true)
    end
end

local hooked = {}
local function HookViewers()
    for _, name in pairs(ns.CDM_VIEWER) do
        local v = _G[name]
        if v and not hooked[name] then
            hooked[name] = true
            if v.RefreshLayout then hooksecurefunc(v, "RefreshLayout", OnNativeRelayout) end
            if v.Layout       then hooksecurefunc(v, "Layout",       OnNativeRelayout) end
            -- Drop our pin when the pool recycles an item frame for new content, so
            -- a stale offset is never re-imposed before the next LayoutCDMRow.
            if v.OnAcquireItemFrame then
                hooksecurefunc(v, "OnAcquireItemFrame", function(_, itemFrame)
                    -- Drop our pin AND the CDMGroups engine's cached identity key (_uuLastGoodKey): the pool
                    -- just recycled this frame for new content, so neither a stale offset nor a stale
                    -- stable-key may survive into the next layout pass (the key is a private field the engine
                    -- reads for its combat secret-value early-out; clearing it here is a no-op for other frames).
                    if itemFrame then itemFrame._uuPin = nil; itemFrame._uuLastGoodKey = nil end
                end)
            end
        end
    end
end

-- Last-seen Cooldown Manager enable state, so a CVAR_UPDATE only does work when it
-- actually flips (the event fires for every CVar). Seeded on the first login pass.
local lastCdmEnabled

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CVAR_UPDATE")
f:SetScript("OnEvent", function(_, event, cvarName)
    if event == "CVAR_UPDATE" then
        -- CVAR_UPDATE fires for EVERY CVar; only the cooldown-viewer toggle can change
        -- our placement. Early-out on the changed-CVar name so unrelated events don't
        -- even pay the GetCVarBool read below.
        if cvarName and cvarName ~= "cooldownViewerEnabled" then return end
        -- React only when the Cooldown Manager enable state flips: force a re-layout
        -- (every icon moves between CDM and free placement) and rebuild any open
        -- tracker config so its greyed checkbox + CDM/free controls update live.
        local nowOn = ns.IsCDMEnabled()
        if nowOn ~= lastCdmEnabled then
            lastCdmEnabled = nowOn
            ns.CDMAnchor.RefreshAll(true)
            if ns.RebuildActiveModule then ns.RebuildActiveModule() end
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- Reconcile EditMode state that may have flipped during combat so it can't
        -- get stuck (which would freeze all re-imposition).
        editModeActive = (EditModeManagerFrame and EditModeManagerFrame:IsShown()) or false
        if not editModeActive then ns.CDMAnchor.RefreshAll(true) end
        return
    end
    HookViewers()
    HookAyijeFading()   -- register our icons with Ayije_CDM's fade pipeline (if present)
    lastCdmEnabled = ns.IsCDMEnabled()   -- seed so the first CVAR_UPDATE flip is detected
    C_Timer.After(0.1, function() ns.CDMAnchor.RefreshAll(true) end)
end)

-- ── Edit Mode: match each managed viewer's husk to its Group 1 block ──────────
-- Our engines pin the real cooldown icons to their own "Group 1" container, so in
-- Blizzard's Edit Mode the native viewer's selection rectangle no longer reflects what
-- the user actually sees. While Edit Mode is open we glue each of the 4 managed viewers
-- (Essential / Utility / Tracked Buffs / Tracked Bars) to EXACTLY cover its Group 1
-- container — a two-corner anchor, so the husk tracks Group 1's size AND position live —
-- and restore the viewer's native anchor + layout on exit.
--
-- TAINT NOTE: unlike GlueViewer / LayoutCDMRow above (which deliberately BAIL while
-- editModeActive), this path intentionally writes these protected viewer anchors WHILE Edit
-- Mode is open. That is acceptable because: (1) the writes go through hooksecurefunc post-hooks
-- + raw C methods, so the hook's taint does not propagate into Blizzard's secure Edit Mode
-- execution; (2) Edit Mode's SaveLayouts serialises each system's own secure systemInfo, NOT a
-- frame's live (tainted) anchor, so moving/saving OTHER systems is unaffected; (3) these same 4
-- viewers are already persistently tainted every session by CDMEditModeLock's SetMovable(false);
-- and (4) all writes run OUT of combat only (Edit Mode is always out of combat).
-- INVARIANT: this husk-move is safe ONLY because CDMEditModeLock keeps these exact 4 viewers
-- non-movable + dialog-hidden in Edit Mode (so the moved husk can never be saved back as the
-- native anchor). Keep EM_VIEWERS and CDMEditModeLock's LOCK_NAMES in lockstep.
local EM_VIEWERS = {
    { name = ns.CDM_VIEWER.essential,  g1 = function() local i = ns.CDMGroups and ns.CDMGroups.essential; return i and i.GetContainer and i.GetContainer(1) end },
    { name = ns.CDM_VIEWER.utility,    g1 = function() local i = ns.CDMGroups and ns.CDMGroups.utility;   return i and i.GetContainer and i.GetContainer(1) end },
    { name = "BuffIconCooldownViewer", g1 = function() return ns.BuffGroups and ns.BuffGroups.GetContainer and ns.BuffGroups.GetContainer(1) end },
    { name = "BuffBarCooldownViewer",  g1 = function() return ns.BarGroups  and ns.BarGroups.GetContainer  and ns.BarGroups.GetContainer(1)  end },
}

-- A Group 1 container is a usable anchor only once it has been laid out with real bounds
-- (shown, positioned, width > 1). Until then we leave the viewer at its native spot.
local function Group1Ready(c)
    return (c and c.IsShown and c:IsShown() and c.GetWidth and (c:GetWidth() or 0) > 1 and c:GetLeft()) and true or false
end

local function GlueViewerToGroup1(v, c)
    v._uuEMG1 = c
    if not v._uuEMHook then
        v._uuEMHook = true
        -- Re-impose if Blizzard / EditMode re-anchors the viewer while we own it for Edit Mode.
        hooksecurefunc(v, "SetPoint", function(self, _, relTo)
            if not editModeActive or self._uuEMApplying or InCombatLockdown() then return end
            local g1 = self._uuEMG1
            if not g1 or relTo == g1 then return end
            self._uuEMApplying = true
            RawClearAllPoints(self)
            RawSetPoint(self, "TOPLEFT",     g1, "TOPLEFT",     0, 0)
            RawSetPoint(self, "BOTTOMRIGHT", g1, "BOTTOMRIGHT", 0, 0)
            self._uuEMApplying = false
        end)
    end
    v._uuEMApplying = true
    RawClearAllPoints(v)
    RawSetPoint(v, "TOPLEFT",     c, "TOPLEFT",     0, 0)
    RawSetPoint(v, "BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    v._uuEMApplying = false
end

-- Capture the viewer's native anchor ONCE (before we override it) so exit can restore it.
-- Returns true once a non-empty anchor is captured. A viewer with ZERO points must NOT be
-- glued (we'd have nothing to restore and would strand it point-less at the screen origin).
local function SaveViewerPoints(v)
    if v._uuEMSaved then return true end
    local saved = {}
    for i = 1, (v.GetNumPoints and v:GetNumPoints() or 0) do
        saved[i] = { v:GetPoint(i) }
    end
    if #saved == 0 then return false end
    v._uuEMSaved = saved
    return true
end

local function RestoreViewerPoints(v)
    local saved = v._uuEMSaved
    v._uuEMG1, v._uuEMSaved = nil, nil
    if not saved then return end
    v._uuEMApplying = true
    RawClearAllPoints(v)
    for _, pt in ipairs(saved) do
        if pt[1] then RawSetPoint(v, pt[1], pt[2], pt[3], pt[4], pt[5]) end
    end
    v._uuEMApplying = false
    if v.RefreshLayout then pcall(v.RefreshLayout, v) end   -- snap the husk back to its native size
end

local function ApplyEditModeOverlay()
    if InCombatLockdown() then return end
    for _, e in ipairs(EM_VIEWERS) do
        local v = e.name and _G[e.name]
        if v then
            local c = e.g1()
            -- Only take over a viewer we can faithfully restore (SaveViewerPoints captured a
            -- real native anchor) AND whose Group 1 is actually laid out.
            if Group1Ready(c) and SaveViewerPoints(v) then
                GlueViewerToGroup1(v, c)
            end
        end
    end
end

local emRestoreEv
local function ClearEditModeOverlay()
    -- Combat can force-close Edit Mode; the protected SetPoint restore must wait for safety.
    if InCombatLockdown() then
        emRestoreEv = emRestoreEv or CreateFrame("Frame")
        emRestoreEv:RegisterEvent("PLAYER_REGEN_ENABLED")
        emRestoreEv:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            ClearEditModeOverlay()
        end)
        return
    end
    for _, e in ipairs(EM_VIEWERS) do
        local v = e.name and _G[e.name]
        if v and v._uuEMSaved then RestoreViewerPoints(v) end
    end
end

-- While EditMode is open we release the viewers (so the user can drag them
-- normally); on close we re-capture their new position and take ownership again.
-- EnterEditMode/ExitEditMode are wired to BOTH EditModeManagerFrame OnShow/OnHide AND the
-- EventRegistry EditMode.Enter/Exit signals (Blizzard fires both on one open/close), so guard
-- on editModeActive to run the body exactly once per transition.
local function EnterEditMode()
    if editModeActive then return end
    editModeActive = true
    if not InCombatLockdown() then
        ReleaseAll()
        ApplyEditModeOverlay()
        -- Group 1's preview block may not be sized at the very instant Edit Mode opens; retry
        -- shortly so a late-laid-out block still gets matched (the live anchor then tracks it).
        C_Timer.After(0.2, function() if editModeActive then ApplyEditModeOverlay() end end)
    end
end
local function ExitEditMode()
    if not editModeActive then return end
    editModeActive = false
    ClearEditModeOverlay()
    -- Drop the captured anchors so the next refresh re-reads the (possibly moved)
    -- EditMode position instead of restoring the stale one.
    for _, c in pairs(containers) do c._uuBase = nil end
    C_Timer.After(0.1, function() ns.CDMAnchor.RefreshAll(true) end)
end

if _G.EditModeManagerFrame then
    EditModeManagerFrame:HookScript("OnShow", EnterEditMode)
    EditModeManagerFrame:HookScript("OnHide", ExitEditMode)
end
if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", EnterEditMode, ns)
    EventRegistry:RegisterCallback("EditMode.Exit",  ExitEditMode,  ns)
end
