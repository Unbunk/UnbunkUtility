-- Core/SlashCommands.lua

local _, ns = ...
local L = ns.L

local function OpenConfig()
    if UnbunkUtility and UnbunkUtility.OpenWindow then
        UnbunkUtility.OpenWindow()
    else
        ns.Print(L["Config panel not ready yet."])
    end
end

local function PrintHelp()
    ns.Print(L["Commands:"])
    print(L["  |cff338cff/ubu|r or |cff338cff/ubu config|r — open settings"])
    print(L["  |cff338cff/ubu help|r — show this help"])
    print(L["  |cff338cff/ubu debug|r — dump LibRangeCheck friend checkers (dev)"])
end

SLASH_UNBUNKUTILITY1 = "/ubu"
SlashCmdList["UNBUNKUTILITY"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        OpenConfig()
    elseif cmd == "help" then
        PrintHelp()
    elseif cmd == "debug" then
        -- Silent flag so a missing lib degrades gracefully instead of erroring.
        local RangeCheck = LibStub("LibRangeCheck-3.0", true)
        if not RangeCheck then
            ns.Print(L["Debug — LibRangeCheck-3.0 not loaded."])
            return
        end
        ns.Print(L["Debug — Friend checkers |cffff9900in combat|r:"])
        -- `or {}` guards against a future LibRangeCheck dropping/renaming these
        -- internal fields (ipairs on nil would error in this dev-only command).
        for _, rc in ipairs(RangeCheck.friendRCInCombat or {}) do
            print("  |cff338cff" .. rc.range .. "y|r — " .. tostring(rc.info))
        end
        ns.Print(L["Debug — Friend checkers |cff00ff00out of combat|r:"])
        for _, rc in ipairs(RangeCheck.friendRC or {}) do
            print("  |cff338cff" .. rc.range .. "y|r — " .. tostring(rc.info))
        end
        ns.Print(L["Debug — Res checkers |cffff9900in combat|r:"])
        for range in RangeCheck:GetFriendCheckers(true) do
            print("  |cff338cff" .. range .. "y|r")
        end
    else
        ns.Print(L["Unknown command. Type |cff338cff/ubu help|r for the list."])
    end
end
