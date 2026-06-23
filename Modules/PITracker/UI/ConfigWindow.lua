-- Modules/PITracker/UI/ConfigWindow.lua

local _, ns = ...
local L = ns.L
ns.PITracker = ns.PITracker or {}
local PI = ns.PITracker

local function CreatePITrackerPanel(parent)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local menu  -- forward declare so closures can reach menu.refs.pe

    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 26, text = L["PI Tracker"] },

        -- ════════════ General: enable + where it is active ════════════
        {
            type  = "group",
            title = L["General"],
            -- Disabling the module greys everything in General (Test button, instance
            -- filter) except the enable checkbox itself, which stays live to re-enable.
            gate  = { enabled = function() return PI.CfgGet("enabled") ~= false end, master = "enable" },
            build = function()
                return {
                    -- ── Enable checkbox (gate master — stays live) ────────────────────────
                    {
                        type   = "checkbox",
                        ref    = "enable",
                        label  = L["Enable PI Tracker"],
                        height = 28,
                        disabled = function() return true end,   -- locked: feature unavailable
                        get    = function() return PI.CfgGet("enabled") ~= false end,
                        set    = function(val)
                            PI.CfgSet("enabled", val)
                            PI.SetEnabled(val)   -- live start/stop of the 0.5s ticker
                            PI.ApplyVisuals()
                            if menu then menu.Refresh() end
                        end,
                    },

                    -- ── Test button (greys with the module — not the gate master) ─────────
                    {
                        type    = "button",
                        label   = L["Test"],
                        width   = 80,
                        height  = 22,
                        onClick = function() PI.RunTest(20) end,
                    },

                    -- Instance filter
                    {
                        type      = "instanceFilter",
                        getConfig = function() return PI.CfgGet("instanceFilter") end,
                        setConfig = function(key, val)
                            local filter = PI.CfgGet("instanceFilter")
                            filter[key] = val
                            PI.CfgSet("instanceFilter", filter)
                        end,
                    },
                }
            end,
        },

        -- ════════════ Sound ════════════
        {
            type  = "group",
            title = L["Sound"],
            enabledBy = function() return PI.CfgGet("enabled") ~= false end,
            build = function()
                return {
                    {
                        type      = "sound",
                        LSM       = LSM,
                        label     = L["Sound on PI"],
                        getKey    = function() return PI.CfgGet("soundKeyPI") end,
                        getEnable = function() return PI.CfgGet("soundOnPI") end,
                        onSelect  = function(key, path)
                            PI.CfgSet("soundKeyPI", key)
                            PI.CfgSet("soundPathPI", path)
                        end,
                        onToggle  = function(val) PI.CfgSet("soundOnPI", val) end,
                        onTest    = function() PI.PlaySound() end,
                    },
                }
            end,
        },

        -- ════════════ Icon ════════════
        {
            type  = "group",
            title = L["Icon"],
            enabledBy = function() return PI.CfgGet("enabled") ~= false end,
            -- Unchecking "Show icon" greys the rest of the Icon box (placement / border /
            -- timer text) since there is no icon to configure; the checkbox stays live.
            gate      = { enabled = function() return PI.CfgGet("showIcon") ~= false end, master = "showicon" },
            build = function()
                local frameName = "PITrackerFrame"
                local function inCdm() return ns.CDMIncludedVal(PI.CfgGet("includeInCdm")) end
                local function curDest() return PI.CfgGet("cdmDest") or "essential" end
                local function rebuildMenu() if menu then menu.Rebuild() end end
                local function applyIcon()
                    if ns.BumpStyleEpoch then ns.BumpStyleEpoch() end   -- in-CDM size override -> force the engine to re-pack (its layout sig folds the epoch)
                    PI.ApplyVisuals(); PI.ApplyFont(); PI.ApplyBorder(); PI.ApplySize()
                    if ns.CDMAnchor and ns.CDMAnchor.RefreshAll then ns.CDMAnchor.RefreshAll(true) end
                end

                local e = {
                    { type = "checkbox", ref = "showicon", label = L["Show icon"], height = 24,
                      get = function() return PI.CfgGet("showIcon") ~= false end,
                      set = function(val) PI.CfgSet("showIcon", val); PI.ApplyVisuals() end },

                    { type = "group", title = L["Placement"], build = function() return {
                        { type = "checkbox", label = L["Include in cdm"],
                          disabled = function() return not ns.IsCDMEnabled() end,
                          get = function() return inCdm() end,
                          set = function(v) PI.CfgSet("includeInCdm", v); PI.ApplySize(); PI.ApplyPosition(); rebuildMenu() end },
                        { type = "dropdown", label = L["Anchor to"], width = 200, height = 50,
                          when = function() return inCdm() end,
                          getList = function() return ns.CDMDestList() end,
                          getCurrentKey = function() return ns.CDMDestChoiceLabel(PI.CfgGet) end,
                          onSelect = function(label) ns.CDMApplyDestChoice(label, PI.CfgSet); PI.ApplySize(); PI.ApplyPosition(); rebuildMenu() end },
                    } end },
                }

                local cfg = {
                    frameName  = frameName,
                    getDest    = curDest,
                    cdmAtEnd   = function() return PI.CfgGet("cdmAtEnd") end,
                    inCdm      = inCdm,
                    applyIcon  = applyIcon,
                    rebuild    = rebuildMenu,
                    getOv      = function() return PI.CfgGet("ovCollapsed") ~= false end,
                    setOv      = function(c) PI.CfgSet("ovCollapsed", c) end,
                    getFree    = function() return PI.CfgGet("freeCollapsed") ~= false end,
                    setFree    = function(c) PI.CfgSet("freeCollapsed", c) end,
                    -- Default override-set: ONLY Timer (size 14 + urgency thresholds). Rest inherits the group.
                    seedValues = function() return ns.DefaultTrackerTimerSeed() end,
                    freeBuild  = function()
                        return ns.CDMGroups.TrackerFreeCadres({
                            get       = PI.CfgGet,
                            set       = PI.CfgSet,
                            touch     = applyIcon,
                            rebuild   = rebuildMenu,
                            sizeApply = function() PI.ApplySize() end,
                            LSM       = LSM,
                            pos = {
                                getX = function() return PI.CfgGet("posX") end,
                                getY = function() return PI.CfgGet("posY") end,
                                onApply = function(x, yv) if x then PI.CfgSet("posX", x) end if yv then PI.CfgSet("posY", yv) end PI.ApplyPosition() end,
                                onUnlock = function() PI.SetUnlocked(true) end,
                                onLock = function() PI.SetUnlocked(false); if PI.pe then PI.pe.Refresh() end end,
                                isUnlocked = function() return PI.IsUnlocked() end,
                                onBuilt = function(w) PI.pe = w end,
                            },
                        })
                    end,
                }
                for _, x in ipairs(ns.CDMGroups.TrackerCdmCadres(cfg)) do e[#e + 1] = x end
                return e
            end,
        },
    }

    -- gap=12, width=518, autoHook=true -> OnShow re-sync is generated automatically.
    menu = ns.ui.BuildMenu(parent, options, { gap = 12, width = 518, LSM = LSM })

    -- The Override / Free settings sections start collapsed and re-collapse on each tab show.
    parent:HookScript("OnHide", function()
        PI.CfgSet("ovCollapsed", true); PI.CfgSet("freeCollapsed", true)
    end)
    parent:HookScript("OnShow", function() if menu then menu.Rebuild() end end)

    -- Feature-unavailable banner. Put it in its own frame raised WAY above the greyed
    -- cadres AND the disable-gate click-blockers (those sit at host level + 500), so the
    -- red text reads clearly on top of everything. Anchored a bit above centre.
    local bannerFrame = CreateFrame("Frame", nil, parent)
    bannerFrame:SetAllPoints(parent)
    bannerFrame:SetFrameLevel((parent:GetFrameLevel() or 0) + 1000)
    local banner = bannerFrame:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    banner:SetPoint("CENTER", bannerFrame, "CENTER", 0, 100)
    banner:SetJustifyH("CENTER")
    banner:SetText(L["|cffff4444Feature unavailable since Midnight changes.\nWorking on it...|r"])

    return menu
end

-- ── Enregistrement ──────────────────────────────────────────────────────────────

UnbunkUtility.OnAddonLoaded(function()
    UnbunkUtility.RegisterModule(L["PI Tracker"], nil, CreatePITrackerPanel)
end)
