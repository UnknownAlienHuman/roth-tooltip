local eventCallbacks = {}
local triggerLog = {}
local LibEvent = {}
function LibEvent:attachEvent(names, callback)
    for name in tostring(names):gmatch("([^,%s]+)") do
        eventCallbacks[name] = eventCallbacks[name] or {}
        table.insert(eventCallbacks[name], callback)
    end
end
function LibEvent:trigger(name, ...)
    triggerLog[#triggerLog + 1] = { name, ... }
end

LibStub = {
    GetLibrary = function(_, name)
        assert(name == "LibEvent.7000")
        return LibEvent
    end,
}

Enum = {
    TooltipDataType = {
        Item = 1,
        Spell = 2,
        Unit = 3,
        UnitAura = 4,
        Macro = 5,
    },
}

local afterCallbacks = {}
C_Timer = {}
function C_Timer.After(_, callback)
    afterCallbacks[#afterCallbacks + 1] = callback
end

function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local combat = false
function InCombatLockdown() return combat end

local restrictions = false
local contextsCleared = 0
local refreshes = {}
local redispatches = {}
local addon = {}
function addon:CanAccessValue() return true end
function addon:IsObjectAccessible(value) return value ~= nil end
function addon:IsTooltipSafe(value) return type(value) == "table" end
function addon:SafeMethod(object, method, ...)
    if method == "IsShown" then return object.shown == true end
    if method == "Hide" then object.shown = false; return true end
    if method == "GetParent" then return object.parent end
    local fn = object[method]
    if type(fn) == "function" then return fn(object, ...) end
end
function addon:SetPrimaryTooltipContext(tooltip, context)
    tooltip.context = context
end
function addon:GetPrimaryTooltipContext(tooltip)
    return tooltip.context
end
function addon:ClearTooltipContexts()
    contextsCleared = contextsCleared + 1
    for tooltip in pairs(self.tooltipSet or {}) do tooltip.context = nil end
end
function addon:RefreshTooltipSafe(tooltip, reason)
    refreshes[#refreshes + 1] = { tooltip, reason }
    return true
end
function addon:RedispatchTooltipContext(tooltip, context)
    redispatches[#redispatches + 1] = { tooltip, context }
    return true
end
function addon:HasSecretRestrictions() return restrictions end

assert(loadfile("Engine/TooltipRegistry.lua"))("RothTooltip", addon)
assert(type(addon.RegisterTooltipFrame) == "function")
assert(type(addon.RequestManagedTooltipRefresh) == "function")

local itemTip = { shown = true, context = { type = 1, itemID = 42, hyperlink = "item:42" } }
local unitTip = { shown = true, context = { type = 3, unitToken = "target" } }
local macroTip = { shown = true, context = { type = 5, itemID = 42, hyperlink = "item:42" } }
addon:RegisterTooltipFrame(itemTip)
addon:RegisterTooltipFrame(unitTip)
addon:RegisterTooltipFrame(macroTip)

assert(addon:RequestManagedTooltipRefresh(nil, "first") == 2)
assert(addon:RequestManagedTooltipRefresh(nil, "second") == 2)
assert(#afterCallbacks == 1, "refreshes were not coalesced")
afterCallbacks[1]()
assert(#refreshes == 2)
assert(refreshes[1][2] == "first" and refreshes[2][2] == "first")

refreshes = {}
afterCallbacks = {}
for _, callback in ipairs(eventCallbacks.MODIFIER_STATE_CHANGED or {}) do
    callback(callback, "LSHIFT", 1)
end
assert(#afterCallbacks == 1)
afterCallbacks[1]()
assert(#refreshes == 2)

refreshes = {}
afterCallbacks = {}
for _, callback in ipairs(eventCallbacks.GET_ITEM_INFO_RECEIVED or {}) do
    callback(callback, 42, true)
end
assert(#afterCallbacks == 1)
afterCallbacks[1]()
assert(#refreshes == 1 and refreshes[1][1] == itemTip)
assert(#redispatches == 1 and redispatches[1][1] == macroTip)

itemTip.shown, unitTip.shown, macroTip.shown = true, true, true
restrictions = true
for _, callback in ipairs(eventCallbacks.ADDON_RESTRICTION_STATE_CHANGED or {}) do
    callback(callback)
end
assert(itemTip.shown == false and unitTip.shown == false and macroTip.shown == false)
assert(contextsCleared >= 1)

-- Clearing restrictions retries idempotent setup instead of hiding again.
itemTip.shown = true
itemTip.context = { type = 1, itemID = 42, hyperlink = "item:42" }
restrictions = false
afterCallbacks = {}
for _, callback in ipairs(eventCallbacks.ADDON_RESTRICTION_STATE_CHANGED or {}) do
    callback(callback)
end
assert(itemTip.shown == true)
assert(#afterCallbacks == 1)

print("tooltip_registry: ok")
