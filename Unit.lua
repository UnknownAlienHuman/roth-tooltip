local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local C_ChallengeMode = C_ChallengeMode
local C_PlayerInfo = C_PlayerInfo
local C_PaperDollInfo = C_PaperDollInfo

local MAX_INSPECT_CACHE = 64
local INSPECT_CACHE_TTL = 300
local INSPECT_REQUEST_THROTTLE = 2
local RAID_CACHE_TTL = 300

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function CanAccessAll(...)
    return not addon.CanAccessAllValues or addon:CanAccessAllValues(...)
end

local function Call(fn, ...)
    if not CanAccess(fn) or type(fn) ~= "function" then return nil end
    if not CanAccessAll(...) then return nil end

    local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 = pcall(fn, ...)
    if not ok then return nil end

    if not CanAccess(a1) then a1 = nil end
    if not CanAccess(a2) then a2 = nil end
    if not CanAccess(a3) then a3 = nil end
    if not CanAccess(a4) then a4 = nil end
    if not CanAccess(a5) then a5 = nil end
    if not CanAccess(a6) then a6 = nil end
    if not CanAccess(a7) then a7 = nil end
    if not CanAccess(a8) then a8 = nil end
    if not CanAccess(a9) then a9 = nil end
    if not CanAccess(a10) then a10 = nil end
    if not CanAccess(a11) then a11 = nil end
    if not CanAccess(a12) then a12 = nil end
    if not CanAccess(a13) then a13 = nil end
    if not CanAccess(a14) then a14 = nil end

    return a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14
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

local function ReadString(tbl, key)
    local value = ReadField(tbl, key)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function IsOrdinaryUnit(unit)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return false end
    if addon.IsUnitIdentityRestricted and addon:IsUnitIdentityRestricted(unit) then return false end
    return true
end

local function EscapePattern(text)
    return (text:gsub("([^%w])", "%%%1"))
end

local function AddStatLine(tip, label, value)
    if not addon:IsTooltipSafe(tip) then return end
    if not CanAccess(label) or type(label) ~= "string" or label == "" then return end
    if not CanAccess(value) or (type(value) ~= "string" and type(value) ~= "number") then return end

    local keyword = EscapePattern(label) .. ":"
    if addon:FindLine(tip, keyword) then return end

    local text = string.format("%s: |cffffffff%s|r", label, tostring(value))
    addon:SafeMethod(tip, "AddLine", text, 0, 1, 0.8)
end

local function GetBestMythicPlusKey(unit)
    if not IsOrdinaryUnit(unit) then return nil end
    if not C_PlayerInfo or type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) ~= "function" then return nil end

    local summary = Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    if type(summary) ~= "table" then return nil end

    local runs = ReadField(summary, "runs")
    if type(runs) ~= "table" then return nil end

    local bestLevel, bestModeID, bestScore
    for _, run in ipairs(runs) do
        if CanAccess(run) and type(run) == "table" then
            local level = ReadNumber(run, "bestRunLevel")
            local score = ReadNumber(run, "bestRunScore")
            if score == nil then score = ReadNumber(run, "mapScore") end
            local modeID = ReadNumber(run, "challengeModeID")

            if level ~= nil then
                local replace = bestLevel == nil or level > bestLevel
                if not replace and level == bestLevel and score ~= nil then
                    replace = bestScore == nil or score > bestScore
                end
                if replace then
                    bestLevel = level
                    bestModeID = modeID
                    bestScore = score
                end
            end
        end
    end

    if bestLevel == nil then return nil end

    local mapName
    if type(bestModeID) == "number" and C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name = Call(C_ChallengeMode.GetMapUIInfo, bestModeID)
        if type(name) == "string" and name ~= "" then mapName = name end
    end
    return bestLevel, mapName
end

local raidProgressCache
local raidProgressCacheTime = 0

local function PreferRaidEntry(previous, difficultyID, encounterProgress)
    if not previous then return true end
    if type(difficultyID) == "number" and type(previous.difficultyID) == "number"
        and difficultyID ~= previous.difficultyID then
        return difficultyID > previous.difficultyID
    end
    return encounterProgress > previous.encounterProgress
end

local function GetAllSavedRaidProgress()
    if type(GetNumSavedInstances) ~= "function" or type(GetSavedInstanceInfo) ~= "function" then return nil end

    local now = GetTime and GetTime() or 0
    if raidProgressCache and now - raidProgressCacheTime < RAID_CACHE_TTL then
        return raidProgressCache
    end

    local count = Call(GetNumSavedInstances)
    if type(count) ~= "number" or count < 1 then
        raidProgressCache = {}
        raidProgressCacheTime = now
        return raidProgressCache
    end

    local byName = {}
    for index = 1, count do
        local name, _, _, difficultyID, locked, _, _, isRaid, _, difficultyName, numEncounters, encounterProgress = Call(GetSavedInstanceInfo, index)

        if type(name) == "string" and name ~= "" and locked == true and isRaid == true
            and type(numEncounters) == "number" and type(encounterProgress) == "number" then
            local previous = byName[name]
            if PreferRaidEntry(previous, difficultyID, encounterProgress) then
                byName[name] = {
                    raidName = name,
                    difficultyID = type(difficultyID) == "number" and difficultyID or nil,
                    difficultyName = type(difficultyName) == "string" and difficultyName or nil,
                    numEncounters = numEncounters,
                    encounterProgress = encounterProgress,
                }
            end
        end
    end

    local raids = {}
    for _, entry in pairs(byName) do
        raids[#raids + 1] = entry
    end
    table.sort(raids, function(a, b) return a.raidName < b.raidName end)

    raidProgressCache = raids
    raidProgressCacheTime = now
    return raids
end

local function InvalidateRaidCache()
    raidProgressCache = nil
    raidProgressCacheTime = 0
end

local inspectCache = {}
local inspectCacheCount = 0
local pendingInspectGUID
local pendingInspectUnit
local inspectLastRequest = 0

local function PruneInspectCache(now)
    local oldestGUID, oldestTime
    inspectCacheCount = 0

    for guid, entry in pairs(inspectCache) do
        local entryTime = type(entry) == "table" and entry.time or 0
        if type(entryTime) ~= "number" or now - entryTime > INSPECT_CACHE_TTL then
            inspectCache[guid] = nil
        else
            inspectCacheCount = inspectCacheCount + 1
            if oldestTime == nil or entryTime < oldestTime then
                oldestGUID = guid
                oldestTime = entryTime
            end
        end
    end

    if inspectCacheCount >= MAX_INSPECT_CACHE and oldestGUID then
        inspectCache[oldestGUID] = nil
        inspectCacheCount = inspectCacheCount - 1
    end
end

local function GetSafeUnitGUID(unit)
    if not IsOrdinaryUnit(unit) then return nil end
    local guid = Call(UnitGUID, unit)
    if type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

local function GetTooltipContextGUID(context)
    if CanAccess(context) and type(context) == "table" then
        local guid = context.guid
        if CanAccess(guid) and type(guid) == "string" and guid ~= "" then
            return guid
        end
        local unit = context.unitToken
        if IsOrdinaryUnit(unit) then return GetSafeUnitGUID(unit) end
    end
    return nil
end

local function ResolveInspectUnit(guid)
    if type(guid) ~= "string" or guid == "" then return nil end

    if IsOrdinaryUnit(pendingInspectUnit) and GetSafeUnitGUID(pendingInspectUnit) == guid then
        return pendingInspectUnit
    end

    local unit = addon:ResolveUnitToken(nil, guid)
    if IsOrdinaryUnit(unit) and GetSafeUnitGUID(unit) == guid then
        return unit
    end
    return nil
end

local function ShouldClearInspectTarget()
    if addon:IsObjectAccessible(InspectFrame) and addon:SafeMethod(InspectFrame, "IsShown") == true then
        return false
    end
    if addon:IsObjectAccessible(PlayerSpellsFrame)
        and addon:SafeMethod(PlayerSpellsFrame, "IsInspecting") == true then
        return false
    end
    return true
end

local function ClearPendingInspect()
    pendingInspectGUID = nil
    pendingInspectUnit = nil

    if type(ClearInspectPlayer) == "function" and ShouldClearInspectTarget() then
        pcall(ClearInspectPlayer)
    end
end

local function OnInspectReady(_, guid)
    if not CanAccess(guid) or type(guid) ~= "string" or guid == "" then return end
    if pendingInspectGUID == nil or guid ~= pendingInspectGUID then return end

    local unit = ResolveInspectUnit(guid)
    if unit then
        local itemLevel
        if C_PaperDollInfo and type(C_PaperDollInfo.GetInspectItemLevel) == "function" then
            itemLevel = Call(C_PaperDollInfo.GetInspectItemLevel, unit)
        end

        local specID
        if type(GetInspectSpecialization) == "function" then
            specID = Call(GetInspectSpecialization, unit)
        end

        if type(itemLevel) ~= "number" or itemLevel <= 0 then itemLevel = nil end
        if type(specID) ~= "number" or specID <= 0 then specID = nil end

        local now = GetTime and GetTime() or 0
        PruneInspectCache(now)
        inspectCache[guid] = {
            ilvl = itemLevel,
            specID = specID,
            time = now,
        }
        inspectCacheCount = inspectCacheCount + 1
    end

    ClearPendingInspect()

    if addon.RefreshManagedTooltipsMatching then
        addon:RefreshManagedTooltipsMatching(function(_, context)
            return GetTooltipContextGUID(context) == guid
        end, "INSPECT_READY")
    end
end

local function RequestInspect(unit, guid, now)
    if not IsOrdinaryUnit(unit) then return end
    if type(guid) ~= "string" or guid == "" then return end
    if InCombatLockdown() then return end
    if type(CanInspect) ~= "function" or addon:SafeCallBoolean(CanInspect, unit) ~= true then return end
    if type(NotifyInspect) ~= "function" then return end

    local sameRequest = pendingInspectGUID == guid and pendingInspectUnit == unit
    if sameRequest and now - inspectLastRequest <= INSPECT_REQUEST_THROTTLE then return end

    pendingInspectGUID = guid
    pendingInspectUnit = unit
    inspectLastRequest = now
    local ok = pcall(NotifyInspect, unit)
    if not ok then
        pendingInspectGUID = nil
        pendingInspectUnit = nil
    end
end

local function GetCachedInspect(guid, now)
    if type(guid) ~= "string" or guid == "" then return nil end
    local entry = inspectCache[guid]
    if type(entry) ~= "table" then return nil end
    if type(entry.time) ~= "number" or now - entry.time > INSPECT_CACHE_TTL then
        inspectCache[guid] = nil
        inspectCacheCount = math.max(0, inspectCacheCount - 1)
        return nil
    end
    return entry
end

local function AddPlayerStats(tip, unit)
    local playerConfig = addon.db and addon.db.unit and addon.db.unit.player
    if type(playerConfig) ~= "table" or not IsOrdinaryUnit(unit) then return end
    if addon.AreUnitStatsRestricted and addon:AreUnitStatsRestricted() then return end

    local isSelf = false
    if not addon.CanCompareUnitTokens or addon:CanCompareUnitTokens(unit, "player") then
        isSelf = addon:SafeCallBoolean(UnitIsUnit, unit, "player") == true
    end

    local guid = GetSafeUnitGUID(unit)
    local now = GetTime and GetTime() or 0
    local cache = GetCachedInspect(guid, now)

    if playerConfig.showItemLevel == true then
        local itemLevel
        if isSelf then
            local _, equipped = Call(GetAverageItemLevel)
            if type(equipped) == "number" and equipped > 0 then itemLevel = equipped end
        elseif cache and type(cache.ilvl) == "number" then
            itemLevel = cache.ilvl
        else
            RequestInspect(unit, guid, now)
        end

        if type(itemLevel) == "number" then
            local label = addon.L and addon.L["tooltip.itemLevel"] or "Item Level"
            AddStatLine(tip, label, string.format("%.1f", itemLevel))
        end
    end

    if playerConfig.showPveScore == true then
        local score
        if isSelf and C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
            score = Call(C_ChallengeMode.GetOverallDungeonScore)
        elseif not isSelf and C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
            local summary = Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
            score = ReadNumber(summary, "currentSeasonScore")
        end

        if type(score) == "number" then
            local colored = tostring(score)
            if C_ChallengeMode and type(C_ChallengeMode.GetDungeonScoreRarityColor) == "function" then
                local color = Call(C_ChallengeMode.GetDungeonScoreRarityColor, score)
                local r = ReadNumber(color, "r")
                local g = ReadNumber(color, "g")
                local b = ReadNumber(color, "b")
                if r and g and b then
                    colored = string.format("|cff%s%d|r", addon:GetHexColor(r, g, b), score)
                end
            end
            local label = addon.L and addon.L["tooltip.pveScore"] or "PvE Score"
            AddStatLine(tip, label, colored)
        end
    end

    if playerConfig.showBestKey == true then
        local level, mapName = GetBestMythicPlusKey(unit)
        if type(level) == "number" then
            local value = string.format("+%d", level)
            if type(mapName) == "string" then value = value .. " - " .. mapName end
            local label = addon.L and addon.L["tooltip.bestKey"] or "Best M+ Key"
            AddStatLine(tip, label, value)
        end
    end

    if playerConfig.showRaidProgress == true and isSelf then
        local raids = GetAllSavedRaidProgress()
        if type(raids) == "table" then
            for _, raid in ipairs(raids) do
                local value = string.format("%d/%d", raid.encounterProgress, raid.numEncounters)
                if type(raid.difficultyName) == "string" then
                    value = value .. " " .. raid.difficultyName
                end
                AddStatLine(tip, raid.raidName, value)
            end
        end
    end

    local role = Call(UnitGroupRolesAssigned, unit)
    if type(role) ~= "string" then role = nil end

    local specID
    if isSelf then
        local specIndex = Call(GetSpecialization)
        if type(specIndex) == "number" and type(GetSpecializationInfo) == "function" then
            specID = Call(GetSpecializationInfo, specIndex)
        end
    elseif cache and type(cache.specID) == "number" then
        specID = cache.specID
    end

    if type(specID) == "number" and type(GetSpecializationInfoByID) == "function" then
        local _, specName, _, _, specRole = Call(GetSpecializationInfoByID, specID)
        if type(specName) == "string" and specName ~= "" then
            local label = addon.L and addon.L["tooltip.spec"] or "Spec"
            AddStatLine(tip, label, specName)
            if role == nil or role == "NONE" then
                if type(specRole) == "string" then role = specRole end
            end
        end
    end

    if type(role) == "string" and role ~= "NONE" then
        local label = addon.L and addon.L["tooltip.role"] or "Role"
        AddStatLine(tip, label, _G[role] or role)
    end
end

local function Strip(text)
    if not CanAccess(text) or type(text) ~= "string" then return "" end
    return (text:gsub("%s+([|%x%s]+)<trim>", "%1"))
end

local function SafeColorFunction(name, raw)
    local fn = addon.colorfunc and addon.colorfunc[name]
    if type(fn) ~= "function" then return nil end
    local ok, r, g, b = pcall(fn, raw)
    if not ok or not CanAccessAll(r, g, b) then return nil end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b
end

local function ColorBorder(tip, config, raw)
    if not addon:IsTooltipSafe(tip) or type(config) ~= "table" then return end

    local mode = config.coloredBorder
    local r, g, b = SafeColorFunction(mode, raw)
    if r then
        LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
    elseif type(mode) == "string" and mode ~= "default" then
        r, g, b = addon:GetRGBColor(mode)
        LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
    else
        local color = addon.db and addon.db.general and addon.db.general.borderColor
        if type(color) == "table" then
            LibEvent:trigger("tooltip.style.border.color", tip, unpack(color))
        end
    end
end

local function ColorBackground(tip, config, raw)
    if not addon:IsTooltipSafe(tip) or type(config) ~= "table" then return end
    local background = config.background
    if type(background) ~= "table" then return end

    local mode = background.colorfunc
    if mode == "default" or mode == "" or mode == "inherit" then
        local color = addon.db and addon.db.general and addon.db.general.background
        if type(color) ~= "table" then return end
        local r, g, b, a = unpack(color)
        if type(background.alpha) == "number" then a = background.alpha end
        LibEvent:trigger("tooltip.style.background", tip, r, g, b, a)
        return
    end

    local r, g, b = SafeColorFunction(mode, raw)
    if r then
        local alpha = type(background.alpha) == "number" and background.alpha or 0.8
        LibEvent:trigger("tooltip.style.background", tip, r, g, b, alpha)
    end
end

local function GrayForDead(tip, config, unit)
    if type(config) ~= "table" or config.grayForDead ~= true then return end
    if addon:SafeCallBoolean(UnitIsDeadOrGhost, unit) ~= true then return end
    if not addon:IsTooltipSafe(tip) then return end

    LibEvent:trigger("tooltip.style.border.color", tip, 0.6, 0.6, 0.6)
    LibEvent:trigger("tooltip.style.background", tip, 0.1, 0.1, 0.1)

    local name = addon:SafeMethod(tip, "GetName")
    local lineCount = addon:SafeMethod(tip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return end

    for index = 1, lineCount do
        local line = _G[name .. "TextLeft" .. index]
        if addon:IsObjectAccessible(line) then
            local text = addon:SafeMethod(line, "GetText")
            if CanAccess(text) and type(text) == "string" then
                text = text:gsub("|cff%x%x%x%x%x%x", "|cffaaaaaa")
                addon:SafeMethod(line, "SetText", text)
            end
            addon:SafeMethod(line, "SetTextColor", 0.7, 0.7, 0.7)
        end
    end
end

local function ShowBigFactionIcon(tip, config, raw)
    local elements = type(config) == "table" and config.elements or nil
    local factionConfig = type(elements) == "table" and elements.factionBig or nil
    local faction = type(raw) == "table" and raw.factionGroup or nil
    if type(factionConfig) ~= "table" or factionConfig.enable ~= true then return end
    if faction ~= "Alliance" and faction ~= "Horde" then return end

    local icon = addon:SafeGet(tip, "BigFactionIcon")
    if not addon:IsObjectAccessible(icon) then return end
    addon:SafeMethod(icon, "SetTexture", "Interface\\Timer\\" .. faction .. "-Logo")
    addon:SafeMethod(icon, "Show")
end

local function HideLineRange(tip, first, last)
    local name = addon:SafeMethod(tip, "GetName")
    local lineCount = addon:SafeMethod(tip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return end

    last = math.min(last or lineCount, lineCount)
    for index = first, last do
        local line = _G[name .. "TextLeft" .. index]
        if addon:IsObjectAccessible(line) then addon:SafeMethod(line, "SetText", nil) end
    end
end

local function SetTooltipLine(tip, index, text)
    if type(text) ~= "string" then return end
    local line = addon:GetLine(tip, index)
    if addon:IsObjectAccessible(line) then addon:SafeMethod(line, "SetText", text) end
end

local function PlayerCharacter(tip, unit, config, raw)
    local data = addon:GetUnitData(unit, config.elements, raw)
    if type(data) ~= "table" then return end

    HideLineRange(tip, 2, 3)
    addon:HideLine(tip, "^" .. LEVEL)
    addon:HideLine(tip, "^" .. FACTION_ALLIANCE)
    addon:HideLine(tip, "^" .. FACTION_HORDE)
    addon:HideLine(tip, "^" .. PVP)

    for index, values in ipairs(data) do
        if type(values) == "table" then
            SetTooltipLine(tip, index, Strip(table.concat(values, " ")))
        end
    end

    ColorBorder(tip, config, raw)
    ColorBackground(tip, config, raw)
    GrayForDead(tip, config, unit)
    ShowBigFactionIcon(tip, config, raw)
    AddPlayerStats(tip, unit)
end

local function NonPlayerCharacter(tip, unit, config, raw)
    local levelLine = addon:FindLine(tip, "^" .. LEVEL)
    local lineCount = addon:SafeMethod(tip, "NumLines")
    if levelLine or (type(lineCount) == "number" and lineCount > 1) then
        local data = addon:GetUnitData(unit, config.elements, raw)
        local titleLine = addon:GetNpcTitle(tip)
        local keepTitle = config.elements and config.elements.npcTitle
            and config.elements.npcTitle.enable == true and addon:IsObjectAccessible(titleLine)
        local offset = keepTitle and 1 or 0

        if type(data) == "table" then
            for index, values in ipairs(data) do
                if type(values) == "table" then
                    if index == 1 then
                        SetTooltipLine(tip, index, table.concat(values, " "))
                    elseif index == 2 and keepTitle then
                        local titleText = addon:SafeMethod(titleLine, "GetText")
                        if CanAccess(titleText) and type(titleText) == "string" then
                            addon:SafeMethod(titleLine, "SetText", addon:FormatData(titleText, config.elements.npcTitle, raw))
                        end
                        SetTooltipLine(tip, index + offset, table.concat(values, " "))
                    else
                        SetTooltipLine(tip, index + offset, table.concat(values, " "))
                    end
                end
            end
        end
    end

    addon:HideLine(tip, "^" .. LEVEL)
    addon:HideLine(tip, "^" .. PVP)
    ColorBorder(tip, config, raw)
    ColorBackground(tip, config, raw)
    GrayForDead(tip, config, unit)
    ShowBigFactionIcon(tip, config, raw)
end

local function ResolveTooltipUnit(unit, guid, context)
    if CanAccess(context) and type(context) == "table" then
        local contextUnit = context.unitToken
        if IsOrdinaryUnit(contextUnit) then return contextUnit end
    end

    local contextGUID
    if CanAccess(context) and type(context) == "table" then contextGUID = context.guid end
    if type(contextGUID) ~= "string" then contextGUID = guid end
    return addon:ResolveUnitToken(unit, contextGUID)
end

local function OnTooltipUnit(_, tip, unit, guid, _, context)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Unit") then return end
    if addon.AllowTrigger and not addon:AllowTrigger("unit", tip) then return end
    if not addon:IsTooltipSafe(tip) then return end

    local started
    if addon.MM and addon.MM.OnCallStart then
        started = addon.MM:OnCallStart("Unit", "tooltip:unit")
    end

    local token = ResolveTooltipUnit(unit, guid, context)
    if not IsOrdinaryUnit(token) then
        if addon.MM and addon.MM.OnCallEnd then addon.MM:OnCallEnd("Unit", started) end
        return
    end

    local raw = addon:GetUnitInfo(token)
    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, token)
    if type(raw) ~= "table" or isPlayer == nil then
        if addon.MM and addon.MM.OnCallEnd then addon.MM:OnCallEnd("Unit", started) end
        return
    end

    local unitConfig = addon.db and addon.db.unit
    if type(unitConfig) == "table" then
        if isPlayer == true and type(unitConfig.player) == "table" then
            PlayerCharacter(tip, token, unitConfig.player, raw)
        elseif isPlayer == false and type(unitConfig.npc) == "table" then
            NonPlayerCharacter(tip, token, unitConfig.npc, raw)
        end
    end

    if addon.MM and addon.MM.OnCallEnd then addon.MM:OnCallEnd("Unit", started) end
end

local function OnModifierStateChanged()
    if addon.AreUnitStatsRestricted and addon:AreUnitStatsRestricted() then return end

    local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    addon:RefreshManagedTooltipsMatching(function(_, context)
        if type(context) ~= "table" then return false end
        if type(unitType) == "number" and context.type == unitType then return true end
        return GetTooltipContextGUID(context) ~= nil
    end, "MODIFIER_STATE_CHANGED")
end

local M = {}

function M:Init()
    self.cbUnit = OnTooltipUnit
    self.cbModifier = OnModifierStateChanged
    self.cbInspectReady = OnInspectReady
    self.cbInvalidate = InvalidateRaidCache
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("Unit", "tooltip:unit", self.cbUnit, "tooltip:unit")
    else
        LibEvent:attachTrigger("tooltip:unit", self.cbUnit)
    end

    if addon.MM and addon.MM.AttachEvent then
        addon.MM:AttachEvent("Unit", "MODIFIER_STATE_CHANGED", self.cbModifier, "MODIFIER_STATE_CHANGED")
        addon.MM:AttachEvent("Unit", "INSPECT_READY", self.cbInspectReady, "INSPECT_READY")
        addon.MM:AttachEvent("Unit", "PLAYER_ENTERING_WORLD", self.cbInvalidate, "PLAYER_ENTERING_WORLD")
        addon.MM:AttachEvent("Unit", "BOSS_KILL", self.cbInvalidate, "BOSS_KILL")
    else
        LibEvent:attachEvent("MODIFIER_STATE_CHANGED", self.cbModifier)
        LibEvent:attachEvent("INSPECT_READY", self.cbInspectReady)
        LibEvent:attachEvent("PLAYER_ENTERING_WORLD", self.cbInvalidate)
        LibEvent:attachEvent("BOSS_KILL", self.cbInvalidate)
    end
end

function M:Disable()
    ClearPendingInspect()
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Unit", M)
end

addon.ColorUnitBorder = ColorBorder
addon.ColorUnitBackground = ColorBackground
