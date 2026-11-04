-- RothTooltip Engine: authoritative Retail 12.1 tooltip data boundary.
--
-- This file owns restriction predicates, sanitized tooltip context, safe
-- source-preserving refresh, owner-chain helpers and line access. Managed-frame lifecycle is owned by Engine/TooltipRegistry.lua.

local _, addon = ...

local function CanAccess(value)
    return addon:CanAccessValue(value)
end

local function CanAccessAll(...)
    return addon:CanAccessAllValues(...)
end

local function Call(fn, ...)
    return addon:SafeCall("Midnight", fn, ...)
end

local function ReadField(tbl, key)
    return addon:SafeGet(tbl, key)
end

local function ReadNumber(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return value end
end

local function ReadString(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "string" and value ~= "" then return value end
end

local function QuerySecretPredicate(fn, ...)
    -- RothTooltip targets Retail 12.1. Missing patch-critical predicates are a
    -- denied capability, not permission to probe the underlying API.
    if type(fn) ~= "function" or not CanAccessAll(...) then return true end
    local ok, result = pcall(fn, ...)
    if not ok or not CanAccess(result) then return true end
    return result ~= false
end

function addon:HasSecretRestrictions()
    return QuerySecretPredicate(C_Secrets and C_Secrets.HasSecretRestrictions)
end

function addon:AreAurasRestricted()
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldAurasBeSecret)
end

function addon:AreCooldownsRestricted()
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldCooldownsBeSecret)
end

function addon:IsSpellAuraRestricted(spellIdentifier)
    if not CanAccess(spellIdentifier) then return true end
    local valueType = type(spellIdentifier)
    if valueType ~= "number" and valueType ~= "string" then return true end
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret, spellIdentifier)
end

function addon:AreUnitStatsRestricted()
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitStatsBeSecret)
end

function addon:IsUnitIdentityRestricted(unit)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return true end
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret, unit)
end

function addon:IsUnitHealthRestricted(unit)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return true end
    if QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitHealthBeSecret, unit) then return true end
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret, unit)
end

function addon:CanCompareUnitTokens(unit1, unit2)
    if not CanAccessAll(unit1, unit2) then return false end
    if type(unit1) ~= "string" or type(unit2) ~= "string" then return false end

    local fn = C_Secrets and C_Secrets.CanCompareUnitTokens
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, unit1, unit2)
    return ok and CanAccess(result) and result == true
end

-- Never retain native TooltipData or a unit token between callbacks. Public
-- accessors return fresh, ordinary snapshots; missing/denied data has no fallback.
local function PositiveID(data, key)
    local value = ReadNumber(data, key)
    if value and value > 0 and value < math.huge and value == math.floor(value) then return value end
end

local function ItemLink(data)
    local link = ReadString(data, "hyperlink") or ReadString(data, "link")
    if link and (link:match("^item:%d+") or link:find("|Hitem:%d+")) then return link end
end

local function ReadItem(context, data)
    context.hyperlink = ItemLink(data)
    local guid = ReadString(data, "guid")
    if not context.hyperlink and guid and context.type == Enum.TooltipDataType.Item then
        context.hyperlink = Call(C_Item and C_Item.GetItemLinkByGUID, guid)
        if type(context.hyperlink) ~= "string" then context.hyperlink = nil end
    end
    context.itemID = PositiveID(data, "itemID")
    if context.hyperlink then
        context.itemID = Call(C_Item and C_Item.GetItemInfoInstant, context.hyperlink) or context.itemID
    end
    if type(context.itemID) ~= "number" then context.itemID = nil end
    if context.type == Enum.TooltipDataType.Item then context.itemID = context.itemID or context.id end
end

function addon:ResolveUnitToken(unit, guid)
    if not CanAccessAll(unit, guid) then return nil end
    if guid ~= nil and (type(guid) ~= "string" or guid == "") then return nil end
    if guid then unit = Call(UnitTokenFromGUID, guid) end
    if type(unit) ~= "string" or unit == "" or self:IsUnitIdentityRestricted(unit) then return nil end
    if guid and Call(UnitGUID, unit) ~= guid then return nil end
    return unit
end

local function ReadUnit(context, data)
    local guid = ReadField(data, "guid")
    local unit = ReadField(data, "unitToken") or ReadField(data, "unit")
    context.unitToken = addon:ResolveUnitToken(unit, guid)
    if not context.unitToken then return nil end
    context.guid = Call(UnitGUID, context.unitToken)
    if type(context.guid) ~= "string" or context.guid == "" then return nil end
    return context
end

local IDENTITY_FIELDS = { "type", "id", "guid", "unitToken", "unit", "hyperlink", "link", "spellID", "spellId", "itemID" }

function addon:GetPrimaryTooltipContext(tooltip, suppliedData)
    if not self:IsTooltipSafe(tooltip) or not CanAccess(suppliedData) then return nil end
    local data = suppliedData
    if data == nil then data = self:SafeMethod(tooltip, "GetPrimaryTooltipData") end
    if not self:CanAccessTable(data) then return nil end
    -- Access the identity fields before calling helpers which themselves might
    -- evaluate borrowed native fields. No TooltipUtil/GetUnit secret probing.
    for _, key in ipairs(IDENTITY_FIELDS) do
        if not CanAccess(data[key]) then return nil end
    end
    local context = { type = ReadNumber(data, "type"), id = PositiveID(data, "id") }
    local types = Enum.TooltipDataType
    if context.type == nil or context.type < 0 or context.type ~= math.floor(context.type) then return nil end
    if context.type == types.Unit then return ReadUnit(context, data) end
    if context.type == types.Item then
        ReadItem(context, data)
    elseif context.type == types.Spell or context.type == types.UnitAura then
        context.spellID = PositiveID(data, "spellID") or PositiveID(data, "spellId") or context.id
        if context.type == types.UnitAura and (self:AreAurasRestricted()
            or not context.spellID or self:IsSpellAuraRestricted(context.spellID)) then return nil end
    elseif context.type == types.Macro or context.type == types.Flyout or context.type == types.PetAction then
        ReadItem(context, data)
        if not context.itemID and not context.hyperlink then
            context.spellID = PositiveID(data, "spellID") or PositiveID(data, "spellId")
        end
    end
    return context
end

function addon:SafeGetSpellID(tooltip)
    local context = self:GetPrimaryTooltipContext(tooltip)
    return context and context.spellID
end

function addon:GetTooltipUnit(tooltip)
    local context = self:GetPrimaryTooltipContext(tooltip)
    return context and context.unitToken
end

local function GetTooltipOwner(tooltip)
    local owner = addon:SafeMethod(tooltip, "GetOwner")
    if addon:IsObjectAccessible(owner) then return owner end
end

local function WalkOwnerChain(owner, visitor)
    local current = owner
    for depth = 0, 15 do
        if not addon:IsObjectAccessible(current) then return nil end
        if visitor(current, depth) then return current end
        current = addon:SafeMethod(current, "GetParent")
        if current == nil then return nil end
    end
end

local function FrameName(frame)
    local name = addon:SafeMethod(frame, "GetName")
    if type(name) == "string" then return name end
end

local function FrameAttribute(frame, key)
    local value = addon:SafeMethod(frame, "GetAttribute", key)
    if CanAccess(value) then return value end
end

local function FrameUnit(frame)
    local unit = addon:SafeGet(frame, "unit")
    if type(unit) ~= "string" or unit == "" then unit = FrameAttribute(frame, "unit") end
    if type(unit) ~= "string" or unit == "" then return nil end
    return addon:ResolveUnitToken(unit)
end

function addon:GetMouseFocusUnit()
    local owner = GetTooltipOwner(GameTooltip)
    if not owner then return nil, nil, nil end

    local unitOwner, unit
    WalkOwnerChain(owner, function(frame)
        unit = FrameUnit(frame)
        if unit then unitOwner = frame return true end
        return false
    end)
    return unit, owner, unitOwner
end

function addon:IsActionBar(tooltip)
    local owner = GetTooltipOwner(tooltip)
    if not owner then return false end
    return WalkOwnerChain(owner, function(frame)
        local action = addon:SafeGet(frame, "action")
        if type(action) == "number" then return true end
        action = FrameAttribute(frame, "action")
        if type(action) == "number" then return true end
        local name = FrameName(frame)
        return type(name) == "string" and (
            name:find("ActionButton", 1, true)
            or name:find("MultiBar", 1, true)
            or name:find("PetActionButton", 1, true)
            or name:find("PossessButton", 1, true)
        ) ~= nil
    end) ~= nil
end

function addon:IsBag(tooltip)
    local owner = GetTooltipOwner(tooltip)
    if not owner then return false end
    return WalkOwnerChain(owner, function(frame)
        if type(addon:SafeGet(frame, "GetItemContextMatchResult")) == "function" then return true end
        local name = FrameName(frame)
        return type(name) == "string" and (
            name:find("ContainerFrame", 1, true) or name:find("BagItem", 1, true)
        ) ~= nil
    end) ~= nil
end

-- Only repeat a standard setter whose exact source is represented by our
-- ordinary snapshot. Bag, inventory, action and comparison getters stay native.
local RefreshSetters = {
    GetUnit = { method = "SetUnit", kind = "unit", field = "unitToken" },
    GetHyperlink = { method = "SetHyperlink", kind = "item", field = "hyperlink" },
    GetItemByID = { method = "SetItemByID", kind = "item", field = "itemID" },
    GetSpellByID = { method = "SetSpellByID", kind = "spell", field = "spellID" },
}
local refreshing = setmetatable({}, { __mode = "k" })

function addon:RefreshTooltipSafe(tooltip)
    if not self:IsManagedTooltip(tooltip) or refreshing[tooltip]
        or self:SafeMethod(tooltip, "IsShown") ~= true then return false end
    local context = self:GetPrimaryTooltipContext(tooltip)
    if not context then return false end
    local info = self:SafeMethod(tooltip, "GetPrimaryTooltipInfo")
    local getter = ReadString(info, "getterName")
    local spec = getter and RefreshSetters[getter]
    if not spec or not self:AllowTrigger(spec.kind, tooltip) then return false end
    local argument = context[spec.field]
    local setter = self:SafeGet(tooltip, spec.method)
    if argument == nil or type(setter) ~= "function" then return false end
    refreshing[tooltip] = true
    local ok, result = pcall(setter, tooltip, argument)
    refreshing[tooltip] = nil
    if not ok then self:DoctorLog("lua", "tooltip-refresh", result) end
    return ok and CanAccess(result) and result ~= false
end

function addon:RefreshManagedTooltipsMatching(matchFunc)
    local refreshed = 0
    self:ForEachVisibleManagedTooltip(function(tooltip)
        local context = self:GetPrimaryTooltipContext(tooltip)
        if context and (not matchFunc or matchFunc(tooltip, context))
            and self:RefreshTooltipSafe(tooltip) then refreshed = refreshed + 1 end
    end)
    return refreshed
end

function addon:FindLine(tooltip, keyword)
    if not self:IsTooltipSafe(tooltip) or not CanAccess(keyword) or type(keyword) ~= "string" then return nil end
    local name = self:SafeMethod(tooltip, "GetName")
    local lineCount = self:SafeMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return nil end

    for index = 2, lineCount do
        local line = _G[name .. "TextLeft" .. index]
        if self:IsObjectAccessible(line) then
            local text = self:SafeMethod(line, "GetText")
            if type(text) == "string" then
                local ok, found = pcall(string.find, text, keyword)
                if ok and found then return line, index, _G[name .. "TextRight" .. index] end
            end
        end
    end
end

function addon:HideLine(tooltip, keyword)
    local left, _, right = self:FindLine(tooltip, keyword)
    if left then self:SafeMethod(left, "SetText", nil) end
    if right then self:SafeMethod(right, "SetText", nil) end
end

function addon:GetLine(tooltip, number)
    if not self:IsTooltipSafe(tooltip) or type(number) ~= "number" or number ~= number or number < 1 or number > 128 or number ~= math.floor(number) then return nil end
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

function addon:FindLineByType(tooltip, lineType)
    if not self:IsTooltipSafe(tooltip) or type(lineType) ~= "number" then return nil end
    local data = self:SafeMethod(tooltip, "GetPrimaryTooltipData")
    local lines = ReadField(data, "lines")
    if not self:CanAccessTable(lines) then return nil end
    -- Native arrays are bounded defensively; line indexes remain callback-local.
    for index = 1, 128 do
        local line = ReadField(lines, index)
        if line == nil then break end
        if ReadNumber(line, "type") == lineType then
            local lineIndex = ReadNumber(line, "lineIndex")
            if lineIndex and lineIndex >= 1 and lineIndex <= 128 then
                local left, right = self:GetLine(tooltip, lineIndex)
                return left, right, lineIndex
            end
        end
    end
end
