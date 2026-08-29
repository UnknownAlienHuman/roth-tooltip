-- RothTooltip Retail 12.1 TooltipDataProcessor bridge.
--
-- Raw TooltipData is consumed only by Engine/Midnight.lua. Feature modules
-- receive a sanitized primitive context; raw aura records and argument vectors
-- are never forwarded or retained.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function WantTrigger(eventName)
    return addon.MM and addon.MM:HasTriggerSubscribers(eventName) == true
end

local function BuildContext(tooltip, tooltipData)
    if not addon:CanAccessValue(tooltipData) then
        addon:SetPrimaryTooltipContext(tooltip, nil)
        return nil
    end
    return addon:GetPrimaryTooltipContext(tooltip, tooltipData)
end

local function IsUnitContext(context, unitType)
    if type(context) ~= "table" then return false end
    if type(unitType) == "number" and context.type == unitType then return true end
    return type(context.unitToken) == "string" or type(context.guid) == "string"
end

local function IsArenaInstance()
    local inInstance, instanceType = addon:SafeCall("IsInInstance", IsInInstance)
    return inInstance == true and instanceType == "arena"
end

local function CheckVisibility(tooltip, context, unitType)
    if not addon:IsTooltipSafe(tooltip) then return false end
    local visibility = addon.db and addon.db.general and addon.db.general.visibility
    if type(visibility) ~= "table" then return true end

    if visibility.bags == "hide" and addon:IsBag(tooltip) then return false end
    if visibility.actionBars == "hide" and addon:IsActionBar(tooltip) then return false end

    if InCombatLockdown() then
        local mode = visibility.inCombat or "show"
        if mode == "hide" then return false end
        if mode == "unitOnly" and not IsUnitContext(context, unitType) then return false end
    end

    if visibility.inRaid == "hide" and addon:SafeCallBoolean(IsInRaid) == true then return false end
    if visibility.inArena == "hide" and IsArenaInstance() then return false end
    return true
end

local function Prepare(tooltip, tooltipData, unitType)
    if not addon:IsManagedTooltip(tooltip) then return nil end

    local context = BuildContext(tooltip, tooltipData)
    if not CheckVisibility(tooltip, context, unitType) then
        addon:SafeMethod(tooltip, "Hide")
        return nil
    end
    return context
end

local function ContextHasItem(context)
    return type(context) == "table"
        and (type(context.hyperlink) == "string" or type(context.itemID) == "number")
end

local function ContextHasSpell(context)
    return type(context) == "table" and type(context.spellID) == "number"
end

local function CreateItemDispatcher(unitType)
    return function(tooltip, tooltipData)
        local context = Prepare(tooltip, tooltipData, unitType)
        if not ContextHasItem(context) or not addon:AllowTrigger("item", tooltip) then return end
        if WantTrigger("tooltip:item") then
            LibEvent:trigger("tooltip:item", tooltip, context.hyperlink, context)
        end
    end
end

local function CreateSpellDispatcher(unitType)
    return function(tooltip, tooltipData)
        local context = Prepare(tooltip, tooltipData, unitType)
        if not ContextHasSpell(context) or not addon:AllowTrigger("spell", tooltip) then return end
        if WantTrigger("tooltip:spell") then
            LibEvent:trigger("tooltip:spell", tooltip, context)
        end
    end
end

local function CreateUnitDispatcher(unitType)
    return function(tooltip, tooltipData)
        local context = Prepare(tooltip, tooltipData, unitType)
        if not IsUnitContext(context, unitType) or not addon:AllowTrigger("unit", tooltip) then return end
        if WantTrigger("tooltip:unit") then
            LibEvent:trigger("tooltip:unit", tooltip, context.unitToken, context.guid, unitType, context)
        end
    end
end

local function CreateAuraDispatcher(unitType)
    return function(tooltip, tooltipData)
        local context = Prepare(tooltip, tooltipData, unitType)
        if not ContextHasSpell(context) or not addon:AllowTrigger("aura", tooltip) then return end
        if WantTrigger("tooltip:aura") then
            -- Preserve historic trigger arity without forwarding raw AuraData.
            LibEvent:trigger("tooltip:aura", tooltip, nil, context.spellID, context)
        end
    end
end

local function CreateActionLikeDispatcher(unitType)
    return function(tooltip, tooltipData)
        local context = Prepare(tooltip, tooltipData, unitType)
        -- Item evidence is decisive. This preserves item macros and item-backed
        -- pet/flyout tooltips instead of treating every action-like id as a spell.
        if ContextHasItem(context) then
            if addon:AllowTrigger("item", tooltip) and WantTrigger("tooltip:item") then
                LibEvent:trigger("tooltip:item", tooltip, context.hyperlink, context)
            end
        elseif ContextHasSpell(context) then
            if addon:AllowTrigger("spell", tooltip) and WantTrigger("tooltip:spell") then
                LibEvent:trigger("tooltip:spell", tooltip, context)
            end
        end
    end
end

local function CreateGenericDispatcher(unitType)
    return function(tooltip, tooltipData)
        local context = Prepare(tooltip, tooltipData, unitType)
        if not addon:AllowTrigger("other", tooltip) then return end
        if type(context) ~= "table" or type(context.id) ~= "number" then return end
        if not WantTrigger("tooltip:genericid") then return end

        local label = type(addon.TYPE_NAME) == "table" and addon.TYPE_NAME[context.type] or nil
        if type(label) ~= "string" or label == "" then label = "ID" end
        LibEvent:trigger("tooltip:genericid", tooltip, label, context.id, context.type, context)
    end
end

function addon:InitTooltipDataProcessor()
    if self.__RT_TooltipProcessorInitialized then return self.__RT_TooltipProcessorReady == true end
    self.__RT_TooltipProcessorInitialized = true
    self.__RT_TooltipProcessorReady = false

    local processor = TooltipDataProcessor
    local addPostCall = processor and processor.AddTooltipPostCall
    local dataTypes = Enum and Enum.TooltipDataType
    if type(addPostCall) ~= "function" or type(dataTypes) ~= "table" then
        if self.DoctorLog then
            self:DoctorLog("api", "TooltipDataProcessor",
                "AddTooltipPostCall or Enum.TooltipDataType unavailable", nil)
        end
        return false
    end

    local itemType = dataTypes.Item
    local spellType = dataTypes.Spell
    local unitType = dataTypes.Unit
    local auraType = dataTypes.UnitAura
    if type(itemType) ~= "number" or type(spellType) ~= "number"
        or type(unitType) ~= "number" or type(auraType) ~= "number" then
        if self.DoctorLog then
            self:DoctorLog("api", "TooltipDataProcessor", "Required Retail tooltip enum missing", nil)
        end
        return false
    end

    local registered = {}
    local function Register(typeID, callback)
        if type(typeID) ~= "number" or registered[typeID] then return true end
        local ok, errorMessage = pcall(addPostCall, typeID, callback)
        if not ok then
            if addon.DoctorLog then
                addon:DoctorLog("api", "TooltipDataProcessor:" .. tostring(typeID),
                    addon:SafeToString(errorMessage, "registration failed"), nil)
            end
            return false
        end
        registered[typeID] = true
        return true
    end

    local ready = true
    ready = Register(itemType, CreateItemDispatcher(unitType)) and ready
    ready = Register(spellType, CreateSpellDispatcher(unitType)) and ready
    ready = Register(unitType, CreateUnitDispatcher(unitType)) and ready
    ready = Register(auraType, CreateAuraDispatcher(unitType)) and ready

    local actionLikeDispatcher = CreateActionLikeDispatcher(unitType)
    for _, typeID in ipairs({ dataTypes.PetAction, dataTypes.Flyout, dataTypes.Macro }) do
        if type(typeID) == "number" then Register(typeID, actionLikeDispatcher) end
    end

    local genericDispatcher = CreateGenericDispatcher(unitType)
    for typeID in pairs(addon.TYPE_NAME or {}) do
        if type(typeID) == "number" and not registered[typeID] then
            Register(typeID, genericDispatcher)
        end
    end

    self.__RT_TooltipProcessorReady = ready
    return ready
end

addon:InitTooltipDataProcessor()
