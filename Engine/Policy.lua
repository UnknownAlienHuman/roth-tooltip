-- RothTooltip Engine: Policy
-- Centralizes "what is allowed" depending on combat, forbidden tooltips, etc.

local _, addon = ...

addon.Policy = addon.Policy or {}

-- Combat policy modes:
-- STRICT: only visual skin + item enhancements, skip unit/aura (most sensitive)
-- BALANCED: allow spell in combat; unit/aura still skipped
-- AGGRESSIVE: allow everything (risk: secret values / taint)

local DEFAULT_MODE = "STRICT"

function addon:PolicyMode()
    local db = self.db
    local mode = db and db.general and db.general.combatPolicy
    if (type(mode) ~= "string") then
        return DEFAULT_MODE
    end
    mode = mode:upper()
    if (mode ~= "STRICT" and mode ~= "BALANCED" and mode ~= "AGGRESSIVE") then
        mode = DEFAULT_MODE
    end
    return mode
end

function addon:IsTooltipSafe(tip)
    if (tip == nil) then return false end
    if (tip.IsForbidden and tip:IsForbidden()) then return false end
    return true
end

-- kind: "skin"|"item"|"spell"|"unit"|"aura"|"anchor"|"event"
function addon:AllowTrigger(kind, tip)
    if (kind == "skin" or kind == "anchor") then
        return true
    end

    if (not self:IsTooltipSafe(tip)) then
        return false
    end

    if (InCombatLockdown()) then
        local mode = self:PolicyMode()
        if (mode == "AGGRESSIVE") then
            return true
        end
        if (kind == "item") then
            return true
        end
        if (kind == "spell" and mode == "BALANCED") then
            return true
        end
        return false
    end

    return true
end
