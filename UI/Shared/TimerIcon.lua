-- UI/Shared/TimerIcon.lua
-- Reusable icon with countdown timer widget.
--
-- Usage:
--   local ti = ns.ui.CreateTimerIcon({
--       name       = "MyTimerIcon",
--       getCfg     = function(key) return MyCfg_Get(key) end,
--       onDragStop = function(x, y) ... end,
--   })
--   ti.SetIcon(textureId)
--   ti.SetTimer(expiry, duration, color) — duration draws the CD swipe, color overrides timer text color
--   ti.ClearTimer()
--   ti.ShowCheck()  / ti.HideCheck() — persistent green check on/off
--   ti.BlinkCheck() — flash the check briefly then hide (use on CD-ready)
--   ti.SetGlow(bool) — toggle the pixel glow around the icon
--   ti.Show()
--   ti.Hide()
--   ti.IsShown()
--   ti.SetUnlocked(bool)
--   ti.IsUnlocked()
--   ti.ApplySize()
--   ti.ApplyPosition()
--   ti.ApplyFont()
--   ti.GetFrame()
--   ti.onExpire = function() ... end  -- optional callback fired when the timer expires

local _, ns = ...

ns.ui = ns.ui or {}

-- The most urgent matching tier for `total` seconds remaining: the entry with the
-- smallest `at` threshold the time has fallen to or below. tiers = { {at=, scale=,
-- color={r,g,b,a}}, ... } (order-independent). Returns nil when none apply.
local function MatchTier(tiers, total)
    local best
    for _, ti in ipairs(tiers) do
        local at = ti.at or 0
        if total <= at and (not best or at < (best.at or 0)) then best = ti end
    end
    return best
end

-- ── Press overlay (shared across all TimerIcons) ────────────────────────────────
-- A SINGLE poll loop tints an icon while its action-bar keybind is physically held. A tracker opts in
-- via result.ApplyKeybind (which registers it here when its CDM dest enables "Show press overlay"); the
-- loop only iterates the registered trackers, so it's idle by default. Taint-free (only IsKeyDown / the
-- modifier getters + a plain texture). Mirrors the native poller in the CDMGroups engine.
local PRESS_FALLBACK = { r = 1, g = 1, b = 1, a = 0.35 }
local pressTrackers = {}   -- [frame] = { frame, overlay, getCombos, getColor }
local pressPoller
local function ComboDown(c)
    if c.shift ~= IsShiftKeyDown() then return false end
    if c.ctrl  ~= IsControlKeyDown() then return false end
    if c.alt   ~= IsAltKeyDown() then return false end
    return IsKeyDown(c.key)
end
local function AnyComboDown(combos)
    for _, c in ipairs(combos) do if ComboDown(c) then return true end end
    return false
end
local function EnsurePressPoller()
    if pressPoller then return end
    pressPoller = CreateFrame("Frame")
    local accum = 0
    pressPoller:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 0.05 then return end
        accum = 0
        local typing = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        for f, e in pairs(pressTrackers) do
            local want = false
            if not typing and f:IsShown() then
                local combos = e.getCombos()
                if combos and AnyComboDown(combos) then want = true end
            end
            if want then
                local pc = e.getColor() or PRESS_FALLBACK
                e.overlay:SetColorTexture(pc.r, pc.g, pc.b, pc.a or 0.35)
                e.overlay:Show()
            else
                e.overlay:Hide()
            end
        end
    end)
end

-- ── Below-player glow (LibCustomGlow) ───────────────────────────────────────────
-- The below-player "Glow" cadre draws a LibCustomGlow halo on the tracker while it is ACTIVE
-- (green/buff-up). Types pixel/autocast/button (proc is N/A for a tracker). Calls mirror the CDMGroups
-- engine. No-op if the lib is absent. The halo frame is a child of the icon, so it hides with it.
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local DEST_GLOW_KEY = "uuti"
local function StartDestGlow(frame, gtype, colorArr)
    if not LCG then return end
    if gtype == "autocast" then LCG.AutoCastGlow_Start(frame, colorArr, nil, nil, nil, nil, nil, DEST_GLOW_KEY)
    elseif gtype == "button" then LCG.ButtonGlow_Start(frame)
    else LCG.PixelGlow_Start(frame, colorArr, nil, nil, nil, nil, nil, nil, nil, DEST_GLOW_KEY) end
end
local function StopDestGlow(frame, gtype)
    if not LCG then return end
    if gtype == "autocast" then LCG.AutoCastGlow_Stop(frame, DEST_GLOW_KEY)
    elseif gtype == "button" then LCG.ButtonGlow_Stop(frame)
    else LCG.PixelGlow_Stop(frame, DEST_GLOW_KEY) end
end

function ns.ui.CreateTimerIcon(config)
    local name      = config.name
    local getCfg    = config.getCfg
    local onDragStop = config.onDragStop

    local result   = {}
    local unlocked = false
    local expirationTime = nil
    -- Cache of the last whole-second value rendered, so the OnUpdate only
    -- reformats/SetText/SetTextColor when the displayed mm:ss actually changes
    -- (instead of every frame at 60-144 Hz). Reset whenever a timer (re)starts.
    local lastSecs = nil
    -- Urgency colouring + flash for COOLDOWN timers only (NOT active
    -- positive-buff timers, which keep their own colour — green/PI): the text
    -- turns yellow at <=15s and red at <=5s remaining, and flashes briefly each
    -- time it crosses one of those thresholds. A timer set with an explicit
    -- colour (result._timerColor) is an active buff and is left untouched.
    local URGENT_YELLOW  = 15
    local URGENT_RED     = 5
    local FLASH_DURATION = 0.6   -- seconds the text flashes at a threshold
    local flashUntil     = nil   -- GetTime() until which the text is flashing
    -- The text also grows a little at each tier for extra urgency.
    local SIZE_YELLOW    = 1.2   -- font scale at the yellow tier
    local SIZE_RED       = 1.45  -- font scale at the red tier
    local baseFontSize   = nil   -- un-scaled timer font size (set by ApplySize/ApplyFont)
    local sizeScale      = 1     -- current urgency font scale (cooldown timers only)

    -- ── Frame ─────────────────────────────────────────────────────────────────

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(64, 64)
    -- Below HIGH-strata panels (e.g. the talents window) but above Blizzard's
    -- Cooldown Manager. See ns.SetTrackerIconStrata.
    ns.SetTrackerIconStrata(frame)
    frame:Hide()

    -- ── Icon ──────────────────────────────────────────────────────────────────

    -- Aspect-preserving icon crop, IDENTICAL to CDMGroups Engine.IconTexCoord: a square slot trims a
    -- 7% border zoom (0.07,0.93); a NON-square slot letterboxes the longer axis so the art keeps its
    -- proportions instead of stretching. Recomputed on every resize (ApplyDerivedSizing) so a tracker
    -- folded into a non-square group matches the native cooldowns beside it (else the trinket looked
    -- zoomed/stretched while the natives were letterboxed).
    local ICON_ZOOM = 0.07
    local function IconTexCoordFor(w, h)
        if not (w and h) or w <= 0 or h <= 0 then return ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM end
        local texW = 1 - ICON_ZOOM * 2
        local aspect = w / h
        local xR = aspect < 1 and aspect or 1
        local yR = aspect > 1 and 1 / aspect or 1
        return -0.5 * texW * xR + 0.5,  0.5 * texW * xR + 0.5,
               -0.5 * texW * yR + 0.5,  0.5 * texW * yR + 0.5
    end

    local iconTex = frame:CreateTexture(nil, "BACKGROUND")
    iconTex:SetAllPoints(frame)
    iconTex:SetTexCoord(IconTexCoordFor(64, 64))   -- 0.07,0.93 square default; re-cropped on resize

    local checkTex = frame:CreateTexture(nil, "OVERLAY")
    checkTex:SetTexture(ns.GREEN_CHECK_TEXTURE)
    checkTex:SetPoint("CENTER", frame, "CENTER", 0, 0)
    checkTex:Hide()

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetDrawEdge(false)

    -- ── Border (configurable) ───────────────────────────────────────────────────
    -- Independent of the frame backdrop (which SetUnlocked uses for the yellow drag
    -- outline). Four thin edge textures on a dedicated child frame raised above the
    -- cooldown swipe so the border stays visible over it. The edges are anchored to
    -- the corners, so they auto-track icon resizes; ApplyBorder only refreshes their
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

    -- ── Timer text ──────────────────────────────────────────────────────────────
    -- On a dedicated host frame raised ABOVE the border frame so the countdown is
    -- always readable over BOTH the cooldown swipe and the configurable border
    -- (the border sits at frame+10; this sits one level higher).
    local timerHost = CreateFrame("Frame", nil, frame)
    timerHost:SetAllPoints(frame)
    timerHost:SetFrameLevel(borderFrame:GetFrameLevel() + 1)
    local timerText = timerHost:CreateFontString(nil, "OVERLAY")
    -- A benign initial font so the OnUpdate tick's SetText can never hit "Font not set" if it fires before
    -- ApplyFont/ApplySize set the real one (e.g. a timer that starts before the engine first sizes the icon).
    timerText:SetFont(ns.ResolveFontPath(nil, nil), 20, "")
    timerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    timerText:Hide()

    -- ── Keybind text + press overlay (Cooldown Manager integration) ──────────────
    -- The keybind text sits on the timer host (above the border + swipe, like the timer); the press
    -- overlay is a tint over the icon, BELOW the border/timer. Both are driven by result.ApplyKeybind
    -- from the icon's CDM dest (the group's per-icon flags when a Cooldown-groups group owns this icon,
    -- else the per-dest below-player flags). A FREE icon shows neither.
    local keybindText = timerHost:CreateFontString(nil, "OVERLAY")
    keybindText:Hide()
    local pressOverlay = frame:CreateTexture(nil, "OVERLAY")
    pressOverlay:SetAllPoints(frame)
    pressOverlay:Hide()
    -- Below-player Title (tracked spell/item NAME) + Stacks/Charges. Additive; rendered only for a
    -- below-player icon when the per-dest cadres enable them (hidden otherwise).
    local titleFS = timerHost:CreateFontString(nil, "OVERLAY")
    titleFS:Hide()
    local stacksFS = timerHost:CreateFontString(nil, "OVERLAY")
    stacksFS:Hide()

    -- ── Drag ──────────────────────────────────────────────────────────────────

    -- True when the NEW "Cooldown groups" engine OWNS this icon's dest: it then folds this tracker
    -- into its group layout and drives the frame's SetPoint/SetSize itself (2x/sec via RefreshLayout).
    -- When this is true the icon must YIELD its own placement/sizing so the engine isn't stomped — the
    -- engine still calls SetSlotSize directly to size the frame, so SetSlotSize itself does NOT yield.
    local function EngineOwns()
        if not getCfg("includeInCdm") then return false end
        local dest = getCfg("cdmDest") or "essential"   -- match GetIconDescriptors' nil→essential fold
        return ns.CDMGroups and ns.CDMGroups.OwnsDest and ns.CDMGroups.OwnsDest(dest) or false
    end
    result.EngineOwns = EngineOwns

    -- True when this icon is currently managed by the Cooldown Manager integration
    -- (a native-row slot, or the below-player row). When true, ns.CDMAnchor owns the
    -- position/size and the icon is not free-draggable.
    local function CDMActive()
        -- Cooldown Manager disabled in the game options -> the integration is inert,
        -- so the icon is always free (draggable, positioned by posX/posY).
        if ns.IsCDMEnabled and not ns.IsCDMEnabled() then return false end
        if not getCfg("includeInCdm") then return false end
        local dest = getCfg("cdmDest")
        if dest == "belowPlayer" then return true end
        -- Require the viewer to be present AND shown: a hidden-but-present viewer
        -- (e.g. disabled in EditMode) would otherwise strand our icon at its last
        -- pinned offset; treating it as inactive reverts the icon to free placement.
        local v = ns.GetCDMViewer and ns.GetCDMViewer(dest)
        return v ~= nil and v:IsShown()
    end
    result.CDMActive = CDMActive

    -- The CONFIG dest for a below-player icon: which bucket's settings it reads. The PLACEMENT dest
    -- stays "belowPlayer" (CDMActive / cdmDest checks are unchanged); only the config SOURCE splits by
    -- the icon's "Icon at the end of the row" flag (cdmAtEnd) — the same bucketing LayoutBelowPlayer
    -- uses (cdmAtEnd ~= false -> end bucket). So a front icon reads cdmBelowRow.front, an end icon .end.
    local function CfgDest()
        return ns.CDMAnchor.IsAtEnd(getCfg("cdmAtEnd")) and "belowEnd" or "belowFront"
    end

    -- Effective timer config for THIS icon: the per-dest below-player value (when set) overrides the
    -- tracker's own config; everything else (and any unset below-player key) falls back to getCfg, then
    -- `default`. So a below-player Timer cadre value governs below-player icons with ZERO change to
    -- essential/utility/free trackers (they always hit the getCfg fallback).
    -- Per-icon override value for an ENGINE-OWNED icon (in a CDMGroups essential/utility group), via the
    -- group's per-icon override store (I.IconGet = override → group default). Returned ONLY once the icon
    -- has been migrated to the override system (I.IconOverrideMigrated) — so an un-migrated tracker keeps
    -- reading its OWN config (getCfg) and nothing regresses; a migrated one's in-CDM appearance comes
    -- entirely from its "Override settings", never its "Free icon settings". nil = not applicable.
    local function FrameName() return frame and frame.GetName and frame:GetName() end
    local function EngineIconGet(key)
        if not EngineOwns() then return nil end
        local I = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[getCfg("cdmDest") or "essential"]
        local fn = FrameName()
        if I and I.IconGet and fn and I.IconOverrideMigrated and I.IconOverrideMigrated(fn) then
            return I.IconGet(fn, key)
        end
        return nil
    end
    local function TimerCfg(key, default)
        if CDMActive() then
            if getCfg("cdmDest") == "belowPlayer" and ns.CDMAnchor and ns.CDMAnchor.GetDestCfgFor then
                -- below-player: per-icon override (when migrated) → bucket value.
                local v = ns.CDMAnchor.GetDestCfgFor(FrameName(), CfgDest(), key, nil)
                if v ~= nil then return v end
            else
                local v = EngineIconGet(key)
                if v ~= nil then return v end
            end
        end
        local g = getCfg(key)
        if g ~= nil then return g end
        return default
    end

    -- Effective timer urgency tiers: below-player maps its per-dest timerThresholds {time,size,color}
    -- (essential's shape) to the tracker's {at,scale,color}; thresholds OFF → {} (no built-in urgency,
    -- base colour only). Other dests keep their own timerTiers (nil → the built-in yellow@15 / red@5).
    -- Map the group/below-player {time,size,color}+enabled threshold shape to the tracker's {at,scale,color}
    -- tiers. Shared by the below-player and engine-owned branches.
    local function ThresholdsToTiers(enabled, thr)
        if not enabled then return {} end
        if not thr then return {} end
        local t = {}
        for _, x in ipairs(thr) do t[#t + 1] = { at = x.time, scale = x.size, color = x.color } end
        return t
    end
    local function TimerTiers()
        if CDMActive() then
            if getCfg("cdmDest") == "belowPlayer" and ns.CDMAnchor and ns.CDMAnchor.GetDestCfgFor then
                local cd, fn = CfgDest(), FrameName()
                return ThresholdsToTiers(ns.CDMAnchor.GetDestCfgFor(fn, cd, "timerThresholdsEnabled", false),
                                         ns.CDMAnchor.GetDestCfgFor(fn, cd, "timerThresholds", nil))
            elseif EngineIconGet("timerThresholdsEnabled") ~= nil then
                -- Migrated engine-owned icon: urgency tiers come from its override thresholds.
                return ThresholdsToTiers(EngineIconGet("timerThresholdsEnabled") == true,
                                         EngineIconGet("timerThresholds"))
            end
        end
        return getCfg("timerTiers")
    end

    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if CDMActive() then return end  -- CDM-managed: not free-draggable
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- CDM-managed icons are positioned by ns.CDMAnchor and aren't free-draggable
        -- (OnDragStart bails too); never re-anchor one onto a free CENTER point here.
        if CDMActive() then return end
        -- Don't read GetPoint() here: StartMoving can leave the frame on a
        -- different anchor/relativePoint than the CENTER/UIParent/CENTER that
        -- ApplyPosition re-applies, so its xOfs/yOfs would be in that other anchor's
        -- space and the icon would teleport on the next locked tick. Compute the
        -- centre offset from UIParent directly (scale-normalised) and re-anchor to a
        -- single CENTER point so the saved offset and the live frame stay in sync.
        local es, ues = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local fx, fy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not (fx and ux and es > 0) then return end
        local x = math.floor((fx * es - ux * ues) / es)
        local y = math.floor((fy * es - uy * ues) / es)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", x, y)
        if onDragStop then onDragStop(x, y) end
    end)

    -- Applies the timer font at the current urgency size scale. Both ApplySize
    -- (which runs every tick) and the OnUpdate go through this, so the scaled
    -- size stays consistent — otherwise ApplySize would reset the grown text to
    -- base every tick and it would flicker.
    local function SetTimerFont()
        if not baseFontSize then return end
        local path    = ns.ResolveFontPath(TimerCfg("timerFontPath", nil), TimerCfg("timerFontKey", nil))
        local outline = TimerCfg("timerOutline", nil) or ""
        timerText:SetFont(path, math.max(8, math.floor(baseFontSize * sizeScale)), outline)
    end

    -- ── OnUpdate ──────────────────────────────────────────────────────────────

    frame:SetScript("OnUpdate", function(self)
        if not expirationTime then
            timerText:Hide()
            return
        end
        local remaining = expirationTime - GetTime()
        if remaining <= 0 then
            timerText:Hide()
            timerText:SetAlpha(1)
            expirationTime = nil
            lastSecs = nil
            flashUntil = nil
            sizeScale = 1  -- next timer starts at base size, not a stale grown one
            if result.onExpire then result.onExpire() end
        else
            -- Only the whole-second value drives the displayed mm:ss, so skip
            -- the format/SetText/SetTextColor work on frames where it is unchanged.
            local total = math.floor(remaining)
            if total ~= lastSecs then
                local prev = lastSecs
                lastSecs = total
                timerText:SetText(ns.FormatMMSS(total))
                -- Custom configurable urgency tiers (e.g. the user's custom CDM icons).
                -- When present they REPLACE the hardcoded yellow@15 / red@5 thresholds;
                -- absent (every built-in tracker) -> the original behaviour is untouched.
                local tiers = TimerTiers()
                local scale = 1
                if result._timerColor then
                    -- Active positive buff (green / PI yellow): keep its colour
                    -- as-is — never urgency-recolour and never flash these.
                    timerText:SetTextColor(result._timerColor.r, result._timerColor.g, result._timerColor.b, 1)
                elseif tiers then
                    -- Custom tiers: the most urgent matching tier sets colour + size.
                    local tier = MatchTier(tiers, total)
                    if tier and tier.color then
                        timerText:SetTextColor(tier.color.r, tier.color.g, tier.color.b, tier.color.a or 1)
                        scale = tier.scale or 1
                    else
                        local c = TimerCfg("timerColor", nil)
                        if c then timerText:SetTextColor(c.r, c.g, c.b, c.a or 1)
                        else timerText:SetTextColor(1, 1, 1, 1) end
                    end
                    -- Flash when crossing INTO a more urgent tier (smaller `at`).
                    if prev then
                        local pT, cT = MatchTier(tiers, prev), MatchTier(tiers, total)
                        if cT and (not pT or (cT.at or 0) < (pT.at or 0)) then
                            flashUntil = GetTime() + FLASH_DURATION
                        end
                    end
                elseif total <= URGENT_RED then
                    timerText:SetTextColor(1, 0, 0, 1)        -- red <=5s
                    scale = SIZE_RED
                elseif total <= URGENT_YELLOW then
                    timerText:SetTextColor(1, 0.82, 0, 1)     -- yellow <=15s
                    scale = SIZE_YELLOW
                else
                    local c = TimerCfg("timerColor", nil)
                    if c then
                        timerText:SetTextColor(c.r, c.g, c.b, c.a or 1)
                    else
                        timerText:SetTextColor(1, 0, 0, 1)
                    end
                end
                if scale ~= sizeScale then
                    sizeScale = scale
                    SetTimerFont()
                end
                -- Flash on crossing a hardcoded threshold — cooldown timers only, and
                -- only on the hardcoded path (the custom-tier flash is handled above).
                if not result._timerColor and not tiers and prev then
                    if (prev > URGENT_YELLOW and total <= URGENT_YELLOW)
                        or (prev > URGENT_RED and total <= URGENT_RED) then
                        flashUntil = GetTime() + FLASH_DURATION
                    end
                end
                -- "Show timer" toggle (per-dest for below-player, else the tracker's); absent -> shown.
                if TimerCfg("showTimer", nil) ~= false then
                    timerText:Show()
                else
                    timerText:Hide()
                end
            end
            -- Per-frame: pulse the text alpha during a flash window, then restore.
            if flashUntil then
                if GetTime() < flashUntil then
                    local on = (math.floor(GetTime() / 0.12) % 2) == 0
                    timerText:SetAlpha(on and 1 or 0.15)
                else
                    flashUntil = nil
                    timerText:SetAlpha(1)
                end
            end
        end
    end)

    -- ── API ───────────────────────────────────────────────────────────────────

    -- Remember the last icon so the config (e.g. the below-player reorder strip) can
    -- show it via the getIcon registered with ns.CDMAnchor below.
    local curIcon
    function result.SetIcon(texture)
        curIcon = texture
        iconTex:SetTexture(texture)
    end

    function result.SetTimer(expiry, duration, color)
        expirationTime = expiry
        lastSecs = nil  -- force a re-render of text/color on the next OnUpdate
        flashUntil = nil
        timerText:SetAlpha(1)
        checkTex:Hide()
        if expiry and duration then
            cooldown:SetCooldown(expiry - duration, duration)
        end
        if color then
            result._timerColor = color
            sizeScale = 1  -- active buffs are never urgency-grown
            -- A coloured timer marks an *active* state (buff / lust up), so keep
            -- the icon at full colour under the rotating swipe.
            iconTex:SetDesaturated(false)
        else
            result._timerColor = nil
            -- The default (uncoloured) timer is a cooldown / unavailable state:
            -- grey the icon out behind the swipe so it reads as "not ready".
            iconTex:SetDesaturated(true)
        end
        if result.ApplyDestGlow then result.ApplyDestGlow() end
    end

    function result.ClearTimer()
        expirationTime = nil
        lastSecs = nil
        timerText:Hide()
        cooldown:Clear()
        iconTex:SetDesaturated(false)  -- restore full colour once the CD/timer ends
        result._timerColor = nil
        if result.ApplyDestGlow then result.ApplyDestGlow() end
        -- The check is now driven separately (Show / Hide / Blink) by
        -- consumers, so they can flash it on CD-completion instead of
        -- leaving it permanently visible.
    end

    function result.Show()
        if not unlocked then frame:Show() end
    end

    function result.Hide()
        if not unlocked then frame:Hide() end
    end

    -- NOTE: reports the RAW frame state. While unlocked, Show()/Hide() are no-ops
    -- (drag mode force-shows the frame), so this can read true even when the owner
    -- logically wants it hidden. No caller relies on it today; treat with care.
    function result.IsShown()
        return frame:IsShown()
    end

    function result.GetFrame()
        return frame
    end

    function result.ApplyFont()
        baseFontSize = TimerCfg("timerFontSize", nil) or 20
        SetTimerFont()
        -- React to the "show timer" toggle immediately: hide now if off, else clear the
        -- cached second so a re-enabled timer re-renders on the next tick.
        if TimerCfg("showTimer", nil) == false then
            timerText:Hide()
        else
            lastSecs = nil
        end
    end

    function result.ApplyPosition()
        -- While unlocked the user is dragging the icon to place it. The owning
        -- module's 0.5s layout ticker (and ns.CDMAnchor relayouts) also call this,
        -- and a ClearAllPoints+SetPoint mid-drag fights StartMoving — the icon
        -- teleports back to its saved spot, or lands at a random offset on a short
        -- drag. Leave placement to the user until Lock; OnDragStop saves the drop
        -- position and the next locked tick re-anchors from it.
        if unlocked then return end
        -- The NEW groups engine owns this icon's dest: it positions + sizes the frame in its own
        -- RefreshLayout (2x/sec). Do NOTHING here — re-anchoring it (even to CDMAnchor) would fight
        -- the engine's SetPoint/SetSize. Mirror of the CDMActive short-circuit below.
        if EngineOwns() then return end
        -- When the Cooldown Manager integration is active, ns.CDMAnchor owns this
        -- icon's position AND size (native-row slot or below-player row); just ask
        -- for a refresh. Otherwise it's free — positioned on screen by posX/posY.
        if CDMActive() then
            if ns.CDMAnchor then ns.CDMAnchor.RefreshAll() end
            return
        end
        -- Free placement: clear any fade alpha the CDM fade-along may have left on
        -- this icon (it only fades icons currently in the CDM).
        frame:SetAlpha(1)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", getCfg("posX") or 0, getCfg("posY") or 200)
    end

    -- Recompute font / check / border from the CURRENT frame size. Shared by
    -- ApplySize (config size) and SetSlotSize (native row size) so the look stays
    -- consistent whatever drives the size.
    local function ApplyDerivedSizing()
        local w, h = frame:GetSize()
        iconTex:SetTexCoord(IconTexCoordFor(w, h))   -- aspect-aware crop, matches native CDM icons (no stretch)
        -- The user-configured timer font size wins; we only auto-derive from the
        -- icon size when none is set. ItemTracker.ApplyVisuals calls ApplySize()
        -- (→ here) every 0.5s tick, so without this the configured timerFontSize
        -- was overwritten by the derived value on the very next tick and the
        -- exposed "Timer text size" control had no effect.
        baseFontSize = TimerCfg("timerFontSize", nil) or math.max(10, math.floor(math.min(w, h) * 0.4))
        SetTimerFont()
        -- Below-player timer text position (per-dest); CENTER everywhere else (TimerCfg → CENTER fallback).
        if ns.AnchorFS then
            ns.AnchorFS(timerText, frame, TimerCfg("timerPos", "CENTER"), TimerCfg("timerOffX", 0), TimerCfg("timerOffY", 0))
        end
        local checkSize = math.floor(math.min(w, h) * 0.6)
        checkTex:SetSize(checkSize, checkSize)
        result.ApplyBorder()
        result.ApplyKeybind()
        result.ApplyDestGlow()
        result.ApplyDestExtras()
    end

    function result.ApplySize()
        -- The NEW groups engine owns this dest: it sizes the frame via SetSlotSize (below) to the
        -- group's iconW/iconH and re-derives the look there. The module's own 0.5s ApplySize must NOT
        -- impose the configured size (it would fight the engine 2x/sec) — yield entirely.
        if EngineOwns() then return end
        -- In any CDM mode the size is owned by ns.CDMAnchor via SetSlotSize:
        -- essential/utility use the per-row size override (default 44); below-player uses
        -- the per-profile cdmBelowRow size. Only a FREE icon uses its configured size.
        if not CDMActive() then
            local w = math.max(8, math.min(512, getCfg("iconWidth") or 64))
            local h = math.max(8, math.min(512, getCfg("iconHeight") or 64))
            frame:SetSize(w, h)
        end
        ApplyDerivedSizing()
    end

    -- Called by ns.CDMAnchor in slot mode to match the native row's icon size.
    function result.SetSlotSize(w, h)
        w = math.max(8, math.min(512, w or 64))
        h = math.max(8, math.min(512, h or 64))
        frame:SetSize(w, h)
        ApplyDerivedSizing()
    end

    -- Draw / refresh the configurable border from config (borderEnabled,
    -- borderColor, borderSize). Cheap; safe to call on every size / reload pass.
    function result.ApplyBorder()
        -- In the Cooldown Manager the per-DEST border (set in the Essentials / Utility /
        -- Below player frame panels) governs every icon of that dest, so they all share one
        -- border. A free icon (not in the CDM) uses its own border config.
        local enabled, c, size
        if EngineOwns() then
            -- In a CDMGroups group, read the GROUP's per-icon border config for this tracker's key — the
            -- SAME source the engine uses for the native cooldowns beside it (I.IconGet resolves the
            -- per-icon pencil override, else the group default). Otherwise the tracker drew its own
            -- (often differently-coloured/sized) border and stood out from its neighbours.
            local dest = getCfg("cdmDest") or "essential"
            local I = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[dest]
            local key = frame:GetName()
            if I and I.IconGet and key then
                enabled, c, size = I.IconGet(key, "borderEnabled"), I.IconGet(key, "borderColor"), I.IconGet(key, "borderSize")
            else
                enabled, c, size = getCfg("borderEnabled"), getCfg("borderColor"), getCfg("borderSize")
            end
        elseif CDMActive() and ns.CDMAnchor and ns.CDMAnchor.GetDestBorderFor then
            -- Below-player icons read their bucket's border (front/end), or their own per-icon override
            -- when migrated; other dests by their own name.
            local bd = getCfg("cdmDest") or "essential"
            if bd == "belowPlayer" then bd = CfgDest() end
            enabled, c, size = ns.CDMAnchor.GetDestBorderFor(FrameName(), bd)
        else
            enabled, c, size = getCfg("borderEnabled"), getCfg("borderColor"), getCfg("borderSize")
        end
        if not enabled then
            for _, t in pairs(borderEdges) do t:Hide() end
            return
        end
        size = math.max(1, math.min(16, size or 1))
        c = c or { r = 0, g = 0, b = 0, a = 1 }
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

    -- ── Keybind text + press overlay resolution ─────────────────────────────────
    local function CdmGroupInstance()
        local dest = getCfg("cdmDest") or "essential"
        return ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[dest]
    end
    -- A CDM display flag ("showKeybinds" / "showPressOverlay") for THIS icon: the group's per-icon value
    -- (pencil override → group) when a Cooldown-groups group owns the dest; the per-dest below-player
    -- flag when pinned below the player; never for a free icon.
    local function CdmFlag(key)
        if EngineOwns() then
            local I = CdmGroupInstance()
            local fn = frame:GetName()
            if I and I.IconGet and fn then return I.IconGet(fn, key) == true end
        elseif CDMActive() and getCfg("cdmDest") == "belowPlayer" then
            if ns.CDMAnchor and ns.CDMAnchor.GetDestCdmFlagFor then
                return ns.CDMAnchor.GetDestCdmFlagFor(FrameName(), CfgDest(), key) == true
            end
        end
        return false
    end
    -- The icon's keybind target: its on-use SPELL first, then its ITEM (a trinket/potion is bound on the
    -- bar as an item, not a spell). Text + raw combos come from the shared resolver.
    local function KbText()
        if not ns.CDGKeybinds then return nil end
        local sid = getCfg("spellId")
        local txt = sid and ns.CDGKeybinds.GetKeybindText(sid)
        if not txt and config.getItemId then
            local iid = config.getItemId()
            if iid then txt = ns.CDGKeybinds.GetKeybindTextForItem(iid) end
        end
        return txt
    end
    local function KbCombos()
        if not ns.CDGKeybinds then return nil end
        local sid = getCfg("spellId")
        local c = sid and ns.CDGKeybinds.GetRawCombos(sid)
        if not c and config.getItemId then
            local iid = config.getItemId()
            if iid then c = ns.CDGKeybinds.GetRawCombosForItem(iid) end
        end
        return c
    end
    local function PressColor()
        if EngineOwns() then
            local I = CdmGroupInstance()
            local fn = frame:GetName()
            if I and I.IconGet and fn then return I.IconGet(fn, "pressOverlayColor") or PRESS_FALLBACK end
        end
        return PRESS_FALLBACK
    end

    -- Refresh the keybind text + the press-overlay registration from the icon's CDM dest. Called every
    -- ApplyDerivedSizing pass (size / relayout tick) so a rebind or config change repaints within a tick.
    function result.ApplyKeybind()
        if CdmFlag("showKeybinds") then
            local fontKey, fontPath, fontSize, outline, color, pos, ox, oy
            if EngineOwns() then
                local I = CdmGroupInstance()
                local fn = frame:GetName()
                fontKey, fontPath = I.IconGet(fn, "keybindFontKey"), I.IconGet(fn, "keybindFontPath")
                fontSize, outline = I.IconGet(fn, "keybindFontSize") or 12, I.IconGet(fn, "keybindOutline") or "OUTLINE"
                color = I.IconGet(fn, "keybindColor")
                pos, ox, oy = I.IconGet(fn, "keybindPos") or "TOPLEFT", I.IconGet(fn, "keybindOffX"), I.IconGet(fn, "keybindOffY")
            else
                local w, h = frame:GetSize()
                fontKey, fontPath = getCfg("timerFontKey"), getCfg("timerFontPath")
                fontSize, outline = math.max(8, math.floor(math.min(w, h) * 0.28)), "OUTLINE"
                pos, ox, oy = "TOPLEFT", 2, -2
            end
            keybindText:SetFont(ns.ResolveFontPath(fontPath, fontKey), fontSize or 12, outline or "OUTLINE")
            local c = color or { r = 1, g = 1, b = 1, a = 1 }
            keybindText:SetTextColor(c.r, c.g, c.b, c.a or 1)
            if ns.AnchorFS then ns.AnchorFS(keybindText, frame, pos or "TOPLEFT", ox, oy) end
            local txt = KbText()
            if txt and txt ~= "" then keybindText:SetText(txt); keybindText:Show() else keybindText:Hide() end
        else
            keybindText:Hide()
        end

        if CdmFlag("showPressOverlay") then
            EnsurePressPoller()
            if not pressTrackers[frame] then
                pressTrackers[frame] = { frame = frame, overlay = pressOverlay, getCombos = KbCombos, getColor = PressColor }
            end
        elseif pressTrackers[frame] then
            pressTrackers[frame] = nil
            pressOverlay:Hide()
        end
    end

    -- Below-player glow: a LibCustomGlow halo while the tracked spell is PROCCED (Blizzard's spell-
    -- activation overlay → frame._procced, set by the proc events below) when the per-dest "Show glow on
    -- proc" is on. Only below-player; any other dest stops it. Track the active glow type so we Start/Stop
    -- only on a real change (the lib animates itself).
    function result.ApplyDestGlow()
        local wantType, colorArr
        if CDMActive() and getCfg("cdmDest") == "belowPlayer" and ns.CDMAnchor and ns.CDMAnchor.GetDestGlowFor then
            local enabled, gt, c = ns.CDMAnchor.GetDestGlowFor(FrameName(), CfgDest())
            if enabled and frame._procced then
                wantType = gt or "pixel"
                colorArr = { c.r or 1, c.g or 1, c.b or 1, c.a or 1 }
            end
        end
        local cur = frame._destGlowType
        if cur == wantType then return end
        if cur then StopDestGlow(frame, cur) end
        if wantType then StartDestGlow(frame, wantType, colorArr) end
        frame._destGlowType = wantType
    end

    -- Below-player Title (the tracked spell/item NAME) + Stacks/Charges. Name/charges lightly cached.
    local nameKey, nameVal
    local function ResolveName()
        local sid = getCfg("spellId")
        if sid and sid ~= 0 then
            if nameKey ~= sid then nameKey, nameVal = sid, (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) end
            if nameVal then return nameVal end
        end
        if config.getItemId then
            local iid = config.getItemId()
            if iid then
                local k = "i" .. iid
                if nameKey ~= k then nameKey, nameVal = k, (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(iid)) end
                return nameVal
            end
        end
        return nil
    end
    local function ResolveCharges()
        local sid = getCfg("spellId")
        if sid and sid ~= 0 and C_Spell and C_Spell.GetSpellCharges then
            local ci = C_Spell.GetSpellCharges(sid)
            if ci and (ci.maxCharges or 0) > 1 then return ci.currentCharges end
        end
        -- A caller-supplied count wins over the default item-count (e.g. healthstones count CHARGES via
        -- GetItemCount(id, false, true), not plain stacks). Authoritative when present.
        if config.getCount then return config.getCount() end
        if config.getItemId then
            local iid = config.getItemId()
            if iid and C_Item and C_Item.GetItemCount then
                local n = C_Item.GetItemCount(iid)
                if n and n > 0 then return n end
            end
        end
        return nil
    end
    local function DCfg(key, default)
        return (ns.CDMAnchor and ns.CDMAnchor.GetDestCfgFor and ns.CDMAnchor.GetDestCfgFor(FrameName(), CfgDest(), key, default)) or default
    end
    -- Render the per-dest Title + Stacks. Below-player: from the bucket (+ this icon's per-icon override)
    -- via DCfg. Engine-owned (essential/utility): from the icon's per-icon override (EngineIconGet), but
    -- ONLY once migrated — so an un-migrated engine icon draws nothing here and its module keeps own-drawing
    -- (no double-draw). Free / other dests: hide both (the module own-draws).
    function result.ApplyDestExtras()
        local isBP = CDMActive() and getCfg("cdmDest") == "belowPlayer"
        local function EngineMigrated()
            if not EngineOwns() then return false end
            local I = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[getCfg("cdmDest") or "essential"]
            local fn = FrameName()
            return (I and I.IconOverrideMigrated and fn and I.IconOverrideMigrated(fn)) or false
        end
        local isEngine = (not isBP) and EngineMigrated()
        local drawExtras = isBP or isEngine
        -- Per-dest extras source: below-player → DCfg (bucket + per-icon override); engine-owned → the
        -- per-icon override (EngineIconGet, migrated-only). nil → caller default.
        local function XCfg(key, default)
            local v
            if isBP then v = DCfg(key, nil)
            elseif isEngine then v = EngineIconGet(key) end
            if v ~= nil then return v end
            return default
        end
        -- Title: free text (titleText), styled with the title* keys.
        if drawExtras and XCfg("showTitle", false) then
            titleFS:SetFont(ns.ResolveFontPath(XCfg("titleFontPath", nil), XCfg("titleFontKey", "Fira Mono")),
                XCfg("titleFontSize", 12), XCfg("titleOutline", "OUTLINE"))
            local c = XCfg("titleColor", nil) or { r = 1, g = 1, b = 1, a = 1 }
            titleFS:SetTextColor(c.r, c.g, c.b, c.a or 1)
            if ns.AnchorFS then ns.AnchorFS(titleFS, frame, XCfg("titlePos", "TOP"), XCfg("titleOffX", 0), XCfg("titleOffY", 0)) end
            local txt = XCfg("titleText", "") or ""
            if txt ~= "" then titleFS:SetText(txt); titleFS:Show() else titleFS:Hide() end
        else
            titleFS:Hide()
        end
        -- Stacks / charges: the tracked spell's charges, or the item count, styled with the stack* keys.
        if drawExtras and XCfg("showStack", true) then
            stacksFS:SetFont(ns.ResolveFontPath(XCfg("stackFontPath", nil), XCfg("stackFontKey", "Fira Mono")),
                XCfg("stackFontSize", 10), XCfg("stackOutline", "OUTLINE"))
            local c = XCfg("stackColor", nil) or { r = 1, g = 1, b = 1, a = 1 }
            stacksFS:SetTextColor(c.r, c.g, c.b, c.a or 1)
            if ns.AnchorFS then ns.AnchorFS(stacksFS, frame, XCfg("stackPos", "BOTTOMRIGHT"), XCfg("stackOffX", 2), XCfg("stackOffY", -2)) end
            local ch = ResolveCharges()
            if ch and ch > 0 then
                stacksFS:SetText(tostring(ch)); stacksFS:Show()
            elseif XCfg("showAtZero", false) then   -- keep a literal "0" when the tracker opted in
                stacksFS:SetText("0"); stacksFS:Show()
            else
                stacksFS:Hide()
            end
        else
            stacksFS:Hide()
        end
    end

    function result.SetUnlocked(val)
        unlocked = val
        if val then
            frame:EnableMouse(true)
            frame:SetBackdrop({
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            local _br, _bg, _bb = ns.GetBrandColor()
            frame:SetBackdropBorderColor(_br, _bg, _bb, 0.8)   -- brand blue (re-read on (re)build)
            frame:Show()
        else
            frame:EnableMouse(false)
            frame:SetBackdrop(nil)
        end
    end

    function result.IsUnlocked()
        return unlocked
    end

    -- Blink animation: flash the check briefly on CD-completion, then hide.
    local BLINK_TOTAL    = 1.5
    local BLINK_INTERVAL = 0.2
    local function StopBlink()
        if frame.blinkFrame then
            frame.blinkFrame:SetScript("OnUpdate", nil)
        end
        checkTex:SetAlpha(1)
    end

    function result.ShowCheck()
        StopBlink()
        checkTex:Show()
    end

    function result.HideCheck()
        StopBlink()
        checkTex:Hide()
    end

    function result.BlinkCheck()
        StopBlink()
        checkTex:Show()
        checkTex:SetAlpha(1)
        if not frame.blinkFrame then
            frame.blinkFrame = CreateFrame("Frame", nil, frame)
        end
        local elapsed = 0
        frame.blinkFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= BLINK_TOTAL then
                self:SetScript("OnUpdate", nil)
                checkTex:Hide()
                checkTex:SetAlpha(1)
                return
            end
            local phase = math.floor(elapsed / BLINK_INTERVAL) % 2
            checkTex:SetAlpha(phase == 0 and 1 or 0)
        end)
    end

    -- Pixel glow: a handful of small bright dots marching around the icon
    -- perimeter on a loop. Created lazily and reused across show/hide.
    local function EnsurePixelGlow()
        if frame.pixelGlow then return frame.pixelGlow end

        local DOT_COUNT = 8
        local DOT_SIZE  = 3
        local CYCLE     = 1.5  -- seconds for one full lap

        local glow = CreateFrame("Frame", nil, frame)
        glow:SetAllPoints(frame)
        glow:Hide()

        local dots = {}
        for i = 1, DOT_COUNT do
            local dot = glow:CreateTexture(nil, "OVERLAY")
            dot:SetSize(DOT_SIZE, DOT_SIZE)
            dot:SetColorTexture(1, 1, 0, 1)  -- yellow
            dots[i] = dot
        end

        local elapsed = 0
        glow:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            local progress = (elapsed % CYCLE) / CYCLE
            local w, h = frame:GetSize()
            if w == 0 or h == 0 then return end
            local perimeter = 2 * (w + h)
            for i, dot in ipairs(dots) do
                local p = (progress + (i - 1) / DOT_COUNT) % 1
                local d = p * perimeter
                local x, y
                if d < w then
                    x, y = d, 0
                elseif d < w + h then
                    x, y = w, -(d - w)
                elseif d < 2 * w + h then
                    x, y = w - (d - w - h), -h
                else
                    x, y = 0, -(perimeter - d)
                end
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", frame, "TOPLEFT", x, y)
            end
        end)

        frame.pixelGlow = glow
        return glow
    end

    function result.SetGlow(enabled)
        if enabled then
            EnsurePixelGlow():Show()
        elseif frame.pixelGlow then
            frame.pixelGlow:Hide()
        end
    end

    -- In slot mode, re-pack the row when this icon shows/hides: it occupies a slot
    -- only while visible, and our own visibility changes don't trigger a native
    -- viewer relayout, so nudge ns.CDMAnchor ourselves.
    local function SlotRepack()
        -- When the groups engine owns this dest, a tracker occupies a group slot only WHILE shown, and
        -- our own show/hide doesn't trigger the engine's viewer hook — so nudge the engine to reflow.
        if EngineOwns() then
            local dest = getCfg("cdmDest") or "essential"
            local I = ns.CDMGroups and ns.CDMGroups.instances and ns.CDMGroups.instances[dest]
            if I and I.ScheduleRelayout then I.ScheduleRelayout() end
            return
        end
        if ns.CDMAnchor and CDMActive() then ns.CDMAnchor.RefreshAll() end
    end
    frame:HookScript("OnShow", SlotRepack)
    frame:HookScript("OnHide", SlotRepack)

    -- Below-player "Show glow on proc": track Blizzard's spell-activation overlay for the tracked spell
    -- so ApplyDestGlow can flash the halo while it is procced (set frame._procced; re-apply the glow).
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    frame:SetScript("OnEvent", function(_, event, arg1)
        local sid = getCfg("spellId")
        if sid and arg1 == sid then
            frame._procced = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            if result.ApplyDestGlow then result.ApplyDestGlow() end
        end
    end)

    -- Follow the native Cooldown Manager: ns.CDMAnchor re-applies this icon's
    -- position whenever the viewer relayouts / moves; in slot mode it also sizes
    -- the icon to the native row via SetSlotSize.
    if ns.CDMAnchor then
        ns.CDMAnchor.Register({
            apply       = result.ApplyPosition,
            frame       = frame,
            getCfg      = getCfg,
            setCfg      = config.setCfg,   -- optional: lets the CDM reorder strips flip cdmAtEnd on drag
            setSize     = result.SetSlotSize,
            getIcon     = function() return curIcon end,
            cdmEligible = config.cdmEligible,  -- optional: false → don't fold into a CDM group (e.g. a passive trinket)
        })
    end

    return result
end