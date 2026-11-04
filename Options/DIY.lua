local _, addon = ...
local LibEvent = addon.LibEvent
local Options = addon.Options

if not Options then return end

local Preview = {
    frame = nil,
    lines = {},
    elements = {},
    dragging = nil,
    dragRows = nil,
    dragGeneration = nil,
    overButton = nil,
    overLine = nil,
    accumulator = 0,
}
Options.DIY = Preview

local PLACEHOLDER = {
    statusAFK = "AFK",
    statusDND = "DND",
    statusDC = "DC",
    friendIcon = addon.icons.friend,
    pvpIcon = addon.icons.pvp,
    roleIcon = addon.icons.DAMAGER,
    raidIcon = ICON_LIST and ICON_LIST[8] and ICON_LIST[8] .. "0|t" or "",
}
setmetatable(PLACEHOLDER, { __index = function(_, key) return key end })

local function Elements()
    return addon.db and addon.db.unit and addon.db.unit.player
        and addon.db.unit.player.elements or nil
end

local function PlayerConfig()
    return addon.db and addon.db.unit and addon.db.unit.player or nil
end

local function CreateDropLine(frame, lineNumber)
    local line = Preview.lines[lineNumber]
    if line then return line end

    line = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    line:SetSize(320, 24)
    line.line = lineNumber
    if type(line.SetBackdrop) == "function" then
        line:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        line:SetBackdropBorderColor(1, 0.9, 0.1)
    end
    line:SetAlpha(0)
    Preview.lines[lineNumber] = line
    return line
end

local function ClearHighlights()
    for _, line in ipairs(Preview.lines) do addon:SafeMethod(line, "SetAlpha", 0) end
    for _, element in pairs(Preview.elements) do
        if element.vbar then addon:SafeMethod(element.vbar, "Hide") end
    end
end

local function ResetDrag(element)
    element = element or Preview.dragging
    if element and addon:IsObjectAccessible(element) then addon:SafeMethod(element, "StopMovingOrSizing") end
    Preview.dragging = nil
    Preview.dragRows = nil
    Preview.dragGeneration = nil
    Preview.overButton = nil
    Preview.overLine = nil
    Preview.accumulator = 0
    if Preview.frame then addon:SafeMethod(Preview.frame, "SetScript", "OnUpdate", nil) end
    ClearHighlights()
end

local function RemoveElementFromRows(rows, elementKey)
    for _, row in ipairs(rows) do
        for index = #row, 1, -1 do
            if row[index] == elementKey then table.remove(row, index) end
        end
    end
end

local function CompactRows(rows)
    for index = #rows, 1, -1 do
        if type(rows[index]) ~= "table" or #rows[index] == 0 then table.remove(rows, index) end
    end
end

local function ProfileGeneration()
    return tonumber(addon.__RT_ProfileGeneration) or 0
end

local function CopyLayoutRows(rows)
    if type(rows) ~= "table" then return nil end
    local copy = {}
    for rowIndex, row in ipairs(rows) do
        if type(row) ~= "table" then return nil end
        local target = {}
        for column, elementKey in ipairs(row) do target[column] = elementKey end
        copy[rowIndex] = target
    end
    return copy
end

local function UpdateDragTargets(_, elapsed)
    if not Preview.dragging then return end
    Preview.accumulator = Preview.accumulator + (tonumber(elapsed) or 0)
    if Preview.accumulator < 0.10 then return end
    Preview.accumulator = 0

    Preview.overButton = nil
    Preview.overLine = nil
    ClearHighlights()

    for _, row in ipairs(Elements() or {}) do
        for _, elementKey in ipairs(row) do
            local element = Preview.elements[elementKey]
            if element and element ~= Preview.dragging and element:IsShown() and element:IsMouseOver() then
                Preview.overButton = element
                element.vbar:Show()
                return
            end
        end
    end

    for _, line in ipairs(Preview.lines) do
        if line:IsShown() and line:IsMouseOver() then
            Preview.overLine = line
            line:SetAlpha(1)
            return
        end
    end
end

local function FinishDrag(element)
    local rows = Elements()
    local generation = ProfileGeneration()
    if type(rows) ~= "table" or rows ~= Preview.dragRows
        or generation ~= Preview.dragGeneration or InCombatLockdown() then
        ResetDrag(element)
        if addon:IsObjectAccessible(Preview.frame) then Preview:Render() end
        return
    end

    local candidate = CopyLayoutRows(rows)
    if not candidate then ResetDrag(element); return end
    RemoveElementFromRows(candidate, element.key)

    local inserted = false
    if Preview.overButton then
        local targetKey = Preview.overButton.key
        for _, row in ipairs(candidate) do
            for index = 1, #row do
                if row[index] == targetKey then
                    table.insert(row, index, element.key)
                    inserted = true
                    break
                end
            end
            if inserted then break end
        end
    elseif Preview.overLine then
        local rowIndex = math.max(1, math.min(16, tonumber(Preview.overLine.line) or (#candidate + 1)))
        candidate[rowIndex] = candidate[rowIndex] or {}
        table.insert(candidate[rowIndex], element.key)
        inserted = true
    elseif #candidate < 16 then
        candidate[#candidate + 1] = { element.key }
        inserted = true
    else
        candidate[16] = candidate[16] or {}
        table.insert(candidate[16], element.key)
        inserted = true
    end

    CompactRows(candidate)
    if not inserted then
        ResetDrag(element)
        Preview:Render()
        return
    end

    local normalized, reason = addon:NormalizeProfile({
        unit = { player = { elements = candidate } },
    }, true, addon.db)
    if not normalized then
        addon:DoctorLog("profile", "diy-layout", reason)
        ResetDrag(element)
        Preview:Render()
        return
    end

    -- Validate ownership again immediately before publishing the replacement.
    if Elements() ~= rows or ProfileGeneration() ~= generation or InCombatLockdown() then
        ResetDrag(element)
        Preview:Render()
        return
    end

    local committed = normalized.unit.player.elements
    ResetDrag(element)
    Options:SetVariable("unit.player.elements", committed)
end

local function StartDrag(element)
    if not Preview.frame or InCombatLockdown() then return end
    local rows = Elements()
    if type(rows) ~= "table" then return end
    Preview.dragging = element
    Preview.dragRows = rows
    Preview.dragGeneration = ProfileGeneration()
    Preview.overButton = nil
    Preview.overLine = nil
    Preview.accumulator = 0

    local cursorX, cursorY = GetCursorPosition()
    local scale = addon:SafeMethod(UIParent, "GetEffectiveScale")
    if not addon:CanAccessAllValues(cursorX, cursorY, scale)
        or type(cursorX) ~= "number" or type(cursorY) ~= "number"
        or type(scale) ~= "number" or scale <= 0 then ResetDrag(element); return end
    addon:SafeMethod(element, "StartMoving")
    addon:SafeMethod(element, "ClearAllPoints")
    addon:SafeMethod(element, "SetPoint", "CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
    Preview.frame:SetScript("OnUpdate", UpdateDragTargets)
end

local function CreateElementButton(frame, elementKey)
    local element = Preview.elements[elementKey]
    if element then return element end

    element = CreateFrame("Button", nil, frame)
    element.key = elementKey
    element:SetSize(40, 20)
    element:SetMovable(true)
    element:RegisterForDrag("LeftButton")

    element.text = element:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    element.text:SetPoint("LEFT")
    element.vbar = element:CreateTexture(nil, "OVERLAY")
    element.vbar:SetPoint("TOPLEFT")
    element.vbar:SetPoint("BOTTOMLEFT", 2, 0)
    element.vbar:SetColorTexture(1, 0.8, 0)
    element.vbar:Hide()

    element:SetScript("OnDragStart", StartDrag)
    element:SetScript("OnDragStop", FinishDrag)
    element:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Options.L[self.key])
        GameTooltip:Show()
    end)
    element:SetScript("OnLeave", GameTooltip_Hide)

    Preview.elements[elementKey] = element
    return element
end

function Preview:Render()
    local frame = self.frame
    local rows = Elements()
    local playerConfig = PlayerConfig()
    if not frame or type(rows) ~= "table" or type(playerConfig) ~= "table" then return end

    local raw = addon:GetUnitInfo("player", rows) or {}
    addon:ApplyGeneralStyleToTooltip(frame)

    for _, element in pairs(self.elements) do element:Hide() end
    local maximumWidth = 0
    local visibleRows = 0

    for rowIndex, entries in ipairs(rows) do
        local line = CreateDropLine(frame, rowIndex)
        local lineWidth = 0
        if type(entries) == "table" then
            for _, elementKey in ipairs(entries) do
                local config = rows[elementKey]
                if type(config) == "table" and config.enable == true then
                    local element = CreateElementButton(frame, elementKey)
                    local value = raw[elementKey]
                    if value == nil then value = PLACEHOLDER[elementKey] end
                    if config.color and config.wildcard then
                        value = addon:FormatData(value, config, raw)
                    else
                        value = addon:SafeToString(value, "")
                    end

                    element.text:SetText(value)
                    element:SetWidth(math.max(4, element.text:GetWidth() + 4))
                    element:ClearAllPoints()
                    element:SetPoint("LEFT", line, "LEFT", lineWidth, 0)
                    element:Show()
                    lineWidth = lineWidth + element:GetWidth()
                end
            end
        end
        maximumWidth = math.max(maximumWidth, lineWidth + 16)
        visibleRows = rowIndex
    end

    local dropRow = math.min(16, visibleRows + 1)
    local totalWidth = math.max(180, maximumWidth)
    frame:SetWidth(totalWidth + 28)
    frame:SetHeight(dropRow * 24 + 40)

    for lineIndex = 1, dropRow do
        local line = CreateDropLine(frame, lineIndex)
        line:Show()
        line:SetWidth(totalWidth)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -(lineIndex * 25) + 13)
    end
    for lineIndex = dropRow + 1, #self.lines do self.lines[lineIndex]:Hide() end

    local factionIcon = addon:GetBigFactionIcon(frame, true)
    local factionBig = rows.factionBig
    if type(factionBig) == "table" and factionBig.enable == true
        and addon:IsObjectAccessible(factionIcon)
        and (raw.factionGroup == "Alliance" or raw.factionGroup == "Horde") then
        addon:SafeMethod(factionIcon, "SetTexture", "Interface\\Timer\\" .. raw.factionGroup .. "-Logo")
        addon:SafeMethod(factionIcon, "Show")
        frame:SetWidth(totalWidth + 48)
    elseif addon:IsObjectAccessible(factionIcon) then
        addon:SafeMethod(factionIcon, "Hide")
    end

    addon.ColorUnitBorder(frame, playerConfig, raw)
    addon.ColorUnitBackground(frame, playerConfig, raw)
end

local function CreatePreview()
    if Preview.frame ~= nil then
        if addon:IsObjectAccessible(Preview.frame) then return Preview.frame end
        return nil
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame.identity = "diy"
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetSize(360, 180)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetScript("OnShow", function() Preview:Render() end)
    frame:SetScript("OnHide", function() ResetDrag() end)
    frame:Hide()

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() frame:Hide() end)

    local tips = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLargeOutline")
    tips:SetPoint("BOTTOM", 0, 10)
    local font, size = tips:GetFont()
    tips:SetFont(font, size or 12, "NONE")
    tips:SetText(Options.L["<Drag element to customize the style>"])

    Preview.frame = frame
    addon:RegisterTooltipFrame(frame)
    return frame
end

function Options:OpenDIYEditor()
    local frame = CreatePreview()
    if frame then frame:Show(); Preview:Render() end
end

LibEvent:attachTrigger("tooltip:variables:loaded, tooltip:variable:changed", function()
    ResetDrag()
    local frame = Preview.frame
    if addon:IsObjectAccessible(frame) and addon:SafeMethod(frame, "IsShown") == true then Preview:Render() end
end)
