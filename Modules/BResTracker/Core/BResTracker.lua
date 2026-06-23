-- Modules/BResTracker/Core/BResTracker.lua
-- Tracks the number of battle resurrection charges available in the group/raid
-- shared pool. C_Spell.GetSpellCharges(20484) reports the pool state regardless
-- of the player's class.

local _, ns = ...
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

local AceEvent = LibStub("AceEvent-3.0")
local AceTimer = LibStub("AceTimer-3.0")
AceEvent:Embed(BR)
AceTimer:Embed(BR)

local BRES_SPELL_ID  = 20484    -- Rebirth (represents the shared BRes pool)
local BRES_ICON_ID   = 136080   -- Rebirth icon (fallback)

-- ── Frame ────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame", "BResTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(48, 48)
-- Below HIGH-strata panels (e.g. the talents window) but above Blizzard's
-- Cooldown Manager. See ns.SetTrackerIconStrata.
ns.SetTrackerIconStrata(frame)
frame:Hide()

local iconTex = frame:CreateTexture(nil, "BACKGROUND")
iconTex:SetAllPoints(frame)
iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints(frame)
cooldown:SetHideCountdownNumbers(true)
cooldown:SetDrawEdge(false)

-- ── Border (configurable) ──────────────────────────────────────────────────
-- Mirrors result.ApplyBorder() in UI/Shared/TimerIcon.lua. This tracker uses a
-- custom frame (not TimerIcon), so the four edge textures live on a dedicated
-- child frame raised above the cooldown swipe; ApplyBorder refreshes their
-- thickness / colour / visibility from config.
local borderFrame = CreateFrame("Frame", nil, frame)
borderFrame:SetAllPoints(frame)
borderFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
local borderEdges = {}
for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
    local t = borderFrame:CreateTexture(nil, "OVERLAY")
    t:Hide()
    borderEdges[edge] = t
end

-- Timer + charge count live on a host frame raised ABOVE the border (like
-- TimerIcon's timerHost) so they stay readable over both the cooldown swipe and
-- the configurable border.
local timerHost = CreateFrame("Frame", nil, frame)
timerHost:SetAllPoints(frame)
timerHost:SetFrameLevel(borderFrame:GetFrameLevel() + 1)

local timerText = timerHost:CreateFontString(nil, "OVERLAY")
timerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
timerText:Hide()

local countText = timerHost:CreateFontString(nil, "OVERLAY")
countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
countText:Hide()

-- Internal state for detecting the "charge regained" transition.
local lastCharges = nil
local lastMax     = nil   -- pool size at the last tick, to tell a real consume
                          -- from the pool shrinking (raid losing members)
local lastCooldownStart = 0

-- Cache the last-applied icon texture and charge-count text/colour so the 0.5s
-- ticker only touches the textures when they actually change (the icon is
-- session-constant; the charge count rarely moves). SetTexture / SetText /
-- SetTextColor each re-upload or re-shape, so guarding them off saves per-tick work.
local lastIconTex = nil
local lastCur     = nil
local lastCurColor = nil   -- "g" (green) / "r" (red) / "d" (dimmed dash)

-- Test mode state (shared with PlayerList via the BR namespace).
BR.testMode          = false
BR.testEndsAt        = 0
BR.testCooldownStart = 0
BR.testMembers       = {}
BR.testCooldownEnds  = {}

function BR.RunTest(duration)
    duration = duration or 15
    local now = GetTime()
    BR.testMode          = true
    BR.testEndsAt        = now + duration
    -- ~4:30 remaining inside a 10-min cycle so the cooldown spiral shows motion.
    BR.testCooldownStart = now - 330
    BR.testMembers = {
        { guid = "test1", name = "Drood",  class = "DRUID"       },
        { guid = "test2", name = "Deathk", class = "DEATHKNIGHT" },
        { guid = "test3", name = "Locky",  class = "WARLOCK"     },
        { guid = "test4", name = "Praes",  class = "DRUID"       },
        { guid = "test5", name = "Pala",   class = "PALADIN"     },
    }
    BR.testCooldownEnds = {
        test2 = now + 480,  -- 8:00 remaining
        test4 = now + 150,  -- 2:30 remaining
    }
    BR.ApplyVisuals()
    if BR.RefreshList then BR.RefreshList() end
end

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function IsActiveInCurrentInstance()
    return ns.IsActiveInInstance(BR.CfgGet("instanceFilter"))
end

-- True when a battle-res charge pool CAN exist: in a group, inside an instance
-- whose type passes the filter. That's exactly the relevant content — raid boss
-- encounters and Mythic+ runs. (Out in the open world, or solo, there is no pool.)
-- Combat is intentionally NOT required: in M+ the pool is live the whole run, and
-- in a raid the icon stays visible out of combat showing a dimmed "—" until a boss
-- is pulled. Test mode forces it on for the preview.
function BR.IsContextActive()
    if BR.testMode then return true end
    if not IsInGroup() then return false end
    if not IsInInstance() then return false end
    return IsActiveInCurrentInstance()
end

-- Whether the icon is on screen. The player list is gated on this too, so there is
-- never a list without the icon.
function BR.IconShouldShow()
    return (BR.CfgGet("enabled") and BR.CfgGet("showIcon") and BR.IsContextActive()) and true or false
end

-- The BRes pool icon is constant for the session, so resolve it once and cache
-- it (mirrors PITracker.GetPIIcon). C_Spell.GetSpellInfo can return nil while
-- spell data is still loading, so keep trying (don't cache the nil) until it
-- resolves.
local resolvedIconID
local function ResolveIcon()
    if not resolvedIconID then
        local info = C_Spell.GetSpellInfo(BRES_SPELL_ID)
        resolvedIconID = info and info.iconID
    end
    return resolvedIconID or BRES_ICON_ID
end

-- ── Apply visuals ────────────────────────────────────────────────────────────

function BR.ApplyVisuals()
    -- While unlocked, keep the frame visible for positioning.
    if BR.IsUnlocked() then return end

    -- Auto-stop test mode once the duration elapses.
    if BR.testMode and GetTime() >= BR.testEndsAt then
        BR.testMode = false
        BR.testEndsAt = 0
        BR.testMembers = {}
        BR.testCooldownEnds = {}
    end

    -- Show whenever we're in a relevant context (group + instance, per the filter)
    -- — NOT only when a charge pool is currently active. Outside that, hide and
    -- reset so the first later pool tick is adopted silently.
    if not BR.CfgGet("enabled") or not BR.IsContextActive() then
        frame:Hide()
        lastCharges = nil
        lastMax     = nil
        return
    end

    -- Charge data: real shared pool or fake test values. havePool is false when no
    -- pool exists yet (a raid out of combat) — the icon still shows, dimmed.
    local cur, maxC, cdStart, cdDur, havePool
    if BR.testMode then
        cur, maxC = 2, 3
        cdStart   = BR.testCooldownStart
        cdDur     = 600
        havePool  = true
    else
        local info = C_Spell.GetSpellCharges(BRES_SPELL_ID)
        if info and info.maxCharges and info.maxCharges > 0 then
            cur      = info.currentCharges or 0
            maxC     = info.maxCharges
            cdStart  = info.cooldownStartTime
            cdDur    = info.cooldownDuration
            havePool = true
        else
            havePool = false
        end
    end

    -- Draw the icon when showIcon is on. The charge-transition detection (sounds)
    -- runs below regardless of showIcon, so the ready/used sounds stay independent.
    if BR.CfgGet("showIcon") then
        frame:Show()
        local iconTexID = ResolveIcon()
        if iconTexID ~= lastIconTex then
            iconTex:SetTexture(iconTexID)
            lastIconTex = iconTexID
        end
        iconTex:SetDesaturated(not havePool)

        if havePool then
            -- Charge counter (green when at least one available, red otherwise).
            -- Only re-set the text/colour when the count actually changes.
            if cur ~= lastCur then
                countText:SetText(tostring(cur))
                lastCur = cur
            end
            local color = cur > 0 and "g" or "r"
            if color ~= lastCurColor then
                if cur > 0 then
                    countText:SetTextColor(0, 1, 0, 1)
                else
                    countText:SetTextColor(1, 0, 0, 1)
                end
                lastCurColor = color
            end
            countText:Show()

            -- Cooldown / timer for the next incoming charge.
            if cur < maxC and cdStart and cdStart > 0 then
                local remain = (cdStart + cdDur) - GetTime()
                if remain > 0 then
                    timerText:SetText(ns.FormatMMSS(remain))
                    timerText:Show()
                    if lastCooldownStart ~= cdStart then
                        cooldown:SetCooldown(cdStart, cdDur)
                        lastCooldownStart = cdStart
                    end
                else
                    timerText:Hide()
                    cooldown:Clear()
                    lastCooldownStart = 0
                end
            else
                timerText:Hide()
                cooldown:Clear()
                lastCooldownStart = 0
            end
        else
            -- No pool yet (raid out of combat): dimmed icon, greyed "-", no timer.
            -- lastCur uses the literal "-" as its sentinel so re-entering this
            -- branch on later ticks skips the SetText/SetTextColor churn.
            if lastCur ~= "-" then
                countText:SetText("-")
                lastCur = "-"
            end
            if lastCurColor ~= "d" then
                countText:SetTextColor(0.6, 0.6, 0.6, 1)
                lastCurColor = "d"
            end
            countText:Show()
            timerText:Hide()
            cooldown:Clear()
            lastCooldownStart = 0
        end
    else
        frame:Hide()
    end

    -- Charge transitions (ready/used sounds), run regardless of showIcon but only
    -- while a pool exists. Suppressed during test mode, for a moment after a loading
    -- screen (stale count), and when the pool size changed this tick (a shrinking
    -- raid lowers currentCharges with no actual cast).
    if havePool then
        if not BR.testMode and lastCharges ~= nil and lastMax == maxC and not ns.RecentlyZoned() then
            if cur > lastCharges and BR.CfgGet("soundOnReady") then
                BR.PlaySound()
            elseif cur < lastCharges then
                if BR.AttributeBResCast then BR.AttributeBResCast() end
                if BR.CfgGet("soundOnUsed") then BR.PlaySoundUsed() end
            end
        end
        lastCharges = cur
        lastMax     = maxC
    else
        -- No pool: reset so a later pool start (boss pull -> 1 charge) doesn't fire
        -- a phantom "ready".
        lastCharges = nil
        lastMax     = nil
    end
end

-- ── Apply font / size / position ─────────────────────────────────────────────

function BR.ApplyFont()
    local fontPath = BR.CfgGet("timerFontPath")
    local fontSize = BR.CfgGet("timerFontSize") or 14
    local outline  = BR.CfgGet("timerOutline") or "OUTLINE"
    local c        = BR.CfgGet("timerColor") or { r = 1, g = 1, b = 1, a = 1 }
    local resolved = ns.ResolveFontPath(fontPath, BR.CfgGet("timerFontKey"))

    timerText:SetFont(resolved, fontSize, outline)
    timerText:SetTextColor(c.r, c.g, c.b, c.a or 1)

    local countSize = BR.CfgGet("countFontSize") or 16
    countText:SetFont(resolved, countSize, outline)
end

-- True when the NEW "Cooldown groups" engine OWNS this tracker's dest: it then folds this frame into
-- its group layout and drives SetPoint/SetSize itself. The frame must YIELD its own placement/sizing
-- so the engine isn't stomped (the engine still calls SetSlotSize directly, so that does NOT yield).
function BR.EngineOwns()
    if not BR.CfgGet("includeInCdm") then return false end
    local dest = BR.CfgGet("cdmDest") or "essential"   -- match GetIconDescriptors' nil→essential fold
    return ns.CDMGroups and ns.CDMGroups.OwnsDest and ns.CDMGroups.OwnsDest(dest) or false
end

function BR.ApplyPosition()
    -- The NEW groups engine owns this dest: it positions + sizes the frame in its own RefreshLayout
    -- (2x/sec). Do NOTHING here — re-anchoring it would fight the engine's SetPoint/SetSize.
    if BR.EngineOwns() then return end
    -- Cooldown Manager integration: ns.CDMAnchor owns this frame's position (and,
    -- for native-row destinations, its size). The below-player artificial row is
    -- always available; the essential/utility rows only when their viewer exists.
    -- Don't self-anchor in either case — just request a refresh.
    -- ns.CDMIncludedVal (not raw includeInCdm) so a disabled Cooldown Manager
    -- falls through to the free SetPoint below instead of stranding the frame.
    if ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) and ns.CDMAnchor
        and (BR.CfgGet("cdmDest") == "belowPlayer"
            or (ns.GetCDMViewer and ns.GetCDMViewer(BR.CfgGet("cdmDest")))) then
        ns.CDMAnchor.RefreshAll()
        return
    end
    -- Free: positioned on screen by posX/posY.
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        BR.CfgGet("posX") or 0,
        BR.CfgGet("posY") or 0)
end

-- Follow the native Cooldown Manager: when this custom frame is anchored to a
-- viewer, ns.CDMAnchor re-applies its position whenever the viewer relayouts /
-- moves. In slot mode it also sizes the frame to the native row via SetSlotSize.
-- Registered once at module load (mirrors TimerIcon's self-registration).
if ns.CDMAnchor then
    ns.CDMAnchor.Register({
        apply   = BR.ApplyPosition,
        frame   = frame,
        getCfg  = BR.CfgGet,
        setCfg  = function(key, val) BR.CfgSet(key, val) end,   -- cdmAtEnd flip on a cross-strip drag
        setSize = function(w, h) BR.SetSlotSize(w, h) end,
        getIcon = function() return ResolveIcon() end,
    })
end

function BR.ApplySize()
    -- The NEW groups engine owns this dest: it sizes the frame via SetSlotSize (below) to the group's
    -- iconW/iconH. The module's own ApplySize must NOT impose the configured size (it would fight the
    -- engine 2x/sec) — yield entirely. SetSlotSize (the engine's direct call) still applies the size.
    if BR.EngineOwns() then return end
    -- A native-row destination (essential/utility) is sized to the native icons by
    -- ns.CDMAnchor, so do NOT override it with the configured size (just refresh
    -- font/border). Below-player and free icons use the configured size.
    local dest = ns.CDMIncludedVal(BR.CfgGet("includeInCdm")) and BR.CfgGet("cdmDest")
    local matchNative = (dest == "essential" or dest == "utility")
        and ns.GetCDMViewer and ns.GetCDMViewer(dest)
    if not matchNative then
        local w = BR.CfgGet("iconWidth") or 48
        local h = BR.CfgGet("iconHeight") or 48
        frame:SetSize(w, h)
    end
    BR.ApplyFont()
    BR.ApplyBorder()
end

-- Called by ns.CDMAnchor in slot mode to match the native row's icon size. The
-- iconTex / cooldown / borderFrame textures are SetAllPoints(frame) so they
-- follow the resize; we only re-apply the font (size-independent here) and border.
function BR.SetSlotSize(w, h)
    w = math.max(8, math.min(512, w or 48))
    h = math.max(8, math.min(512, h or 48))
    frame:SetSize(w, h)
    BR.ApplyFont()
    BR.ApplyBorder()
end

-- Draw / refresh the configurable border from config (borderEnabled,
-- borderColor, borderSize). Reproduces result.ApplyBorder() from
-- UI/Shared/TimerIcon.lua. Cheap; safe to call on every size / reload pass.
function BR.ApplyBorder()
    if not BR.CfgGet("borderEnabled") then
        for _, t in pairs(borderEdges) do t:Hide() end
        return
    end
    local size = math.max(1, math.min(16, BR.CfgGet("borderSize") or 1))
    local c = BR.CfgGet("borderColor") or { r = 0, g = 0, b = 0, a = 1 }
    local r, g, b, a = c.r or 0, c.g or 0, c.b or 0, c.a or 1
    for _, t in pairs(borderEdges) do t:SetColorTexture(r, g, b, a) end

    borderEdges.top:ClearAllPoints()
    borderEdges.top:SetPoint("TOPLEFT")
    borderEdges.top:SetPoint("TOPRIGHT")
    borderEdges.top:SetHeight(size)

    borderEdges.bottom:ClearAllPoints()
    borderEdges.bottom:SetPoint("BOTTOMLEFT")
    borderEdges.bottom:SetPoint("BOTTOMRIGHT")
    borderEdges.bottom:SetHeight(size)

    borderEdges.left:ClearAllPoints()
    borderEdges.left:SetPoint("TOPLEFT")
    borderEdges.left:SetPoint("BOTTOMLEFT")
    borderEdges.left:SetWidth(size)

    borderEdges.right:ClearAllPoints()
    borderEdges.right:SetPoint("TOPRIGHT")
    borderEdges.right:SetPoint("BOTTOMRIGHT")
    borderEdges.right:SetWidth(size)

    for _, t in pairs(borderEdges) do t:Show() end
end

-- ── Drag / unlock ────────────────────────────────────────────────────────────

function BR.SetUnlocked(val)
    if val then
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Don't read GetPoint(): StartMoving can leave the frame on a different
            -- anchor/relativePoint than the CENTER/UIParent/CENTER that ApplyPosition
            -- re-applies, so its xOfs/yOfs would be in that other anchor's space and
            -- the icon would teleport on the next locked tick. Compute the centre
            -- offset from UIParent directly (scale-normalised) and re-anchor to a
            -- single CENTER point so the saved offset and the live frame stay in sync
            -- (mirrors TimerIcon.OnDragStop).
            local es, ues = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local fx, fy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if not (fx and ux and es and es > 0) then return end
            local x = math.floor((fx * es - ux * ues) / es)
            local y = math.floor((fy * es - uy * ues) / es)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
            BR.CfgSet("posX", x)
            BR.CfgSet("posY", y)
            if BR.pe then BR.pe.Refresh() end
        end)
        frame:SetBackdrop({
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        ns.SetBrandBorder(frame, 0.8)   -- live brand blue
        -- Preview: show the icon and a fake count so the user sees what they
        -- are positioning even when out of group.
        iconTex:SetTexture(ResolveIcon())
        iconTex:SetDesaturated(false)
        cooldown:Clear()
        timerText:Hide()
        countText:SetText("1")
        countText:SetTextColor(0, 1, 0, 1)
        countText:Show()
        frame:Show()
    else
        frame:SetMovable(false)
        frame:EnableMouse(false)
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        frame:SetBackdrop(nil)
        lastCharges = nil
        -- The unlock preview wrote the icon/count textures directly (bypassing the
        -- per-tick caches), so invalidate them: ApplyVisuals below must re-apply
        -- the real icon/count even if they happen to match the cached values.
        lastIconTex  = nil
        lastCur      = nil
        lastCurColor = nil
        -- Restore the real state immediately (group / cooldown / list).
        BR.ApplyVisuals()
        if BR.RefreshList then BR.RefreshList() end
    end
end

function BR.IsUnlocked()
    return frame:IsMovable() and frame:IsMouseEnabled()
end

function BR.GetFrame() return frame end

-- ── Events ───────────────────────────────────────────────────────────────────

local function OnVisualsRefresh(event)
    BR.ApplyVisuals()
end
BR:RegisterEvent("PLAYER_ENTERING_WORLD", OnVisualsRefresh)
BR:RegisterEvent("ZONE_CHANGED_NEW_AREA", OnVisualsRefresh)
BR:RegisterEvent("GROUP_ROSTER_UPDATE", OnVisualsRefresh)
BR:RegisterEvent("SPELL_UPDATE_CHARGES", OnVisualsRefresh)

-- Ticker: refreshes the mm:ss countdown and catches charge regained.
-- Early-out when disabled so a turned-off module does ~zero per-tick work.
BR:ScheduleRepeatingTimer(function()
    if not BR.CfgGet("enabled") then return end
    BR.ApplyVisuals()
    if BR.RefreshList then BR.RefreshList() end
end, 0.5)

-- Reload hook: re-applies everything when a profile is loaded.
ns.RegisterReloadHook(function()
    BR.ApplyPosition()
    BR.ApplyFont()
    BR.ApplySize()
    BR.ApplyBorder()
    BR.ApplyVisuals()
    if BR.ApplyListPosition then BR.ApplyListPosition() end
    if BR.RefreshList then BR.RefreshList() end
end)

local initBR = CreateFrame("Frame")
initBR:RegisterEvent("PLAYER_LOGIN")
initBR:SetScript("OnEvent", function(self)
    BR.ApplyPosition()
    BR.ApplyFont()
    BR.ApplySize()
    BR.ApplyVisuals()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
