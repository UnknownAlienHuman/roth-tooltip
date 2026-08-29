-- RothTooltip semantic rendered-line registry.
--
-- Blizzard assigns lineData.lineIndex before line post-calls. Capture only the
-- ordinary line type/index pair so feature modules can address native unit
-- lines without matching localized text or retaining raw TooltipDataLine data.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local LinesByTooltip = setmetatable({}, { __mode = "k" })

local function CanAccess(value)
    return addon:CanAccessValue(value)
end

local function ReadNumber(tbl, key)
    if not CanAccess(tbl) or type(tbl) ~= "table" then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if not ok or not CanAccess(value) or type(value) ~= "number" then return nil end
    return value
end

local function GetTooltipLines(tooltip, create)
    if not addon:IsObjectAccessible(tooltip) then return nil end
    local lines = LinesByTooltip[tooltip]
    if not lines and create == true then
        lines = { lastIndex = 0 }
        LinesByTooltip[tooltip] = lines
    end
    return lines
end

local function TrackRenderedLine(tooltip, lineData)
    if not addon:IsManagedTooltip(tooltip) then return end

    local lineType = ReadNumber(lineData, "type")
    local lineIndex = ReadNumber(lineData, "lineIndex")
    if lineType == nil or lineIndex == nil or lineIndex < 1 then return end

    local lines = GetTooltipLines(tooltip, true)
    -- The first rendered line marks a new ProcessLines generation. This reset
    -- does not depend on OnTooltipCleared hooks, which may be temporarily
    -- forbidden during restriction transitions.
    if lineIndex == 1 or lineIndex < (lines.lastIndex or 0) then
        lines = { lastIndex = 0 }
        LinesByTooltip[tooltip] = lines
    end
    lines.lastIndex = math.max(lines.lastIndex or 0, lineIndex)

    local indexes = lines[lineType]
    if not indexes then indexes = {}; lines[lineType] = indexes end
    if indexes[#indexes] ~= lineIndex then indexes[#indexes + 1] = lineIndex end
end

function addon:GetRenderedLineIndices(tooltip, lineType)
    if type(lineType) ~= "number" then return nil end
    local lines = GetTooltipLines(tooltip, false)
    return lines and lines[lineType] or nil
end

function addon:GetRenderedLine(tooltip, lineType, occurrence)
    local indexes = self:GetRenderedLineIndices(tooltip, lineType)
    local index = type(indexes) == "table" and indexes[tonumber(occurrence) or 1] or nil
    if type(index) ~= "number" then return nil end
    local left, right = self:GetLine(tooltip, index)
    return left, right, index
end

function addon:ClearRenderedLine(tooltip, lineType, occurrence)
    local left, right = self:GetRenderedLine(tooltip, lineType, occurrence)
    if self:IsObjectAccessible(left) then self:SafeMethod(left, "SetText", nil) end
    if self:IsObjectAccessible(right) then self:SafeMethod(right, "SetText", nil) end
end

function addon:ClearRenderedLineType(tooltip, lineType)
    local indexes = self:GetRenderedLineIndices(tooltip, lineType)
    if type(indexes) ~= "table" then return end
    for _, index in ipairs(indexes) do
        local left, right = self:GetLine(tooltip, index)
        if self:IsObjectAccessible(left) then self:SafeMethod(left, "SetText", nil) end
        if self:IsObjectAccessible(right) then self:SafeMethod(right, "SetText", nil) end
    end
end

local function ClearTooltipLines(_, tooltip)
    if CanAccess(tooltip) and tooltip ~= nil then LinesByTooltip[tooltip] = nil end
end

local processor = TooltipDataProcessor
local addLinePostCall = processor and processor.AddLinePostCall
local lineTypes = Enum and Enum.TooltipDataLineType
if type(addLinePostCall) == "function" and type(lineTypes) == "table" then
    for _, lineType in pairs(lineTypes) do
        if type(lineType) == "number" then pcall(addLinePostCall, lineType, TrackRenderedLine) end
    end
elseif addon.DoctorLog then
    addon:DoctorLog("api", "TooltipLines", "TooltipDataProcessor.AddLinePostCall unavailable", nil)
end

LibEvent:attachTrigger("tooltip:cleared, tooltip:hide, tooltip:unregister", ClearTooltipLines)
