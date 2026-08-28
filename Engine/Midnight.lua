-- RothTooltip Engine: Retail 12.1 runtime hardening
--
-- This file is intentionally loaded immediately after Core.lua. Core still
-- contains compatibility code for earlier Midnight builds; the functions
-- below replace its public access/context helpers with the 12.1 contract:
-- gate first with canaccessvalue, keep only ordinary primitives, and fail
-- closed instead of probing inaccessible values.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local CanAccessValueAPI = type(canaccessvalue) == "function" and canaccessvalue or nil
local CanAccessAllValuesAPI = type(canaccessallvalues) == "function" and canaccessallvalues or nil
local IsSecretValueAPI = type(issecretvalue) == "function" and issecretvalue or nil

local function CanAccessValue(value)
    if CanAccessValueAPI then
        return CanAccessValueAPI(value) == true
    end
    if IsSecretValueAPI then
        return IsSecretValueAPI(value) ~= true
    end
    return true
end

local function CanAccessAllValues(...)
    if CanAccessAllValuesAPI then
        return CanAccessAllValuesAPI(...) == true
    end
    for index = 1, select("#", ...) do
        if not CanAccessValue(select(index, ...)) then
            return false
        end
    end
    return true
end

-- Core.lua defines an older comparison-probe fallback. Reassert the 12.1
-- public helpers after Core has loaded.
function addon:CanAccessValue(value)
    return CanAccessValue(value)
end

function addon:CanAccessAllValues(...)
    return CanAccessAllValues(...)
end

function addon:IsSecret(value)
    return not CanAccessValue(value)
end

function addon:SafeBoolean(value)
    if not CanAccessValue(value) or value == nil then return nil end
    if type(value) == "boolean" then return value end
    return value and true or false
end

function addon:SafeCallBoolean(fn, ...)
    if not CanAccessValue(fn) or type(fn) ~= "function" then return nil end
    if not CanAccessAllValues(...) then return nil end

    local ok, value = pcall(fn, ...)
    if not ok or not CanAccessValue(value) then return nil end
    return self:SafeBoolean(value)
end

function addon:SafeToString(value, placeholder)
    if not CanAccessValue(value) then return placeholder or "??" end
    if value == nil then return placeholder end
    if type(value) == "string" then return value end

    local ok, text = pcall(tostring, value)
    if ok and CanAccessValue(text) and type(text) == "string" then
        return text
    end
    return placeholder or "??"
end

local function ReadObjectMember(object, key)
    if not CanAccessValue(object) or object == nil then return nil end
    if not CanAccessValue(key) or key == nil then return nil end

    local ok, value = pcall(function()
        return object[key]
    end)
    if not ok or not CanAccessValue(value) then return nil end
    return value
end

local function CallObjectMethod(object, method, ...)
    if not CanAccessValue(object) or object == nil then return nil end
    local fn = ReadObjectMember(object, method)
    if type(fn) ~= "function" or not CanAccessAllValues(...) then return nil end

    local ok, a, b, c, d = pcall(fn, object, ...)
    if not ok then return nil end
    if not CanAccessValue(a) then a = nil end
    if not CanAccessValue(b) then b = nil end
    if not CanAccessValue(c) then c = nil end
    if not CanAccessValue(d) then d = nil end
    return a, b, c, d
end

function addon:IsObjectAccessible(object)
    if not CanAccessValue(object) or object == nil then return false end

    local canAccess = ReadObjectMember(object, "CanBeAccessedInContext")
    if type(canAccess) == "function" then
        local ok, result = pcall(canAccess, object)
        if not ok or not CanAccessValue(result) or result ~= true then
            return false
        end
    end

    local isForbidden = ReadObjectMember(object, "IsForbidden")
    if type(isForbidden) == "function" then
        local ok, result = pcall(isForbidden, object)
        if not ok or not CanAccessValue(result) or result == true then
            return false
        end
    end

    return true
end

local function QuerySecretPredicate(fn, ...)
    if type(fn) ~= "function" then return false end
    if not CanAccessAllValues(...) then return true end

    local ok, result = pcall(fn, ...)
    if not ok or not CanAccessValue(result) then
        return true
    end
    return result == true
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

function addon:AreUnitStatsRestricted()
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitStatsBeSecret)
end

function addon:IsUnitIdentityRestricted(unit)
    if not CanAccessValue(unit) or type(unit) ~= "string" or unit == "" then
        return true
    end
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret, unit)
end

function addon:IsUnitHealthRestricted(unit)
    if not CanAccessValue(unit) or type(unit) ~= "string" or unit == "" then
        return true
    end
    if QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitHealthBeSecret, unit) then
        return true
    end
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret, unit)
end

function addon:CanCompareUnitTokens(unit1, unit2)
    if not CanAccessAllValues(unit1, unit2) then return false end
    if type(unit1) ~= "string" or type(unit2) ~= "string" then return false end

    local fn = C_Secrets and C_Secrets.CanCompareUnitTokens
    if type(fn) ~= "function" then return true end

    local ok, result = pcall(fn, unit1, unit2)
    return ok and CanAccessValue(result) and result == true
end

local function ReadField(tbl, key)
    if not CanAccessValue(tbl) or type(tbl) ~= "table" then return nil end
    local ok, value = pcall(function()
        return tbl[key]
    end)
    if not ok or not CanAccessValue(value) then return nil end
    return value
end

local function ReadNumber(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "number" then return value end
    return nil
end

local function ReadString(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function NormalizeLink(value)
    if not CanAccessValue(value) or type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

local function GetTooltipPrimaryData(tooltip, suppliedData)
    if not CanAccessValue(suppliedData) then return nil end
    if type(suppliedData) == "table" then return suppliedData end
    if not addon:IsObjectAccessible(tooltip) then return nil end

    local fn = ReadObjectMember(tooltip, "GetPrimaryTooltipData")
    if type(fn) ~= "function" then return nil end

    local ok, data = pcall(fn, tooltip)
    if not ok or not CanAccessValue(data) or type(data) ~= "table" then
        return nil
    end
    return data
end

local function TooltipIsType(tooltip, tooltipType)
    if type(tooltipType) ~= "number" or not addon:IsObjectAccessible(tooltip) then
        return false
    end
    local fn = ReadObjectMember(tooltip, "IsTooltipType")
    if type(fn) ~= "function" then return false end

    local ok, result = pcall(fn, tooltip, tooltipType)
    return ok and CanAccessValue(result) and result == true
end

local function TooltipQuery(fn, tooltip)
    if type(fn) ~= "function" or not addon:IsObjectAccessible(tooltip) then
        return nil, nil, nil, nil
    end

    local ok, a, b, c, d = pcall(fn, tooltip)
    if not ok then return nil, nil, nil, nil end
    if not CanAccessValue(a) then a = nil end
    if not CanAccessValue(b) then b = nil end
    if not CanAccessValue(c) then c = nil end
    if not CanAccessValue(d) then d = nil end
    return a, b, c, d
end

local function ResolveItemID(itemInfo)
    if not CanAccessValue(itemInfo) or itemInfo == nil then return nil end
    if type(itemInfo) ~= "string" and type(itemInfo) ~= "number" then return nil end
    if not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then return nil end

    local ok, itemID = pcall(C_Item.GetItemInfoInstant, itemInfo)
    if ok and CanAccessValue(itemID) and type(itemID) == "number" then
        return itemID
    end
    return nil
end

local ContextFields = {
    type = "number",
    id = "number",
    itemID = "number",
    spellID = "number",
    dataInstanceID = "number",
    hyperlink = "string",
    guid = "string",
    unitToken = "string",
}

local function CopyOrdinaryContext(context)
    if not CanAccessValue(context) or type(context) ~= "table" then return nil end

    local copy = {}
    for key, expectedType in pairs(ContextFields) do
        local value = ReadField(context, key)
        if type(value) == expectedType and (expectedType ~= "string" or value ~= "") then
            copy[key] = value
        end
    end

    if not next(copy) then return nil end
    return copy
end

addon.__RT_ContextByTooltip = addon.__RT_ContextByTooltip or setmetatable({}, { __mode = "k" })
local ContextByTooltip = addon.__RT_ContextByTooltip

function addon:GetCachedTooltipContext(tooltip)
    if not self:IsObjectAccessible(tooltip) then return nil end
    return ContextByTooltip[tooltip]
end

function addon:SetPrimaryTooltipContext(tooltip, context)
    if not self:IsObjectAccessible(tooltip) then return end
    ContextByTooltip[tooltip] = CopyOrdinaryContext(context)
end

function addon:ResolveUnitToken(unit, guid)
    if CanAccessValue(guid) and type(guid) == "string" and guid ~= "" and type(UnitTokenFromGUID) == "function" then
        local ok, token = pcall(UnitTokenFromGUID, guid)
        if ok and CanAccessValue(token) and type(token) == "string" and token ~= ""
            and not self:IsUnitIdentityRestricted(token) then
            return token
        end
    end

    if not CanAccessValue(unit) or type(unit) ~= "string" or unit == "" then
        return nil
    end
    if self:IsUnitIdentityRestricted(unit) then
        return nil
    end
    return unit
end

function addon:GetPrimaryTooltipContext(tooltip, suppliedData)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if not CanAccessValue(suppliedData) then return nil end

    if suppliedData == nil then
        local cached = ContextByTooltip[tooltip]
        if cached then return cached end
    end

    local tooltipData = GetTooltipPrimaryData(tooltip, suppliedData)
    local dataTypes = Enum and Enum.TooltipDataType or nil
    local itemType = dataTypes and dataTypes.Item or nil
    local spellType = dataTypes and dataTypes.Spell or nil
    local unitType = dataTypes and dataTypes.Unit or nil
    local auraType = dataTypes and dataTypes.UnitAura or nil
    local actionType = dataTypes and dataTypes.Action or nil
    local petActionType = dataTypes and dataTypes.PetAction or nil
    local flyoutType = dataTypes and dataTypes.Flyout or nil
    local macroType = dataTypes and dataTypes.Macro or nil

    local context = {}
    context.type = ReadNumber(tooltipData, "type")
    context.dataInstanceID = ReadNumber(tooltipData, "dataInstanceID")
    context.id = ReadNumber(tooltipData, "id")
    context.guid = ReadString(tooltipData, "guid")

    context.hyperlink = NormalizeLink(ReadField(tooltipData, "hyperlink"))
    if not context.hyperlink then
        context.hyperlink = NormalizeLink(ReadField(tooltipData, "link"))
    end

    context.itemID = ReadNumber(tooltipData, "itemID")
    context.spellID = ReadNumber(tooltipData, "spellID")
    if not context.spellID then
        context.spellID = ReadNumber(tooltipData, "spellId")
    end

    local suppliedUnit = ReadString(tooltipData, "unitToken")
    if not suppliedUnit then
        suppliedUnit = ReadString(tooltipData, "unit")
    end

    local isItem = context.type == itemType or TooltipIsType(tooltip, itemType)
    if isItem then
        local _, hyperlink, itemID = TooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedItem, tooltip)
        context.hyperlink = NormalizeLink(hyperlink) or context.hyperlink
        if type(itemID) == "number" then context.itemID = itemID end
    end

    local isSpell = context.type == spellType or TooltipIsType(tooltip, spellType)
    if isSpell then
        local _, spellID = TooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedSpell, tooltip)
        if type(spellID) == "number" then context.spellID = spellID end
    end

    local isUnit = context.type == unitType or TooltipIsType(tooltip, unitType)
    if isUnit then
        local _, displayedUnit, displayedGuid = TooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedUnit, tooltip)
        if type(displayedGuid) == "string" and displayedGuid ~= "" then
            context.guid = displayedGuid
        end
        if type(displayedUnit) == "string" and displayedUnit ~= "" then
            suppliedUnit = displayedUnit
        end
    end

    if not context.itemID and context.type == itemType and type(context.id) == "number" then
        context.itemID = context.id
    end
    if not context.itemID and context.hyperlink then
        context.itemID = ResolveItemID(context.hyperlink)
    end

    local useDataIDAsSpellID = context.type == spellType
        or context.type == auraType
        or context.type == actionType
        or context.type == petActionType
        or context.type == flyoutType
        or context.type == macroType

    if not context.spellID and useDataIDAsSpellID and type(context.id) == "number" then
        context.spellID = context.id
    end

    context.unitToken = self:ResolveUnitToken(suppliedUnit, context.guid)

    if not tooltipData then
        local getItem = ReadObjectMember(tooltip, "GetItem")
        if type(getItem) == "function" and not context.hyperlink then
            local ok, _, link = pcall(getItem, tooltip)
            if ok and CanAccessValue(link) then
                context.hyperlink = NormalizeLink(link)
            end
        end

        if not context.itemID and context.hyperlink then
            context.itemID = ResolveItemID(context.hyperlink)
        end

        if not context.spellID then
            local _, spellID, maybeSpellID = self:SafeGetSpell(tooltip)
            local resolvedSpellID = maybeSpellID or spellID
            if type(resolvedSpellID) == "number" then
                context.spellID = resolvedSpellID
                context.type = context.type or spellType
            end
        end

        if not context.unitToken then
            local getUnit = ReadObjectMember(tooltip, "GetUnit")
            if type(getUnit) == "function" then
                local ok, _, unitToken = pcall(getUnit, tooltip)
                if ok and CanAccessValue(unitToken) then
                    context.unitToken = self:ResolveUnitToken(unitToken, context.guid)
                end
            end
        end
    end

    if not context.type then
        if context.itemID or context.hyperlink then
            context.type = itemType
        elseif context.unitToken or context.guid then
            context.type = unitType
        elseif context.spellID then
            context.type = spellType
        end
    end

    if not context.id then
        context.id = context.itemID or context.spellID
    end

    local clean = CopyOrdinaryContext(context)
    if clean then
        ContextByTooltip[tooltip] = clean
    end
    return clean
end

function addon:SafeGetSpell(tooltip)
    if not self:IsObjectAccessible(tooltip) then return nil end
    local fn = ReadObjectMember(tooltip, "GetSpell")
    if type(fn) ~= "function" then return nil end

    local ok, a, b, c = pcall(fn, tooltip)
    if not ok then return nil end
    if not CanAccessValue(a) then a = nil end
    if not CanAccessValue(b) then b = nil end
    if not CanAccessValue(c) then c = nil end
    return a, b, c
end

function addon:SafeGetSpellID(tooltip)
    local context = self:GetPrimaryTooltipContext(tooltip)
    local spellID = context and context.spellID or nil
    if type(spellID) == "number" then return spellID end

    local _, second, third = self:SafeGetSpell(tooltip)
    if type(third) == "number" then return third end
    if type(second) == "number" then return second end
    return nil
end

function addon:GetTooltipUnit(tooltip)
    if not self:IsObjectAccessible(tooltip) then return nil end

    local context = self:GetPrimaryTooltipContext(tooltip)
    if context and type(context.unitToken) == "string" then
        return context.unitToken
    end

    local fn = ReadObjectMember(tooltip, "GetUnit")
    if type(fn) ~= "function" then return nil end
    local ok, _, unit = pcall(fn, tooltip)
    if not ok or not CanAccessValue(unit) then return nil end
    return self:ResolveUnitToken(unit, context and context.guid or nil)
end

local function GetTooltipOwner(tooltip)
    if not addon:IsObjectAccessible(tooltip) then return nil end
    local owner = CallObjectMethod(tooltip, "GetOwner")
    if owner and addon:IsObjectAccessible(owner) then return owner end
    return nil
end

local function WalkOwnerChain(owner, visitor)
    local current = owner
    local depth = 0
    while current and depth < 16 do
        if not addon:IsObjectAccessible(current) then return nil end
        if visitor(current, depth) then return current end
        current = CallObjectMethod(current, "GetParent")
        depth = depth + 1
    end
    return nil
end

local function FrameName(frame)
    local name = CallObjectMethod(frame, "GetName")
    if type(name) == "string" then return name end
    return nil
end

local function FrameAttribute(frame, key)
    local value = CallObjectMethod(frame, "GetAttribute", key)
    if CanAccessValue(value) then return value end
    return nil
end

local function FrameUnit(frame)
    local unit = ReadObjectMember(frame, "unit")
    if type(unit) ~= "string" or unit == "" then
        unit = FrameAttribute(frame, "unit")
    end
    if type(unit) ~= "string" or unit == "" then return nil end
    return addon:ResolveUnitToken(unit)
end

function addon:FindMouseFocus(predicate)
    local owner = GetTooltipOwner(GameTooltip)
    if not owner then return nil end

    return WalkOwnerChain(owner, function(frame, depth)
        if type(predicate) ~= "function" then return depth == 0 end
        local ok, result = pcall(predicate, frame, depth + 1)
        return ok and CanAccessValue(result) and result == true
    end)
end

function addon:GetMouseFocus()
    return self:FindMouseFocus()
end

function addon:GetMouseFocusUnit()
    local owner = GetTooltipOwner(GameTooltip)
    if not owner then return nil, nil, nil end

    local unitOwner
    local unit = nil
    WalkOwnerChain(owner, function(frame)
        unit = FrameUnit(frame)
        if unit then
            unitOwner = frame
            return true
        end
        return false
    end)
    return unit, owner, unitOwner
end

function addon:IsActionBar(tooltip)
    local owner = GetTooltipOwner(tooltip)
    if not owner then return false end

    return WalkOwnerChain(owner, function(frame)
        local action = ReadObjectMember(frame, "action")
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
        if type(ReadObjectMember(frame, "GetItemContextMatchResult")) == "function" then
            return true
        end
        local name = FrameName(frame)
        return type(name) == "string" and (
            name:find("ContainerFrame", 1, true)
            or name:find("BagItem", 1, true)
        ) ~= nil
    end) ~= nil
end

function addon:RegisterTooltipFrame(tooltip)
    if not self:IsObjectAccessible(tooltip) then return false end
    if self.tooltipSet and self.tooltipSet[tooltip] then return true end

    self.tooltips = self.tooltips or {}
    self.tooltipSet = self.tooltipSet or {}
    self.tooltips[#self.tooltips + 1] = tooltip
    self.tooltipSet[tooltip] = true
    LibEvent:trigger("tooltip:init", tooltip)
    return true
end

function addon:ForEachVisibleManagedTooltip(callback)
    if type(callback) ~= "function" or type(self.tooltips) ~= "table" then return 0 end

    local seen = {}
    local count = 0
    for _, tooltip in pairs(self.tooltips) do
        if tooltip and not seen[tooltip] and self:IsObjectAccessible(tooltip) then
            local shown = CallObjectMethod(tooltip, "IsShown")
            if shown == true then
                seen[tooltip] = true
                count = count + 1
                callback(tooltip, count)
            end
        end
    end
    return count
end

function addon:RefreshTooltipSafe(tooltip, reason)
    if not self:IsObjectAccessible(tooltip) then return false end
    if CallObjectMethod(tooltip, "IsShown") ~= true then return false end

    local context = self:GetPrimaryTooltipContext(tooltip)
    if not context then return false end

    local unit = context.unitToken
    if type(unit) == "string" and not self:IsUnitIdentityRestricted(unit) then
        local setUnit = ReadObjectMember(tooltip, "SetUnit")
        if type(setUnit) == "function" then
            local ok, result = pcall(setUnit, tooltip, unit)
            if ok and CanAccessValue(result) and result ~= false then return true end
        end
    end

    local hyperlink = context.hyperlink
    if type(hyperlink) == "string" then
        local setHyperlink = ReadObjectMember(tooltip, "SetHyperlink")
        if type(setHyperlink) == "function" then
            local ok, result = pcall(setHyperlink, tooltip, hyperlink)
            if ok and CanAccessValue(result) and result ~= false then return true end
        end
    end

    local spellID = context.spellID
    if type(spellID) == "number" then
        local setSpellByID = ReadObjectMember(tooltip, "SetSpellByID")
        if type(setSpellByID) == "function" then
            local ok, result = pcall(setSpellByID, tooltip, spellID)
            if ok and CanAccessValue(result) and result ~= false then return true end
        end
    end

    -- RebuildFromTooltipInfo can replay restricted raw payload. Retail 12.1
    -- refreshes only from an ordinary unit token, hyperlink, or spell ID.
    return false
end

function addon:RefreshManagedTooltipsMatching(matchFunc, reason)
    local refreshed = 0
    self:ForEachVisibleManagedTooltip(function(tooltip)
        local context = self:GetPrimaryTooltipContext(tooltip)
        local matches = true
        if type(matchFunc) == "function" then
            local ok, result = pcall(matchFunc, tooltip, context)
            matches = ok and CanAccessValue(result) and result == true
        end
        if matches and self:RefreshTooltipSafe(tooltip, reason) then
            refreshed = refreshed + 1
        end
    end)
    return refreshed
end

function addon:FindLine(tooltip, keyword)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if not CanAccessValue(keyword) or type(keyword) ~= "string" then return nil end

    local name = CallObjectMethod(tooltip, "GetName")
    local lineCount = CallObjectMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return nil end

    for index = 2, lineCount do
        local line = _G[name .. "TextLeft" .. index]
        if line and self:IsObjectAccessible(line) then
            local text = CallObjectMethod(line, "GetText")
            if CanAccessValue(text) and type(text) == "string" then
                local ok, found = pcall(string.find, text, keyword)
                if ok and found then
                    return line, index, _G[name .. "TextRight" .. index]
                end
            end
        end
    end
    return nil
end

function addon:HideLine(tooltip, keyword)
    local line = self:FindLine(tooltip, keyword)
    if line and self:IsObjectAccessible(line) then
        CallObjectMethod(line, "SetText", nil)
    end
end

function addon:GetLine(tooltip, number)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if type(number) ~= "number" then return nil end

    local name = CallObjectMethod(tooltip, "GetName")
    local lineCount = CallObjectMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return nil end

    if number > lineCount then
        CallObjectMethod(tooltip, "AddLine", " ")
        lineCount = CallObjectMethod(tooltip, "NumLines")
        if type(lineCount) ~= "number" or number > lineCount then return nil end
    end
    return _G[name .. "TextLeft" .. number], _G[name .. "TextRight" .. number]
end

local function SafeValues(fn, ...)
    if not CanAccessValue(fn) or type(fn) ~= "function" then return nil, nil, nil, nil end
    if not CanAccessAllValues(...) then return nil, nil, nil, nil end

    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil, nil, nil, nil end
    if not CanAccessValue(a) then a = nil end
    if not CanAccessValue(b) then b = nil end
    if not CanAccessValue(c) then c = nil end
    if not CanAccessValue(d) then d = nil end
    return a, b, c, d
end

function addon:GetQuestBossIcon(unit)
    if self:SafeCallBoolean(UnitIsQuestBoss, unit) then return self.icons.questboss end
end

function addon:GetPVPIcon(unit)
    if self:SafeCallBoolean(UnitIsPVPFreeForAll, unit) then return self.icons.pvp end
end

function addon:GetRoleIcon(unit)
    local role = SafeValues(UnitGroupRolesAssigned, unit)
    if type(role) == "string" and role ~= "NONE" then
        return self.icons[string.upper(role)]
    end
end

function addon:GetFactionIcon(factionGroup)
    if type(factionGroup) ~= "string" then return nil end
    return self.icons[factionGroup]
end

function addon:GetRaidIcon(unit)
    local index = SafeValues(GetRaidTargetIndex, unit)
    if type(index) ~= "number" then return nil end
    local icon = ICON_LIST and ICON_LIST[index]
    if type(icon) == "string" then return icon .. "0|t" end
    return nil
end

function addon:GetClassIcon(class)
    if not CanAccessValue(class) or type(class) ~= "string" then return nil end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[string.upper(class)]
    if type(coords) ~= "table" then return nil end
    local x1, x2, y1, y2 = unpack(coords)
    if type(x1) ~= "number" or type(x2) ~= "number" or type(y1) ~= "number" or type(y2) ~= "number" then
        return nil
    end
    return string.format(self.icons.class, x1 * 256, x2 * 256, y1 * 256, y2 * 256)
end

function addon:GetFriendIcon(unit)
    if self:IsUnitIdentityRestricted(unit) then return nil end
    if not self:SafeCallBoolean(UnitIsPlayer, unit) then return nil end

    local guid = SafeValues(UnitGUID, unit)
    if type(guid) ~= "string" or guid == "" then return nil end

    if self:SafeCallBoolean(C_FriendList and C_FriendList.IsFriend, guid) then
        return self.icons.friend
    end

    local playerGUID = SafeValues(UnitGUID, "player")
    if type(playerGUID) ~= "string" or guid == playerGUID then return nil end

    local info = SafeValues(C_BattleNet and C_BattleNet.GetAccountInfoByGUID, guid)
    if type(info) == "table" and self:SafeBoolean(ReadField(info, "isFriend")) then
        return self.icons.bnetfriend
    end
    return nil
end

function addon:GetUnitSpeed(unit)
    if self:IsUnitIdentityRestricted(unit) or self:AreUnitStatsRestricted() then return nil end

    local _, speed, flightSpeed, swimSpeed = SafeValues(GetUnitSpeed, unit)
    if type(speed) ~= "number" or speed == 0 then return nil end
    if type(flightSpeed) ~= "number" then flightSpeed = speed end
    if type(swimSpeed) ~= "number" then swimSpeed = speed end

    local base = BASE_MOVEMENT_SPEED or 7
    speed = speed / base * 100
    flightSpeed = flightSpeed / base * 100
    swimSpeed = swimSpeed / base * 100

    if self:SafeCallBoolean(UnitIsOtherPlayersPet, unit) then
        -- Keep ordinary run speed.
    elseif self:SafeCallBoolean(IsSwimming, unit) then
        speed = swimSpeed
    elseif self:SafeCallBoolean(IsFlying, unit) then
        speed = flightSpeed
    end
    return speed + 0.5
end

function addon:GetTitle(name, pvpName)
    if type(name) ~= "string" or name == "" then return nil end
    if type(pvpName) ~= "string" or pvpName == "" or name == pvpName then return nil end

    local first, last = string.find(pvpName, name, 1, true)
    if not first then return nil end

    local title = string.sub(pvpName, 1, first - 1) .. string.sub(pvpName, last + 1)
    title = string.gsub(title, ",", "")
    title = string.gsub(title, "，", "")
    title = strtrim(title)
    if title == "" then return nil end
    return title, first ~= 1
end

function addon:GetZone(unit, unitName, realm)
    if type(unit) ~= "string" or type(unitName) ~= "string" or type(realm) ~= "string" then return nil end
    if not self:SafeCallBoolean(IsInGroup) then return nil end

    local prefix, index = string.match(unit, "(.-)(%d+)")
    if index and prefix == "raid" then
        local zone = select(7, SafeValues(GetRaidRosterInfo, tonumber(index)))
        if type(zone) == "string" then return zone end
        return nil
    end

    if index and prefix == "party" then
        local fullName = unitName .. "-" .. realm
        for rosterIndex = 1, 5 do
            local name, _, _, _, _, _, zone = GetRaidRosterInfo(rosterIndex)
            if CanAccessAllValues(name, zone) and type(name) == "string" and type(zone) == "string" then
                if name == unitName or name == fullName then return zone end
            end
        end
    end
    return nil
end

function addon:GetUnitInfo(unit)
    if not CanAccessValue(unit) or type(unit) ~= "string" or unit == "" then return nil end
    if self:IsUnitIdentityRestricted(unit) then return nil end

    local name, realm = SafeValues(UnitName, unit)
    local pvpName = SafeValues(UnitPVPName, unit)
    local gender = SafeValues(UnitSex, unit)
    local level = SafeValues(UnitLevel, unit)
    local effectiveLevel = SafeValues(UnitEffectiveLevel, unit)
    local raceName, race = SafeValues(UnitRace, unit)
    local className, class = SafeValues(UnitClass, unit)
    local factionGroup, factionName = SafeValues(UnitFactionGroup, unit)
    local reaction = SafeValues(UnitReaction, unit, "player")
    local guildName, guildRank, guildIndex, guildRealm = SafeValues(GetGuildInfo, unit)
    local classification = SafeValues(UnitClassification, unit)
    local role = SafeValues(UnitGroupRolesAssigned, unit)
    local creature = SafeValues(UnitCreatureType, unit)

    local connected = self:SafeCallBoolean(UnitIsConnected, unit)
    local isAFK = self:SafeCallBoolean(UnitIsAFK, unit)
    local isDND = self:SafeCallBoolean(UnitIsDND, unit)
    local isPlayer = self:SafeCallBoolean(UnitIsPlayer, unit)

    if type(name) ~= "string" then name = nil end
    if type(realm) ~= "string" then realm = nil end
    if type(pvpName) ~= "string" then pvpName = nil end
    if type(gender) ~= "number" then gender = nil end
    if type(level) ~= "number" then level = nil end
    if type(effectiveLevel) ~= "number" then effectiveLevel = nil end
    if type(raceName) ~= "string" then raceName = nil end
    if type(race) ~= "string" then race = nil end
    if type(className) ~= "string" then className = nil end
    if type(class) ~= "string" then class = nil end
    if type(factionGroup) ~= "string" then factionGroup = nil end
    if type(factionName) ~= "string" then factionName = nil end
    if type(reaction) ~= "number" then reaction = nil end
    if type(guildName) ~= "string" then guildName = nil end
    if type(guildRank) ~= "string" then guildRank = nil end
    if type(guildIndex) ~= "number" then guildIndex = nil end
    if type(guildRealm) ~= "string" then guildRealm = nil end
    if type(classification) ~= "string" then classification = nil end
    if type(role) ~= "string" then role = "NONE" end
    if type(creature) ~= "string" then creature = nil end

    local levelValue = "??"
    if type(level) == "number" and level >= 0 then levelValue = level end

    local bossLabel = nil
    if classification == "worldboss" or level == -1 then bossLabel = BOSS end

    local raw = {}
    raw.raidIcon = self:GetRaidIcon(unit)
    raw.pvpIcon = self:GetPVPIcon(unit)
    raw.factionIcon = self:GetFactionIcon(factionGroup)
    raw.classIcon = self:GetClassIcon(class)
    raw.roleIcon = self:GetRoleIcon(unit)
    raw.questIcon = self:GetQuestBossIcon(unit)
    raw.friendIcon = self:GetFriendIcon(unit)
    raw.factionName = factionName
    raw.role = role ~= "NONE" and role or nil
    raw.name = name
    raw.gender = select(1, self:GetGender(gender))
    raw.realm = realm or GetRealmName()
    raw.levelValue = levelValue
    raw.className = className
    raw.raceName = raceName
    raw.guildName = guildName
    raw.guildRank = guildRank
    raw.guildIndex = guildName and guildIndex or nil
    raw.guildRealm = guildRealm
    raw.statusAFK = isAFK and AFK or nil
    raw.statusDND = isDND and DND or nil
    raw.statusDC = connected == false and OFFLINE or nil
    raw.reactionName = reaction and _G["FACTION_STANDING_LABEL" .. reaction] or nil
    raw.creature = creature
    raw.classifBoss = bossLabel
    raw.classifElite = classification == "elite" and ELITE or nil
    raw.classifRare = (classification == "rare" or classification == "rareelite") and GARRISON_MISSION_RARE or nil
    raw.isPlayer = isPlayer and PLAYER or nil
    raw.moveSpeed = self:GetUnitSpeed(unit)
    raw.zone = name and self:GetZone(unit, name, raw.realm) or nil
    raw.unit = unit
    raw.level = level
    raw.effectiveLevel = effectiveLevel or level
    raw.race = race
    raw.class = class
    raw.factionGroup = factionGroup
    raw.reaction = reaction
    raw.classif = classification
    raw.title, raw.titleIsPrefix = self:GetTitle(name, pvpName)
    if raw.classifBoss then raw.classifElite = nil end
    return raw
end

LibEvent:attachTrigger("tooltip:cleared, tooltip:hide", function(_, tooltip)
    if CanAccessValue(tooltip) and tooltip ~= nil then
        ContextByTooltip[tooltip] = nil
    end
end)
