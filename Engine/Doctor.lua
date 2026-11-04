local addonName, addon = ...
local errors = {}
local MAX_ERRORS = 80
local LIMITS = { kind = 64, where = 256, message = 1024, extra = 1024 }

local function BoundedText(value, fallback, limit)
    local text = addon:SafeToString(value, fallback)
    if type(text) ~= "string" then return fallback end
    if #text > limit then return text:sub(1, limit - 3) .. "..." end
    return text
end

function addon:DoctorLog(kind, where, err, extra)
    errors[#errors + 1] = {
        time = GetTime(),
        kind = BoundedText(kind, "lua", LIMITS.kind),
        where = BoundedText(where, "?", LIMITS.where),
        message = BoundedText(err, "<inaccessible error>", LIMITS.message),
        extra = BoundedText(extra, nil, LIMITS.extra),
    }
    if #errors > MAX_ERRORS then table.remove(errors, 1) end
end

function addon:DoctorClear()
    for index = #errors, 1, -1 do errors[index] = nil end
end

function addon:DoctorExportText()
    local lines = { "RothTooltip Doctor Report", "Time\tKind\tWhere\tError" }
    for _, entry in ipairs(errors) do
        lines[#lines + 1] = string.format("%.3f\t%s\t%s\t%s",
            entry.time, entry.kind, entry.where, entry.message)
        if entry.extra then lines[#lines + 1] = entry.extra end
    end
    return table.concat(lines, "\n")
end

addon.LibEvent:SetErrorSink(function(kind, event, err, fn)
    local owner, hook = addon.MM:OnError(fn, err)
    local where = owner and (owner .. ":" .. (hook or event)) or event
    addon:DoctorLog(kind, where, err)
end)

local function AttachTaintEvent(event)
    addon.LibEvent:attachEvent(event, function(_, source, operation)
        if addon:CanAccessValue(source) and source == addonName then
            addon:DoctorLog("taint", event, operation)
        end
    end)
end

AttachTaintEvent("ADDON_ACTION_BLOCKED")
AttachTaintEvent("ADDON_ACTION_FORBIDDEN")
