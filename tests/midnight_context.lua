local LibEvent = { attachTrigger = function() end }
LibStub = { GetLibrary = function() return LibEvent end }

Enum = {
    TooltipDataType = {
        Item = 1,
        Spell = 2,
        Unit = 3,
        UnitAura = 4,
        PetAction = 5,
        Flyout = 6,
        Macro = 7,
    },
}

local spellAuraSecret = false
C_Secrets = {
    HasSecretRestrictions = function() return false end,
    ShouldAurasBeSecret = function() return false end,
    ShouldCooldownsBeSecret = function() return false end,
    ShouldSpellAuraBeSecret = function() return spellAuraSecret end,
    ShouldUnitStatsBeSecret = function() return false end,
    ShouldUnitIdentityBeSecret = function() return false end,
    ShouldUnitHealthBeSecret = function() return false end,
    ShouldUnitHealthMaxBeSecret = function() return false end,
    CanCompareUnitTokens = function() return true end,
}

TooltipUtil = {}
function TooltipUtil.GetDisplayedItem(tooltip)
    return tooltip.itemName, tooltip.itemLink, tooltip.itemID
end
function TooltipUtil.GetDisplayedSpell(tooltip)
    return tooltip.spellName, tooltip.spellID
end
function TooltipUtil.GetDisplayedUnit(tooltip)
    return tooltip.unitName, tooltip.unitToken, tooltip.guid
end

C_Item = {
    GetItemInfoInstant = function(item)
        if item == "item:42" then return 42 end
        return type(item) == "number" and item or nil
    end,
}

function UnitTokenFromGUID(guid)
    if guid == "Player-1" then return "player" end
end

local inaccessible = {}
local addon = {}
function addon:CanAccessValue(value) return value ~= inaccessible end
function addon:CanAccessAllValues(...)
    for index = 1, select("#", ...) do
        if select(index, ...) == inaccessible then return false end
    end
    return true
end
function addon:SafeCall(_, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end
function addon:SafeCallBoolean(fn, ...)
    local value = self:SafeCall("bool", fn, ...)
    return value == nil and nil or value == true
end
function addon:SafeGet(object, key)
    if object == nil or object == inaccessible then return nil end
    return object[key]
end
function addon:IsObjectAccessible(object) return object ~= nil and object ~= inaccessible end
function addon:IsTooltipSafe(object) return self:IsObjectAccessible(object) end
function addon:SafeMethod(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return nil end
    return self:SafeCall(method, fn, object, ...)
end

assert(loadfile("Engine/Midnight.lua"))("RothTooltip", addon)

local function Tooltip()
    local tooltip = {}
    function tooltip:IsTooltipType(typeID)
        return self.nativeType == typeID
    end
    function tooltip:GetPrimaryTooltipData()
        return self.primaryData
    end
    function tooltip:GetSpell()
        return self.spellName, self.spellID
    end
    function tooltip:GetItem()
        return self.itemName, self.itemLink
    end
    function tooltip:GetUnit()
        return self.unitName, self.unitToken
    end
    function tooltip:IsShown() return true end
    return tooltip
end

local itemMacro = Tooltip()
itemMacro.itemName = "Item"
itemMacro.itemLink = "item:42"
itemMacro.itemID = 42
local context = addon:GetPrimaryTooltipContext(itemMacro, { type = Enum.TooltipDataType.Macro, id = 7 })
assert(context.type == Enum.TooltipDataType.Macro)
assert(context.itemID == 42 and context.hyperlink == "item:42")
assert(context.spellID == nil)

local spellMacro = Tooltip()
spellMacro.spellName = "Spell"
spellMacro.spellID = 99
context = addon:GetPrimaryTooltipContext(spellMacro, { type = Enum.TooltipDataType.Macro, id = 8 })
assert(context.type == Enum.TooltipDataType.Macro)
assert(context.itemID == nil and context.hyperlink == nil)
assert(context.spellID == 99)

local aura = Tooltip()
spellAuraSecret = false
context = addon:GetPrimaryTooltipContext(aura, { type = Enum.TooltipDataType.UnitAura, id = 123 })
assert(context.spellID == 123)
spellAuraSecret = true
context = addon:GetPrimaryTooltipContext(aura, { type = Enum.TooltipDataType.UnitAura, id = 123 })
assert(context.spellID == nil)
spellAuraSecret = false

local unitTip = Tooltip()
unitTip.unitToken = "player"
unitTip.guid = "Player-1"
context = addon:GetPrimaryTooltipContext(unitTip, {
    type = Enum.TooltipDataType.Unit,
    unitToken = "player",
    guid = "Player-1",
})
assert(context.unitToken == "player" and context.guid == "Player-1")

addon:SetPrimaryTooltipContext(unitTip, { type = 3, unitToken = "player" })
assert(addon:GetCachedTooltipContext(unitTip) ~= nil)
assert(addon:GetPrimaryTooltipContext(unitTip, inaccessible) == nil)
assert(addon:GetCachedTooltipContext(unitTip) == nil)

print("midnight_context: ok")
