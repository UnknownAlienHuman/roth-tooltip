-- RothTooltip Engine: Safe helpers
-- Goal: isolate failures inside optional blocks.

local addonName, addon = ...
RothTooltip = addon

addon.Safe = addon.Safe or {}

-- SafeCall(tag, fn, ...):
-- - returns fn(...) on success
-- - on error: forwards to addon:DoctorLog(...) when available and returns nil
function addon:SafeCall(tag, fn, ...)
    if (type(fn) ~= "function") then
        return nil
    end

    local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(fn, ...)
    if (ok) then
        return r1, r2, r3, r4, r5, r6, r7, r8
    end

    -- r1 is the error message
    if (type(self.DoctorLog) == "function") then
        pcall(self.DoctorLog, self, "lua", tag or "SafeCall", r1, debugstack(2, 20, 20))
    end
    return nil
end

-- SafeGet(obj, key): never errors
function addon:SafeGet(obj, key)
    if (obj == nil) then return nil end
    local ok, v = pcall(function() return obj[key] end)
    if ok then return v end
    return nil
end

-- SafeMethod(obj, method, ...): pcall wrapper around obj[method](obj,...)
function addon:SafeMethod(obj, method, ...)
    if (obj == nil) then return nil end
    local fn = obj[method]
    if (type(fn) ~= "function") then return nil end
    return self:SafeCall(method, fn, obj, ...)
end
