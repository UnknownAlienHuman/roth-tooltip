local _, addon = ...

local modelFrame
local rotateElapsed = 0
local rotationActive = false

local function IsOrdinaryUnit(unit)
    return addon:CanAccessValue(unit)
        and type(unit) == "string"
        and unit ~= ""
        and not addon:IsUnitIdentityRestricted(unit)
end

local function StopRotation()
    if rotationActive and addon:IsObjectAccessible(modelFrame) and addon:CanBindScripts(modelFrame) then
        addon:SafeMethod(modelFrame, "SetScript", "OnUpdate", nil)
    end
    rotationActive = false
    rotateElapsed = 0
end

local function ClearModel()
    StopRotation()
    if not addon:IsObjectAccessible(modelFrame) then return end
    addon:SafeMethod(modelFrame, "ClearModel")
    addon:SafeMethod(modelFrame, "Hide")
end

local function ModelPathAllowed(unit)
    return not InCombatLockdown()
        and not addon:AreUnitStatsRestricted()
        and IsOrdinaryUnit(unit)
end

local function ApplyModelLayout(frame)
    if not addon:IsObjectAccessible(frame) then return end
    local config = addon.db and addon.db.model or {}
    addon:SafeMethod(frame, "SetSize", tonumber(config.width) or 100, tonumber(config.height) or 100)
    addon:SafeMethod(frame, "SetFacing", tonumber(config.facing) or -0.25)
    addon:SafeMethod(frame, "ClearAllPoints")
    addon:SafeMethod(frame, "SetPoint", "BOTTOMRIGHT", GameTooltip, "TOPRIGHT",
        tonumber(config.offsetX) or 8, tonumber(config.offsetY) or -16)
end

local function RotationUpdate(self, elapsed)
    if type(elapsed) ~= "number" then return end
    rotateElapsed = rotateElapsed + elapsed
    if rotateElapsed < 0.05 then return end

    local delta = rotateElapsed
    rotateElapsed = 0
    if IsControlKeyDown() ~= true and IsAltKeyDown() ~= true then return end
    local facing = addon:SafeMethod(self, "GetFacing")
    if type(facing) == "number" then
        addon:SafeMethod(self, "SetFacing", facing + math.pi * delta)
    end
end

local function UpdateRotationState()
    local frame = modelFrame
    if not addon:IsObjectAccessible(frame) or not addon:CanBindScripts(frame) then return end
    local shouldRotate = addon:SafeMethod(frame, "IsShown") == true
        and (IsControlKeyDown() == true or IsAltKeyDown() == true)

    if shouldRotate and not rotationActive then
        local setScript = addon:SafeGet(frame, "SetScript")
        if type(setScript) == "function" and pcall(setScript, frame, "OnUpdate", RotationUpdate) then
            rotationActive = true
        end
    elseif not shouldRotate and rotationActive then
        StopRotation()
    end
end

local function EnsureModelFrame(tooltip)
    if addon:IsObjectAccessible(modelFrame) then
        ApplyModelLayout(modelFrame)
        return modelFrame
    end
    if tooltip ~= GameTooltip or not addon:IsTooltipSafe(tooltip) or InCombatLockdown() then return nil end

    local ok, frame = pcall(CreateFrame, "PlayerModel", nil, UIParent)
    if not ok or not addon:IsObjectAccessible(frame) then return nil end
    addon:SafeMethod(frame, "SetClampedToScreen", true)
    addon:SafeMethod(frame, "SetFrameStrata", "TOOLTIP")
    addon:SafeMethod(frame, "Hide")
    modelFrame = frame
    ApplyModelLayout(frame)
    return frame
end

local function ResolveModelUnit(tooltip, unit, context)
    if type(context) ~= "table" then context = addon:GetPrimaryTooltipContext(tooltip) end
    if type(context) == "table" and IsOrdinaryUnit(context.unitToken) then return context.unitToken end
    local guid = type(context) == "table" and context.guid or nil
    local token = addon:ResolveUnitToken(unit, guid)
    if IsOrdinaryUnit(token) then return token end
end

local function SetModelUnit(frame, unit)
    if not addon:IsObjectAccessible(frame) or not ModelPathAllowed(unit) then return false end

    local canSetUnit = addon:SafeGet(frame, "CanSetUnit")
    if type(canSetUnit) == "function" then
        -- CanSetUnit has no documented return. Only an error or explicit false
        -- denies; SetUnit supplies the authoritative success boolean.
        local ok, result = pcall(canSetUnit, frame, unit)
        if not ok or not addon:CanAccessValue(result) or result == false then return false end
    end

    local setUnit = addon:SafeGet(frame, "SetUnit")
    if type(setUnit) ~= "function" then return false end
    local ok, success = pcall(setUnit, frame, unit)
    return ok and addon:CanAccessValue(success) and success == true
end

local function UpdateModel(tooltip, unit, context)
    if tooltip ~= GameTooltip or not addon:IsTooltipSafe(tooltip) then return end
    local token = ResolveModelUnit(tooltip, unit, context)
    if not ModelPathAllowed(token) then ClearModel() return end

    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, token)
    if isPlayer == nil then ClearModel() return end
    local unitConfig = addon.db and addon.db.unit
    local config = type(unitConfig) == "table" and (isPlayer and unitConfig.player or unitConfig.npc) or nil
    if type(config) ~= "table" or config.showModel ~= true then ClearModel() return end

    local frame = EnsureModelFrame(tooltip)
    if not frame or not SetModelUnit(frame, token) then ClearModel() return end
    ApplyModelLayout(frame)
    addon:SafeMethod(frame, "Show")
    UpdateRotationState()
end

local function OnVariableChanged(_, key)
    if type(key) ~= "string" then return end
    if key:find("^model%.") or key == "unit.player.showModel" or key == "unit.npc.showModel" then
        if addon:IsObjectAccessible(modelFrame) then ApplyModelLayout(modelFrame) end
    end
end

local M = {}

function M:Init()
    self.cbInit = function(_, tooltip)
        if tooltip == GameTooltip and not InCombatLockdown() then EnsureModelFrame(tooltip) end
    end
    self.cbUnit = function(_, tooltip, unit, _, _, context)
        if not addon:AllowTrigger("unit", tooltip) then ClearModel() return end
        UpdateModel(tooltip, unit, context)
    end
    self.cbClear = function(_, tooltip)
        if tooltip == GameTooltip then ClearModel() end
    end
    self.cbModifier = UpdateRotationState
    self.cbVariable = OnVariableChanged
end

function M:Enable()
    addon.MM:AttachTrigger("Model", "tooltip:init", self.cbInit, "tooltip:init")
    addon.MM:AttachTrigger("Model", "tooltip:unit", self.cbUnit, "tooltip:unit")
    addon.MM:AttachTrigger("Model", "tooltip:cleared, tooltip:hide", self.cbClear, "tooltip:clear")
    addon.MM:AttachTrigger("Model", "tooltip:variable:changed", self.cbVariable, "variable-change")
    addon.MM:AttachEvent("Model", "PLAYER_REGEN_DISABLED", self.cbClear, "PLAYER_REGEN_DISABLED")
    addon.MM:AttachEvent("Model", "MODIFIER_STATE_CHANGED", self.cbModifier, "rotation-modifier")
end

function M:Disable()
    ClearModel()
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Model", M)
