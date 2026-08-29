-- RothTooltip target-line enrichment.
--
-- Only the exact compound token for the displayed unit is used. The module does
-- not scan group/unit candidates or reconstruct inaccessible identity.

local _, addon = ...

local TARGET_LABEL = TARGET or "Target"

local function EscapePattern(text)
    return (text:gsub("(%W)", "%%%1"))
end

local function IsOrdinaryUnit(unit)
    return addon:CanAccessValue(unit)
        and type(unit) == "string"
        and unit ~= ""
        and not addon:IsUnitIdentityRestricted(unit)
end

local function SafeUnitName(unit)
    if not IsOrdinaryUnit(unit) then return nil end
    local name = addon:SafeCall("UnitName", UnitName, unit)
    if type(name) == "string" and name ~= "" then return name end
end

local function ResolveBaseUnit(tooltip, context)
    local unit = type(context) == "table" and context.unitToken or nil
    if not IsOrdinaryUnit(unit) then unit = addon:GetTooltipUnit(tooltip) end
    if IsOrdinaryUnit(unit) then return unit end
end

local function ResolveTargetUnit(baseUnit)
    if not IsOrdinaryUnit(baseUnit) then return nil end
    local targetUnit = baseUnit .. "target"
    if not addon:CanCompareUnitTokens(baseUnit, targetUnit) then return nil end
    if addon:SafeCallBoolean(UnitExists, targetUnit) ~= true then return nil end
    return targetUnit
end

local function ShouldShowTarget(baseUnit)
    local config = addon.db and addon.db.unit
    if type(config) ~= "table" then return false end

    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, baseUnit)
    if isPlayer == true then
        return type(config.player) == "table" and config.player.showTarget == true
    elseif isPlayer == false then
        return type(config.npc) == "table" and config.npc.showTarget == true
    end
    return false
end

local function OnTooltipUnit(_, tooltip, _, _, _, context)
    if not addon:IsTooltipSafe(tooltip) or not addon:AllowTrigger("unit", tooltip) then return end

    local baseUnit = ResolveBaseUnit(tooltip, context)
    if not baseUnit or not ShouldShowTarget(baseUnit) then return end

    local targetUnit = ResolveTargetUnit(baseUnit)
    local targetName = SafeUnitName(targetUnit)
    if not targetName then return end

    local raidIcon = addon:GetRaidIcon(targetUnit)
    if type(raidIcon) ~= "string" then raidIcon = "" end
    local text = string.format("%s: %s%s", TARGET_LABEL, raidIcon, targetName)

    local line = addon:FindLine(tooltip, "^" .. EscapePattern(TARGET_LABEL) .. ":")
    if addon:IsObjectAccessible(line) then
        addon:SafeMethod(line, "SetText", text)
    else
        addon:SafeMethod(tooltip, "AddLine", text, 0.8, 0.8, 0.8)
    end
end

local function OnUnitTarget(_, changedUnit)
    if not IsOrdinaryUnit(changedUnit) then return end
    addon:RequestManagedTooltipRefresh(function(_, context)
        local displayedUnit = type(context) == "table" and context.unitToken or nil
        if not IsOrdinaryUnit(displayedUnit)
            or not addon:CanCompareUnitTokens(displayedUnit, changedUnit) then
            return false
        end
        return addon:SafeCallBoolean(UnitIsUnit, displayedUnit, changedUnit) == true
    end, "UNIT_TARGET")
end

local M = {}

function M:Init()
    self.cbUnit = OnTooltipUnit
    self.cbUnitTarget = OnUnitTarget
end

function M:Enable()
    addon.MM:AttachTrigger("Target", "tooltip:unit", self.cbUnit, "tooltip:unit")
    addon.MM:AttachEvent("Target", "UNIT_TARGET", self.cbUnitTarget, "UNIT_TARGET")
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Target", M)
