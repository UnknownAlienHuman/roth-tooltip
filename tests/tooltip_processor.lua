local events = {}
local LibEvent = {}
function LibEvent:trigger(name, ...)
    events[#events + 1] = { name = name, args = { ... } }
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
        PetAction = 5,
        Flyout = 6,
        Macro = 7,
        Quest = 8,
    },
}

local postCalls = {}
TooltipDataProcessor = {}
function TooltipDataProcessor.AddTooltipPostCall(typeID, callback)
    postCalls[typeID] = callback
end

function InCombatLockdown() return false end
function IsInRaid() return false end
function IsInInstance() return false, "none" end

local addon = {
    db = { general = { visibility = {} } },
    TYPE_NAME = { [8] = "Quest" },
}
addon.MM = {}
function addon.MM:HasTriggerSubscribers() return true end
function addon:CanAccessValue() return true end
function addon:IsManagedTooltip() return true end
function addon:IsTooltipSafe() return true end
function addon:AllowTrigger() return true end
function addon:GetPrimaryTooltipContext(_, data) return data end
function addon:SetPrimaryTooltipContext(_, data) self.lastContext = data end
function addon:SafeCall(_, fn, ...) return fn(...) end
function addon:SafeCallBoolean(fn, ...) return fn(...) and true or false end
function addon:SafeToString(value) return tostring(value) end
function addon:SafeMethod(_, method)
    if method == "IsShown" then return true end
    if method == "Hide" then return true end
end
function addon:IsBag() return false end
function addon:IsActionBar() return false end
function addon:DoctorLog(...)
    error("unexpected DoctorLog")
end

assert(loadfile("Engine/TooltipProcessor.lua"))("RothTooltip", addon)
for typeID = 1, 8 do assert(postCalls[typeID], "missing post-call " .. typeID) end

local tooltip = {}
local function Reset() events = {} end
local function LastName() return events[#events] and events[#events].name end

Reset()
local macroItem = { type = 7, id = 7, itemID = 42, hyperlink = "item:42", spellID = 99 }
postCalls[7](tooltip, macroItem)
assert(#events == 1 and LastName() == "tooltip:item")
assert(events[1].args[1] == tooltip)
assert(events[1].args[2] == "item:42")
assert(events[1].args[3] == macroItem)

Reset()
local macroSpell = { type = 7, id = 7, spellID = 99 }
postCalls[7](tooltip, macroSpell)
assert(#events == 1 and LastName() == "tooltip:spell")
assert(events[1].args[2] == macroSpell)

Reset()
local aura = { type = 4, id = 123, spellID = 123 }
postCalls[4](tooltip, aura)
assert(#events == 1 and LastName() == "tooltip:aura")
assert(events[1].args[2] == nil)
assert(events[1].args[3] == 123)
assert(events[1].args[4] == aura)

Reset()
local unit = { type = 3, unitToken = "target", guid = "Creature-0-0-0-0-1" }
postCalls[3](tooltip, unit)
assert(#events == 1 and LastName() == "tooltip:unit")
assert(events[1].args[2] == "target")
assert(events[1].args[3] == unit.guid)

Reset()
local quest = { type = 8, id = 777 }
postCalls[8](tooltip, quest)
assert(#events == 1 and LastName() == "tooltip:genericid")
assert(events[1].args[2] == "Quest")
assert(events[1].args[3] == 777)

Reset()
assert(addon:RedispatchTooltipContext(tooltip, macroItem) == true)
assert(#events == 1 and LastName() == "tooltip:item")

Reset()
assert(addon:RedispatchTooltipContext(tooltip, {}) == false)
assert(#events == 0)

print("tooltip_processor: ok")
