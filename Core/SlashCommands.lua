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
    print(L["  |cff338cff/ubu|r or |cff338cff/ubu config|r or |cff338cff/ubu settings|r — open settings"])
    print(L["  |cff338cff/ubu help|r — show this help"])
end

SLASH_UNBUNKUTILITY1 = "/ubu"
SlashCmdList["UNBUNKUTILITY"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "settings" or cmd == "options" or cmd == "option" then
        OpenConfig()
    elseif cmd == "help" then
        PrintHelp()
    elseif cmd == "console" or cmd == "console mode" or cmd == "cm" then
        -- Console mode is part of the debug suite: only reachable once the account-
        -- wide "I know what I'm doing" gate is ticked; otherwise stay hidden.
        if ns.IsDebugUnlocked and ns.IsDebugUnlocked() and ns.Debug_ToggleConsole then
            ns.Debug_ToggleConsole()
        else
            ns.Print(L["Unknown command. Type |cff338cff/ubu help|r for the list."])
        end
    elseif cmd == "debug print start" or cmd == "debug print stop" then
        -- Start/stop the Addon-usage periodic print (debug suite — gated by the unlock).
        if ns.IsDebugUnlocked and ns.IsDebugUnlocked() and ns.Debug_SetUsageActive then
            ns.Debug_SetUsageActive(cmd == "debug print start")
        else
            ns.Print(L["Unknown command. Type |cff338cff/ubu help|r for the list."])
        end
    else
        ns.Print(L["Unknown command. Type |cff338cff/ubu help|r for the list."])
    end
end
