-- Focused Retail 12.1 corrections layered over the legacy Core overrides.
-- Kept separate so the compatibility Core remains diff-stable and auditable.

local _, addon = ...

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function ReadField(tbl, key)
    if not CanAccess(tbl) or type(tbl) ~= "table" then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if not ok or not CanAccess(value) then return nil end
    return value
end

local function ReadNumber(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "number" then return value end
    return nil
end

local function Call4(fn, ...)
    if not CanAccess(fn) or type(fn) ~= "function" then return nil end
    if addon.CanAccessAllValues and not addon:CanAccessAllValues(...) then return nil end

    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    if not CanAccess(a) then a = nil end
    if not CanAccess(b) then b = nil end
    if not CanAccess(c) then c = nil end
    if not CanAccess(d) then d = nil end
    return a, b, c, d
end

local function ResolveDisplayedSpellID(tooltip)
    if not addon:IsObjectAccessible(tooltip) then return nil end

    local getDisplayedSpell = TooltipUtil and TooltipUtil.GetDisplayedSpell
    if type(getDisplayedSpell) == "function" then
        local _, spellID = Call4(getDisplayedSpell, tooltip)
        if type(spellID) == "number" and spellID > 0 then return spellID end
    end

    local getSpell = addon:SafeGet(tooltip, "GetSpell")
    if type(getSpell) == "function" then
        local _, second, third = Call4(getSpell, tooltip)
        if type(third) == "number" and third > 0 then return third end
        if type(second) == "number" and second > 0 then return second end
    end
    return nil
end

local BaseGetPrimaryTooltipContext = addon.GetPrimaryTooltipContext

function addon:GetPrimaryTooltipContext(tooltip, suppliedData)
    local context = BaseGetPrimaryTooltipContext(self, tooltip, suppliedData)
    if type(context) ~= "table" then return context end

    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then return context end

    local actionLike = context.type == dataTypes.Action
        or context.type == dataTypes.PetAction
        or context.type == dataTypes.Flyout
        or context.type == dataTypes.Macro

    if actionLike then
        local explicitSpellID = ReadNumber(suppliedData, "spellID") or ReadNumber(suppliedData, "spellId")
        local resolvedSpellID = explicitSpellID or ResolveDisplayedSpellID(tooltip)
        context.spellID = resolvedSpellID
        self:SetPrimaryTooltipContext(tooltip, context)
    end
    return context
end

-- Core's recursive version could add only one line per call. Ensure callers
-- requesting line N receive line N without unbounded recursion.
function addon:GetLine(tooltip, number)
    if not self:IsObjectAccessible(tooltip) or type(number) ~= "number" or number < 1 then return nil end

    local name = self:SafeMethod(tooltip, "GetName")
    local lineCount = self:SafeMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return nil end

    local added = 0
    while lineCount < number and added < 64 do
        self:SafeMethod(tooltip, "AddLine", " ")
        local nextCount = self:SafeMethod(tooltip, "NumLines")
        if type(nextCount) ~= "number" or nextCount <= lineCount then break end
        lineCount = nextCount
        added = added + 1
    end
    if lineCount < number then return nil end
    return _G[name .. "TextLeft" .. number], _G[name .. "TextRight" .. number]
end

function addon:GetUnitSpeed(unit)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return nil end
    if self.IsUnitIdentityRestricted and self:IsUnitIdentityRestricted(unit) then return nil end
    if self.AreUnitStatsRestricted and self:AreUnitStatsRestricted() then return nil end

    local currentSpeed, runSpeed = Call4(GetUnitSpeed, unit)
    local speed = type(currentSpeed) == "number" and currentSpeed or runSpeed
    if type(speed) ~= "number" then return nil end

    local baseSpeed = BASE_MOVEMENT_SPEED or 7
    if type(baseSpeed) ~= "number" or baseSpeed <= 0 then return nil end
    return speed / baseSpeed * 100 + 0.5
end

local function GetRosterNameAndZone(index)
    if type(index) ~= "number" or type(GetRaidRosterInfo) ~= "function" then return nil, nil end
    if not addon.CanAccessAllValues or addon:CanAccessAllValues(index) then
        local ok, name, _, _, _, _, _, zone = pcall(GetRaidRosterInfo, index)
        if not ok then return nil, nil end
        if not CanAccess(name) or type(name) ~= "string" then name = nil end
        if not CanAccess(zone) or type(zone) ~= "string" then zone = nil end
        return name, zone
    end
    return nil, nil
end

function addon:GetZone(unit, unitName, realm)
    if not CanAccess(unit) or not CanAccess(unitName) or not CanAccess(realm) then return nil end
    if type(unit) ~= "string" or type(unitName) ~= "string" or type(realm) ~= "string" then return nil end
    if self:SafeCallBoolean(IsInGroup) ~= true then return nil end

    local prefix, indexText = unit:match("^(raid)(%d+)$")
    if prefix == "raid" then
        local _, zone = GetRosterNameAndZone(tonumber(indexText))
        return zone
    end

    prefix, indexText = unit:match("^(party)(%d+)$")
    if prefix ~= "party" then return nil end

    local fullName = unitName .. "-" .. realm
    local count = Call4(GetNumGroupMembers)
    if type(count) ~= "number" or count < 1 then count = 5 end
    count = math.min(count, 40)

    for rosterIndex = 1, count do
        local name, zone = GetRosterNameAndZone(rosterIndex)
        if name == unitName or name == fullName then return zone end
    end
    return nil
end
