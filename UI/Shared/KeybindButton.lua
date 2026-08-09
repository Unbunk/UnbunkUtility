-- UI/Shared/KeybindButton.lua
-- Reusable button that captures a NEW key/mouse binding for a WoW binding command
-- (e.g. an addon-registered BINDING_NAME_* action, see Bindings.xml) and applies it live.
--
-- Constraint surfaced by research into Blizzard's own Key Bindings panel: SetBinding()
-- never "replaces" a key -- it only ever ADDS a key -> command mapping, and does NOT clear
-- whatever command already owns the key being assigned. A true rebind is therefore a
-- multi-step affair done here, mirroring KeybindListener:UnbindKey/SetBinding in Blizzard's
-- own Blizzard_Keybindings.lua: unbind the command's current key(s) with SetBinding(key,
-- nil), clear the NEW key's existing owner (if any) the same way, THEN bind the new one --
-- and check that final SetBinding's return value, since Blizzard's own code treats it as a
-- real failure mode rather than assuming it always succeeds. Every real Blizzard call site
-- also does this synchronously inside a hardware-event handler (OnKeyDown / OnClick), never
-- from a timer -- so this widget captures and applies the binding inline in those same
-- handlers.
--
-- Usage:
--   local kb = ns.ui.CreateKeybindButton({
--       parent  = panel,
--       command = "MY_ADDON_COMMAND",   -- a name already declared via BINDING_NAME_* / Bindings.xml
--       width   = 140,
--       height  = 22,
--   })
--   kb.frame     -- button frame
--   kb.Refresh() -- re-reads GetBindingKey(command) and updates the label (useful since
--                -- Blizzard's own Key Bindings panel could also change this same command)
--
-- Controls: left-click starts "listening" (label -> "..."), then the next key or mouse
-- button press is captured as the new binding. ESCAPE cancels listening with no change.
-- Right-click (while not listening) clears the binding entirely.

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

-- Blizzard click-registration button names -> SetBinding/GetBindingKey key names.
local CLICK_TO_KEY = {
    LeftButton   = "BUTTON1",
    RightButton  = "BUTTON2",
    MiddleButton = "BUTTON3",
}
local function ClickToBindingKey(button)
    local mapped = CLICK_TO_KEY[button]
    if mapped then return mapped end
    local n = button:match("^Button(%d+)$")
    return n and ("BUTTON" .. n) or nil
end

-- Bare modifier keys / UNKNOWN are never bindable on their own -- keep listening.
local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
    SHIFT = true, CTRL = true, ALT = true, META = true,
    UNKNOWN = true,
}

-- Only one keybind button across the whole UI can be "listening" at a time. Kept at file
-- scope (shared by every button this file creates, not per-instance) so starting to listen
-- on one button cancels any other one left stuck showing "..." elsewhere on screen -- see
-- StartListening below.
local activeListener   -- the currently-listening button's own StopListening function, or nil

function ns.ui.CreateKeybindButton(config)
    local parent  = config.parent
    local command = config.command
    local width   = config.width  or 140
    local height  = config.height or 22

    local result = {}
    local listening = false

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    btn:RegisterForClicks("AnyUp")
    btn:EnableKeyboard(false)

    -- Same border+fill pattern as UI/Shared/Button.lua, for visual parity.
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(btn)
    border:SetColorTexture(0.4, 0.4, 0.4, 1)

    local fill = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetPoint("TOPLEFT",     btn, "TOPLEFT",      1, -1)
    fill:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1,  1)
    fill:SetColorTexture(0.15, 0.15, 0.15, 0.9)

    local function SetBorder(r, g, b) border:SetColorTexture(r, g, b, 1) end
    local function SetFill(v)         fill:SetColorTexture(v, v, v, 0.9) end

    local lbl = btn:CreateFontString(nil, "OVERLAY", "UnbunkUtilityBody")
    lbl:SetPoint("CENTER")

    -- ── Label ─────────────────────────────────────────────────────────────────

    local function CurrentLabel()
        local key1 = GetBindingKey(command)
        if not key1 then return L["Not bound"] end
        local text = GetBindingText and GetBindingText(key1, "KEY_")
        return (text and text ~= "") and text or key1
    end

    function result.Refresh()
        if listening then return end   -- don't clobber the "..." prompt mid-capture
        lbl:SetText(CurrentLabel())
    end

    -- ── Hover / idle visuals ─────────────────────────────────────────────────

    local function ApplyIdleColors()
        SetBorder(0.4, 0.4, 0.4)
        SetFill(0.15)
        lbl:SetTextColor(1, 1, 1, 1)
    end

    local function ApplyHoverColors()
        local r, g, b = ns.GetBrandColor()   -- live brand blue
        SetBorder(r, g, b)
        SetFill(0.22)
        lbl:SetTextColor(r, g, b, 1)
    end

    btn:SetScript("OnEnter", function()
        if listening then return end   -- already held in the brand-coloured "listening" state
        ApplyHoverColors()
    end)
    btn:SetScript("OnLeave", function()
        if listening then return end
        ApplyIdleColors()
    end)

    -- ── Capture ──────────────────────────────────────────────────────────────

    local function StopListening()
        listening = false
        if activeListener == StopListening then activeListener = nil end
        btn:EnableKeyboard(false)
        ApplyIdleColors()
        result.Refresh()
    end

    local function BuildChordString(baseKey)
        -- ALT, CTRL, SHIFT ordering matches the canonical order Blizzard's own chord
        -- helpers/comparators use, so stored strings read consistently everywhere else
        -- GetBindingKey/GetBindingText show them (e.g. the real Key Bindings panel).
        local parts = {}
        if IsAltKeyDown() then parts[#parts + 1] = "ALT" end
        if IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
        if IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
        parts[#parts + 1] = baseKey
        return table.concat(parts, "-")
    end

    local function ApplyBinding(newKey)
        -- SetBinding/SaveBindings are documented #nocombat -- they cannot be called while in
        -- combat lockdown. Bail out (no bindings touched) rather than risk a silent no-op or a
        -- hard error that would abort before StopListening() runs and leave the widget stuck.
        if InCombatLockdown() then
            ns.Print(L["Can't do that in combat."])
            StopListening()
            return
        end
        -- SetBinding only ever ADDS a key -> command mapping; clear the command's existing
        -- key(s) first so this is a true replace, not a second bind alongside the old one.
        local oldKey1, oldKey2 = GetBindingKey(command)
        if oldKey1 then SetBinding(oldKey1, nil) end
        if oldKey2 then SetBinding(oldKey2, nil) end
        -- newKey may already belong to some OTHER command -- SetBinding does not clear that
        -- for us, so do it explicitly (mirrors Blizzard's own KeybindListener:UnbindKey) or
        -- the key would end up shared by two commands and this assignment could lose to it.
        SetBinding(newKey, nil)
        local applied = SetBinding(newKey, command)
        SaveBindings(GetCurrentBindingSet())
        StopListening()
        if not applied then
            -- Matches Blizzard's own KeybindListener:SetBinding, which checks this same
            -- return value and treats false as a real failure rather than assuming success.
            ns.Print(L["Couldn't bind that key."])
        end
    end

    local function TryCapture(rawKey)
        if not rawKey or IGNORED_KEYS[rawKey] then return end   -- keep listening
        -- Left/right click are never bindable, even chorded with a modifier -- matches
        -- Blizzard's own Key Bindings panel (IsKeyPressIgnoredForBinding always excludes
        -- BUTTON1/BUTTON2 regardless of modifiers), since modified clicks are pervasively used
        -- elsewhere in the UI (shift-click item links, etc.) and a bare click is also how this
        -- button itself is operated.
        if rawKey == "BUTTON1" or rawKey == "BUTTON2" then
            return
        end
        ApplyBinding(BuildChordString(rawKey))
    end

    local function ClearBinding()
        if InCombatLockdown() then
            ns.Print(L["Can't do that in combat."])
            return
        end
        local k1, k2 = GetBindingKey(command)
        if k1 then SetBinding(k1, nil) end
        if k2 then SetBinding(k2, nil) end
        SaveBindings(GetCurrentBindingSet())
        result.Refresh()
    end

    local function StartListening()
        -- EnableKeyboard(true) is documented #nocombat, like SetBinding/SaveBindings above
        -- (unlike EnableKeyboard(false) in StopListening, which releases capture rather than
        -- granting it and isn't guarded elsewhere in this file). Bail before touching any
        -- state, so a click made in combat lockdown can't throw mid-handler and leave the
        -- widget stuck showing "..." with the keyboard never actually captured.
        if InCombatLockdown() then
            ns.Print(L["Can't do that in combat."])
            return
        end
        if activeListener then activeListener() end   -- cancel whichever other button was listening
        listening = true
        activeListener = StopListening
        lbl:SetText("...")
        ApplyHoverColors()
        btn:EnableKeyboard(true)
    end

    btn:SetScript("OnKeyDown", function(self, key)
        if not listening then return end
        -- SetPropagateKeyboardInput is PROTECTED in combat -- calling it under lockdown
        -- throws ADDON_ACTION_BLOCKED, so skip swallowing there (harmless degradation: the
        -- captured key may also fire whatever it's already bound to, same as not capturing).
        if not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)   -- swallow while capturing
        end
        if key == "ESCAPE" then
            StopListening()   -- cancel: no change
            return
        end
        TryCapture(key)
    end)

    btn:SetScript("OnClick", function(self, mouseButton)
        if not listening then
            if mouseButton == "LeftButton" then
                StartListening()
            elseif mouseButton == "RightButton" then
                ClearBinding()
            end
            return
        end
        TryCapture(ClickToBindingKey(mouseButton))
    end)

    btn:SetScript("OnMouseWheel", function(self, delta)
        if not listening then return end
        TryCapture(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)

    -- A hidden panel mid-capture must release the keyboard grab, or the next OnShow would
    -- still be "half listening" with stale visuals.
    btn:HookScript("OnHide", function()
        if listening then StopListening() end
    end)

    result.frame = btn
    result.Refresh()

    return result
end
