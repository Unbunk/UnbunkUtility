-- Modules/DecursiveMove/Core/DecursiveMove.lua
-- Owner utility: reposition Decursive's Micro-Unit-Frame (MUF) container. Decursive keeps
-- the container at D.profile.DebuffsFrameContainer_x/y and exposes two methods we drive:
--   D.MicroUnitF:SavePos()  -- store the container's CURRENT on-screen position (handles
--                              the StickToRight offset) into the profile
--   D.MicroUnitF:Place()    -- re-anchor the container from the saved position
-- An "Unlock" overlay lets the user drag the container (out of combat — the container is a
-- secure frame holding the MUF buttons, so Decursive itself postpones placement in combat);
-- on drop we just call Decursive's own SavePos + Place so the coordinate convention stays
-- exactly theirs. Reachable only from the owner-gated "Personal utilities" tab.

local _, ns = ...
local L = ns.L
ns.DecursiveMove = ns.DecursiveMove or {}
local DM = ns.DecursiveMove

-- Resolve the Decursive addon object (optional dependency — nil when absent).
local function GetDecursive()
    if not LibStub then return nil end
    local AceAddon = LibStub("AceAddon-3.0", true)
    if not (AceAddon and AceAddon.GetAddon) then return nil end
    return AceAddon:GetAddon("Decursive", true)   -- silent=true → nil if not loaded
end

-- D, MicroUnitF manager, container frame (any may be nil if Decursive isn't ready).
local function GetMUF()
    local D = GetDecursive()
    local muf = D and D.MicroUnitF
    return D, muf, (muf and muf.Frame)
end

function DM.IsAvailable()
    local _, _, frame = GetMUF()
    return frame ~= nil
end

-- ── Unlock overlay ────────────────────────────────────────────────────────────
local unlocked = false
local overlay

local function EnsureOverlay()
    if overlay then return overlay end
    local o = CreateFrame("Frame", "UnbunkDecursiveMUFMover", UIParent, "BackdropTemplate")
    o:SetFrameStrata("FULLSCREEN_DIALOG")
    o:SetToplevel(true)
    o:EnableMouse(true)
    o:RegisterForDrag("LeftButton")
    o:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    local r, g, b = ns.GetBrandColor()
    o:SetBackdropColor(r, g, b, 0.30)
    o:SetBackdropBorderColor(r, g, b, 1)

    local lbl = o:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH6")
    lbl:SetPoint("CENTER")
    lbl:SetText(L["Drag to move"])

    o:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            ns.Print(L["Can't move Decursive's frame in combat."])
            return
        end
        local _, _, f = GetMUF()
        if f then f:SetMovable(true); f:StartMoving() end
    end)
    o:SetScript("OnDragStop", function()
        local _, muf, f = GetMUF()
        if f then f:StopMovingOrSizing() end
        if muf and muf.SavePos then muf:SavePos() end   -- store new pos (Decursive's convention)
        if muf and muf.Place   then muf:Place()   end   -- re-anchor cleanly
    end)
    o:Hide()
    overlay = o
    return o
end

-- Re-tint the overlay live with the brand colour.
if ns.RegisterBrandRefresh then
    ns.RegisterBrandRefresh("DecursiveMUFMover", function(r, g, b)
        if overlay then overlay:SetBackdropColor(r, g, b, 0.30); overlay:SetBackdropBorderColor(r, g, b, 1) end
    end)
end

function DM.SetUnlocked(v)
    unlocked = v and true or false
    local _, _, frame = GetMUF()
    if not frame then unlocked = false; if overlay then overlay:Hide() end; return end
    local o = EnsureOverlay()
    if unlocked then
        o:ClearAllPoints(); o:SetAllPoints(frame); o:Show(); o:Raise()
    else
        o:Hide()
    end
end

function DM.IsUnlocked() return unlocked end

-- Clear the saved position → Decursive re-places the container at its default corner.
function DM.Reset()
    local D, muf = GetMUF()
    if not (D and muf) then return end
    if InCombatLockdown() then
        ns.Print(L["Can't move Decursive's frame in combat."])
        return
    end
    if D.profile then
        D.profile.DebuffsFrameContainer_x = false
        D.profile.DebuffsFrameContainer_y = false
    end
    if muf.Place then muf:Place() end
end

-- Always drop the overlay when combat starts (it would otherwise eat clicks meant for the
-- MUFs, i.e. block curing) and on reload.
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function() if unlocked then DM.SetUnlocked(false) end end)

ns.RegisterReloadHook(function() if unlocked then DM.SetUnlocked(false) end end)
