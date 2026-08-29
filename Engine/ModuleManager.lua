-- RothTooltip event bus and module lifecycle owner.
--
-- Native event registration, custom triggers, callback attribution, and module
-- attach/detach are centralized here. Optional modules are attached only after
-- General selects the active SavedVariables store. Failed Init/Enable calls do
-- not leave a module marked attached and all registered links are rolled back.

local _, addon = ...

LibStub = LibStub or {
    GetLibrary = function(self, name) return self[name] end,
    NewLibrary = function(self, name) self[name] = self[name] or {}; return self[name] end,
}

local MAJOR, MINOR = "LibEvent.7000", 5
local lib = LibStub:NewLibrary(MAJOR, MINOR) or LibStub:GetLibrary(MAJOR)
if not lib then return end

local function WeakKeys(tbl)
    tbl = type(tbl) == "table" and tbl or {}
    return setmetatable(tbl, { __mode = "k" })
end

local function NewBucket()
    return { items = {}, depth = 0, dirty = false }
end

lib.events = lib.events or {}
lib.triggers = lib.triggers or {}
lib._muteUntil = WeakKeys(lib._muteUntil)
lib._errState = WeakKeys(lib._errState)
lib._errorSink = lib._errorSink or nil

local frame = lib._frame
if not frame then
    frame = CreateFrame("Frame")
    lib._frame = frame
end

local function Now()
    return GetTime and GetTime() or 0
end

local function Compact(bucket)
    if type(bucket) ~= "table" or bucket.depth > 0 or not bucket.dirty then return end
    local write = 1
    for read = 1, #bucket.items do
        local callback = bucket.items[read]
        if callback then bucket.items[write], write = callback, write + 1 end
    end
    for index = write, #bucket.items do bucket.items[index] = nil end
    bucket.dirty = false
end

local function BucketEmpty(bucket)
    if type(bucket) ~= "table" then return true end
    Compact(bucket)
    for index = 1, #bucket.items do
        if bucket.items[index] then return false end
    end
    return true
end

local function BucketContains(bucket, callback)
    if type(bucket) ~= "table" or type(callback) ~= "function" then return false end
    for index = 1, #bucket.items do
        if bucket.items[index] == callback then return true end
    end
    return false
end

local function BucketAdd(bucket, callback)
    if type(callback) ~= "function" or BucketContains(bucket, callback) then return false end
    bucket.items[#bucket.items + 1] = callback
    return true
end

local function BucketRemove(bucket, callback)
    if type(bucket) ~= "table" or type(callback) ~= "function" then return false end
    local removed = false
    for index = 1, #bucket.items do
        if bucket.items[index] == callback then
            bucket.items[index] = false
            bucket.dirty = true
            removed = true
        end
    end
    Compact(bucket)
    return removed
end

local function SplitNames(names)
    local result = {}
    for name in string.gmatch(names or "", "([^,%s]+)") do result[#result + 1] = name end
    return result
end

function lib:SetErrorSink(callback)
    self._errorSink = type(callback) == "function" and callback or nil
    return self
end

local function CallSafe(kind, eventName, callback, ...)
    if type(callback) ~= "function" then return end
    local now = Now()
    local muteUntil = lib._muteUntil[callback]
    if type(muteUntil) == "number" and muteUntil > now then return end

    local ok, errorMessage = pcall(callback, callback, ...)
    if ok then return end

    local state = lib._errState[callback]
    if type(state) ~= "table" or now - (state.windowStart or 0) > 10 then
        state = { windowStart = now, count = 0 }
        lib._errState[callback] = state
    end
    state.count = state.count + 1
    if state.count >= 3 then lib._muteUntil[callback] = now + 60 end

    if type(lib._errorSink) == "function" then
        pcall(lib._errorSink, kind, eventName, errorMessage, callback)
    end
end

local function DispatchBucket(bucket, kind, eventName, ...)
    if type(bucket) ~= "table" then return end
    bucket.depth = bucket.depth + 1
    local limit = #bucket.items
    for index = 1, limit do
        local callback = bucket.items[index]
        if callback then CallSafe(kind, eventName, callback, ...) end
    end
    bucket.depth = bucket.depth - 1
    Compact(bucket)
end

frame:SetScript("OnEvent", function(_, eventName, ...)
    DispatchBucket(lib.events[eventName], "event", eventName, ...)
end)

function lib:event(eventName, ...)
    DispatchBucket(self.events[eventName], "event", eventName, ...)
end

function lib:addEventListener(eventNames, callback)
    if type(callback) ~= "function" then return self, false, "callback is not a function" end
    local allRegistered = true
    local lastError

    for _, eventName in ipairs(SplitNames(eventNames)) do
        local bucket = self.events[eventName]
        if not bucket then
            local ok, errorMessage = pcall(frame.RegisterEvent, frame, eventName)
            if ok then
                bucket = NewBucket()
                self.events[eventName] = bucket
            else
                allRegistered = false
                lastError = errorMessage
                if type(self._errorSink) == "function" then
                    pcall(self._errorSink, "event-register", eventName, errorMessage, callback)
                end
            end
        end
        if bucket then BucketAdd(bucket, callback) end
    end
    return self, allRegistered, lastError
end

local function ReleaseEventIfEmpty(eventName)
    local bucket = lib.events[eventName]
    if not BucketEmpty(bucket) then return end
    lib.events[eventName] = nil
    pcall(frame.UnregisterEvent, frame, eventName)
end

function lib:removeEventListener(eventNames, callback)
    if type(eventNames) == "function" and callback == nil then
        callback = eventNames
        local names = {}
        for eventName in pairs(self.events) do names[#names + 1] = eventName end
        for _, eventName in ipairs(names) do
            BucketRemove(self.events[eventName], callback)
            ReleaseEventIfEmpty(eventName)
        end
        return self
    end

    if type(callback) ~= "function" then return self end
    for _, eventName in ipairs(SplitNames(eventNames)) do
        BucketRemove(self.events[eventName], callback)
        ReleaseEventIfEmpty(eventName)
    end
    return self
end

function lib:addEventListenerOnce(eventName, callback)
    if type(callback) ~= "function" then return self, false end
    local wrapper
    wrapper = function(_, ...)
        lib:removeEventListener(eventName, wrapper)
        return callback(callback, ...)
    end
    return self:addEventListener(eventName, wrapper)
end

function lib:addTriggerListener(triggerNames, callback)
    if type(callback) ~= "function" then return self, false end
    for _, triggerName in ipairs(SplitNames(triggerNames)) do
        local bucket = self.triggers[triggerName]
        if not bucket then bucket = NewBucket(); self.triggers[triggerName] = bucket end
        BucketAdd(bucket, callback)
    end
    return self, true
end

function lib:removeTriggerListener(triggerNames, callback)
    if type(triggerNames) == "function" and callback == nil then
        callback = triggerNames
        local names = {}
        for triggerName in pairs(self.triggers) do names[#names + 1] = triggerName end
        for _, triggerName in ipairs(names) do
            local bucket = self.triggers[triggerName]
            BucketRemove(bucket, callback)
            if BucketEmpty(bucket) then self.triggers[triggerName] = nil end
        end
        return self
    end

    if type(callback) ~= "function" then return self end
    for _, triggerName in ipairs(SplitNames(triggerNames)) do
        local bucket = self.triggers[triggerName]
        BucketRemove(bucket, callback)
        if BucketEmpty(bucket) then self.triggers[triggerName] = nil end
    end
    return self
end

function lib:removeAllTriggers(triggerName)
    self.triggers[triggerName] = nil
    return self
end

function lib:addTriggerListenerOnce(triggerName, callback)
    if type(callback) ~= "function" then return self, false end
    local wrapper
    wrapper = function(_, ...)
        lib:removeTriggerListener(triggerName, wrapper)
        return callback(callback, ...)
    end
    return self:addTriggerListener(triggerName, wrapper)
end

function lib:trigger(triggerName, ...)
    DispatchBucket(self.triggers[triggerName], "trigger", triggerName, ...)
end

lib.attachEvent = lib.addEventListener
lib.attachEventOnce = lib.addEventListenerOnce
lib.detachEvent = lib.removeEventListener
lib.attachTrigger = lib.addTriggerListener
lib.attachTriggerOnce = lib.addTriggerListenerOnce
lib.detachTrigger = lib.removeTriggerListener
lib.detachAllTriggers = lib.removeAllTriggers
addon.LibEvent = lib

addon.MM = addon.MM or {}
local MM = addon.MM

MM.meta = WeakKeys(MM.meta)
MM.state = MM.state or {}
MM.modules = MM.modules or {}
MM.links = MM.links or {}
MM.triggerCounts = MM.triggerCounts or {}
MM.core = MM.core or { General = true }
MM.applyingSaved = false

local function EnsureState(moduleName)
    local state = MM.state[moduleName]
    if type(state) ~= "table" then
        state = {
            initialized = false,
            enabled = true,
            attached = false,
            calls = 0,
            errors = 0,
            lastError = nil,
            lastHook = nil,
            lastAt = 0,
            lastMs = 0,
        }
        MM.state[moduleName] = state
    end
    return state
end

local function EnsureModulesDB()
    if type(addon.db) ~= "table" then return nil end
    if type(addon.db.modules) ~= "table" then addon.db.modules = {} end
    return addon.db.modules
end

local function FindLink(moduleName, kind, eventName, original)
    local links = MM.links[moduleName]
    if type(links) ~= "table" then return nil end
    for index = 1, #links do
        local link = links[index]
        if link.kind == kind and link.event == eventName and link.original == original then
            return link
        end
    end
end

local function AddLink(moduleName, kind, eventName, original, wrapper, hook)
    if FindLink(moduleName, kind, eventName, original) then return false end
    local links = MM.links[moduleName]
    if type(links) ~= "table" then links = {}; MM.links[moduleName] = links end
    links[#links + 1] = {
        kind = kind,
        event = eventName,
        original = original,
        wrapper = wrapper,
        hook = hook,
    }
    return true
end

function MM:Track(moduleName, callback, hook)
    if type(callback) ~= "function" then return end
    self.meta[callback] = { module = tostring(moduleName or "?"), hook = tostring(hook or "?") }
end

function MM:OnError(callback, errorMessage)
    local metadata = self.meta[callback]
    if type(metadata) ~= "table" then return nil end
    local state = EnsureState(metadata.module)
    state.errors = state.errors + 1
    state.lastError = addon:SafeToString(errorMessage, "?")
    state.lastHook = metadata.hook
    state.lastAt = Now()
    return metadata.module, metadata.hook
end

local function LogLifecycleError(moduleName, phase, errorMessage)
    local state = EnsureState(moduleName)
    state.errors = state.errors + 1
    state.lastError = addon:SafeToString(errorMessage, "?")
    state.lastHook = phase
    state.lastAt = Now()
    if addon.DoctorLog then
        addon:DoctorLog("lua", moduleName .. ":" .. phase, errorMessage, nil)
    end
end

local function InvokeModule(moduleName, phase, fn, moduleObject, ...)
    if type(fn) ~= "function" then return true end
    local ok, errorMessage = pcall(fn, moduleObject, ...)
    if not ok then LogLifecycleError(moduleName, phase, errorMessage) end
    return ok
end

local function EnsureInitialized(moduleName, moduleObject)
    local state = EnsureState(moduleName)
    if state.initialized then return true end
    if not InvokeModule(moduleName, "Init", moduleObject.Init, moduleObject, addon) then return false end
    state.initialized = true
    moduleObject.__rtInitialized = true
    return true
end

function MM:IsEnabled(moduleName)
    moduleName = tostring(moduleName or "?")
    if self.core[moduleName] then return true end
    return EnsureState(moduleName).enabled ~= false
end

function MM:OnCallStart(moduleName, hook)
    moduleName = tostring(moduleName or "?")
    if not self:IsEnabled(moduleName) then return nil end
    local state = EnsureState(moduleName)
    state.calls = state.calls + 1
    state.lastHook = hook or state.lastHook
    state.lastAt = Now()
    return state.lastAt
end

function MM:OnCallEnd(moduleName, startedAt)
    if type(startedAt) ~= "number" then return end
    EnsureState(tostring(moduleName or "?")).lastMs = math.max(0, Now() - startedAt) * 1000
end

function MM:HasTriggerSubscribers(triggerName)
    return type(triggerName) == "string" and (self.triggerCounts[triggerName] or 0) > 0
end

local function MakeModuleWrapper(moduleName, callback, hook)
    local wrapper
    wrapper = function(_, ...)
        if not MM:IsEnabled(moduleName) then return end
        local startedAt = MM:OnCallStart(moduleName, hook)
        callback(callback, ...)
        MM:OnCallEnd(moduleName, startedAt)
    end
    MM:Track(moduleName, wrapper, hook)
    return wrapper
end

function MM:AttachTrigger(moduleName, triggerNames, callback, hook)
    if type(callback) ~= "function" then error("AttachTrigger callback is not a function", 2) end
    moduleName = tostring(moduleName or "?")

    for _, triggerName in ipairs(SplitNames(triggerNames)) do
        if not FindLink(moduleName, "trigger", triggerName, callback) then
            local wrapper = MakeModuleWrapper(moduleName, callback, hook or triggerName)
            local _, registered = lib:attachTrigger(triggerName, wrapper)
            if not registered then
                self.meta[wrapper] = nil
                error("failed to attach trigger " .. triggerName, 2)
            end
            AddLink(moduleName, "trigger", triggerName, callback, wrapper, hook or triggerName)
            self.triggerCounts[triggerName] = (self.triggerCounts[triggerName] or 0) + 1
        end
    end
end

function MM:AttachEvent(moduleName, eventNames, callback, hook)
    if type(callback) ~= "function" then error("AttachEvent callback is not a function", 2) end
    moduleName = tostring(moduleName or "?")

    for _, eventName in ipairs(SplitNames(eventNames)) do
        if not FindLink(moduleName, "event", eventName, callback) then
            local wrapper = MakeModuleWrapper(moduleName, callback, hook or eventName)
            local _, registered, errorMessage = lib:attachEvent(eventName, wrapper)
            if not registered then
                self.meta[wrapper] = nil
                error("failed to attach event " .. eventName .. ": "
                    .. addon:SafeToString(errorMessage, "unknown error"), 2)
            end
            AddLink(moduleName, "event", eventName, callback, wrapper, hook or eventName)
        end
    end
end

function MM:Detach(moduleName)
    moduleName = tostring(moduleName or "?")
    local links = self.links[moduleName]
    if type(links) ~= "table" then return end

    for index = #links, 1, -1 do
        local link = links[index]
        if link.kind == "trigger" then
            lib:detachTrigger(link.event, link.wrapper)
            self.triggerCounts[link.event] = math.max(0, (self.triggerCounts[link.event] or 1) - 1)
            if self.triggerCounts[link.event] == 0 then self.triggerCounts[link.event] = nil end
        else
            lib:detachEvent(link.event, link.wrapper)
        end
        self.meta[link.wrapper] = nil
        links[index] = nil
    end
    EnsureState(moduleName).attached = false
end

function MM:RegisterModule(moduleName, moduleObject)
    if type(moduleName) ~= "string" or moduleName == "" or type(moduleObject) ~= "table" then return false end
    local existing = self.modules[moduleName]
    if existing and existing ~= moduleObject then
        LogLifecycleError(moduleName, "Register", "duplicate module owner")
        return false
    end

    self.modules[moduleName] = moduleObject
    self.links[moduleName] = self.links[moduleName] or {}
    local state = EnsureState(moduleName)
    if not EnsureInitialized(moduleName, moduleObject) then return false end

    if self.core[moduleName] then
        local enabled = self:Enable(moduleName, true)
        local db = EnsureModulesDB()
        if db then db[moduleName] = true end
        return enabled
    end

    if addon.__RT_VariablesLoaded ~= true then
        state.attached = false
        return true
    end

    local db = EnsureModulesDB()
    if db and db[moduleName] == false then self:Disable(moduleName, true)
    else self:Enable(moduleName, true) end
    return true
end

function MM:Enable(moduleName, silent)
    moduleName = tostring(moduleName or "")
    if moduleName == "" then return false end
    if not self.core[moduleName] and addon.__RT_VariablesLoaded ~= true then return false end

    local moduleObject = self.modules[moduleName]
    if type(moduleObject) ~= "table" or not EnsureInitialized(moduleName, moduleObject) then return false end

    local state = EnsureState(moduleName)
    if state.enabled ~= false and state.attached then return true end

    state.enabled = true
    local db = EnsureModulesDB()
    if db then db[moduleName] = true end

    if not InvokeModule(moduleName, "Enable", moduleObject.Enable, moduleObject) then
        self:Detach(moduleName)
        state.enabled = false
        state.attached = false
        return false
    end

    state.attached = true
    return true
end

function MM:Disable(moduleName, silent)
    moduleName = tostring(moduleName or "")
    if moduleName == "" then return false end
    if self.core[moduleName] then EnsureState(moduleName).enabled = true return false end

    local state = EnsureState(moduleName)
    state.enabled = false
    local db = EnsureModulesDB()
    if db then db[moduleName] = false end

    self:Detach(moduleName)
    local moduleObject = self.modules[moduleName]
    if type(moduleObject) == "table" then
        InvokeModule(moduleName, "Disable", moduleObject.Disable, moduleObject)
    end
    return true
end

function MM:Toggle(moduleName)
    if self:IsEnabled(moduleName) then return self:Disable(moduleName) end
    return self:Enable(moduleName)
end

function MM:ApplySaved()
    if self.applyingSaved or addon.__RT_VariablesLoaded ~= true then return end
    self.applyingSaved = true

    local db = EnsureModulesDB()
    if db then
        for coreName in pairs(self.core) do db[coreName] = true end
        local names = {}
        for moduleName in pairs(self.modules) do names[#names + 1] = moduleName end
        table.sort(names)
        for _, moduleName in ipairs(names) do
            if db[moduleName] == false and not self.core[moduleName] then
                self:Disable(moduleName, true)
            else
                self:Enable(moduleName, true)
            end
        end
    end
    self.applyingSaved = false
end

function MM:ExportText()
    local names = {}
    for moduleName in pairs(self.state) do names[#names + 1] = moduleName end
    table.sort(names)
    local output = {
        "RothTooltip Modules",
        "Name\tInit\tEnabled\tAttached\tCalls\tErrors\tLast(ms)\tLastHook\tLastError",
    }
    for _, moduleName in ipairs(names) do
        local state = EnsureState(moduleName)
        output[#output + 1] = string.format(
            "%s\t%s\t%s\t%s\t%d\t%d\t%.1f\t%s\t%s",
            moduleName,
            state.initialized and "1" or "0",
            self:IsEnabled(moduleName) and "1" or "0",
            state.attached and "1" or "0",
            state.calls or 0,
            state.errors or 0,
            state.lastMs or 0,
            tostring(state.lastHook or ""),
            tostring(state.lastError or "")
        )
    end
    return table.concat(output, "\n")
end

function addon:EnableModule(moduleName)
    return self.MM and self.MM:Enable(moduleName)
end

function addon:DisableModule(moduleName)
    return self.MM and self.MM:Disable(moduleName)
end

function addon:ToggleModule(moduleName)
    return self.MM and self.MM:Toggle(moduleName)
end

lib:attachTrigger("tooltip:variables:loaded", function()
    MM:ApplySaved()
end)
