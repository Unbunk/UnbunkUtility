-- Modules/CastBar/Core/CastBar.lua
-- A custom player cast bar (cast / channel / empower) plus an option to hide Blizzard's
-- native PlayerCastingBarFrame. Inspired by the reference CDM addon's PlayerCastBar: we watch the
-- UNIT_SPELLCAST_* events on "player", read UnitCastingInfo / UnitChannelInfo for the
-- timing, drive a StatusBar in OnUpdate, and suppress the Blizzard bar by unregistering
-- its events + hooking Show/Register so other addons can't bring it back.

local _, ns = ...
ns.CastBar = ns.CastBar or {}
local CB = ns.CastBar

local GetTime          = GetTime
local UnitCastingInfo  = UnitCastingInfo
local UnitChannelInfo  = UnitChannelInfo
local UnitEmpoweredStagePercentages = _G.UnitEmpoweredStagePercentages   -- DF+ empower stages (nil on Classic)
local floor            = math.floor

local BAR_TEXTURE   = "Interface\\TargetingFrame\\UI-StatusBar"
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local PREVIEW_ICON  = 134400  -- question-mark icon, used while positioning

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_EMPOWER_UPDATE",
}

local container, bar, bg, icon, nameFS, timeFS, spark
local enabled = false                 -- our events currently registered
local cast = { active = false }       -- { active, channel(=fill down), startKind, castID, startT, endT, notInt }

local function C(key) return CB.CfgGet(key) end

local testing = false                 -- preview loop driven by the "Test" button

-- The saved statusbar key if it's actually registered, else "Blizzard" (LSM's always-present
-- default). This keeps the saved default "Better Blizzard" — so it auto-activates once a media
-- pack provides it — while users without that pack see/render "Blizzard".
local function EffectiveTextureKey(key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and key and LSM:IsValid("statusbar", key) then return key end
    return "Blizzard"
end
CB.EffectiveTexture = EffectiveTextureKey

-- LibSharedMedia statusbar texture for a key (via its effective key), else the bar default.
local function ResolveTexture(key)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local p = LSM and LSM:Fetch("statusbar", EffectiveTextureKey(key), true)
    return p or BAR_TEXTURE
end

-- The live frame a CDM destination anchors / sizes against. For essential / utility we follow
-- the CDMGroups "Group 1" container (the user-configured primary row), NOT the whole native
-- viewer — so both adapt-width and anchor track Group 1 specifically. We only use it once the
-- engine has it live (shown + positioned); until then (CDM off, empty Group 1, or the brief
-- window right after a /reload) we fall back to the native viewer. belowPlayer -> PlayerFrame.
local function GroupOneBox(dest)
    local inst = ns.CDMGroups and ns.CDMGroups[dest]
    local box  = inst and inst.GetContainer and inst.GetContainer(1)
    if box and box:IsShown() and box:GetLeft() then return box end
    return nil
end

local function AnchorDestFrame(dest)
    if dest == "belowPlayer" then return _G.PlayerFrame end
    return GroupOneBox(dest) or ns.GetCDMViewer(dest)
end

-- Container point + anchor-frame point for the saved "position relative to anchor".
local function RelPoints()
    local p = CB.REL_POINTS[C("positionRelative")] or CB.REL_POINTS.bottom
    return p[1], p[2]
end

-- A frame's named point in absolute screen pixels (scale folded in), or nil.
local function PointAbs(frame, point)
    local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    local s = frame:GetEffectiveScale()
    if not (l and b and s and s > 0) then return nil end
    local x = point:find("LEFT") and l or (point:find("RIGHT") and (l + w) or (l + w / 2))
    local y = point:find("BOTTOM") and b or (point:find("TOP") and (b + h) or (b + h / 2))
    return x * s, y * s
end

-- ── Empower stage notch pips (Evoker empowered casts) ─────────────────────────
-- An empowered spell fills as a single bar; draw a thin notch at each internal stage
-- boundary so the player can see where each empower level lands. UnitEmpoweredStagePercentages
-- returns the PER-STAGE fractions (player unit, non-secret); accumulate them for the boundaries.
local EMPOWER_PIP_W = 2
local empowerPips = {}

local function HideEmpowerPips()
    for i = 1, #empowerPips do empowerPips[i]:Hide() end
end

local function ShowEmpowerPips(numStages)
    HideEmpowerPips()
    if not (bar and numStages and numStages > 0 and UnitEmpoweredStagePercentages) then return end
    local pcts = UnitEmpoweredStagePercentages("player")
    if not pcts then return end
    local barW, barH = bar:GetWidth(), bar:GetHeight()
    if not (barW and barW > 1 and barH and barH > 0) then return end
    local bc = C("borderColor") or { r = 0, g = 0, b = 0, a = 1 }
    -- Normalise by the stage total so the boundaries span the bar exactly, whatever scale the API
    -- reports the per-stage values in: the last boundary is the max stage, which is our bar's end
    -- (UnitChannelInfo's endMs), so cumulative/total is the right on-bar fraction either way.
    local total = 0
    for i = 1, numStages do total = total + (pcts[i] or 0) end
    if total <= 0 then return end
    local cumulative, shown = 0, 0
    for i = 1, numStages do
        cumulative = cumulative + (pcts[i] or 0)
        local frac = cumulative / total
        -- Skip the final boundary (= bar end / max stage, where the spark already sits).
        if frac > 0.001 and frac < 0.999 then
            shown = shown + 1
            local pip = empowerPips[shown]
            if not pip then
                pip = bar:CreateTexture(nil, "OVERLAY", nil, 2)
                empowerPips[shown] = pip
            end
            pip:SetColorTexture(bc.r, bc.g, bc.b, bc.a or 1)
            pip:SetSize(EMPOWER_PIP_W, barH)
            pip:ClearAllPoints()
            pip:SetPoint("CENTER", bar, "LEFT", barW * frac, 0)
            pip:Show()
        end
    end
end

-- ── Per-tick fill ─────────────────────────────────────────────────────────────
local function OnUpdate()
    if not cast.active then return end
    local now   = GetTime()
    local total = cast.endT - cast.startT
    if total <= 0 then return end
    local frac = cast.channel and (cast.endT - now) / total or (now - cast.startT) / total
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    bar:SetValue(frac)
    if spark:IsShown() then
        -- The spark's single point was set at cast start; only its x-offset moves each
        -- frame. SetPoint with the same anchor replaces that one point (no ClearAllPoints).
        spark:SetPoint("CENTER", bar, "LEFT", (bar:GetWidth() or 0) * frac, 0)
    end
    if cast.showTimer then
        local remaining = cast.endT - now
        if remaining < 0 then remaining = 0 end
        timeFS:SetFormattedText("%.1f", remaining)
    end
    if now >= cast.endT then
        if testing then cast.startT = now; cast.endT = now + 2.5   -- loop the preview
        else CB.StopCast() end
    end
end

-- ── Colour by cast state ──────────────────────────────────────────────────────
local function ApplyColor()
    local c = cast.notInt and C("uninterruptibleColor")
        or (cast.channel and C("channelColor") or C("castColor"))
    c = c or { r = 1, g = 0.7, b = 0 }
    bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
end

-- ── Layout (size, icon split, textures, per-text style + offsets, shown) ───────
local function ApplyLayout()
    if not container then return end
    local h = math.max(6, C("height") or 40)
    local w = math.max(20, C("width") or 255)
    if C("adaptWidth") then
        local af = AnchorDestFrame(C("adaptWidthTo") or "essential")
        local aw = af and af.GetWidth and af:GetWidth()
        -- > 1, not > 0: a freshly-created Group 1 box sits at 1px until the engine sizes it;
        -- ignore that so we keep the saved width rather than collapsing to nearly nothing.
        if aw and aw > 1 then w = math.max(20, aw) end
    end
    container:SetSize(w, h)

    -- Bar fill + background textures.
    bar:SetStatusBarTexture(ResolveTexture(C("barTexture")))
    bg:SetTexture(ResolveTexture(C("bgTexture")))
    bg:SetVertexColor(0.12, 0.12, 0.12, 0.85)   -- darken so it reads as a background

    -- Icon side + gap.
    local gap = C("iconGap") or 1
    icon:ClearAllPoints(); bar:ClearAllPoints()
    if C("showIcon") ~= false then
        icon:SetSize(h, h); icon:Show()
        if C("iconPosition") == "right" then
            icon:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -(h + gap), 0)
        else
            icon:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            bar:SetPoint("TOPLEFT", container, "TOPLEFT", h + gap, 0)
            bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        end
    else
        icon:Hide()
        bar:SetAllPoints(container)
    end

    -- Spell-name style + offset.
    local nfp = ns.ResolveFontPath(C("nameFontPath"), C("nameFontKey"))
    local nc  = C("nameColor") or { r = 1, g = 1, b = 1, a = 1 }
    nameFS:SetFont(nfp, C("nameFontSize") or 12, C("nameOutline") or "OUTLINE")
    nameFS:SetTextColor(nc.r, nc.g, nc.b, nc.a or 1)
    nameFS:ClearAllPoints()
    nameFS:SetPoint("LEFT", bar, "LEFT", C("nameXOffset") or 3, C("nameYOffset") or 0)
    nameFS:SetShown(C("showSpellName") ~= false)

    -- Timer style + offset.
    local tfp = ns.ResolveFontPath(C("timerFontPath"), C("timerFontKey"))
    local tc  = C("timerColor") or { r = 1, g = 1, b = 1, a = 1 }
    timeFS:SetFont(tfp, C("timerFontSize") or 12, C("timerOutline") or "OUTLINE")
    timeFS:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
    timeFS:ClearAllPoints()
    timeFS:SetPoint("RIGHT", bar, "RIGHT", C("timerXOffset") or -3, C("timerYOffset") or 0)
    timeFS:SetShown(C("showTimer") ~= false)

    spark:SetSize(C("sparkThickness") or 20, h * 1.8)
    spark:SetShown(C("showSpark") ~= false)

    -- Border around the whole bar (icon + fill). Reuses the shared 4-edge helper; outset so it
    -- frames the bar from just outside instead of being painted over by the advancing fill.
    if ns.CDMAnchor and ns.CDMAnchor.ApplyFrameBorder then
        local bc = C("borderColor") or { r = 0, g = 0, b = 0, a = 1 }
        ns.CDMAnchor.ApplyFrameBorder(container, C("borderEnabled") ~= false, bc, C("borderThickness") or 1, true)
    end

    -- Keep empower notches aligned if the bar is resized mid-empower (CDM relayout / adapt-width).
    if cast.active and cast.startKind == "empower" then ShowEmpowerPips(cast.numStages) end
end

function CB.ApplyPosition()
    if not container or CB.IsUnlocked() then return end
    container:ClearAllPoints()
    local af = AnchorDestFrame(C("anchorTo") or "essential")
    local sp, ap = RelPoints()
    local px, py = C("posX") or 0, C("posY") or 0
    if af then
        container:SetPoint(sp, af, ap, px, py)
    else
        container:SetPoint(sp, UIParent, "CENTER", px, py)   -- CDM off / viewer absent
    end
end

-- ── Follow Group 1's box size (fixes adapt-width / anchor not updating after a /reload) ──
-- The CDMGroups engine makes Group 1's container at 1px and only sizes + positions it a moment
-- later (and again on spec change / icon add-remove). The cast bar's first layout pass reads a
-- stale/empty box, so without this it never re-adapts after a reload. Hook each Group 1 box's
-- OnSizeChanged once and re-apply, coalesced to the next frame (after the engine's layout pass).
local sizePending = false
local function OnAnchorSizeChanged()
    -- Disabled module does ZERO work: a Group 1 box resize (CDM layout / spec / icon add-remove /
    -- zone transition) still fires this hook, but we skip the closure + C_Timer + ApplyLayout work.
    -- The hook is a HookScript (unremovable); CB.ApplyEnabled() re-applies layout on re-enable.
    if not enabled then return end
    if sizePending then return end
    sizePending = true
    C_Timer.After(0, function()
        sizePending = false
        if not container then return end
        ApplyLayout()
        CB.ApplyPosition()
    end)
end

local hookedBoxes = {}
local function HookGroupOneBoxes()
    for _, dest in ipairs({ "essential", "utility" }) do
        local inst = ns.CDMGroups and ns.CDMGroups[dest]
        local box  = inst and inst.GetContainer and inst.GetContainer(1)
        if box and not hookedBoxes[box] then
            hookedBoxes[box] = true
            box:HookScript("OnSizeChanged", OnAnchorSizeChanged)
        end
    end
end

-- ── Start / stop a cast ───────────────────────────────────────────────────────
-- kind: "cast" (fill up) | "channel" (channel/empower; non-empower fills down).
local function StartCast(kind)
    if not container or not enabled then return end
    local name, text, texture, startMs, endMs, notInt, channel, castID, isEmpowered, numStages
    if kind == "cast" then
        name, text, texture, startMs, endMs, _, castID, notInt = UnitCastingInfo("player")
        channel = false
    else
        name, text, texture, startMs, endMs, _, notInt, _, isEmpowered, numStages = UnitChannelInfo("player")
        channel = not isEmpowered   -- empowered casts build up like a normal cast
    end
    if not name or not startMs or not endMs then CB.StopCast(); return end

    cast.active  = true
    cast.channel = channel and true or false
    -- Which START fired, so the matching STOP family is the only one that ends the bar:
    -- "cast" (UNIT_SPELLCAST_STOP), "channel" (CHANNEL_STOP), "empower" (EMPOWER_STOP).
    cast.startKind = (kind == "cast") and "cast" or (isEmpowered and "empower" or "channel")
    cast.castID  = castID   -- nil for channels/empowers (UnitChannelInfo carries no cast GUID)
    cast.numStages = isEmpowered and numStages or nil   -- empower stage count, for the ApplyLayout pip reposition
    cast.startT  = startMs / 1000
    cast.endT    = endMs / 1000
    cast.notInt  = notInt and true or false
    -- Cache showTimer here instead of CfgGet-ing it every OnUpdate frame.
    cast.showTimer = C("showTimer") ~= false

    if C("showIcon") ~= false then icon:SetTexture(texture); icon:Show() end
    if C("showSpellName") ~= false then nameFS:SetText(text or name) end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(cast.channel and 1 or 0)
    ApplyColor()
    -- Empower stage notches (Evoker): shown for empowered casts, cleared for everything else.
    if isEmpowered then ShowEmpowerPips(numStages) else HideEmpowerPips() end
    -- Anchor the spark once at cast start; OnUpdate then only adjusts its x-offset.
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", bar, "LEFT", 0, 0)
    container:SetScript("OnUpdate", OnUpdate)
    container:Show()
end

function CB.StopCast()
    cast.active = false
    cast.startKind = nil; cast.numStages = nil   -- no stale empower state lingers after a cast ends
    HideEmpowerPips()
    if container then
        container:SetScript("OnUpdate", nil)
        if not CB.IsUnlocked() then container:Hide() end
    end
end

-- ── Event routing ─────────────────────────────────────────────────────────────
-- castGUID is the event's own cast token (2nd payload arg after unit). We gate the
-- "end" events on it + on which START opened the bar, so a stale STOP can't blank the
-- bar before the cast finishes — the cause of "disappears before the end of some casts":
--   * an instant / off-GCD spell fired mid-cast sends its OWN UNIT_SPELLCAST_STOP with a
--     different GUID — it must NOT kill the real cast (matches Blizzard's CastingBarFrame);
--   * a channel's brief lead-in UNIT_SPELLCAST_STOP arrives right after CHANNEL_START — it
--     must be ignored while we're channelling.
-- A nil castID (channels carry none) or nil castGUID falls through the guard (still ends).
local function GuidMatches(castGUID)
    return (not cast.castID) or (not castGUID) or (cast.castID == castGUID)
end

local function OnEvent(_, event, unit, castGUID)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_START" then
        StartCast("cast")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        StartCast("channel")
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        if cast.active and not cast.channel then StartCast("cast") end
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        if cast.active then StartCast("channel") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        cast.notInt = false; if cast.active then ApplyColor() end
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        cast.notInt = true; if cast.active then ApplyColor() end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        -- Only a plain cast's own STOP/FAILED ends it (channels/empowers use their own STOP).
        if cast.active and cast.startKind == "cast" and GuidMatches(castGUID) then CB.StopCast() end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if cast.active and GuidMatches(castGUID) then CB.StopCast() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if cast.active and cast.startKind == "channel" then CB.StopCast() end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if cast.active and cast.startKind == "empower" then CB.StopCast() end
    end
end

-- ── Frame construction (lazy) ─────────────────────────────────────────────────
local function EnsureFrames()
    if container then return end
    container = CreateFrame("Frame", "UnbunkCastBar", UIParent, "BackdropTemplate")
    -- HIGH so the whole cast bar (the StatusBar child `bar`, the icon, the 4 border-edge
    -- textures drawn on this container, and the name/timer text) always draws ABOVE every CDM
    -- element — the Essential / Utility / Tracked Buffs / Tracked Bars viewers plus the
    -- below-player and free icons all live on MEDIUM. Frame STRATA dominates frame level, and the
    -- CDM side's levels are dynamic (PinNative / glow / border re-impose), so raising the strata
    -- is the robust lever rather than chasing levels. Stays below DIALOG/TOOLTIP (config windows,
    -- tooltips), which is intended.
    container:SetFrameStrata("HIGH")
    container:SetClampedToScreen(true)
    container:Hide()

    bar = CreateFrame("StatusBar", nil, container)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.7)

    icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Text is parented to the BAR (a child frame, above the container) at a high OVERLAY
    -- sublevel, so it always draws on top of the advancing fill and the spark.
    nameFS = bar:CreateFontString(nil, "OVERLAY")
    timeFS = bar:CreateFontString(nil, "OVERLAY")
    nameFS:SetDrawLayer("OVERLAY", 7)
    timeFS:SetDrawLayer("OVERLAY", 7)

    spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK_TEXTURE)
    spark:SetBlendMode("ADD")

    container:SetScript("OnEvent", OnEvent)
    ApplyLayout()
end

local function RegisterCastEvents()
    for _, e in ipairs(CAST_EVENTS) do container:RegisterUnitEvent(e, "player") end
end
local function UnregisterCastEvents()
    for _, e in ipairs(CAST_EVENTS) do container:UnregisterEvent(e) end
end

-- ── Enable / disable the whole module ─────────────────────────────────────────
function CB.ApplyEnabled()
    EnsureFrames()
    if C("enabled") ~= false then
        enabled = true
        RegisterCastEvents()
        ApplyLayout()
        CB.ApplyPosition()
    else
        enabled = false
        UnregisterCastEvents()
        CB.StopTest()   -- clears `testing` too, so a running Test preview's OnUpdate stops (StopTest → StopCast)
        if not CB.IsUnlocked() then container:Hide() end
    end
end

function CB.ApplyConfig()
    EnsureFrames()
    HookGroupOneBoxes()
    ApplyLayout()
    CB.ApplyPosition()
    if cast.active then ApplyColor() end
end

-- ── Test preview (the "Test" toggle under Enable cast bar) ─────────────────────
-- Drives a looping fake cast so the current styling is visible; works even while the
-- module is disabled. OnUpdate restarts the timer instead of stopping while `testing`.
-- (Defined down here so EnsureFrames is already in scope.)
function CB.IsTesting() return testing end
function CB.StartTest()
    EnsureFrames()
    testing      = true
    cast.active  = true
    cast.channel = false
    cast.notInt  = false
    cast.startKind = "cast"   -- not an empower: clear any stale empower state so the test bar shows no stage pips
    cast.numStages = nil
    cast.startT  = GetTime()
    cast.endT    = GetTime() + 2.5
    cast.showTimer = C("showTimer") ~= false
    ApplyLayout()
    if C("showIcon") ~= false then icon:SetTexture(PREVIEW_ICON); icon:Show() end
    if C("showSpellName") ~= false then nameFS:SetText((ns.L and ns.L["Cast bar"]) or "Cast bar") end
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    ApplyColor()
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", bar, "LEFT", 0, 0)
    container:SetScript("OnUpdate", OnUpdate)
    container:Show()
end
function CB.StopTest()
    testing = false
    CB.StopCast()
end

-- ── Hide / restore Blizzard's native player cast bar ──────────────────────────
local blizzHooked, blizzHidden = false, false
function CB.ApplyBlizzard()
    local pcb = PlayerCastingBarFrame or _G.CastingBarFrame
    if not pcb then return end
    if C("hideBlizzard") ~= false then
        blizzHidden = true
        pcb:UnregisterAllEvents()
        pcb:Hide()
        if not blizzHooked then
            blizzHooked = true
            -- Keep it down even if another addon (or Blizzard) tries to revive it.
            hooksecurefunc(pcb, "Show", function(self) if blizzHidden then self:Hide() end end)
            hooksecurefunc(pcb, "RegisterEvent", function(self) if blizzHidden then self:UnregisterAllEvents() end end)
            hooksecurefunc(pcb, "RegisterUnitEvent", function(self) if blizzHidden then self:UnregisterAllEvents() end end)
        end
    elseif blizzHidden then
        -- Best-effort restore (a /reload fully re-initialises Blizzard's own setup).
        blizzHidden = false
        for _, e in ipairs(CAST_EVENTS) do pcall(pcb.RegisterUnitEvent, pcb, e, "player") end
    end
end

-- ── Unlock / drag (config "position" editor) ──────────────────────────────────
function CB.SetUnlocked(val)
    EnsureFrames()
    if val then
        ApplyLayout()
        CB.ApplyPosition()
        container:SetMovable(true)
        container:EnableMouse(true)
        container:RegisterForDrag("LeftButton")
        container:SetScript("OnDragStart", function(self) self:StartMoving() end)
        container:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Store the drop as an offset from the chosen anchor point, so it reproduces
            -- under SetPoint(selfPoint, anchorFrame, anchorPoint, posX, posY).
            local af = AnchorDestFrame(C("anchorTo") or "essential") or UIParent
            local sp, ap = RelPoints()
            if af == UIParent then ap = "CENTER" end
            local sx, sy = PointAbs(self, sp)
            local ax, ay = PointAbs(af, ap)
            local cs = self:GetEffectiveScale()
            if not (sx and ax and cs and cs > 0) then return end
            local x = floor((sx - ax) / cs)
            local y = floor((sy - ay) / cs)
            CB.CfgSet("posX", x); CB.CfgSet("posY", y)
            self:ClearAllPoints()
            self:SetPoint(sp, af, ap, x, y)
            if CB.pe then CB.pe.Refresh() end
        end)
        container:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        ns.SetBrandBorder(container, 0.8)
        -- Static preview so the bar is visible to position.
        cast.active = false
        HideEmpowerPips()
        container:SetScript("OnUpdate", nil)
        bar:SetMinMaxValues(0, 1); bar:SetValue(0.6)
        local cc = C("castColor") or { r = 1, g = 0.7, b = 0 }
        bar:SetStatusBarColor(cc.r, cc.g, cc.b, cc.a or 1)
        if C("showSpellName") ~= false then nameFS:SetText((ns.L and ns.L["Cast bar"]) or "Cast bar") end
        if C("showTimer") ~= false then timeFS:SetText("1.5") end
        if C("showIcon") ~= false then icon:SetTexture(PREVIEW_ICON); icon:Show() end
        if spark:IsShown() then spark:ClearAllPoints(); spark:SetPoint("CENTER", bar, "LEFT", (bar:GetWidth() or 0) * 0.6, 0) end
        container:Show()
    else
        container:SetMovable(false)
        container:EnableMouse(false)
        container:SetScript("OnDragStart", nil)
        container:SetScript("OnDragStop", nil)
        container:SetBackdrop(nil)
        CB.StopCast()
        container:Hide()   -- re-shows on the next real cast
    end
end

function CB.IsUnlocked()
    return container and container:IsMovable() and container:IsMouseEnabled() or false
end

-- ── Profile reload + login bootstrap ─────────────────────────────────────────
ns.RegisterReloadHook(function()
    CB.ApplyEnabled()
    CB.ApplyConfig()
    CB.ApplyBlizzard()
end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    EnsureFrames()
    CB.ApplyEnabled()
    CB.ApplyConfig()
    CB.ApplyBlizzard()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
