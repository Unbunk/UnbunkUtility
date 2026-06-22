-- Modules/Debug/UI/ConfigWindow.lua
-- Debug Utilities panel + Console mode.
--
-- The tab is gated behind an "I know what I'm doing" checkbox (account-wide, OFF by
-- default): until ticked, the debug options here AND any gated sub-tabs stay hidden.
--
-- Console mode is a large black chat-style window that mirrors every print() call
-- (plain print, ns.Print, `/run print(...)`). It can also capture chat, bucketed
-- into three opt-in toggles (player messages / channels / everything else). Chat is
-- formatted with the NATIVE helpers (class-coloured clickable names via the sender
-- GUID, real channel names, ChatTypeInfo colours, AFK/DND flags, self-contained
-- system lines) the way Prat-3.0 does, instead of a crude "[TAG] sender: msg".

local _, ns = ...
local L = ns.L

-- Per-profile unlock flag. nil / false = locked (the default). Switching profiles
-- therefore switches the whole debug suite on/off (handled by ns.OnProfileApplied).
function ns.IsDebugUnlocked()
    return ns.db and ns.db.profile and ns.db.profile.debugUnlocked == true
end

local function CCfg() return ns.db and ns.db.profile and ns.db.profile.console end

-- ── Chat capture buckets ──────────────────────────────────────────────────────
local PLAYERS_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}
local CHANNELS_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL" }
local OTHERS_EVENTS = {
    "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY",
    "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE",
    "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_PET_INFO",
    "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT", "CHAT_MSG_TARGETICONS",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_PARTY",
    "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_IGNORED",
}
local EVENT_BUCKET = {}
for _, e in ipairs(PLAYERS_EVENTS)  do EVENT_BUCKET[e] = "players"  end
for _, e in ipairs(CHANNELS_EVENTS) do EVENT_BUCKET[e] = "channels" end
for _, e in ipairs(OTHERS_EVENTS)   do EVENT_BUCKET[e] = "others"   end

-- Types whose arg1 is already a complete, self-contained line: show it as-is, never
-- prefix a "sender:" (matches how the real chat frame displays them).
local COMPLETE_LINE = {
    SYSTEM = true, LOOT = true, MONEY = true, CURRENCY = true, SKILL = true,
    TRADESKILLS = true, PET_INFO = true, ACHIEVEMENT = true, GUILD_ACHIEVEMENT = true,
    TARGETICONS = true, IGNORED = true, TEXT_EMOTE = true, RAID_BOSS_EMOTE = true,
    BG_SYSTEM_NEUTRAL = true, BG_SYSTEM_ALLIANCE = true, BG_SYSTEM_HORDE = true,
    COMBAT_XP_GAIN = true, COMBAT_HONOR_GAIN = true, COMBAT_FACTION_CHANGE = true,
}

-- ── Console window + capture ──────────────────────────────────────────────────
local consoleFrame
local lineBuffer = {}
local LINE_CAP   = 500
local INPUT_H    = 24

local function AddLine(text)
    lineBuffer[#lineBuffer + 1] = text
    if #lineBuffer > LINE_CAP then table.remove(lineBuffer, 1) end
    if consoleFrame then
        consoleFrame.smf:AddMessage(text)
        if consoleFrame.smfSB then consoleFrame.smfSB.Update() end
    end
end

-- Hook the global print ONCE, EAGERLY at load (not lazily when the console window is
-- first opened) — so every print() is captured from login on: buffered into lineBuffer
-- and replayed when the window opens, plus mirrored live while it is open. Gated at
-- fire time, so nothing is captured/mirrored while debug is locked. origPrint always
-- runs first, so normal chat output is untouched.
if not ns._consoleHooked then
    ns._consoleHooked = true
    local origPrint = print
    print = function(...)
        origPrint(...)
        if not ns.IsDebugUnlocked() then return end   -- locked: don't mirror
        -- Secret values (WoW 11.x) stay secret through tostring() and would blow up
        -- table.concat ("invalid value (secret)") — e.g. BigWigs print()ing a gossip
        -- string. Substitute a placeholder so the mirror never errors on them.
        local n, parts = select("#", ...), {}
        for i = 1, n do
            local v = select(i, ...)
            if issecretvalue and issecretvalue(v) then
                parts[i] = "<secret>"
            else
                parts[i] = tostring(v)
            end
        end
        AddLine(table.concat(parts, " "))
    end
end

local function RunConsoleInput(text)
    if not text or text:gsub("%s", "") == "" then return end
    AddLine("|cff999999> " .. text .. "|r")
    if text:sub(1, 1) == "/" then
        local edit = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
        if edit and ChatEdit_SendText then
            edit:SetText(text)
            ChatEdit_SendText(edit, 0)
            edit:SetText("")
        end
        return
    end
    local fn = loadstring(text) or loadstring("return " .. text)
    if not fn then return end
    local ok, res = pcall(fn)
    if not ok then
        AddLine("|cffff4444" .. tostring(res) .. "|r")
    elseif res ~= nil then
        AddLine(tostring(res))
    end
end

-- Thin scrollbar styled exactly like ns.ui.CreateScrollBar (8px dark track + grey
-- thumb), but driven by a ScrollingMessageFrame's OFFSET model instead of a
-- ScrollFrame: offset 0 = bottom/newest, GetMaxScrollRange() = top/oldest. Methods
-- are guarded, so if a client lacks them the track simply stays hidden (no error).
local function CreateMessageScrollBar(parent, smf)
    local sb = {}
    local track = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    track:SetWidth(8)
    track:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    track:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    track:Hide()
    sb.track = track

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8); thumb:SetHeight(12)
    local tex = thumb:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    sb.thumb = thumb

    local function maxRange() return smf.GetMaxScrollRange and smf:GetMaxScrollRange() or 0 end

    local function update()
        local range = maxRange()
        if range <= 0 then track:Hide(); return end
        track:Show()
        local visible = (smf.GetNumLinesDisplayed and smf:GetNumLinesDisplayed()) or 1
        if visible < 1 then visible = 1 end
        local trackH  = track:GetHeight()
        local thumbH  = math.max(12, math.min(trackH, trackH * visible / (visible + range)))
        local offset  = (smf.GetScrollOffset and smf:GetScrollOffset()) or 0
        local frac    = 1 - (offset / range)            -- offset 0 (bottom) -> thumb bottom
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(frac * (trackH - thumbH)))
    end
    sb.Update = update
    -- Auto-sync the thumb whenever the message frame re-renders (new line, scroll,
    -- resize) — no manual Update() needed, though callers may still call it.
    if smf.SetOnDisplayRefreshedCallback then smf:SetOnDisplayRefreshedCallback(update) end

    thumb:EnableMouse(true)
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local startY   = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local startOff = (smf.GetScrollOffset and smf:GetScrollOffset()) or 0
        thumb:SetScript("OnUpdate", function()
            local range  = maxRange()
            local maxOff = track:GetHeight() - thumb:GetHeight()
            if range <= 0 or maxOff <= 0 then return end
            local curY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local newOff = startOff - ((startY - curY) / maxOff) * range  -- drag down -> toward bottom
            smf:SetScrollOffset(math.max(0, math.min(range, math.floor(newOff + 0.5))))
            update()
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local range = maxRange()
        if range <= 0 then return end
        local _, trackY = track:GetCenter()
        local curY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local trackH = track:GetHeight()
        local frac = math.max(0, math.min(1, (trackY + trackH / 2 - curY) / trackH))
        smf:SetScrollOffset(math.floor((1 - frac) * range + 0.5))
        update()
    end)

    return sb
end

local function LayoutBody()
    if not consoleFrame then return end
    local c = CCfg() or {}
    consoleFrame.input:SetShown(c.textEditor ~= false)
    local bottom = (c.textEditor ~= false) and (12 + INPUT_H + 6) or 12
    consoleFrame.smf:ClearAllPoints()
    consoleFrame.smf:SetPoint("TOPLEFT", consoleFrame, "TOPLEFT", 12, -46)
    consoleFrame.smf:SetPoint("BOTTOMRIGHT", consoleFrame, "BOTTOMRIGHT", -26, bottom)
    consoleFrame.smfSB.track:ClearAllPoints()
    consoleFrame.smfSB.track:SetPoint("TOPRIGHT", consoleFrame, "TOPRIGHT", -12, -46)
    consoleFrame.smfSB.track:SetPoint("BOTTOMRIGHT", consoleFrame, "BOTTOMRIGHT", -12, bottom)
    consoleFrame.smfSB.Update()
end

-- "Allow selection": make the LIVE log itself drag-selectable + Ctrl+C-able in place
-- (smf:SetTextCopyable). No separate snapshot — it stays live and renders identically
-- to the normal view. (New lines clear an active selection, so stop the print toggle
-- before copying a stable block.)
local function ApplySelectionMode()
    if not consoleFrame then return end
    local sel = (CCfg() or {}).allowSelection == true
    if consoleFrame.smf.SetTextCopyable then consoleFrame.smf:SetTextCopyable(sel) end
end

-- ── Native-style formatting helpers ───────────────────────────────────────────
local function hexColor(r, g, b)
    return string.format("|cff%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
end

-- Sender name coloured by class (resolved from the chat event's GUID) + realm-aware.
local function colorName(name, guid, chatType)
    if not name or name == "" then return name end
    if Ambiguate then name = Ambiguate(name, chatType == "GUILD" and "guild" or "none") end
    if guid and guid ~= "" and GetPlayerInfoByGUID then
        local _, classFile = GetPlayerInfoByGUID(guid)
        local col = classFile
            and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))
                 or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))
        if col then return hexColor(col.r, col.g, col.b) .. name .. "|r" end
    end
    return name
end

-- "RAID_LEADER" -> "Raid leader" for a readable tag.
local function prettyType(chatType)
    return (chatType:gsub("_", " "):lower():gsub("^%l", string.upper))
end

-- Readable channel label from the real channel args (NOT arg4): "5. Trade".
local function channelDisplay(chanNum, chanName, channelStr)
    local name = chanName
    if name and name ~= "" then
        local base = name:match("^(.-)%s%-%s.+$")   -- strip " - City/Realm" suffix
        if base and base ~= "" then name = base end
    end
    if not name or name == "" then name = channelStr or "Channel" end
    if chanNum and chanNum ~= 0 then return chanNum .. ". " .. name end
    return name
end

local function OnChatEvent(event, ...)
    if not ns.IsDebugUnlocked() then return end   -- defense-in-depth: never capture while locked
    local bucket = EVENT_BUCKET[event]
    if not bucket then return end
    local c = CCfg()
    if not c then return end
    local on = (bucket == "players"  and c.chPlayers)
            or (bucket == "channels" and c.chChannels)
            or (bucket == "others"   and c.chOthers)
    if not on then return end

    local msg, sender, _, channelStr, _, flags, _, chanNum, chanName, _, _, guid = ...
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    msg = msg or ""

    local chatType = event:sub(10)   -- strip "CHAT_MSG_"
    local info = ChatTypeInfo
        and (ChatTypeInfo[(bucket == "channels") and ("CHANNEL" .. (chanNum or "")) or chatType]
             or ChatTypeInfo[chatType])

    local nameDisp = (sender and sender ~= "") and colorName(strtrim(sender), guid, chatType) or nil
    if nameDisp and (flags == "AFK" or flags == "DND") then
        nameDisp = nameDisp .. " |cffff5555<" .. flags .. ">|r"
    end

    local line
    if bucket == "channels" then
        local prefix = "[" .. channelDisplay(chanNum, chanName, channelStr) .. "]"
        if info then prefix = hexColor(info.r, info.g, info.b) .. prefix .. "|r" end
        line = prefix .. (nameDisp and (" " .. nameDisp .. ":") or "") .. " " .. msg
    elseif COMPLETE_LINE[chatType] or not nameDisp then
        line = msg                                   -- self-contained line, as-is
    elseif chatType == "EMOTE" then
        line = nameDisp .. " " .. msg                -- "Name does X" (no colon)
    else
        local prefix = "[" .. prettyType(chatType) .. "]"
        if info then prefix = hexColor(info.r, info.g, info.b) .. prefix .. "|r" end
        line = prefix .. " " .. nameDisp .. ": " .. msg
    end
    AddLine(line)
end

-- Capture frame created up front (NOT lazily with the window), so the channel
-- toggles register their events whether or not the console window is open.
local chatFrame = CreateFrame("Frame")
chatFrame:SetScript("OnEvent", function(_, event, ...) OnChatEvent(event, ...) end)

local function UpdateChatRegistration()
    chatFrame:UnregisterAllEvents()
    -- Debug locked → capture nothing, regardless of the saved bucket toggles.
    if not ns.IsDebugUnlocked() then return end
    local c = CCfg() or {}
    local function reg(list, on)
        if not on then return end
        for _, e in ipairs(list) do pcall(chatFrame.RegisterEvent, chatFrame, e) end
    end
    reg(PLAYERS_EVENTS,  c.chPlayers)
    reg(CHANNELS_EVENTS, c.chChannels)
    reg(OTHERS_EVENTS,   c.chOthers)
end

-- Re-apply all console options (panel checkboxes + on creation + at login + profile
-- switch). Also re-applies the saved (now per-profile) window size to an open console.
function ns.Debug_ApplyConsoleOptions()
    if consoleFrame then
        local c = CCfg()
        if c and c.w and c.h then
            consoleFrame:SetSize(c.w, c.h)        -- this profile's saved size
        else
            consoleFrame:SetSize(760, 500)        -- no saved size -> default (matches EnsureConsole)
        end
    end
    LayoutBody()
    ApplySelectionMode()
    UpdateChatRegistration()
end

-- Force-close the console (used by the profile switch when the new profile re-locks the
-- debug suite); mirrors the "I know what I'm doing" un-tick teardown.
function ns.Debug_CloseConsole()
    if consoleFrame then
        consoleFrame:Hide()
        consoleFrame.smf:Clear()
    end
    wipe(lineBuffer)
end

local function EnsureConsole()
    if consoleFrame then return consoleFrame end

    local f = CreateFrame("Frame", "UnbunkUtilityConsole", UIParent, "BackdropTemplate")
    f:SetSize(760, 500)
    f:SetPoint("CENTER")
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(420, 280)
    elseif f.SetMinResize then f:SetMinResize(420, 280) end
    local savedCfg = CCfg()
    if savedCfg and savedCfg.w and savedCfg.h then f:SetSize(savedCfg.w, savedCfg.h) end
    -- Above all normal windows (config window + most addons sit at DIALOG).
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()
    table.insert(UISpecialFrames, "UnbunkUtilityConsole")   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH1")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText(L["Console Mode"])

    local closeBtn = ns.ui.CreateButton({ parent = f, label = "X", width = 24, height = 22 })
    closeBtn.frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    closeBtn.frame:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = ns.ui.CreateButton({ parent = f, label = L["Clear"], width = 70, height = 22 })
    clearBtn.frame:SetPoint("RIGHT", closeBtn.frame, "LEFT", -6, 0)

    -- Start/Stop print toggle (left of Clear) — same state as the Print panel button
    -- and /ubu debug print start|stop; the refresher keeps all of them in sync.
    local printBtn = ns.ui.CreateButton({
        parent = f, label = L["Start print"], width = 90, height = 22,
        onClick = function()
            if ns.Debug_SetUsageActive then
                ns.Debug_SetUsageActive(not (ns.Debug_IsUsageActive and ns.Debug_IsUsageActive()))
            end
        end,
    })
    printBtn.frame:SetPoint("RIGHT", clearBtn.frame, "LEFT", -6, 0)
    if ns.Debug_RegisterUsageRefresh then
        ns.Debug_RegisterUsageRefresh(function()
            printBtn.SetText((ns.Debug_IsUsageActive and ns.Debug_IsUsageActive())
                and L["Stop print"] or L["Start print"])
        end)
    end

    local smf = CreateFrame("ScrollingMessageFrame", nil, f)
    smf:SetFontObject("ChatFontNormal")
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetMaxLines(LINE_CAP)
    smf:SetHyperlinksEnabled(true)
    smf:EnableMouse(true)        -- needed so hyperlinks (and copy selection) react
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        elseif delta > 0 then self:ScrollUp() else self:ScrollDown() end
        if f.smfSB then f.smfSB.Update() end
    end)
    -- Clickable / hoverable links (item, spell, player, achievement, …).
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then SetItemRef(link, text, button, self) end
    end)
    smf:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    smf:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    f.smf = smf

    -- Clear wipes both the live log and the replay buffer (set after smf exists so
    -- the handler captures the real smf, not a nil global).
    clearBtn.frame:SetScript("OnClick", function()
        smf:Clear()
        wipe(lineBuffer)
    end)

    -- Addon-styled scrollbar for the live log (smf offset model). "Allow selection"
    -- makes the smf itself copyable in place (ApplySelectionMode) — no extra frame.
    f.smfSB = CreateMessageScrollBar(f, smf)

    local input = CreateFrame("EditBox", nil, f)
    input:SetHeight(INPUT_H)
    input:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    input:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    input:SetAutoFocus(false)
    input:SetFontObject("ChatFontNormal")
    input:SetTextInsets(6, 4, 2, 2)
    local ibg = input:CreateTexture(nil, "BACKGROUND")
    ibg:SetAllPoints(input)
    ibg:SetColorTexture(0.12, 0.12, 0.12, 0.95)
    input:SetScript("OnEnterPressed", function(self) RunConsoleInput(self:GetText()); self:SetText("") end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.input = input

    -- ── Swallow C / V while the console is open ────────────────────────────────
    -- Pressing C or V here must NOT fire a game keybind (cast a spell, open a bound
    -- window). Copy (Ctrl+C on the selectable log) is handled by the engine's text-copy
    -- system and paste (Ctrl+V) by the input EditBox, BOTH before this binding gate — so
    -- copy/paste keep working while the bare C / V keybinds are eaten. Every other key is
    -- propagated so normal keybinds still fire. While the input EditBox has focus this
    -- handler doesn't run (the EditBox owns the keystrokes), so typing c / v and Ctrl+V
    -- paste behave normally. EnableKeyboard only intercepts while the frame is shown.
    f:EnableKeyboard(true)
    local function KeyGate(self, key)
        self:SetPropagateKeyboardInput(key ~= "C" and key ~= "V")
    end
    f:SetScript("OnKeyDown", KeyGate)
    f:SetScript("OnKeyUp", KeyGate)

    -- Bottom-right resize triangle: drag to size the window freely; the new size is
    -- saved (account-wide) and restored on the next open.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    local gNorm = grip:GetNormalTexture(); if gNorm then gNorm:SetVertexColor(0.7, 0.7, 0.7) end
    local gHi   = grip:GetHighlightTexture(); if gHi then ns.SetBrandVertex(gHi) end
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local c = CCfg()
        if c then c.w = math.floor(f:GetWidth() + 0.5); c.h = math.floor(f:GetHeight() + 0.5) end
        LayoutBody()
    end)
    f.grip = grip

    -- Live re-layout while dragging the grip (anchored regions auto-resize, but the
    -- scrollbar thumb needs a recompute) and a refresh once shown.
    f:SetScript("OnSizeChanged", function() LayoutBody() end)
    f:HookScript("OnShow", function()
        C_Timer.After(0.05, function()
            if f.smfSB then f.smfSB.Update() end
        end)
    end)

    consoleFrame = f

    -- Replay the buffered history (print mirror is hooked eagerly at load, above).
    for _, line in ipairs(lineBuffer) do smf:AddMessage(line) end

    ns.Debug_ApplyConsoleOptions()
    return f
end

function ns.Debug_ToggleConsole()
    if not ns.IsDebugUnlocked() then return end   -- debug locked: refuse to open
    local f = EnsureConsole()
    if f:IsShown() then f:Hide() else f:Show(); f:Raise() end
end

-- ── Debug panel ───────────────────────────────────────────────────────────────
local function CreateDebugPanel(parent)
    local menu

    local function ConsoleToggle(label, key)
        return {
            type  = "checkbox",
            label = label,
            get   = function() local c = CCfg(); return c and c[key] == true end,
            set   = function(v)
                local c = CCfg()
                if c then c[key] = v and true or false end
                if ns.Debug_ApplyConsoleOptions then ns.Debug_ApplyConsoleOptions() end
            end,
        }
    end

    -- Like ConsoleToggle but with a grey H6 hint to the RIGHT of the checkbox label.
    local function ConsoleToggleHint(label, key, hint)
        return {
            type   = "custom",
            height = 24,
            build  = function(host)
                local function get() local c = CCfg(); return c and c[key] == true end
                local cb = ns.ui.CreateCheckbox({
                    parent  = host,
                    label   = label,
                    checked = get(),
                    onClick = function(v)
                        local c = CCfg()
                        if c then c[key] = v and true or false end
                        if ns.Debug_ApplyConsoleOptions then ns.Debug_ApplyConsoleOptions() end
                    end,
                })
                cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                local h = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                h:SetPoint("LEFT", cb.label, "RIGHT", 10, 0)
                h:SetTextColor(0.6, 0.6, 0.6)
                h:SetText(hint)
                return { frame = host, height = 24, Refresh = function() cb.SetChecked(get()) end }
            end,
        }
    end

    -- Channel-bucket toggle: checkbox + a grey detail line listing exactly which
    -- channels it activates (a separate line so the long lists don't overflow).
    local function ChannelToggle(label, key, detail)
        return {
            type   = "custom",
            height = 42,
            build  = function(host)
                local function get() local c = CCfg(); return c and c[key] == true end
                local cb = ns.ui.CreateCheckbox({
                    parent  = host,
                    label   = label,
                    checked = get(),
                    onClick = function(v)
                        local c = CCfg()
                        if c then c[key] = v and true or false end
                        if ns.Debug_ApplyConsoleOptions then ns.Debug_ApplyConsoleOptions() end
                    end,
                })
                cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)

                local d = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                d:SetPoint("TOPLEFT", host, "TOPLEFT", 28, -20)
                d:SetWidth(470)
                d:SetJustifyH("LEFT")
                d:SetTextColor(0.6, 0.6, 0.6)
                d:SetText("(" .. detail .. ")")

                return { frame = host, height = 42, Refresh = function() cb.SetChecked(get()) end }
            end,
        }
    end

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["Debug"] },

        -- "I know what I'm doing" gate — checkbox + PepeEz icon to its right.
        {
            type   = "custom",
            height = 30,
            build  = function(host)
                local cb = ns.ui.CreateCheckbox({
                    parent  = host,
                    label   = L["I know what I'm doing"],
                    checked = ns.IsDebugUnlocked(),
                    onClick = function(val)
                        if ns.db and ns.db.profile then ns.db.profile.debugUnlocked = val and true or false end
                        -- Re-locking must fully shut the suite down: close the window,
                        -- drop any captured chat/prints from memory, and re-apply options
                        -- (UpdateChatRegistration unregisters every chat event while locked).
                        if not val then
                            wipe(lineBuffer)
                            if consoleFrame then
                                consoleFrame:Hide()
                                consoleFrame.smf:Clear()
                            end
                            -- Close any open Graph windows (hiding them cancels their
                            -- sampling tickers via OnHide) so nothing keeps polling once locked.
                            if ns.Debug_CloseGraphs then ns.Debug_CloseGraphs() end
                        end
                        ns.Debug_ApplyConsoleOptions()
                        if ns.Debug_ApplyUsageOptions then ns.Debug_ApplyUsageOptions() end
                        if menu then menu.Rebuild() end
                        if ns.RefreshNav then ns.RefreshNav() end
                    end,
                })
                cb.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)

                local pepe = host:CreateTexture(nil, "ARTWORK")
                pepe:SetSize(22, 22)
                pepe:SetPoint("LEFT", cb.label, "RIGHT", 8, 0)
                pepe:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                pepe:SetTexture(UNBUNK_ICON_PEPE_EZ)

                return {
                    frame   = host, height = 30,
                    Refresh = function() cb.SetChecked(ns.IsDebugUnlocked()) end,
                }
            end,
        },

        -- ── Console mode (gated) ──────────────────────────────────────────────────
        {
            type  = "group",
            title = L["Console mode"],
            shown = function() return ns.IsDebugUnlocked() end,
            build = function()
                return {
                    {
                        type       = "button",
                        label      = L["Open Console Mode"],
                        width      = 180,
                        height     = 22,
                        hostHeight = 28,
                        onClick    = function() if ns.Debug_ToggleConsole then ns.Debug_ToggleConsole() end end,
                    },
                    ConsoleToggle(L["Text editor"],     "textEditor"),
                    ConsoleToggleHint(L["Allow selection"], "allowSelection",
                        L["hold and drag to select, then Ctrl+C to copy"]),

                    {
                        type  = "group",
                        title = L["Channels"],
                        build = function()
                            return {
                                ChannelToggle(L["Activate players messages"], "chPlayers",
                                    L["say, emote, yell, guild, officer, guild announce, whisper, party + leader, raid + leader + warning, instance + leader"]),
                                ChannelToggle(L["Activate channels"], "chChannels",
                                    L["general, trade, local defense, services"]),
                                ChannelToggle(L["Activate others"], "chOthers",
                                    L["everything else"]),
                            }
                        end,
                    },
                }
            end,
        },

        -- ── Special Key (owner access) ────────────────────────────────────────────
        {
            type  = "group",
            title = L["Special Key"],
            shown = function() return ns.IsDebugUnlocked() end,
            build = function()
                return {
                    -- Validate (or Enter) SAVES the typed key to the variables, then clears
                    -- the field — the key is never displayed afterwards (only stored).
                    { type = "custom", height = 30, build = function(host)
                        local input   -- forward-declared so store() captures THIS local
                        local function store()
                            local v = input.GetText()
                            if ns.db and ns.db.global then ns.db.global.specialKey = v or "" end
                            input.SetText(""); input.editBox:ClearFocus()
                            if ns.RefreshNav then ns.RefreshNav() end   -- owner nav appears if key + account match
                        end
                        local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        lbl:SetPoint("LEFT", host, "LEFT", 0, 0)
                        lbl:SetText(L["Key"])
                        input = ns.ui.CreateTextInput({
                            parent = host, width = 200, height = 22, maxLetters = 64, text = "",
                            onEnter = function() store() end,
                        })
                        input.frame:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                        local valBtn = ns.ui.CreateButton({
                            parent = host, label = L["Validate Key"], width = 120, height = 22,
                            onClick = function() store() end,
                        })
                        valBtn.frame:SetPoint("LEFT", input.frame, "RIGHT", 8, 0)
                        return { frame = host, height = 30, Refresh = function() input.SetText("") end }
                    end },
                }
            end,
        },

        -- ── Create an account hash (mint access hashes for specific accounts) ──────
        -- A standalone generator: enter a key, click Generate, and it prints the hash
        -- of (key :: THIS account's BattleTag). Each authorised person runs it on their
        -- account and sends you the value; you bake the values into a future allow-list
        -- to gate features to specific people. (Running it with the owner key reproduces
        -- OWNER_HASH.) It stores nothing — it is purely a generator.
        {
            type  = "group",
            title = L["Create an account hash"],
            shown = function() return ns.IsDebugUnlocked() end,
            build = function()
                return {
                    { type = "custom", height = 30, build = function(host)
                        local lbl = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
                        lbl:SetPoint("LEFT", host, "LEFT", 0, 0)
                        lbl:SetText(L["Key"])
                        local input = ns.ui.CreateTextInput({
                            parent = host, width = 200, height = 22, maxLetters = 64, text = "",
                        })
                        input.frame:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                        local genBtn = ns.ui.CreateButton({
                            parent = host, label = L["Generate account hash"], width = 180, height = 22,
                            onClick = function()
                                -- Prints the hash (saves NOTHING), then clears the field.
                                if ns.Debug_GenerateAccountHash then ns.Debug_GenerateAccountHash(input.GetText()) end
                                input.SetText(""); input.editBox:ClearFocus()
                            end,
                        })
                        genBtn.frame:SetPoint("LEFT", input.frame, "RIGHT", 8, 0)
                        return { frame = host, height = 30 }
                    end },
                }
            end,
        },
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

-- ── Secret scaffolding: owner detection (hashed) + placeholder panels ──────────
-- The owner's BattleTag is NOT stored in clear. We keep a one-way HASH of
-- (secret key :: BattleTag). The secret key is NEVER in the code — the owner types it
-- into Debug > Special Key (saved account-wide as ns.db.global.specialKey). Owner access
-- needs BOTH the right key AND the right Battle.net account, because the hash binds them:
-- a stranger can't paste their own tag (the hash wouldn't match without the key) and the
-- tag can't be read back out of the code (a hash is one-way). The owner sets OWNER_HASH
-- once via Debug > Special Key > "Generate owner hash" (prints the value to paste here).
-- CAVEAT: this only deters CASUAL inspection/tampering. Client Lua ships in the clear and
-- can always be edited to bypass the gate — there is no real client-side security.
local OWNER_HASH = "01c6c812c5d94c88"   -- from Debug > Special Key > "Generate owner hash"

-- 64-bit FNV-1a (two salted passes) -> 16 hex chars. `bit` is WoW's LuaBitOp library.
local FNV_PRIME = 16777619
local function fnvMul(h)   -- (h * FNV_PRIME) mod 2^32, kept precision-exact (h < 2^32)
    local hi = math.floor(h / 65536) % 65536
    local lo = h % 65536
    return ((lo * FNV_PRIME) + ((hi * FNV_PRIME) % 65536) * 65536) % 4294967296
end
local function fnv1a(str, seed)
    local h = seed
    for i = 1, #str do
        h = bit.bxor(h, str:byte(i)) % 4294967296   -- keep h unsigned (bxor can return signed)
        h = fnvMul(h)
    end
    return h
end
local function Hash(str)
    return string.format("%08x%08x", fnv1a(str, 2166136261), fnv1a(str .. "|UU|", 2654435761))
end
local function normKey(k) return (k or ""):gsub("^%s+", ""):gsub("%s+$", "") end   -- trim, keep case
local function normTag(t) return (t or ""):gsub("%s", ""):lower() end               -- trim + case-fold
local function OwnerHashOf(key, tag) return Hash(normKey(key) .. "::" .. normTag(tag)) end

-- The player's own BattleTag, scanned out of BNGetInfo() (its return position varies
-- by client) — the value shaped like "Name#1234". nil if Battle.net is unavailable.
function ns.GetMyBattleTag()
    if not BNGetInfo then return nil end
    -- Scan ALL returns with select() (NOT ipairs over a packed table, which stops at
    -- the first nil hole) for the value shaped like "Name#1234".
    local n = select("#", BNGetInfo())
    for i = 1, n do
        local v = select(i, BNGetInfo())
        if type(v) == "string" and v:find("#", 1, true) then return v end
    end
    return nil
end

-- Owner = right Special Key (Debug tab) AND the right Battle.net account. Both are
-- required because the hash binds them. An empty key or an unset OWNER_HASH -> not owner.
function ns.IsAccountOwner()
    if OWNER_HASH == "" then return false end
    local key = ns.db and ns.db.global and ns.db.global.specialKey
    if not key or key == "" then return false end
    local tag = ns.GetMyBattleTag()
    if not tag then return false end
    return OwnerHashOf(key, tag) == OWNER_HASH
end

-- Print an access hash for a typed key + THIS account's BattleTag. Used to mint hashes
-- to gate future features to specific people: each authorised person runs it on their
-- account with an agreed key and sends you the value, which you bake into an allow-list.
-- Running it with the owner key reproduces OWNER_HASH. Stores nothing — pure generator.
function ns.Debug_GenerateAccountHash(key)
    local tag = ns.GetMyBattleTag()
    if normKey(key) == "" then
        print("|cff338cff[UnbunkUtility]|r " .. (L["Enter a key first."] or "Enter a key first."))
        return
    end
    if not tag then
        print("|cff338cff[UnbunkUtility]|r " .. (L["No BattleTag found (is Battle.net available?)."] or "No BattleTag found."))
        return
    end
    print("|cff338cff[UnbunkUtility]|r ACCOUNT_HASH = \"" .. OwnerHashOf(key, tag) .. "\"")
end

-- Minimal placeholder panel: H2 title + a grey description. New secret sub-tabs
-- start as these stubs until their real content is built.
local function StubPanel(parent, title, desc)
    local h = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    h:SetText(title)
    local d = parent:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
    d:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -12)
    d:SetWidth(480); d:SetJustifyH("LEFT")
    d:SetTextColor(0.6, 0.6, 0.6)
    d:SetText(desc)
    return d
end

-- Secret settings: a "Brand colour" cadre with a colour swatch (opens the native
-- ColorPickerFrame; its swatchFunc fires live while dragging) + a Reset button that
-- restores the base blue. ns.SetBrandColor/ResetBrandColor recolour the whole addon
-- live (Core/Shared.lua).
local function CreateSecretPanel(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText(L["Secret settings"])

    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -52)
    box:SetSize(380, 96)
    box:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local boxTitle = box:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH3")
    boxTitle:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    boxTitle:SetText(L["Change addon color"])

    local hint = box:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
    hint:SetPoint("TOPLEFT", boxTitle, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(352); hint:SetJustifyH("LEFT"); hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L["Changes the blue used everywhere in the addon, live."])

    -- Colour swatch -> addon-styled picker; live-updates the brand colour as you drag.
    local sw = ns.ui.CreateColorSwatch({
        parent = box, width = 40, height = 22, hasOpacity = false,
        getColor = function() local r, g, b = ns.GetBrandColor(); return { r = r, g = g, b = b, a = 1 } end,
        onChange = function(r, g, b) ns.SetBrandColor(r, g, b) end,
    })
    sw.frame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)

    local resetBtn = ns.ui.CreateButton({
        parent = box, label = L["Reset"], width = 70, height = 22,
        onClick = function() ns.ResetBrandColor(); sw.Refresh() end,
    })
    resetBtn.frame:SetPoint("LEFT", sw.frame, "RIGHT", 12, 0)

    -- ── "Change addon font" cadre: pick an LSM font; ns.SetAddonFont re-faces every
    -- addon font object live (no reload). Reset goes back to the default UI face.
    local fbox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    fbox:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -14)
    fbox:SetSize(380, 96)
    fbox:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    fbox:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
    fbox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local ftitle = fbox:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH3")
    ftitle:SetPoint("TOPLEFT", fbox, "TOPLEFT", 12, -10)
    ftitle:SetText(L["Change addon font"])

    local fhint = fbox:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
    fhint:SetPoint("TOPLEFT", ftitle, "BOTTOMLEFT", 0, -6)
    fhint:SetWidth(352); fhint:SetJustifyH("LEFT"); fhint:SetTextColor(0.6, 0.6, 0.6)
    fhint:SetText(L["Changes the font of all the addon's text, live."])

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local fontDD = ns.ui.CreateDropdown({
            parent        = fbox,
            anchorFrame   = fhint,
            width         = 200,
            itemHeight    = 20,
            visibleItems  = 10,
            searchable    = true,
            getList       = function() return LSM:List("font") end,
            getCurrentKey = function() return ns.GetAddonFontKey() end,
            onSelect      = function(name) ns.SetAddonFont(name) end,
        })
        fontDD.SetCurrent(ns.GetAddonFontKey() or L["Default font"])

        local fReset = ns.ui.CreateButton({
            parent = fbox, label = L["Reset"], width = 70, height = 22,
            onClick = function() ns.SetAddonFont(nil); fontDD.SetCurrent(ns.GetAddonFontKey() or L["Default font"]) end,
        })
        fReset.frame:SetPoint("LEFT", fontDD.toggleBtn, "RIGHT", 10, 0)
    else
        local noLSM = fbox:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
        noLSM:SetPoint("TOPLEFT", fhint, "BOTTOMLEFT", 0, -10)
        noLSM:SetTextColor(1, 0.5, 0.2)
        noLSM:SetText(L["LibSharedMedia-3.0 not found."])
    end

    return nil
end

local initDbg = CreateFrame("Frame")
initDbg:RegisterEvent("ADDON_LOADED")
initDbg:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Debug"], nil, CreateDebugPanel)

    -- Secret debug sub-tabs. Registered unconditionally; their visibility in the nav
    -- is gated in Core.lua BuildNavTree (unlock for the secret settings + Addon usage,
    -- owner account for Unbunk).
    UnbunkUtility.RegisterModule(L["Secret settings"], nil, CreateSecretPanel)
    -- "Beta" (Modules/Fader/UI), "Personal utilities" (Modules/DetailsProfile/UI), and
    -- "List" / "Print" / "Graph" (their own files) are real panels registered elsewhere.

    -- Apply saved console options at login (ns.db ready via Core/DB.lua's earlier
    -- ADDON_LOADED), so any enabled chat buckets start capturing immediately.
    if ns.Debug_ApplyConsoleOptions then ns.Debug_ApplyConsoleOptions() end
    self:UnregisterEvent("ADDON_LOADED")
end)
