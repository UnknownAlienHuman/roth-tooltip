-- Session-long registration; modules only subscribe to the private bus.
local _, addon = ...
local bus = addon.LibEvent
local types = Enum.TooltipDataType

local function Hidden(tooltip, context)
    local visibility = addon.db and addon.db.general and addon.db.general.visibility
    if type(visibility) ~= "table" then return false end
    if visibility.bags == "hide" and addon:IsBag(tooltip) then return true end
    if visibility.actionBars == "hide" and addon:IsActionBar(tooltip) then return true end
    if InCombatLockdown() then
        if visibility.inCombat == "hide" then return true end
        if visibility.inCombat == "unitOnly" and context.type ~= types.Unit then return true end
    end
    if visibility.inRaid == "hide" and addon:SafeCallBoolean(IsInRaid) == true then return true end
    return visibility.inArena == "hide" and addon:SafeCallBoolean(C_PvP and C_PvP.IsArena) == true
end

local function Emit(kind, tooltip, ...)
    local trigger = "tooltip:" .. kind
    if addon.MM:HasTriggerSubscribers(trigger) and addon:AllowTrigger(kind == "genericid" and "other" or kind, tooltip) then
        bus:trigger(trigger, tooltip, ...)
    end
end

local function PreCall(tooltip, data)
    if not addon:IsManagedTooltip(tooltip) then return end
    local context = addon:GetPrimaryTooltipContext(tooltip, data)
    -- Unknown/inaccessible inputs must never consume the native display.
    if context and Hidden(tooltip, context) then
        addon:SafeMethod(tooltip, "Hide")
        return true
    end
end

local function PostCall(tooltip, data)
    if not addon:IsManagedTooltip(tooltip) then
        if addon:CanAccessValue(tooltip) then bus:trigger("tooltip:invalidated", tooltip) end
        return
    end
    local context = addon:GetPrimaryTooltipContext(tooltip, data)
    if not context then bus:trigger("tooltip:invalidated", tooltip); return end
    local kind = context.type
    if kind == types.Unit then
        Emit("unit", tooltip, context.unitToken, context.guid, kind, context)
    elseif kind == types.UnitAura then
        if context.spellID then Emit("aura", tooltip, nil, context.spellID, context) end
    elseif context.itemID or context.hyperlink then
        Emit("item", tooltip, context.hyperlink, context)
    elseif context.spellID then
        Emit("spell", tooltip, context)
    elseif context.id then
        Emit("genericid", tooltip, addon.TYPE_NAME[kind] or "ID", context.id, kind, context)
    end
end

local preRegistered, postRegistered = false, false

function addon:InitTooltipDataProcessor()
    if self.__RT_TooltipProcessorReady then return true end
    if not preRegistered then
        TooltipDataProcessor.AddTooltipPreCall(TooltipDataProcessor.AllTypes, PreCall)
        preRegistered = true
    end
    if not postRegistered then
        TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, PostCall)
        postRegistered = true
    end
    self.__RT_TooltipProcessorReady = true
    return true
end

addon:InitTooltipDataProcessor()
