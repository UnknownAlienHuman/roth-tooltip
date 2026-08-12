-- RothTooltip Engine: Doctor
-- Collects errors/taint reports without killing the whole addon.

local _, addon = ...

local LibEvent = LibStub and LibStub:GetLibrary("LibEvent.7000", true)

addon._doctor = addon._doctor or { errors = {}, max = 80 }

local function Now()
    return (GetTime and GetTime()) or 0
end

local function Push(entry)
    local d = addon._doctor
    d.errors[#d.errors+1] = entry
    local over = #d.errors - (d.max or 80)
    if (over > 0) then
        for i = 1, over do
            table.remove(d.errors, 1)
        end
    end
end

-- kind: "lua" (pcall), "event" (LibEvent), "taint" (blocked)
function addon:DoctorLog(kind, where, err, extra)
    local entry = {
        t = Now(),
        kind = kind or "lua",
        where = tostring(where or "?"),
        err = tostring(err or "?"),
        extra = extra and tostring(extra) or nil,
    }
    Push(entry)
end

function addon:DoctorClear()
    addon._doctor.errors = {}
end

function addon:DoctorExportText()
    local d = addon._doctor
    local out = {}
    out[#out+1] = "RothTooltip Doctor Report"
    out[#out+1] = "Time\tKind\tWhere\tError"
    for _, e in ipairs(d.errors) do
        out[#out+1] = string.format("%.3f\t%s\t%s\t%s", e.t or 0, e.kind or "?", e.where or "?", e.err or "?")
        if (e.extra) then
            out[#out+1] = e.extra
        end
    end
    return table.concat(out, "\n")
end

-- Attach error sink + taint watcher
function addon:InitDoctor()
    if (self.__doctorInit) then return end
    self.__doctorInit = true

    if (LibEvent and LibEvent.SetErrorSink) then
        LibEvent:SetErrorSink(function(kind, event, err, func)
            local where = event or "?"
            if (addon.MM and addon.MM.OnError) then
                local module, hook = addon.MM:OnError(func, err)
                if (module and module ~= "?") then
                    where = string.format("%s:%s", module, hook or where)
                end
            end
            addon:DoctorLog(kind or "event", where, err or "?", nil)
        end)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, addonName, addonFunc)
        if (addonName == "RothTooltip") then
            addon:DoctorLog("taint", event, addonFunc or "?", nil)
        end
    end)
end

-- Initialize immediately (safe: LibStub and CreateFrame are loaded before addons)
addon:InitDoctor()
