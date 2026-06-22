-- Modules/ReloadAnnounce/Core/ReloadAnnounce.lua
-- Extra utility: announce a reload in group chat right before /reload happens.
--
-- A ReloadUI / C_UI.Reload post-hook fires while the reload is being queued (still time
-- to SendChatMessage before the client tears down), so reloading while in a group posts
-- the message. The 3 channels (say / party / raid) are individually toggleable AND ranked
-- by a drag-reorder priority list: the message goes to the HIGHEST-priority channel that
-- is both enabled AND available in the current group context (raid only in a raid, party
-- only in a 5-man party, say always). An "Active in" instance filter gates it further.

local ADDON, ns = ...
ns.ReloadAnnounce = ns.ReloadAnnounce or {}
local RA = ns.ReloadAnnounce

local DEFAULT_MESSAGE = "Reloading..."

local DEFAULTS = {
    enabled        = false,
    message        = DEFAULT_MESSAGE,
    channels       = { say = true, party = true, raid = true },  -- which channels are enabled
    order          = { "raid", "party", "say" },                 -- priority (drag-reorderable)
    instanceFilter = { dungeon = true, raid = true, battleground = true, outdoor = true },
    -- Which group contexts may announce. Defaults reproduce the old "only when grouped"
    -- behaviour (party + raid, never solo); enabling solo posts to /say while alone.
    groupTypes     = { group = true, raid = true, solo = false },
}

-- Channel definitions: SendChatMessage target, display label, and an availability test.
RA.CHANNELS = {
    say   = { channel = "SAY",   label = "/s (say)",           avail = function() return true end },
    party = { channel = "PARTY", label = "/p (party)",         avail = function() return IsInGroup() and not IsInRaid() end },
    raid  = { channel = "RAID",  label = "/raid (raid group)", avail = function() return IsInRaid() end },
}
RA.ORDER_KEYS = { "raid", "party", "say" }   -- canonical key set

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.reloadAnnounce end
RA.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    p.reloadAnnounce = p.reloadAnnounce or {}
    ns.MergeDefaults(p.reloadAnnounce, DEFAULTS)
end
ns.RegisterCfgInitHook(InitCfg)

-- The saved priority order, sanitised to exactly the known keys (preserve the user's
-- order, drop unknowns/dupes, append any missing) so the list is always well-formed.
function RA.CurrentOrder()
    local c = Cfg()
    local saved = (c and c.order) or {}
    local out, seen = {}, {}
    for _, k in ipairs(saved) do
        if RA.CHANNELS[k] and not seen[k] then out[#out + 1] = k; seen[k] = true end
    end
    for _, k in ipairs(RA.ORDER_KEYS) do
        if not seen[k] then out[#out + 1] = k; seen[k] = true end
    end
    return out
end

function RA.SaveOrder(order)
    local c = Cfg(); if c then c.order = order end
end

-- Whether the CURRENT group context (raid / party / solo) is one the user allows. Raid and
-- party default ON, solo OFF, so an unset/legacy profile keeps the old "groups only" rule.
function RA.GroupTypeAllowed(c)
    local gt = c.groupTypes
    if IsInRaid()  then return not gt or gt.raid ~= false  end
    if IsInGroup() then return not gt or gt.group ~= false end
    return gt ~= nil and gt.solo == true
end

-- Send the announce to the top-priority enabled+available channel (one channel only).
-- `announced` is a one-shot guard so the ReloadUI + C_UI.Reload hooks can't double-send
-- (the flag is naturally reset by the imminent reload).
local announced = false
function RA.Announce()
    if announced then return end
    local c = Cfg()
    if not c or not c.enabled then return end
    if not RA.GroupTypeAllowed(c) then return end                       -- gated by group type
    if not ns.IsActiveInInstance(c.instanceFilter) then return end
    local msg = (c.message and c.message ~= "") and c.message or DEFAULT_MESSAGE
    for _, key in ipairs(RA.CurrentOrder()) do
        local ch = RA.CHANNELS[key]
        if c.channels and c.channels[key] and ch and ch.avail() then
            announced = true
            SendChatMessage(msg, ch.channel)
            return
        end
    end
end

-- Hook the reload entry points (a /reload or /rl goes through ReloadUI; some callers use
-- C_UI.Reload directly). The one-shot guard prevents a double announce if both fire.
if type(ReloadUI) == "function" then
    hooksecurefunc("ReloadUI", function() RA.Announce() end)
end
if C_UI and type(C_UI.Reload) == "function" then
    hooksecurefunc(C_UI, "Reload", function() RA.Announce() end)
end
