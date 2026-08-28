-- RothTooltip Retail 12.1 TooltipDataProcessor bridge
--
-- Boundary contract:
--   * raw TooltipData is accepted only by addon:GetPrimaryTooltipContext();
--   * only sanitized primitive context fields cross into addon modules;
--   * raw AuraData/data.args never leave this file;
--   * visibility and policy checks fail closed on inaccessible state.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function TooltipName(tooltip)
    if not addon:IsObjectAccessible(tooltip) then return nil end
    local name = addon:SafeMethod(tooltip, "GetName")
    if CanAccess(name) and type(name) == "string" then return name end
    return nil
end

local function LooksLikeBlizzardSpellTooltip(tooltip)
    local name = TooltipName(tooltip)
    if not name then return false end
    if name == "SpellBookTooltip" then return true end
    if name:find("PlayerSpells", 1, true) and name:find("Tooltip", 1, true) then return true end
    return name:find("Spell", 1, true) ~= nil and name:find("Tooltip", 1, true) ~= nil
end

local function IsManagedTooltip(tooltip)
    if not addon:IsTooltipSafe(tooltip) then return false end
    if type(addon.tooltipSet) ~= "table" then return false end
    if addon.tooltipSet[tooltip] then return true end

    local parent = addon:SafeMethod(tooltip, "GetParent")
    if addon:IsObjectAccessible(parent) and addon.tooltipSet[parent] then return true end
    if LooksLikeBlizzardSpellTooltip(tooltip) then return true end
    return addon:IsObjectAccessible(parent) and LooksLikeBlizzardSpellTooltip(parent)
end

local function WantTrigger(eventName)
    if addon.MM and addon.MM.HasTriggerSubscribers then
        return addon.MM:HasTriggerSubscribers(eventName) == true
    end
    return true
end

local function BuildContext(tooltip, tooltipData)
    local context = addon:GetPrimaryTooltipContext(tooltip, tooltipData)
    addon:SetPrimaryTooltipContext(tooltip, context)
    return context
end

local function IsUnitContext(context, unitType)
    if type(context) ~= "table" then return false end
    if type(unitType) == "number" and context.type == unitType then return true end
    return type(context.unitToken) == "string" or type(context.guid) == "string"
end

local function CheckVisibility(tooltip, context, unitType)
    if not addon:IsTooltipSafe(tooltip) then return false end
    local visibility = addon.db and addon.db.general and addon.db.general.visibility
    if type(visibility) ~= "table" then return true end

    if visibility.bags == "hide" and addon:IsBag(tooltip) then return false end
    if visibility.actionBars == "hide" and addon:IsActionBar(tooltip) then return false end

    if InCombatLockdown() then
        local combatMode = visibility.inCombat or "show"
        if combatMode == "hide" then return false end
        if combatMode == "unitOnly" and not IsUnitContext(context, unitType) then return false end
    end

    if visibility.inRaid == "hide" and addon:SafeCallBoolean(IsInRaid) == true then return false end
    if visibility.inArena == "hide"
        and addon:SafeCallBoolean(C_PvP and C_PvP.IsArena) == true then
        return false
    end
    return true
end

local function HideForVisibility(tooltip)
    if addon:IsTooltipSafe(tooltip) then addon:SafeMethod(tooltip, "Hide") end
end

local function ContextHasItem(context)
    return type(context) == "table"
        and (type(context.hyperlink) == "string" or type(context.itemID) == "number")
end

local function ContextHasSpell(context)
    return type(context) == "table" and type(context.spellID) == "number"
end

local function CreateDispatcher(dataType, unitType, kind)
    return function(tooltip, tooltipData)
        if not IsManagedTooltip(tooltip) then return end

        local context = BuildContext(tooltip, tooltipData)
        if not CheckVisibility(tooltip, context, unitType) then
            HideForVisibility(tooltip)
            return
        end

        if kind == "item" then
            if not addon:AllowTrigger("item", tooltip) or not ContextHasItem(context) then return end
            if WantTrigger("tooltip:item") then
                LibEvent:trigger("tooltip:item", tooltip, context.hyperlink, context)
            end
            return
        end

        if kind == "spell" then
            if not addon:AllowTrigger("spell", tooltip) then return end
            if WantTrigger("tooltip:spell") then
                LibEvent:trigger("tooltip:spell", tooltip, context)
            end
            return
        end

        if kind == "unit" then
            if not addon:AllowTrigger("unit", tooltip) or not IsUnitContext(context, unitType) then return end
            if WantTrigger("tooltip:unit") then
                LibEvent:trigger(
                    "tooltip:unit",
                    tooltip,
                    context and context.unitToken or nil,
                    context and context.guid or nil,
                    dataType,
                    context
                )
            end
            return
        end

        if kind == "aura" then
            if not addon:AllowTrigger("aura", tooltip) then return end
            if WantTrigger("tooltip:aura") then
                -- Intentionally preserve the trigger arity while replacing
                -- the former raw args payload with nil.
                LibEvent:trigger(
                    "tooltip:aura",
                    tooltip,
                    nil,
                    context and context.spellID or nil,
                    context
                )
            end
        end
    end
end

local function CreateActionDispatcher(unitType)
    return function(tooltip, tooltipData)
        if not IsManagedTooltip(tooltip) then return end

        local context = BuildContext(tooltip, tooltipData)
        if not CheckVisibility(tooltip, context, unitType) then
            HideForVisibility(tooltip)
            return
        end

        -- Item evidence is decisive. Only otherwise dispatch the sanitized
        -- spell ID; no texture/API probe is used as a classifier.
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
        if not IsManagedTooltip(tooltip) then return end

        local context = BuildContext(tooltip, tooltipData)
        if not CheckVisibility(tooltip, context, unitType) then
            HideForVisibility(tooltip)
            return
        end
        if not addon:AllowTrigger("other", tooltip) then return end
        if type(context) ~= "table" or type(context.id) ~= "number" then return end
        if not WantTrigger("tooltip:genericid") then return end

        local label = type(addon.TYPE_NAME) == "table" and addon.TYPE_NAME[context.type] or nil
        if type(label) ~= "string" or label == "" then label = "ID" end
        LibEvent:trigger("tooltip:genericid", tooltip, label, context.id, context.type, context)
    end
end

function addon:InitTooltipDataProcessor()
    if self.__RT_TDPInitialized and not self.__RT_DeferTooltipProcessor then
        return self.__RT_UseTDP == true
    end

    self.__RT_DeferTooltipProcessor = nil
    self.__RT_TDPInitialized = true
    self.__RT_UseTDP = false

    local processor = TooltipDataProcessor
    local addPostCall = processor and processor.AddTooltipPostCall
    local dataTypes = Enum and Enum.TooltipDataType
    if type(addPostCall) ~= "function" or type(dataTypes) ~= "table" then
        if self.DoctorLog then
            self:DoctorLog("api", "TooltipDataProcessor", "AddTooltipPostCall or Enum.TooltipDataType unavailable", nil)
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
        local ok, err = pcall(addPostCall, typeID, callback)
        if not ok then
            if addon.DoctorLog then
                addon:DoctorLog("api", "TooltipDataProcessor:" .. tostring(typeID), tostring(err), nil)
            end
            return false
        end
        registered[typeID] = true
        return true
    end

    local coreOK = true
    coreOK = Register(itemType, CreateDispatcher(itemType, unitType, "item")) and coreOK
    coreOK = Register(spellType, CreateDispatcher(spellType, unitType, "spell")) and coreOK
    coreOK = Register(unitType, CreateDispatcher(unitType, unitType, "unit")) and coreOK
    coreOK = Register(auraType, CreateDispatcher(auraType, unitType, "aura")) and coreOK

    local actionDispatcher = CreateActionDispatcher(unitType)
    for _, typeID in ipairs({ dataTypes.Action, dataTypes.PetAction, dataTypes.Flyout, dataTypes.Macro }) do
        if type(typeID) == "number" then Register(typeID, actionDispatcher) end
    end

    if type(addon.TYPE_NAME) == "table" then
        local genericDispatcher = CreateGenericDispatcher(unitType)
        for typeID in pairs(addon.TYPE_NAME) do
            if type(typeID) == "number" and not registered[typeID] then
                Register(typeID, genericDispatcher)
            end
        end
    end

    self.__RT_UseTDP = coreOK
    return coreOK
end

addon:InitTooltipDataProcessor()
