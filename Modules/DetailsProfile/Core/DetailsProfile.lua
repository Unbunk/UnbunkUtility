-- Modules/DetailsProfile/Core/DetailsProfile.lua
-- Owner utility: auto-switch the Details! damage-meter profile by context. A "raid"
-- context applies the raid profile, otherwise the dungeon profile. The context is read
-- from the GROUP type (IsInRaid), the INSTANCE type (IsInInstance == "raid"), or BOTH
-- (raid when either is raid), per the chosen mode. Uses the same Details! API as the
-- user's macro: Details:GetCurrentProfileName() / Details:ApplyProfile(name).
--
-- Switching is skipped in combat (it would reset the meter windows mid-fight) and
-- deferred to PLAYER_REGEN_ENABLED. Account-wide config (ns.db.global.detailsSwitch);
-- disabled by default and only reachable from the owner-gated "Personal utilities" panel.

local ADDON, ns = ...
ns.DetailsProfile = ns.DetailsProfile or {}
local DP = ns.DetailsProfile

local DEFAULTS = {
    enabled        = false,
    mode           = "both",              -- "group" | "instance" | "both"
    raidProfile    = "Principal (raid)",
    dungeonProfile = "Principal (dj)",
}

local function Cfg() return ns.db and ns.db.global and ns.db.global.detailsSwitch end
DP.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local g = ns.db.global
    g.detailsSwitch = g.detailsSwitch or {}
    ns.MergeDefaults(g.detailsSwitch, DEFAULTS)
end
ns.RegisterCfgInitHook(InitCfg)

-- Details! + its profile API present?
function DP.DetailsReady()
    return Details ~= nil and Details.GetCurrentProfileName and Details.ApplyProfile and true or false
end

-- Does the current context count as "raid" for the chosen mode?
local function WantRaid(c)
    local _, instType = IsInInstance()
    if c.mode == "group" then
        return IsInRaid()
    elseif c.mode == "instance" then
        return instType == "raid"
    end
    return IsInRaid() or instType == "raid"   -- "both": raid when EITHER is raid
end

local pending = false

-- Apply the context-appropriate profile (only when it actually differs, so a switch
-- happens on real context changes, not every roster tick). Re-armed on config change,
-- the relevant events, reload hook, and the panel's "Apply now" button.
function DP.Apply()
    local c = Cfg()
    if not c or not c.enabled then return end
    if not DP.DetailsReady() then return end
    local want = WantRaid(c) and c.raidProfile or c.dungeonProfile
    if not want or want == "" then return end
    if InCombatLockdown() then pending = true; return end   -- don't disrupt the meter mid-fight
    if Details:GetCurrentProfileName() == want then return end
    Details:ApplyProfile(want)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then pending = false; DP.Apply() end
        return
    end
    DP.Apply()
end)

ns.RegisterReloadHook(function() DP.Apply() end)
