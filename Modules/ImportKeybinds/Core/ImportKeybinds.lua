-- Modules/ImportKeybinds/Core/ImportKeybinds.lua
-- Owner utility: capture the current character's action-bar CONTENTS (spells / macros / items
-- placed in the bar slots) into ONE account-wide template, then re-apply it on any other
-- character with a click. Modelled on ActionBarSaver: read with GetActionInfo, write with
-- PickupSpell / PickupItem / PickupMacro + PlaceAction.
--
-- Scope (decided with the user): CONTENTS only — NOT key bindings (those are account-wide by
-- default on modern retail) and NOT macro recreation. A single UNIVERSAL template: applying it
-- on a different class simply SKIPS the slots whose spell the character doesn't know and any
-- macro that doesn't exist on the character. Placement is ADDITIVE (it overwrites the template
-- slots, leaves every other slot untouched) and works OUT OF COMBAT only (placing an action is
-- forbidden to insecure code in combat).
--
-- Storage is account-wide (ns.db.global.importKeybinds) so the template is shared by every
-- character. Purely on-demand (button-driven): no events, no ticker.

local _, ns = ...
ns.ImportKeybinds = ns.ImportKeybinds or {}
local IK = ns.ImportKeybinds

-- Every action slot, 1-180. 1-120 = the 10 classic pages (which Dominos / other bar addons map their
-- bars onto in ANY arrangement, incl. the main bar's alt pages 13-24 and the form/bonus pages 73-120);
-- 121-132 = the last bonus bar — this is where the mounted / skyriding "bar 1" override lives, so it MUST
-- be captured; 145-180 = MultiActionBars 5-7. 133-144 (vehicle/possess) is normally empty and captured
-- harmlessly. A slot ID maps to the same on-screen position on every character, so a raw slot is portable.
local BAR_RANGES = {
    { 1, 180 },
}
local BAR_SLOTS = {}
for _, r in ipairs(BAR_RANGES) do
    for s = r[1], r[2] do BAR_SLOTS[#BAR_SLOTS + 1] = s end
end

-- ── Small API shims (globals vary slightly across patches) ────────────────────
local function SpellKnown(id)
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return nil
end

local function BaseSpell(id)
    if C_Spell and C_Spell.GetBaseSpell then return C_Spell.GetBaseSpell(id) or id end
    return id
end

local function ItemName(id)
    if C_Item and C_Item.GetItemInfo then return (C_Item.GetItemInfo(id)) end
    if GetItemInfo then return (GetItemInfo(id)) end
    return nil
end

-- ── Template state (account-wide) ─────────────────────────────────────────────
local function Store()
    if not ns.db then return nil end
    ns.db.global.importKeybinds = ns.db.global.importKeybinds or {}
    return ns.db.global.importKeybinds
end

function IK.TemplateInfo()
    local s = ns.db and ns.db.global and ns.db.global.importKeybinds
    if not s or not s.template or #s.template == 0 then return nil end
    return s.meta or { count = #s.template }
end

function IK.HasTemplate()
    return IK.TemplateInfo() ~= nil
end

-- A mount on a bar can be stored three ways: as a "summonmount" (id = mountID), as the mount's
-- summon SPELL, or as a mount ITEM. Resolve any of them to the canonical mountID, else nil.
local function MountIDOf(kind, id)
    if kind == "summonmount" then return id end
    if not C_MountJournal then return nil end
    if kind == "spell" and C_MountJournal.GetMountFromSpell then return C_MountJournal.GetMountFromSpell(id) end
    if kind == "item"  and C_MountJournal.GetMountFromItem  then return C_MountJournal.GetMountFromItem(id) end
    return nil
end

-- ── Capture: snapshot THIS character's bars into the one account-wide template ─
function IK.Capture()
    if InCombatLockdown() then return false, "combat" end
    local s = Store(); if not s then return false, "nodb" end
    local tpl = {}
    for _, slot in ipairs(BAR_SLOTS) do
        local kind, id, subType = GetActionInfo(slot)
        if kind then
            local e = { slot = slot, subType = subType }
            local mountID = MountIDOf(kind, id)
            if mountID then
                -- Store mounts by mountID (class-independent) + their summon spell, so import can
                -- place them however the client allows (see PickupMount).
                e.kind    = "mount"
                e.mountID = mountID
                if C_MountJournal.GetMountInfoByID then
                    local name, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
                    e.spellID = spellID
                    e.name    = name
                    e.icon    = icon
                end
            elseif kind == "spell" then
                e.kind = "spell"
                e.id   = BaseSpell(id)
                e.name = SpellName(e.id)
                if C_Spell and C_Spell.GetSpellTexture then e.icon = C_Spell.GetSpellTexture(e.id) end
            elseif kind == "macro" then
                -- Macro slots are per-character indices; save the NAME (+ body for reference)
                -- so import can re-find the macro by name on another character. GetMacroInfo's 2nd
                -- return is the icon.
                e.kind      = "macro"
                local name, icon, body = GetMacroInfo(id)
                e.macroName = name
                e.macroBody = body
                e.name      = name
                e.icon      = icon
            elseif kind == "item" then
                e.kind = "item"
                e.id   = id
                e.name = ItemName(id)
                if C_Item and C_Item.GetItemIconByID then e.icon = C_Item.GetItemIconByID(id) end
            else
                e.kind = kind
                e.id   = id
            end
            -- Universal fallback icon (whatever the action slot displays) when the per-type lookup missed.
            if not e.icon and GetActionTexture then e.icon = GetActionTexture(slot) end
            tpl[#tpl + 1] = e
        end
    end
    local _, class = UnitClass("player")
    s.template = tpl
    s.meta = { char = UnitName("player"), class = class, count = #tpl }
    return true, #tpl
end

-- ── Import: place the template onto THIS character's bars (additive) ───────────
-- Patch 11.0 (The War Within) namespaced the spell/item pickups into C_Spell / C_Item and
-- REMOVED the old globals — `PickupSpell` is nil on current clients. Resolve once, preferring
-- the C_ API and falling back to the global (matches LibActionButton-1.0's PickupAny).
local PickupSpellFn = (C_Spell and C_Spell.PickupSpell) or _G.PickupSpell
local PickupItemFn  = (C_Item  and C_Item.PickupItem)   or _G.PickupItem
local PlaceActionFn = _G.PlaceAction

-- Put the right thing on the cursor for one template entry. Returns false to skip the slot
-- (unknown spell, missing macro, unsupported type or missing API) without touching the bar.
local function PickupEntry(e)
    local k = e.kind
    if k == "spell" then
        if not (PickupSpellFn and SpellKnown(e.id)) then return false end   -- unknown on this class / no API => skip
        PickupSpellFn(e.id)
    elseif k == "item" then
        if not PickupItemFn then return false end
        PickupItemFn(e.id)
    elseif k == "macro" then
        local idx = e.macroName and GetMacroIndexByName(e.macroName) or 0
        if not idx or idx == 0 or not PickupMacro then return false end     -- macro absent (per-char) => skip
        PickupMacro(idx)
    elseif k == "equipmentset" then
        if not (C_EquipmentSet and C_EquipmentSet.PickupEquipmentSet) then return false end
        pcall(C_EquipmentSet.PickupEquipmentSet, e.id)
    elseif k == "companion" then
        if not PickupCompanion then return false end
        pcall(PickupCompanion, e.subType or "MOUNT", e.id)
    elseif k == "battlepet" then
        if not (C_PetJournal and C_PetJournal.PickupPet) then return false end
        pcall(C_PetJournal.PickupPet, e.id)
    else
        return false                                        -- mounts handled separately / flyout / unknown => skip
    end
    return true
end

-- Mounts are fiddly: C_MountJournal.Pickup takes a DISPLAY index (NOT a mountID), a mount can be
-- stored several ways, and the summon is also a spell. Try each route and accept only when the
-- CORRECT mount (or its spell) actually lands on the cursor — so a wrong guess self-skips.
local function PickupMount(mountID, spellID)
    if not (mountID and C_MountJournal) then return false end
    -- Don't place a mount this character hasn't collected.
    if C_MountJournal.GetMountInfoByID then
        local collected = select(11, C_MountJournal.GetMountInfoByID(mountID))
        if collected == false then return false end
    end
    local function cursorIsMount()
        local ct, cid = GetCursorInfo()
        return ct == "mount" and cid == mountID
    end
    if C_MountJournal.Pickup then
        -- A) some client versions accept the mountID directly.
        ClearCursor(); pcall(C_MountJournal.Pickup, mountID)
        if cursorIsMount() then return true end
        -- B) resolve the display index for this mountID, then Pickup(index).
        ClearCursor()
        local n = C_MountJournal.GetNumDisplayedMounts and C_MountJournal.GetNumDisplayedMounts() or 0
        for i = 1, n do
            if select(12, C_MountJournal.GetDisplayedMountInfo(i)) == mountID then
                ClearCursor(); pcall(C_MountJournal.Pickup, i)
                if cursorIsMount() then return true end
                break
            end
        end
    end
    -- C) fall back to the mount's summon spell.
    if spellID and PickupSpellFn then
        ClearCursor(); pcall(PickupSpellFn, spellID)
        local ct = GetCursorInfo()
        if ct == "mount" or ct == "spell" then return true end
    end
    ClearCursor()
    return false
end

local function PlaceOne(e)
    ClearCursor()
    if e.kind == "mount" then
        if PlaceActionFn and PickupMount(e.mountID, e.spellID) then
            PlaceActionFn(e.slot); ClearCursor(); return true
        end
        ClearCursor(); return false
    end
    if not PickupEntry(e) then ClearCursor(); return false end
    -- Self-correcting: only place if the pickup actually put something on the cursor, so an
    -- unsupported/mismatched type is skipped instead of clearing the slot.
    if PlaceActionFn and GetCursorInfo() then
        PlaceActionFn(e.slot)
        ClearCursor()
        return true
    end
    ClearCursor()
    return false
end

function IK.Import()
    if InCombatLockdown() then return false, "combat" end
    local s = ns.db and ns.db.global and ns.db.global.importKeybinds
    local tpl = s and s.template
    if not tpl or #tpl == 0 then return false, "empty" end
    local placed, skipped = 0, 0
    for _, e in ipairs(tpl) do
        if e.enabled == false then
            -- excluded by the user in "Edit template" — leave the slot untouched
        elseif PlaceOne(e) then
            placed = placed + 1
        else
            skipped = skipped + 1
        end
    end
    ClearCursor()
    return true, placed, skipped
end

-- ── Clear: empty every captured action slot on THIS character ──────────────────
-- Wipes the SAME 1-180 range Capture reads (all classic pages + bonus/mounted bar + MultiActionBars),
-- so it clears exactly the bars a capture would snapshot. PickupAction lifts a slot's action onto the
-- cursor; ClearCursor discards it, leaving the slot empty. Out-of-combat only, like Capture / Import.
function IK.ClearAll()
    if InCombatLockdown() then return false, "combat" end
    if not (PickupAction and ClearCursor and HasAction) then return false, "noapi" end
    local cleared = 0
    for _, slot in ipairs(BAR_SLOTS) do
        if HasAction(slot) then
            ClearCursor()
            PickupAction(slot)
            ClearCursor()
            cleared = cleared + 1
        end
    end
    ClearCursor()
    return true, cleared
end

-- ── Key bindings (separate from bar contents) ─────────────────────────────────
-- Capture every bound command's key(s) into the account-wide store, then re-apply them with
-- SetBinding + SaveBindings (the Dominos pattern). Guarded to out-of-combat.
local SaveBindingsFn = SaveBindings or AttemptToSaveBindings

function IK.BindingsInfo()
    local s = ns.db and ns.db.global and ns.db.global.importKeybinds
    if not (s and s.bindings and #s.bindings > 0) then return nil end
    return { count = #s.bindings }
end

function IK.HasBindings()
    return IK.BindingsInfo() ~= nil
end

function IK.CaptureBindings()
    if InCombatLockdown() then return false, "combat" end
    local s = Store(); if not s then return false, "nodb" end
    local list = {}
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)   -- header rows have no keys => filtered out
        if command and (key1 or key2) then
            list[#list + 1] = { command = command, key1 = key1, key2 = key2 }
        end
    end
    s.bindings = list
    return true, #list
end

function IK.ImportBindings()
    if InCombatLockdown() then return false, "combat" end
    local s = ns.db and ns.db.global and ns.db.global.importKeybinds
    local list = s and s.bindings
    if not list or #list == 0 then return false, "empty" end
    local set = 0
    for _, b in ipairs(list) do
        if b.key1 and SetBinding(b.key1, b.command) then set = set + 1 end
        if b.key2 and SetBinding(b.key2, b.command) then set = set + 1 end
    end
    if SaveBindingsFn then SaveBindingsFn(GetCurrentBindingSet()) end
    return true, set
end
