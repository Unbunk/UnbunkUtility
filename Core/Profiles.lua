-- Core/Profiles.lua
--
-- Public profile API (ns.profiles.*) layered on top of the AceDB engine created
-- in Core/DB.lua (ns.db). AceDB owns the storage and writes live, so there is no
-- snapshot-on-logout step here anymore: every setter mutates ns.db.profile.* in
-- place and AceDB persists it. This file only adapts AceDB's profile methods to
-- the API the UI expects, plus export/import.
--
-- Export / import use the native 12.0 serialization engine (C_EncodingUtil): the profile
-- table is CBOR-serialized, DEFLATE-compressed and Base64-encoded into a single paste-safe
-- blob tagged with the "!UU2!" format sentinel. This replaced the old AceSerializer +
-- LibDeflate + hand-rolled Base64 pipeline (both libs are gone — CBOR round-trips tables
-- natively, no loadstring/setfenv on imported text). Blobs from that old pipeline ("!UU1!"
-- and the pre-sentinel Base64 forms) can no longer be imported — re-export from this version.

local _, ns = ...
local L = ns.L

local C_EncodingUtil = C_EncodingUtil
local DEFLATE = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate

ns.profiles = ns.profiles or {}

-- Deep-copy a profile for serialization, DROPPING values CBOR can't encode (function / userdata /
-- thread) exactly as the old hand-rolled serializer did — so one stray non-data value can't make
-- SerializeCBOR throw and blank a whole export — and coercing non-finite numbers to 0. Config
-- profiles are pure data, so this normally copies everything; it's belt-and-suspenders.
local function CleanCopy(v)
    local t = type(v)
    if t == "table" then
        local out = {}
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then   -- our config keys are always scalar
                local c = CleanCopy(val)
                if c ~= nil then out[k] = c end
            end
        end
        return out
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return 0 end
        return v
    elseif t == "string" or t == "boolean" then
        return v
    end
    return nil   -- function / userdata / thread: not serializable, drop it
end

-- Encode a Lua table into the paste-safe "!UU2!" blob (CBOR -> DEFLATE -> Base64), or nil if
-- the native engine is unavailable. pcall-guarded: SerializeCBOR errors on unserialisable input
-- rather than returning nil, so a malformed profile can't throw out of Export.
local function EncodeBlob(t)
    if not (C_EncodingUtil and DEFLATE) then return nil end
    local ok, out = pcall(function()
        return C_EncodingUtil.EncodeBase64(
            C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(t), DEFLATE))
    end)
    if ok and type(out) == "string" then return "!UU2!" .. out end
    return nil
end

-- Decode a "!UU2!" blob body (sentinel already stripped) back into a table, or (nil, message).
-- Each engine step is pcall'd AND type-checked: the C_EncodingUtil calls error() on a non-string
-- and can return non-string junk on corrupt input.
local function DecodeBlob(body)
    if not (C_EncodingUtil and DEFLATE) then
        return nil, L["This profile needs a newer version of UnbunkUtility."]
    end
    body = body:gsub("%s", "")   -- a pasted blob may be wrapped across several lines
    local ok1, decoded = pcall(C_EncodingUtil.DecodeBase64, body)
    if not ok1 or type(decoded) ~= "string" then return nil, L["corrupt profile data"] end
    local ok2, raw = pcall(C_EncodingUtil.DecompressString, decoded, DEFLATE)
    if not ok2 or type(raw) ~= "string" then return nil, L["corrupt profile data"] end
    local ok3, result = pcall(C_EncodingUtil.DeserializeCBOR, raw)
    if not ok3 or type(result) ~= "table" then return nil, L["corrupt profile data"] end
    return result
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ns.profiles.GetCurrent()
    if not ns.db then return "Default" end
    return ns.db:GetCurrentProfile()
end

function ns.profiles.GetList()
    if not ns.db then return { "Default" } end
    local list = ns.db:GetProfiles()
    table.sort(list)
    return list
end

-- Switch the active profile. AceDB's OnProfileChanged callback (Core/DB.lua) has
-- already re-applied every module's CfgInit + Reload hooks, so we only need to
-- rebuild any open config frames here. Returns false for an unknown profile to
-- preserve the legacy contract (AceDB:SetProfile would otherwise create it).
function ns.profiles.Load(name)
    if not ns.db then return false end
    if name == ns.db:GetCurrentProfile() then
        -- Same profile: no AceDB SetProfile (so no OnProfileChanged callback) —
        -- run the reload hooks ourselves before rebuilding the frames.
        ns.RunReloadHooks()
        ns.profiles.ReloadAll()
        return true
    end
    local known = false
    for _, p in ipairs(ns.db:GetProfiles()) do
        if p == name then known = true break end
    end
    if not known then return false end
    ns.db:SetProfile(name)          -- fires OnProfileChanged -> CfgInit + Reload
    ns.profiles.ReloadAll()
    return true
end

-- Wipe the current profile back to module defaults. AceDB:ResetProfile fires
-- OnProfileReset (Core/DB.lua), which re-runs every module's CfgInit so the
-- defaults are re-merged; we then rebuild any open config frames.
function ns.profiles.ResetCurrent()
    if not ns.db then return false end
    ns.db:ResetProfile()            -- fires OnProfileReset -> CfgInit + Reload
    ns.profiles.ReloadAll()
    return true
end

-- Create a new profile with DEFAULT settings (NOT a clone of the current one).
-- Returns false if the name is empty or already exists. SetProfile to the
-- not-yet-existing name creates an EMPTY profile and switches to it; the
-- OnProfileChanged callback (Core/DB.lua) then runs every module's CfgInit, which
-- merges each module's DEFAULTS in — so the fresh profile starts at defaults.
function ns.profiles.Create(name)
    if not ns.db then return false end
    if not name or name == "" then return false end
    for _, p in ipairs(ns.db:GetProfiles()) do
        if p == name then return false end
    end
    ns.db:SetProfile(name)   -- creates + activates a fresh (empty -> defaults) profile
    ns.profiles.ReloadAll()
    return true
end

-- Delete a profile. "Default" is protected. If the active profile is deleted we
-- must switch away first (AceDB:DeleteProfile errors on the active profile),
-- falling back to "Default".
function ns.profiles.Delete(name)
    if not ns.db then return false end
    if name == "Default" then return false end
    local known = false
    for _, p in ipairs(ns.db:GetProfiles()) do
        if p == name then known = true break end
    end
    if not known then return false end
    if ns.db:GetCurrentProfile() == name then
        ns.db:SetProfile("Default")  -- fires OnProfileChanged -> CfgInit + Reload
        ns.profiles.ReloadAll()
    end
    ns.db:DeleteProfile(name, true)
    return true
end

function ns.profiles.Export()
    if not ns.db then return "" end
    -- Wrap a snapshot of the active profile in a small versioned envelope so Import can
    -- recognise our blobs and reject foreign / future ones cleanly.
    local payload = {
        addon   = "UnbunkUtility",
        version = 2,
        data    = CleanCopy(ns.db.profile),
    }
    return EncodeBlob(payload) or ""
end

-- Decode an export blob into a profile snapshot (the per-module data table), or
-- (nil, errorMessage). Only the native "!UU2!" format is supported; the old "!UU1!" /
-- pre-sentinel Base64 blobs needed AceSerializer + LibDeflate, which are gone. The caller
-- decides WHERE to write the snapshot (the current profile vs a brand-new one).
local function DecodeProfileBlob(str)
    if type(str) ~= "string" then return nil, L["invalid profile data"] end
    str = str:gsub("^%s+", "")  -- tolerate leading whitespace before the sentinel

    if str:sub(1, 5) ~= "!UU2!" then
        -- Old formats can't be decoded without the removed libs — point the user at a fresh export.
        return nil, L["This profile was exported by an old version — please re-export it."]
    end
    local raw, err = DecodeBlob(str:sub(6))
    if type(raw) ~= "table" then return nil, err or L["invalid profile data"] end

    -- Accept both the versioned envelope { addon, version, data } and a bare snapshot (a table
    -- of per-module DBs, none named addon/version/data), for defensiveness.
    local snapshot = raw
    if raw.addon ~= nil or raw.version ~= nil or raw.data ~= nil then
        if raw.addon ~= "UnbunkUtility" then
            return nil, L["not an UnbunkUtility profile"]
        end
        if type(raw.data) ~= "table" then
            return nil, L["invalid profile data"]
        end
        snapshot = raw.data
    end
    return snapshot
end

-- Wipe the ACTIVE profile table in place (keeping the identity AceDB tracks) and
-- copy `snapshot` into it, then re-apply: CfgInit re-merges defaults + sound-key
-- migration and ReloadAll re-applies settings / rebuilds frames.
local function ApplySnapshot(snapshot)
    -- Migrate any pre-restructure sound keys in the blob before it is written; the
    -- CfgInit re-run below backfills any missing defaults too.
    ns.MigrateSoundKeys(snapshot)
    local profile = ns.db.profile
    for k in pairs(profile) do profile[k] = nil end
    for k, v in pairs(snapshot) do profile[k] = ns.DeepCopy(v) end
    ns.RunCfgInitHooks()
    ns.RunReloadHooks()   -- in-place import: no AceDB callback ran the reload hooks
    if ns.OnProfileApplied then ns.OnProfileApplied() end   -- re-apply per-profile debug state
    ns.profiles.ReloadAll()
end

-- Import a blob OVER the current profile (kept for back-compat / callers that
-- want the in-place overwrite).
function ns.profiles.Import(str)
    if not ns.db then return false end
    local snapshot, err = DecodeProfileBlob(str)
    if not snapshot then return false, err end
    ApplySnapshot(snapshot)
    return true
end

-- Import a blob into a NEW profile named `name`, leaving the current profile
-- untouched until the switch. Rejects an empty or already-existing name, and
-- validates the blob BEFORE creating the profile so a bad paste creates nothing.
function ns.profiles.ImportAs(name, str)
    if not ns.db then return false end
    if type(name) ~= "string" or name:gsub("%s", "") == "" then
        return false, L["Profile name required"]
    end
    for _, p in ipairs(ns.db:GetProfiles()) do
        if p == name then return false, string.format(L["Profile already exists: %s"], name) end
    end
    local snapshot, err = DecodeProfileBlob(str)
    if not snapshot then return false, err end
    -- Suppress the OnProfileChanged apply for the empty profile this creates: ApplySnapshot
    -- runs CfgInit + Reload + OnProfileApplied once, on the imported data (avoids applying twice).
    ns._importingProfile = true
    ns.db:SetProfile(name)   -- create + switch to the new (empty) profile
    ns._importingProfile = nil
    ApplySnapshot(snapshot)  -- the snapshot is now written into the new profile
    return true
end

-- Rebuild any open config frames to reflect the active profile. The module RELOAD
-- hooks are intentionally NOT run here: the AceDB callbacks in Core/DB.lua
-- (OnProfileChanged / OnProfileReset / OnProfileCopied) already run CfgInit + Reload
-- on every real profile switch/reset, so running them here too fired every module's
-- reload hook TWICE per switch (plus a full frame rebuild right after AceDB had
-- already re-applied everything). Callers that change settings WITHOUT an AceDB
-- callback — the same-profile branch of Load, and ApplySnapshot's in-place import —
-- run the reload hooks themselves before calling this.
function ns.profiles.ReloadAll()
    -- Rebuild any open config frames to reflect the active profile.
    if UnbunkUtility and UnbunkUtility.panels then
        for _, mod in pairs(UnbunkUtility.panels) do
            -- Reclaim the panel's UIParent-parented dropdown drop-frames before
            -- orphaning it (they aren't children of mod.frame, so dropping the
            -- frame alone would leak them on every profile switch).
            if mod.menu and mod.menu.auxFrames then
                for _, fr in ipairs(mod.menu.auxFrames) do
                    fr:Hide()
                    fr:ClearAllPoints()
                    fr:SetParent(nil)
                end
            end
            if mod.frame then
                mod.frame:Hide()
                mod.frame:ClearAllPoints()
                mod.frame:SetParent(nil)
                mod.frame = nil
            end
            mod.menu = nil
        end
        -- RefreshNav rebuilds the nav tree (so debug sub-tab visibility tracks the new
        -- profile's "I know what I'm doing") AND re-shows the active panel fresh; fall
        -- back to ShowActiveModule if the nav was never built.
        if ns.RefreshNav then
            ns.RefreshNav()
        elseif UnbunkUtility.ShowActiveModule then
            UnbunkUtility.ShowActiveModule()
        end
    end
end
