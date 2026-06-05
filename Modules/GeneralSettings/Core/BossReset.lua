-- Modules/GeneralSettings/Core/BossReset.lua
-- Plays a configurable sound when a boss encounter ends WITHOUT a kill (a wipe /
-- reset). Driven by the native ENCOUNTER_END event:
--   * its explicit `success` flag means a kill (1) is never mistaken for a wipe;
--   * it fires immediately (no boss mod and no wipe-confirmation delay — unlike
--     BigWigs_OnBossWipe, which lags a few seconds while it confirms the wipe);
--   * it needs no dependency and fires exactly once, so there is no double.
-- A short debounce guards against the rare case of the event repeating. Config
-- lives in ns.db.global.bossReset (see Core/Shared.lua).

local _, ns = ...
ns.bossReset = ns.bossReset or {}
local BR = ns.bossReset

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(BR)
AceTimer:Embed(BR)

local DEBOUNCE = 3  -- minimum seconds between plays (guards against the event repeating)
local lastPlay = 0

local function Cfg()
    return ns.db and ns.db.global.bossReset
end

-- Guarded play used by the encounter hook.
local function PlayBossReset()
    local cfg = Cfg()
    if not cfg or not cfg.enabled then return end
    local now = GetTime()
    if now - lastPlay < DEBOUNCE then return end  -- already played for this wipe
    lastPlay = now
    ns.PlaySoundFromCfg(cfg, "soundPath", "soundKey")
end

-- Unguarded play for the options "test" button (ignores enabled / debounce).
function BR.PlayTest()
    local cfg = Cfg()
    if not cfg then return end
    ns.PlaySoundFromCfg(cfg, "soundPath", "soundKey")
end

-- Native encounter end: success == 1 is a kill, anything else is a wipe / reset.
-- A boolean `true` is treated as a kill too, so the "never on a kill" guarantee
-- holds regardless of how the client represents the success flag.
-- AceEvent callback signature is (event, ...) — no leading `self` — so the
-- success flag is the 5th payload arg (encounterID, name, difficultyID, groupSize, success).
BR:RegisterEvent("ENCOUNTER_END", function(event, _, _, _, _, success)
    if success ~= 1 and success ~= true then
        PlayBossReset()
    end
end)
