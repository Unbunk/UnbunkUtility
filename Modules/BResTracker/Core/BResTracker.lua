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

local function ResolveIcon()
    local info = C_Spell.GetSpellInfo(BRES_SPELL_ID)
    return (info and info.iconID) or BRES_ICON_ID
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

    if not BR.CfgGet("enabled") then
        frame:Hide()
        lastCharges = nil
        return
    end
    -- Test mode bypasses the instance filter so the preview always works.
    if not BR.testMode and not IsActiveInCurrentInstance() then
        frame:Hide()
        lastCharges = nil
        return
    end

    -- Source of the data: real shared pool or fake test values.
    local cur, maxC, cdStart, cdDur
    if BR.testMode then
        cur, maxC = 2, 3
        cdStart   = BR.testCooldownStart
        cdDur     = 600
    else
        local info = C_Spell.GetSpellCharges(BRES_SPELL_ID)
        if not info or not info.maxCharges or info.maxCharges == 0 then
            -- No BRes pool (solo / group too small).
            frame:Hide()
            lastCharges = nil
            return
        end
        cur     = info.currentCharges or 0
        maxC    = info.maxCharges
        cdStart = info.cooldownStartTime
        cdDur   = info.cooldownDuration
    end

    -- Render the icon only when showIcon is on, but keep running the charge-
    -- transition detection below regardless: the ready/used sounds are separate
    -- toggles, and short-circuiting here used to also leave lastCharges stale
    -- (a phantom sound when the icon was later re-enabled).
    if BR.CfgGet("showIcon") then
        frame:Show()
        iconTex:SetTexture(ResolveIcon())

        -- Charge counter (green when at least one available, red otherwise).
        countText:SetText(tostring(cur))
        if cur > 0 then
            countText:SetTextColor(0, 1, 0, 1)
        else
            countText:SetTextColor(1, 0, 0, 1)
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
        frame:Hide()
    end

    -- Charge transitions. Suppressed during test mode, for a moment after a
    -- loading screen where the count reads stale (ns.RecentlyZoned), and when the
    -- pool size changed this tick: a shrinking raid lowers currentCharges with no
    -- actual cast, which must not fire the "used" sound / false attribution.
    if not BR.testMode and lastCharges ~= nil and lastMax == maxC and not ns.RecentlyZoned() then
        if cur > lastCharges and BR.CfgGet("soundOnReady") then
            BR.PlaySound()
        elseif cur < lastCharges then
            -- A charge was consumed: attribute the cast to the most recent
            -- BRes-capable caster, and play the "used" sound if enabled.
            if BR.AttributeBResCast then BR.AttributeBResCast() end
            if BR.CfgGet("soundOnUsed") then BR.PlaySoundUsed() end
        end
    end
    lastCharges = cur
    lastMax     = maxC
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

function BR.ApplyPosition()
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
        setSize = function(w, h) BR.SetSlotSize(w, h) end,
    })
end

function BR.ApplySize()
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
            -- A CDM-managed icon is not free-draggable, so a drop is always a plain
            -- screen-offset reposition.
            local _, _, _, x, y = self:GetPoint()
            BR.CfgSet("posX", math.floor(x))
            BR.CfgSet("posY", math.floor(y))
            if BR.pe then BR.pe.Refresh() end
        end)
        frame:SetBackdrop({
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 10,
        })
        frame:SetBackdropBorderColor(1, 1, 0, 0.8)
        -- Preview: show the icon and a fake count so the user sees what they
        -- are positioning even when out of group.
        iconTex:SetTexture(ResolveIcon())
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
