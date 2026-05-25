-- UI/PositionEditor.lua

function HealerRange_CreatePositionEditor(parent, config)
    local label      = config.label or "Position (offset from screen center)"
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

    local sectionLabel = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sectionLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    sectionLabel:SetText(label)
    height = height + 20

    -- ── X offset ──────────────────────────────────────────────────────────────

    local xLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    xLbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    xLbl:SetText("X offset")

    local yLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    yLbl:SetPoint("LEFT", xLbl, "RIGHT", 40, 0)
    yLbl:SetText("Y offset")

    height = height + 18

    local xBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    xBox:SetSize(70, 20)
    xBox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -height)
    xBox:SetAutoFocus(false)
    xBox:SetMaxLetters(6)
    xBox:SetText(tostring(getX() or 0))
    result.xBox = xBox

    local yBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    yBox:SetSize(70, 20)
    yBox:SetPoint("LEFT", xBox, "RIGHT", 40, 0)
    yBox:SetAutoFocus(false)
    yBox:SetMaxLetters(6)
    yBox:SetText(tostring(getY() or 0))
    result.yBox = yBox

    local function ApplyPos()
        local x  = tonumber(xBox:GetText())
        local yv = tonumber(yBox:GetText())
        if onApply then onApply(x, yv) end
    end

    xBox:SetScript("OnEnterPressed", function(self) ApplyPos() self:ClearFocus() end)
    yBox:SetScript("OnEnterPressed", function(self) ApplyPos() self:ClearFocus() end)

    local unlockBtnWidget = Unbunk_CreateButton({
        parent = container,
        label  = isUnlocked and isUnlocked() and "Lock" or "Unlock",
        width  = 80,
        height = 22,
    })
    local unlockBtn = unlockBtnWidget.frame
    unlockBtn:SetPoint("LEFT", yBox, "RIGHT", 10, 2)
    result.unlockBtn = unlockBtn

    local currentlyUnlocked = false

    unlockBtn:SetScript("OnClick", function()
        currentlyUnlocked = not currentlyUnlocked
        if currentlyUnlocked then
            unlockBtnWidget.SetText("Lock")
            if onUnlock then onUnlock() end
        else
            unlockBtnWidget.SetText("Unlock")
            xBox:SetText(tostring(getX() or 0))
            yBox:SetText(tostring(getY() or 0))
            if onLock then onLock() end
        end
    end)

    parent:HookScript("OnHide", function()
        currentlyUnlocked = false
        unlockBtnWidget.SetText("Unlock")
    end)

    height = height + 30

    container:SetHeight(height)
    result.frame  = container
    result.height = height

    function result.Refresh()
        xBox:SetText(tostring(getX() or 0))
        yBox:SetText(tostring(getY() or 0))
        currentlyUnlocked = isUnlocked and isUnlocked() or false
        unlockBtnWidget.SetText(currentlyUnlocked and "Lock" or "Unlock")
    end

    return result
end