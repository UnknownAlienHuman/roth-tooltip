local libraries = {}
LibStub = {
    NewLibrary = function(_, name)
        libraries[name] = libraries[name] or {}
        return libraries[name]
    end,
    GetLibrary = function(_, name)
        return libraries[name]
    end,
}

local now = 0
function GetTime()
    now = now + 0.001
    return now
end

local failEvent = true
local registered = {}
local frame = {}
function frame:SetScript(name, callback)
    self[name] = callback
end
function frame:RegisterEvent(name)
    if failEvent and name == "FAIL_EVENT" then error("event unavailable") end
    registered[name] = true
end
function frame:UnregisterEvent(name)
    registered[name] = nil
end
function CreateFrame()
    return frame
end

local doctorErrors = {}
local addon = {
    db = { modules = {} },
    __RT_VariablesLoaded = true,
}
function addon:SafeToString(value, fallback)
    if value == nil then return fallback end
    return tostring(value)
end
function addon:DoctorLog(kind, owner, message)
    doctorErrors[#doctorErrors + 1] = { kind, owner, tostring(message) }
end

assert(loadfile("Engine/ModuleManager.lua"))("RothTooltip", addon)
assert(addon.MM and addon.LibEvent)

local callbackCalls = 0
local broken = {}
function broken:Init()
    self.initialized = (self.initialized or 0) + 1
end
function broken:Enable()
    addon.MM:AttachEvent("Broken", "GOOD_EVENT, FAIL_EVENT", function()
        callbackCalls = callbackCalls + 1
    end, "broken-events")
end
function broken:Disable()
    self.disabled = (self.disabled or 0) + 1
end

addon.MM:RegisterModule("Broken", broken)
local state = addon.MM.state.Broken
assert(state.initialized == true)
assert(state.enabled == false)
assert(state.attached == false)
assert(addon.db.modules.Broken == false)
assert(registered.GOOD_EVENT == nil)
assert(registered.FAIL_EVENT == nil)
assert(#(addon.MM.links.Broken or {}) == 0)
assert(state.errors >= 1)
assert(#doctorErrors >= 1)

failEvent = false
assert(addon.MM:Enable("Broken") == true)
assert(state.enabled == true)
assert(state.attached == true)
assert(addon.db.modules.Broken == true)
assert(registered.GOOD_EVENT == true)
assert(registered.FAIL_EVENT == true)
assert(broken.initialized == 1)

addon.LibEvent:event("GOOD_EVENT")
assert(callbackCalls == 1)
assert(addon.MM:Disable("Broken") == true)
assert(state.enabled == false)
assert(state.attached == false)
assert(registered.GOOD_EVENT == nil)
assert(registered.FAIL_EVENT == nil)
assert(broken.disabled == 1)

local initFailure = {}
function initFailure:Init()
    error("init failed")
end
function initFailure:Enable()
    error("must not run")
end
addon.MM:RegisterModule("InitFailure", initFailure)
local initState = addon.MM.state.InitFailure
assert(initState.initialized == false)
assert(initState.enabled == false)
assert(initState.attached == false)
assert(addon.db.modules.InitFailure ~= true)

local explicitFailure = {}
function explicitFailure:Init() end
function explicitFailure:Enable()
    return false
end
addon.MM:RegisterModule("ExplicitFailure", explicitFailure)
local explicitState = addon.MM.state.ExplicitFailure
assert(explicitState.initialized == true)
assert(explicitState.enabled == false)
assert(explicitState.attached == false)
assert(addon.db.modules.ExplicitFailure == false)

print("module_lifecycle: ok")
