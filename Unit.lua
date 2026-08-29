local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local C_ChallengeMode = C_ChallengeMode
local C_PlayerInfo = C_PlayerInfo
local C_PaperDollInfo = C_PaperDollInfo

local INSPECT_CACHE_TTL = 300
local INSPECT_CACHE_MAX = 64
local INSPECT_REQUEST_THROTTLE = 2
local INSPECT_REQUEST_TIMEOUT = 5
local MYTHIC_PLUS_CACHE_TTL = 60
local MYTHIC_PLUS_CACHE_MAX = 64
local RAID_CACHE_TTL = 300

local function CanAccess(value)
    return addon:CanAccessValue(value)
end

local function Call(fn, ...)
    if not CanAccess(fn) or type(fn) ~= "function" then return nil end
    if not addon:CanAccessAllValues(...) then return nil end
    return addon:SafeCall("Unit", fn, ...)
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

local function IsOrdinaryUnit(unit)
    return CanAccess(unit)
        and type(unit) == "string"
        and unit ~= ""
        and not addon:IsUnitIdentityRestricted(unit)
end

local function EscapePattern(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("(%W)", "%%%1"))
end

local function AddStatLine(tooltip, label, value)
    if not addon:IsTooltipSafe(tooltip) then return end
    if type(label) ~= "string" or label == "" then return end
    if type(value) ~= "string" and type(value) ~= "number" then return end

    if addon:FindLine(tooltip, "^" .. EscapePattern(label) .. ":") then return end
    addon:SafeMethod(
        tooltip,
        "AddLine",
        string.format("%s: |cffffffff%s|r", label, tostring(value)),
        0,
        1,
        0.8
    )
end

local mythicPlusCache = {}

local function PruneTimedCache(cache, now, ttl, maximum)
    local count = 0
    local oldestKey, oldestTime
    for key, entry in pairs(cache) do
        local entryTime = type(entry) == "table" and entry.time or nil
        if type(entryTime) ~= "number" or now - entryTime > ttl then
            cache[key] = nil
        else
            count = count + 1
            if oldestTime == nil or entryTime < oldestTime then
                oldestKey = key
                oldestTime = entryTime
            end
        end
    end
    if count >= maximum and oldestKey then cache[oldestKey] = nil end
end

local function SanitizeMythicPlusSummary(summary)
    if not CanAccess(summary) or type(summary) ~= "table" then return nil end

    local clean = { runs = {} }
    local currentSeasonScore = ReadNumber(summary, "currentSeasonScore")
    if currentSeasonScore ~= nil then clean.currentSeasonScore = currentSeasonScore end

    local runs = ReadField(summary, "runs")
    if type(runs) == "table" then
        for _, run in ipairs(runs) do
            if CanAccess(run) and type(run) == "table" then
                local level = ReadNumber(run, "bestRunLevel")
                local score = ReadNumber(run, "bestRunScore") or ReadNumber(run, "mapScore")
                local mapID = ReadNumber(run, "challengeModeID")
                if level ~= nil or score ~= nil or mapID ~= nil then
                    clean.runs[#clean.runs + 1] = {
                        bestRunLevel = level,
                        bestRunScore = score,
                        challengeModeID = mapID,
                    }
                end
            end
        end
    end

    if clean.currentSeasonScore == nil and #clean.runs == 0 then return nil end
    return clean
end

local function GetMythicPlusSummary(unit)
    if not IsOrdinaryUnit(unit) then return nil end
    if not C_PlayerInfo or type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) ~= "function" then return nil end

    local guid = Call(UnitGUID, unit)
    if type(guid) ~= "string" or guid == "" then return nil end

    local now = GetTime and GetTime() or 0
    local cached = mythicPlusCache[guid]
    if type(cached) == "table" and type(cached.time) == "number"
        and now - cached.time <= MYTHIC_PLUS_CACHE_TTL then
        return cached.summary
    end

    PruneTimedCache(mythicPlusCache, now, MYTHIC_PLUS_CACHE_TTL, MYTHIC_PLUS_CACHE_MAX)
    local summary = SanitizeMythicPlusSummary(Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit))
    if not summary then return nil end

    mythicPlusCache[guid] = { summary = summary, time = now }
    return summary
end

local function GetBestMythicPlusKey(summary)
    if type(summary) ~= "table" or type(summary.runs) ~= "table" then return nil end

    local bestLevel, bestMapID, bestScore
    for _, run in ipairs(summary.runs) do
        local level = type(run) == "table" and run.bestRunLevel or nil
        local score = type(run) == "table" and run.bestRunScore or nil
        local mapID = type(run) == "table" and run.challengeModeID or nil
        if type(level) == "number" then
            local replace = bestLevel == nil or level > bestLevel
            if not replace and level == bestLevel and type(score) == "number" then
                replace = bestScore == nil or score > bestScore
            end
            if replace then
                bestLevel, bestMapID, bestScore = level, mapID, score
            end
        end
    end
    if bestLevel == nil then return nil end

    local mapName
    if type(bestMapID) == "number" and C_ChallengeMode
        and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name = Call(C_ChallengeMode.GetMapUIInfo, bestMapID)
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

local function GetSavedRaidProgress()
    if type(GetNumSavedInstances) ~= "function" or type(GetSavedInstanceInfo) ~= "function" then return nil end

    local now = GetTime and GetTime() or 0
    if type(raidProgressCache) == "table" and now - raidProgressCacheTime < RAID_CACHE_TTL then
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
        local name, _, _, difficultyID, locked, _, _, isRaid, _, difficultyName,
            numEncounters, encounterProgress = Call(GetSavedInstanceInfo, index)

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

    local result = {}
    for _, entry in pairs(byName) do result[#result + 1] = entry end
    table.sort(result, function(left, right) return left.raidName < right.raidName end)
    raidProgressCache = result
    raidProgressCacheTime = now
    return result
end

local inspectCache = {}
local pendingInspectGUID
local pendingInspectUnit
local inspectLastRequest = -math.huge

local function GetSafeUnitGUID(unit)
    if not IsOrdinaryUnit(unit) then return nil end
    local guid = Call(UnitGUID, unit)
    if type(guid) == "string" and guid ~= "" then return guid end
end

local function InspectUIOwnsChannel()
    if addon:IsObjectAccessible(InspectFrame) and addon:SafeMethod(InspectFrame, "IsShown") == true then
        return true
    end
    if addon:IsObjectAccessible(PlayerSpellsFrame)
        and addon:SafeMethod(PlayerSpellsFrame, "IsInspecting") == true then
        return true
    end
    return false
end

local function ClearPendingInspect(clearNative)
    pendingInspectGUID = nil
    pendingInspectUnit = nil
    if clearNative == true and type(ClearInspectPlayer) == "function" and not InspectUIOwnsChannel() then
        pcall(ClearInspectPlayer)
    end
end

local function GetCachedInspect(guid, now)
    if type(guid) ~= "string" or guid == "" then return nil end
    local entry = inspectCache[guid]
    if type(entry) ~= "table" then return nil end
    if type(entry.time) ~= "number" or now - entry.time > INSPECT_CACHE_TTL then
        inspectCache[guid] = nil
        return nil
    end
    return entry
end

local function RequestInspect(unit, guid, now)
    if not IsOrdinaryUnit(unit) or type(guid) ~= "string" or guid == "" then return end
    if InCombatLockdown() or InspectUIOwnsChannel() then return end
    if type(CanInspect) ~= "function" or addon:SafeCallBoolean(CanInspect, unit) ~= true then return end
    if type(NotifyInspect) ~= "function" then return end

    if pendingInspectGUID then
        if now - inspectLastRequest <= INSPECT_REQUEST_TIMEOUT then return end
        ClearPendingInspect(true)
    end
    if now - inspectLastRequest <= INSPECT_REQUEST_THROTTLE then return end

    PruneTimedCache(inspectCache, now, INSPECT_CACHE_TTL, INSPECT_CACHE_MAX)
    pendingInspectGUID = guid
    pendingInspectUnit = unit
    inspectLastRequest = now
    local ok = pcall(NotifyInspect, unit)
    if not ok then ClearPendingInspect(false) end
end

local function ResolveInspectUnit(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    if IsOrdinaryUnit(pendingInspectUnit) and GetSafeUnitGUID(pendingInspectUnit) == guid then
        return pendingInspectUnit
    end
    local unit = addon:ResolveUnitToken(nil, guid)
    if IsOrdinaryUnit(unit) and GetSafeUnitGUID(unit) == guid then return unit end
end

local function ContextGUID(context)
    if type(context) ~= "table" then return nil end
    if type(context.guid) == "string" and context.guid ~= "" then return context.guid end
    return GetSafeUnitGUID(context.unitToken)
end

local function OnInspectReady(_, guid)
    if not CanAccess(guid) or type(guid) ~= "string" or guid == "" then return end
    if guid ~= pendingInspectGUID then return end

    local unit = ResolveInspectUnit(guid)
    if unit then
        local itemLevel = C_PaperDollInfo and type(C_PaperDollInfo.GetInspectItemLevel) == "function"
            and Call(C_PaperDollInfo.GetInspectItemLevel, unit) or nil
        local specID = type(GetInspectSpecialization) == "function"
            and Call(GetInspectSpecialization, unit) or nil

        if type(itemLevel) ~= "number" or itemLevel <= 0 then itemLevel = nil end
        if type(specID) ~= "number" or specID <= 0 then specID = nil end

        if itemLevel ~= nil or specID ~= nil then
            local now = GetTime and GetTime() or 0
            PruneTimedCache(inspectCache, now, INSPECT_CACHE_TTL, INSPECT_CACHE_MAX)
            inspectCache[guid] = { ilvl = itemLevel, specID = specID, time = now }
        end
    end

    ClearPendingInspect(true)
    addon:RefreshManagedTooltipsMatching(function(_, context)
        return ContextGUID(context) == guid
    end, "INSPECT_READY")
end

local function ColorBorder(tooltip, config, raw)
    if not addon:IsTooltipSafe(tooltip) or type(config) ~= "table" then return end
    local mode = config.coloredBorder
    local colorFunction = addon.colorfunc and addon.colorfunc[mode]
    if type(colorFunction) == "function" then
        local ok, red, green, blue = pcall(colorFunction, raw)
        if ok and type(red) == "number" and type(green) == "number" and type(blue) == "number" then
            LibEvent:trigger("tooltip.style.border.color", tooltip, red, green, blue)
            return
        end
    end

    if type(mode) == "string" and mode ~= "default" then
        local red, green, blue = addon:GetRGBColor(mode)
        LibEvent:trigger("tooltip.style.border.color", tooltip, red, green, blue)
        return
    end

    local color = addon.db and addon.db.general and addon.db.general.borderColor
    if type(color) == "table" then
        LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(color))
    end
end

local function ColorBackground(tooltip, config, raw)
    if not addon:IsTooltipSafe(tooltip) or type(config) ~= "table" then return end
    local background = config.background
    if type(background) ~= "table" then return end

    local mode = background.colorfunc
    if mode == "default" or mode == "" or mode == "inherit" then
        local color = addon.db and addon.db.general and addon.db.general.background
        if type(color) == "table" then
            local red, green, blue, alpha = unpack(color)
            if type(background.alpha) == "number" then alpha = background.alpha end
            LibEvent:trigger("tooltip.style.background", tooltip, red, green, blue, alpha)
        end
        return
    end

    local colorFunction = addon.colorfunc and addon.colorfunc[mode]
    if type(colorFunction) ~= "function" then return end
    local ok, red, green, blue = pcall(colorFunction, raw)
    if ok and type(red) == "number" and type(green) == "number" and type(blue) == "number" then
        LibEvent:trigger("tooltip.style.background", tooltip, red, green, blue,
            type(background.alpha) == "number" and background.alpha or 0.8)
    end
end

local function GrayForDead(tooltip, config, unit)
    if type(config) ~= "table" or config.grayForDead ~= true then return end
    if addon:SafeCallBoolean(UnitIsDeadOrGhost, unit) ~= true then return end

    LibEvent:trigger("tooltip.style.border.color", tooltip, 0.6, 0.6, 0.6)
    LibEvent:trigger("tooltip.style.background", tooltip, 0.1, 0.1, 0.1)

    local name = addon:SafeMethod(tooltip, "GetName")
    local lineCount = addon:SafeMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return end
    for index = 1, lineCount do
        local line = _G[name .. "TextLeft" .. index]
        if addon:IsObjectAccessible(line) then
            local text = addon:SafeMethod(line, "GetText")
            if type(text) == "string" then
                addon:SafeMethod(line, "SetText", text:gsub("|cff%x%x%x%x%x%x", "|cffaaaaaa"))
            end
            addon:SafeMethod(line, "SetTextColor", 0.7, 0.7, 0.7)
        end
    end
end

local function ShowBigFactionIcon(tooltip, config, raw)
    local element = type(config) == "table" and type(config.elements) == "table"
        and config.elements.factionBig or nil
    local faction = type(raw) == "table" and raw.factionGroup or nil
    local icon = addon:GetBigFactionIcon(tooltip, true)
    if not addon:IsObjectAccessible(icon) then return end

    if type(element) == "table" and element.enable == true
        and (faction == "Alliance" or faction == "Horde") then
        addon:SafeMethod(icon, "SetTexture", "Interface\\Timer\\" .. faction .. "-Logo")
        addon:SafeMethod(icon, "Show")
    else
        addon:SafeMethod(icon, "Hide")
    end
end

local function HideLineRange(tooltip, first, last)
    local name = addon:SafeMethod(tooltip, "GetName")
    local lineCount = addon:SafeMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return end
    last = math.min(last or lineCount, lineCount)
    for index = first, last do
        local line = _G[name .. "TextLeft" .. index]
        if addon:IsObjectAccessible(line) then addon:SafeMethod(line, "SetText", nil) end
    end
end

local function SetTooltipLine(tooltip, index, text)
    if type(text) ~= "string" then return end
    local line = addon:GetLine(tooltip, index)
    if addon:IsObjectAccessible(line) then addon:SafeMethod(line, "SetText", strtrim(text)) end
end

local function AddPlayerStats(tooltip, unit, config)
    if type(config) ~= "table" or not IsOrdinaryUnit(unit) or addon:AreUnitStatsRestricted() then return end

    local isSelf = addon:CanCompareUnitTokens(unit, "player")
        and addon:SafeCallBoolean(UnitIsUnit, unit, "player") == true
    local guid = GetSafeUnitGUID(unit)
    local now = GetTime and GetTime() or 0
    local inspect = GetCachedInspect(guid, now)
    local summary
    if config.showPveScore == true or config.showBestKey == true then
        summary = GetMythicPlusSummary(unit)
    end

    if not isSelf and not inspect then RequestInspect(unit, guid, now) end

    if config.showItemLevel == true then
        local itemLevel
        if isSelf then
            local _, equipped = Call(GetAverageItemLevel)
            if type(equipped) == "number" and equipped > 0 then itemLevel = equipped end
        elseif inspect and type(inspect.ilvl) == "number" then
            itemLevel = inspect.ilvl
        end
        if itemLevel then
            AddStatLine(tooltip, addon.L["tooltip.itemLevel"] or "Item Level", string.format("%.1f", itemLevel))
        end
    end

    if config.showPveScore == true then
        local score
        if isSelf and C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
            score = Call(C_ChallengeMode.GetOverallDungeonScore)
        end
        if type(score) ~= "number" then score = type(summary) == "table" and summary.currentSeasonScore or nil end
        if type(score) == "number" then
            local displayed = tostring(math.floor(score + 0.5))
            if C_ChallengeMode and type(C_ChallengeMode.GetDungeonScoreRarityColor) == "function" then
                local color = Call(C_ChallengeMode.GetDungeonScoreRarityColor, score)
                local red, green, blue = ReadNumber(color, "r"), ReadNumber(color, "g"), ReadNumber(color, "b")
                if red and green and blue then
                    displayed = string.format("|cff%s%s|r", addon:GetHexColor(red, green, blue), displayed)
                end
            end
            AddStatLine(tooltip, addon.L["tooltip.pveScore"] or "PvE Score", displayed)
        end
    end

    if config.showBestKey == true then
        local level, mapName = GetBestMythicPlusKey(summary)
        if level then
            local value = string.format("+%d", level)
            if mapName then value = value .. " - " .. mapName end
            AddStatLine(tooltip, addon.L["tooltip.bestKey"] or "Best M+ Key", value)
        end
    end

    if config.showRaidProgress == true and isSelf then
        for _, raid in ipairs(GetSavedRaidProgress() or {}) do
            local value = string.format("%d/%d", raid.encounterProgress, raid.numEncounters)
            if raid.difficultyName then value = value .. " " .. raid.difficultyName end
            AddStatLine(tooltip, raid.raidName, value)
        end
    end

    local role = Call(UnitGroupRolesAssigned, unit)
    if type(role) ~= "string" then role = nil end
    local specID
    if isSelf then
        local specIndex = Call(GetSpecialization)
        if type(specIndex) == "number" then specID = Call(GetSpecializationInfo, specIndex) end
    elseif inspect then
        specID = inspect.specID
    end

    if type(specID) == "number" and type(GetSpecializationInfoByID) == "function" then
        local _, specName, _, _, specRole = Call(GetSpecializationInfoByID, specID)
        if type(specName) == "string" and specName ~= "" then
            AddStatLine(tooltip, addon.L["tooltip.spec"] or "Spec", specName)
        end
        if (role == nil or role == "NONE") and type(specRole) == "string" then role = specRole end
    end
    if type(role) == "string" and role ~= "NONE" then
        AddStatLine(tooltip, addon.L["tooltip.role"] or "Role", _G[role] or role)
    end
end

local function PlayerCharacter(tooltip, unit, config, raw)
    local data = addon:GetUnitData(unit, config.elements, raw)
    HideLineRange(tooltip, 2, 3)
    addon:HideLine(tooltip, "^" .. LEVEL)
    addon:HideLine(tooltip, "^" .. FACTION_ALLIANCE)
    addon:HideLine(tooltip, "^" .. FACTION_HORDE)
    addon:HideLine(tooltip, "^" .. PVP)

    for index, values in ipairs(data) do
        if type(values) == "table" then SetTooltipLine(tooltip, index, table.concat(values, " ")) end
    end

    ColorBorder(tooltip, config, raw)
    ColorBackground(tooltip, config, raw)
    GrayForDead(tooltip, config, unit)
    ShowBigFactionIcon(tooltip, config, raw)
    AddPlayerStats(tooltip, unit, config)
end

local function NonPlayerCharacter(tooltip, unit, config, raw)
    local levelLine = addon:FindLine(tooltip, "^" .. LEVEL)
    local lineCount = addon:SafeMethod(tooltip, "NumLines")
    if levelLine or (type(lineCount) == "number" and lineCount > 1) then
        local data = addon:GetUnitData(unit, config.elements, raw)
        local titleLine = addon:GetNpcTitle(tooltip)
        local keepTitle = type(config.elements) == "table"
            and type(config.elements.npcTitle) == "table"
            and config.elements.npcTitle.enable == true
            and addon:IsObjectAccessible(titleLine)
        local offset = keepTitle and 1 or 0

        for index, values in ipairs(data) do
            if type(values) == "table" then
                if index == 1 then
                    SetTooltipLine(tooltip, index, table.concat(values, " "))
                elseif index == 2 and keepTitle then
                    local titleText = addon:SafeMethod(titleLine, "GetText")
                    if type(titleText) == "string" then
                        addon:SafeMethod(titleLine, "SetText",
                            addon:FormatData(titleText, config.elements.npcTitle, raw))
                    end
                    SetTooltipLine(tooltip, index + offset, table.concat(values, " "))
                else
                    SetTooltipLine(tooltip, index + offset, table.concat(values, " "))
                end
            end
        end
    end

    addon:HideLine(tooltip, "^" .. LEVEL)
    addon:HideLine(tooltip, "^" .. PVP)
    ColorBorder(tooltip, config, raw)
    ColorBackground(tooltip, config, raw)
    GrayForDead(tooltip, config, unit)
    ShowBigFactionIcon(tooltip, config, raw)
end

local function ResolveTooltipUnit(tooltip, unit, guid, context)
    if type(context) == "table" and IsOrdinaryUnit(context.unitToken) then return context.unitToken end
    local contextGUID = type(context) == "table" and context.guid or guid
    return addon:ResolveUnitToken(unit, contextGUID)
end

local function OnTooltipUnit(_, tooltip, unit, guid, _, context)
    if not addon:IsTooltipSafe(tooltip) or not addon:AllowTrigger("unit", tooltip) then return end
    local token = ResolveTooltipUnit(tooltip, unit, guid, context)
    if not IsOrdinaryUnit(token) then return end

    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, token)
    if isPlayer == nil then return end
    local unitConfig = addon.db and addon.db.unit
    local config = type(unitConfig) == "table" and (isPlayer and unitConfig.player or unitConfig.npc) or nil
    if type(config) ~= "table" then return end

    local raw = addon:GetUnitInfo(token, config.elements)
    if type(raw) ~= "table" then return end
    if isPlayer then PlayerCharacter(tooltip, token, config, raw)
    else NonPlayerCharacter(tooltip, token, config, raw) end
end

local function RefreshUnitTooltips()
    local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    addon:RefreshManagedTooltipsMatching(function(_, context)
        return type(context) == "table" and context.type == unitType
    end, "MODIFIER_STATE_CHANGED")
end

local function InvalidateProgressCaches()
    raidProgressCache = nil
    raidProgressCacheTime = 0
    wipe(mythicPlusCache)
end

local M = {}

function M:Init()
    self.cbUnit = OnTooltipUnit
    self.cbModifier = RefreshUnitTooltips
    self.cbInspectReady = OnInspectReady
    self.cbInvalidate = InvalidateProgressCaches
end

function M:Enable()
    addon.MM:AttachTrigger("Unit", "tooltip:unit", self.cbUnit, "tooltip:unit")
    addon.MM:AttachEvent("Unit", "MODIFIER_STATE_CHANGED", self.cbModifier, "MODIFIER_STATE_CHANGED")
    addon.MM:AttachEvent("Unit", "INSPECT_READY", self.cbInspectReady, "INSPECT_READY")
    addon.MM:AttachEvent("Unit", "PLAYER_ENTERING_WORLD, BOSS_KILL, UPDATE_INSTANCE_INFO",
        self.cbInvalidate, "progress-cache")
end

function M:Disable()
    ClearPendingInspect(true)
    wipe(inspectCache)
    wipe(mythicPlusCache)
    InvalidateProgressCaches()
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Unit", M)
addon.ColorUnitBorder = ColorBorder
addon.ColorUnitBackground = ColorBackground
