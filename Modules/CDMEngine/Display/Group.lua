-- Modules/CDMEngine/Display/Group.lua
--
-- Phase 2 of the standalone CDM engine (ns.CDMEngine). A pooled GROUP container frame: a plain anchor
-- frame that holds a flow of E.Icon widgets (one category → one group). No textures, no native-frame
-- contact. It carries a CACHED size (GetDefaultSize / SetDefaultSize) that the container measures
-- bottom-up, instead of reading the live GetWidth() while a SetSize is still in flight (the Coolinator
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
    g.trackers = {}   -- L2: hosted CDM tracker descriptors (module-owned frames; never E.Icon-released)
    g.nativeBuffs = {}   -- hosted NATIVE BuffIcon pool frames (re-anchored via CDMAnchor.PinNativeTo)
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
    g.catKey = spec and spec.key   -- stable string key ("Essential"/...) for per-group designer positions
    if g.children then wipe(g.children) else g.children = {} end
    if g.trackers then wipe(g.trackers) else g.trackers = {} end
    if g.nativeBuffs then wipe(g.nativeBuffs) else g.nativeBuffs = {} end
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
    g.catKey = nil
    if g.children then wipe(g.children) end   -- child icons are freed by E.Icon.ReleaseAll, not here
    -- L2: hosted tracker frames are module-owned (never E.Icon-released), but we MUST let go of them here —
    -- re-parent each back to UIParent so a tracker that hid ITSELF (and so won't be re-collected by the next
    -- PopulateGroup) is never left an invisible child of this pooled/reused group. A still-shown tracker is
    -- immediately re-parented into the fresh group by PopulateGroup/ArrangeGroup, so this is a no-op for it.
    if g.trackers then
        for _, td in ipairs(g.trackers) do
            if td.frame then td.frame:ClearAllPoints(); td.frame:SetParent(UIParent) end
        end
        wipe(g.trackers)
    end
    -- Hosted native BuffIcon frames: hand them BACK to their viewer (ReleaseNativeAdopt RawSetParents them
    -- onto BuffIconCooldownViewer + clears our _uuAdopt so the re-impose hooks go inert). A still-active buff
    -- is immediately re-adopted by the next PopulateGroup/ArrangeGroup; an expired one is re-owned by the
    -- viewer's own layout (which hides it). Never Hide/Show them (taint vectors).
    if g.nativeBuffs then
        for _, nf in ipairs(g.nativeBuffs) do
            if ns.CDMAnchor and ns.CDMAnchor.ReleaseNativeAdopt then ns.CDMAnchor.ReleaseNativeAdopt(nf) end
        end
        wipe(g.nativeBuffs)
    end
    g.w, g.h = 1, 1
    g:Hide()
    g:ClearAllPoints()
    g:SetParent(UIParent)
    pool[#pool + 1] = g
end

function Group.ReleaseAll()
    for g in pairs(active) do Group.Release(g) end
end
