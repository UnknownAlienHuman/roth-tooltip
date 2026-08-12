local _, addon = ...

--=========================================================
-- Module wrapper
--=========================================================
local M = {}

local function ClearTooltipModel(tip)
    if (tip and tip.model) then
        tip.model:ClearModel()
        tip.model:Hide()
    end
end

local function ResolveModelUnit(tip, unit, context)
    context = context or addon:GetPrimaryTooltipContext(tip)

    local token = context and context.unitToken
    if (addon:IsSecret(token) or type(token) ~= "string" or token == "") then
        token = addon:ResolveUnitToken(unit, context and context.guid)
    end

    if (addon:IsSecret(token) or type(token) ~= "string" or token == "") then
        token = addon:GetTooltipUnit(tip)
    end

    if (addon:IsSecret(token) or type(token) ~= "string" or token == "") then
        return nil
    end

    return token
end

local function CanSetTooltipModelUnit(tip, unit)
    if (not tip or not tip.model or not unit) then
        return false
    end

    if (tip.model.CanSetUnit) then
        local ok, canSet = pcall(tip.model.CanSetUnit, tip.model, unit)
        if (not ok or addon:IsSecret(canSet) or canSet == false) then
            return false
        end
    end

    return true
end

local function SetTooltipModelUnit(tip, unit)
    if (not CanSetTooltipModelUnit(tip, unit)) then
        return false
    end

    local ok, success = pcall(tip.model.SetUnit, tip.model, unit)
    if (not ok or success == false) then
        return false
    end

    return true
end

function M:Init()
    self.cbInit = function(_, tip)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Model")) then return end
        if (tip ~= GameTooltip) then return end
        if (not tip.model) then
            local cfg = addon.db and addon.db.model or {}
            tip.model = CreateFrame("PlayerModel", nil, tip)
            tip.model:SetSize(cfg.width or 100, cfg.height or 100)
            tip.model:SetFacing(cfg.facing or -0.25)
            tip.model:SetPoint("BOTTOMRIGHT", tip, "TOPRIGHT", cfg.offsetX or 8, cfg.offsetY or -16)
            tip.model:Hide()
            tip.model:SetScript("OnUpdate", function(self, elapsed)
                self.__RTRotateElapsed = (self.__RTRotateElapsed or 0) + elapsed
                if (self.__RTRotateElapsed < 0.05) then
                    return
                end
                elapsed = self.__RTRotateElapsed
                self.__RTRotateElapsed = 0
                if (IsControlKeyDown() or IsAltKeyDown()) then
                    self:SetFacing(self:GetFacing() + math.pi * elapsed)
                end
            end)
        end
    end

    self.cbUnit = function(_, tip, unit, guid, _, context)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Model")) then return end
        if (tip ~= GameTooltip) then return end
        if (not addon.db or not addon.db.unit) then return end

        local token = ResolveModelUnit(tip, unit, context)
        if (not token) then
            ClearTooltipModel(tip)
            return
        end

        local ok, isPlayer = pcall(UnitIsPlayer, token)
        if (not ok or addon:IsSecret(isPlayer)) then isPlayer = nil end

        local facing = (addon.db.model and addon.db.model.facing) or -0.25
        if (addon.db.unit.player.showModel and isPlayer) then
            if (SetTooltipModelUnit(tip, token)) then
                tip.model:SetFacing(facing)
                tip.model:Show()
            else
                ClearTooltipModel(tip)
            end
        elseif (addon.db.unit.npc.showModel and isPlayer == false) then
            if (SetTooltipModelUnit(tip, token)) then
                tip.model:SetFacing(facing)
                tip.model:Show()
            else
                ClearTooltipModel(tip)
            end
        else
            ClearTooltipModel(tip)
        end
    end

    self.cbCleared = function(_, tip)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Model")) then return end
        if (tip ~= GameTooltip) then return end
        ClearTooltipModel(tip)
    end
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("Model", "tooltip:init", self.cbInit, "tooltip:init")
        addon.MM:AttachTrigger("Model", "tooltip:unit", self.cbUnit, "tooltip:unit")
        addon.MM:AttachTrigger("Model", "tooltip:cleared", self.cbCleared, "tooltip:cleared")
    end
end

function M:Disable()
    ClearTooltipModel(GameTooltip)
end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Model", M)
end
