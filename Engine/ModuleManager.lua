-- RothTooltip Engine: event bus and module lifecycle owner.
--
-- One layer owns native event registration, custom trigger subscriptions,
-- callback attribution, and module enable/disable cleanup. Feature modules do
-- not need their own dispatcher, pending queue, or registration bookkeeping.

local _, addon = ...

LibStub = LibStub or {
    GetLibrary = function(self, name) return self[name] end,
    NewLibrary = function(self, name) self[name] = self[name] or {}; return self[name] end,
}

local MAJOR, MINOR = "LibEvent.7000", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    lib = LibStub:GetLibrary(MAJOR)
end
if not lib then return end

local function NewBucket()
    return { items = {}, depth = 0, dirty = false }
end

lib.events = lib.events or {}
lib.triggers = lib.triggers or {}
lib._muteUntil = lib._muteUntil or {}
lib._errState = lib._errState or {}
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

    local items = bucket.items
    local write = 1
    for read = 1, #items do
        local callback = items[read]
        if callback then
            items[write] = callback
            write = write + 1
        end
    end
    for index = write, #items do
        items[index] = nil
    end
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
    if state.count >= 3 then
        lib._muteUntil[callback] = now + 60
    end

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
        if callback then
            CallSafe(kind, eventName, callback, ...)
        end
    end
    bucket.depth = bucket.depth - 1
    Compact(bucket)
end

frame:SetScript("OnEvent", function(_, eventName, ...)
    DispatchBucket(lib.events[eventName], "event", eventName, ...)
end)

local function SplitNames(names)
    local result = {}
    for name in string.gmatch(names or "", "([^,%s]+)") do
        result[#result + 1] = name
    end
    return result
end

function lib:event(eventName, ...)
    DispatchBucket(self.events[eventName], "event", eventName, ...)
end

function lib:addEventListener(eventNames, callback)
    if type(callback) ~= "function" then return self end

    for _, eventName in ipairs(SplitNames(eventNames)) do
        local bucket = self.events[eventName]
        if not bucket then
            bucket = NewBucket()
            self.events[eventName] = bucket
            local ok, errorMessage = pcall(frame.RegisterEvent, frame, eventName)
            if not ok then
                self.events[eventName] = nil
                if type(self._errorSink) == "function" then
                    pcall(self._errorSink, "event-register", eventName, errorMessage, callback)
                end
            end
        end
        if self.events[eventName] then
            BucketAdd(self.events[eventName], callback)
        end
    end
    return self
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
    if type(callback) ~= "function" then return self end
    local wrapper
    wrapper = function(_, ...)
        lib:removeEventListener(eventName, wrapper)
        return callback(callback, ...)
    end
    return self:addEventListener(eventName, wrapper)
end

function lib:addTriggerListener(triggerNames, callback)
    if type(callback) ~= "function" then return self end
    for _, triggerName in ipairs(SplitNames(triggerNames)) do
        local bucket = self.triggers[triggerName]
        if not bucket then
            bucket = NewBucket()
            self.triggers[triggerName] = bucket
        end
        BucketAdd(bucket, callback)
    end
    return self
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
    if type(callback) ~= "function" then return self end
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

MM.meta = MM.meta or {}
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

local function AddLink(moduleName, kind, eventName, original, wrapper, hook)
    local links = MM.links[moduleName]
    if type(links) ~= "table" then
        links = {}
        MM.links[moduleName] = links
    end

    for index = 1, #links do
        local link = links[index]
        if link.kind == kind and link.event == eventName and link.original == original then
            return false
        end
    end

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
    self.meta[callback] = {
        module = tostring(moduleName or "?"),
        hook = tostring(hook or "?"),
    }
end

function MM:OnError(callback, errorMessage)
    local metadata = self.meta[callback]
    if type(metadata) ~= "table" then return nil end

    local state = EnsureState(metadata.module)
    state.errors = state.errors + 1
    state.lastError = addon.SafeToString and addon:SafeToString(errorMessage, "?") or tostring(errorMessage or "?")
    state.lastHook = metadata.hook
    state.lastAt = Now()
    return metadata.module, metadata.hook
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
    local state = EnsureState(tostring(moduleName or "?"))
    local elapsed = Now() - startedAt
    state.lastMs = math.max(0, elapsed) * 1000
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
    if type(callback) ~= "function" then return end
    moduleName = tostring(moduleName or "?")

    for _, triggerName in ipairs(SplitNames(triggerNames)) do
        local wrapper = MakeModuleWrapper(moduleName, callback, hook or triggerName)
        if AddLink(moduleName, "trigger", triggerName, callback, wrapper, hook or triggerName) then
            lib:attachTrigger(triggerName, wrapper)
            self.triggerCounts[triggerName] = (self.triggerCounts[triggerName] or 0) + 1
        else
            self.meta[wrapper] = nil
        end
    end
end

function MM:AttachEvent(moduleName, eventNames, callback, hook)
    if type(callback) ~= "function" then return end
    moduleName = tostring(moduleName or "?")

    for _, eventName in ipairs(SplitNames(eventNames)) do
        local wrapper = MakeModuleWrapper(moduleName, callback, hook or eventName)
        if AddLink(moduleName, "event", eventName, callback, wrapper, hook or eventName) then
            lib:attachEvent(eventName, wrapper)
        else
            self.meta[wrapper] = nil
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
        elseif link.kind == "event" then
            lib:detachEvent(link.event, link.wrapper)
        end
        self.meta[link.wrapper] = nil
        links[index] = nil
    end
    EnsureState(moduleName).attached = false
end

function MM:RegisterModule(moduleName, moduleObject)
    if type(moduleName) ~= "string" or moduleName == "" or type(moduleObject) ~= "table" then return end

    self.modules[moduleName] = moduleObject
    self.links[moduleName] = self.links[moduleName] or {}
    local state = EnsureState(moduleName)

    if not moduleObject.__rtInitialized and type(moduleObject.Init) == "function" then
        moduleObject.__rtInitialized = true
        addon:SafeCall(moduleName .. ":Init", moduleObject.Init, moduleObject, addon)
    end

    if self.core[moduleName] then
        self:Enable(moduleName, true)
        local db = EnsureModulesDB()
        if db then db[moduleName] = true end
        return
    end

    local db = EnsureModulesDB()
    if db then
        if db[moduleName] == false then
            self:Disable(moduleName, true)
        else
            self:Enable(moduleName, true)
        end
    else
        state.enabled = true
    end
end

function MM:Enable(moduleName, silent)
    moduleName = tostring(moduleName or "")
    if moduleName == "" then return end

    local state = EnsureState(moduleName)
    if state.enabled ~= false and state.attached then return end

    state.enabled = true
    local db = EnsureModulesDB()
    if db then db[moduleName] = true end

    local moduleObject = self.modules[moduleName]
    if moduleObject and type(moduleObject.Enable) == "function" then
        addon:SafeCall(moduleName .. ":Enable", moduleObject.Enable, moduleObject)
    end
    state.attached = true
end

function MM:Disable(moduleName, silent)
    moduleName = tostring(moduleName or "")
    if moduleName == "" then return end
    if self.core[moduleName] then
        EnsureState(moduleName).enabled = true
        return
    end

    local state = EnsureState(moduleName)
    if state.enabled == false and not state.attached then return end
    state.enabled = false

    local db = EnsureModulesDB()
    if db then db[moduleName] = false end

    self:Detach(moduleName)
    local moduleObject = self.modules[moduleName]
    if moduleObject and type(moduleObject.Disable) == "function" then
        addon:SafeCall(moduleName .. ":Disable", moduleObject.Disable, moduleObject)
    end
end

function MM:Toggle(moduleName)
    if self:IsEnabled(moduleName) then self:Disable(moduleName) else self:Enable(moduleName) end
end

function MM:ApplySaved()
    if self.applyingSaved then return end
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
        "Name\tEnabled\tAttached\tCalls\tErrors\tLast(ms)\tLastHook\tLastError",
    }
    for _, moduleName in ipairs(names) do
        local state = EnsureState(moduleName)
        output[#output + 1] = string.format(
            "%s\t%s\t%s\t%d\t%d\t%.1f\t%s\t%s",
            moduleName,
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
    if self.MM then self.MM:Enable(moduleName) end
end

function addon:DisableModule(moduleName)
    if self.MM then self.MM:Disable(moduleName) end
end

function addon:ToggleModule(moduleName)
    if self.MM then self.MM:Toggle(moduleName) end
end

lib:attachTrigger("tooltip:variables:loaded", function()
    MM:ApplySaved()
end)
