local _, addon = ...

local modelFrame
local rotateElapsed = 0

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function IsOrdinaryUnit(unit)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return false end
    if addon.IsUnitIdentityRestricted and addon:IsUnitIdentityRestricted(unit) then return false end
    return true
end

local function ClearTooltipModel()
    if not addon:IsObjectAccessible(modelFrame) then return end
    addon:SafeMethod(modelFrame, "ClearModel")
    addon:SafeMethod(modelFrame, "Hide")
end

local function ModelPathAllowed(unit)
    if InCombatLockdown() then return false end
    if addon.AreUnitStatsRestricted and addon:AreUnitStatsRestricted() then return false end
    return IsOrdinaryUnit(unit)
end

local function EnsureModelFrame(tip)
    if addon:IsObjectAccessible(modelFrame) then return modelFrame end
    if not addon:IsTooltipSafe(tip) or tip ~= GameTooltip then return nil end
    if InCombatLockdown() then return nil end

    local config = addon.db and addon.db.model or {}
    local frame = CreateFrame("PlayerModel", nil, UIParent)
    if not addon:IsObjectAccessible(frame) then return nil end

    addon:SafeMethod(frame, "SetSize", tonumber(config.width) or 100, tonumber(config.height) or 100)
    addon:SafeMethod(frame, "SetFacing", tonumber(config.facing) or -0.25)
    addon:SafeMethod(frame, "SetClampedToScreen", true)
    addon:SafeMethod(frame, "SetFrameStrata", "TOOLTIP")
    addon:SafeMethod(frame, "ClearAllPoints")
    addon:SafeMethod(
        frame,
        "SetPoint",
        "BOTTOMRIGHT",
        tip,
        "TOPRIGHT",
        tonumber(config.offsetX) or 8,
        tonumber(config.offsetY) or -16
    )
    addon:SafeMethod(frame, "Hide")

    addon:SafeMethod(frame, "SetScript", "OnUpdate", function(self, elapsed)
        if type(elapsed) ~= "number" then return end
        rotateElapsed = rotateElapsed + elapsed
        if rotateElapsed < 0.05 then return end

        local delta = rotateElapsed
        rotateElapsed = 0
        if IsControlKeyDown() ~= true and IsAltKeyDown() ~= true then return end

        local facing = addon:SafeMethod(self, "GetFacing")
        if CanAccess(facing) and type(facing) == "number" then
            addon:SafeMethod(self, "SetFacing", facing + math.pi * delta)
        end
    end)

    modelFrame = frame
    return frame
end

local function ResolveModelUnit(tip, unit, suppliedContext)
    local context = suppliedContext
    if not CanAccess(context) or type(context) ~= "table" then
        context = addon:GetPrimaryTooltipContext(tip)
    end

    if type(context) == "table" and IsOrdinaryUnit(context.unitToken) then
        return context.unitToken
    end

    local guid = type(context) == "table" and context.guid or nil
    local token = addon:ResolveUnitToken(unit, guid)
    if IsOrdinaryUnit(token) then return token end
    return nil
end

local function CanSetModelUnit(frame, unit)
    if not addon:IsObjectAccessible(frame) or not ModelPathAllowed(unit) then return false end

    local canSet = addon:SafeGet(frame, "CanSetUnit")
    if type(canSet) == "function" then
        local ok, result = pcall(canSet, frame, unit)
        if not ok or not CanAccess(result) or result ~= true then return false end
    end
    return true
end

local function SetModelUnit(frame, unit)
    if not CanSetModelUnit(frame, unit) then return false end
    local setUnit = addon:SafeGet(frame, "SetUnit")
    if type(setUnit) ~= "function" then return false end

    local ok, result = pcall(setUnit, frame, unit)
    if not ok or not CanAccess(result) or result == false then return false end
    return true
end

local function UpdateModel(tip, unit, context)
    if not addon:IsTooltipSafe(tip) or tip ~= GameTooltip then return end

    local token = ResolveModelUnit(tip, unit, context)
    if not ModelPathAllowed(token) then
        ClearTooltipModel()
        return
    end

    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, token)
    if isPlayer == nil then
        ClearTooltipModel()
        return
    end

    local unitConfig = addon.db and addon.db.unit
    local showModel = false
    if type(unitConfig) == "table" then
        if isPlayer == true then
            showModel = type(unitConfig.player) == "table" and unitConfig.player.showModel == true
        else
            showModel = type(unitConfig.npc) == "table" and unitConfig.npc.showModel == true
        end
    end
    if not showModel then
        ClearTooltipModel()
        return
    end

    local frame = EnsureModelFrame(tip)
    if not frame or not SetModelUnit(frame, token) then
        ClearTooltipModel()
        return
    end

    local config = addon.db and addon.db.model or {}
    addon:SafeMethod(frame, "ClearAllPoints")
    addon:SafeMethod(
        frame,
        "SetPoint",
        "BOTTOMRIGHT",
        tip,
        "TOPRIGHT",
        tonumber(config.offsetX) or 8,
        tonumber(config.offsetY) or -16
    )
    addon:SafeMethod(frame, "SetFacing", tonumber(config.facing) or -0.25)
    addon:SafeMethod(frame, "Show")
end

local M = {}

function M:Init()
    self.cbInit = function(_, tip)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Model") then return end
        if CanAccess(tip) and tip == GameTooltip and not InCombatLockdown() then
            EnsureModelFrame(tip)
        end
    end

    self.cbUnit = function(_, tip, unit, _, _, context)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Model") then return end
        if addon.AllowTrigger and not addon:AllowTrigger("unit", tip) then
            ClearTooltipModel()
            return
        end
        UpdateModel(tip, unit, context)
    end

    self.cbClear = function(_, tip)
        if CanAccess(tip) and tip == GameTooltip then ClearTooltipModel() end
    end

    self.cbCombat = ClearTooltipModel
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("Model", "tooltip:init", self.cbInit, "tooltip:init")
        addon.MM:AttachTrigger("Model", "tooltip:unit", self.cbUnit, "tooltip:unit")
        addon.MM:AttachTrigger("Model", "tooltip:cleared, tooltip:hide", self.cbClear, "tooltip:cleared/hide")
    end
    if addon.MM and addon.MM.AttachEvent then
        addon.MM:AttachEvent("Model", "PLAYER_REGEN_DISABLED", self.cbCombat, "PLAYER_REGEN_DISABLED")
    end
end

function M:Disable()
    ClearTooltipModel()
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Model", M)
end
