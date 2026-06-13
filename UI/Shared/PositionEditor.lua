-- UI/PositionEditor.lua

local _, ns = ...
local L = ns.L
ns.ui = ns.ui or {}

function ns.ui.CreatePositionEditor(parent, config)
    local label      = config.label or L["Position (offset from screen center)"]
    local getX       = config.getX
    local getY       = config.getY
    local onApply    = config.onApply
    local onUnlock   = config.onUnlock
    local onLock     = config.onLock
    local isUnlocked = config.isUnlocked

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    container:SetWidth(518)

    local height = 0
    local result = {}

    -- ── Label ─────────────────────────────────────────────────────────────────

    local sectionLabel = container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH4")
    sectionLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    sectionLabel:SetText(label)
    height = height + 20

    -- ── X offset ──────────────────────────────────────────────────────────────

    local xLbl = container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
    xLbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    xLbl:SetText(L["X offset"])

    local yLbl = container:CreateFontString(nil, "ARTWORK", "UnbunkUtilityBody")
    yLbl:SetPoint("LEFT", xLbl, "RIGHT", 40, 0)
    yLbl:SetText(L["Y offset"])

    height = height + 18

    local xInput = ns.ui.CreateTextInput({
        parent     = container,
        width      = 70,
        height     = 22,
        numeric       = true,
        allowNegative = true,
        maxLetters = 7,
        text       = tostring(getX() or 0),
    })
    xInput.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    result.xBox = xInput.editBox

    local yInput = ns.ui.CreateTextInput({
        parent     = container,
        width      = 70,
        height     = 22,
        numeric       = true,
        allowNegative = true,
        maxLetters = 7,
        text       = tostring(getY() or 0),
    })

    xInput.editBox:SetScript("OnEnterPressed", function(self)
        local x = tonumber(self:GetText())
        local y = tonumber(yInput.GetText())
        if x and y and onApply then onApply(x, y) end
        self:ClearFocus()
    end)

    yInput.editBox:SetScript("OnEnterPressed", function(self)
        local x = tonumber(xInput.GetText())
        local y = tonumber(self:GetText())
        if x and y and onApply then onApply(x, y) end
        self:ClearFocus()
    end)
    yInput.frame:SetPoint("LEFT", xInput.frame, "RIGHT", 40, 0)
    result.yBox = yInput.editBox

    local unlockBtnWidget = ns.ui.CreateButton({
        parent = container,
        label  = isUnlocked and isUnlocked() and L["Lock"] or L["Unlock"],
        width  = 80,
        height = 22,
    })
    local unlockBtn = unlockBtnWidget.frame
    unlockBtn:SetPoint("LEFT", yInput.frame, "RIGHT", 10, 2)
    result.unlockBtn = unlockBtn

    local currentlyUnlocked = false

    unlockBtn:SetScript("OnClick", function()
        currentlyUnlocked = not currentlyUnlocked
        if currentlyUnlocked then
            unlockBtnWidget.SetText(L["Lock"])
            if onUnlock then onUnlock() end
        else
            unlockBtnWidget.SetText(L["Unlock"])
            xInput.SetText(tostring(getX() or 0))
            yInput.SetText(tostring(getY() or 0))
            if onLock then onLock() end
        end
    end)

    parent:HookScript("OnHide", function()
        -- If the panel is hidden (tab switch / window close) while still
        -- unlocked, run the lock callback so the target frame is actually
        -- re-locked via the consumer's SetUnlocked(false). Without this it
        -- stays movable + force-shown until the config is reopened and Lock
        -- is clicked manually.
        if currentlyUnlocked and onLock then onLock() end
        currentlyUnlocked = false
        unlockBtnWidget.SetText(L["Unlock"])
    end)

    height = height + 30

    container:SetHeight(height)
    result.frame  = container
    result.height = height

    function result.Refresh()
        xInput.SetText(tostring(getX() or 0))
        yInput.SetText(tostring(getY() or 0))
        currentlyUnlocked = isUnlocked and isUnlocked() or false
        unlockBtnWidget.SetText(currentlyUnlocked and L["Lock"] or L["Unlock"])
    end

    return result
end