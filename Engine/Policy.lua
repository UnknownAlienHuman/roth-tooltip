-- RothTooltip Engine: Policy
-- Centralizes what may run across combat, secret restrictions, and object
-- access constraints.

local _, addon = ...

addon.Policy = addon.Policy or {}

-- Combat policy modes:
-- STRICT: visual skin + item enhancements only.
-- BALANCED: also allows ordinary spell tooltips.
-- AGGRESSIVE: allows ordinary accessible payloads, but never overrides a
-- Blizzard secret predicate or an object access restriction.
local DEFAULT_MODE = "STRICT"

function addon:PolicyMode()
    local db = self.db
    local mode = db and db.general and db.general.combatPolicy
    if type(mode) ~= "string" then return DEFAULT_MODE end

    mode = mode:upper()
    if mode ~= "STRICT" and mode ~= "BALANCED" and mode ~= "AGGRESSIVE" then
        return DEFAULT_MODE
    end
    return mode
end

function addon:IsTooltipSafe(tooltip)
    if self.CanAccessValue and not self:CanAccessValue(tooltip) then return false end
    if tooltip == nil then return false end

    if self.IsObjectAccessible then
        return self:IsObjectAccessible(tooltip)
    end

    local canAccess = tooltip.CanBeAccessedInContext
    if type(canAccess) == "function" then
        local ok, result = pcall(canAccess, tooltip)
        if not ok or result ~= true then return false end
    end

    local isForbidden = tooltip.IsForbidden
    if type(isForbidden) == "function" then
        local ok, result = pcall(isForbidden, tooltip)
        if not ok or result == true then return false end
    end
    return true
end

local function RestrictionsDeny(self, kind)
    if kind == "aura" and self.AreAurasRestricted and self:AreAurasRestricted() then
        return true
    end
    if kind == "unit" and self.AreUnitStatsRestricted and self:AreUnitStatsRestricted() then
        return true
    end
    return false
end

-- kind: skin|item|spell|unit|aura|anchor|event|other
function addon:AllowTrigger(kind, tooltip)
    if RestrictionsDeny(self, kind) then return false end

    if tooltip ~= nil and not self:IsTooltipSafe(tooltip) then
        return false
    end

    if kind == "skin" or kind == "anchor" then
        return true
    end

    if InCombatLockdown() then
        local mode = self:PolicyMode()
        if kind == "item" then return true end
        if kind == "spell" and (mode == "BALANCED" or mode == "AGGRESSIVE") then
            return true
        end
        if mode == "AGGRESSIVE" then
            return kind ~= "unit" and kind ~= "aura"
        end
        return false
    end

    return true
end
