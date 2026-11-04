-- Pure schema owner. All candidates are detached before the active store changes.
local _, addon = ...
local SCHEMA = 3.3
local MAX_NODES, MAX_DEPTH, MAX_STRING = 4096, 10, 512
local enums = {
    position = { "default", "inherit", "cursorRight", "cursor", "auto", "static" },
    cp = { "BOTTOM", "TOP", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
    p = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "TOP", "BOTTOM", "CENTER", "LEFT", "RIGHT" },
    combatPolicy = { "STRICT", "BALANCED", "AGGRESSIVE" },
    statusbarPosition = { "default", "bottom", "top" },
    statusbarColor = { "default", "auto", "smooth" },
    statusbarTextFormat = { "health/max", "percent", "health (percent)", "none" },
    colorfunc = { "default", "inherit", "class", "level", "reaction", "itemQuality", "selection", "faction" },
}
local ranges = {
    scale = { 0.5, 4 }, borderSize = { 1, 8 }, statusbarHeight = { 0, 24 },
    statusbarOffsetX = { -50, 50 }, statusbarOffsetY = { -50, 50 },
    width = { 20, 600 }, height = { 20, 600 }, facing = { -6.3, 6.3 },
    offsetX = { -1000, 1000 }, offsetY = { -1000, 1000 },
    x = { -1000, 1000 }, y = { -1000, 1000 }, cx = { -300, 300 }, cy = { -300, 300 },
    alpha = { 0, 1 },
}
local removedPaths = {
    variables = true,
    ["unit.player.showTargetBy"] = true,
    ["unit.npc.showTargetBy"] = true,
}
for _, key in ipairs({
    "legacyAuraFallback", "scrollEnabled", "scrollMaxHeight", "scrollWheelStep",
    "scrollMinLines", "autoWidthEnabled", "autoWidthMin", "autoWidthMax",
    "stableWidthMode", "nativeWrap", "layoutPipelineEnabled",
}) do
    removedPaths["general." .. key] = true
end
local function Finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function OneOf(value, values)
    for _, allowed in ipairs(values) do if value == allowed then return true end end
    return false
end
local function Clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Clone(child) end
    return copy
end
local function Portable(value, seen, budget, depth)
    if not addon:CanAccessValue(value) then return false end
    budget.count = budget.count + 1
    if budget.count > MAX_NODES or depth > MAX_DEPTH then return false end
    local kind = type(value)
    if kind == "number" then return Finite(value) end
    if kind == "string" then return #value <= MAX_STRING end
    if kind == "boolean" then return true end
    if kind ~= "table" or getmetatable(value) ~= nil or seen[value] then return false end
    if not addon:CanAccessTable(value) then return false end
    seen[value] = true
    for key, child in pairs(value) do
        if not addon:CanAccessValue(key) or (type(key) ~= "string" and type(key) ~= "number") then return false end
        if not Portable(key, seen, budget, depth + 1) or not Portable(child, seen, budget, depth + 1) then return false end
    end
    return true
end
local function ValidFormat(value)
    if type(value) ~= "string" or #value > 128 then return false end
    for width in value:gmatch("%%[-+ #0]*(%d+)") do if tonumber(width) > 64 then return false end end
    for precision in value:gmatch("%%[-+ #0]*%d*%.(%d+)") do if tonumber(precision) > 16 then return false end end
    return true
end

function addon:IsValidElementFormat(value)
    return ValidFormat(value)
end
local function Scalar(value, default, path, key)
    if type(value) == "string" and key:find("FontFlag$", 1) then
        if value == "NORMAL" or value == "NONE" then value = "" end
        return OneOf(value, { "", "default", "OUTLINE", "THINOUTLINE", "THICKOUTLINE", "MONOCHROME", "MONOCHROME,OUTLINE" }) and value or nil
    end
    if key:find("FontSize$", 1) then
        if value == "default" and type(default) == "string" then return value end
        return Finite(value) and value >= 6 and value <= 48 and value or nil
    end
    if enums[key] then return OneOf(value, enums[key]) and value or nil end
    if path:find("general.visibility.", 1, true) == 1 then
        return (value == "show" or value == "hide" or (key == "inCombat" and value == "unitOnly")) and value or nil
    end
    if key == "color" or key == "coloredBorder" then
        if type(value) ~= "string" then return nil end
        return (OneOf(value, enums.colorfunc) or value == "none" or value:match("^%x%x%x%x%x%x$")) and value or nil
    end
    if key == "filter" then
        if type(value) ~= "string" then return nil end
        local filter = value:gsub("^not ", "")
        return (OneOf(filter, { "none", "ininstance", "incombat", "inraid", "samerealm", "samecrossrealm", "sameguild", "inpvp", "inarena", "reaction5", "reaction6" })
            or filter:match("^reaction:[1-8]$")) and value or nil
    end
    if type(value) ~= type(default) then return nil end
    if type(value) == "number" then
        if not Finite(value) then return nil end
        local range = ranges[key] or { 0, 1 } -- Remaining numeric leaves are RGBA.
        return value >= range[1] and value <= range[2] and value or nil
    end
    if type(value) == "string" then
        if #value > MAX_STRING or (key == "wildcard" and not ValidFormat(value)) then return nil end
        return value
    end
    if type(value) == "boolean" then return value end
end

local Normalize
local function Layout(source, defaults, strict, path)
    local result = {}
    for key, default in pairs(defaults) do
        if type(key) == "string" then result[key] = Normalize(source[key], default, strict, path .. "." .. key) end
    end
    local rows, seen, supplied = {}, {}, false
    for key in pairs(source) do
        local index = tonumber(key)
        if index then
            if index < 1 or index > 16 or index ~= math.floor(index) or rows[index] then error("invalid layout row", 0) end
            rows[index], supplied = source[key], true
        elseif defaults[key] == nil and strict then error("unknown layout element", 0) end
    end
    if not supplied then
        for index, row in ipairs(defaults) do result[index] = Clone(row) end
        return result
    end
    local count = 0
    for index = 1, 16 do
        local row = rows[index]
        if row then
            if type(row) ~= "table" or getmetatable(row) then error("invalid layout row", 0) end
            local clean = {}
            for column, element in ipairs(row) do
                if column > 64 or type(element) ~= "string" or type(defaults[element]) ~= "table"
                    or element == "factionBig" or element == "npcTitle" or seen[element] then error("invalid layout element", 0) end
                clean[#clean + 1], seen[element], count = element, true, count + 1
            end
            for key in pairs(row) do
                if type(key) ~= "number" or key < 1 or key > #clean or key ~= math.floor(key) then error("invalid layout columns", 0) end
            end
            if #clean > 0 then result[#result + 1] = clean end
        end
    end
    if count > 64 then error("layout too large", 0) end
    return result
end

Normalize = function(value, default, strict, path)
    if value == nil then return Clone(default) end
    local key = path:match("([^.]+)$") or ""
    if type(default) ~= "table" then
        local result = Scalar(value, default, path, key)
        if result ~= nil then return result end
        if strict then error("invalid setting: " .. path, 0) end
        return Clone(default)
    end
    if type(value) ~= "table" or getmetatable(value) ~= nil or not addon:CanAccessTable(value) then
        if strict then error("invalid section: " .. path, 0) end
        return Clone(default)
    end
    if key == "elements" then
        local ok, result = pcall(Layout, value, default, strict, path)
        if ok then return result end
        if strict then error(result, 0) end
        return Clone(default)
    end
    local result = {}
    for childKey, childDefault in pairs(default) do
        if childKey ~= "version" and childKey ~= "variables" then
            result[childKey] = Normalize(value[childKey], childDefault, strict,
                path == "" and tostring(childKey) or path .. "." .. childKey)
        end
    end
    for childKey in pairs(value) do
        local childPath = path == "" and tostring(childKey) or path .. "." .. tostring(childKey)
        if default[childKey] == nil and not removedPaths[childPath] and strict then
            error("unknown setting: " .. childPath, 0)
        end
    end
    return result
end

function addon:NormalizeProfile(data, strict, defaults)
    defaults = defaults or self.__RT_DefaultDB or self.db
    if type(defaults) ~= "table" then return nil, "defaults unavailable" end
    if not self:CanAccessValue(data) then return nil, "inaccessible profile" end
    if type(data) ~= "table" then
        if strict then return nil, "profile must be a table" end
        data = {}
    end
    if not self:CanAccessTable(data) or getmetatable(data) ~= nil then return nil, "invalid profile table" end
    local version = self:SafeGet(data, "version")
    if strict and version ~= nil and (not Finite(version) or version < 0) then return nil, "invalid profile schema" end
    if type(version) == "number" and version > SCHEMA then return nil, "newer profile schema" end
    if strict and not Portable(data, {}, { count = 0 }, 0) then return nil, "unsupported or oversized profile" end
    local ok, candidate = pcall(Normalize, data, defaults, strict, "")
    if not ok then return nil, candidate end
    candidate.version = SCHEMA
    candidate.modules.General = true
    return candidate
end
