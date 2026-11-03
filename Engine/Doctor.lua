local addonName, addon = ...
local errors = {}
local MAX_ERRORS = 80

function addon:DoctorLog(kind, where, err, extra)
    errors[#errors + 1] = {
        time = GetTime(),
        kind = self:SafeToString(kind, "lua"),
        where = self:SafeToString(where, "?"),
        message = self:SafeToString(err, "<inaccessible error>"),
        extra = self:SafeToString(extra),
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:SetScript("OnEvent", function(_, event, source, operation)
    if addon:CanAccessValue(source) and source == addonName then
        addon:DoctorLog("taint", event, operation)
    end
end)
