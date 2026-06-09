-- Core/Profiles.lua
--
-- Public profile API (ns.profiles.*) layered on top of the AceDB engine created
-- in Core/DB.lua (ns.db). AceDB owns the storage and writes live, so there is no
-- snapshot-on-logout step here anymore: every setter mutates ns.db.profile.* in
-- place and AceDB persists it. This file only adapts AceDB's profile methods to
-- the API the UI expects, plus export/import.
--
-- AceSerializer gives a safe, tested table round-trip for profile export/import
-- (no loadstring/setfenv on imported text, and correct escaping — replaces our
-- hand-rolled Serialize, which the audit found buggy). Its output is wrapped in
-- our Base64 layer so the blob stays paste-safe. Optional: if the lib is missing
-- we fall back to the legacy serializer. Format is auto-detected on import (an
-- AceSerializer blob decodes to a string starting with "^"; the legacy one to a
-- Lua table literal starting with "{"), so blobs exported before this still load.

local _, ns = ...
local L = ns.L

local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
-- LibDeflate (optional): DEFLATE-compresses the serialized profile before encoding
-- it, producing much shorter, still copy/paste-safe export strings. If absent we
-- fall back to the Base64 blob formats below, which stay importable everywhere.
local LibDeflate = LibStub and LibStub("LibDeflate", true)

ns.profiles = ns.profiles or {}

-- Serialize a Lua table to a string literal (for profile export). Skips
-- function/userdata values and guards non-finite numbers so the blob always
-- round-trips through Deserialize.
local function Serialize(t)
    local tt = type(t)
    if tt ~= "table" then
        if tt == "string" then
            return string.format("%q", t)
        elseif tt == "number" then
            if t ~= t or t == math.huge or t == -math.huge then return "0" end
            return string.format("%.17g", t)
        elseif tt == "boolean" then
            return tostring(t)
        else
            return "nil"  -- functions / userdata are not serializable
        end
    end
    local result = "{"
    for k, v in pairs(t) do
        local vt = type(v)
        if vt ~= "function" and vt ~= "userdata" then
            local key
            if type(k) == "string" then
                -- %q escapes quotes/backslashes/newlines so keys containing them
                -- (e.g. a user-named profile or a custom LSM sound key) round-trip
                -- through loadstring instead of producing an invalid chunk.
                key = string.format("[%q]", k)
            else
                key = "[" .. tostring(k) .. "]"
            end
            result = result .. key .. "=" .. Serialize(v) .. ","
        end
    end
    return result .. "}"
end

-- Deserialize a profile string back into a table.
-- IMPORTANT: the input string comes from a shared import between players. We
-- execute the chunk in an empty environment (setfenv) so it can do nothing but
-- build a literal table — no function or global is accessible from inside.
local function Deserialize(str)
    local fn, err = loadstring("return " .. str)
    if not fn then return nil, err end
    setfenv(fn, {})
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    if type(result) ~= "table" then return nil, "invalid profile data" end
    return result
end

-- Base64 encode (used so exported profiles are a single safe-to-paste blob).
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Base64Encode(data)
    return ((data:gsub(".", function(x)
        local r, b = "", x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2^(6-i) or 0) end
        return b64chars:sub(c+1, c+1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

local function Base64Decode(data)
    data = data:gsub("[^" .. b64chars .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (b64chars:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and "1" or "0") end
        return r
    end):gsub("%d%d%d%d%d%d%d%d", function(x)
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2^(8-i) or 0) end
        return string.char(c)
    end))
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
    -- Wrap a snapshot of the active profile in a small versioned envelope so
    -- Import can recognise our blobs and reject foreign / future ones cleanly.
    -- Legacy headerless blobs stay importable (see Import below).
    local payload = {
        addon   = "UnbunkUtility",
        version = 1,
        data    = ns.DeepCopy(ns.db.profile),
    }
    -- Preferred: AceSerializer -> DEFLATE -> print-safe encode, tagged with the
    -- "!UU1!" format sentinel. DEFLATE shrinks the very redundant serialized text
    -- a lot; EncodeForPrint keeps it copy/paste-safe ([a-zA-Z0-9()] only).
    if AceSerializer and LibDeflate then
        local serialized = AceSerializer:Serialize(payload)
        local compressed = LibDeflate:CompressDeflate(serialized)  -- 2nd return (padding) ignored
        return "!UU1!" .. LibDeflate:EncodeForPrint(compressed)
    end
    -- Fallbacks (lib missing / older client): keep the Base64 blob formats so the
    -- export still works and stays importable by any version.
    if AceSerializer then
        return Base64Encode(AceSerializer:Serialize(payload))
    end
    return Base64Encode(Serialize(payload))  -- legacy fallback if the lib is absent
end

-- Decode an export blob into a profile snapshot (the per-module data table), or
-- (nil, errorMessage). Handles the !UU1! compact format and the legacy Base64
-- formats, and unwraps the versioned { addon, version, data } envelope. The caller
-- decides WHERE to write the snapshot (the current profile vs a brand-new one).
local function DecodeProfileBlob(str)
    if type(str) ~= "string" then return nil, L["invalid profile data"] end
    str = str:gsub("^%s+", "")  -- tolerate leading whitespace before the sentinel

    local raw, err
    if str:sub(1, 5) == "!UU1!" then
        -- New compact format: AceSerializer -> DEFLATE -> EncodeForPrint, tagged
        -- with a sentinel. This branch MUST run before any Base64Decode, which
        -- would strip the "!" (outside its alphabet) and mis-route the blob.
        if not (LibDeflate and AceSerializer) then
            return nil, L["This profile needs a newer version of UnbunkUtility."]
        end
        -- Strip ALL whitespace: a pasted blob may be wrapped onto several lines,
        -- and DecodeForPrint only trims leading/trailing space, not interior.
        local body = (str:sub(6)):gsub("%s", "")
        -- DecodeForPrint / DecompressDeflate return nil (not a message) on bad
        -- data and error() on a non-string, so pcall AND nil-check both.
        local ok1, decoded = pcall(LibDeflate.DecodeForPrint, LibDeflate, body)
        if not ok1 or not decoded then return nil, L["corrupt profile data"] end
        local ok2, serialized = pcall(LibDeflate.DecompressDeflate, LibDeflate, decoded)
        if not ok2 or not serialized then return nil, L["corrupt profile data"] end
        local ok3, result = AceSerializer:Deserialize(serialized)
        if not ok3 then return nil, L["corrupt profile data"] end
        raw = result
    else
        -- Legacy format: Base64 -> (AceSerializer "^" | hand-rolled "{") so every
        -- blob exported before this version still imports unchanged.
        local decoded = Base64Decode(str)
        if AceSerializer and decoded:sub(1, 1) == "^" then
            local ok, result = AceSerializer:Deserialize(decoded)
            if not ok then return nil, result end
            raw = result
        else
            raw, err = Deserialize(decoded)
        end
    end
    if type(raw) ~= "table" then return nil, err or L["invalid profile data"] end

    -- Accept both the versioned envelope { addon, version, data } and a legacy
    -- bare snapshot (a table of per-module DBs, none of which is named addon/
    -- version/data), so blobs exported before versioning still import.
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
    ns.db:SetProfile(name)   -- create + switch to the new (empty) profile
    ApplySnapshot(snapshot)  -- the snapshot is now written into the new profile
    return true
end

function ns.profiles.ReloadAll()
    -- Re-apply each module's settings through the hooks they registered.
    ns.RunReloadHooks()

    -- Rebuild any open config frames to reflect the new profile.
    if UnbunkUtility and UnbunkUtility.registeredModules then
        for _, mod in ipairs(UnbunkUtility.registeredModules) do
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
                mod.frame = nil
            end
            mod.menu = nil
        end
        if UnbunkUtility.ShowActiveModule then
            UnbunkUtility.ShowActiveModule()
        end
    end
end
