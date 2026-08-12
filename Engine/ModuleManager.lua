-- RothTooltip Engine: Module Manager
--
-- LibEvent is the dispatcher; ModuleManager adds:
--   * callback tagging by module for diagnostics
--   * per-module stats + enable/disable via /rtt and Options
--   * registered modules (formal contract) with detach-on-disable
--
-- IMPORTANT: LibEvent invokes callbacks as:
--   pcall(func, func, ...)
-- The first callback argument is therefore the callback function itself.
-- Do NOT rely on it being a module table.

local _, addon = ...

---------------------------------
-- LibEvent (minimal event/trigger bus)
-- Patched for Midnight:
--   - pcall wrapper for every callback (one module cannot kill the addon)
--   - temporary mute for noisy callbacks (no permanent detach)
--   - optional error sink for diagnostics
---------------------------------

LibStub = LibStub or {
    GetLibrary = function(self, name) return self[name] end,
    NewLibrary = function(self, name) self[name] = self[name] or {}; return self[name] end,
}
local MAJOR, MINOR = "LibEvent.7000", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.events = lib.events or {}
lib.triggers = lib.triggers or {}

lib._muteUntil = lib._muteUntil or {}
lib._errState  = lib._errState  or {}
lib._errorSink = lib._errorSink or nil

function lib:SetErrorSink(fn)
    self._errorSink = fn
    return self
end

local frame = lib._frame
if not frame then
    frame = CreateFrame("Frame", nil, UIParent)
    lib._frame = frame
end

local function CallSafe(kind, event, func, ...)
    if not func then return end

    local now = GetTime and GetTime() or 0
    local untilTime = lib._muteUntil[func]
    if untilTime and untilTime > now then
        return
    end

    local ok, err = pcall(func, func, ...)
    if ok then return end

    local st = lib._errState[func]
    if (not st) or (now - st.t0 > 10) then
        st = { t0 = now, n = 0 }
        lib._errState[func] = st
    end
    st.n = st.n + 1
    if st.n >= 3 then
        lib._muteUntil[func] = now + 60
    end

    if lib._errorSink then
        pcall(lib._errorSink, kind, event, tostring(err), func)
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    local t = lib.events[event]
    if not t then return end
    for _, fn in pairs(t) do
        CallSafe("bliz", event, fn, ...)
    end
end)

-- Simulate triggering a Blizzard event
function lib:event(event, ...)
    local t = lib.events[event]
    if not t then return end
    for _, fn in pairs(t) do
        CallSafe("bliz", event, fn, ...)
    end
end

-- Add Blizzard event callback
function lib:addEventListener(event, func)
    for e in string.gmatch(event, "([^,%s]+)") do
        if not self.events[e] then
            self.events[e] = {}
            frame:RegisterEvent(e)
        end
        table.insert(self.events[e], func)
    end
    return self
end

-- Remove Blizzard event callback
function lib:removeEventListener(event, func)
    if (type(event) == "function") then
        for _, funcs in pairs(self.events) do
            for k, v in pairs(funcs) do
                if (v == event) then funcs[k] = nil end
            end
        end
    elseif self.events[event] then
        for k, v in pairs(self.events[event]) do
            if (v == func) then self.events[event][k] = nil end
        end
    end
    return self
end

-- One-shot Blizzard event callback
function lib:addEventListenerOnce(event, func)
    return self:addEventListener(event, function(this, ...)
        func(this, ...)
        lib:removeEventListener(event, this)
    end)
end

-- Add trigger callback (custom events)
function lib:addTriggerListener(event, func)
    for e in string.gmatch(event, "([^,%s]+)") do
        if not self.triggers[e] then self.triggers[e] = {} end
        table.insert(self.triggers[e], func)
    end
    return self
end

-- Remove trigger callback
function lib:removeTriggerListener(event, func)
    if (type(event) == "function") then
        for _, funcs in pairs(self.triggers) do
            for k, v in pairs(funcs) do
                if (v == event) then funcs[k] = nil end
            end
        end
    elseif self.triggers[event] then
        for k, v in pairs(self.triggers[event]) do
            if (v == func) then self.triggers[event][k] = nil end
        end
    end
    return self
end

function lib:removeAllTriggers(event)
    self.triggers[event] = nil
    return self
end

function lib:addTriggerListenerOnce(event, func)
    return self:addTriggerListener(event, function(this, ...)
        func(this, ...)
        lib:removeTriggerListener(event, this)
    end)
end

-- Fire a trigger
function lib:trigger(event, ...)
    local t = self.triggers[event]
    if not t then return end
    for _, fn in pairs(t) do
        CallSafe("trigger", event, fn, ...)
    end
end

-- Aliases (legacy API)
lib.attachEvent        = lib.addEventListener
lib.attachEventOnce    = lib.addEventListenerOnce
lib.detachEvent        = lib.removeEventListener
lib.attachTrigger      = lib.addTriggerListener
lib.attachTriggerOnce  = lib.addTriggerListenerOnce
lib.detachTrigger      = lib.removeTriggerListener
lib.detachAllTriggers  = lib.removeAllTriggers

local LibEvent = lib
addon.LibEvent = LibEvent

addon.MM = addon.MM or {}
local MM = addon.MM

-- meta[func] = { module="Unit", hook="tooltip:unit" }
MM.meta    = MM.meta    or {}
-- state[module] = { enabled=true, calls=0, errs=0, lastErr=nil, lastHook=nil, lastAt=0, lastMs=0 }
MM.state   = MM.state   or {}
-- registered modules: modules[name] = moduleObject
MM.modules = MM.modules or {}
-- detachable links for registered modules: _links[name] = { {kind="trigger"|"event", event="...", func=function} }
MM._links  = MM._links  or {}

-- Central trigger dispatch tables:
--   _tSubs[event] = { { module="Unit", func=function, hook="tooltip:unit" }, ... }
--   _tDisp[event] = dispatcherFunction (attached once to LibEvent)
MM._tSubs  = MM._tSubs  or {}
MM._tDisp  = MM._tDisp  or {}

-- Keep pending trigger subscriptions until the first time a trigger fires.
MM._tPend   = MM._tPend   or {}
MM._tPrimed = MM._tPrimed or {}


-- Core modules must never be disabled at load because they initialize SavedVariables.
MM.core = MM.core or { General = true }
MM.__applyingSaved = MM.__applyingSaved or false

local function Now()
    return (GetTime and GetTime()) or 0
end

local function SplitEvents(eventString)
    local out = {}
    for e in string.gmatch(eventString or "", "([^,%s]+)") do
        out[#out+1] = e
    end
    return out
end

local function EnsureState(module)
    local s = MM.state[module]
    if (not s) then
        s = { enabled = true, calls = 0, errs = 0, lastErr = nil, lastHook = nil, lastAt = 0, lastMs = 0 }
        MM.state[module] = s
    end
    return s
end

local function EnsureModulesDB()
    if (not addon or not addon.db) then return nil end
    if (type(addon.db.modules) ~= "table") then
        addon.db.modules = {}
    end
    return addon.db.modules
end

-- ------------------------------------------------------------
-- Public API (used by modules + Options + /rtt)
-- ------------------------------------------------------------

function MM:Track(module, func, hook)
    if (type(func) ~= "function") then return end
    self.meta[func] = { module = tostring(module or "?"), hook = tostring(hook or "?") }
end

-- Called by Doctor's LibEvent error sink to attribute errors to a module.
function MM:OnError(func, err)
    local m = self.meta[func]
    if (not m) then return nil end
    local s = EnsureState(m.module)
    s.errs = (s.errs or 0) + 1
    s.lastErr = tostring(err or "?")
    s.lastHook = m.hook or s.lastHook
    s.lastAt = Now()
    return m.module, m.hook
end

function MM:IsEnabled(module)
    module = tostring(module or "?")
    if (self.core and self.core[module]) then
        return true
    end
    local s = EnsureState(module)
    return (s.enabled ~= false)
end

function MM:OnCallStart(module, hook)
    module = tostring(module or "?")
    if (not self:IsEnabled(module)) then
        return nil
    end
    local s = EnsureState(module)
    s.calls = (s.calls or 0) + 1
    s.lastHook = hook or s.lastHook
    s.lastAt = Now()
    return s.lastAt
end

function MM:OnCallEnd(module, startedAt)
    module = tostring(module or "?")
    if (not self:IsEnabled(module)) then
        return
    end
    if (type(startedAt) ~= "number") then return end
    local s = EnsureState(module)
    local dt = Now() - startedAt
    if (dt < 0) then dt = 0 end
    s.lastMs = dt * 1000
end

function MM:HasTriggerSubscribers(ev)
    if (type(ev) ~= "string" or ev == "") then return false end
    local subs = self._tSubs and self._tSubs[ev]
    if (subs and #subs > 0) then return true end
    local pend = self._tPend and self._tPend[ev]
    if (pend and #pend > 0) then return true end
    return false
end


function MM:Detach(module)
    module = tostring(module or "?")
    local links = self._links[module]
    if (not links) then return end
    if (LibEvent) then
        for _, l in ipairs(links) do
            if (l.kind == "subTrigger") then
                local ev = l.event
                local function RemoveFrom(list)
                    if (not list) then return 0 end
                    for i = #list, 1, -1 do
                        local s = list[i]
                        if (s and s.module == module and s.func == l.func) then
                            table.remove(list, i)
                        end
                    end
                    return #list
                end

                local subs = self._tSubs and self._tSubs[ev]
                local pend = self._tPend and self._tPend[ev]

                local nSubs = RemoveFrom(subs)
                local nPend = RemoveFrom(pend)

                if ((not subs or nSubs == 0) and (not pend or nPend == 0) and self._tDisp and self._tDisp[ev]) then
                    LibEvent:removeTriggerListener(ev, self._tDisp[ev])
                    self._tDisp[ev] = nil
                    if (self._tSubs) then self._tSubs[ev] = nil end
                    if (self._tPend) then self._tPend[ev] = nil end
                    if (self._tPrimed) then self._tPrimed[ev] = nil end
                end
            elseif (l.kind == "trigger") then
                LibEvent:removeTriggerListener(l.event, l.func)
            elseif (l.kind == "event") then
                LibEvent:removeEventListener(l.event, l.func)
            end
        end
    end
    self._links[module] = {}
end

function MM:AttachTrigger(module, event, func, hook)
    if (not LibEvent) then return end
    if (type(func) ~= "function") then return end

    module = tostring(module or "?")
    hook = hook or event

    -- Track for Doctor attribution.
    self:Track(module, func, hook)

    self._links[module] = self._links[module] or {}
    self._tSubs = self._tSubs or {}
    self._tDisp = self._tDisp or {}
    self._tPend = self._tPend or {}
    self._tPrimed = self._tPrimed or {}

    for _, e in ipairs(SplitEvents(event)) do
        -- IMPORTANT: loop variable must be copied for closure safety (Lua 5.1 / WoW).
        local ev = e

        -- Record link for detach-on-disable.
        table.insert(self._links[module], { kind = "subTrigger", event = ev, func = func })

        -- If the trigger hasn't fired yet, keep subs pending and
        -- materialize them on the first dispatch. If it has fired, register immediately.
        if (self._tPrimed[ev]) then
            self._tSubs[ev] = self._tSubs[ev] or {}
            table.insert(self._tSubs[ev], { module = module, func = func, hook = hook })
        else
            self._tPend[ev] = self._tPend[ev] or {}
            table.insert(self._tPend[ev], { module = module, func = func, hook = hook })
        end

        -- Attach central dispatcher once.
        if (not self._tDisp[ev]) then
            local function Dispatch(_, ...)
                -- First time this trigger fires: promote pending subs.
                if (not (MM._tPrimed and MM._tPrimed[ev])) then
                    local pend = MM._tPend and MM._tPend[ev]
                    if (pend and #pend > 0) then
                        MM._tSubs = MM._tSubs or {}
                        MM._tSubs[ev] = MM._tSubs[ev] or {}
                        for i = 1, #pend do
                            MM._tSubs[ev][#MM._tSubs[ev] + 1] = pend[i]
                        end
                        MM._tPend[ev] = nil
                    end
                    MM._tPrimed = MM._tPrimed or {}
                    MM._tPrimed[ev] = true
                end

                local subs = MM._tSubs and MM._tSubs[ev]
                if (not subs) then return end
                for i = 1, #subs do
                    local s = subs[i]
                    if (s and MM:IsEnabled(s.module)) then
                        local started = MM:OnCallStart(s.module, s.hook)
                        local ok, err = pcall(s.func, s.func, ...)
                        if (not ok) then
                            MM:OnError(s.func, err)
                            if (addon and addon.DoctorLog) then
                                addon:DoctorLog("lua", string.format("%s:%s", s.module or "?", s.hook or ev), err, nil)
                            end
                        end
                        MM:OnCallEnd(s.module, started)
                    end
                end
            end
            self._tDisp[ev] = Dispatch
            LibEvent:attachTrigger(ev, Dispatch)
        end
    end
end

function MM:AttachEvent(module, event, func, hook)
    if (not LibEvent) then return end
    if (type(func) ~= "function") then return end

    module = tostring(module or "?")
    hook = hook or event

    self:Track(module, func, hook)

    self._links[module] = self._links[module] or {}
    for _, e in ipairs(SplitEvents(event)) do
        LibEvent:attachEvent(e, func)
        table.insert(self._links[module], { kind = "event", event = e, func = func })
    end
end

function MM:RegisterModule(name, moduleObject)
    if (type(name) ~= "string" or name == "") then return end
    if (type(moduleObject) ~= "table") then return end

    self.modules[name] = moduleObject
    EnsureState(name)
    self._links[name] = self._links[name] or {}

    -- Init once.
    if (not moduleObject.__rt_inited and type(moduleObject.Init) == "function") then
        moduleObject.__rt_inited = true
        if (addon.SafeCall) then
            addon:SafeCall(name..":Init", moduleObject.Init, moduleObject, addon)
        else
            pcall(moduleObject.Init, moduleObject, addon)
        end
    end

    -- Core modules must be enabled immediately (they initialize SavedVariables/engine state).
    if (self.core and self.core[name]) then
        self:Enable(name, true)
        local dbMods = EnsureModulesDB()
        if (dbMods) then dbMods[name] = true end
        return
    end

    -- If variables are already loaded, honor saved module state immediately.
    local dbMods = EnsureModulesDB()
    if (dbMods) then
        local want = dbMods[name]
        if (want == false) then
            self:Disable(name, true)
        else
            self:Enable(name, true)
        end
    end
end

function MM:Enable(name, silent)
    name = tostring(name or "")
    if (name == "") then return end

    local s = EnsureState(name)
    if (self.core and self.core[name]) then
        s.enabled = true
    end
    if (s.enabled ~= false and s.__enabledOnce) then
        return
    end

    s.enabled = true
    s.__enabledOnce = true

    local dbMods = EnsureModulesDB()
    if (dbMods) then
        dbMods[name] = true
    end

    local m = self.modules[name]
    if (m and type(m.Enable) == "function") then
        if (addon.SafeCall) then
            addon:SafeCall(name..":Enable", m.Enable, m)
        else
            pcall(m.Enable, m)
        end
    end

    if (not silent) then
        -- noop (Debug prints are handled by slash handler)
    end
end

function MM:Disable(name, silent)
    name = tostring(name or "")
    if (name == "") then return end

    if (self.core and self.core[name]) then
        -- Forced on.
        local s = EnsureState(name)
        s.enabled = true
        return
    end

    local s = EnsureState(name)
    if (s.enabled == false) then
        return
    end
    s.enabled = false

    local dbMods = EnsureModulesDB()
    if (dbMods) then
        dbMods[name] = false
    end

    -- Detach hooks registered through MM.
    self:Detach(name)

    local m = self.modules[name]
    if (m and type(m.Disable) == "function") then
        if (addon.SafeCall) then
            addon:SafeCall(name..":Disable", m.Disable, m)
        else
            pcall(m.Disable, m)
        end
    end

    if (not silent) then
        -- noop
    end
end

function MM:Toggle(name)
    name = tostring(name or "")
    if (name == "") then return end
    if (self:IsEnabled(name)) then
        self:Disable(name)
    else
        self:Enable(name)
    end
end

function MM:ApplySaved()
    if (self.__applyingSaved) then return end
    self.__applyingSaved = true

    local dbMods = EnsureModulesDB()
    if (dbMods) then
        -- Ensure core modules are always on in the DB.
        if (self.core) then
            for coreName, v in pairs(self.core) do
                if (v) then dbMods[coreName] = true end
            end
        end

        for name, _ in pairs(self.modules) do
            local want = dbMods[name]
            if (want == false and not (self.core and self.core[name])) then
                self:Disable(name, true)
            else
                self:Enable(name, true)
            end
        end
    end

    self.__applyingSaved = false
end

function MM:ExportText()
    local names = {}
    for n, _ in pairs(self.state) do
        if (type(n) == "string") then names[#names+1] = n end
    end
    table.sort(names)

    local out = {}
    out[#out+1] = "RothTooltip Modules"
    out[#out+1] = "Name\tEnabled\tCalls\tErrs\tLast(ms)\tLastHook\tLastErr"

    for _, n in ipairs(names) do
        local s = EnsureState(n)
        local enabled = (self.core and self.core[n]) and true or (s.enabled ~= false)
        out[#out+1] = string.format(
            "%s\t%s\t%d\t%d\t%.1f\t%s\t%s",
            n,
            enabled and "1" or "0",
            s.calls or 0,
            s.errs or 0,
            s.lastMs or 0,
            tostring(s.lastHook or ""),
            tostring(s.lastErr or "")
        )
    end

    return table.concat(out, "\n")
end

-- ------------------------------------------------------------
-- addon helpers used by Options + Debug
-- ------------------------------------------------------------

function addon:EnableModule(name)
    if (self.MM and self.MM.Enable) then
        self.MM:Enable(name)
    end
end

function addon:DisableModule(name)
    if (self.MM and self.MM.Disable) then
        self.MM:Disable(name)
    end
end

function addon:ToggleModule(name)
    if (self.MM and self.MM.Toggle) then
        self.MM:Toggle(name)
    end
end

-- Apply module enable/disable state when SavedVariables are ready.
if (LibEvent and LibEvent.attachTrigger) then
    LibEvent:attachTrigger("tooltip:variables:loaded", function()
        if (addon and addon.MM and addon.MM.ApplySaved) then
            addon.MM:ApplySaved()
        end
    end)
end
