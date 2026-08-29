-- RothTooltip patch-stable shared helpers.
--
-- Core owns formatting, media lookup, color functions, and element filters.
-- Tooltip data, frame registry, style, anchoring, status bar, profiles, and
-- module lifecycle have dedicated owners and must not be reintroduced here.

local _, addon = ...
local LibMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)

local MALE = MALE
local FEMALE = FEMALE

function addon:NormalizeFontFlag(flag, defaultFlag)
    if flag == "default" then flag = defaultFlag end
    if flag == nil then return "" end
    if type(flag) ~= "string" then return "" end
    flag = string.upper(flag)
    if flag == "NORMAL" or flag == "NONE" then return "" end
    return flag
end

addon.L = addon.L or {}
addon.G = addon.G or {}
setmetatable(addon.L, { __index = function(_, key) return key end })
setmetatable(addon.G, { __index = function(_, key) return _G[key] or key end })

addon.icons = {
    Alliance   = "|TInterface\\TargetingFrame\\UI-PVP-ALLIANCE:14:14:0:0:64:64:10:36:2:38|t",
    Horde      = "|TInterface\\TargetingFrame\\UI-PVP-HORDE:14:14:0:0:64:64:4:38:2:36|t",
    Neutral    = "|TInterface\\Timer\\Panda-Logo:14|t",
    pvp        = "|TInterface\\TargetingFrame\\UI-PVP-FFA:14:14:0:0:64:64:10:36:0:38|t",
    class      = "|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:0:256:256:%d:%d:%d:%d|t",
    battlepet  = "|TInterface\\Timer\\Panda-Logo:15|t",
    pettype    = "|TInterface\\TargetingFrame\\PetBadge-%s:14|t",
    questboss  = "|TInterface\\TargetingFrame\\PortraitQuestBadge:0|t",
    friend     = "|TInterface\\AddOns\\RothTooltip\\texture\\friend:14:14:0:0:32:32:1:30:2:30|t",
    bnetfriend = "|TInterface\\ChatFrame\\UI-ChatIcon-BattleNet:14:14:0:0:32:32:1:30:2:30|t",
    TANK       = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t",
    HEALER     = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t",
    DAMAGER    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t",
}

addon.bgs = {
    gradual = "Interface\\Buttons\\GreyscaleRamp64",
    dark = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    alpha = "Interface\\Tooltips\\UI-Tooltip-Background",
    rock = "Interface\\FrameGeneral\\UI-Background-Rock",
    marble = "Interface\\FrameGeneral\\UI-Background-Marble",
    RothTooltipDarkTexture = "Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkTexture",
}

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[DeepCopy(key, seen)] = DeepCopy(child, seen) end
    return result
end

-- Compatibility entrypoints retained for old profile/import callers. Their
-- implementation is detached and delegates to Engine/Schema once available.
function addon:FixNumericKey(value)
    if type(self.NormalizeNumericKeys) == "function" then
        return self:NormalizeNumericKeys(value)
    end
    return value
end

function addon:MergeVariable(defaults, stored)
    if type(self.BuildProfile) == "function" then
        return self:BuildProfile(stored, defaults)
    end
    if type(defaults) ~= "table" then return DeepCopy(stored) end
    local result = DeepCopy(defaults)
    if type(stored) ~= "table" then return result end
    for key, value in pairs(stored) do
        if result[key] ~= nil and type(result[key]) == type(value) then
            result[key] = type(value) == "table" and self:MergeVariable(result[key], value) or value
        end
    end
    return result
end

local function ClampByte(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    return math.floor(value * 255 + 0.5)
end

function addon:GetHexColor(color, green, blue)
    local red
    if green ~= nil and blue ~= nil then
        red = color
    elseif type(color) == "table" then
        red = color.r or color[1]
        green = color.g or color[2]
        blue = color.b or color[3]
    end
    if red == nil or green == nil or blue == nil then return "ffffff" end
    return string.format("%02x%02x%02x", ClampByte(red), ClampByte(green), ClampByte(blue))
end

function addon:GetRGBColor(hex)
    if type(hex) ~= "string" then return 1, 1, 1 end
    hex = hex:gsub("^#", "")
    if hex:match("^%x%x%x%x%x%x%x%x$") then hex = hex:sub(3, 8) end
    if not hex:match("^%x%x%x%x%x%x$") then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end

function addon:GetFont(font, defaultFont)
    if font == "default" then
        font = defaultFont
    elseif type(font) == "string" and _G[font] then
        local resolved = self:SafeMethod(_G[font], "GetFont")
        if type(resolved) == "string" then font = resolved end
    elseif type(font) == "string" and LibMedia and LibMedia:IsValid("font", font) then
        local ok, resolved = pcall(LibMedia.Fetch, LibMedia, "font", font)
        if ok and type(resolved) == "string" then font = resolved end
    end
    return type(font) == "string" and font or defaultFont
end

function addon:GetBgFile(value)
    if type(value) ~= "string" then return nil end
    if self.bgs[value] then return self.bgs[value] end
    if LibMedia and LibMedia:IsValid("background", value) then
        local ok, resolved = pcall(LibMedia.Fetch, LibMedia, "background", value)
        if ok and type(resolved) == "string" then return resolved end
    end
end

function addon:GetBarFile(value)
    if type(value) ~= "string" then return value end
    if LibMedia and LibMedia:IsValid("statusbar", value) then
        local ok, resolved = pcall(LibMedia.Fetch, LibMedia, "statusbar", value)
        if ok and type(resolved) == "string" then return resolved end
    end
    return value
end

function addon:GetGender(gender)
    if gender == 2 then return MALE, "male" end
    if gender == 3 then return FEMALE, "female" end
end

function addon:GetNpcTitle(tooltip)
    local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UnitLevel
    local _, _, levelIndex = type(lineType) == "number" and self:GetRenderedLine(tooltip, lineType) or nil
    if type(levelIndex) ~= "number" or levelIndex <= 2 then return nil end
    return self:GetLine(tooltip, 2)
end

function addon:CheckFilter(config, raw)
    if IsAltKeyDown() or IsControlKeyDown() then return true end
    if type(config) ~= "table" or config.enable ~= true then return false end

    local filter = config.filter
    if filter == nil or filter == "" or filter == "none" then return true end
    if type(filter) ~= "string" then return false end

    local key = filter:match("^[^:]+") or filter
    local negated
    key, negated = key:gsub("^not%s+", "")
    local fn = self.filterfunc and self.filterfunc[key]
    if type(fn) ~= "function" then return true end

    local argument = select(2, strsplit(":", filter))
    local ok, result = pcall(fn, raw, argument)
    if not ok or not self:CanAccessValue(result) then return false end
    result = result and true or false
    return negated > 0 and not result or result
end

function addon:FormatData(value, config, raw)
    if not self:CanAccessValue(value) then return "" end
    if type(config) ~= "table" then return self:SafeToString(value, "") end

    local wildcard = type(config.wildcard) == "string" and config.wildcard or "%s"
    local color = config.color
    local colorFunction = self.colorfunc and self.colorfunc[color]
    if type(colorFunction) == "function" then
        local ok, _, _, _, hex = pcall(colorFunction, raw)
        if ok and type(hex) == "string" then color = hex end
    end

    -- Preserve the original primitive type for %d/%f templates. The legacy
    -- implementation converted every value to string before string.format,
    -- making numeric wildcards fail on every locale.
    local ok, formatted = pcall(string.format, wildcard, value)
    if not ok or type(formatted) ~= "string" then formatted = self:SafeToString(value, "") end

    if color == nil or color == "" or color == "default" or color == "none" then return formatted end
    if type(color) == "table" then color = self:GetHexColor(color) end
    if type(color) ~= "string" then return formatted end
    return "|cff" .. color .. formatted .. "|r"
end

function addon:GetUnitData(unit, elements, raw)
    if type(elements) ~= "table" then return {} end
    if type(raw) ~= "table" then raw = self:GetUnitInfo(unit, elements) end
    if type(raw) ~= "table" then return {} end

    local data = {}
    for rowIndex, row in ipairs(elements) do
        data[rowIndex] = {}
        local namePosition
        local titlePosition
        if type(row) == "table" then
            for _, elementKey in ipairs(row) do
                local config = elements[elementKey]
                local value = raw[elementKey]
                if type(config) == "table" and value ~= nil and self:CheckFilter(config, raw) then
                    if elementKey == "name" then namePosition = #data[rowIndex] + 1 end
                    if elementKey == "title" then titlePosition = #data[rowIndex] + 1 end
                    local formatted = config.color and config.wildcard
                        and self:FormatData(value, config, raw)
                        or self:SafeToString(value, "")
                    if elementKey == "title" and namePosition == #data[rowIndex] and raw.titleIsPrefix then
                        table.insert(data[rowIndex], namePosition, formatted)
                    elseif elementKey == "name" and titlePosition == #data[rowIndex] and not raw.titleIsPrefix then
                        table.insert(data[rowIndex], titlePosition, formatted)
                    else
                        table.insert(data[rowIndex], formatted)
                    end
                end
            end
        end
    end
    for index = #data, 1, -1 do
        if data[index][1] == nil then table.remove(data, index) end
    end
    return data
end

addon.filterfunc = addon.filterfunc or {}
addon.colorfunc = addon.colorfunc or {}

local function WhiteColor()
    return 1, 1, 1, "ffffff"
end

addon.colorfunc.class = function(raw)
    if type(raw) ~= "table" or type(raw.class) ~= "string" then return WhiteColor() end
    local color = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[raw.class]
    if color then return color.r, color.g, color.b, addon:GetHexColor(color) end
    local red, green, blue = addon:SafeCall("GetClassColor", GetClassColor, raw.class)
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then return WhiteColor() end
    return red, green, blue, addon:GetHexColor(red, green, blue)
end

addon.colorfunc.level = function(raw)
    local level = type(raw) == "table" and raw.effectiveLevel or nil
    if type(level) ~= "number" or level <= 0 then level = 999 end
    local color = addon:SafeCall("GetCreatureDifficultyColor", GetCreatureDifficultyColor, level)
    local red = type(color) == "table" and addon:SafeGet(color, "r") or nil
    local green = type(color) == "table" and addon:SafeGet(color, "g") or nil
    local blue = type(color) == "table" and addon:SafeGet(color, "b") or nil
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then return WhiteColor() end
    return red, green, blue, addon:GetHexColor(red, green, blue)
end

addon.colorfunc.reaction = function(raw)
    local reaction = type(raw) == "table" and raw.reaction or nil
    local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction or 4]
    if type(color) ~= "table" then return WhiteColor() end
    return color.r, color.g, color.b, addon:GetHexColor(color)
end

addon.colorfunc.itemQuality = function(raw)
    local quality = type(raw) == "table" and raw.itemQuality or nil
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 0]
    if type(color) ~= "table" then return WhiteColor() end
    return color.r, color.g, color.b, addon:GetHexColor(color)
end

addon.colorfunc.selection = function(raw)
    local unit = type(raw) == "table" and raw.unit or nil
    if type(unit) ~= "string" or addon:IsUnitIdentityRestricted(unit) then return WhiteColor() end
    local red, green, blue = addon:SafeCall("UnitSelectionColor", UnitSelectionColor, unit)
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then return WhiteColor() end
    return red, green, blue, addon:GetHexColor(red, green, blue)
end

addon.colorfunc.faction = function(raw)
    local faction = type(raw) == "table" and raw.factionGroup or nil
    if faction == "Neutral" then return 0.9, 0.7, 0, "e5b200" end
    local playerFaction = addon:SafeCall("UnitFactionGroup", UnitFactionGroup, "player")
    if type(faction) == "string" and faction == playerFaction then return 0, 1, 0.2, "00cc33" end
    return 1, 0.2, 0, "dd3300"
end

addon.filterfunc.reaction6 = function(raw)
    return (type(raw) == "table" and raw.reaction or 4) >= 6
end
addon.filterfunc.reaction5 = function(raw)
    return (type(raw) == "table" and raw.reaction or 4) >= 5
end
addon.filterfunc.reaction = function(raw, reaction)
    return (type(raw) == "table" and raw.reaction or 4) >= (tonumber(reaction) or 5)
end
addon.filterfunc.inraid = function()
    return addon:SafeCallBoolean(IsInRaid) == true
end
addon.filterfunc.incombat = function()
    return InCombatLockdown() == true
end
addon.filterfunc.samerealm = function(raw)
    return type(raw) == "table" and type(raw.realm) == "string" and raw.realm == GetRealmName()
end
addon.filterfunc.samecrossrealm = function(raw)
    local unit = type(raw) == "table" and raw.unit or nil
    if type(unit) ~= "string" or addon:IsUnitIdentityRestricted(unit) then return false end
    local relationship = addon:SafeCall("UnitRealmRelationship", UnitRealmRelationship, unit)
    return type(relationship) == "number" and relationship ~= LE_REALM_RELATION_COALESCED
end
addon.filterfunc.inpvp = function()
    local _, instanceType = addon:SafeCall("IsInInstance", IsInInstance)
    return instanceType == "pvp"
end
addon.filterfunc.inarena = function()
    local _, instanceType = addon:SafeCall("IsInInstance", IsInInstance)
    return instanceType == "arena"
end
addon.filterfunc.ininstance = function()
    return addon:SafeCallBoolean(IsInInstance) == true
end
addon.filterfunc.sameguild = function(raw)
    if type(raw) ~= "table" then return false end
    local name, _, _, realm = addon:SafeCall("GetGuildInfo", GetGuildInfo, "player")
    return type(name) == "string" and name == raw.guildName and realm == raw.guildRealm
end
