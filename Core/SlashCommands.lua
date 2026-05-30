-- Core/SlashCommands.lua

local _, ns = ...
local L = ns.L

local function OpenConfig()
    if UnbunkUtility and UnbunkUtility.OpenWindow then
        UnbunkUtility.OpenWindow()
    else
        print(L["|cffff4444[UnbunkUtility]|r Config panel not ready yet."])
    end
end

local function PrintHelp()
    print(L["|cffff4444[UnbunkUtility]|r Commands:"])
    print(L["  |cffffd700/ubu|r or |cffffd700/ubu config|r — open settings"])
    print(L["  |cffffd700/ubu help|r — show this help"])
    print(L["  |cffffd700/ubu debug|r — dump LibRangeCheck friend checkers (dev)"])
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
            print(L["|cffff4444[UnbunkUtility]|r Debug — LibRangeCheck-3.0 not loaded."])
            return
        end
        print(L["|cffff4444[UnbunkUtility]|r Debug — Friend checkers |cffff9900in combat|r:"])
        for _, rc in ipairs(RangeCheck.friendRCInCombat) do
            print("  |cffffd700" .. rc.range .. "y|r — " .. tostring(rc.info))
        end
        print(L["|cffff4444[UnbunkUtility]|r Debug — Friend checkers |cff00ff00out of combat|r:"])
        for _, rc in ipairs(RangeCheck.friendRC) do
            print("  |cffffd700" .. rc.range .. "y|r — " .. tostring(rc.info))
        end
        print(L["|cffff4444[UnbunkUtility]|r Debug — Res checkers |cffff9900in combat|r:"])
        for range in RangeCheck:GetFriendCheckers(true) do
            print("  |cffffd700" .. range .. "y|r")
        end
    else
        print(L["|cffff4444[UnbunkUtility]|r Unknown command. Type |cffffd700/ubu help|r for the list."])
    end
end
