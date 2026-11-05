-- Run from the repository root: lua5.1 tests/runtime.lua
local passed = 0
unpack = unpack or table.unpack
local secret = setmetatable({}, {
    __tostring = function() error("secret was formatted") end,
    __index = function() error("secret was indexed") end,
})
local function Accessible(value) return not rawequal(value, secret) end
local function Check(name, test)
    local ok, err = pcall(test)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("ok " .. passed .. " - " .. name)
end
local function Pack(...) return { n = select("#", ...), ... } end
local function Load(path, addon) assert(loadfile(path))("RothTooltip", addon) end

local clock, frames, deniedTables
local function Setup(foreign)
    clock, frames = 0, {}
    deniedTables = setmetatable({}, { __mode = "k" })
    LibStub = foreign
    canaccessvalue = Accessible
    canaccessallvalues = function(...)
        for index = 1, select("#", ...) do
            if not Accessible(select(index, ...)) then return false end
        end
        return true
    end
    canaccesstable = function(value)
        return Accessible(value) and deniedTables[value] ~= true
    end
    issecretvalue = function(value) return not Accessible(value) end
    GetTime = function() return clock end
    CreateFrame = function()
        local frame = { events = {}, scripts = {}, registrations = 0, removals = 0 }
        function frame:RegisterEvent(event)
            if event == "INVALID_EVENT" then error("unknown event") end
            self.events[event] = true
            self.registrations = self.registrations + 1
        end
        function frame:UnregisterEvent(event)
            self.events[event] = nil
            self.removals = self.removals + 1
        end
        function frame:SetScript(name, fn) self.scripts[name] = fn end
        frames[#frames + 1] = frame
        return frame
    end
    local addon = { db = { modules = {} } }
    Load("Engine/Safe.lua", addon)
    Load("Engine/ModuleManager.lua", addon)
    Load("Engine/Doctor.lua", addon)
    return addon, addon.MM, addon.LibEvent, frames[1]
end

Check("private bus does not create LibStub", function()
    local addon = Setup()
    assert(LibStub == nil)
    assert(addon.LibEvent)
end)
Check("foreign library is never touched", function()
    local foreign = { NewLibrary = function() error("foreign library modified") end,
        GetLibrary = function() error("foreign library accessed") end }
    local addon = Setup(foreign)
    assert(LibStub == foreign and addon.MM)
end)
Check("safe calls preserve arity, false and nil holes", function()
    local addon = Setup()
    local values = Pack(addon:SafeCall("tuple", function()
        return false, nil, 3, nil, 5, 6, 7, 8, 9, 10, nil, 12, nil
    end))
    assert(values.n == 13 and values[1] == false and values[2] == nil)
    assert(values[10] == 10 and values[12] == 12 and values[13] == nil)
    assert(Pack(addon:SafeCall("void", function() end)).n == 0)
end)
Check("safe calls do not truncate tuples beyond sixteen values", function()
    local addon = Setup()
    local values = Pack(addon:SafeCall("long-tuple", function()
        return 1, 2, 3, 4, 5, 6, 7, 8, nil, 10, 11, 12, 13, 14, 15, 16, false, 18, secret, nil
    end))
    assert(values.n == 20 and values[9] == nil and values[17] == false and values[18] == 18)
    assert(values[19] == nil and values[20] == nil)
end)
Check("inaccessible results are scrubbed without shifting positions", function()
    local addon = Setup()
    local values = Pack(addon:SafeCall("tuple", function() return secret, false, nil, 4, secret end))
    assert(values.n == 5 and values[1] == nil and values[2] == false and values[4] == 4 and values[5] == nil)
end)
Check("inaccessible function and inputs are not invoked", function()
    local addon = Setup()
    local called = false
    assert(addon:SafeCall("input", function() called = true end, secret) == nil)
    assert(addon:SafeCall("function", secret) == nil and not called)
    assert(addon:SafeGet(secret, "x") == nil)
    assert(addon:SafeGet({}, secret) == nil)
end)
Check("false remains false in boolean helpers", function()
    local addon = Setup()
    assert(addon:SafeBoolean(false) == false)
    assert(addon:SafeCallBoolean(function() return false end) == false)
    assert(addon:SafeCallBoolean(function() end) == nil)
    assert(addon:SafeCallBoolean(function() return secret end) == nil)
end)
Check("unknown access capability fails closed", function()
    local addon = {}
    canaccessvalue, canaccessallvalues, issecretvalue = nil, nil, nil
    Load("Engine/Safe.lua", addon)
    assert(not addon:CanAccessValue(1))
    assert(addon:SafeCall("unsupported", function() error("must not execute") end) == nil)
end)
Check("predicate fallbacks preserve false and reject secrets", function()
    Setup()
    canaccessvalue, canaccessallvalues = nil, nil
    local addon = {}
    Load("Engine/Safe.lua", addon)
    assert(addon:CanAccessValue(false) and not addon:CanAccessValue(secret))
    assert(addon:CanAccessAllValues(false, nil, 1) and not addon:CanAccessAllValues(nil, secret))
end)
Check("optional modules wait for saved settings", function()
    local addon, manager, bus = Setup()
    local calls = 0
    manager:RegisterModule("Disabled", { Init = function() calls = calls + 1 end,
        Enable = function() calls = calls + 1 end })
    assert(calls == 0 and not manager:IsEnabled("Disabled"))
    addon.db.modules.Disabled = false
    bus:trigger("tooltip:variables:loaded")
    assert(calls == 0 and not manager:IsEnabled("Disabled"))
end)
Check("core stays enabled and repairs saved core flag", function()
    local addon, manager, bus = Setup()
    manager:RegisterModule("General", {})
    assert(manager:IsEnabled("General"))
    addon.db.modules.General = false
    bus:trigger("tooltip:variables:loaded")
    assert(addon.db.modules.General == true)
    assert(manager:Disable("General") == false and manager:IsEnabled("General"))
end)
Check("failed enable rolls back earlier successful subscriptions", function()
    local addon, manager, bus, frame = Setup()
    bus:trigger("tooltip:variables:loaded")
    local disables = 0
    manager:RegisterModule("Broken", {
        Enable = function()
            manager:AttachEvent("Broken", "GOOD_EVENT", function() end)
            manager:AttachTrigger("Broken", "good", function() end)
            manager:AttachEvent("Broken", "INVALID_EVENT", function() end)
        end,
        Disable = function() disables = disables + 1 end,
    })
    assert(not manager:IsEnabled("Broken") and addon.db.modules.Broken == false)
    assert(frame.events.GOOD_EVENT == nil and not manager:HasTriggerSubscribers("good"))
    assert(#manager._links.Broken == 0 and disables == 1 and manager.state.Broken.errs == 1)
end)
Check("multi-event registration is atomic", function()
    local _, _, bus, frame = Setup()
    assert(not pcall(bus.attachEvent, bus, "GOOD_EVENT, INVALID_EVENT", function() end))
    assert(not frame.events.GOOD_EVENT and not bus.events.GOOD_EVENT and not bus.events.INVALID_EVENT)
end)
Check("failed registration retains other owners", function()
    local _, _, bus, frame = Setup()
    local calls = 0
    bus:attachEvent("GOOD_EVENT", function() calls = calls + 1 end)
    assert(not pcall(bus.attachEvent, bus, "GOOD_EVENT, INVALID_EVENT", function() end))
    assert(frame.events.GOOD_EVENT)
    bus:event("GOOD_EVENT")
    assert(calls == 1)
end)
Check("failed init is retryable and never invokes Enable", function()
    local _, manager, bus = Setup()
    bus:trigger("tooltip:variables:loaded")
    local fail, initialized, enabled = true, 0, 0
    manager:RegisterModule("Retry", {
        Init = function() initialized = initialized + 1; if fail then error("init failed") end end,
        Enable = function() enabled = enabled + 1 end,
    })
    assert(not manager.state.Retry.initialized and enabled == 0)
    fail = false
    assert(manager:Enable("Retry") and initialized == 2 and enabled == 1)
end)
Check("explicit false is not successful Enable", function()
    local addon, manager, bus = Setup()
    bus:trigger("tooltip:variables:loaded")
    manager:RegisterModule("Refused", { Enable = function() return false end })
    assert(not manager:IsEnabled("Refused") and addon.db.modules.Refused == false)
end)
Check("inaccessible lifecycle result fails without formatting", function()
    local _, manager, bus = Setup()
    bus:trigger("tooltip:variables:loaded")
    manager:RegisterModule("SecretResult", { Enable = function() return secret end })
    assert(not manager:IsEnabled("SecretResult"))
end)
Check("repeated enable is idempotent; disable unregisters native events", function()
    local _, manager, bus, frame = Setup()
    bus:trigger("tooltip:variables:loaded")
    local inits, calls = 0, 0
    local callback = function() calls = calls + 1 end
    manager:RegisterModule("Stable", {
        Init = function() inits = inits + 1 end,
        Enable = function()
            assert(manager:IsEnabled("Stable"))
            manager:AttachEvent("Stable", "UPDATE", callback)
            manager:AttachEvent("Stable", "UPDATE", callback)
        end,
    })
    assert(manager:Enable("Stable") and #manager._links.Stable == 1)
    bus:event("UPDATE"); assert(calls == 1)
    assert(manager:Disable("Stable") and not frame.events.UPDATE)
    bus:event("UPDATE"); assert(calls == 1)
    assert(manager:Enable("Stable") and inits == 1)
    bus:event("UPDATE"); assert(calls == 2)
end)
Check("disable errors do not leave newly added callbacks", function()
    local _, manager, bus, frame = Setup()
    bus:trigger("tooltip:variables:loaded")
    manager:RegisterModule("Cleanup", {
        Disable = function()
            manager:AttachEvent("Cleanup", "LEAK", function() end)
            error("cleanup failed")
        end,
    })
    assert(manager:Disable("Cleanup") == false)
    assert(not manager:IsEnabled("Cleanup") and not frame.events.LEAK)
    assert(#manager._links.Cleanup == 0)
end)
Check("unknown and duplicate modules are rejected", function()
    local _, manager = Setup()
    assert(manager:Enable("Missing") == false and manager:Disable("Missing") == false)
    local module = {}
    manager:RegisterModule("Known", module)
    manager:RegisterModule("Known", module)
    assert(not pcall(manager.RegisterModule, manager, "Known", {}))
end)
Check("removing next callback during dispatch takes effect immediately", function()
    local _, _, bus = Setup()
    local calls = {}
    local removed = function() calls[#calls + 1] = "removed" end
    bus:attachTrigger("test", function() calls[#calls + 1] = "first"; bus:detachTrigger("test", removed) end)
    bus:attachTrigger("test", removed)
    bus:attachTrigger("test", function() calls[#calls + 1] = "last" end)
    bus:trigger("test")
    assert(table.concat(calls, ",") == "first,last")
end)
Check("self-removal does not skip the following callback", function()
    local _, _, bus = Setup()
    local calls = 0
    bus:attachTrigger("test", function(self) bus:detachTrigger("test", self) end)
    bus:attachTrigger("test", function() calls = calls + 1 end)
    bus:trigger("test"); bus:trigger("test")
    assert(calls == 2)
end)
Check("new callbacks wait until the next dispatch", function()
    local _, _, bus = Setup()
    local calls = 0
    local added = function() calls = calls + 1 end
    bus:attachTrigger("test", function() bus:attachTrigger("test", added) end)
    bus:trigger("test"); assert(calls == 0)
    bus:trigger("test"); assert(calls == 1)
end)
Check("nested dispatch does not activate a new cross-event subscriber", function()
    local _, manager, bus = Setup()
    local calls = 0
    bus:attachTrigger("outer", function()
        bus:attachTrigger("inner", function() calls = calls + 1 end)
        assert(not manager:HasTriggerSubscribers("inner"))
        bus:trigger("inner")
    end)
    bus:trigger("outer"); assert(calls == 0)
    assert(manager:HasTriggerSubscribers("inner"))
    bus:trigger("inner"); assert(calls == 1)
end)
Check("pending subscriber removed before outer completion stays removed", function()
    local _, _, bus = Setup()
    local calls = 0
    local pending = function() calls = calls + 1 end
    bus:attachTrigger("outer", function()
        bus:attachTrigger("inner", pending)
        bus:detachTrigger("inner", pending)
        bus:trigger("inner")
    end)
    bus:trigger("outer"); bus:trigger("inner")
    assert(calls == 0 and not bus.triggers.inner)
end)
Check("detach and reattach cannot resurrect a captured callback", function()
    local _, _, bus = Setup()
    local calls, first = 0, true
    local callback = function() calls = calls + 1 end
    bus:attachTrigger("test", function()
        if first then first = false; bus:detachTrigger("test", callback); bus:attachTrigger("test", callback) end
    end)
    bus:attachTrigger("test", callback)
    bus:trigger("test"); assert(calls == 0)
    bus:trigger("test"); assert(calls == 1)
end)
Check("one-shot detaches before reentrant dispatch and errors", function()
    local _, _, bus = Setup()
    local calls = 0
    bus:attachTriggerOnce("one,two", function()
        calls = calls + 1
        bus:trigger("two")
        error("expected error")
    end)
    bus:trigger("one"); bus:trigger("one"); bus:trigger("two")
    assert(calls == 1 and not bus.triggers.one and not bus.triggers.two)
end)
Check("native event forwarding keeps false and nil arguments", function()
    local _, _, bus, frame = Setup()
    local received
    bus:attachEvent("UPDATE", function(_, ...) received = Pack(...) end)
    frame.scripts.OnEvent(frame, "UPDATE", false, nil, 3, nil)
    assert(received.n == 4 and received[1] == false and received[3] == 3)
end)
Check("detach by callback removes all native subscriptions", function()
    local _, _, bus, frame = Setup()
    local callback = function() end
    bus:attachEvent("A,B,C", callback)
    bus:detachEvent(callback)
    assert(not frame.events.A and not frame.events.B and not frame.events.C)
    assert(not bus.events.A and not bus.events.B and not bus.events.C)
end)
Check("error storms are bounded and muted callbacks recover", function()
    local addon, _, bus = Setup()
    local calls = 0
    bus:attachTrigger("broken", function() calls = calls + 1; error("repeat") end)
    for _ = 1, 100 do bus:trigger("broken") end
    assert(calls == 3)
    clock = 61; bus:trigger("broken"); assert(calls == 4)
    assert(addon:DoctorExportText():find("repeat", 1, true))
end)
Check("inaccessible error and taint fields are never formatted", function()
    local addon = Setup()
    addon:SafeCall("failure", function() error(secret) end)
    local watcher = frames[1]
    watcher.scripts.OnEvent(watcher, "ADDON_ACTION_BLOCKED", secret, secret)
    watcher.scripts.OnEvent(watcher, "ADDON_ACTION_BLOCKED", "RothTooltip", secret)
    assert(addon:DoctorExportText():find("<inaccessible error>", 1, true))
end)
Check("diagnostics retain at most 80 entries and clear correctly", function()
    local addon = Setup()
    for index = 1, 100 do addon:DoctorLog("test", "bounded", "marker-" .. index) end
    local text = addon:DoctorExportText()
    local _, count = text:gsub("marker%-", "")
    assert(count == 80 and not text:find("marker-20\n", 1, true))
    assert(text:find("marker-100", 1, true))
    addon:DoctorClear()
    assert(not addon:DoctorExportText():find("marker", 1, true))
end)
Check("diagnostic payloads have fixed byte budgets", function()
    local addon, manager = Setup()
    local huge = string.rep("x", 5000)
    addon:DoctorLog(huge, huge, huge, huge)
    local report = addon:DoctorExportText()
    assert(#report < 2500)
    manager:Track("General", function() end, "bounded")
    local tracked
    for fn in pairs(manager.meta) do tracked = fn end
    manager:OnError(tracked, huge)
    assert(#manager.state.General.lastErr == 1024)
end)
Check("doctor shares the private native event owner", function()
    local _, _, bus, frame = Setup()
    assert(#frames == 1)
    assert(frame.events.ADDON_ACTION_BLOCKED and frame.events.ADDON_ACTION_FORBIDDEN)
    assert(bus.events.ADDON_ACTION_BLOCKED and bus.events.ADDON_ACTION_FORBIDDEN)
end)
Check("reentrant enable cannot report a half-initialized module as ready", function()
    local _, manager = Setup()
    local module = {}
    function module:Init()
        assert(manager:Enable("Reentrant") == false)
        assert(manager:Disable("Reentrant") == false)
    end
    manager:RegisterModule("Reentrant", module)
    manager:ApplySaved()
    assert(manager:Enable("Reentrant") == true)
end)
Check("enable failure detaches before cleanup can emit an event", function()
    local _, manager, bus, frame = Setup()
    local calls = 0
    manager:RegisterModule("Broken", {
        Enable = function()
            manager:AttachEvent("Broken", "UPDATE", function() calls = calls + 1 end)
            return false
        end,
        Disable = function()
            assert(not manager:IsEnabled("Broken"))
            bus:event("UPDATE")
        end,
    })
    manager:ApplySaved()
    assert(not manager:Enable("Broken"))
    assert(calls == 0 and not frame.events.UPDATE)
    assert(manager.state.Broken.errs > 0)
end)
Check("disabled modules cannot recreate subscriptions from late work", function()
    local _, manager, _, frame = Setup()
    manager:RegisterModule("Late", {})
    manager:ApplySaved()
    manager:Enable("Late"); manager:Disable("Late")
    assert(not pcall(manager.AttachEvent, manager, "Late", "UPDATE", function() end))
    assert(not pcall(manager.AttachTrigger, manager, "Late", "update", function() end))
    assert(not frame.events.UPDATE and #manager._links.Late == 0)
end)
Check("mute threshold counts failures within one ten-second window", function()
    local _, _, bus = Setup()
    local calls = 0
    bus:attachTrigger("sporadic", function() calls = calls + 1; error("expected") end)
    for step = 0, 4 do clock = step * 6; bus:trigger("sporadic") end
    assert(calls == 5, "separated failures were mistaken for a burst")
end)
Check("native one-shot unregisters before its callback throws", function()
    local _, _, bus, frame = Setup()
    local calls = 0
    bus:attachEventOnce("ONCE", function()
        calls = calls + 1
        assert(not frame.events.ONCE)
        bus:event("ONCE")
        error("expected")
    end)
    bus:event("ONCE"); bus:event("ONCE")
    assert(calls == 1 and frame.removals == 1)
end)
Check("one thousand toggles release callbacks and native registrations", function()
    local _, manager, bus, frame = Setup()
    local calls = 0
    local baselineRegistrations, baselineRemovals = frame.registrations, frame.removals
    manager:ApplySaved()
    manager:RegisterModule("Cycle", { Enable = function()
        manager:AttachEvent("Cycle", "UPDATE", function() calls = calls + 1 end)
    end })
    for _ = 1, 1000 do
        assert(manager:Enable("Cycle"))
        bus:event("UPDATE")
        assert(manager:Disable("Cycle"))
    end
    collectgarbage("collect")
    assert(calls == 1000 and frame.registrations - baselineRegistrations == 1000
        and frame.removals - baselineRemovals == 1000)
    assert(not bus.events.UPDATE and #manager._links.Cycle == 0)
    local retained = 0
    for _ in pairs(manager.meta) do retained = retained + 1 end
    assert(retained == 1, "detached callback metadata leaked")
end)

local function Globals()
    Enum = { ForbiddenAspect = { ScriptBindings = 1, UntrustedLayoutScriptExecution = 2, ChangeParent = 4 },
        TooltipDataType = { Item = 0, Spell = 1, Unit = 2, UnitAura = 3 } }
    InCombatLockdown = function() return false end
    IsAltKeyDown = function() return false end
    IsControlKeyDown = function() return false end
    IsShiftKeyDown = function() return false end
    GetRealmName = function() return "Realm" end
    strupper, strlower, format, floor = string.upper, string.lower, string.format, math.floor
    strtrim = function(text) return text:match("^%s*(.-)%s*$") end
    strsplit = function(separator, text)
        local parts, start = {}, 1
        while true do
            local first, last = text:find(separator, start, true)
            if not first then parts[#parts + 1] = text:sub(start); break end
            parts[#parts + 1] = text:sub(start, first - 1); start = last + 1
        end
        return unpack(parts)
    end
    wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end; return tbl end
    StaticPopupDialogs, SlashCmdList = {}, {}
    Settings = nil
    GameTooltip, GameTooltipHeaderText, GameTooltipText, UIParent = nil, nil, nil, nil
    SharedTooltip_SetBackdropStyle = function() end
    GameTooltip_SetBackdropStyle = function() end
    GameTooltip_SetDefaultAnchor = function() end
    local hooks = {}
    hooksecurefunc = function(name, callback)
        hooks[name] = hooks[name] or {}
        table.insert(hooks[name], callback)
    end
    return hooks
end

local function LoadUI(foreign)
    local addon, manager, bus, frame = Setup(foreign)
    local hooks = Globals()
    addon.db.general = {}
    addon.tooltipSet = setmetatable({}, { __mode = "k" })
    function addon:IsManagedTooltip(tooltip)
        return self:IsTooltipSafe(tooltip) and self.tooltipSet[tooltip] == true
    end
    function addon:AreAurasRestricted() return false end
    function addon:AreUnitStatsRestricted() return false end
    Load("Engine/Policy.lua", addon)
    Load("Core.lua", addon)
    Load("Engine/Style.lua", addon)
    Load("Options/Core.lua", addon)
    Load("Options.lua", addon)
    Load("Engine/Debug.lua", addon)
    return addon, manager, bus, frame, hooks
end

Check("all changed UI files load without LibStub", function()
    local addon = LoadUI()
    assert(LibStub == nil and addon.Options and SlashCmdList.RothTooltip)
end)
Check("optional media lookup is lazy", function()
    local calls = 0
    local addon = LoadUI({ GetLibrary = function(_, name, silent)
        assert(name == "LibSharedMedia-3.0" and silent == true)
        calls = calls + 1
    end })
    assert(calls == 0)
    addon:GetSharedMediaFile("font", "LateFont")
    assert(calls == 1)
end)
Check("optional media can appear after addon load", function()
    local addon = LoadUI()
    local library = {
        IsValid = function(_, kind, value) return kind == "font" and value == "LateFont" end,
        Fetch = function() return "late-font.ttf" end,
    }
    LibStub = { GetLibrary = function() return library end }
    assert(addon:GetSharedMediaFile("font", "LateFont") == "late-font.ttf")
end)
Check("only one hook owns each native backdrop function", function()
    local _, _, _, _, hooks = LoadUI()
    assert(#hooks.SharedTooltip_SetBackdropStyle == 1)
    assert(#hooks.GameTooltip_SetBackdropStyle == 1)
    assert(#hooks.GameTooltip_SetDefaultAnchor == 1)
end)
Check("negated filters correctly reject a true result", function()
    local addon = LoadUI()
    addon.filterfunc.example = function() return true end
    assert(addon:CheckFilter({ enable = true, filter = "example" }, {}))
    assert(not addon:CheckFilter({ enable = true, filter = "not example" }, {}))
    addon.filterfunc.example = function() return false end
    assert(addon:CheckFilter({ enable = true, filter = "not example" }, {}))
end)
Check("modifiers bypass filters but never enable disabled elements", function()
    local addon = LoadUI()
    IsAltKeyDown = function() return true end
    addon.filterfunc.example = function() return false end
    assert(addon:CheckFilter({ enable = true, filter = "example" }, {}))
    assert(not addon:CheckFilter({ enable = false, filter = "none" }, {}))
    assert(not addon:CheckFilter(nil, {}))
end)
Check("unknown object security does not permit method calls", function()
    local addon = LoadUI()
    local calls = 0
    local object = { CanBeAccessedInContext = function() return true end,
        IsForbidden = function() end, Work = function() calls = calls + 1 end }
    addon:SafeMethod(object, "Work"); assert(calls == 0)
    object.IsForbidden = function() return secret end
    addon:SafeMethod(object, "Work"); assert(calls == 0)
    object.IsForbidden = function() return false end
    addon:SafeMethod(object, "Work"); assert(calls == 1)
end)
Check("table access denial is checked before member indexing", function()
    Setup()
    local blocked = setmetatable({}, { __index = function() error("indexed denied table") end })
    canaccesstable = function(value) return value ~= blocked end
    local addon = {}; Load("Engine/Safe.lua", addon)
    assert(not addon:CanAccessTable(blocked))
    assert(addon:SafeGet(blocked, "field") == nil)
    assert(not addon:IsObjectAccessible(blocked))
end)
Check("missing table capability fails closed", function()
    Setup(); canaccesstable = nil
    local addon = {}; Load("Engine/Safe.lua", addon)
    assert(not addon:CanAccessTable({}))
    assert(addon:SafeGet({}, "field") == nil)
end)
Check("forbidden aspect answers require an accessible false", function()
    local addon = LoadUI()
    local object = { HasAnyForbiddenAspects = function() return false end }
    assert(addon:IsTooltipSafe(object) and addon:CanBindScripts(object))
    for _, value in ipairs({ true, 0, "false", secret }) do
        object.HasAnyForbiddenAspects = function() return value end
        assert(not addon:IsTooltipSafe(object) and not addon:CanBindScripts(object))
    end
    object.HasAnyForbiddenAspects = function() end
    assert(not addon:IsTooltipSafe(object))
    object.HasAnyForbiddenAspects = nil
    assert(not addon:IsTooltipSafe(object))
end)
Check("AGGRESSIVE policy cannot override restricted tooltip layout", function()
    local addon = LoadUI()
    addon.db.general.combatPolicy = "AGGRESSIVE"
    InCombatLockdown = function() return true end
    local tooltip = { HasAnyForbiddenAspects = function() return true end }
    assert(not addon:AllowTrigger("skin", tooltip))
    assert(not addon:AllowTrigger("item", tooltip))
    assert(not addon:AllowTrigger("spell", tooltip))
end)
Check("unknown module cannot be enabled before saved settings", function()
    local _, manager = LoadUI()
    manager:RegisterModule("Deferred", { Enable = function() error("premature enable") end })
    assert(not manager:Enable("Deferred"))
    assert(not manager:IsEnabled("Deferred"))
end)
Check("shared callback errors retain the subscription owner", function()
    local _, manager, bus = LoadUI()
    bus:trigger("tooltip:variables:loaded")
    local function fails() error("failure") end
    manager:RegisterModule("First", { Enable = function() manager:AttachTrigger("First", "first", fails) end })
    manager:RegisterModule("Second", { Enable = function() manager:AttachTrigger("Second", "second", fails) end })
    bus:trigger("first")
    assert(manager.state.First.errs == 1 and manager.state.Second.errs == 0)
    assert(manager.state.First.lastHook == "first")
end)
Check("Settings reports failed enable as disabled", function()
    local addon, manager, bus = LoadUI()
    bus:trigger("tooltip:variables:loaded")
    manager:RegisterModule("Broken", { Enable = function() return false end })
    local value
    bus:attachTrigger("tooltip:variable:changed", function(_, _, changed) value = changed end)
    assert(not addon.Options:SetVariable("modules.Broken", true))
    assert(value == false and addon.db.modules.Broken == false and not manager:IsEnabled("Broken"))
end)
Check("Settings cannot disable the core module", function()
    local addon, manager, bus = LoadUI()
    manager:RegisterModule("General", {})
    bus:trigger("tooltip:variables:loaded")
    assert(not addon.Options:SetVariable("modules.General", false))
    assert(addon.db.modules.General == true and manager:IsEnabled("General"))
end)
Check("slash commands report actual outcomes", function()
    local addon, manager, bus = LoadUI()
    local refreshes = 0
    addon.RefreshManagedTooltipsMatching = function() refreshes = refreshes + 1 end
    bus:trigger("tooltip:variables:loaded")
    manager:RegisterModule("General", {})
    manager:RegisterModule("Broken", { Enable = function() return false end })
    addon.db.modules.Working = false
    manager:RegisterModule("Working", {})
    local messages, originalPrint = {}, print
    print = function(message) messages[#messages + 1] = message end
    local ok, err = pcall(function()
        local command = SlashCmdList.ROTHTOOLTIPDOCTOR
        command("enable Missing"); command("enable Broken"); command("disable General")
        command("enable Working"); command("toggle Working")
    end)
    print = originalPrint
    assert(ok, err)
    for index = 1, 3 do assert(messages[index]:find("failed", 1, true)) end
    assert(messages[4] == "RothTooltip: Working enabled")
    assert(messages[5] == "RothTooltip: Working disabled")
    assert(refreshes == 2)
end)
Check("managed tooltip trigger forwarding retains nil positions", function()
    local addon, _, bus = LoadUI()
    function addon:ForEachManagedTooltip(callback) callback({}) end
    local result
    bus:attachTrigger("tuple", function(_, _, ...) result = Pack(...) end)
    addon.Options:TriggerManagedTooltips("tuple", false, nil, 3, nil)
    assert(result.n == 4 and result[1] == false and result[3] == 3)
end)

local function MockSettings()
    local categories, values, notifications = {}, {}, {}
    local function Category(name)
        local category = { name = name }
        function category:GetID() return self.name end
        local layout = { AddInitializer = function() end }
        categories[#categories + 1] = category
        return category, layout
    end
    local function Initializer() return { SetParentInitializer = function() end } end
    Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },
        Default = { True = true, False = false },
        RegisterVerticalLayoutCategory = Category,
        RegisterVerticalLayoutSubcategory = function(_, name) return Category(name) end,
        RegisterProxySetting = function(_, name, _, _, default, getter, setter)
            assert(not values[name], "duplicate setting: " .. name)
            values[name] = { default = default, get = getter, set = setter }
            return values[name]
        end,
        CreateCheckbox = Initializer, CreateSlider = Initializer,
        CreateColorSwatch = Initializer,
        CreateDropdown = function(_, setting, options)
            setting.options = options()
            return Initializer()
        end,
        CreateSliderOptions = function() return {} end,
        CreateControlTextContainer = function()
            local data = {}
            return {
                Add = function(_, value, text) data[#data + 1] = { value = value, text = text } end,
                GetData = function() return data end,
            }
        end,
        RegisterAddOnCategory = function() end,
        NotifyUpdate = function(name)
            local setting = values[name]
            if not setting then return end
            notifications[name] = (notifications[name] or 0) + 1
            setting.notifiedValue = setting.get()
        end,
    }
    return categories, values, notifications
end
Check("Settings initializes every category without external libraries", function()
    local addon = LoadUI()
    local categories, values = MockSettings()
    addon.__RT_VariablesLoaded = true
    function addon:IsUsingCharacterProfile() return false end
    assert(addon.Options:TryInitialize())
    assert(#categories == 10)
    assert(values.ROTH_TOOLTIP_GENERAL_SCALE and values.ROTH_TOOLTIP_MODULES_UNIT)
    assert(addon.Options:TryInitialize() and #categories == 10)
    assert(LibStub == nil)
end)
Check("Settings exposes complete supported domains and no dead unit modes", function()
    local addon = LoadUI()
    local _, values = MockSettings()
    addon.__RT_VariablesLoaded = true
    function addon:IsUsingCharacterProfile() return false end
    assert(addon.Options:TryInitialize())

    local function HasOption(settingName, expected)
        local setting = assert(values[settingName], settingName)
        for _, option in ipairs(setting.options or {}) do
            if option.value == expected then return true end
        end
        return false
    end

    assert(HasOption("ROTH_TOOLTIP_UNIT_PLAYER_ANCHOR_POSITION", "auto"))
    assert(HasOption("ROTH_TOOLTIP_UNIT_PLAYER_ANCHOR_P", "CENTER"))
    assert(HasOption("ROTH_TOOLTIP_UNIT_PLAYER_ELEMENTS_NAME_FILTER", "sameguild"))
    assert(HasOption("ROTH_TOOLTIP_UNIT_PLAYER_ELEMENTS_NAME_FILTER", "not sameguild"))
    assert(not HasOption("ROTH_TOOLTIP_UNIT_PLAYER_ELEMENTS_NAME_COLOR_MODE", "itemQuality"))
    assert(values.ROTH_TOOLTIP_UNIT_NPC_ELEMENTS_NPCTITLE == nil)
end)
Check("changing shared fonts dispatches once, not once per tooltip", function()
    local addon, _, bus = LoadUI()
    function addon:ForEachManagedTooltip(callback) for _ = 1, 20 do callback({}) end end
    local count = 0
    bus:attachTrigger("tooltip.style.font.header", function() count = count + 1 end)
    addon.Options:SetVariable("general.headerFontSize", 14)
    assert(count == 1)
end)


local function Visual(parent)
    local frame = { parent = parent, shown = true, scripts = {}, hooks = 0, clears = 0 }
    function frame:CanBeAccessedInContext() return not self.inaccessible end
    function frame:IsForbidden() return false end
    function frame:HasAnyForbiddenAspects() return self.restricted == true end
    function frame:IsShown() return self.shown end
    function frame:GetFrameLevel() return 1 end
    function frame:GetFont() return "font.ttf", 12, "" end
    function frame:HasScript() return true end
    function frame:HookScript(name, callback)
        self.scripts[name] = self.scripts[name] or {}
        table.insert(self.scripts[name], callback); self.hooks = self.hooks + 1
    end
    function frame:Fire(name)
        for _, callback in ipairs(self.scripts[name] or {}) do callback(self) end
    end
    function frame:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
    function frame:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
    function frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function frame:ClearAllPoints() self.clears = self.clears + 1 end
    function frame:SetVertexColor(...) self.color = { ... } end
    function frame:SetTexture(texture) self.texture = texture end
    function frame:CreateTexture() return Visual(self) end
    for _, method in ipairs({ "SetAllPoints", "SetPoint", "SetHeight", "SetWidth", "SetFrameLevel",
        "SetTexCoord", "SetHorizTile", "SetVertTile", "SetBlendMode", "SetScale", "SetAlpha", "SetGradient" }) do
        frame[method] = function() end
    end
    return frame
end
Check("spell icon presentation does not mutate native icon or border ownership", function()
    local addon, _, bus = LoadUI()
    addon.db.spell = { showIcon = true }
    addon.db.modules.Spell = true
    addon.GetPrimaryTooltipContext = function() return { spellID = 42 } end
    addon.ApplyGeneralStyleToTooltip = function() end

    local tooltip, line, border = Visual(), Visual(), Visual()
    line.text = "Spell"
    function line:GetText() return self.text end
    function line:SetFormattedText(pattern, ...) self.text = string.format(pattern, ...) end
    tooltip.IconBorder = border
    tooltip.Icon = Visual(tooltip)
    addon.GetLine = function() return line end

    local previousSpell = C_Spell
    C_Spell = { GetSpellTexture = function() return 123 end }
    Load("Spell.lua", addon)
    bus:trigger("tooltip:variables:loaded")
    bus:trigger("tooltip:spell", tooltip, { spellID = 42 })
    C_Spell = previousSpell

    assert(line.text:find("^|T123", 1) ~= nil)
    assert(border:IsShown() and tooltip.Icon:IsShown())
end)
local function StyledUI()
    local addon, manager, bus, _, hooks = LoadUI()
    UIParent, GameTooltip = Visual(), Visual()
    GameTooltip.NineSlice = Visual(GameTooltip)
    GameTooltip.Background = Visual(GameTooltip); GameTooltip.Background:Hide()
    addon.tooltipSet[GameTooltip] = true
    local created = 0
    CreateFrame = function(_, _, parent) created = created + 1; return Visual(parent) end
    addon.db.general = { scale = 1, mask = true, bgfile = "RothTooltipDarkTexture",
        borderCorner = "RothTooltipDarkFrame", borderSize = 1,
        borderColor = { 0.6, 0.6, 0.6, 0.85 }, background = { 0, 0, 0, 0.9 } }
    bus:trigger("tooltip:init", GameTooltip)
    return addon, bus, GameTooltip, hooks, function() return created end
end
Check("repeated style initialization does not add hooks or frames", function()
    local addon, bus, tooltip, _, created = StyledUI()
    local initial = created()
    assert(initial == 3 and tooltip.hooks == 3)
    for _ = 1, 100 do bus:trigger("tooltip:init", tooltip) end
    assert(created() == initial and tooltip.hooks == 3)
    assert(not addon:DoctorExportText():find("\nlua\t", 1, true))
end)
Check("Roth border stays flat-border-free after size and color changes", function()
    local addon, bus, tooltip = StyledUI()
    local style = addon:GetTooltipStyle(tooltip)
    bus:trigger("tooltip.style.border.color", tooltip, 0.2, 0.3, 0.4, 0.8)
    bus:trigger("tooltip.style.border.size", tooltip, 3)
    for _, edge in pairs(style.border) do assert(edge.color[4] == 0) end
    assert(style.rothFrame.color[1] == 0.2 and style.borderColor[3] == 0.4)
    bus:trigger("tooltip.style.border.corner", tooltip, "angular")
    for _, edge in pairs(style.border) do assert(edge.color[1] == 0.2 and edge.color[4] == 0.8) end
end)
Check("show and native backdrop updates preserve feature colors", function()
    local addon, bus, tooltip, hooks = StyledUI()
    bus:trigger("tooltip.style.border.color", tooltip, 0.2, 0.3, 0.4, 0.8)
    bus:trigger("tooltip.style.background", tooltip, 0.1, 0.2, 0.3, 0.7)
    tooltip:Fire("OnShow")
    hooks.SharedTooltip_SetBackdropStyle[1](tooltip)
    hooks.GameTooltip_SetBackdropStyle[1](tooltip)
    local style = addon:GetTooltipStyle(tooltip)
    assert(style.borderColor[1] == 0.2 and style.backgroundColor[3] == 0.3)
end)
Check("one cleared callback performs one layout reset", function()
    local addon, _, tooltip = StyledUI()
    local style = addon:GetTooltipStyle(tooltip)
    local before = style.clears
    tooltip:Fire("OnTooltipCleared")
    assert(style.clears == before + 1)
end)
Check("unregistered tooltips restore native regions and stop dispatching", function()
    local addon, bus, tooltip = StyledUI()
    local count = 0
    bus:attachTrigger("tooltip:show, tooltip:hide, tooltip:cleared", function() count = count + 1 end)
    addon.tooltipSet[tooltip] = nil
    bus:trigger("tooltip:unregister", tooltip)
    assert(tooltip.NineSlice:IsShown() and not tooltip.Background:IsShown())
    tooltip:Fire("OnShow"); tooltip:Fire("OnHide"); tooltip:Fire("OnTooltipCleared")
    assert(count == 0)
end)
Check("temporary style access denial does not create a replacement", function()
    local addon, bus, tooltip, _, created = StyledUI()
    local style = addon:GetTooltipStyle(tooltip)
    local initial = created()
    style.inaccessible = true
    bus:trigger("tooltip:init", tooltip)
    assert(created() == initial and addon:GetTooltipStyle(tooltip) == nil)
    style.inaccessible = false
    assert(addon:GetTooltipStyle(tooltip) == style)
end)
Check("restricted tooltip layouts do not create visual attachments", function()
    local addon, bus, _, _, created = StyledUI()
    local tooltip = Visual(); tooltip.restricted = true; addon.tooltipSet[tooltip] = true
    local before = created()
    bus:trigger("tooltip:init", tooltip)
    assert(created() == before and tooltip.hooks == 0)
    assert(addon:GetTooltipStyle(tooltip) == nil)
end)

print(string.format("PASS: %d tests (%s); WoW client not run", passed, _VERSION))
return { Check = Check, Setup = Setup, Globals = Globals, Visual = Visual, MockSettings = MockSettings,
    Load = Load, secret = secret,
    DenyTable = function(value, denied) deniedTables[value] = denied and true or nil end,
    SetClock = function(value) clock = value end, Count = function() return passed end }
