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
        if not CanAccessValue(select(index, ...)) then return false end
    end
    return true
end

function addon:IsSecret(value)
    return not CanAccessValue(value)
end

-- SafeCall is error containment for already-accessible inputs. Its outputs are
-- independently gated before they cross back into addon code.
function addon:SafeCall(tag, fn, ...)
    if not CanAccessValue(fn) or type(fn) ~= "function" then return nil end
    if not self:CanAccessAllValues(...) then return nil end

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

function addon:SafeGet(object, key)
    if not CanAccessValue(object) or object == nil then return nil end
    if not CanAccessValue(key) or key == nil then return nil end

    local ok, value = pcall(function() return object[key] end)
    if not ok or not CanAccessValue(value) then return nil end
    return value
end

function addon:SafeMethod(object, method, ...)
    if not CanAccessValue(object) or object == nil then return nil end
    if self.IsObjectAccessible and not self:IsObjectAccessible(object) then return nil end

    local fn = self:SafeGet(object, method)
    if type(fn) ~= "function" then return nil end
    return self:SafeCall(method, fn, object, ...)
end
