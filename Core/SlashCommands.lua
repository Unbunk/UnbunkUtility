-- Core/SlashCommands.lua

local _, ns = ...
ns.HealerRange = ns.HealerRange or {}
local HR = ns.HealerRange

local function OpenConfig()
    if UnbunkUtility and UnbunkUtility.OpenWindow then
        UnbunkUtility.OpenWindow()
    else
        print("|cffff4444[UnbunkUtility]|r Config panel not ready yet.")
    end
end

local function PrintHelp()
    print("|cffff4444[UnbunkUtility]|r Commands:")
    print("  |cffffd700/ubu|r or |cffffd700/ubu config|r — open settings")
    print("  |cffffd700/ubu help|r — show this help")
    print("  |cffffd700/ubu test|r — test healer range alert")
    print("  |cffffd700/ubu lock|r — lock alert position")
    print("  |cffffd700/ubu reset|r — reset alert position")
end

SLASH_UNBUNKUTILITY1 = "/ubu"
SlashCmdList["UNBUNKUTILITY"] = function(msg)
    local cmd = strtrim(msg):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        OpenConfig()
    elseif cmd == "help" then
        PrintHelp()
    elseif cmd == "test" then
        HR.SetTesting(true)
        HR.GetFrame():Show()
        HR.PlaySound()
        print("|cffff4444[UnbunkUtility]|r Alert test — disappears in 5 seconds.")
        C_Timer.After(5, function()
            HR.SetTesting(false)
            if not HR.IsUnlocked() then
                HR.GetFrame():Hide()
            end
        end)
    elseif cmd == "lock" then
        if HR.SetUnlocked then HR.SetUnlocked(false) end
        if HR.pe then HR.pe.Refresh() end
        print("|cffff4444[UnbunkUtility]|r Alert locked and position saved.")
    elseif cmd == "reset" then
        HR.CfgSet("posX", 0)
        HR.CfgSet("posY", 100)
        HR.ApplyPosition()
        print("|cffff4444[UnbunkUtility]|r Position reset.")
    elseif cmd == "debug" then
        local RangeCheck = LibStub("LibRangeCheck-3.0")
        print("|cffff4444[UnbunkUtility]|r Debug — Friend checkers |cffff9900in combat|r:")
        for _, rc in ipairs(RangeCheck.friendRCInCombat) do
            print("  |cffffd700" .. rc.range .. "y|r — " .. tostring(rc.info))
        end
        print("|cffff4444[UnbunkUtility]|r Debug — Friend checkers |cff00ff00out of combat|r:")
        for _, rc in ipairs(RangeCheck.friendRC) do
            print("  |cffffd700" .. rc.range .. "y|r — " .. tostring(rc.info))
        end
        print("|cffff4444[UnbunkUtility]|r Debug — Res checkers |cffff9900in combat|r:")
        for range, checker in RangeCheck:GetFriendCheckers(true) do
            print("  |cffffd700" .. range .. "y|r")
        end
    else
        print("|cffff4444[UnbunkUtility]|r Unknown command. Type |cffffd700/ubu help|r for the list.")
    end
end