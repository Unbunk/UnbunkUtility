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

-- Account-wide unlock flag. nil / false = locked (the default).
function ns.IsDebugUnlocked()
    return ns.db and ns.db.global and ns.db.global.debugUnlocked == true
end

local function CCfg() return ns.db and ns.db.global and ns.db.global.console end

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

-- Strip WoW escape sequences so copied text is clean plain text (no |cff… codes,
-- no |T texture markup) — hyperlinks collapse to their visible label.
local function stripCodes(s)
    s = s:gsub("|H.-|h(.-)|h", "%1")          -- hyperlink -> its display text
    s = s:gsub("|T.-|t", "")                  -- inline textures (icons)
    s = s:gsub("|K.-|k", "")                  -- masked text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")      -- colour start
    s = s:gsub("|r", "")                      -- colour end
    s = s:gsub("||", "|")                     -- unescape pipes
    return s
end

-- Selection mode shows a read-only EditBox snapshot of the buffer: reliable drag-
-- select + Ctrl+C. Built once on entry and left frozen, so incoming lines can't
-- clear the active selection mid-drag.
local function RebuildEditBox()
    if not consoleFrame or not consoleFrame.edit then return end
    local edit = consoleFrame.edit
    local txt  = stripCodes(table.concat(lineBuffer, "\n"))
    edit._str  = txt
    edit:SetText(txt)
    edit:SetCursorPosition(#txt)
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

-- Show the active view's scrollbar (and refresh its thumb), hide the other.
local function RefreshScrollBars()
    if not consoleFrame or not consoleFrame.smfSB then return end
    if (CCfg() or {}).allowSelection == true then
        consoleFrame.smfSB.track:Hide()
        consoleFrame.selSB.Update()
    else
        consoleFrame.selSB.track:Hide()
        consoleFrame.smfSB.Update()
    end
end

local function LayoutBody()
    if not consoleFrame then return end
    local c = CCfg() or {}
    consoleFrame.input:SetShown(c.textEditor ~= false)
    local bottom = (c.textEditor ~= false) and (12 + INPUT_H + 6) or 12
    for _, region in ipairs({ consoleFrame.smf, consoleFrame.scroll }) do
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", consoleFrame, "TOPLEFT", 12, -46)
        region:SetPoint("BOTTOMRIGHT", consoleFrame, "BOTTOMRIGHT", -26, bottom)
    end
    -- Both tracks share the right-hand gutter; only the active view shows one.
    for _, bar in ipairs({ consoleFrame.smfSB, consoleFrame.selSB }) do
        bar.track:ClearAllPoints()
        bar.track:SetPoint("TOPRIGHT", consoleFrame, "TOPRIGHT", -12, -46)
        bar.track:SetPoint("BOTTOMRIGHT", consoleFrame, "BOTTOMRIGHT", -12, bottom)
    end
    consoleFrame.edit:SetWidth(consoleFrame:GetWidth() - 52)
    RefreshScrollBars()
end

-- Toggle between the live ScrollingMessageFrame and the copyable EditBox snapshot.
local function ApplySelectionMode()
    if not consoleFrame then return end
    local sel = (CCfg() or {}).allowSelection == true
    consoleFrame.smf:SetShown(not sel)
    consoleFrame.scroll:SetShown(sel)
    if sel then RebuildEditBox() end
    RefreshScrollBars()
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

-- Re-apply all console options (panel checkboxes + on creation + at login).
function ns.Debug_ApplyConsoleOptions()
    LayoutBody()
    ApplySelectionMode()
    UpdateChatRegistration()
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
        if f.edit then f.edit._str = ""; f.edit:SetText("") end
    end)

    -- Copyable snapshot (selection mode): read-only multiline EditBox in a PLAIN
    -- scroll frame (no UIPanelScrollFrameTemplate, so no default Blizzard scrollbar —
    -- we attach our own addon-styled bar below to match the rest of the UI).
    local scroll = CreateFrame("ScrollFrame", nil, f)
    local edit   = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetMaxLetters(0)
    edit:SetWidth(f:GetWidth() - 48)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only: revert any typed change so it stays a faithful copy buffer
    -- (selecting/copying never triggers OnTextChanged, so it stays usable).
    edit:SetScript("OnTextChanged", function(self, user)
        if user and self._str and self:GetText() ~= self._str then
            self:SetText(self._str)
        end
    end)
    scroll:SetScrollChild(edit)
    scroll:Hide()
    f.scroll = scroll
    f.edit   = edit

    -- Addon-styled scrollbars (same look as ns.ui.CreateScrollBar everywhere else):
    -- one for the selection snapshot (real ScrollFrame) and one for the live log
    -- (smf offset model). LayoutBody anchors both tracks in the right gutter;
    -- RefreshScrollBars shows only the active view's bar.
    f.selSB = ns.ui.CreateScrollBar({
        parent       = f,
        scrollFrame  = scroll,
        itemHeight   = 14,
        visibleItems = 20,
        getListSize  = function() return math.max(20, #lineBuffer) end,
    })
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
    local gHi   = grip:GetHighlightTexture(); if gHi then gHi:SetVertexColor(0.20, 0.55, 1.0) end
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local c = CCfg()
        if c then c.w = math.floor(f:GetWidth() + 0.5); c.h = math.floor(f:GetHeight() + 0.5) end
        LayoutBody()
    end)
    f.grip = grip

    -- Live re-layout while dragging the grip (anchored regions auto-resize, but the
    -- edit width + scrollbar thumbs need a recompute) and a refresh once shown.
    f:SetScript("OnSizeChanged", function() LayoutBody() end)
    f:HookScript("OnShow", function()
        C_Timer.After(0.05, function()
            if f.smfSB then f.smfSB.Update() end
            if f.selSB then f.selSB.Update() end
        end)
    end)

    consoleFrame = f

    -- Replay the buffered history into the freshly-built log.
    for _, line in ipairs(lineBuffer) do smf:AddMessage(line) end

    -- Hook the global print ONCE so every print() also lands in the console.
    if not ns._consoleHooked then
        ns._consoleHooked = true
        local origPrint = print
        print = function(...)
            origPrint(...)
            if not ns.IsDebugUnlocked() then return end   -- locked: don't mirror
            local n, parts = select("#", ...), {}
            for i = 1, n do parts[i] = tostring((select(i, ...))) end
            AddLine(table.concat(parts, " "))
        end
    end

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
                        if ns.db then ns.db.global.debugUnlocked = val and true or false end
                        -- Re-locking must fully shut the suite down: close the window,
                        -- drop any captured chat/prints from memory, and re-apply options
                        -- (UpdateChatRegistration unregisters every chat event while locked).
                        if not val then
                            wipe(lineBuffer)
                            if consoleFrame then
                                consoleFrame:Hide()
                                consoleFrame.smf:Clear()
                                if consoleFrame.edit then consoleFrame.edit._str = ""; consoleFrame.edit:SetText("") end
                            end
                        end
                        ns.Debug_ApplyConsoleOptions()
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
                    ConsoleToggle(L["Allow selection"], "allowSelection"),

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
    }

    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
    return menu
end

-- ── Secret scaffolding: owner detection + placeholder panels ──────────────────
-- Hard-coded owner identity: the secret "Unbunk" nav category (Core.lua
-- BuildNavTree) is shown only on this Battle.net account. To find a tag in-game:
--   /run print(BNGetInfo())
local OWNER_BATTLETAG = "REDACTED"   -- owner account; gates the secret "Unbunk" nav

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

-- True only on the owner's Battle.net account (gates the secret "Unbunk" nav).
-- Tolerant compare (trim + case-fold) so stray spacing/case can't cause a miss.
local function normTag(t) return (t or ""):gsub("%s", ""):lower() end
function ns.IsAccountOwner()
    local tag = ns.GetMyBattleTag()
    return tag ~= nil and normTag(tag) == normTag(OWNER_BATTLETAG)
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

local initDbg = CreateFrame("Frame")
initDbg:RegisterEvent("ADDON_LOADED")
initDbg:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Debug"], nil, CreateDebugPanel)

    -- Secret debug sub-tabs. Registered unconditionally; their visibility in the nav
    -- is gated in Core.lua BuildNavTree (unlock for the secret settings + Addon usage,
    -- owner account for Unbunk).
    UnbunkUtility.RegisterModule(L["Secret settings"], nil, function(parent)
        StubPanel(parent, L["Secret settings"], L["Hidden developer settings — work in progress."])
        return nil
    end)
    UnbunkUtility.RegisterModule(L["Print"], nil, function(parent)
        StubPanel(parent, L["Print"], L["Addon usage — print log (work in progress)."]); return nil
    end)
    UnbunkUtility.RegisterModule(L["Graph"], nil, function(parent)
        StubPanel(parent, L["Graph"], L["Addon usage — graph (work in progress)."]); return nil
    end)
    UnbunkUtility.RegisterModule(L["Overview"], nil, function(parent)
        StubPanel(parent, L["Unbunk"], L["Owner-only secret area — work in progress."]); return nil
    end)

    -- Apply saved console options at login (ns.db ready via Core/DB.lua's earlier
    -- ADDON_LOADED), so any enabled chat buckets start capturing immediately.
    if ns.Debug_ApplyConsoleOptions then ns.Debug_ApplyConsoleOptions() end
    self:UnregisterEvent("ADDON_LOADED")
end)
