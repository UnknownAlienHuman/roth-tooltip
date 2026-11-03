-- Policy is separate from object access; neither can override Blizzard limits.
local _, addon = ...

function addon:PolicyMode()
    local general = self.db and self.db.general
    local mode = general and general.combatPolicy
    if type(mode) == "string" then mode = mode:upper() end
    if mode == "BALANCED" or mode == "AGGRESSIVE" then return mode end
    return "STRICT"
end

function addon:IsTooltipSafe(tooltip)
    local aspect = Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.UntrustedLayoutScriptExecution
    return type(aspect) == "number" and not self:HasForbiddenAspects(tooltip, aspect)
end

function addon:AllowTrigger(kind, tooltip)
    if not self:CanAccessValue(tooltip) then return false end
    if tooltip ~= nil and not self:IsTooltipSafe(tooltip) then return false end
    if kind == "aura" and self:AreAurasRestricted() then return false end
    if kind == "unit" and self:AreUnitStatsRestricted() then return false end
    if kind == "skin" or kind == "anchor" or not InCombatLockdown() then return true end
    if kind == "item" then return true end
    local mode = self:PolicyMode()
    if kind == "spell" and mode ~= "STRICT" then return true end
    return mode == "AGGRESSIVE" and kind ~= "unit" and kind ~= "aura"
end
