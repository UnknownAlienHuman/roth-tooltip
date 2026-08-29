-- RothTooltip diagnostics owner.
--
-- Collects bounded Lua/event/taint reports without terminating the addon. Error
-- text is capability-gated and repeated identical failures are coalesced.

local _, addon = ...
local LibEvent = LibStub and LibStub:GetLibrary("LibEvent.7000", true)

addon._doctor = addon._doctor or { errors = {}, max = 80, lastByKey = {} }

local function Now()
    return (GetTime and GetTime()) or 0
end

local function SafeText(value, fallback)
    if type(addon.SafeToString) == "function" then return addon:SafeToString(value, fallback or "?") end
    if value == nil then return fallback or "?" end
    local ok, text = pcall(tostring, value)
    return ok and text or (fallback or "?")
end

local function Push(entry)
    local doctor = addon._doctor
    doctor.errors = type(doctor.errors) == "table" and doctor.errors or {}
    doctor.lastByKey = type(doctor.lastByKey) == "table" and doctor.lastByKey or {}

    local key = table.concat({ entry.kind, entry.where, entry.err }, "\031")
    local previous = doctor.lastByKey[key]
    if type(previous) == "table" and entry.t - (previous.t or 0) <= 2 then
        previous.t = entry.t
        previous.count = (previous.count or 1) + 1
        if entry.extra then previous.extra = entry.extra end
        return
    end

    entry.count = 1
    doctor.errors[#doctor.errors + 1] = entry
    doctor.lastByKey[key] = entry

    while #doctor.errors > (doctor.max or 80) do
        local removed = table.remove(doctor.errors, 1)
        if removed then
            local removedKey = table.concat({ removed.kind, removed.where, removed.err }, "\031")
            if doctor.lastByKey[removedKey] == removed then doctor.lastByKey[removedKey] = nil end
        end
    end
end

function addon:DoctorLog(kind, where, errorMessage, extra)
    Push({
        t = Now(),
        kind = SafeText(kind, "lua"),
        where = SafeText(where, "?"),
        err = SafeText(errorMessage, "?"),
        extra = extra ~= nil and SafeText(extra, nil) or nil,
    })
end

function addon:DoctorClear()
    addon._doctor.errors = {}
    addon._doctor.lastByKey = {}
end

function addon:DoctorExportText()
    local output = {
        "RothTooltip Doctor Report",
        "Time\tCount\tKind\tWhere\tError",
    }
    for _, entry in ipairs(addon._doctor.errors or {}) do
        output[#output + 1] = string.format("%.3f\t%d\t%s\t%s\t%s",
            entry.t or 0,
            entry.count or 1,
            entry.kind or "?",
            entry.where or "?",
            entry.err or "?")
        if entry.extra then output[#output + 1] = entry.extra end
    end
    return table.concat(output, "\n")
end

function addon:InitDoctor()
    if self.__doctorInit then return end
    self.__doctorInit = true

    if LibEvent and LibEvent.SetErrorSink then
        LibEvent:SetErrorSink(function(kind, eventName, errorMessage, callback)
            local where = SafeText(eventName, "?")
            if addon.MM and addon.MM.OnError then
                local module, hook = addon.MM:OnError(callback, errorMessage)
                if module and module ~= "?" then
                    where = string.format("%s:%s", module, hook or where)
                end
            end
            addon:DoctorLog(kind or "event", where, errorMessage or "?", nil)
        end)
    end

    local ok, watcher = pcall(CreateFrame, "Frame")
    if not ok or not watcher then return end
    pcall(watcher.RegisterEvent, watcher, "ADDON_ACTION_BLOCKED")
    pcall(watcher.RegisterEvent, watcher, "ADDON_ACTION_FORBIDDEN")
    pcall(watcher.SetScript, watcher, "OnEvent", function(_, eventName, addonName, addonFunction)
        if addon:CanAccessValue(addonName) and addonName == "RothTooltip" then
            addon:DoctorLog("taint", eventName, addonFunction or "?", nil)
        end
    end)
end

addon:InitDoctor()
