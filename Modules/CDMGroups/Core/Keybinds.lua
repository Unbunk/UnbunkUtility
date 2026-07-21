-- Modules/CDMGroups/Core/Keybinds.lua
-- Shared keybind resolver for the Cooldown Manager display (ns.CDGKeybinds). Resolves a spellID (or an
-- itemID, for trinkets/potions) to:
--   * a short DISPLAY string for the "Show Keybinds" text on a CDM icon (e.g. "SC4" = Shift-Ctrl-4), and
--   * the raw {key, shift, ctrl, alt} combos for the "Press overlay" (poll IsKeyDown while held).
--
-- Approach: iterate the STANDARD Blizzard action bars (the user runs default bars). Each bar's button
-- frames have a fixed name + a fixed binding-command prefix, so for a button whose current action holds
-- our spell/item we read GetBindingKey(command) directly — no fragile slot→page→command math. The high
-- bars (5/6/7) are best-effort (skipped if their frames don't exist).
--
-- Caching: results are cached per spellID/itemID with a `false` sentinel for "looked up, no binding" so a
-- miss isn't re-scanned every call (avoids the action-bar-scan churn this addon has fought before). The
-- cache is wiped + a version bumped only on binding/bar/spec EVENTS (debounced to the next frame), never
-- per tick. No protected/secure API is touched — taint-free.

local _, ns = ...
local KB = {}
ns.CDGKeybinds = KB

local textCache, rawCache         = {}, {}   -- [spellID] -> text|false ;  [spellID] -> combos|false
local itemTextCache, itemRawCache = {}, {}   -- [itemID]  -> text|false ;  [itemID]  -> combos|false
local version = 0
function KB.GetCacheVersion() return version end

-- (button-frame name prefix, binding-command prefix) for the standard Blizzard bars.
local BARS = {
    { "ActionButton",              "ACTIONBUTTON"          },   -- main bar (current page)
    { "MultiBarBottomLeftButton",  "MULTIACTIONBAR1BUTTON" },
    { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
    { "MultiBarRightButton",       "MULTIACTIONBAR3BUTTON" },
    { "MultiBarLeftButton",        "MULTIACTIONBAR4BUTTON" },
    { "MultiBar5Button",           "MULTIACTIONBAR5BUTTON" },   -- best-effort (frame may not exist)
    { "MultiBar6Button",           "MULTIACTIONBAR6BUTTON" },
    { "MultiBar7Button",           "MULTIACTIONBAR7BUTTON" },
}

local MOD_ABBREV = { SHIFT = "S", CTRL = "C", ALT = "A", META = "M" }
local KEY_ABBREV = {
    MOUSEWHEELUP = "MwU", MOUSEWHEELDOWN = "MwD",
    SPACE = "Spc", ESCAPE = "Esc", INSERT = "Ins", DELETE = "Del", HOME = "Hm", END = "End",
    PAGEUP = "PgU", PAGEDOWN = "PgD", BACKSPACE = "BkSp", ENTER = "Ent", TAB = "Tab",
    NUMPAD0 = "N0", NUMPAD1 = "N1", NUMPAD2 = "N2", NUMPAD3 = "N3", NUMPAD4 = "N4",
    NUMPAD5 = "N5", NUMPAD6 = "N6", NUMPAD7 = "N7", NUMPAD8 = "N8", NUMPAD9 = "N9",
    UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
}

-- "SHIFT-CTRL-4" -> ("SC4", { key="4", shift=true, ctrl=true, alt=false }). The parsed combo is returned
-- ONLY for keyboard keys (press detection polls IsKeyDown); mouse buttons / wheel still format as TEXT
-- (M4 / MwU) but carry no parsed combo (can't reliably poll them).
local function ParseAndFormat(raw)
    if not raw or raw == "" then return nil end
    local parts = { strsplit("-", raw) }
    local n = #parts
    local shift, ctrl, alt, abbr = false, false, false, ""
    for i = 1, n - 1 do
        local m = parts[i]
        if m == "SHIFT" then shift = true elseif m == "CTRL" then ctrl = true elseif m == "ALT" then alt = true end
        abbr = abbr .. (MOD_ABBREV[m] or m:sub(1, 1))
    end
    local key  = parts[n]
    local base = KEY_ABBREV[key]
    if not base then
        local bn = key:match("^BUTTON(%d+)$")
        base = bn and ("M" .. bn) or key
    end
    local text = abbr .. base
    local parsed
    if not (key:find("MOUSEWHEEL") or key:match("^BUTTON%d+$")) then
        parsed = { key = key, shift = shift, ctrl = ctrl, alt = alt }
    end
    return text, parsed
end

-- Scan the standard bars; matchSlot(slot) decides whether an action slot holds our target. Returns the
-- SHORTEST binding text + the list of raw keyboard combos found. Matching by SLOT (not by GetActionInfo's
-- id) lets the spell matcher use C_ActionBar.FindSpellActionButtons, which resolves a spell to its action
-- slots OVERRIDE-AWARE: a cooldown tracked by its BASE spellId still finds the binding when the bar holds
-- the talent/override form (and vice-versa). The old exact id-equality missed those, so some spells never
-- showed a keybind.
local function ResolveByButtons(matchSlot)
    local shortest, raws
    for _, bar in ipairs(BARS) do
        local btnPrefix, bindPrefix = bar[1], bar[2]
        for i = 1, 12 do
            local btn = _G[btnPrefix .. i]
            local slot = btn and (btn.action or (btn.GetAttribute and btn:GetAttribute("action")))
            if slot and matchSlot(slot) then
                for _, rawKey in ipairs({ GetBindingKey(bindPrefix .. i) }) do
                    local text, parsed = ParseAndFormat(rawKey)
                    if text and (not shortest or #text < #shortest) then shortest = text end
                    if parsed then raws = raws or {}; raws[#raws + 1] = parsed end
                end
            end
        end
    end
    return shortest, raws
end

-- The action slots that cast this spell, resolved override-aware by Blizzard. Returns { [slot]=true } or nil.
local function SpellSlotSet(spellID)
    local slots = C_ActionBar and C_ActionBar.FindSpellActionButtons and C_ActionBar.FindSpellActionButtons(spellID)
    if not slots or #slots == 0 then return nil end
    local set = {}
    for _, s in ipairs(slots) do set[s] = true end
    return set
end

local function SpellMatch(spellID)
    local set = SpellSlotSet(spellID)
    return function(slot)
        if set and set[slot] then return true end
        -- Fallback for what FindSpellActionButtons can't see (e.g. a macro that casts the spell).
        local atype, id = GetActionInfo(slot)
        if atype == "spell" then return id == spellID end
        if atype == "macro" and GetMacroSpell then return GetMacroSpell(id) == spellID end
        return false
    end
end
local function ItemMatch(itemID)
    return function(slot)
        local atype, id = GetActionInfo(slot)
        return atype == "item" and id == itemID
    end
end

function KB.GetKeybindText(spellID)
    if not spellID then return nil end
    local c = textCache[spellID]
    if c ~= nil then return c or nil end
    local text, raws = ResolveByButtons(SpellMatch(spellID))
    textCache[spellID] = text or false
    rawCache[spellID]  = (raws and #raws > 0) and raws or false
    return text
end
function KB.GetRawCombos(spellID)        -- press overlay
    if not spellID then return nil end
    if rawCache[spellID] == nil then KB.GetKeybindText(spellID) end
    return rawCache[spellID] or nil
end
function KB.GetKeybindTextForItem(itemID)
    if not itemID then return nil end
    local c = itemTextCache[itemID]
    if c ~= nil then return c or nil end
    local text, raws = ResolveByButtons(ItemMatch(itemID))
    itemTextCache[itemID] = text or false
    itemRawCache[itemID]  = (raws and #raws > 0) and raws or false
    return text
end
function KB.GetRawCombosForItem(itemID)
    if not itemID then return nil end
    if itemRawCache[itemID] == nil then KB.GetKeybindTextForItem(itemID) end
    return itemRawCache[itemID] or nil
end

-- ── Invalidation (debounced to next frame) ───────────────────────────────────
-- Consumers hook ns.CDGKeybinds.onInvalidate (chained) to repaint immediately on a rebind / bar swap;
-- otherwise the engine's / tracker's own ticker picks the change up within its interval.
local function Invalidate()
    wipe(textCache); wipe(rawCache); wipe(itemTextCache); wipe(itemRawCache)
    version = version + 1
    if KB.onInvalidate then KB.onInvalidate() end
end

local pending = false
local function Debounce()
    if pending then return end
    pending = true
    C_Timer.After(0, function() pending = false; Invalidate() end)
end

local ev = CreateFrame("Frame")
for e in pairs({
    UPDATE_BINDINGS = 1, ACTIONBAR_SLOT_CHANGED = 1, ACTIONBAR_PAGE_CHANGED = 1,
    UPDATE_BONUS_ACTIONBAR = 1, UPDATE_OVERRIDE_ACTIONBAR = 1, UPDATE_VEHICLE_ACTIONBAR = 1,
    PLAYER_SPECIALIZATION_CHANGED = 1, TRAIT_CONFIG_UPDATED = 1, PLAYER_ENTERING_WORLD = 1,
}) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function() Debounce() end)
