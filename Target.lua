--[[
Roth Tooltip - Target helpers

Retail 12.1 can make unit identity and comparisons inaccessible. This module
therefore derives a compound "unittarget" token only from an ordinary unit
string and only while Blizzard's unit predicates permit the path.

"Targeted By" remains disabled because it would require scanning and comparing
many compound unit tokens on every hover.
]]

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local TARGET_LABEL = TARGET or "Target"

local function IsOrdinaryUnit(unit)
    if addon.CanAccessValue and not addon:CanAccessValue(unit) then return false end
    if type(unit) ~= "string" or unit == "" then return false end
    if addon.IsUnitIdentityRestricted and addon:IsUnitIdentityRestricted(unit) then return false end
    return true
end

local function SafeUnitName(unit)
    if not IsOrdinaryUnit(unit) then return nil end

    local ok, name = pcall(UnitName, unit)
    if not ok then return nil end
    if addon.CanAccessValue and not addon:CanAccessValue(name) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

local function SafeUnitExists(unit)
    if not IsOrdinaryUnit(unit) then return false end
    return addon:SafeCallBoolean(UnitExists, unit) == true
end

local function ResolveBaseUnit(tip, context)
    local unit
    if type(context) == "table" then
        unit = context.unitToken
    end
    if not IsOrdinaryUnit(unit) then
        unit = addon:GetTooltipUnit(tip)
    end
    if not IsOrdinaryUnit(unit) then return nil end
    return unit
end

local function ResolveTargetUnit(baseUnit)
    if not IsOrdinaryUnit(baseUnit) then return nil end

    local targetUnit = baseUnit .. "target"
    if addon.CanCompareUnitTokens and not addon:CanCompareUnitTokens(baseUnit, targetUnit) then
        return nil
    end
    if not SafeUnitExists(targetUnit) then return nil end
    return targetUnit
end

local function ShouldShowTarget(baseUnit)
    local unitDB = addon.db and addon.db.unit
    if type(unitDB) ~= "table" then return false end

    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, baseUnit)
    if isPlayer == true then
        return unitDB.player and unitDB.player.showTarget == true
    elseif isPlayer == false then
        return unitDB.npc and unitDB.npc.showTarget == true
    end
    return false
end

local function UpdateTargetLine(tip, context)
    if not addon:IsTooltipSafe(tip) then return end

    local baseUnit = ResolveBaseUnit(tip, context)
    if not baseUnit or not ShouldShowTarget(baseUnit) then return end

    local targetUnit = ResolveTargetUnit(baseUnit)
    local targetName = SafeUnitName(targetUnit)
    if not targetName then return end

    local icon = addon:GetRaidIcon(targetUnit)
    if type(icon) ~= "string" then icon = "" end
    local lineText = string.format("%s: %s%s", TARGET_LABEL, icon, targetName)

    local line = addon:FindLine(tip, "^" .. TARGET_LABEL .. ":")
    if line and addon:IsObjectAccessible(line) then
        addon:SafeMethod(line, "SetText", lineText)
    else
        addon:SafeMethod(tip, "AddLine", lineText, 0.8, 0.8, 0.8)
    end
end

local function OnTooltipUnitTarget(_, tip, _, _, _, context)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Target") then return end
    if addon.AllowTrigger and not addon:AllowTrigger("unit", tip) then return end

    local started
    if addon.MM and addon.MM.OnCallStart then
        started = addon.MM:OnCallStart("Target", "tooltip:unit")
    end

    UpdateTargetLine(tip, context)

    if addon.MM and addon.MM.OnCallEnd then
        addon.MM:OnCallEnd("Target", started)
    end
end

local M = {}

function M:Init()
    self.cbUnit = OnTooltipUnitTarget
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("Target", "tooltip:unit", self.cbUnit, "tooltip:unit")
    else
        LibEvent:attachTrigger("tooltip:unit", self.cbUnit)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Target", M)
end
