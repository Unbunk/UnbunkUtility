-- Core/Profiles.lua

local _, ns = ...

ns.profiles = ns.profiles or {}
local ALL_DBS = {
    HealerRange       = function() return HealerRangeDB       end,
    DeathAlert        = function() return DeathAlertDB        end,
    BLTracker         = function() return BLTrackerDB         end,
    PotionTracker     = function() return PotionTrackerDB     end,
    TrinketTracker    = function() return TrinketTrackerDB    end,
    PITracker         = function() return PITrackerDB         end,
    PlayerDeath       = function() return PlayerDeathDB       end,
    BResTracker       = function() return BResTrackerDB       end,
    HealthstoneTracker = function() return HealthstoneTrackerDB end,
}

local ALL_SETTERS = {
    HealerRange       = function(t) HealerRangeDB       = t end,
    DeathAlert        = function(t) DeathAlertDB        = t end,
    BLTracker         = function(t) BLTrackerDB         = t end,
    PotionTracker     = function(t) PotionTrackerDB     = t end,
    TrinketTracker    = function(t) TrinketTrackerDB    = t end,
    PITracker         = function(t) PITrackerDB         = t end,
    PlayerDeath       = function(t) PlayerDeathDB       = t end,
    BResTracker       = function(t) BResTrackerDB       = t end,
    HealthstoneTracker = function(t) HealthstoneTrackerDB = t end,
}

local function InitDB()
    UnbunkUtilityDB = UnbunkUtilityDB or {}
    UnbunkUtilityDB.currentProfile = UnbunkUtilityDB.currentProfile or "Default"
    UnbunkUtilityDB.profiles       = UnbunkUtilityDB.profiles or {}
    if not UnbunkUtilityDB.profiles["Default"] then
        UnbunkUtilityDB.profiles["Default"] = {}
    end
end

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
                key = '["' .. k .. '"]'
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
    return UnbunkUtilityDB.currentProfile or "Default"
end

function ns.profiles.GetList()
    local list = {}
    for name in pairs(UnbunkUtilityDB.profiles) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

function ns.profiles.SaveCurrent()
    local name = ns.profiles.GetCurrent()
    local snapshot = {}
    for dbName, getter in pairs(ALL_DBS) do
        snapshot[dbName] = DeepCopy(getter())
    end
    UnbunkUtilityDB.profiles[name] = snapshot
end

function ns.profiles.Load(name)
    if not UnbunkUtilityDB.profiles[name] then return false end
    local snapshot = UnbunkUtilityDB.profiles[name]
    for dbName, setter in pairs(ALL_SETTERS) do
        if snapshot[dbName] then
            setter(DeepCopy(snapshot[dbName]))
        end
    end
    UnbunkUtilityDB.currentProfile = name
    -- Re-apply every module's defaults + sound-key migration onto the freshly
    -- loaded DB tables: older/imported snapshots may be missing newer keys, and
    -- nothing else runs CfgInit after login.
    ns.RunCfgInitHooks()
    ns.profiles.ReloadAll()
    return true
end

-- Reset every module's saved variables to their defaults, then snapshot the
-- clean state into the current profile. Driven generically off ALL_SETTERS +
-- the CfgInit hook registry so no module can be forgotten.
function ns.profiles.ResetCurrent()
    for _, setter in pairs(ALL_SETTERS) do
        setter({})
    end
    ns.RunCfgInitHooks()
    ns.profiles.SaveCurrent()
    ns.profiles.ReloadAll()
    return true
end

function ns.profiles.Create(name)
    if not name or name == "" then return false end
    if UnbunkUtilityDB.profiles[name] then return false end
    -- Snapshot the current profile first so we clone its latest state.
    ns.profiles.SaveCurrent()
    -- Create the new profile as a copy of the current one.
    local currentName = ns.profiles.GetCurrent()
    UnbunkUtilityDB.profiles[name] = DeepCopy(UnbunkUtilityDB.profiles[currentName])
    UnbunkUtilityDB.currentProfile = name
    return true
end

function ns.profiles.Delete(name)
    if name == "Default" then return false end
    if not UnbunkUtilityDB.profiles[name] then return false end
    UnbunkUtilityDB.profiles[name] = nil
    if ns.profiles.GetCurrent() == name then
        ns.profiles.Load("Default")
    end
    return true
end

function ns.profiles.Export()
    ns.profiles.SaveCurrent()
    local name = ns.profiles.GetCurrent()
    local data = Serialize(UnbunkUtilityDB.profiles[name])
    return Base64Encode(data)
end

function ns.profiles.Import(str)
    local data = Base64Decode(str)
    local t, err = Deserialize(data)
    if not t then return false, err end
    -- Migrate any pre-restructure sound keys in the imported blob; Load() then
    -- re-runs every module's CfgInit so missing defaults are backfilled too.
    ns.MigrateSoundKeys(t)
    local name = ns.profiles.GetCurrent()
    UnbunkUtilityDB.profiles[name] = t
    ns.profiles.Load(name)
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

local initProfiles = CreateFrame("Frame")
initProfiles:RegisterEvent("ADDON_LOADED")
initProfiles:RegisterEvent("PLAYER_LOGOUT")
initProfiles:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGOUT" then
        ns.profiles.SaveCurrent()
        return
    end
    if addonName ~= "UnbunkUtility" then return end
    InitDB()
    self:UnregisterEvent("ADDON_LOADED")
end)