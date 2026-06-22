-- Core/AuraDispatch.lua
-- One shared, coalescing UNIT_AURA broadcaster for the whole addon.
--
-- Why this exists: ~7 modules independently subscribed UNIT_AURA. Three of them
-- (BL/PI/Racial trackers) used AceEvent, which has no unit filter, so they woke
-- for EVERY unit's aura change in a raid and discarded the non-"player" fires in
-- Lua. The rest each ran their own RegisterUnitEvent + full refresh, so a single
-- player UNIT_AURA (which fires many times per second in combat) fanned out into
-- N full module refreshes.
--
-- This module owns ONE RegisterUnitEvent("UNIT_AURA", unit) frame per watched
-- unit token (player/focus/...) and coalesces a burst of events in a single
-- frame into ONE next-frame callback round, so subscribers run at most once per
-- frame no matter how many UNIT_AURA the game fires. Subscribers register a
-- lightweight callback instead of owning an event frame.

local ADDON, ns = ...

local D = {}
ns.AuraDispatch = D

-- unit token -> { frame, subs = {cb,...}, pending = bool, flush = fn }
local units = {}

local function ensure(unit)
    local u = units[unit]
    if u then return u end

    u = { subs = {}, pending = false }

    -- One persistent flush closure per unit (reused across bursts so we don't
    -- allocate a closure every frame; only the C_Timer.After timer object is
    -- transient, and at most one is live per unit per frame).
    u.flush = function()
        u.pending = false
        local subs = u.subs
        for i = 1, #subs do
            local cb = subs[i]
            -- pcall so one misbehaving subscriber can't break the others.
            local ok, err = pcall(cb, unit)
            if not ok and ns.Print then
                ns.Print("|cffff4444AuraDispatch error|r: " .. tostring(err))
            end
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_AURA", unit)
    f:SetScript("OnEvent", function()
        -- Coalesce: schedule a single next-frame flush per burst.
        if u.pending then return end
        u.pending = true
        C_Timer.After(0, u.flush)
    end)

    u.frame = f
    units[unit] = u
    return u
end

-- Register a callback fired (coalesced, next frame) whenever `unit`'s auras
-- change. Returns the callback so callers can keep it for Unregister.
function D.Register(unit, cb)
    if type(cb) ~= "function" then return end
    local u = ensure(unit)
    u.subs[#u.subs + 1] = cb
    return cb
end

function D.Unregister(unit, cb)
    local u = units[unit]
    if not u then return end
    local subs = u.subs
    for i = #subs, 1, -1 do
        if subs[i] == cb then table.remove(subs, i) end
    end
end
