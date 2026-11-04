-- Ordinary, synchronous unit presentation. No retained native payloads.
local _, addon = ...
local function Call(fn, ...) return addon:SafeCall("UnitInfo", fn, ...) end
local function CanAccessAll(...) return addon:CanAccessAllValues(...) end
local function CanAccess(value) return addon:CanAccessValue(value) end
local function ReadField(tbl, key) return addon:SafeGet(tbl, key) end

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
    if type(index) ~= "number" then return nil end
    local icon = ICON_LIST and ICON_LIST[index]
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

    if self:SafeCallBoolean(C_FriendList and C_FriendList.IsFriend, guid) then return self.icons.friend end
    local playerGUID = Call(UnitGUID, "player")
    if type(playerGUID) ~= "string" or guid == playerGUID then return nil end

    local info = Call(C_BattleNet and C_BattleNet.GetAccountInfoByGUID, guid)
    if type(info) == "table" and self:SafeBoolean(ReadField(info, "isFriend")) then return self.icons.bnetfriend end
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
    local first, last = string.find(pvpName, name, 1, true)
    if not first then return nil end

    local title = string.sub(pvpName, 1, first - 1) .. string.sub(pvpName, last + 1)
    title = strtrim((title:gsub(",", ""):gsub("，", "")))
    if title == "" then return nil end
    return title, first ~= 1
end

local ROSTER_ZONE_CACHE_TTL = 2
local rosterZoneCache = {}
local rosterZoneCacheAt = -math.huge

local function GetRosterNameAndZone(index)
    if type(index) ~= "number" or type(GetRaidRosterInfo) ~= "function" then return nil, nil end
    local name, _, _, _, _, _, zone = Call(GetRaidRosterInfo, index)
    if type(name) ~= "string" or name == "" then name = nil end
    if type(zone) ~= "string" or zone == "" then zone = nil end
    return name, zone
end

function addon:InvalidateUnitRosterCache()
    wipe(rosterZoneCache)
    rosterZoneCacheAt = -math.huge
end

local function GetRosterZoneCache()
    local now = GetTime and GetTime() or 0
    if now - rosterZoneCacheAt <= ROSTER_ZONE_CACHE_TTL then return rosterZoneCache end

    wipe(rosterZoneCache)
    local count = Call(GetNumGroupMembers)
    if type(count) ~= "number" or count < 1 then count = 0 end
    for index = 1, math.min(count, 40) do
        local name, zone = GetRosterNameAndZone(index)
        if name and zone then
            rosterZoneCache[name] = zone
            local shortName = name:match("^[^-]+")
            if shortName and rosterZoneCache[shortName] == nil then rosterZoneCache[shortName] = zone end
        end
    end
    rosterZoneCacheAt = now
    return rosterZoneCache
end

function addon:GetZone(unit, unitName, realm)
    if not CanAccessAll(unit, unitName, realm) or type(unit) ~= "string"
        or type(unitName) ~= "string" or type(realm) ~= "string" then return nil end
    if self:SafeCallBoolean(IsInGroup) ~= true then return nil end

    local raidIndex = unit:match("^raid(%d+)$")
    if raidIndex then
        local _, zone = GetRosterNameAndZone(tonumber(raidIndex))
        return zone
    end
    if not unit:match("^party%d+$") then return nil end

    local zones = GetRosterZoneCache()
    return zones[unitName .. "-" .. realm] or zones[unitName]
end

function addon:GetUnitInfo(unit, elements)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == ""
        or self:IsUnitIdentityRestricted(unit) then return nil end

    local name, realm = Call(UnitName, unit)
    local level = Call(UnitLevel, unit)
    local effectiveLevel = Call(UnitEffectiveLevel, unit)
    local className, class = Call(UnitClass, unit)
    local factionGroup, factionName = Call(UnitFactionGroup, unit)
    local reaction = self:CanCompareUnitTokens(unit, "player") and Call(UnitReaction, unit, "player") or nil
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
    local connected
    if needConnection then connected = self:SafeCallBoolean(UnitIsConnected, unit) end

    local raw = {
        unit = unit,
        name = name,
        realm = realm or GetRealmName(),
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
