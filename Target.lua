--[[
Roth Tooltip - Target helpers

Midnight (12.0+): many Unit* APIs can return SecretValue booleans/strings and cannot be used
in boolean context or as protected arguments. The original TinyTooltip "target" and
"targeted by" features relied on frequent UnitIsUnit/UnitExists checks (often on compound
unit tokens like party1target), which now hard-error.

This module provides a safe subset:
  - Optional "Target: <name>" line for the tooltip's resolved unit token.

The "Targeted By" list is disabled in Midnight because it requires unsafe iteration over
compound unit tokens.
]]

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local TARGET_LABEL = TARGET or "Target"

local function SafeUnitName(unit)
    if (not unit) then return end
    local name

    -- Prefer securecallfunction when available to keep execution untainted.
    if (type(securecallfunction) == "function") then
        name = securecallfunction(UnitName, unit)
    else
        local ok, v = pcall(UnitName, unit)
        if (ok) then name = v end
    end

    -- UnitName can return SecretValue strings in Midnight (do NOT compare them).
    if (addon:IsSecret(name)) then
        return
    end

    if (type(name) ~= "string") then
        name = addon:SafeToString(name)
    end

    if (not name or name == "") then
        return
    end

    return name
end

local function SafeUnitExists(unit)
    if (not unit or type(unit) ~= "string") then
        return false
    end

    local exists
    if (type(securecallfunction) == "function") then
        exists = securecallfunction(UnitExists, unit)
    else
        local ok, value = pcall(UnitExists, unit)
        if (ok) then
            exists = value
        end
    end

    if (addon:IsSecret(exists)) then
        return false
    end

    return exists == true
end

local function ResolveTargetUnit(tip, context)
    context = context or addon:GetPrimaryTooltipContext(tip)

    local baseUnit = context and context.unitToken
    if (addon:IsSecret(baseUnit) or type(baseUnit) ~= "string" or baseUnit == "") then
        baseUnit = addon:GetTooltipUnit(tip)
    end
    if ((addon:IsSecret(baseUnit) or type(baseUnit) ~= "string" or baseUnit == "") and tip == GameTooltip) then
        baseUnit = "mouseover"
    end
    if (addon:IsSecret(baseUnit) or type(baseUnit) ~= "string" or baseUnit == "") then
        return nil
    end

    local targetUnit = baseUnit .. "target"
    if (not SafeUnitExists(targetUnit)) then
        return nil
    end

    return targetUnit
end

local function UpdateTargetLine(tip, context)
    if (not addon.db or not addon.db.unit) then return end

    -- Keep the original settings structure, but be conservative: if either player or npc
    -- target display is enabled, show it for the tooltip's resolved unit token.
    local unitDB = addon.db.unit
    local show = (unitDB.player and unitDB.player.showTarget) or (unitDB.npc and unitDB.npc.showTarget)
    if (not show) then return end

    local targetUnit = ResolveTargetUnit(tip, context)
    local targetName = SafeUnitName(targetUnit)
    if (not targetName) then
        return
    end

    local icon = addon:GetRaidIcon(targetUnit) or ""
    local lineText = string.format("%s: %s%s", TARGET_LABEL, icon, targetName)

    local line = addon:FindLine(tip, TARGET_LABEL .. ":")
    if (line) then
        line:SetText(lineText)
    else
        tip:AddLine(lineText, 0.8, 0.8, 0.8)
    end

end

local function OnTooltipUnit_Target(self, tip, unit, guid, _, context)
    if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Target")) then return end
    if (addon.AllowTrigger and not addon:AllowTrigger("unit", tip)) then return end

    local started
    if (addon.MM and addon.MM.OnCallStart) then started = addon.MM:OnCallStart("Target", "tooltip:unit") end

    UpdateTargetLine(tip, context)

    if (addon.MM and addon.MM.OnCallEnd) then addon.MM:OnCallEnd("Target", started) end
end

-- Module wrapper
local M = {}

function M:Init()
    self.cbUnit = OnTooltipUnit_Target
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("Target", "tooltip:unit", self.cbUnit, "tooltip:unit")
    else
        LibEvent:attachTrigger("tooltip:unit", self.cbUnit)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Target", M)
end
