-- UI/Shared/Prompt.lua
-- Small modal text-entry dialog (e.g. "name the imported profile"). Matches the
-- addon's dark window style and is reused as a singleton.
--
-- Usage:
--   ns.ui.ShowPrompt({
--       title      = L["Import profile"],
--       text       = L["Name the new profile:"],
--       default    = "Imported",
--       acceptText = L["Import"],     -- optional (default: OK)
--       cancelText = L["Cancel"],     -- optional (default: Cancel)
--       maxLetters = 32,              -- optional (default: 32)
--       onAccept   = function(value) ... end,
--       onCancel   = function() ... end,   -- optional
--   })

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

local dialog  -- singleton, created lazily on first ShowPrompt

local function EnsureDialog()
    if dialog then return dialog end

    -- FULLSCREEN_DIALOG sits above the config window (DIALOG strata) so the prompt
    -- is always on top of it.
    local f = CreateFrame("Frame", "UnbunkUtilityPrompt", UIParent, "BackdropTemplate")
    f:SetSize(380, 162)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)   -- swallow clicks on the dialog body
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "UnbunkUtilityH2")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    f.title = title

    local desc = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -46)
    desc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -46)
    desc:SetJustifyH("LEFT")
    f.desc = desc

    local input = ns.ui.CreateTextInput({
        parent = f, width = 344, height = 26, maxLetters = 32, text = "",
    })
    input.frame:SetPoint("TOP", f, "TOP", 0, -74)
    f.input = input

    -- OnClick handlers are (re)bound per ShowPrompt call (see below).
    local accept = ns.ui.CreateButton({ parent = f, label = L["OK"],     width = 110, height = 24 })
    accept.frame:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 16)
    f.accept = accept

    local cancel = ns.ui.CreateButton({ parent = f, label = L["Cancel"], width = 110, height = 24 })
    cancel.frame:SetPoint("BOTTOMLEFT", f, "BOTTOM", 8, 16)
    f.cancel = cancel

    dialog = f
    return f
end

function ns.ui.ShowPrompt(opts)
    opts = opts or {}
    local f = EnsureDialog()

    f.title:SetText(opts.title or "")
    f.desc:SetText(opts.text or "")
    f.input.editBox:SetMaxLetters(opts.maxLetters or 32)
    f.input.SetText(opts.default or "")
    f.accept.SetText(opts.acceptText or L["OK"])
    f.cancel.SetText(opts.cancelText or L["Cancel"])

    -- `closed` guards against accept+hide firing twice (e.g. Enter then a click).
    local closed = false
    local function close()
        if closed then return end
        closed = true
        f.input.editBox:ClearFocus()
        f:Hide()
    end
    local function doAccept()
        local v = f.input.GetText()
        close()
        if opts.onAccept then opts.onAccept(v) end
    end
    local function doCancel()
        close()
        if opts.onCancel then opts.onCancel() end
    end

    f.accept.frame:SetScript("OnClick", doAccept)
    f.cancel.frame:SetScript("OnClick", doCancel)
    f.input.editBox:SetScript("OnEnterPressed", doAccept)
    f.input.editBox:SetScript("OnEscapePressed", doCancel)

    f:Show()
    f:Raise()
    f.input.editBox:SetFocus()
    f.input.editBox:HighlightText()
end
