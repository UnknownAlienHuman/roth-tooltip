-- RothTooltip shared core
--
-- This file contains patch-stable formatting, configuration merge, media,
-- color/filter, and visual trigger glue. Retail 12.1 tooltip data handling is
-- owned exclusively by Engine/Midnight.lua and Engine/TooltipProcessor.lua.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
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

local function AutoValidateElements(source, destination)
    local known = {}
    for rowIndex, row in ipairs(destination) do
        known[rowIndex] = true
        if type(row) == "table" then
            for index = #row, 1, -1 do
                local key = row[index]
                if source[key] == nil then
                    table.remove(row, index)
                else
                    known[key] = true
                end
            end
        end
    end

    for key, value in pairs(source) do
        if type(key) ~= "number" and destination[key] == nil then
            destination[key] = value
            if key ~= "factionBig" and key ~= "npcTitle" and not known[key]
                and type(destination[1]) == "table" then
                table.insert(destination[1], 1, key)
            end
        end
    end
    return destination
end

function addon:FixNumericKey(tbl, seen)
    if type(tbl) ~= "table" then return tbl end
    seen = seen or {}
    if seen[tbl] then return tbl end
    seen[tbl] = true

    local converted = {}
    for key, value in pairs(tbl) do
        if type(key) == "string" and string.match(key, "^[1-9]%d*$") then
            tbl[key] = nil
            converted[tonumber(key)] = value
        end
    end
    for key, value in pairs(converted) do
        if tbl[key] == nil then tbl[key] = value end
    end
    for key, value in pairs(tbl) do
        if type(value) == "table" then
            tbl[key] = self:FixNumericKey(value, seen)
        end
    end
    return tbl
end

function addon:MergeVariable(source, destination)
    if type(source) ~= "table" then return destination end
    if type(destination) ~= "table" then destination = {} end

    destination.version = source.version
    for key, value in pairs(source) do
        if destination[key] == nil then
            destination[key] = value
        elseif type(value) == "table" and type(destination[key]) == "table" then
            if key == "elements" then
                destination[key] = AutoValidateElements(value, destination[key])
            else
                self:MergeVariable(value, destination[key])
            end
        end
    end
    return destination
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
    hex = string.gsub(hex, "^#", "")
    if string.match(hex, "^%x%x%x%x%x%x%x%x$") then
        hex = string.sub(hex, 3, 8)
    end
    if not string.match(hex, "^%x%x%x%x%x%x$") then return 1, 1, 1 end

    local red = tonumber(string.sub(hex, 1, 2), 16) or 255
    local green = tonumber(string.sub(hex, 3, 4), 16) or 255
    local blue = tonumber(string.sub(hex, 5, 6), 16) or 255
    return red / 255, green / 255, blue / 255
end

function addon:GetFont(font, defaultFont)
    if font == "default" then
        font = defaultFont
    elseif type(font) == "string" and _G[font] then
        local object = _G[font]
        local getFont = self:SafeGet(object, "GetFont")
        if type(getFont) == "function" then
            local resolved = self:SafeCall("GetFont", getFont, object)
            if type(resolved) == "string" then font = resolved end
        end
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
    return nil
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
    return nil
end

function addon:GetNpcTitle(tooltip)
    local line, index = self:FindLine(tooltip, "^" .. LEVEL)
    if not line or type(index) ~= "number" or index <= 2 then return nil end
    return self:GetLine(tooltip, 2)
end

function addon:CheckFilter(config, raw)
    if IsAltKeyDown() or IsControlKeyDown() then return true end
    if type(config) ~= "table" or config.enable ~= true then return false end

    local filter = config.filter
    if filter == nil or filter == "" or filter == "none" then return true end
    if type(filter) ~= "string" then return false end

    local key = string.match(filter, "^[^:]+") or filter
    local negated
    key, negated = string.gsub(key, "^not%s+", "")
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

    local text = self:SafeToString(value, "")
    local ok, formatted = pcall(string.format, wildcard, text)
    if not ok or type(formatted) ~= "string" then formatted = text end

    if color == nil or color == "" or color == "default" or color == "none" then
        return formatted
    end
    if type(color) == "table" then color = self:GetHexColor(color) end
    if type(color) ~= "string" then return formatted end
    return "|cff" .. color .. formatted .. "|r"
end

function addon:GetUnitData(unit, elements, raw)
    if type(elements) ~= "table" then return {} end
    if type(raw) ~= "table" then raw = self:GetUnitInfo(unit) end
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
    if color then
        return color.r, color.g, color.b, addon:GetHexColor(color)
    end

    local red, green, blue = addon:SafeCall("GetClassColor", GetClassColor, raw.class)
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
        return WhiteColor()
    end
    return red, green, blue, addon:GetHexColor(red, green, blue)
end

addon.colorfunc.level = function(raw)
    local level = type(raw) == "table" and raw.effectiveLevel or nil
    if type(level) ~= "number" or level <= 0 then level = 999 end
    local color = addon:SafeCall("GetCreatureDifficultyColor", GetCreatureDifficultyColor, level)
    if type(color) ~= "table" then return WhiteColor() end
    return color.r, color.g, color.b, addon:GetHexColor(color)
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
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
        return WhiteColor()
    end
    return red, green, blue, addon:GetHexColor(red, green, blue)
end

addon.colorfunc.faction = function(raw)
    local faction = type(raw) == "table" and raw.factionGroup or nil
    if faction == "Neutral" then return 0.9, 0.7, 0, "e5b200" end

    local playerFaction = addon:SafeCall("UnitFactionGroup", UnitFactionGroup, "player")
    if type(faction) == "string" and faction == playerFaction then
        return 0, 1, 0.2, "00cc33"
    end
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

local function SafeTooltipStyle(tooltip)
    if type(addon.GetTooltipStyle) ~= "function" then return nil end
    return addon:GetTooltipStyle(tooltip)
end

LibEvent:attachTrigger("tooltip.scale", function(_, frame, scale)
    if addon:IsTooltipSafe(frame) and type(scale) == "number" then
        addon:SafeMethod(frame, "SetScale", scale)
    end
end)

LibEvent:attachTrigger("tooltip.anchor.cursor", function(_, frame, parent)
    if addon:IsTooltipSafe(frame) and addon:IsObjectAccessible(parent) then
        addon:SafeMethod(frame, "SetOwner", parent, "ANCHOR_CURSOR")
    end
end)

LibEvent:attachTrigger("tooltip.anchor.cursor.right", function(_, frame, parent, offsetX, offsetY)
    if addon:IsTooltipSafe(frame) and addon:IsObjectAccessible(parent) then
        addon:SafeMethod(
            frame,
            "SetOwner",
            parent,
            "ANCHOR_CURSOR_RIGHT",
            tonumber(offsetX) or 36,
            tonumber(offsetY) or -12
        )
    end
end)

LibEvent:attachTrigger("tooltip.anchor.static", function(_, frame, parent, offsetX, offsetY, anchorPoint)
    if not addon:IsTooltipSafe(frame) then return end
    local _, relativeTo = addon:SafeMethod(frame, "GetPoint")
    if relativeTo ~= UIParent and relativeTo ~= GameTooltipDefaultContainer then return end

    anchorPoint = type(anchorPoint) == "string" and anchorPoint or "BOTTOMRIGHT"
    addon:SafeMethod(frame, "ClearAllPoints")
    addon:SafeMethod(
        frame,
        "SetPoint",
        anchorPoint,
        UIParent,
        anchorPoint,
        tonumber(offsetX) or (-CONTAINER_OFFSET_X - 13),
        tonumber(offsetY) or CONTAINER_OFFSET_Y
    )
end)

LibEvent:attachTrigger("tooltip.anchor.none", function(_, frame, parent)
    if not addon:IsTooltipSafe(frame) or not addon:IsObjectAccessible(parent) then return end
    addon:SafeMethod(frame, "SetOwner", parent, "ANCHOR_NONE")
    addon:SafeMethod(frame, "Hide")
end)

LibEvent:attachTrigger("tooltip.statusbar.height", function(_, height)
    if addon:IsObjectAccessible(GameTooltipStatusBar) then
        addon:SafeMethod(GameTooltipStatusBar, "SetHeight", tonumber(height) or 12)
    end
end)

LibEvent:attachTrigger("tooltip.statusbar.text", function(_, enabled)
    addon.__RT_StatusBarTextEnabled = enabled == true
end)

LibEvent:attachTrigger("tooltip.statusbar.font", function(_, font, size, flag)
    local getText = addon.GetStatusBarText
    local text = type(getText) == "function" and addon:GetStatusBarText(GameTooltipStatusBar) or nil
    if not addon:IsObjectAccessible(text) then return end

    local originalFont, originalSize, originalFlag = addon:SafeMethod(text, "GetFont")
    local defaultFont = addon:IsObjectAccessible(NumberFontNormal)
        and addon:SafeMethod(NumberFontNormal, "GetFont") or originalFont
    font = addon:GetFont(font, defaultFont)
    if flag == "default" then flag = "THINOUTLINE" end
    flag = addon:NormalizeFontFlag(flag, "THINOUTLINE")
    size = tonumber(size) or originalSize

    if type(font) == "string" and type(size) == "number" then
        addon:SafeMethod(text, "SetFont", font, size, flag or originalFlag)
    end
end)

LibEvent:attachTrigger("tooltip.statusbar.texture", function(_, value)
    if addon:IsObjectAccessible(GameTooltipStatusBar) then
        addon:SafeMethod(GameTooltipStatusBar, "SetStatusBarTexture", addon:GetBarFile(value))
    end
end)

LibEvent:attachTrigger("tooltip.statusbar.position", function(_, position, offsetX, offsetY)
    if not addon:IsTooltipSafe(GameTooltip) or not addon:IsObjectAccessible(GameTooltipStatusBar) then return end
    LibEvent:trigger("tooltip.style.init", GameTooltip)

    local style = SafeTooltipStyle(GameTooltip)
    if not style then return end

    addon:SafeMethod(style, "ClearAllPoints")
    addon:SafeMethod(GameTooltipStatusBar, "ClearAllPoints")
    local backdrop = addon:SafeMethod(style, "GetBackdrop")
    if type(backdrop) ~= "table" then return end

    if addon:SafeMethod(GameTooltipStatusBar, "IsShown") ~= true then position = "" end
    offsetX = tonumber(offsetX)
    offsetY = tonumber(offsetY)

    if position == "bottom" then
        local offset = backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border"
            and 5 or (tonumber(backdrop.edgeSize) or 1) + 1
        offsetX = offsetX and offsetX ~= 0 and offsetX or offset
        offsetY = offsetY and offsetY ~= 0 and offsetY or -offset
        addon:SafeMethod(GameTooltipStatusBar, "SetPoint", "TOPLEFT", GameTooltip, "BOTTOMLEFT", offsetX, 2)
        addon:SafeMethod(GameTooltipStatusBar, "SetPoint", "TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -offsetX, 2)
        addon:SafeMethod(style, "SetPoint", "TOPLEFT")
        addon:SafeMethod(style, "SetPoint", "BOTTOMRIGHT", GameTooltipStatusBar, "BOTTOMRIGHT", offsetX, offsetY)
    elseif position == "top" then
        local offset = backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border"
            and 4 or tonumber(backdrop.edgeSize) or 1
        offsetX = offsetX and offsetX ~= 0 and offsetX or offset
        offsetY = offsetY and offsetY ~= 0 and offsetY or offset
        addon:SafeMethod(GameTooltipStatusBar, "SetPoint", "BOTTOMLEFT", GameTooltip, "TOPLEFT", offsetX, -4)
        addon:SafeMethod(GameTooltipStatusBar, "SetPoint", "BOTTOMRIGHT", GameTooltip, "TOPRIGHT", -offsetX, -4)
        addon:SafeMethod(style, "SetPoint", "TOPLEFT", GameTooltipStatusBar, "TOPLEFT", -offsetX, offsetY)
        addon:SafeMethod(style, "SetPoint", "BOTTOMRIGHT")
    else
        local offset = backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border" and 2 or 0
        addon:SafeMethod(GameTooltipStatusBar, "SetPoint", "TOPLEFT", GameTooltip, "BOTTOMLEFT", offset, -1)
        addon:SafeMethod(GameTooltipStatusBar, "SetPoint", "TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -offset, -1)
        addon:SafeMethod(style, "SetAllPoints")
    end
end)

local function HookBackdropFunction(functionName)
    if type(hooksecurefunc) ~= "function" or type(_G[functionName]) ~= "function" then return end
    hooksecurefunc(functionName, function(tooltip)
        if addon:IsManagedTooltip(tooltip) then
            addon:ApplyGeneralStyleToTooltip(tooltip)
        end
    end)
end

HookBackdropFunction("SharedTooltip_SetBackdropStyle")
HookBackdropFunction("GameTooltip_SetBackdropStyle")

LibEvent:attachTrigger("ROTHTOOLTIP_GENERAL_INIT", function()
    local general = addon.db and addon.db.general
    if type(general) ~= "table" then return end

    LibEvent:trigger("tooltip.style.font.header", GameTooltip, general.headerFont, general.headerFontSize, general.headerFontFlag)
    LibEvent:trigger("tooltip.style.font.body", GameTooltip, general.bodyFont, general.bodyFontSize, general.bodyFontFlag)
    LibEvent:trigger("tooltip.statusbar.height", general.statusbarHeight)
    LibEvent:trigger("tooltip.statusbar.text", general.statusbarText)
    LibEvent:trigger("tooltip.statusbar.font", general.statusbarFont, general.statusbarFontSize, general.statusbarFontFlag)
    LibEvent:trigger("tooltip.statusbar.texture", general.statusbarTexture)

    for _, tooltip in pairs(addon.tooltips or {}) do
        if addon:IsTooltipSafe(tooltip) then
            LibEvent:trigger("tooltip.style.init", tooltip)
            LibEvent:trigger("tooltip.scale", tooltip, general.scale)
            LibEvent:trigger("tooltip.style.mask", tooltip, general.mask)
            LibEvent:trigger("tooltip.style.bgfile", tooltip, general.bgfile)
            LibEvent:trigger("tooltip.style.border.corner", tooltip, general.borderCorner)
            LibEvent:trigger("tooltip.style.border.size", tooltip, general.borderSize)
            LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(general.borderColor))
            LibEvent:trigger("tooltip.style.background", tooltip, unpack(general.background))
        end
    end
end)

LibEvent:attachTrigger("tooltip:show", function(_, tooltip)
    addon:ApplyGeneralStyleToTooltip(tooltip)
end)

if type(hooksecurefunc) == "function" and type(GameTooltip_SetDefaultAnchor) == "function" then
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        LibEvent:trigger("tooltip:anchor", tooltip, parent)
    end)
end
