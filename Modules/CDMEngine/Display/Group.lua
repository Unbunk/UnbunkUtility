-- Modules/CDMEngine/Display/Group.lua
--
-- Phase 2 of the standalone CDM engine (ns.CDMEngine). A pooled GROUP container frame: a plain anchor
-- frame that holds a flow of E.Icon widgets (one category → one group). No textures, no native-frame
-- contact. It carries a CACHED size (GetDefaultSize / SetDefaultSize) that the container measures
-- bottom-up, instead of reading the live GetWidth() while a SetSize is still in flight (the the reference engine
-- BaseLayout gotcha). Group.Release does NOT release its child icons — E.Icon.ReleaseAll owns that
-- teardown (single owner, avoids double-release).

local _, ns = ...
ns.CDMEngine = ns.CDMEngine or {}
local E = ns.CDMEngine
local Group = {}
E.Group = Group

local pool, active = {}, {}

local function BuildGroupFrame()
    local g = CreateFrame("Frame", nil, UIParent)
    if ns.SetTrackerIconStrata then ns.SetTrackerIconStrata(g) else g:SetFrameStrata("MEDIUM") end
    g.children = {}
    g.w, g.h = 1, 1
    return g
end

function Group.Acquire()
    local g = table.remove(pool) or BuildGroupFrame()
    active[g] = true
    return g
end

function Group.Setup(g, spec)
    g.spec = spec
    if g.children then wipe(g.children) else g.children = {} end
    g.w, g.h = 1, 1
    g:Show()
end

-- Cached (measured) size — read by the container when stacking groups.
function Group.GetDefaultSize(g)
    return g.w or 1, g.h or 1
end
function Group.SetDefaultSize(g, w, h)
    g.w, g.h = w, h
    g:SetSize(w, h)
end

function Group.Release(g)
    if not g then return end
    active[g] = nil
    g.spec = nil
    if g.children then wipe(g.children) end   -- child icons are freed by E.Icon.ReleaseAll, not here
    g.w, g.h = 1, 1
    g:Hide()
    g:ClearAllPoints()
    g:SetParent(UIParent)
    pool[#pool + 1] = g
end

function Group.ReleaseAll()
    for g in pairs(active) do Group.Release(g) end
end
