-- Core/Welcome.lua
-- One-line login greeting. Account-wide (ns.db.global.welcome.enabled), ON by default,
-- toggled from the General Settings tab. The version is read LIVE from the .toc so the
-- message never goes stale when the addon is bumped.

local ADDON, ns = ...

local DEFAULTS = { enabled = true }

local function CfgInit()
    if not ns.db then return end
    ns.db.global.welcome = ns.db.global.welcome or {}
    ns.MergeDefaults(ns.db.global.welcome, DEFAULTS)
end
ns.RegisterCfgInitHook(CfgInit)

-- Enabled unless EXPLICITLY turned off, so a fresh / not-yet-initialised DB still greets.
function ns.Welcome_IsEnabled()
    local w = ns.db and ns.db.global and ns.db.global.welcome
    return not (w and w.enabled == false)
end

function ns.Welcome_SetEnabled(val)
    if not ns.db then return end
    ns.db.global.welcome = ns.db.global.welcome or {}
    ns.db.global.welcome.enabled = val and true or false
end

-- PLAYER_LOGIN fires after Core/DB.lua's ADDON_LOADED bootstrap (ns.db + CfgInit
-- defaults are in place by then). Greet once per login unless disabled.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not ns.Welcome_IsEnabled() then return end
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = (meta and meta(ADDON, "Version")) or "?"
    -- ns.L (not a captured upvalue): Welcome.lua loads BEFORE Locales/*.lua in the
    -- .toc, so ns.L doesn't exist yet at file-load time — resolve it at call time.
    print(string.format(
        ns.L["|cff33aaffUnbunkUtility|r v%s loaded - type |cff338cff/ubu|r to open settings."],
        version))
end)
