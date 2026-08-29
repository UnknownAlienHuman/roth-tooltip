-- RothTooltip schema and SavedVariables ownership.
--
-- Defaults are immutable after Config.lua loads. Active account/character
-- profiles are rebuilt as detached tables containing only known schema keys,
-- except explicitly opaque extension maps.

local _, addon = ...

local OPAQUE_PATHS = {
    variables = true,
}

local function JoinPath(path, key)
    key = tostring(key)
    if path == nil or path == "" then return key end
    return path .. "." .. key
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return result
end

local function NormalizeNumericKeys(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return value end
    seen[value] = true

    local converted = {}
    for key, child in pairs(value) do
        if type(key) == "string" and key:match("^[1-9]%d*$") then
            value[key] = nil
            converted[tonumber(key)] = child
        end
    end
    for key, child in pairs(converted) do
        if value[key] == nil then value[key] = child end
    end
    for _, child in pairs(value) do NormalizeNumericKeys(child, seen) end
    return value
end

local function CompatibleScalar(defaultValue, storedValue)
    if storedValue ~= nil and type(defaultValue) == type(storedValue) then
        return DeepCopy(storedValue)
    end
    return DeepCopy(defaultValue)
end

local function IsElementsPath(path)
    return type(path) == "string" and path:match("%.elements$") ~= nil
end

local MergeKnown

local function MergeElements(defaults, stored, path)
    local result = {}
    local valid = {}
    local defaultRows = {}
    local defaultRowFor = {}

    for key, defaultValue in pairs(defaults) do
        if type(key) ~= "number" then
            valid[key] = true
            result[key] = MergeKnown(defaultValue, type(stored) == "table" and stored[key] or nil,
                JoinPath(path, key))
        end
    end

    for rowIndex, defaultRow in ipairs(defaults) do
        defaultRows[rowIndex] = DeepCopy(defaultRow)
        for _, elementKey in ipairs(defaultRow) do
            if valid[elementKey] and defaultRowFor[elementKey] == nil then
                defaultRowFor[elementKey] = rowIndex
            end
        end
    end

    local rows = {}
    local seenElement = {}
    if type(stored) == "table" then
        local rowIndexes = {}
        for key, row in pairs(stored) do
            if type(key) == "number" and key >= 1 and key % 1 == 0 and type(row) == "table" then
                rowIndexes[#rowIndexes + 1] = key
            end
        end
        table.sort(rowIndexes)

        for _, rowIndex in ipairs(rowIndexes) do
            local cleanRow = {}
            for _, elementKey in ipairs(stored[rowIndex]) do
                if type(elementKey) == "string" and valid[elementKey] and not seenElement[elementKey] then
                    cleanRow[#cleanRow + 1] = elementKey
                    seenElement[elementKey] = true
                end
            end
            if #cleanRow > 0 then rows[#rows + 1] = cleanRow end
        end
    end

    if #rows == 0 then
        rows = defaultRows
        for _, row in ipairs(rows) do
            for _, elementKey in ipairs(row) do seenElement[elementKey] = true end
        end
    else
        for rowIndex = 1, #defaultRows do rows[rowIndex] = rows[rowIndex] or {} end
        -- Add schema elements in deterministic default-row order. Existing
        -- user ordering remains untouched.
        for rowIndex, defaultRow in ipairs(defaultRows) do
            for _, elementKey in ipairs(defaultRow) do
                if valid[elementKey] and not seenElement[elementKey] then
                    rows[rowIndex][#rows[rowIndex] + 1] = elementKey
                    seenElement[elementKey] = true
                end
            end
        end
    end

    for index, row in ipairs(rows) do
        if #row > 0 then result[#result + 1] = row end
    end
    return result
end

MergeKnown = function(defaultValue, storedValue, path)
    if type(defaultValue) ~= "table" then
        return CompatibleScalar(defaultValue, storedValue)
    end

    if OPAQUE_PATHS[path] then
        if type(storedValue) == "table" then return DeepCopy(storedValue) end
        return DeepCopy(defaultValue)
    end

    if IsElementsPath(path) then
        return MergeElements(defaultValue, storedValue, path)
    end

    local stored = type(storedValue) == "table" and storedValue or nil
    local result = {}
    for key, childDefault in pairs(defaultValue) do
        result[key] = MergeKnown(childDefault, stored and stored[key] or nil, JoinPath(path, key))
    end
    return result
end

function addon:DeepCopy(value)
    return DeepCopy(value)
end

function addon:NormalizeNumericKeys(value)
    return NormalizeNumericKeys(value)
end

function addon:BuildProfile(stored, base)
    base = type(base) == "table" and base or self.__RT_DefaultDB or self.db or {}
    stored = type(stored) == "table" and DeepCopy(stored) or {}
    NormalizeNumericKeys(stored)
    return MergeKnown(base, stored, "")
end

function addon:GetDefaultProfile()
    return DeepCopy(self.__RT_DefaultDB or self.db or {})
end

-- Config.lua has already established the complete schema when this file loads.
addon.__RT_DefaultDB = DeepCopy(addon.db or {})
