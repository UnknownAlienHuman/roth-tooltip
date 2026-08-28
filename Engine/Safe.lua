-- RothTooltip Engine: Safe helpers
-- Retail 12.1: inaccessible values are capability-gated, not probed through
-- comparisons or protected retry loops.

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

function addon:CanAccessValue(value)
    return CanAccessValue(value)
end

function addon:CanAccessAllValues(...)
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

function addon:IsSecret(value)
    return not CanAccessValue(value)
end

-- SafeCall(tag, fn, ...):
-- - calls only with ordinary, currently accessible arguments;
-- - returns fn(...) on success;
-- - on an ordinary Lua error, forwards to Doctor and returns nil.
--
-- pcall is error containment only. It is never used to discover or unwrap a
-- value that failed the access gate.
function addon:SafeCall(tag, fn, ...)
    if not CanAccessValue(fn) or type(fn) ~= "function" then
        return nil
    end
    if not self:CanAccessAllValues(...) then
        return nil
    end

    local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(fn, ...)
    if ok then
        return r1, r2, r3, r4, r5, r6, r7, r8
    end

    if type(self.DoctorLog) == "function" then
        pcall(self.DoctorLog, self, "lua", tag or "SafeCall", r1, debugstack(2, 20, 20))
    end
    return nil
end

-- SafeGet(obj, key): returns only an accessible value.
function addon:SafeGet(obj, key)
    if not CanAccessValue(obj) or obj == nil then return nil end
    if not CanAccessValue(key) or key == nil then return nil end

    local ok, value = pcall(function()
        return obj[key]
    end)
    if not ok or not CanAccessValue(value) then
        return nil
    end
    return value
end

-- SafeMethod(obj, method, ...): access-gated pcall wrapper around
-- obj[method](obj, ...).
function addon:SafeMethod(obj, method, ...)
    if not CanAccessValue(obj) or obj == nil then return nil end
    if self.IsObjectAccessible and not self:IsObjectAccessible(obj) then return nil end

    local fn = self:SafeGet(obj, method)
    if type(fn) ~= "function" then return nil end
    return self:SafeCall(method, fn, obj, ...)
end
