local _, addon = ...
local model
local elapsedTime = 0

local function ClearModel()
    if model then
        addon:SafeMethod(model, "Hide")
        addon:SafeMethod(model, "ClearModel")
    end
    elapsedTime = 0
end

local function PositionModel()
    local config = addon.db.model
    local x, y = GetCursorPosition()
    local scale = addon:SafeMethod(UIParent, "GetEffectiveScale")
    if not addon:CanAccessAllValues(x, y, scale) or type(x) ~= "number"
        or type(y) ~= "number" or type(scale) ~= "number" or scale <= 0 then return end
    addon:SafeMethod(model, "ClearAllPoints")
    addon:SafeMethod(model, "SetPoint", "BOTTOMLEFT", UIParent, "BOTTOMLEFT",
        x / scale + config.offsetX, y / scale + 24 + config.offsetY)
end

local function OnUpdate(_, elapsed)
    elapsedTime = elapsedTime + elapsed
    if elapsedTime < 0.05 then return end
    local delta = elapsedTime
    elapsedTime = 0
    if InCombatLockdown() or not addon:IsTooltipSafe(GameTooltip)
        or addon:AreUnitStatsRestricted() then ClearModel(); return end
    PositionModel()
    if IsControlKeyDown() or IsAltKeyDown() then
        local facing = addon:SafeMethod(model, "GetFacing")
        if type(facing) == "number" then addon:SafeMethod(model, "SetFacing", facing + math.pi * delta) end
    end
end

local function EnsureModel()
    if model then return model end
    if InCombatLockdown() then return nil end
    model = CreateFrame("PlayerModel", nil, UIParent)
    model:SetClampedToScreen(true)
    model:SetFrameStrata("TOOLTIP")
    model:SetScript("OnUpdate", OnUpdate)
    model:Hide()
    return model
end

local function OnUnit(_, tooltip, _, _, _, context)
    if not addon:CanAccessValue(tooltip) or tooltip ~= GameTooltip then return end
    if not addon:AllowTrigger("unit", tooltip) or InCombatLockdown() then ClearModel(); return end
    local unit = context and addon:ResolveUnitToken(context.unitToken, context.guid)
    if not unit then ClearModel(); return end
    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, unit)
    local config = isPlayer ~= nil and addon.db.unit[isPlayer and "player" or "npc"]
    if not config or not config.showModel then ClearModel(); return end
    local frame = EnsureModel()
    if not frame then return end
    -- CanSetUnit has no documented return. SetUnit's explicit result owns success.
    if addon:SafeMethod(frame, "SetUnit", unit) ~= true then ClearModel(); return end
    local layout = addon.db.model
    addon:SafeMethod(frame, "SetSize", layout.width, layout.height)
    addon:SafeMethod(frame, "SetFacing", layout.facing)
    PositionModel()
    addon:SafeMethod(frame, "Show")
end

local function OnClear(_, tooltip)
    if addon:CanAccessValue(tooltip) and tooltip == GameTooltip then ClearModel() end
end

local M = {}
function M:Enable()
    EnsureModel()
    addon.MM:AttachTrigger("Model", "tooltip:unit", OnUnit)
    addon.MM:AttachTrigger("Model", "tooltip:cleared, tooltip:hide, tooltip:unregister, tooltip:invalidated", OnClear)
    addon.MM:AttachTrigger("Model", "tooltip:variables:loaded", ClearModel)
    addon.MM:AttachEvent("Model", "PLAYER_REGEN_DISABLED, ADDON_RESTRICTION_STATE_CHANGED, PLAYER_LEAVING_WORLD", ClearModel)
end
function M:Disable() ClearModel() end
addon.MM:RegisterModule("Model", M)
