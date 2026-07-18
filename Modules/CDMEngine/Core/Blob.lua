-- Modules/CDMEngine/Core/Blob.lua
--
-- Phase 0 of the standalone "Coolinator-like" CDM engine (ns.CDMEngine). This module is
-- ISOLATED: it does NOT touch the native-reuse modules (CDMGroups/BuffGroups/BarGroups). It is the
-- foundation the rest of the engine builds on — the ability to READ, DECODE and (safely) WRITE the
-- CooldownViewer's persistent LAYOUT blob: the config that decides WHICH cooldowns the CDM tracks
-- and in which category (Essential / Utility / TrackedBuff / TrackedBar). Today we only READ what
-- Blizzard's own UI configured; this lets us eventually PROGRAM it.
--
-- The blob is `"<envelopeVersion>|<base64(deflate(cbor(table)))>"`. We reuse the exact native
-- serialization pipeline we already adopted for profiles (C_EncodingUtil) plus the taint scrub
-- (ns.PurgeTaintedKey) — so the whole codec + write path is already ours, no new libs.
--
-- Schema (reverse-engineered from the native serializer; matches Coolinator v94): the decoded blob
-- is a POSITIONAL array — [1] = schema version (4 or 5), then the top-level fields in Blob.FIELD.
-- Each layout is itself positional (Blob.LAYOUT_FIELD).
--
-- SAFETY: Read / Encode / VerifyRoundTrip never mutate anything. Write() DOES mutate the live CDM
-- config and is guarded (out of combat + not in Edit Mode); nothing calls it automatically yet.

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
local Blob = {}
E.Blob = Blob

local C_EncodingUtil   = C_EncodingUtil
local C_CooldownViewer = C_CooldownViewer
local DEFLATE = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate

-- Top-level positional fields of the decoded blob.
local F = {
    VERSION             = 1,   -- schema version (4 or 5)
    ACTIVE_LAYOUT_NAMES = 2,   -- classSpecTag -> active layoutID
    LAYOUTS             = 3,   -- classSpecTag -> layoutID -> layout table
    LAYOUT_ID_DATA      = 4,   -- layoutID -> human-readable layout name
}
-- Positional fields of ONE layout table (values under F.LAYOUTS[tag][id]).
local L = {
    COOLDOWN_ORDER           = 1,   -- global order list (nil = let the category overrides drive)
    CATEGORY_OVERRIDES       = 2,   -- Enum.CooldownViewerCategory -> { cooldownID, ... }
    ALERT_OVERRIDES          = 3,
    HIDDEN_GROUP_BUFFS       = 4,
    GROUP_BUFF_VISUAL_ALERTS = 5,
}
Blob.FIELD        = F
Blob.LAYOUT_FIELD = L

-- Ordered list of the categories we care about (label + enum), skipping any the client lacks.
-- NB: 12.1.0 has only Essential/Utility/TrackedBuff/TrackedBar (verified in-game). "GroupBuff" is kept here
-- purely as forward-compat — the `C[key] ~= nil` guard drops it (it is absent), so it never reaches the UI.
-- The enum also carries internal HiddenSpell=-1 / HiddenAura=-2 buckets, which are NOT display categories.
local function BuildCategories()
    local t = {}
    local C = Enum and Enum.CooldownViewerCategory
    if not C then return t end
    local order = { "Essential", "Utility", "TrackedBuff", "TrackedBar", "GroupBuff" }
    for _, key in ipairs(order) do
        if C[key] ~= nil then t[#t + 1] = { key = key, enum = C[key] } end
    end
    return t
end
Blob.CATEGORIES = BuildCategories()

-- The class/spec tag Blizzard keys layouts by (e.g. "MAGE_FROST"), or nil.
function Blob.GetTag()
    return CooldownViewerUtil and CooldownViewerUtil.GetCurrentClassAndSpecTag
        and CooldownViewerUtil.GetCurrentClassAndSpecTag() or nil
end

-- Decode the live layout blob into its Lua table, or (nil, tag, reason). Never mutates game state
-- except the one-shot native schema upgrade (WriteData) when the stored schema is older than 4,
-- mirroring the native UI's own upgrade — `doNotTryAgain` bounds that to a single retry.
function Blob.Read(doNotTryAgain)
    local tag = Blob.GetTag()
    if not (C_EncodingUtil and C_CooldownViewer and C_CooldownViewer.GetLayoutData and DEFLATE) then
        return nil, tag, "native CDM serialization API unavailable"
    end
    local full = C_CooldownViewer.GetLayoutData()
    if type(full) ~= "string" then return nil, tag, "no layout data" end
    local body = full:match("^%d+%|(.*)$")
    if not body then return nil, tag, "unrecognised envelope" end
    local ok, data = pcall(function()
        return C_EncodingUtil.DeserializeCBOR(
            C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(body), DEFLATE))
    end)
    if not ok or type(data) ~= "table" then return nil, tag, "decode failed" end

    local ver = data[F.VERSION]
    if type(ver) ~= "number" then return nil, tag, "no schema version" end
    -- Stored schema too old: ask the native serializer to rewrite/upgrade it once, then re-read.
    if ver < 4 then
        local S = CooldownViewerSettings
        if not doNotTryAgain and S and S.dataSerialization and S.dataSerialization.WriteData then
            pcall(S.dataSerialization.WriteData, S.dataSerialization)
            return Blob.Read(true)
        end
    end
    if ver ~= 4 and ver ~= 5 then
        return nil, tag, "unsupported schema version " .. tostring(ver)
    end
    return data, tag
end

-- Encode a blob table back into the `"1|..."` string, or nil. pcall-guarded (SerializeCBOR errors
-- on unserialisable input). Does NOT touch game state — the caller decides whether to Write it.
function Blob.Encode(cdmData)
    if not (C_EncodingUtil and DEFLATE) then return nil end
    local ok, out = pcall(function()
        return C_EncodingUtil.EncodeBase64(
            C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(cdmData), DEFLATE))
    end)
    if ok and type(out) == "string" then return "1|" .. out end
    return nil
end

-- The cooldownIDs of a category. The 2nd arg widens the set: false/nil = the currently CONFIGURED
-- subset (what the user selected for this category), true = ALL cooldowns AVAILABLE to the category
-- for this spec (a superset — verified in-game: configured count <= available count). Exact API
-- semantics to be pinned when Phase 1 programs categories; today we only enumerate.
function Blob.GetTracked(categoryEnum, available)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and categoryEnum ~= nil) then
        return {}
    end
    return C_CooldownViewer.GetCooldownViewerCategorySet(categoryEnum, available and true or false) or {}
end

-- The native cooldown info for a cooldownID (spellID / overrideSpellID / linkedSpellIDs / flags / ...).
function Blob.GetInfo(cdmID)
    return C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdmID) or nil
end

-- ── DANGER: writes the live CDM layout config ─────────────────────────────────────────────────
-- Guarded (out of combat + not in Edit Mode). Encodes the (possibly-mutated) blob, scrubs + purges
-- the native caches so the CDM rebuilds from it, sets it, and re-enables the viewer next frame.
-- Returns true, or (false, reason). NOTHING calls this automatically yet — it's the write path the
-- later phases (programming what the CDM tracks) will use.
function Blob.Write(cdmData)
    if InCombatLockdown() then return false, "in combat" end
    if EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown() then
        return false, "edit mode open"
    end
    if not (C_CooldownViewer and C_CooldownViewer.SetLayoutData) then return false, "no SetLayoutData" end
    local str = Blob.Encode(cdmData)
    if not str then return false, "encode failed" end

    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("cooldownViewerEnabled", "0") end
    -- Scrub the taint our decode/edit left on Blizzard's derived caches AND invalidate them, so the
    -- native side regenerates from the new blob instead of a stale/tainted cache (ns.PurgeTaintedKey).
    local S = CooldownViewerSettings
    if S and ns.PurgeTaintedKey then
        if S.dataSerialization then ns.PurgeTaintedKey(S.dataSerialization, "cachedSerializedData") end
        if S.dataProvider     then ns.PurgeTaintedKey(S.dataProvider,     "displayData")         end
        if S.layoutManager    then ns.PurgeTaintedKey(S.layoutManager,    "activeLayoutID")       end
    end
    C_CooldownViewer.SetLayoutData(str)
    if C_Timer and C_Timer.After and C_CVar and C_CVar.SetCVar then
        C_Timer.After(0, function() C_CVar.SetCVar("cooldownViewerEnabled", "1") end)
    end
    return true
end

-- ── Verification (no writes) ──────────────────────────────────────────────────────────────────
local function DeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not DeepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Prove our C_EncodingUtil codec round-trips the REAL live blob faithfully, WITHOUT writing: read
-- it, re-encode it, decode our re-encode, and structurally compare. Returns (ok, reason).
function Blob.VerifyRoundTrip()
    local data, _, reason = Blob.Read()
    if not data then return false, "read: " .. tostring(reason) end
    local str = Blob.Encode(data)
    if not str then return false, "encode failed" end
    local body = str:match("^%d+%|(.*)$")
    local ok, data2 = pcall(function()
        return C_EncodingUtil.DeserializeCBOR(
            C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(body), DEFLATE))
    end)
    if not ok or type(data2) ~= "table" then return false, "re-decode failed" end
    return DeepEqual(data, data2), "structural compare"
end

-- The name of the active layout for the current spec (what Blizzard's UI calls it), or nil.
function Blob.GetActiveLayoutName(data, tag)
    data = data or Blob.Read()
    tag  = tag or Blob.GetTag()
    if not (data and tag) then return nil end
    local names = data[F.ACTIVE_LAYOUT_NAMES]
    local id = names and names[tag]
    local idData = data[F.LAYOUT_ID_DATA]
    return id and idData and idData[id] or nil, id
end

-- ── Dev / verification slash: /uucdmblob ──────────────────────────────────────────────────────
-- Reads the live blob, prints a summary of what the CDM tracks, and runs the round-trip check.
-- READ-ONLY — never writes. Purely to confirm the Phase 0 foundation works on real data.
local function PrintSummary()
    local pr = ns.Print or function(m) print("|cff338cff[UnbunkUtility]|r " .. m) end
    local data, tag, reason = Blob.Read()
    if not data then
        pr("CDM blob: could not read (" .. tostring(reason) .. "). Is the Cooldown Manager enabled?")
        return
    end
    local name, id = Blob.GetActiveLayoutName(data, tag)
    pr(("CDM blob: schema v%s, spec tag %q, active layout id %s (%s)")
        :format(tostring(data[F.VERSION]), tostring(tag), tostring(id), tostring(name or "?")))
    for _, cat in ipairs(Blob.CATEGORIES) do
        local configured = Blob.GetTracked(cat.enum, false)   -- currently-selected subset
        local available  = Blob.GetTracked(cat.enum, true)    -- all available to the category
        pr(("  %s: %d configured / %d available"):format(cat.key, #configured, #available))
    end
    local ok, why = Blob.VerifyRoundTrip()
    pr("  Round-trip codec: " .. (ok and "|cff40ff40OK (faithful)|r" or ("|cffff4040MISMATCH|r (" .. tostring(why) .. ")")))
end

SLASH_UUCDMBLOB1 = "/uucdmblob"
SlashCmdList["UUCDMBLOB"] = PrintSummary
