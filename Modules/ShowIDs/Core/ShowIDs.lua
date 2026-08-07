-- Modules/ShowIDs/Core/ShowIDs.lua
-- Extra utility: append spell / item / icon / quest / NPC IDs to game tooltips. Each is an
-- independent toggle (all OFF by default). The hooks are wired ONCE at load and gated at
-- fire-time by the saved flags (same pattern as the Debug print mirror), so toggling a
-- checkbox takes effect immediately with no reload. Spell/item/icon/NPC ride the modern
-- tooltip data processor (one AllTypes post-call, dispatched by data.type — the EnhanceQoL
-- approach, which is what makes buffs/auras and NPCs work); quests don't flow through it, so
-- they hook the quest-log title button instead.

local ADDON, ns = ...
ns.ShowIDs = ns.ShowIDs or {}
local SI = ns.ShowIDs

local DEFAULTS = {
    spell = false,   -- append "Spell ID: n" to spell tooltips
    item  = false,   -- append "Item ID: n" to item tooltips
    icon  = false,   -- append "Icon ID: n" (the icon's texture file ID) to spell + item tooltips
    quest = false,   -- append "Quest ID: n" to quest-log tooltips
    npc   = false,   -- append "NPC ID: n" (from the unit GUID) to creature tooltips
}

local function Cfg() return ns.db and ns.db.profile and ns.db.profile.showIDs end
SI.Cfg = Cfg

local function InitCfg()
    if not ns.db then return end
    local p = ns.db.profile
    p.showIDs = p.showIDs or {}
    ns.MergeDefaults(p.showIDs, DEFAULTS)
end
ns.RegisterCfgInitHook(InitCfg)

function SI.Get(key)
    local c = Cfg()
    return c and c[key] == true
end
function SI.Set(key, val)
    local c = Cfg()
    if c then c[key] = val and true or false end
end

-- Light blue so the ID line stands apart from the tooltip body without clashing.
local ID_COLOR = { 0.4, 0.7, 1.0 }

-- Append "<Label> ID: <n>" to a tooltip. Called from the data-processor post-call, which
-- already runs on a freshly-rebuilt tooltip each show, so there is no line accumulation.
local function AppendID(tooltip, label, id)
    if not (tooltip and id) then return end
    tooltip:AddLine(label .. " ID: " .. id, ID_COLOR[1], ID_COLOR[2], ID_COLOR[3])
end

-- The icon (texture file ID) of a spell / item, or nil.
local function SpellIconID(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellTexture) then return nil end
    return C_Spell.GetSpellTexture(spellID)
end
local function ItemIconID(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    -- Degrade to the addon's other canonical resolver (never a removed global).
    return select(5, C_Item.GetItemInfoInstant(itemID))
end

-- The unit token a tooltip currently describes, or nil.
local function TooltipUnitToken(tt)
    if GetUnitTokenFromTooltip then
        local u = GetUnitTokenFromTooltip(tt)
        if u then return u end
    end
    if tt and tt.GetUnit then
        local _, u = tt:GetUnit()
        return u
    end
    return nil
end
-- The NPC ID encoded in a Creature / Vehicle GUID (players / pets return nil).
local function NpcIDFromGUID(guid)
    if not guid or (issecretvalue and issecretvalue(guid)) then return nil end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(npcID) end
    return nil
end

-- Classify the tooltip data type. Buffs / debuffs arrive as UnitAura (NOT Spell) — that's
-- why aura tooltips showed no ID — and several other types are spell-backed too, so we treat
-- them all as "spell" (data.id is the underlying spell id). Creatures come through as Unit /
-- Corpse (NPC id derived from the unit GUID). We hook ALL types once and dispatch by
-- data.type (the EnhanceQoL approach) instead of registering per type.
local SPELL_LIKE, ITEM_LIKE, UNIT_LIKE = {}, {}, {}
if Enum and Enum.TooltipDataType then
    local T = Enum.TooltipDataType
    local function mark(set, key) if key ~= nil then set[key] = true end end
    mark(SPELL_LIKE, T.Spell)
    mark(SPELL_LIKE, T.UnitAura)        -- buffs / debuffs (data.id = the aura's spell id)
    mark(SPELL_LIKE, T.AzeriteEssence)
    mark(SPELL_LIKE, T.EnhancedConduit)
    mark(SPELL_LIKE, T.RecipeRankInfo)
    mark(SPELL_LIKE, T.Totem)
    mark(ITEM_LIKE,  T.Item)
    mark(UNIT_LIKE,  T.Unit)            -- creatures / NPCs (id from the unit GUID)
    mark(UNIT_LIKE,  T.Corpse)
end

local function AnyOn() return SI.Get("spell") or SI.Get("item") or SI.Get("icon") or SI.Get("npc") end

-- Wire the modern tooltip data processor (retail). One AllTypes post-call, gated + dispatched.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tt, data)
        if not data or not AnyOn() then return end
        if issecretvalue and (issecretvalue(data.type) or issecretvalue(data.id)) then return end
        local t = data.type
        if SPELL_LIKE[t] then
            if SI.Get("spell") then AppendID(tt, "Spell", data.id) end
            if SI.Get("icon")  then AppendID(tt, "Icon",  SpellIconID(data.id)) end
        elseif ITEM_LIKE[t] then
            if SI.Get("item") then AppendID(tt, "Item", data.id) end
            if SI.Get("icon") then AppendID(tt, "Icon", ItemIconID(data.id)) end
        elseif UNIT_LIKE[t] and SI.Get("npc") then
            -- Prefer the GUID the data processor already carries; fall back to the unit
            -- token only when it's missing. Both can be SECRET (WoW 11.x): NpcIDFromGUID
            -- guards a secret guid (-> no line), and a secret token must NEVER reach
            -- UnitGUID (it ERRORS on secret args, unlike tostring), so guard it too.
            local guid = data.guid
            if guid == nil then
                local unit = TooltipUnitToken(tt)
                if unit and not (issecretvalue and issecretvalue(unit)) then
                    guid = UnitGUID(unit)
                end
            end
            AppendID(tt, "NPC", NpcIDFromGUID(guid))
        end
    end)
end

-- Quest IDs don't flow through the tooltip data processor, so hook the quest-log title
-- button's OnEnter (the EnhanceQoL approach) and append the quest ID to its already-shown
-- tooltip (hence the explicit Show()). Deferred to PLAYER_LOGIN so the global exists.
local function HookQuestTooltip()
    if SI._questHooked or type(QuestMapLogTitleButton_OnEnter) ~= "function" then return end
    SI._questHooked = true
    hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(self)
        if not SI.Get("quest") then return end
        local qid = self and self.questID
        if qid and GameTooltip:IsShown() then
            AppendID(GameTooltip, "Quest", qid)
            GameTooltip:Show()
        end
    end)
end
local questHookFrame = CreateFrame("Frame")
questHookFrame:RegisterEvent("PLAYER_LOGIN")
questHookFrame:SetScript("OnEvent", function(self) HookQuestTooltip(); self:UnregisterEvent("PLAYER_LOGIN") end)
