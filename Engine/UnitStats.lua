-- Bounded optional enrichment; native inspect ownership is never cleared.
local _, addon = ...

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
    return addon:SafeGet(tbl, key)
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
    if addon:CanAccessTable(runs) then
        for index = 1, 64 do
            local run = ReadField(runs, index)
            if run == nil then break end
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

local function RaidDifficultyRank(difficultyID)
    if type(difficultyID) ~= "number" then return 0 end
    local _, instanceType, isHeroic, _, displayHeroic, displayMythic, _, isLFR =
        Call(GetDifficultyInfo, difficultyID)

    if displayMythic == true then return 4 end
    if isHeroic == true or displayHeroic == true then return 3 end
    if isLFR == true then return 1 end
    if instanceType == nil or instanceType == "raid" then return 2 end
    return 0
end

local function PreferRaidEntry(previous, difficultyRank, encounterProgress)
    if not previous then return true end
    local previousRank = tonumber(previous.difficultyRank) or 0
    if difficultyRank ~= previousRank then return difficultyRank > previousRank end
    return encounterProgress > previous.encounterProgress
end

local function GetSavedRaidProgress()
    if type(GetNumSavedInstances) ~= "function" or type(GetSavedInstanceInfo) ~= "function" then return nil end

    local now = GetTime and GetTime() or 0
    if type(raidProgressCache) == "table" and now - raidProgressCacheTime < RAID_CACHE_TTL then
        return raidProgressCache
    end

    local count = Call(GetNumSavedInstances)
    if type(count) ~= "number" or count ~= count or count < 1 then
        raidProgressCache = {}
        raidProgressCacheTime = now
        return raidProgressCache
    end

    count = math.min(256, math.floor(count))
    local byName = {}
    for index = 1, count do
        local name, _, _, difficultyID, locked, _, _, isRaid, _, difficultyName,
            numEncounters, encounterProgress = Call(GetSavedInstanceInfo, index)

        if type(name) == "string" and name ~= "" and locked == true and isRaid == true
            and type(numEncounters) == "number" and type(encounterProgress) == "number" then
            local difficultyRank = RaidDifficultyRank(difficultyID)
            local previous = byName[name]
            if PreferRaidEntry(previous, difficultyRank, encounterProgress) then
                byName[name] = {
                    raidName = name,
                    difficultyID = type(difficultyID) == "number" and difficultyID or nil,
                    difficultyRank = difficultyRank,
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
local pendingInspectTimer
local inspectGeneration = 0
local foreignInspectUntil = 0
local requestingInspect = false
local inspectHooksInstalled = false
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

local function ClearPendingInspect()
    inspectGeneration = inspectGeneration + 1
    pendingInspectGUID = nil
    if pendingInspectTimer then
        local timer = pendingInspectTimer
        pendingInspectTimer = nil
        local cancel = addon:SafeGet(timer, "Cancel")
        if type(cancel) == "function" then pcall(cancel, timer) end
    end
    -- ClearInspectPlayer has global ownership. Never clear somebody else's
    -- target, including on disable, timeout or restriction changes.
end

local function ObserveInspectRequest()
    if requestingInspect then return end
    ClearPendingInspect()
    foreignInspectUntil = GetTime() + INSPECT_REQUEST_TIMEOUT
    inspectLastRequest = GetTime()
end

local function InstallInspectHooks()
    if inspectHooksInstalled or type(hooksecurefunc) ~= "function" then return end
    if type(NotifyInspect) ~= "function" or type(ClearInspectPlayer) ~= "function" then return end
    hooksecurefunc("NotifyInspect", ObserveInspectRequest)
    hooksecurefunc("ClearInspectPlayer", function()
        ClearPendingInspect()
        foreignInspectUntil = 0
    end)
    inspectHooksInstalled = true
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
    if InCombatLockdown() or addon:AreUnitStatsRestricted() or InspectUIOwnsChannel()
        or not inspectHooksInstalled or now < foreignInspectUntil then return end
    if type(CanInspect) ~= "function" or addon:SafeCallBoolean(CanInspect, unit) ~= true then return end
    if type(NotifyInspect) ~= "function" or not C_Timer
        or type(C_Timer.NewTimer) ~= "function" then return end

    if pendingInspectGUID then
        if now - inspectLastRequest <= INSPECT_REQUEST_TIMEOUT then return end
        ClearPendingInspect()
    end
    if now - inspectLastRequest <= INSPECT_REQUEST_THROTTLE then return end

    PruneTimedCache(inspectCache, now, INSPECT_CACHE_TTL, INSPECT_CACHE_MAX)
    ClearPendingInspect()
    pendingInspectGUID = guid
    inspectLastRequest = now
    local generation = inspectGeneration
    pendingInspectTimer = C_Timer.NewTimer(INSPECT_REQUEST_TIMEOUT, function()
        if generation == inspectGeneration and pendingInspectGUID == guid then ClearPendingInspect() end
    end)
    if not pendingInspectTimer then ClearPendingInspect(); return end

    requestingInspect = true
    local ok, message = pcall(NotifyInspect, unit)
    requestingInspect = false
    if not ok then ClearPendingInspect(); addon:DoctorLog("lua", "NotifyInspect", message) end
end

local function ResolveInspectUnit(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
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
    if InCombatLockdown() or addon:AreUnitStatsRestricted() or InspectUIOwnsChannel()
        or GetTime() - inspectLastRequest > INSPECT_REQUEST_TIMEOUT then ClearPendingInspect(); return end

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

    ClearPendingInspect()
    addon:RefreshManagedTooltipsMatching(function(_, context)
        return ContextGUID(context) == guid
    end, "INSPECT_READY")
end

local function AddItemLevel(tooltip, isSelf, inspect)
    local level
    if isSelf then
        local _, equipped = Call(GetAverageItemLevel)
        if type(equipped) == "number" and equipped > 0 then level = equipped end
    elseif inspect then level = inspect.ilvl end
    if level then AddStatLine(tooltip, addon.L["tooltip.itemLevel"], string.format("%.1f", level)) end
end

local function AddScore(tooltip, isSelf, summary)
    local score
    if isSelf then score = Call(C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) end
    if type(score) ~= "number" then score = summary and summary.currentSeasonScore end
    if type(score) ~= "number" then return end
    local displayed = tostring(math.floor(score + 0.5))
    local color = Call(C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor, score)
    local red, green, blue = ReadNumber(color, "r"), ReadNumber(color, "g"), ReadNumber(color, "b")
    if red and green and blue then displayed = "|cff" .. addon:GetHexColor(red, green, blue) .. displayed .. "|r" end
    AddStatLine(tooltip, addon.L["tooltip.pveScore"], displayed)
end

local function AddBestKey(tooltip, summary)
    local level, name = GetBestMythicPlusKey(summary)
    if level then AddStatLine(tooltip, addon.L["tooltip.bestKey"], string.format("+%d", level) .. (name and " - " .. name or "")) end
end

local function AddRaidProgress(tooltip)
    for _, raid in ipairs(GetSavedRaidProgress() or {}) do
        local value = string.format("%d/%d", raid.encounterProgress, raid.numEncounters)
        if raid.difficultyName then value = value .. " " .. raid.difficultyName end
        AddStatLine(tooltip, raid.raidName, value)
    end
end

local function AddSpecialization(tooltip, unit, isSelf, inspect, config)
    local specID, role
    if isSelf then
        local index = Call(GetSpecialization)
        if type(index) == "number" then specID = Call(GetSpecializationInfo, index) end
    elseif inspect then specID = inspect.specID end
    if type(specID) == "number" then
        local _, name, _, _, specRole = Call(GetSpecializationInfoByID, specID)
        if type(name) == "string" and name ~= "" then AddStatLine(tooltip, addon.L["tooltip.spec"], name) end
        if type(specRole) == "string" then role = specRole end
    end
    local assigned = Call(UnitGroupRolesAssigned, unit)
    if type(assigned) == "string" and assigned ~= "NONE" then role = assigned end
    if type(role) == "string" and role ~= "NONE" and not config.elements.role.enable then
        AddStatLine(tooltip, addon.L["tooltip.role"], _G[role] or role)
    end
end

function addon:AddPlayerStats(tooltip, unit, config)
    if type(config) ~= "table" or not IsOrdinaryUnit(unit) or self:AreUnitStatsRestricted() then return end
    local isSelf = self:CanCompareUnitTokens(unit, "player") and self:SafeCallBoolean(UnitIsUnit, unit, "player") == true
    local now, guid = GetTime(), GetSafeUnitGUID(unit)
    local inspect = GetCachedInspect(guid, now)
    if not isSelf and not inspect and (config.showItemLevel or config.showSpecialization) then RequestInspect(unit, guid, now) end
    local summary
    if config.showPveScore or config.showBestKey then summary = GetMythicPlusSummary(unit) end
    if config.showItemLevel then AddItemLevel(tooltip, isSelf, inspect) end
    if config.showPveScore then AddScore(tooltip, isSelf, summary) end
    if config.showBestKey then AddBestKey(tooltip, summary) end
    if config.showRaidProgress and isSelf then AddRaidProgress(tooltip) end
    if config.showSpecialization then AddSpecialization(tooltip, unit, isSelf, inspect, config) end
end

local function InvalidateProgressCaches()
    raidProgressCache, raidProgressCacheTime = nil, 0
    wipe(mythicPlusCache)
    addon.InvalidateUnitRosterCache()
end

local function CancelRestrictedWork()
    ClearPendingInspect()
    wipe(inspectCache)
    InvalidateProgressCaches()
end

function addon:EnableUnitStats()
    InstallInspectHooks()
    self.MM:AttachEvent("Unit", "INSPECT_READY", OnInspectReady, "inspect-ready")
    self.MM:AttachEvent("Unit", "PLAYER_ENTERING_WORLD, BOSS_KILL, UPDATE_INSTANCE_INFO, GROUP_ROSTER_UPDATE",
        InvalidateProgressCaches, "progress-cache")
    self.MM:AttachEvent("Unit", "PLAYER_REGEN_DISABLED, ADDON_RESTRICTION_STATE_CHANGED, PLAYER_LEAVING_WORLD",
        CancelRestrictedWork, "inspect-cancel")
end

function addon:DisableUnitStats()
    CancelRestrictedWork()
end
