-- RothTooltip authoritative Retail 12.1 data boundary.
--
-- Raw TooltipData is normalized here into ordinary primitives. Feature modules
-- never receive raw TooltipData, AuraData, or args vectors. This layer also
-- owns type-preserving refresh and bounded ordinary unit metadata caches.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local ContextByTooltip = setmetatable({}, { __mode = "k" })
local FriendIconCache = {}
local RosterZoneCache = {}
local FRIEND_CACHE_TTL = 30
local FRIEND_CACHE_MAX = 128
local ROSTER_CACHE_TTL = 5

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
    if not CanAccess(tbl) or type(tbl) ~= "table" or not CanAccess(key) then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if not ok or not CanAccess(value) then return nil end
    return value
end

local function ReadNumber(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "number" then return value end
end

local function ReadString(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "string" and value ~= "" then return value end
end

local function QuerySecretPredicate(fn, ...)
    if type(fn) ~= "function" or not CanAccessAll(...) then return true end
    local ok, result = pcall(fn, ...)
    if not ok or not CanAccess(result) then return true end
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

local function TooltipIsType(tooltip, tooltipType)
    if type(tooltipType) ~= "number" or not addon:IsObjectAccessible(tooltip) then return false end
    local fn = addon:SafeGet(tooltip, "IsTooltipType")
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, tooltip, tooltipType)
    return ok and CanAccess(result) and result == true
end

local function TooltipQuery(fn, tooltip)
    if type(fn) ~= "function" or not addon:IsObjectAccessible(tooltip) then return nil end
    return Call(fn, tooltip)
end

local function GetTooltipPrimaryData(tooltip, suppliedData)
    if suppliedData ~= nil then
        if CanAccess(suppliedData) and type(suppliedData) == "table" then return suppliedData end
        return nil
    end
    local fn = addon:SafeGet(tooltip, "GetPrimaryTooltipData")
    if type(fn) ~= "function" then return nil end
    local data = Call(fn, tooltip)
    if type(data) == "table" then return data end
end

local function NormalizeLink(value)
    if CanAccess(value) and type(value) == "string" and value ~= "" then return value end
end

local function ResolveItemID(itemInfo)
    if not CanAccess(itemInfo) or itemInfo == nil then return nil end
    local valueType = type(itemInfo)
    if valueType ~= "string" and valueType ~= "number" then return nil end
    if not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then return nil end
    local itemID = Call(C_Item.GetItemInfoInstant, itemInfo)
    if type(itemID) == "number" then return itemID end
end

local function ResolveDisplayedItem(tooltip)
    local _, link, itemID = TooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedItem, tooltip)
    link = NormalizeLink(link)
    if type(itemID) ~= "number" then itemID = link and ResolveItemID(link) or nil end
    return link, itemID
end

local function ResolveDisplayedSpellID(tooltip)
    local _, spellID = TooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedSpell, tooltip)
    if type(spellID) == "number" and spellID > 0 then return spellID end

    local getSpell = addon:SafeGet(tooltip, "GetSpell")
    if type(getSpell) ~= "function" then return nil end
    local _, second, third = Call(getSpell, tooltip)
    if type(third) == "number" and third > 0 then return third end
    if type(second) == "number" and second > 0 then return second end
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
    if not CanAccess(context) or type(context) ~= "table" then return nil end
    local clean = {}
    for key, expectedType in pairs(ContextFields) do
        local value = ReadField(context, key)
        if type(value) == expectedType and (expectedType ~= "string" or value ~= "") then
            clean[key] = value
        end
    end
    if next(clean) == nil then return nil end
    return clean
end

function addon:GetCachedTooltipContext(tooltip)
    if not self:IsObjectAccessible(tooltip) then return nil end
    return ContextByTooltip[tooltip]
end

function addon:SetPrimaryTooltipContext(tooltip, context)
    if not self:IsObjectAccessible(tooltip) then return end
    ContextByTooltip[tooltip] = CopyOrdinaryContext(context)
end

function addon:ClearTooltipContexts()
    for tooltip in pairs(ContextByTooltip) do ContextByTooltip[tooltip] = nil end
end

function addon:ResolveUnitToken(unit, guid)
    if CanAccess(guid) and type(guid) == "string" and guid ~= ""
        and type(UnitTokenFromGUID) == "function" then
        local token = Call(UnitTokenFromGUID, guid)
        if type(token) == "string" and token ~= "" and not self:IsUnitIdentityRestricted(token) then
            return token
        end
    end
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return nil end
    if self:IsUnitIdentityRestricted(unit) then return nil end
    return unit
end

function addon:GetPrimaryTooltipContext(tooltip, suppliedData)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if suppliedData ~= nil and not CanAccess(suppliedData) then
        ContextByTooltip[tooltip] = nil
        return nil
    end
    if suppliedData == nil and ContextByTooltip[tooltip] then return ContextByTooltip[tooltip] end

    local tooltipData = GetTooltipPrimaryData(tooltip, suppliedData)
    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then ContextByTooltip[tooltip] = nil return nil end

    local itemType = dataTypes.Item
    local spellType = dataTypes.Spell
    local unitType = dataTypes.Unit
    local auraType = dataTypes.UnitAura
    local petActionType = dataTypes.PetAction
    local flyoutType = dataTypes.Flyout
    local macroType = dataTypes.Macro

    local context = {
        type = ReadNumber(tooltipData, "type"),
        id = ReadNumber(tooltipData, "id"),
        itemID = ReadNumber(tooltipData, "itemID"),
        spellID = ReadNumber(tooltipData, "spellID") or ReadNumber(tooltipData, "spellId"),
        dataInstanceID = ReadNumber(tooltipData, "dataInstanceID"),
        hyperlink = NormalizeLink(ReadField(tooltipData, "hyperlink"))
            or NormalizeLink(ReadField(tooltipData, "link")),
        guid = ReadString(tooltipData, "guid"),
    }
    local suppliedUnit = ReadString(tooltipData, "unitToken") or ReadString(tooltipData, "unit")

    if context.type == itemType or TooltipIsType(tooltip, itemType) then
        local link, itemID = ResolveDisplayedItem(tooltip)
        context.hyperlink = link or context.hyperlink
        context.itemID = itemID or context.itemID
    end

    if context.type == spellType or TooltipIsType(tooltip, spellType) then
        context.spellID = ResolveDisplayedSpellID(tooltip) or context.spellID
    end

    if context.type == unitType or TooltipIsType(tooltip, unitType) then
        local _, displayedUnit, displayedGUID = TooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedUnit, tooltip)
        if type(displayedGUID) == "string" and displayedGUID ~= "" then context.guid = displayedGUID end
        if type(displayedUnit) == "string" and displayedUnit ~= "" then suppliedUnit = displayedUnit end
    end

    if not context.itemID and context.type == itemType and type(context.id) == "number" then
        context.itemID = context.id
    end
    if not context.itemID and context.hyperlink then context.itemID = ResolveItemID(context.hyperlink) end

    if not context.spellID and (context.type == spellType or context.type == auraType)
        and type(context.id) == "number" then
        context.spellID = context.id
    end

    local actionLike = context.type == petActionType
        or context.type == flyoutType
        or context.type == macroType
    if actionLike then
        local link, itemID = ResolveDisplayedItem(tooltip)
        if link or itemID then
            context.hyperlink = link or context.hyperlink
            context.itemID = itemID or context.itemID
            context.spellID = nil
        else
            context.spellID = ReadNumber(tooltipData, "spellID")
                or ReadNumber(tooltipData, "spellId")
                or ResolveDisplayedSpellID(tooltip)
        end
    end

    if context.type == auraType and (
        self:AreAurasRestricted()
        or type(context.spellID) ~= "number"
        or self:IsSpellAuraRestricted(context.spellID)
    ) then
        context.spellID = nil
    end

    context.unitToken = self:ResolveUnitToken(suppliedUnit, context.guid)

    if not tooltipData then
        if not context.hyperlink then
            local getItem = addon:SafeGet(tooltip, "GetItem")
            if type(getItem) == "function" then
                local _, link = Call(getItem, tooltip)
                context.hyperlink = NormalizeLink(link)
                if context.hyperlink then context.itemID = ResolveItemID(context.hyperlink) end
            end
        end
        if not context.spellID and not context.itemID then
            context.spellID = ResolveDisplayedSpellID(tooltip)
        end
        if not context.unitToken then
            local getUnit = addon:SafeGet(tooltip, "GetUnit")
            if type(getUnit) == "function" then
                local _, token = Call(getUnit, tooltip)
                context.unitToken = self:ResolveUnitToken(token, context.guid)
            end
        end
    end

    if not context.type then
        if context.itemID or context.hyperlink then context.type = itemType
        elseif context.unitToken or context.guid then context.type = unitType
        elseif context.spellID then context.type = spellType end
    end
    if not context.id then context.id = context.itemID or context.spellID end

    local clean = CopyOrdinaryContext(context)
    ContextByTooltip[tooltip] = clean
    return clean
end

function addon:SafeGetSpell(tooltip)
    local fn = self:IsObjectAccessible(tooltip) and self:SafeGet(tooltip, "GetSpell") or nil
    if type(fn) ~= "function" then return nil end
    return Call(fn, tooltip)
end

function addon:SafeGetSpellID(tooltip)
    local context = self:GetPrimaryTooltipContext(tooltip)
    if type(context) == "table" and type(context.spellID) == "number" then return context.spellID end
    local _, second, third = self:SafeGetSpell(tooltip)
    if type(third) == "number" then return third end
    if type(second) == "number" then return second end
end

function addon:GetTooltipUnit(tooltip)
    if not self:IsObjectAccessible(tooltip) then return nil end
    local context = self:GetPrimaryTooltipContext(tooltip)
    if type(context) == "table" and type(context.unitToken) == "string" then return context.unitToken end
    local fn = self:SafeGet(tooltip, "GetUnit")
    if type(fn) ~= "function" then return nil end
    local _, unit = Call(fn, tooltip)
    return self:ResolveUnitToken(unit, context and context.guid or nil)
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

function addon:FindMouseFocus(predicate)
    local owner = GetTooltipOwner(GameTooltip)
    if not owner then return nil end
    return WalkOwnerChain(owner, function(frame, depth)
        if type(predicate) ~= "function" then return depth == 0 end
        local ok, result = pcall(predicate, frame, depth + 1)
        return ok and CanAccess(result) and result == true
    end)
end

function addon:GetMouseFocus()
    return self:FindMouseFocus()
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

local function CallTooltipSetter(tooltip, methodName, argument)
    local fn = addon:IsObjectAccessible(tooltip) and addon:SafeGet(tooltip, methodName) or nil
    if type(fn) ~= "function" or not CanAccess(argument) then return false end
    local ok, result = pcall(fn, tooltip, argument)
    if not ok or not CanAccess(result) then return false end
    return result ~= false
end

function addon:RefreshTooltipSafe(tooltip, reason)
    if type(self.IsManagedTooltip) ~= "function" or not self:IsManagedTooltip(tooltip) then return false end
    if self:SafeMethod(tooltip, "IsShown") ~= true then return false end

    local context = self:GetPrimaryTooltipContext(tooltip)
    if type(context) ~= "table" then return false end
    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then return false end

    if context.type == dataTypes.Unit then
        if not self:AllowTrigger("unit", tooltip) then return false end
        local unit = context.unitToken
        if type(unit) ~= "string" or self:IsUnitIdentityRestricted(unit) then return false end
        return CallTooltipSetter(tooltip, "SetUnit", unit)
    elseif context.type == dataTypes.Item then
        if not self:AllowTrigger("item", tooltip) then return false end
        if type(context.hyperlink) == "string" then
            return CallTooltipSetter(tooltip, "SetHyperlink", context.hyperlink)
        elseif type(context.itemID) == "number" then
            return CallTooltipSetter(tooltip, "SetItemByID", context.itemID)
        end
    elseif context.type == dataTypes.Spell and type(context.spellID) == "number" then
        if not self:AllowTrigger("spell", tooltip) then return false end
        return CallTooltipSetter(tooltip, "SetSpellByID", context.spellID)
    end
    return false
end

function addon:RefreshManagedTooltipsMatching(matchFunc, reason)
    if type(self.ForEachVisibleManagedTooltip) ~= "function" then return 0 end
    local refreshed = 0
    self:ForEachVisibleManagedTooltip(function(tooltip)
        local context = self:GetPrimaryTooltipContext(tooltip)
        local matches = type(matchFunc) ~= "function"
        if type(matchFunc) == "function" then
            local ok, result = pcall(matchFunc, tooltip, context)
            matches = ok and CanAccess(result) and result == true
        end
        if matches and self:RefreshTooltipSafe(tooltip, reason) then refreshed = refreshed + 1 end
    end)
    return refreshed
end

function addon:GetLine(tooltip, number)
    if not self:IsTooltipSafe(tooltip) or type(number) ~= "number" or number < 1 then return nil end
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

function addon:FindLine(tooltip, keyword)
    if not self:IsTooltipSafe(tooltip) or not CanAccess(keyword) or type(keyword) ~= "string" then return nil end
    local lineCount = self:SafeMethod(tooltip, "NumLines")
    if type(lineCount) ~= "number" then return nil end

    for index = 1, lineCount do
        local left, right = self:GetLine(tooltip, index)
        for _, line in ipairs({ left, right }) do
            if self:IsObjectAccessible(line) then
                local text = self:SafeMethod(line, "GetText")
                if type(text) == "string" then
                    local ok, found = pcall(string.find, text, keyword)
                    if ok and found then return left, index, right end
                end
            end
        end
    end
end

function addon:ClearLine(tooltip, index)
    local left, right = self:GetLine(tooltip, index)
    if self:IsObjectAccessible(left) then self:SafeMethod(left, "SetText", nil) end
    if self:IsObjectAccessible(right) then self:SafeMethod(right, "SetText", nil) end
end

function addon:HideLine(tooltip, keyword)
    local _, index = self:FindLine(tooltip, keyword)
    if index then self:ClearLine(tooltip, index) end
end

local function PruneCache(cache, now, ttl, maximum)
    local count = 0
    local oldestKey, oldestTime
    for key, entry in pairs(cache) do
        local entryTime = type(entry) == "table" and entry.time or nil
        if type(entryTime) ~= "number" or now - entryTime > ttl then
            cache[key] = nil
        else
            count = count + 1
            if oldestTime == nil or entryTime < oldestTime then oldestKey, oldestTime = key, entryTime end
        end
    end
    if count >= maximum and oldestKey then cache[oldestKey] = nil end
end

local function ElementEnabled(elements, key)
    return type(elements) == "table"
        and type(elements[key]) == "table"
        and elements[key].enable == true
end

function addon:GetQuestBossIcon(unit)
    if self:SafeCallBoolean(UnitIsQuestBoss, unit) then return self.icons.questboss end
end

function addon:GetPVPIcon(unit)
    if self:SafeCallBoolean(UnitIsPVPFreeForAll, unit) then return self.icons.pvp end
end

function addon:GetRoleIcon(unit)
    local role = Call(UnitGroupRolesAssigned, unit)
    if type(role) == "string" and role ~= "NONE" then return self.icons[string.upper(role)] end
end

function addon:GetFactionIcon(factionGroup)
    if type(factionGroup) == "string" then return self.icons[factionGroup] end
end

function addon:GetRaidIcon(unit)
    local index = Call(GetRaidTargetIndex, unit)
    local icon = type(index) == "number" and ICON_LIST and ICON_LIST[index] or nil
    if type(icon) == "string" then return icon .. "0|t" end
end

function addon:GetClassIcon(class)
    if type(class) ~= "string" then return nil end
    local coordinates = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[string.upper(class)]
    if type(coordinates) ~= "table" then return nil end
    local x1, x2, y1, y2 = unpack(coordinates)
    if type(x1) ~= "number" or type(x2) ~= "number"
        or type(y1) ~= "number" or type(y2) ~= "number" then return nil end
    return string.format(self.icons.class, x1 * 256, x2 * 256, y1 * 256, y2 * 256)
end

function addon:GetFriendIcon(unit)
    if self:IsUnitIdentityRestricted(unit) or self:SafeCallBoolean(UnitIsPlayer, unit) ~= true then return nil end
    local guid = Call(UnitGUID, unit)
    if type(guid) ~= "string" or guid == "" then return nil end

    local now = GetTime and GetTime() or 0
    local cached = FriendIconCache[guid]
    if type(cached) == "table" and now - cached.time <= FRIEND_CACHE_TTL then
        return cached.icon or nil
    end

    PruneCache(FriendIconCache, now, FRIEND_CACHE_TTL, FRIEND_CACHE_MAX)
    local icon
    if self:SafeCallBoolean(C_FriendList and C_FriendList.IsFriend, guid) then
        icon = self.icons.friend
    else
        local playerGUID = Call(UnitGUID, "player")
        if type(playerGUID) == "string" and guid ~= playerGUID then
            local info = Call(C_BattleNet and C_BattleNet.GetAccountInfoByGUID, guid)
            if type(info) == "table" and self:SafeBoolean(ReadField(info, "isFriend")) then
                icon = self.icons.bnetfriend
            end
        end
    end
    FriendIconCache[guid] = { icon = icon or false, time = now }
    return icon
end

function addon:GetUnitSpeed(unit)
    if self:IsUnitIdentityRestricted(unit) or self:AreUnitStatsRestricted() then return nil end
    local currentSpeed, runSpeed = Call(GetUnitSpeed, unit)
    local speed = type(currentSpeed) == "number" and currentSpeed or runSpeed
    local baseSpeed = BASE_MOVEMENT_SPEED or 7
    if type(speed) ~= "number" or type(baseSpeed) ~= "number" or baseSpeed <= 0 then return nil end
    return speed / baseSpeed * 100 + 0.5
end

function addon:GetTitle(name, pvpName)
    if type(name) ~= "string" or name == "" or type(pvpName) ~= "string"
        or pvpName == "" or name == pvpName then return nil end
    local first, last = pvpName:find(name, 1, true)
    if not first then return nil end
    local title = strtrim((pvpName:sub(1, first - 1) .. pvpName:sub(last + 1)):gsub("[,，]", ""))
    if title == "" then return nil end
    return title, first ~= 1
end

local function RebuildRosterZoneCache()
    wipe(RosterZoneCache)
    local count = Call(GetNumGroupMembers)
    if type(count) ~= "number" then count = 0 end
    for index = 1, math.min(count, 40) do
        local name, _, _, _, _, _, zone = Call(GetRaidRosterInfo, index)
        if type(name) == "string" and type(zone) == "string" then
            RosterZoneCache[name] = zone
            local shortName = Ambiguate and Ambiguate(name, "short") or name:match("^[^-]+")
            if type(shortName) == "string" then RosterZoneCache[shortName] = zone end
        end
    end
    RosterZoneCache.time = GetTime and GetTime() or 0
end

function addon:GetZone(unit, unitName, realm)
    if not CanAccessAll(unit, unitName, realm) or type(unit) ~= "string"
        or type(unitName) ~= "string" or type(realm) ~= "string" then return nil end
    if self:SafeCallBoolean(IsInGroup) ~= true then return nil end

    local now = GetTime and GetTime() or 0
    if type(RosterZoneCache.time) ~= "number" or now - RosterZoneCache.time > ROSTER_CACHE_TTL then
        RebuildRosterZoneCache()
    end
    return RosterZoneCache[unitName .. "-" .. realm] or RosterZoneCache[unitName]
end

function addon:GetUnitInfo(unit, elements)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == ""
        or self:IsUnitIdentityRestricted(unit) then return nil end

    local name, realm = Call(UnitName, unit)
    local level = Call(UnitLevel, unit)
    local effectiveLevel = Call(UnitEffectiveLevel, unit)
    local className, class = Call(UnitClass, unit)
    local factionGroup, factionName = Call(UnitFactionGroup, unit)
    local reaction = Call(UnitReaction, unit, "player")
    local classification = Call(UnitClassification, unit)
    local isPlayer = self:SafeCallBoolean(UnitIsPlayer, unit)

    if type(name) ~= "string" then name = nil end
    if type(realm) ~= "string" then realm = nil end
    if type(level) ~= "number" then level = nil end
    if type(effectiveLevel) ~= "number" then effectiveLevel = nil end
    if type(className) ~= "string" then className = nil end
    if type(class) ~= "string" then class = nil end
    if type(factionGroup) ~= "string" then factionGroup = nil end
    if type(factionName) ~= "string" then factionName = nil end
    if type(reaction) ~= "number" then reaction = nil end
    if type(classification) ~= "string" then classification = nil end

    local needTitle = ElementEnabled(elements, "title")
    local needGender = ElementEnabled(elements, "gender")
    local needRace = ElementEnabled(elements, "raceName")
    local needGuild = ElementEnabled(elements, "guildName")
        or ElementEnabled(elements, "guildRank")
        or ElementEnabled(elements, "guildIndex")
        or ElementEnabled(elements, "guildRealm")
    local needRole = ElementEnabled(elements, "role") or ElementEnabled(elements, "roleIcon")
    local needCreature = ElementEnabled(elements, "creature")
    local needConnection = ElementEnabled(elements, "statusDC")

    local pvpName = needTitle and Call(UnitPVPName, unit) or nil
    local gender = needGender and Call(UnitSex, unit) or nil
    local raceName, race
    if needRace then raceName, race = Call(UnitRace, unit) end
    local guildName, guildRank, guildIndex, guildRealm
    if needGuild then guildName, guildRank, guildIndex, guildRealm = Call(GetGuildInfo, unit) end
    local role = needRole and Call(UnitGroupRolesAssigned, unit) or nil
    local creature = needCreature and Call(UnitCreatureType, unit) or nil
    local connected = needConnection and self:SafeCallBoolean(UnitIsConnected, unit) or nil
    local localRealm = Call(GetRealmName)

    local raw = {
        unit = unit,
        name = name,
        realm = realm or (type(localRealm) == "string" and localRealm or ""),
        level = level,
        effectiveLevel = effectiveLevel or level,
        levelValue = type(level) == "number" and level >= 0 and level or "??",
        className = className,
        class = class,
        factionGroup = factionGroup,
        factionName = factionName,
        reaction = reaction,
        classif = classification,
        isPlayer = isPlayer and PLAYER or nil,
        statusDC = connected == false and OFFLINE or nil,
    }

    raw.raidIcon = ElementEnabled(elements, "raidIcon") and self:GetRaidIcon(unit) or nil
    raw.pvpIcon = ElementEnabled(elements, "pvpIcon") and self:GetPVPIcon(unit) or nil
    raw.factionIcon = ElementEnabled(elements, "factionIcon") and self:GetFactionIcon(factionGroup) or nil
    raw.classIcon = ElementEnabled(elements, "classIcon") and self:GetClassIcon(class) or nil
    raw.roleIcon = ElementEnabled(elements, "roleIcon") and self:GetRoleIcon(unit) or nil
    raw.questIcon = ElementEnabled(elements, "questIcon") and self:GetQuestBossIcon(unit) or nil
    raw.friendIcon = ElementEnabled(elements, "friendIcon") and self:GetFriendIcon(unit) or nil
    raw.statusAFK = ElementEnabled(elements, "statusAFK") and self:SafeCallBoolean(UnitIsAFK, unit) and AFK or nil
    raw.statusDND = ElementEnabled(elements, "statusDND") and self:SafeCallBoolean(UnitIsDND, unit) and DND or nil
    raw.moveSpeed = ElementEnabled(elements, "moveSpeed") and self:GetUnitSpeed(unit) or nil
    raw.zone = ElementEnabled(elements, "zone") and name and self:GetZone(unit, name, raw.realm) or nil

    raw.title, raw.titleIsPrefix = self:GetTitle(name, pvpName)
    raw.gender = select(1, self:GetGender(gender))
    raw.raceName = type(raceName) == "string" and raceName or nil
    raw.race = type(race) == "string" and race or nil
    raw.guildName = type(guildName) == "string" and guildName or nil
    raw.guildRank = type(guildRank) == "string" and guildRank or nil
    raw.guildIndex = raw.guildName and type(guildIndex) == "number" and guildIndex or nil
    raw.guildRealm = type(guildRealm) == "string" and guildRealm or nil
    raw.role = type(role) == "string" and role ~= "NONE" and role or nil
    raw.creature = type(creature) == "string" and creature or nil
    raw.reactionName = reaction and _G["FACTION_STANDING_LABEL" .. reaction] or nil
    raw.classifBoss = (classification == "worldboss" or level == -1) and BOSS or nil
    raw.classifElite = not raw.classifBoss and classification == "elite" and ELITE or nil
    raw.classifRare = (classification == "rare" or classification == "rareelite")
        and GARRISON_MISSION_RARE or nil
    return raw
end

local function ClearOrdinaryCaches()
    wipe(FriendIconCache)
    wipe(RosterZoneCache)
end

LibEvent:attachTrigger("tooltip:cleared, tooltip:hide, tooltip:unregister", function(_, tooltip)
    if CanAccess(tooltip) and tooltip ~= nil then ContextByTooltip[tooltip] = nil end
end)
LibEvent:attachEvent("GROUP_ROSTER_UPDATE, FRIENDLIST_UPDATE", ClearOrdinaryCaches)
