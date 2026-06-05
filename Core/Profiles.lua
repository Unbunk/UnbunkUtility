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

-- Create a new profile cloned from the current one. Returns false if the name is
-- empty or already exists. Switching to the (not-yet-existing) name creates it
-- lazily; CopyProfile then copies the previous current profile's settings into it.
function ns.profiles.Create(name)
    if not ns.db then return false end
    if not name or name == "" then return false end
    for _, p in ipairs(ns.db:GetProfiles()) do
        if p == name then return false end
    end
    local oldCurrent = ns.db:GetCurrentProfile()
    ns.db:SetProfile(name)                  -- creates + activates the new profile
    ns.db:CopyProfile(oldCurrent, true)     -- clone the previous current into it
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
    if AceSerializer then
        return Base64Encode(AceSerializer:Serialize(payload))
    end
    return Base64Encode(Serialize(payload))  -- legacy fallback if the lib is absent
end

function ns.profiles.Import(str)
    if not ns.db then return false end
    local decoded = Base64Decode(str)
    -- Auto-detect the serializer: AceSerializer blobs start with "^", the legacy
    -- hand-rolled ones with a "{" table literal — so old exports still import.
    local raw, err
    if AceSerializer and decoded:sub(1, 1) == "^" then
        local ok, result = AceSerializer:Deserialize(decoded)
        if not ok then return false, result end
        raw = result
    else
        raw, err = Deserialize(decoded)
    end
    if type(raw) ~= "table" then return false, err or L["invalid profile data"] end

    -- Accept both the versioned envelope { addon, version, data } and a legacy
    -- bare snapshot (a table of per-module DBs, none of which is named addon/
    -- version/data), so blobs exported before versioning still import.
    local snapshot = raw
    if raw.addon ~= nil or raw.version ~= nil or raw.data ~= nil then
        if raw.addon ~= "UnbunkUtility" then
            return false, L["not an UnbunkUtility profile"]
        end
        if type(raw.data) ~= "table" then
            return false, L["invalid profile data"]
        end
        snapshot = raw.data
    end

    -- Migrate any pre-restructure sound keys in the imported blob before it is
    -- written; the CfgInit re-run below backfills missing defaults too.
    ns.MigrateSoundKeys(snapshot)

    -- Wipe-and-copy the snapshot into the live profile table in place (keeping the
    -- same table identity AceDB tracks), then re-apply: CfgInit re-merges defaults
    -- + sound-key migration and ReloadAll re-applies settings / rebuilds frames.
    local profile = ns.db.profile
    for k in pairs(profile) do profile[k] = nil end
    for k, v in pairs(snapshot) do profile[k] = ns.DeepCopy(v) end
    ns.RunCfgInitHooks()
    ns.profiles.ReloadAll()
    return true
end

function ns.profiles.ReloadAll()
    -- Re-apply each module's settings through the hooks they registered.
    ns.RunReloadHooks()

    -- Rebuild any open config frames to reflect the new profile.
    if UnbunkUtility and UnbunkUtility.registeredModules then
        for _, mod in ipairs(UnbunkUtility.registeredModules) do
            if mod.frame then
                mod.frame:Hide()
                mod.frame = nil
            end
        end
        if UnbunkUtility.ShowActiveModule then
            UnbunkUtility.ShowActiveModule()
        end
    end
end
