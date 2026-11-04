local _, addon = ...

local accessValue = canaccessvalue
local accessAll = canaccessallvalues
local accessTable = canaccesstable
local isSecret = issecretvalue
local unpack = unpack or table.unpack

function addon:CanAccessValue(value)
    if type(accessValue) == "function" then return accessValue(value) == true end
    if type(isSecret) == "function" then return isSecret(value) ~= true end
    return false
end

function addon:CanAccessAllValues(...)
    if type(accessAll) == "function" then return accessAll(...) == true end
    for index = 1, select("#", ...) do
        if not self:CanAccessValue(select(index, ...)) then return false end
    end
    return true
end

function addon:CanAccessTable(value)
    return self:CanAccessValue(value) and type(value) == "table"
        and type(accessTable) == "function" and accessTable(value) == true
end

function addon:SafeBoolean(value)
    if not self:CanAccessValue(value) or value == nil then return nil end
    return not not value
end

function addon:SafeToString(value, fallback)
    if not self:CanAccessValue(value) then return fallback or "??" end
    if value == nil then return fallback end
    if type(value) == "string" then return value end
    local ok, text = pcall(tostring, value)
    if ok and self:CanAccessValue(text) and type(text) == "string" then return text end
    return fallback or "??"
end

local function Results(tag, ok, ...)
    if not ok then
        if addon.DoctorLog then
            pcall(addon.DoctorLog, addon, "lua", tag, select(1, ...))
        end
        return nil
    end
    -- The ordinary hot path needs no result table. Keep nil slots and arity.
    if addon:CanAccessAllValues(...) then return ... end
    local values, count = {}, select("#", ...)
    for index = 1, count do
        local value = select(index, ...)
        if addon:CanAccessValue(value) then values[index] = value end
    end
    return unpack(values, 1, count)
end

function addon:SafeCall(tag, fn, ...)
    if not self:CanAccessValue(fn) or type(fn) ~= "function" then return nil end
    if not self:CanAccessAllValues(...) then return nil end
    return Results(tag, pcall(fn, ...))
end

function addon:SafeCallBoolean(fn, ...)
    return self:SafeBoolean(self:SafeCall("boolean", fn, ...))
end

local function ReadMember(object, key)
    return object[key]
end

function addon:SafeGet(object, key)
    if not self:CanAccessAllValues(object, key) or object == nil or key == nil then return nil end
    if type(object) == "table" and not self:CanAccessTable(object) then return nil end
    local ok, value = pcall(ReadMember, object, key)
    if ok and self:CanAccessValue(value) then return value end
end

function addon:IsObjectAccessible(object)
    if not self:CanAccessValue(object) then return false end
    local kind = type(object)
    if kind ~= "table" and kind ~= "userdata" then return false end
    if kind == "table" and not self:CanAccessTable(object) then return false end

    local fn = self:SafeGet(object, "CanBeAccessedInContext")
    if type(fn) == "function" then
        local ok, allowed = pcall(fn, object)
        if not ok or not self:CanAccessValue(allowed) or allowed ~= true then return false end
    end
    fn = self:SafeGet(object, "IsForbidden")
    if type(fn) == "function" then
        local ok, forbidden = pcall(fn, object)
        if not ok or not self:CanAccessValue(forbidden) or forbidden ~= false then return false end
    end
    return true
end

function addon:HasForbiddenAspects(object, aspects)
    if not self:CanAccessValue(aspects) or not self:IsObjectAccessible(object) then return true end
    local fn = self:SafeGet(object, "HasAnyForbiddenAspects")
    if type(fn) ~= "function" then return true end
    local ok, forbidden = pcall(fn, object, aspects)
    return not ok or not self:CanAccessValue(forbidden) or forbidden ~= false
end

function addon:CanBindScripts(object)
    local aspect = Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ScriptBindings
    return type(aspect) == "number" and not self:HasForbiddenAspects(object, aspect)
end

function addon:SafeMethod(object, method, ...)
    if not self:CanAccessValue(object) or object == nil then return nil end
    if not self:IsObjectAccessible(object) then return nil end
    return self:SafeCall(method, self:SafeGet(object, method), object, ...)
end
