-- Modules/BResTracker/Core/BResTracker.lua
-- Tracks the number of battle resurrection charges available in the group/raid
-- shared pool. C_Spell.GetSpellCharges(20484) reports the pool state regardless
-- of the player's class.

local _, ns = ...
ns.BResTracker = ns.BResTracker or {}
local BR = ns.BResTracker

local BRES_SPELL_ID  = 20484    -- Rebirth (represents the shared BRes pool)
local BRES_ICON_ID   = 136080   -- Rebirth icon (fallback)

-- ── Frame ────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame", "BResTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(48, 48)
-- Render above Blizzard's Cooldown Manager (which sits at MEDIUM strata).
frame:SetFrameStrata("HIGH")
frame:Hide()

local iconTex = frame:CreateTexture(nil, "BACKGROUND")
iconTex:SetAllPoints(frame)
iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints(frame)
cooldown:SetHideCountdownNumbers(true)
cooldown:SetDrawEdge(false)

local timerText = cooldown:CreateFontString(nil, "OVERLAY")
timerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
timerText:Hide()

local countText = frame:CreateFontString(nil, "OVERLAY")
countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
countText:Hide()

-- Internal state for detecting the "charge regained" transition.
local lastCharges = nil
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
        { guid = "test4", name = "Praes",  class = "EVOKER"      },
        { guid = "test5", name = "Huntr",  class = "HUNTER"      },
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

    if not BR.CfgGet("showIcon") then
        frame:Hide()
        return
    end

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
            timerText:SetText(string.format("%d:%02d", remain / 60, remain % 60))
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

    -- Charge transitions (suppressed during test mode).
    if not BR.testMode and lastCharges ~= nil then
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
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        BR.CfgGet("posX") or 0,
        BR.CfgGet("posY") or 0)
end

function BR.ApplySize()
    local w = BR.CfgGet("iconWidth") or 48
    local h = BR.CfgGet("iconHeight") or 48
    frame:SetSize(w, h)
    BR.ApplyFont()
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
        -- Restore the real state immediately (group / cooldown / etc.).
        BR.ApplyVisuals()
    end
end

function BR.IsUnlocked()
    return frame:IsMovable() and frame:IsMouseEnabled()
end

function BR.GetFrame() return frame end

-- ── Events ───────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")

eventFrame:SetScript("OnEvent", function()
    BR.ApplyVisuals()
end)

-- Ticker: refreshes the mm:ss countdown and catches charge regained.
C_Timer.NewTicker(0.5, function()
    if BR.CfgGet("enabled") then
        BR.ApplyVisuals()
        if BR.RefreshList then BR.RefreshList() end
    end
end)

-- Reload hook: re-applies everything when a profile is loaded.
ns.RegisterReloadHook(function()
    BR.ApplyPosition()
    BR.ApplyFont()
    BR.ApplySize()
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
