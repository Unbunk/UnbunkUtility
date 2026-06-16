-- Modules/BuffGroups/Core/BuffGroups.lua
-- Engine for the custom CDM Buff groups. We take the native BuffIconCooldownViewer as the
-- SOURCE of buffs (its TrackedBuff category) and REUSE its real icon frames: each active
-- frame is moved (pinned) into the movable container of its assigned group, exactly like the
-- Essentials/Utility rows, so Blizzard keeps rendering cooldown / charges / combat state.
-- Buffs are split across groups via ns.db.profile.buffGroups (drag in the config); a buff's
-- DEFAULT group follows the CDM's HideByDefault flag (shown -> Group 1, hidden -> Unused).
-- "Unused" frames are parked off-screen.

local _, ns = ...
ns.BuffGroups = ns.BuffGroups or {}
local BG = ns.BuffGroups

local GAP   = 2
local CAT_BUFF  = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff
local HIDE_FLAG = Enum and Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideByDefault
-- A cooldown is "hidden in the CDM" via the HideByDefault flag on its info.flags (the exact
-- test the reference CDM addon uses), NOT via the GetCooldownViewerCategorySet arg.
local function IsHiddenInfo(info)
    return (info and info.flags and HIDE_FLAG and FlagsUtil and FlagsUtil.IsSet
        and FlagsUtil.IsSet(info.flags, HIDE_FLAG)) or false
end

local containers = {}   -- containers[groupId] = Frame (one movable row per group)
local trackedCache      -- array of displayed-buff spellIds (= the viewer's pool frame ids)

-- ── Spell helpers ─────────────────────────────────────────────────────────────
local function SpellTexture(spellId)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId)
    return tex or 134400
end
BG.SpellTexture = SpellTexture
function BG.SpellName(spellId)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    return (info and info.name) or ("[" .. tostring(spellId) .. "]")
end

-- The spell id of a native buff frame — the key used everywhere (config list AND live pin)
-- so they always match. Reads ns.CDMAnchor.NativeFrameSpellId (the .cooldownInfo field), then
-- falls back to the GetCooldownInfo()/GetSpellID() methods some buff frames use instead.
local function FrameSpellId(nf)
    local id = ns.CDMAnchor and ns.CDMAnchor.NativeFrameSpellId and ns.CDMAnchor.NativeFrameSpellId(nf)
    if id then return id end
    local ci = nf.GetCooldownInfo and nf:GetCooldownInfo()
    if type(ci) == "table" then
        local s = ci.overrideTooltipSpellID or ci.overrideSpellID or ci.spellID
        if s and (not issecretvalue or not issecretvalue(s)) and s > 0 then return s end
    end
    if nf.GetSpellID then
        local s = nf:GetSpellID()
        if s and (not issecretvalue or not issecretvalue(s)) and s > 0 then return s end
    end
    return nil
end
BG.FrameSpellId = FrameSpellId

-- ── Displayed-buff enumeration ─────────────────────────────────────────────────
-- The buffs we can show are exactly the ones the native CDM DISPLAYS: the viewer keeps one
-- pool frame per displayed buff (hidden buffs have no frame). So that pool IS the source —
-- both for the config list and the live layout — keyed by the frame's spell id, which sidesteps
-- the GetCooldownViewerCooldownInfo-vs-frame override id mismatch. Refreshed on spec change.
local function CollectDisplayed()
    local out, seen = {}, {}
    local frames = (ns.CDMAnchor and ns.CDMAnchor.EnumBuffIcons and ns.CDMAnchor.EnumBuffIcons()) or {}
    for _, nf in ipairs(frames) do
        local sid = FrameSpellId(nf)
        if sid and not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
    end
    return out
end

function BG.RefreshTracked()
    trackedCache = CollectDisplayed()
    -- Seed each displayed buff's order into Group 1 (the default), in the CDM's own order. The
    -- GROUP is dynamic (BG.GroupOf): unassigned -> Group 1; only manual drags persist.
    for _, sid in ipairs(trackedCache) do
        if BG.RawAssign(sid) == nil then BG.AppendOrder(1, sid) end
    end
    return trackedCache
end

-- All buffs the config knows about: the displayed (pool) buffs + user-added customs (deduped),
-- computed live so the list always reflects the current CDM display set.
function BG.AllBuffs()
    local out = CollectDisplayed()
    local seen = {}
    for _, sid in ipairs(out) do seen[sid] = true end
    for _, sid in ipairs(BG.CustomList()) do
        if not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
    end
    return out
end

-- ── Per-buff icon ─────────────────────────────────────────────────────────────
-- ── Group containers + layout (reusing the REAL native buff frames) ───────────
local pinned = {}      -- set of native frames we currently own (released when disabled)
local offscreen        -- a hidden anchor far off-screen that parks "unused" frames

local function OffscreenAnchor()
    if offscreen then return offscreen end
    offscreen = CreateFrame("Frame", nil, UIParent)
    offscreen:SetSize(1, 1)
    offscreen:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    return offscreen
end

local function GetContainer(groupId)
    if containers[groupId] then return containers[groupId] end
    local f = CreateFrame("Frame", "UnbunkUtilityBuffGroup" .. groupId, UIParent, "BackdropTemplate")
    f:SetSize(1, 1)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    containers[groupId] = f
    return f
end

local function ReleaseAllPins()
    for nf in pairs(pinned) do ns.CDMAnchor.ReleaseNativePin(nf) end
    wipe(pinned)
end

-- The spell id of a native buff frame, matching the config-side enumeration. Falls back to
-- the GetCooldownInfo()/GetSpellID() methods in case a buff frame exposes its info that way
-- rather than via the .cooldownInfo field that ns.CDMAnchor.NativeFrameSpellId reads.
local function FrameSpellId(nf)
    local id = ns.CDMAnchor.NativeFrameSpellId(nf)
    if id then return id end
    local ci = nf.GetCooldownInfo and nf:GetCooldownInfo()
    if type(ci) == "table" then
        local s = ci.overrideTooltipSpellID or ci.overrideSpellID or ci.spellID
        if s and (not issecretvalue or not issecretvalue(s)) and s > 0 then return s end
    end
    if nf.GetSpellID then
        local s = nf:GetSpellID()
        if s and (not issecretvalue or not issecretvalue(s)) and s > 0 then return s end
    end
    return nil
end

-- ── Public refresh ────────────────────────────────────────────────────────────
-- Like the reference addon: reuse the REAL native buff frames (Blizzard keeps rendering their cooldown,
-- charges and combat state — nothing to read or recompute). Each ACTIVE frame is pinned into
-- its assigned group's container (the same re-impose hook as the CDM rows, so the native
-- viewer's own relayout can't pull it back); "unused" buffs are parked far off-screen. When
-- the module is off, every pin is released so Blizzard lays the native viewer out normally.
function BG.RefreshLayout()
    if not BG.Enabled() then
        ReleaseAllPins()
        for _, c in pairs(containers) do c:Hide() end
        return
    end

    -- Bucket the active native frames by their assigned group.
    local byGroup = {}
    for _, nf in ipairs(ns.CDMAnchor.EnumBuffIcons()) do
        local sid = FrameSpellId(nf)
        local gid = sid and BG.GroupOf(sid) or 0
        byGroup[gid] = byGroup[gid] or {}
        byGroup[gid][#byGroup[gid] + 1] = { nf = nf, sid = sid }
    end

    -- Unused (group 0): park off-screen so they show nowhere.
    for _, item in ipairs(byGroup[0] or {}) do
        ns.CDMAnchor.ReleaseNativePin(item.nf)
        ns.CDMAnchor.PinNativeTo(item.nf, OffscreenAnchor(), 0, 0)
        pinned[item.nf] = true
    end

    for _, g in ipairs(BG.GroupList()) do
        local container = GetContainer(g.id)
        local iconW, iconH = g.iconW or 32, g.iconH or 32
        if not g.unlocked then
            container:ClearAllPoints()
            container:SetPoint("CENTER", UIParent, "CENTER", g.posX or 0, g.posY or 0)
        end

        -- Order this group's frames by the saved group order.
        local list = byGroup[g.id] or {}
        local rank = {}
        for i, sid in ipairs(BG.GetGroupBuffs(g.id)) do rank[sid] = i end
        table.sort(list, function(a, b) return (rank[a.sid] or 1e9) < (rank[b.sid] or 1e9) end)

        -- The viewer keeps a frame per displayed buff and shows it only while the aura is up.
        -- Pack the currently-SHOWN ones left→right in the group; park the inactive ones
        -- off-screen so they don't flash at the native spot when they proc (the ticker re-packs
        -- within ~0.2s).
        local x, shownN = 0, 0
        for _, item in ipairs(list) do
            local nf = item.nf
            if nf.IsShown and nf:IsShown() then
                ns.CDMAnchor.PinNativeTo(nf, container, x, 0, iconW, iconH)
                ns.CDMAnchor.ApplyFrameBorder(nf, g.borderEnabled ~= false, g.borderColor, g.borderSize)
                x = x + iconW + GAP
                shownN = shownN + 1
            else
                ns.CDMAnchor.PinNativeTo(nf, OffscreenAnchor(), 0, 0)
            end
            pinned[nf] = true
        end
        local total = (shownN > 0) and (x - GAP) or iconW
        container:SetSize(math.max(1, total), iconH)
        container:SetShown(shownN > 0 or g.unlocked)
    end
end
BG.ApplyAll = BG.RefreshLayout

-- Full rebuild after spec/profile change: refresh the tracked set, drop stale containers
-- for deleted groups, re-layout.
function BG.Rebuild()
    BG.RefreshTracked()
    for gid, c in pairs(containers) do
        if not BG.GetGroup(gid) then c:Hide() end
    end
    BG.RefreshLayout()
end

-- ── Per-group unlock / drag ───────────────────────────────────────────────────
function BG.IsGroupUnlocked(groupId)
    local c = containers[groupId]
    return c and c:IsMovable() and c:IsMouseEnabled() or false
end

function BG.SetGroupUnlocked(groupId, val)
    local g = BG.GetGroup(groupId); if not g then return end
    local c = GetContainer(groupId)
    if val then
        g.unlocked = true
        c:ClearAllPoints()
        c:SetPoint("CENTER", UIParent, "CENTER", g.posX or 0, g.posY or 0)
        c:SetSize(math.max(g.iconW or 32, 32), math.max(g.iconH or 32, 32))
        c:SetMovable(true); c:EnableMouse(true)
        c:RegisterForDrag("LeftButton")
        c:SetScript("OnDragStart", function(self) self:StartMoving() end)
        c:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local es, ues = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local fx, fy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if not (fx and ux and es > 0) then return end
            -- Container is LEFT-anchored content; convert its CENTER back to a CENTER offset
            -- so the saved posX/posY match LayoutGroup's CENTER re-anchor.
            local x = math.floor((fx * es - ux * ues) / es)
            local y = math.floor((fy * es - uy * ues) / es)
            BG.GSet(groupId, "posX", x)
            BG.GSet(groupId, "posY", y)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
            if BG.pe and BG.pe[groupId] then BG.pe[groupId].Refresh() end
        end)
        c:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        ns.SetBrandBorder(c, 0.8)
        c:Show()
    else
        g.unlocked = false
        c:SetMovable(false); c:EnableMouse(false)
        c:SetScript("OnDragStart", nil); c:SetScript("OnDragStop", nil)
        c:SetBackdrop(nil)
        BG.RefreshLayout()
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────
-- The tracked-buff SET changes on spec / talent change (and at load); the per-frame
-- placement is re-applied on a light ticker (cheap SetPoints) so buffs that appear or
-- expire get pinned into / out of their group within ~0.2s.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function() BG.RefreshTracked() end)

local accum = 0
ev:SetScript("OnUpdate", function(_, dt)
    accum = accum + dt
    if accum < 0.2 then return end
    accum = accum - 0.2
    BG.RefreshLayout()
end)

ns.RegisterReloadHook(function() BG.Rebuild() end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    BG.Rebuild()
    self:UnregisterEvent("PLAYER_LOGIN")
end)

-- ── Diagnostic: /run UU_BuffDebug() ───────────────────────────────────────────
-- Dumps what the addon actually sees so we can stop guessing: the hidden-flag API, each
-- tracked cooldown's resolved spellId + RAW flags value + hidden verdict + assigned group,
-- and every live frame it enumerates (spellId / shown / group). Paste the output back.
function BG.Debug()
    local function p(...) print("|cff338cff[BuffDebug]|r", ...) end
    p("HIDE_FLAG =", tostring(HIDE_FLAG), "| FlagsUtil =", tostring(FlagsUtil ~= nil))
    local v = _G.BuffIconCooldownViewer
    p("viewer =", tostring(v ~= nil), "| pool =", tostring(v and v.itemFramePool ~= nil),
      "| viewer:IsShown =", tostring(v and v.IsShown and v:IsShown()))
    -- Raw pool probe (BEFORE any filter): tells "pool empty" apart from "frames rejected".
    if v and v.itemFramePool and v.itemFramePool.EnumerateActive then
        local n, sample = 0, nil
        for f in v.itemFramePool:EnumerateActive() do n = n + 1; sample = sample or f end
        p("raw pool active =", n)
        if sample then
            p(string.format("  sample: shown=%s Icon=%s cooldownInfo=%s GetCooldownInfo=%s GetSpellID=%s",
                tostring(sample.IsShown and sample:IsShown()), tostring(sample.Icon ~= nil),
                tostring(sample.cooldownInfo ~= nil), tostring(sample.GetCooldownInfo ~= nil),
                tostring(sample.GetSpellID ~= nil)))
        end
    end
    p("children =", v and #({ v:GetChildren() }) or "?")
    local ids
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        local ok, r = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, CAT_BUFF, true)
        ids = ok and r or nil
    end
    p("category ids =", type(ids) == "table" and #ids or tostring(ids))
    if type(ids) == "table" then
        for i, cdID in ipairs(ids) do
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            local sid = info and (info.overrideTooltipSpellID or info.overrideSpellID or info.spellID)
            p(string.format("  cd=%s sid=%s flags=%s hidden=%s grp=%s",
                tostring(cdID), tostring(sid), tostring(info and info.flags),
                tostring(IsHiddenInfo(info)), tostring(sid and BG.GroupOf(sid))))
            if i >= 15 then p("  ...(truncated)"); break end
        end
    end
    local frames = (ns.CDMAnchor and ns.CDMAnchor.EnumBuffIcons and ns.CDMAnchor.EnumBuffIcons()) or {}
    p("enumerated live frames =", #frames)
    for i, nf in ipairs(frames) do
        local sid = FrameSpellId(nf)
        p(string.format("  frame sid=%s shown=%s grp=%s",
            tostring(sid), tostring(nf.IsShown and nf:IsShown()), tostring(sid and BG.GroupOf(sid))))
        if i >= 15 then break end
    end
end
_G.UU_BuffDebug = BG.Debug
