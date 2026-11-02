-- RothTooltip Engine: capability and object-access helpers for Retail 12.1.
--
-- Inaccessible values are rejected at the integration boundary. Protected
-- calls contain ordinary Lua errors only; they are never used to discover,
-- retry, or declassify secret values.

local _, addon = ...
RothTooltip = addon

addon.Safe = addon.Safe or {}

local CanAccessValueAPI = type(canaccessvalue) == "function" and canaccessvalue or nil
local CanAccessAllValuesAPI = type(canaccessallvalues) == "function" and canaccessallvalues or nil
local IsSecretValueAPI = type(issecretvalue) == "function" and issecretvalue or nil

local function CanAccessValue(value)
    if CanAccessValueAPI then
        return CanAccessValueAPI(value) == true
    end
    if IsSecretValueAPI then
        return IsSecretValueAPI(value) ~= true
    end
    return true
end

local function CanAccessAllValues(...)
    if CanAccessAllValuesAPI then
        return CanAccessAllValuesAPI(...) == true
    end

    for index = 1, select("#", ...) do
        if not CanAccessValue(select(index, ...)) then
            return false
        end
    end
    return true
end

function addon:CanAccessValue(value)
    return CanAccessValue(value)
end

function addon:CanAccessAllValues(...)
    return CanAccessAllValues(...)
end

function addon:IsSecret(value)
    return not CanAccessValue(value)
end

function addon:SafeBoolean(value)
    if not CanAccessValue(value) or value == nil then return nil end
    if type(value) == "boolean" then return value end
    return value and true or false
end

function addon:SafeToString(value, placeholder)
    if not CanAccessValue(value) then return placeholder or "??" end
    if value == nil then return placeholder end
    if type(value) == "string" then return value end

    local ok, text = pcall(tostring, value)
    if ok and CanAccessValue(text) and type(text) == "string" then
        return text
    end
    return placeholder or "??"
end

-- SafeCall accepts only accessible inputs and independently gates each return
-- value before it crosses back into addon code.
function addon:SafeCall(tag, fn, ...)
    if not CanAccessValue(fn) or type(fn) ~= "function" then return nil end
    if not CanAccessAllValues(...) then return nil end

    local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(fn, ...)
    if ok then
        if not CanAccessValue(r1) then r1 = nil end
        if not CanAccessValue(r2) then r2 = nil end
        if not CanAccessValue(r3) then r3 = nil end
        if not CanAccessValue(r4) then r4 = nil end
        if not CanAccessValue(r5) then r5 = nil end
        if not CanAccessValue(r6) then r6 = nil end
        if not CanAccessValue(r7) then r7 = nil end
        if not CanAccessValue(r8) then r8 = nil end
        return r1, r2, r3, r4, r5, r6, r7, r8
    end

    if type(self.DoctorLog) == "function" then
        local stack = type(debugstack) == "function" and debugstack(2, 20, 20) or nil
        pcall(self.DoctorLog, self, "lua", tag or "SafeCall", r1, stack)
    end
    return nil
end

function addon:SafeCallBoolean(fn, ...)
    if not CanAccessValue(fn) or type(fn) ~= "function" then return nil end
    if not CanAccessAllValues(...) then return nil end

    local ok, value = pcall(fn, ...)
    if not ok or not CanAccessValue(value) then return nil end
    return self:SafeBoolean(value)
end

function addon:SafeGet(object, key)
    if not CanAccessValue(object) or object == nil then return nil end
    if not CanAccessValue(key) or key == nil then return nil end

    local ok, value = pcall(function()
        return object[key]
    end)
    if not ok or not CanAccessValue(value) then return nil end
    return value
end

function addon:IsObjectAccessible(object)
    if not CanAccessValue(object) or object == nil then return false end

    local canAccess = self:SafeGet(object, "CanBeAccessedInContext")
    if type(canAccess) == "function" then
        local ok, result = pcall(canAccess, object)
        if not ok or not CanAccessValue(result) or result ~= true then
            return false
        end
    end

    local isForbidden = self:SafeGet(object, "IsForbidden")
    if type(isForbidden) == "function" then
        local ok, result = pcall(isForbidden, object)
        if not ok or not CanAccessValue(result) or result == true then
            return false
        end
    end

    return true
end

function addon:HasForbiddenAspects(object, aspects)
    if not self:IsObjectAccessible(object) then return true end
    if aspects ~= nil and not CanAccessValue(aspects) then return true end

    local fn = self:SafeGet(object, "HasAnyForbiddenAspects")
    if type(fn) ~= "function" then return false end

    local ok, result = pcall(fn, object, aspects)
    if not ok or not CanAccessValue(result) then return true end
    return result == true
end

function addon:CanBindScripts(object)
    if not self:IsObjectAccessible(object) then return false end
    local forbiddenAspect = Enum and Enum.ForbiddenAspect
    local scriptBindings = forbiddenAspect and forbiddenAspect.ScriptBindings or nil
    if type(scriptBindings) ~= "number" then return true end
    return not self:HasForbiddenAspects(object, scriptBindings)
end

function addon:SafeMethod(object, method, ...)
    if not self:IsObjectAccessible(object) then return nil end
    if not CanAccessValue(method) or type(method) ~= "string" then return nil end

    local fn = self:SafeGet(object, method)
    if type(fn) ~= "function" then return nil end
    return self:SafeCall(method, fn, object, ...)
end
