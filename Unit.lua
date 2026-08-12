local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local C_ChallengeMode = C_ChallengeMode
local C_PlayerInfo = C_PlayerInfo
local C_PaperDollInfo = C_PaperDollInfo

local function AddStatLine(tip, label, value)
    if (addon.IsSecret and addon:IsSecret(value)) then return end
    if (value == nil) then return end
    if (type(label) ~= "string") then return end
    if (tip.IsForbidden and tip:IsForbidden()) then return end
    local keyword = label .. ":"
    if (addon:FindLine(tip, keyword)) then return end
    tip:AddLine(format("%s: |cffffffff%s|r", label, value), 0, 1, 0.8)
end



local function GetBestMythicPlusKey(unit)
    if (addon:IsSecret(unit) or not unit) then return end
    if (not C_PlayerInfo) or (not C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then return end

    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
    if (addon:IsSecret(summary) or not summary) then return end

    local runs = summary.runs
    if (type(runs) ~= "table") then return end

    local bestLevel, bestModeID, bestScore

    for _, run in ipairs(runs) do
        if (type(run) == "table") then
            local lvl = run.bestRunLevel
            if (not addon:IsSecret(lvl) and lvl ~= nil and type(lvl) == "number") then
                local score = run.bestRunScore or run.mapScore
                if (addon:IsSecret(score)) then score = nil end

                if (not bestLevel) or (lvl > bestLevel) or (lvl == bestLevel and score and bestScore and score > bestScore) then
                    bestLevel = lvl
                    bestModeID = run.challengeModeID
                    bestScore = score
                end
            end
        end
    end

    if (not bestLevel) then return end

    local mapName
    if (not addon:IsSecret(bestModeID) and bestModeID ~= nil and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then
        local name = C_ChallengeMode.GetMapUIInfo(bestModeID)
        if (type(name) == "string") then
            mapName = name
        end
    end

    return bestLevel, mapName
end

local raidProgressCache = nil
local raidProgressCacheTime = 0
-- Возвращает таблицу всех сохранённых рейдовых прогрессов (лучший по сложности на каждый рейд).
local function GetAllSavedRaidProgress()
    if (not GetNumSavedInstances) or (not GetSavedInstanceInfo) then return end
    local now = GetTime and GetTime() or 0
    if raidProgressCache and (now - raidProgressCacheTime < 300) then
        return raidProgressCache
    end

    local n = GetNumSavedInstances()
    if (addon:IsSecret(n) or type(n) ~= "number") then return end

    local raids = {}  -- raidName → best entry
    for i = 1, n do
        local name, _, _, difficultyId, locked, _, _, isRaid, _, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if (addon:IsSecret(name)) then name = nil end
        if (name and isRaid and locked) then
            if (not addon:IsSecret(numEncounters)) and (not addon:IsSecret(encounterProgress))
                and type(numEncounters) == "number" and type(encounterProgress) == "number" then
                local prev = raids[name]
                if (not prev)
                    or (type(difficultyId) == "number" and type(prev.difficultyId) == "number" and difficultyId > prev.difficultyId)
                    or (encounterProgress > prev.encounterProgress) then
                    raids[name] = {
                        raidName = name,
                        difficultyId = difficultyId,
                        difficultyName = (not addon:IsSecret(difficultyName) and difficultyName) or nil,
                        numEncounters = numEncounters,
                        encounterProgress = encounterProgress,
                    }
                end
            end
        end
    end

    raidProgressCache = raids
    raidProgressCacheTime = now
    return raids
end

local function InvalidateRaidCache()
    raidProgressCache = nil
    raidProgressCacheTime = 0
end
local inspectCache = {}
local pendingInspect = nil
local pendingInspectUnit = nil
local inspectLastRequest = 0

local function GetSafeUnitGUID(unit)
    if (addon:IsSecret(unit) or type(unit) ~= "string" or unit == "") then
        return nil
    end
    local guid = UnitGUID(unit)
    if (addon:IsSecret(guid) or type(guid) ~= "string" or guid == "") then
        return nil
    end
    return guid
end

local function GetTooltipContextGUID(context)
    local guid = context and context.guid
    if (not addon:IsSecret(guid) and type(guid) == "string" and guid ~= "") then
        return guid
    end
    return GetSafeUnitGUID(context and context.unitToken)
end

local function ResolveInspectUnit(guid)
    if (type(guid) ~= "string" or guid == "") then
        return nil
    end

    if (GetSafeUnitGUID(pendingInspectUnit) == guid) then
        return pendingInspectUnit
    end

    local unit = addon:ResolveUnitToken(nil, guid)
    if (GetSafeUnitGUID(unit) == guid) then
        return unit
    end

    return nil
end

local function ShouldClearInspectTarget()
    if (InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown()) then
        return false
    end
    if (PlayerSpellsFrame and PlayerSpellsFrame.IsInspecting and PlayerSpellsFrame:IsInspecting()) then
        return false
    end
    return true
end

LibEvent:attachEvent("INSPECT_READY", function(self, guid)
    if (addon:IsSecret(guid)) then guid = nil end
    if (not guid or guid ~= pendingInspect) then return end

    local unit = ResolveInspectUnit(guid)
    if (unit) then
        local ilvl
        if (C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) then
            ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
        end

        local specID
        if (GetInspectSpecialization) then
            specID = GetInspectSpecialization(unit)
        end

        if (addon:IsSecret(ilvl)) then ilvl = nil end
        if (addon:IsSecret(specID)) then specID = nil end
        if (ilvl == 0) then ilvl = nil end

        inspectCache[guid] = {
            ilvl = ilvl,
            specID = specID,
            time = GetTime and GetTime() or 0,
        }
    end

    pendingInspect = nil
    pendingInspectUnit = nil

    if (ClearInspectPlayer and ShouldClearInspectTarget()) then
        ClearInspectPlayer()
    end

    if (addon.RefreshManagedTooltipsMatching) then
        addon:RefreshManagedTooltipsMatching(function(tip, context)
            return GetTooltipContextGUID(context) == guid
        end, "INSPECT_READY")
    end
end)

-- Adds stats that are safe to compute locally (no inspection or hidden data).
-- Midnight (12.0+) can return SecretValue for some APIs; we guard every output.
local function AddPlayerStats(tip, unit)
    local playerCfg = addon.db and addon.db.unit and addon.db.unit.player
    if (not playerCfg) then return end

    local isSelf = false
    local guid = nil
    if (not addon:IsSecret(unit) and type(unit) == "string") then
        local same = UnitIsUnit(unit, "player")
        if (addon:IsSecret(same)) then same = false end
        isSelf = same and true or false
        guid = UnitGUID(unit)
        if (addon:IsSecret(guid)) then guid = nil end
    end

    local cache = guid and inspectCache[guid] or nil
    local now = GetTime and GetTime() or 0
    if cache and (now - cache.time > 300) then cache = nil end

    if (playerCfg.showItemLevel) then
        if (isSelf) then
            local overall, equipped = GetAverageItemLevel()
            if (not addon:IsSecret(equipped) and type(equipped) == "number") then
                local label = (addon.L and addon.L["tooltip.itemLevel"]) or "Item Level"
                AddStatLine(tip, label, format("%.1f", equipped))
            end
        else
            local ilvl
            if cache and cache.ilvl then
                ilvl = cache.ilvl
            elseif C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
                if CanInspect and CanInspect(unit) then
                    if pendingInspect ~= guid or pendingInspectUnit ~= unit or (now - inspectLastRequest > 2) then
                        pendingInspect = guid
                        pendingInspectUnit = unit
                        inspectLastRequest = now
                        NotifyInspect(unit)
                    end
                end
            end
            
            if ilvl and type(ilvl) == "number" and ilvl > 0 then
                local label = (addon.L and addon.L["tooltip.itemLevel"]) or "Item Level"
                AddStatLine(tip, label, format("%.1f", ilvl))
            end
        end
    end

    if (playerCfg.showPveScore) then
        local score
        if (isSelf and C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) then
            score = C_ChallengeMode.GetOverallDungeonScore()
        elseif (not isSelf and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then
            local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
            if (addon:IsSecret(summary)) then summary = nil end
            if (type(summary) == "table") then
                score = summary.currentSeasonScore
            end
        end

        if (not addon:IsSecret(score) and score ~= nil and type(score) == "number") then
            local colored = tostring(score)
            if (C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor) then
                local color = C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if (color and color.r and color.g and color.b) then
                    local hex = addon:GetHexColor(color)
                    colored = ("|cff" .. hex .. "%d|r"):format(score)
                end
            end
            local label = (addon.L and addon.L["tooltip.pveScore"]) or "PvE Score"
            AddStatLine(tip, label, colored)
        end
    end

    if (playerCfg.showBestKey) then
        local level, mapName = GetBestMythicPlusKey(unit)
        if (level ~= nil and type(level) == "number") then
            local label = (addon.L and addon.L["tooltip.bestKey"]) or "Best M+ Key"
            local value = ("+%d"):format(level)
            if (mapName) then
                value = value .. " - " .. mapName
            end
            AddStatLine(tip, label, value)
        end
    end

    if (playerCfg.showRaidProgress) then
        if (isSelf) then
            local raids = GetAllSavedRaidProgress()
            if (raids) then
                for _, raid in pairs(raids) do
                    if (raid.numEncounters and raid.encounterProgress) then
                        local value = ("%d/%d"):format(raid.encounterProgress, raid.numEncounters)
                        if (raid.difficultyName) then
                            value = value .. " " .. raid.difficultyName
                        end
                        AddStatLine(tip, raid.raidName, value)
                    end
                end
            end
        end
    end

    -- Spec and Role
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if (addon:IsSecret(role)) then role = nil end
    
    local specID
    if isSelf then
        if GetSpecialization then
            local specIndex = GetSpecialization()
            if specIndex and GetSpecializationInfo then
                specID = GetSpecializationInfo(specIndex)
            end
        end
    else
        if cache and cache.specID then
            specID = cache.specID
        end
    end
    
    if (addon:IsSecret(specID)) then specID = nil end
    
    if specID and GetSpecializationInfoByID then
        local id, name, description, icon, specRole = GetSpecializationInfoByID(specID)
        if not addon:IsSecret(name) and name then
            local label = (addon.L and addon.L["tooltip.spec"]) or "Spec"
            AddStatLine(tip, label, name)
            if not role or role == "NONE" then
                role = specRole
            end
        end
    end

    if role and role ~= "NONE" then
        local label = (addon.L and addon.L["tooltip.role"]) or "Role"
        AddStatLine(tip, label, _G[role] or role)
    end
end

local function strip(text)
    if (addon:IsSecret(text) or type(text) ~= "string") then
        return ""
    end
    return (text:gsub("%s+([|%x%s]+)<trim>", "%1"))
end

local function ColorBorder(tip, config, raw)
    if (config.coloredBorder and addon.colorfunc[config.coloredBorder]) then
        local r, g, b = addon.colorfunc[config.coloredBorder](raw)
        LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
    elseif (type(config.coloredBorder) == "string" and config.coloredBorder ~= "default") then
        local r, g, b = addon:GetRGBColor(config.coloredBorder)
        if (r and g and b) then
            LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
        end
    else
        LibEvent:trigger("tooltip.style.border.color", tip, unpack(addon.db.general.borderColor))
    end
end

local function ColorBackground(tip, config, raw)
    local bg = config.background
    if not bg then return end
    if (bg.colorfunc == "default" or bg.colorfunc == "" or bg.colorfunc == "inherit") then
        local r, g, b, a = unpack(addon.db.general.background)
        a = bg.alpha or a
        LibEvent:trigger("tooltip.style.background", tip, r, g, b, a)
        return
    end
    if (addon.colorfunc[bg.colorfunc]) then
        local r, g, b = addon.colorfunc[bg.colorfunc](raw)
        local a = bg.alpha or 0.8
        LibEvent:trigger("tooltip.style.background", tip, r, g, b, a)
    end
end

local function GrayForDead(tip, config, unit)
    local dead = UnitIsDeadOrGhost(unit)
    if (addon:IsSecret(dead)) then dead = nil end
    if (not config.grayForDead or not dead) then return end

    local name = tip and tip.GetName and tip:GetName()
    if (not name) then
        -- Only named tooltip templates expose $parentTextLeftN; avoid hard errors.
        return
    end

    LibEvent:trigger("tooltip.style.border.color", tip, 0.6, 0.6, 0.6)
    LibEvent:trigger("tooltip.style.background", tip, 0.1, 0.1, 0.1)

    for i = 1, tip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        if (line) then
            local text = line:GetText()
            if (not addon:IsSecret(text) and text) then
                text = (text or ""):gsub("|cff%x%x%x%x%x%x", "|cffaaaaaa")
                line:SetText(text)
            end
            line:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

local function ShowBigFactionIcon(tip, config, raw)
    if (config.elements.factionBig and config.elements.factionBig.enable and tip.BigFactionIcon and (raw.factionGroup=="Alliance" or raw.factionGroup == "Horde")) then
        tip.BigFactionIcon:Show()
        tip.BigFactionIcon:SetTexture("Interface\\Timer\\".. raw.factionGroup .."-Logo")
	    -- Width/Wrap handled centrally in Engine/Layout.
    end
end

local function PlayerCharacter(tip, unit, config, raw)
    local data = addon:GetUnitData(unit, config.elements, raw)
    addon:HideLines(tip, 2, 3)
    addon:HideLine(tip, "^"..LEVEL)
    addon:HideLine(tip, "^"..FACTION_ALLIANCE)
    addon:HideLine(tip, "^"..FACTION_HORDE)
    addon:HideLine(tip, "^"..PVP)
    for i, v in ipairs(data) do
        addon:GetLine(tip,i):SetText(strip(table.concat(v, " ")))
    end
    ColorBorder(tip, config, raw)
    ColorBackground(tip, config, raw)
    GrayForDead(tip, config, unit)
    ShowBigFactionIcon(tip, config, raw)
    AddPlayerStats(tip, unit)
end

local function NonPlayerCharacter(tip, unit, config, raw)
    local levelLine = addon:FindLine(tip, "^"..LEVEL)
    if (levelLine or tip:NumLines() > 1) then
        local data = addon:GetUnitData(unit, config.elements, raw)
        local titleLine = addon:GetNpcTitle(tip)
        local increase = 0
        for i, v in ipairs(data) do
            if (i == 1) then
                addon:GetLine(tip,i):SetText(table.concat(v, " "))
            end
            if (i == 2) then
                if (config.elements.npcTitle.enable and titleLine) then
                    local tt = titleLine:GetText()
                    if (not addon:IsSecret(tt) and tt) then
                        titleLine:SetText(addon:FormatData(tt, config.elements.npcTitle, raw))
                    end
                    increase = 1
                end
                i = i + increase
                addon:GetLine(tip,i):SetText(table.concat(v, " "))
            elseif ( i > 2) then
                i = i + increase
                addon:GetLine(tip,i):SetText(table.concat(v, " "))
            end
        end
    end
    addon:HideLine(tip, "^"..LEVEL)
    addon:HideLine(tip, "^"..PVP)
    ColorBorder(tip, config, raw)
    ColorBackground(tip, config, raw)
    GrayForDead(tip, config, unit)
    ShowBigFactionIcon(tip, config, raw)
    -- Width sizing: native Blizzard C API (no custom width manipulation).
end

local function OnTooltipUnit(self, tip, unit, guid, _, context)
    if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Unit")) then return end
    if (addon.AllowTrigger and not addon:AllowTrigger("unit", tip)) then return end
    local started
    if (addon.MM and addon.MM.OnCallStart) then started = addon.MM:OnCallStart("Unit", "tooltip:unit") end
    local token = context and context.unitToken or unit
    if (type(token) ~= "string") then
        token = addon:ResolveUnitToken(unit, (context and context.guid) or guid)
    end
    if (not token) then
        if (addon.MM and addon.MM.OnCallEnd) then addon.MM:OnCallEnd("Unit", started) end
        return
    end

    local raw = addon:GetUnitInfo(token)
    local ok, isPlayer = pcall(UnitIsPlayer, token)
    if (not ok or addon:IsSecret(isPlayer)) then isPlayer = nil end
    if (isPlayer) then
        PlayerCharacter(tip, token, addon.db.unit.player, raw)
    else
        NonPlayerCharacter(tip, token, addon.db.unit.npc, raw)
    end
    if (addon.MM and addon.MM.OnCallEnd) then addon.MM:OnCallEnd("Unit", started) end
end

local function OnModifierStateChanged()
    local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    addon:RefreshManagedTooltipsMatching(function(tip, context)
        if (context and context.type and unitType) then
            return context.type == unitType
        end
        return GetTooltipContextGUID(context) ~= nil
    end, "MODIFIER_STATE_CHANGED")
end

-- Module wrapper
local M = {}

function M:Init()
    self.cb = OnTooltipUnit
    self.cbMod = OnModifierStateChanged
    self.cbInvalidate = InvalidateRaidCache
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("Unit", "tooltip:unit", self.cb, "tooltip:unit")
    else
        LibEvent:attachTrigger("tooltip:unit", self.cb)
    end

    if (addon.MM and addon.MM.AttachEvent) then
        addon.MM:AttachEvent("Unit", "MODIFIER_STATE_CHANGED", self.cbMod, "MODIFIER_STATE_CHANGED")
        addon.MM:AttachEvent("Unit", "PLAYER_ENTERING_WORLD", self.cbInvalidate, "PLAYER_ENTERING_WORLD")
        addon.MM:AttachEvent("Unit", "BOSS_KILL", self.cbInvalidate, "BOSS_KILL")
    else
        LibEvent:attachEvent("MODIFIER_STATE_CHANGED", self.cbMod)
        LibEvent:attachEvent("PLAYER_ENTERING_WORLD", self.cbInvalidate)
        LibEvent:attachEvent("BOSS_KILL", self.cbInvalidate)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Unit", M)
end

addon.ColorUnitBorder = ColorBorder
addon.ColorUnitBackground = ColorBackground
