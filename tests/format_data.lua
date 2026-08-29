local addon = {
    SafeToString = function(_, value, fallback)
        if value == nil then return fallback or "" end
        return tostring(value)
    end,
    CanAccessValue = function() return true end,
}

LibStub = {
    GetLibrary = function() return nil end,
}
IsAltKeyDown = function() return false end
IsControlKeyDown = function() return false end

assert(loadfile("Core.lua"))("RothTooltip", addon)

assert(addon:FormatData(123, { wildcard = "%d%%", color = "default" }, {}) == "123%")
assert(addon:FormatData(12.5, { wildcard = "%.1f", color = "default" }, {}) == "12.5")
assert(addon:FormatData("name", { wildcard = "<%s>", color = "default" }, {}) == "<name>")
assert(addon:FormatData(123, { wildcard = "%q", color = "default" }, {}) == "123")
assert(addon:FormatData(123, { wildcard = "%d", color = "ff0000" }, {}) == "|cffff0000123|r")

print("format data: ok")
