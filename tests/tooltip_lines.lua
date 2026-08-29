local triggerCallbacks = {}
local LibEvent = {}
function LibEvent:attachTrigger(names, callback)
    for name in tostring(names):gmatch("([^,%s]+)") do
        triggerCallbacks[name] = triggerCallbacks[name] or {}
        table.insert(triggerCallbacks[name], callback)
    end
end

LibStub = {
    GetLibrary = function(_, name)
        assert(name == "LibEvent.7000")
        return LibEvent
    end,
}

Enum = {
    TooltipDataLineType = {
        UnitName = 1,
        UnitNameAlias = 1,
        UnitLevel = 2,
        UnitFaction = 3,
    },
}

local postCalls = {}
TooltipDataProcessor = {}
function TooltipDataProcessor.AddLinePostCall(lineType, callback)
    assert(type(lineType) == "number")
    assert(type(callback) == "function")
    postCalls[lineType] = callback
end

local lineObjects = {}
local function Line(index, side)
    local key = tostring(index) .. side
    local line = lineObjects[key]
    if line then return line end
    line = { text = key }
    function line:SetText(value) self.text = value end
    lineObjects[key] = line
    return line
end

local addon = {}
function addon:CanAccessValue() return true end
function addon:IsObjectAccessible(value) return value ~= nil end
function addon:IsManagedTooltip(value) return value ~= nil end
function addon:GetLine(_, index)
    return Line(index, "L"), Line(index, "R")
end
function addon:SafeMethod(object, method, ...)
    return object[method](object, ...)
end
function addon:DoctorLog(...)
    error("unexpected DoctorLog: " .. table.concat({ ... }, ","))
end

assert(loadfile("Engine/TooltipLines.lua"))("RothTooltip", addon)
assert(postCalls[1] and postCalls[2] and postCalls[3])
local count = 0
for _ in pairs(postCalls) do count = count + 1 end
assert(count == 3, "duplicate numeric TooltipDataLineType registration")

local tooltip = {}
postCalls[Enum.TooltipDataLineType.UnitName](tooltip, { type = 1, lineIndex = 1 })
postCalls[Enum.TooltipDataLineType.UnitLevel](tooltip, { type = 2, lineIndex = 3 })
postCalls[Enum.TooltipDataLineType.UnitLevel](tooltip, { type = 2, lineIndex = 3 })

local indexes = addon:GetRenderedLineIndices(tooltip, Enum.TooltipDataLineType.UnitLevel)
assert(#indexes == 1 and indexes[1] == 3)
local left, right, index = addon:GetRenderedLine(tooltip, Enum.TooltipDataLineType.UnitLevel)
assert(left == Line(3, "L") and right == Line(3, "R") and index == 3)

local titleLeft, titleRight = addon:GetNpcTitle(tooltip)
assert(titleLeft == Line(2, "L") and titleRight == Line(2, "R"))
addon:ClearRenderedLine(tooltip, Enum.TooltipDataLineType.UnitLevel)
assert(Line(3, "L").text == nil and Line(3, "R").text == nil)

-- A new lineIndex 1 starts a fresh ProcessLines generation.
postCalls[Enum.TooltipDataLineType.UnitName](tooltip, { type = 1, lineIndex = 1 })
assert(addon:GetRenderedLineIndices(tooltip, Enum.TooltipDataLineType.UnitLevel) == nil)

-- A lower index also resets a generation when line 1 was not observable.
postCalls[Enum.TooltipDataLineType.UnitFaction](tooltip, { type = 3, lineIndex = 5 })
postCalls[Enum.TooltipDataLineType.UnitLevel](tooltip, { type = 2, lineIndex = 2 })
local resetIndexes = addon:GetRenderedLineIndices(tooltip, Enum.TooltipDataLineType.UnitLevel)
assert(#resetIndexes == 1 and resetIndexes[1] == 2)

for _, callback in ipairs(triggerCallbacks["tooltip:hide"] or {}) do
    callback(callback, tooltip)
end
assert(addon:GetRenderedLineIndices(tooltip, Enum.TooltipDataLineType.UnitLevel) == nil)

print("tooltip_lines: ok")
