local _, addon = ...

local bus = { events = {}, triggers = {}, depth = 0, pending = {} }
local MM = { modules = {}, order = {}, state = {}, core = { General = true }, _links = {},
    meta = setmetatable({}, { __mode = "k" }) }
addon.LibEvent, addon.MM = bus, MM

local frame = CreateFrame("Frame")
local variablesLoaded = false
local applyingSaved = false

local Now = GetTime

local function State(name)
    local state = MM.state[name]
    if not state then
        state = { enabled = false, initialized = false, calls = 0, errs = 0, lastMs = 0 }
        MM.state[name] = state
    end
    return state
end

local function SaveEnabled(name, enabled)
    if not variablesLoaded or type(addon.db) ~= "table" then return end
    addon.db.modules = addon.db.modules or {}
    addon.db.modules[name] = enabled
end

function MM:Track(name, fn, hook)
    self.meta[fn] = { module = name, hook = hook }
end

function MM:OnError(fn, err)
    local meta = self.meta[fn]
    if not meta then return end
    local state = State(meta.module)
    state.errs = state.errs + 1
    local text = addon:SafeToString(err, "<inaccessible error>")
    state.lastErr = type(text) == "string"
        and (#text > 1024 and text:sub(1, 1021) .. "..." or text)
        or "<inaccessible error>"
    state.lastHook, state.lastAt = meta.hook, Now()
    return meta.module, meta.hook
end

local function Report(kind, where, err, fn)
    local text = addon:SafeToString(err, "<inaccessible error>")
    if bus.errorSink then
        pcall(bus.errorSink, kind, where, text, fn)
    else
        MM:OnError(fn, text)
    end
end

function bus:SetErrorSink(fn)
    assert(fn == nil or type(fn) == "function", "invalid error sink")
    self.errorSink = fn
    return self
end

local function Compact(list)
    if list.depth > 0 or not list.dirty then return end
    list.dirty = false
    local count = 0
    for index = 1, #list do
        local entry = list[index]
        if entry.active then count = count + 1; list[count] = entry end
    end
    for index = #list, count + 1, -1 do list[index] = nil end
end

local function Remove(entry)
    if not entry.active then return end
    entry.active = false
    local list = entry.list
    list.count = list.count - 1
    list.dirty = true
    if list.count == 0 then
        list.bucket[list.name] = nil
        if list.bucket == bus.events then frame:UnregisterEvent(list.name) end
    end
    Compact(list)
end

local function Subscribe(bucket, name, fn, owner, hook)
    local list = bucket[name]
    if not list then
        if bucket == bus.events then frame:RegisterEvent(name) end
        list = { bucket = bucket, name = name, count = 0, depth = 0 }
        bucket[name] = list
    end
    for _, entry in ipairs(list) do
        if entry.active and entry.fn == fn and entry.owner == owner then return end
    end
    local entry = { fn = fn, owner = owner, hook = hook, active = true, list = list }
    if bus.depth > 0 then
        entry.pending = true
        bus.pending[#bus.pending + 1] = entry
    end
    list[#list + 1], list.count = entry, list.count + 1
    return entry
end

local function Attach(bucket, names, fn, owner, hook)
    assert(type(names) == "string" and type(fn) == "function", "invalid subscription")
    local created = {}
    local ok, err = pcall(function()
        for name in names:gmatch("[^,%s]+") do
            local entry = Subscribe(bucket, name, fn, owner, hook)
            if entry then created[#created + 1] = entry end
        end
    end)
    if not ok then
        for _, entry in ipairs(created) do Remove(entry) end
        error(addon:SafeToString(err, "event registration failed"), 0)
    end
    if owner then
        local links = MM._links[owner]
        for _, entry in ipairs(created) do links[#links + 1] = entry end
        for _, entry in ipairs(created) do MM:Track(owner, entry, hook or entry.list.name) end
    end
end

local function Detach(bucket, names, fn)
    local function Clear(list, callback)
        if not list then return end
        list.depth = list.depth + 1
        for _, entry in ipairs(list) do
            if callback == nil or entry.fn == callback then Remove(entry) end
        end
        list.depth = list.depth - 1
        Compact(list)
    end
    if type(names) == "function" then
        local lists = {}
        for _, list in pairs(bucket) do lists[#lists + 1] = list end
        for _, list in ipairs(lists) do Clear(list, names) end
    elseif type(names) == "string" then
        for name in names:gmatch("[^,%s]+") do Clear(bucket[name], fn) end
    end
end

function MM:IsEnabled(name)
    local state = self.state[name]
    return state ~= nil and state.enabled == true
end

function MM:OnCallStart(name, hook)
    if not self:IsEnabled(name) then return nil end
    local state = State(name)
    state.calls, state.lastHook, state.lastAt = state.calls + 1, hook, Now()
    return state.lastAt
end

function MM:OnCallEnd(name, started)
    if started then State(name).lastMs = math.max(0, Now() - started) * 1000 end
end

local function Dispatch(bucket, name, ...)
    local list = bucket[name]
    if not list then return end
    bus.depth, list.depth = bus.depth + 1, list.depth + 1
    -- Subscriptions created by any nested dispatch wait until the outermost
    -- transaction ends; removals still take effect immediately.
    local limit = #list
    for index = 1, limit do
        local entry = list[index]
        if entry.active and not entry.pending and (not entry.owner or MM:IsEnabled(entry.owner))
            and (not entry.mutedUntil or entry.mutedUntil <= Now()) then
            local started = entry.owner and MM:OnCallStart(entry.owner, entry.hook)
            local ok, err = pcall(entry.fn, entry.fn, ...)
            if entry.owner then MM:OnCallEnd(entry.owner, started) end
            if not ok then
                local now = Now()
                if not entry.errorAt or now - entry.errorAt > 10 then
                    entry.errorAt, entry.errors = now, 0
                end
                entry.errors = entry.errors + 1
                if entry.errors >= 3 then entry.mutedUntil = now + 60 end
                Report(bucket == bus.events and "event" or "trigger", name, err, entry.owner and entry or entry.fn)
            end
        end
    end
    list.depth, bus.depth = list.depth - 1, bus.depth - 1
    Compact(list)
    if bus.depth == 0 and #bus.pending > 0 then
        for _, entry in ipairs(bus.pending) do
            if entry.active then entry.pending = nil end
        end
        for index = #bus.pending, 1, -1 do bus.pending[index] = nil end
    end
end

function bus:addEventListener(names, fn) Attach(self.events, names, fn); return self end
function bus:addTriggerListener(names, fn) Attach(self.triggers, names, fn); return self end
function bus:removeEventListener(names, fn) Detach(self.events, names, fn); return self end
function bus:removeTriggerListener(names, fn) Detach(self.triggers, names, fn); return self end
function bus:removeAllTriggers(names) Detach(self.triggers, names); return self end
function bus:event(name, ...) Dispatch(self.events, name, ...) end
function bus:trigger(name, ...) Dispatch(self.triggers, name, ...) end

function bus:addEventListenerOnce(names, fn)
    return self:addEventListener(names, function(once, ...)
        self:removeEventListener(names, once)
        return fn(fn, ...)
    end)
end

function bus:addTriggerListenerOnce(names, fn)
    return self:addTriggerListener(names, function(once, ...)
        self:removeTriggerListener(names, once)
        return fn(fn, ...)
    end)
end

bus.attachEvent, bus.attachEventOnce = bus.addEventListener, bus.addEventListenerOnce
bus.detachEvent = bus.removeEventListener
bus.attachTrigger, bus.attachTriggerOnce = bus.addTriggerListener, bus.addTriggerListenerOnce
bus.detachTrigger, bus.detachAllTriggers = bus.removeTriggerListener, bus.removeAllTriggers
frame:SetScript("OnEvent", function(_, name, ...) bus:event(name, ...) end)

function MM:AttachEvent(name, events, fn, hook)
    assert(self.modules[name], "unknown module")
    assert(self:IsEnabled(name), "disabled module")
    Attach(bus.events, events, fn, name, hook)
end

function MM:AttachTrigger(name, events, fn, hook)
    assert(self.modules[name], "unknown module")
    assert(self:IsEnabled(name), "disabled module")
    Attach(bus.triggers, events, fn, name, hook)
end

function MM:HasTriggerSubscribers(name)
    local list = bus.triggers[name]
    if not list then return false end
    for _, entry in ipairs(list) do
        if entry.active and not entry.pending
            and (not entry.owner or self:IsEnabled(entry.owner)) then return true end
    end
    return false
end

function MM:Detach(name)
    for _, entry in ipairs(self._links[name] or {}) do
        Remove(entry)
        self.meta[entry] = nil
    end
    self._links[name] = {}
end

local function Lifecycle(name, method)
    local module = MM.modules[name]
    local fn = module[method]
    if type(fn) ~= "function" then return true end
    MM:Track(name, fn, method)
    local ok, result = pcall(fn, module, addon)
    if not ok then Report("lifecycle", name .. ":" .. method, result, fn); return false end
    if not addon:CanAccessValue(result) or result == false then
        Report("lifecycle", name .. ":" .. method, "lifecycle rejected", fn)
        return false
    end
    return true
end

function MM:Enable(name)
    if not self.modules[name] or (not self.core[name] and not variablesLoaded) then return false end
    local state = State(name)
    if state.changing then return false end
    if state.enabled then SaveEnabled(name, true); return true end
    state.changing, state.enabled = true, true
    if not state.initialized then state.initialized = Lifecycle(name, "Init") end
    local enabled = state.initialized and Lifecycle(name, "Enable")
    if not enabled then
        state.enabled = false
        self:Detach(name)
        Lifecycle(name, "Disable")
        self:Detach(name)
    end
    state.enabled, state.changing = enabled, false
    SaveEnabled(name, enabled)
    return enabled
end

function MM:Disable(name)
    if not self.modules[name] or self.core[name] then return false end
    local state = State(name)
    if state.changing then return false end
    local wasEnabled = state.enabled
    state.enabled, state.changing = false, true
    self:Detach(name)
    local ok = not wasEnabled or Lifecycle(name, "Disable")
    -- A faulty Disable must not leave subscriptions created during teardown.
    self:Detach(name)
    state.changing = false
    SaveEnabled(name, false)
    return ok
end

function MM:Toggle(name)
    if self:IsEnabled(name) then return self:Disable(name) end
    return self:Enable(name)
end

function MM:RegisterModule(name, module)
    assert(type(name) == "string" and name ~= "" and type(module) == "table", "invalid module")
    if self.modules[name] == module then return end
    assert(self.modules[name] == nil, "duplicate module: " .. name)
    self.modules[name], self._links[name] = module, {}
    self.order[#self.order + 1] = name
    State(name)
    if self.core[name] or (variablesLoaded and addon.db.modules[name] ~= false) then self:Enable(name) end
end

function MM:ApplySaved()
    if applyingSaved or type(addon.db) ~= "table" then return end
    applyingSaved, variablesLoaded = true, true
    addon.db.modules = type(addon.db.modules) == "table" and addon.db.modules or {}
    for _, name in ipairs(self.order) do
        if self.core[name] or addon.db.modules[name] ~= false then self:Enable(name)
        else self:Disable(name) end
    end
    applyingSaved = false
end

function MM:ExportText()
    local names, out = {}, { "RothTooltip Modules", "Name\tEnabled\tCalls\tErrs\tLast(ms)\tLastHook\tLastErr" }
    for name in pairs(self.modules) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local state = self.state[name]
        out[#out + 1] = string.format("%s\t%d\t%d\t%d\t%.1f\t%s\t%s", name,
            state.enabled and 1 or 0, state.calls, state.errs, state.lastMs,
            state.lastHook or "", state.lastErr or "")
    end
    return table.concat(out, "\n")
end

local function FinishModuleChange(name, wasEnabled, origin)
    local isEnabled = MM:IsEnabled(name)
    if wasEnabled == isEnabled then return end

    if type(addon.RefreshManagedTooltipsMatching) == "function" then
        addon:RefreshManagedTooltipsMatching(nil, "module:" .. tostring(name))
    end
    if origin ~= "settings" then
        local options = addon.Options
        if type(options) == "table" and type(options.NotifySetting) == "function" then
            options:NotifySetting("modules." .. tostring(name))
        end
    end
end

function addon:SetModuleEnabled(name, enabled, origin)
    local wasEnabled = MM:IsEnabled(name)
    local ok
    if enabled == true then ok = MM:Enable(name)
    else ok = MM:Disable(name) end
    FinishModuleChange(name, wasEnabled, origin)
    return ok
end

function addon:EnableModule(name, origin)
    return self:SetModuleEnabled(name, true, origin)
end

function addon:DisableModule(name, origin)
    return self:SetModuleEnabled(name, false, origin)
end

function addon:ToggleModule(name, origin)
    return self:SetModuleEnabled(name, not MM:IsEnabled(name), origin)
end

bus:attachTrigger("tooltip:variables:loaded", function() MM:ApplySaved() end)
