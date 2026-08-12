local addonName, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
local CopyTable = CopyTable

addon.L = addon.L or {}
setmetatable(addon.L, {
    __index = function(self, k)
        local s = { strsplit(".", k) }
        return rawget(self, s[#s]) or (s[#s]:gsub("([a-z])([A-Z])", "%1 %2"):gsub("^(%a)", strupper))
    end
})
local L = addon.L

local COLOR_MODE_CUSTOM = "__CUSTOM__"
local EMPTY_TABLE = {}

local VISIBILITY_OPTIONS = { "show", "hide" }
local COMBAT_VISIBILITY_OPTIONS = { "show", "hide", "unitOnly" }
local GENERAL_ANCHOR_OPTIONS = { "default", "cursorRight", "cursor", "auto", "static" }
local UNIT_ANCHOR_OPTIONS = { "inherit", "default", "cursorRight", "cursor", "static" }
local STATIC_ANCHOR_POINTS = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "TOP", "BOTTOM" }
local CURSOR_ANCHOR_POINTS = { "BOTTOM", "TOP", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local COLOR_FILTER_OPTIONS = {
    "none",
    "ininstance",
    "incombat",
    "inraid",
    "samerealm",
    "samecrossrealm",
    "inpvp",
    "inarena",
    "reaction5",
    "reaction6",
    "not ininstance",
    "not incombat",
    "not inraid",
    "not samerealm",
    "not samecrossrealm",
    "not inpvp",
    "not inarena",
    "not reaction5",
    "not reaction6",
}
local ELEMENT_COLOR_OPTIONS = { "default", "class", "level", "reaction", "itemQuality", "selection", "faction", COLOR_MODE_CUSTOM }
local FONT_FLAG_OPTIONS = { "default", "NORMAL", "OUTLINE", "THINOUTLINE" }
local STATUSBAR_TEXT_FORMAT_OPTIONS = { "health/max", "percent", "health (percent)", "none" }
local COLOR_FUNC_OPTIONS = { "default", "class", "level", "reaction", "itemQuality", "selection", "faction" }

local PLAYER_ELEMENT_OPTIONS = {
    { key = "unit.player.elements.factionBig" },
    { key = "unit.player.elements.raidIcon", filter = true },
    { key = "unit.player.elements.roleIcon", filter = true },
    { key = "unit.player.elements.pvpIcon", filter = true },
    { key = "unit.player.elements.factionIcon", filter = true },
    { key = "unit.player.elements.classIcon", filter = true },
    { key = "unit.player.elements.friendIcon", filter = true },
    { key = "unit.player.elements.title", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.name", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.realm", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.statusAFK", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.statusDND", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.statusDC", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.guildName", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.guildIndex", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.guildRank", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.guildRealm", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.levelValue", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.factionName", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.gender", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.raceName", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.className", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.isPlayer", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.role", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.moveSpeed", color = true, wildcard = true, filter = true },
    { key = "unit.player.elements.zone", color = true, wildcard = true, filter = true },
}

local NPC_ELEMENT_OPTIONS = {
    { key = "unit.npc.elements.factionBig" },
    { key = "unit.npc.elements.raidIcon", filter = true },
    { key = "unit.npc.elements.classIcon", filter = true },
    { key = "unit.npc.elements.questIcon", filter = true },
    { key = "unit.npc.elements.npcTitle", color = true, wildcard = true },
    { key = "unit.npc.elements.name", color = true, wildcard = true, filter = true },
    { key = "unit.npc.elements.levelValue", color = true, wildcard = true, filter = true },
    { key = "unit.npc.elements.classifBoss", color = true, wildcard = true, filter = true },
    { key = "unit.npc.elements.classifElite", color = true, wildcard = true, filter = true },
    { key = "unit.npc.elements.classifRare", color = true, wildcard = true, filter = true },
    { key = "unit.npc.elements.creature", color = true, wildcard = true, filter = true },
    { key = "unit.npc.elements.reactionName", color = true, wildcard = true, filter = true },
    { key = "unit.npc.elements.moveSpeed", color = true, wildcard = true, filter = true },
}

local categoryRefs = {}
local mediaValues = {
    background = {},
    border = {},
    font = {},
    statusbar = {},
}

local function NormalizeHexColor(value)
    if type(value) ~= "string" then
        return nil
    end

    value = value:gsub("^#", "")
    if value:match("^%x%x%x%x%x%x%x%x$") or value:match("^%x%x%x%x%x%x$") then
        return strupper(value)
    end

    return nil
end

local function IsHexColor(value)
    return NormalizeHexColor(value) ~= nil
end

local function ClampColorComponent(value, fallback)
    value = tonumber(value)
    if value == nil then
        return fallback
    end
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

local function BuildSettingsColorHex(r, g, b, a)
    return ("%02X%02X%02X%02X"):format(
        floor(ClampColorComponent(a, 1) * 255 + 0.5),
        floor(ClampColorComponent(r, 1) * 255 + 0.5),
        floor(ClampColorComponent(g, 1) * 255 + 0.5),
        floor(ClampColorComponent(b, 1) * 255 + 0.5)
    )
end

local function GetHexColorAlpha(value)
    local normalized = NormalizeHexColor(value)
    if normalized and #normalized == 8 then
        return (tonumber(normalized:sub(1, 2), 16) or 255) / 255
    end
    return 1
end

local function GetHexColorNoAlpha(value)
    local normalized = NormalizeHexColor(value)
    if not normalized then
        return nil
    end
    if #normalized == 8 then
        return normalized:sub(3, 8)
    end
    return normalized
end

local function GetSettingsColorHexFromValue(value)
    if type(value) == "table" then
        return BuildSettingsColorHex(
            value[1] or value.r,
            value[2] or value.g,
            value[3] or value.b,
            value[4] or value.a or 1
        )
    end

    local normalized = NormalizeHexColor(value)
    if normalized then
        if #normalized == 6 then
            return "FF" .. normalized
        end
        return normalized
    end

    return "FFFFFFFF"
end

local function GetStoredColorAlpha(value)
    if type(value) == "table" then
        return ClampColorComponent(value[4] or value.a, 1)
    end
    return GetHexColorAlpha(value)
end

local function HumanizeText(value)
    if type(value) == "number" then
        return tostring(value)
    end
    if value == COLOR_MODE_CUSTOM then
        return CUSTOM or "Custom"
    end
    value = tostring(value or "")
    if value == "" then
        return ""
    end
    return value:gsub("([a-z])([A-Z])", "%1 %2"):gsub("^(%a)", strupper)
end

local function GetDropdownOptionText(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return tostring(value)
    end
    if value == COLOR_MODE_CUSTOM then
        return CUSTOM or "Custom"
    end
    return L["dropdown." .. tostring(value)] or HumanizeText(value)
end

local function MakeSettingName(keystring, suffix)
    local name = "ROTH_TOOLTIP_" .. tostring(keystring or "UNKNOWN"):gsub("[^%w]+", "_"):upper()
    if suffix and suffix ~= "" then
        name = name .. "_" .. tostring(suffix):gsub("[^%w]+", "_"):upper()
    end
    return name
end

local function SetNestedValue(target, keystring, value)
    local keys = { strsplit(".", keystring) }
    local scope = target
    for index = 1, #keys - 1 do
        local key = keys[index]
        if type(scope[key]) ~= "table" then
            scope[key] = {}
        end
        scope = scope[key]
    end
    scope[keys[#keys]] = value
end

local function GetVariable(keystring, tbl)
    if keystring == "general.SavedVariablesPerCharacter" then
        return RothTooltipDB and RothTooltipDB.general and RothTooltipDB.general.SavedVariablesPerCharacter
    end

    local keys = { strsplit(".", keystring) }
    local value = tbl or addon.db
    for _, key in ipairs(keys) do
        if type(value) ~= "table" or value[key] == nil then
            return nil
        end
        value = value[key]
    end
    return value
end

local function TriggerManagedTooltips(eventName, ...)
    for _, tip in ipairs(addon.tooltips or EMPTY_TABLE) do
        if tip then
            LibEvent:trigger(eventName, tip, ...)
        end
    end
end

local function RefreshShownTooltips(reason)
    if not addon.RefreshTooltipSafe then
        return
    end

    for _, tip in ipairs(addon.tooltips or EMPTY_TABLE) do
        if tip and tip.IsShown and tip:IsShown() then
            addon:RefreshTooltipSafe(tip, reason)
        end
    end
end

local function CallTrigger(keystring, value)
    local general = addon.db and addon.db.general
    if not general then
        return
    end

    if keystring == "general.mask" then
        TriggerManagedTooltips("tooltip.style.mask", value)
    elseif keystring == "general.scale" then
        TriggerManagedTooltips("tooltip.scale", value)
    elseif keystring == "general.background" then
        TriggerManagedTooltips("tooltip.style.background", unpack(value))
    elseif keystring == "general.borderColor" then
        TriggerManagedTooltips("tooltip.style.border.color", unpack(value))
    elseif keystring == "general.borderSize" then
        TriggerManagedTooltips("tooltip.style.border.size", value)
    elseif keystring == "general.borderCorner" then
        TriggerManagedTooltips("tooltip.style.border.corner", value)
        if value == "angular" then
            TriggerManagedTooltips("tooltip.style.border.size", general.borderSize)
        end
    elseif keystring == "general.bgfile" then
        TriggerManagedTooltips("tooltip.style.bgfile", value)
    end

    if keystring == "general.statusbarText" then
        LibEvent:trigger("tooltip.statusbar.text", value)
    elseif keystring == "general.statusbarHeight" then
        LibEvent:trigger("tooltip.statusbar.height", value)
    elseif keystring == "general.statusbarTexture" then
        LibEvent:trigger("tooltip.statusbar.texture", value)
    elseif keystring == "general.statusbarPosition"
        or keystring == "general.statusbarOffsetX"
        or keystring == "general.statusbarOffsetY" then
        LibEvent:trigger("tooltip.statusbar.position", general.statusbarPosition, general.statusbarOffsetX, general.statusbarOffsetY)
    elseif keystring:find("general.statusbarFont", 1, true) == 1 then
        LibEvent:trigger("tooltip.statusbar.font", general.statusbarFont, general.statusbarFontSize, general.statusbarFontFlag)
    elseif keystring:find("general.headerFont", 1, true) == 1 then
        TriggerManagedTooltips("tooltip.style.font.header", general.headerFont, general.headerFontSize, general.headerFontFlag)
    elseif keystring:find("general.bodyFont", 1, true) == 1 then
        TriggerManagedTooltips("tooltip.style.font.body", general.bodyFont, general.bodyFontSize, general.bodyFontFlag)
    end
end

local function ApplySavedVariableScope(value)
    RothTooltipDB = RothTooltipDB or {}
    RothTooltipDB.general = RothTooltipDB.general or {}
    RothTooltipDB.general.SavedVariablesPerCharacter = value and true or false

    if value then
        local db = CopyTable(addon.db)
        addon.db = addon:MergeVariable(db, RothTooltipCharacterDB or {})
    else
        addon.db = RothTooltipDB
    end

    addon.__RT_StyleRev = (addon.__RT_StyleRev or 0) + 1
    LibEvent:trigger("tooltip:variables:loaded")
    LibEvent:trigger("ROTHTOOLTIP_GENERAL_INIT")
    RefreshShownTooltips("saved-variable-scope")
end

local function NeedsVisibleTooltipRefresh(keystring)
    if keystring == "general.alwaysShowIdInfo" then
        return true
    end

    local prefixes = {
        "item.",
        "quest.",
        "spell.",
        "unit.",
        "general.visibility.",
        "general.combatPolicy",
        "general.statusbarColor",
        "general.statusbarTextFormat",
    }

    for _, prefix in ipairs(prefixes) do
        if keystring:find(prefix, 1, true) == 1 then
            return true
        end
    end

    return false
end

local function SetVariable(keystring, value, tbl)
    if keystring == "general.SavedVariablesPerCharacter" then
        ApplySavedVariableScope(value)
        LibEvent:trigger("tooltip:variable:changed", keystring, value)
        return
    end

    local target = tbl or addon.db
    SetNestedValue(target, keystring, value)

    local modName = keystring:match("^modules%.(.+)$")
    if modName then
        if addon and addon.MM and addon.MM.core and addon.MM.core[modName] then
            SetNestedValue(target, keystring, true)
            value = true
        end
        if addon and addon.EnableModule and addon.DisableModule then
            if value then
                addon:EnableModule(modName)
            else
                addon:DisableModule(modName)
            end
        end
    end

    addon.__RT_StyleRev = (addon.__RT_StyleRev or 0) + 1
    CallTrigger(keystring, value)
    LibEvent:trigger("tooltip:variable:changed", keystring, value)

    if NeedsVisibleTooltipRefresh(keystring) then
        RefreshShownTooltips(keystring)
    end
end

local function AddUniqueValues(target, values)
    local seen = {}
    for _, value in ipairs(target) do
        seen[value] = true
    end
    for _, value in ipairs(values or EMPTY_TABLE) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            target[#target + 1] = value
            seen[value] = true
        end
    end
end

local function RebuildMediaValues()
    wipe(mediaValues.background)
    wipe(mediaValues.border)
    wipe(mediaValues.font)
    wipe(mediaValues.statusbar)

    AddUniqueValues(mediaValues.background, { "gradual", "dark", "alpha", "rock", "marble", "RothTooltipDarkTexture" })
    AddUniqueValues(mediaValues.border, { "default", "angular", "RothTooltipDarkFrame" })
    AddUniqueValues(mediaValues.font, { "default", "ChatFontNormal", "GameFontNormal", "QuestFont", "CombatLogFont" })
    AddUniqueValues(mediaValues.statusbar, { "Interface\\AddOns\\" .. addonName .. "\\texture\\StatusBar" })

    local LibMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)
    if LibMedia then
        AddUniqueValues(mediaValues.background, LibMedia:List("background"))
        AddUniqueValues(mediaValues.border, LibMedia:List("border"))
        AddUniqueValues(mediaValues.font, LibMedia:List("font"))
        AddUniqueValues(mediaValues.statusbar, LibMedia:List("statusbar"))
    end
end

local function BuildTextOptions(values)
    return function()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs(values or EMPTY_TABLE) do
            container:Add(value, GetDropdownOptionText(value))
        end
        return container:GetData()
    end
end

local function AddSection(layout, title, tooltip)
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title, tooltip))
    end
end

local function CreateCheckboxSetting(category, keystring, label, tooltip)
    local defaultValue = GetVariable(keystring)
    if defaultValue == nil then
        defaultValue = false
    end

    local setting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring),
        Settings.VarType.Boolean,
        label,
        defaultValue and Settings.Default.True or Settings.Default.False,
        function()
            return GetVariable(keystring) and true or false
        end,
        function(value)
            SetVariable(keystring, value and true or false)
        end
    )

    return Settings.CreateCheckbox(category, setting, tooltip)
end

local function ApplySliderFormatter(options, step)
    if not options or not options.SetLabelFormatter or not MinimalSliderWithSteppersMixin then
        return
    end

    if step and step < 1 then
        local precision = step < 0.1 and 2 or 1
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return format("%." .. precision .. "f", value)
        end)
    else
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return tostring(floor((tonumber(value) or 0) + 0.5))
        end)
    end
end

local function CreateSliderSetting(category, keystring, label, minValue, maxValue, step, tooltip, defaultValue)
    local currentValue = tonumber(GetVariable(keystring))
    if currentValue == nil then
        currentValue = defaultValue ~= nil and defaultValue or minValue
    end

    local setting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring),
        Settings.VarType.Number,
        label,
        currentValue,
        function()
            return tonumber(GetVariable(keystring)) or currentValue
        end,
        function(value)
            local rounded
            if step and step < 1 then
                local precision = step < 0.1 and 2 or 1
                rounded = tonumber(format("%." .. precision .. "f", value)) or value
            else
                rounded = floor((tonumber(value) or 0) + 0.5)
            end
            SetVariable(keystring, rounded)
        end
    )

    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    ApplySliderFormatter(options, step)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function CreateStringDropdownSetting(category, keystring, label, values, tooltip, defaultValue)
    defaultValue = defaultValue ~= nil and defaultValue or values[1]
    local setting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring),
        Settings.VarType.String,
        label,
        tostring(defaultValue),
        function()
            local value = GetVariable(keystring)
            if value == nil then
                return tostring(defaultValue)
            end
            return tostring(value)
        end,
        function(value)
            SetVariable(keystring, value)
        end
    )

    return Settings.CreateDropdown(category, setting, BuildTextOptions(values), tooltip)
end

local function CreateMixedDropdownSetting(category, keystring, label, values, tooltip)
    local defaultValue = tostring(values[1])
    local optionsFunc = function()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs(values or EMPTY_TABLE) do
            container:Add(tostring(value), GetDropdownOptionText(value))
        end
        return container:GetData()
    end

    local setting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring),
        Settings.VarType.String,
        label,
        defaultValue,
        function()
            local value = GetVariable(keystring)
            if value == nil then
                return defaultValue
            end
            return tostring(value)
        end,
        function(value)
            local castValue = tonumber(value)
            if castValue == nil then
                castValue = value
            end
            SetVariable(keystring, castValue)
        end
    )

    return Settings.CreateDropdown(category, setting, optionsFunc, tooltip)
end

local function GetSettingsColorHex(keystring)
    return GetSettingsColorHexFromValue(GetVariable(keystring))
end

local function CreateRGBAColorSettings(category, keystring, label, tooltip)
    local colorSetting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring, "RGB"),
        Settings.VarType.String,
        label,
        GetSettingsColorHex(keystring),
        function()
            return GetSettingsColorHex(keystring)
        end,
        function(value)
            local current = GetVariable(keystring)
            local alpha = GetStoredColorAlpha(current)
            local r, g, b = addon:GetRGBColor(value)
            SetVariable(keystring, { r, g, b, alpha })
        end
    )
    return Settings.CreateColorSwatch(category, colorSetting, tooltip)
end

local function CreateRGBAAlphaSlider(category, keystring, label, tooltip)
    local setting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring, "ALPHA"),
        Settings.VarType.Number,
        label,
        1,
        function()
            return GetStoredColorAlpha(GetVariable(keystring))
        end,
        function(value)
            local current = GetVariable(keystring)
            local r, g, b = 1, 1, 1
            if type(current) == "table" then
                r = tonumber(current[1]) or 1
                g = tonumber(current[2]) or 1
                b = tonumber(current[3]) or 1
            else
                r, g, b = addon:GetRGBColor(current)
            end
            SetVariable(keystring, { r, g, b, tonumber(format("%.2f", value)) or value })
        end
    )
    local options = Settings.CreateSliderOptions(0, 1, 0.01)
    ApplySliderFormatter(options, 0.01)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function CreateRGBAColorBlock(category, keystring, label, tooltip)
    CreateRGBAColorSettings(category, keystring, label, tooltip)
    CreateRGBAAlphaSlider(category, keystring, label .. " Opacity", tooltip)
end

local function CreateColorFuncBlock(category, baseKey, label)
    CreateStringDropdownSetting(category, baseKey .. ".colorfunc", label .. " Color", COLOR_FUNC_OPTIONS)
    CreateSliderSetting(category, baseKey .. ".alpha", label .. " Opacity", 0, 1, 0.01)
end

local function CreateAnchorBlock(category, baseKey, label, values, layout)
    AddSection(layout, label)
    local positionInitializer = CreateStringDropdownSetting(category, baseKey .. ".position", label .. " Position", values)
    CreateCheckboxSetting(category, baseKey .. ".hiddenInCombat", label .. " Hide in Combat")
    CreateCheckboxSetting(category, baseKey .. ".returnInCombat", label .. " Return in Combat")
    CreateCheckboxSetting(category, baseKey .. ".returnOnUnitFrame", label .. " Return on Unit Frame")

    local function BindToPosition(initializer, predicate)
        if initializer and positionInitializer and initializer.SetParentInitializer then
            initializer:SetParentInitializer(positionInitializer, predicate)
        end
    end

    local staticPoint = CreateStringDropdownSetting(category, baseKey .. ".p", label .. " Static Point", STATIC_ANCHOR_POINTS, nil, "BOTTOMRIGHT")
    local staticX = CreateSliderSetting(category, baseKey .. ".x", label .. " Static X", -1000, 1000, 1, nil, 0)
    local staticY = CreateSliderSetting(category, baseKey .. ".y", label .. " Static Y", -1000, 1000, 1, nil, 0)
    local cursorPoint = CreateStringDropdownSetting(category, baseKey .. ".cp", label .. " Cursor Point", CURSOR_ANCHOR_POINTS, nil, "BOTTOM")
    local cursorX = CreateSliderSetting(category, baseKey .. ".cx", label .. " Cursor X", -300, 300, 1, nil, 0)
    local cursorY = CreateSliderSetting(category, baseKey .. ".cy", label .. " Cursor Y", -300, 300, 1, nil, 20)

    BindToPosition(staticPoint, function()
        return GetVariable(baseKey .. ".position") == "static"
    end)
    BindToPosition(staticX, function()
        return GetVariable(baseKey .. ".position") == "static"
    end)
    BindToPosition(staticY, function()
        return GetVariable(baseKey .. ".position") == "static"
    end)
    BindToPosition(cursorPoint, function()
        return GetVariable(baseKey .. ".position") == "cursor"
    end)
    BindToPosition(cursorX, function()
        local position = GetVariable(baseKey .. ".position")
        return position == "cursor" or position == "auto"
    end)
    BindToPosition(cursorY, function()
        local position = GetVariable(baseKey .. ".position")
        return position == "cursor" or position == "auto"
    end)
end

local function GetElementColorMode(keystring)
    local value = GetVariable(keystring)
    if IsHexColor(value) then
        return COLOR_MODE_CUSTOM
    end
    return tostring(value or "default")
end

local function SetElementColorMode(keystring, value)
    if value == COLOR_MODE_CUSTOM then
        local current = GetVariable(keystring)
        if not IsHexColor(current) then
            current = "ffffff"
        end
        SetVariable(keystring, current)
    else
        SetVariable(keystring, value)
    end
end

local function CreateElementModeDropdown(category, keystring, label)
    local setting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring, "MODE"),
        Settings.VarType.String,
        label,
        "default",
        function()
            return GetElementColorMode(keystring)
        end,
        function(value)
            SetElementColorMode(keystring, value)
        end
    )

    return Settings.CreateDropdown(category, setting, BuildTextOptions(ELEMENT_COLOR_OPTIONS))
end

local function CreateElementColorSwatch(category, keystring, label, parentInitializer)
    local setting = Settings.RegisterProxySetting(
        category,
        MakeSettingName(keystring, "CUSTOM"),
        Settings.VarType.String,
        label,
        "FFFFFFFF",
        function()
            return GetSettingsColorHexFromValue(GetVariable(keystring))
        end,
        function(value)
            SetVariable(keystring, strlower(GetHexColorNoAlpha(value) or "FFFFFF"))
        end
    )

    local initializer = Settings.CreateColorSwatch(category, setting)
    if parentInitializer and initializer.SetParentInitializer then
        initializer:SetParentInitializer(parentInitializer, function()
            return GetElementColorMode(keystring) == COLOR_MODE_CUSTOM
        end)
    end
    return initializer
end

local CreateSettingsButton
local OpenWildcardEditor

local function CreateElementControls(category, layout, elementOptions)
    for _, entry in ipairs(elementOptions) do
        AddSection(layout, L[entry.key])
        CreateCheckboxSetting(category, entry.key .. ".enable", L[entry.key])

        if entry.color then
            local modeInitializer = CreateElementModeDropdown(category, entry.key .. ".color", L[entry.key] .. " Color")
            CreateElementColorSwatch(category, entry.key .. ".color", L[entry.key] .. " Custom Color", modeInitializer)
        end

        if entry.filter then
            CreateStringDropdownSetting(category, entry.key .. ".filter", L[entry.key] .. " Filter", COLOR_FILTER_OPTIONS)
        end

        if entry.wildcard then
            CreateSettingsButton(layout, L[entry.key], "Edit Format", function()
                OpenWildcardEditor(entry.key .. ".wildcard", L[entry.key])
            end, "Edit wildcard text for this element.", true)
        end
    end
end

CreateSettingsButton = function(layout, name, buttonText, onClick, tooltip, addSearchTags)
    if not layout or not CreateSettingsButtonInitializer then
        return nil
    end
    local initializer = CreateSettingsButtonInitializer(name or "", buttonText, onClick, tooltip, addSearchTags == true)
    layout:AddInitializer(initializer)
    return initializer
end

local function GetActiveVariableStore()
    if GetVariable("general.SavedVariablesPerCharacter") then
        RothTooltipCharacterDB = RothTooltipCharacterDB or {}
        return RothTooltipCharacterDB
    end
    RothTooltipDB = RothTooltipDB or {}
    return RothTooltipDB
end

local function CreateVariablesDialog()
    if addon.__RTVariablesDialog then
        return addon.__RTVariablesDialog
    end

    local dialog = CreateFrame("Frame", nil, UIParent, "RothTooltipVariablesTemplate")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    dialog:Hide()

    dialog.close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.close:SetPoint("TOPRIGHT", 0, 0)
    dialog.close:SetScript("OnClick", function() dialog:Hide() end)

    dialog.export:SetScript("OnClick", function()
        local json = C_EncodingUtil.SerializeJSON(addon.db)
        dialog.textarea.text:SetText(json or "")
        dialog.textarea.text:SetFocus(true)
        dialog.textarea.text:HighlightText()
    end)

    dialog.import:SetScript("OnClick", function()
        local text = dialog.textarea.text:GetText()
        local data = C_EncodingUtil.DeserializeJSON(text)
        if (data and type(data) == "table") then
            addon:FixNumericKey(data)
            local store = GetActiveVariableStore()
            local db = addon:MergeVariable(addon.db, data)
            for key in pairs(store) do
                store[key] = nil
            end
            for key, value in pairs(db) do
                store[key] = value
            end
            addon.db = store
            dialog.textarea.text:SetText("")
            LibEvent:trigger("tooltip:variables:loaded")
            LibEvent:trigger("ROTHTOOLTIP_GENERAL_INIT")
            RefreshShownTooltips("import-profile")
            print("|cffFFE4E1[RothTooltip]|r|cff00FFFF variables imported successfully. |r")
        else
            print("|cffFFE4E1[RothTooltip]|r|cffFF3333 invalid variables payload. |r")
        end
    end)

    if dialog.reset then
        dialog.reset:SetScript("OnClick", function()
            StaticPopup_Show("ROTHTOOLTIP_RESET_SV")
        end)
    end

    addon.__RTVariablesDialog = dialog
    return dialog
end

OpenWildcardEditor = function(keystring, label)
    addon.__RTWildcardEdit = {
        keystring = keystring,
        label = label,
    }
    StaticPopup_Show("ROTHTOOLTIP_EDIT_WILDCARD")
end

local function CreateDIYEditor()
    if addon.__RTDIYEditor then
        return addon.__RTDIYEditor
    end

    local diytable = {}
    local diyPlayerTable = {}
    local draggingButton
    local overButton
    local overLine
    local OnElementDragStart
    local OnElementDragStop

    local frame = CreateFrame("Frame", nil, UIParent)
    frame.identity = "diy"
    frame.lines = {}
    frame.elements = {}
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetSize(360, 180)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", 0, 0)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.tips = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLargeOutline")
    frame.tips:SetPoint("BOTTOM", 0, 10)
    frame.tips:SetFont(frame.tips:GetFont(), 12, "NONE")
    frame.tips:SetText(L["<Drag element to customize the style>"])

    local placeholder = {
        statusAFK = "AFK",
        statusDND = "DND",
        statusDC = "DC",
        friendIcon = addon.icons.friend,
        pvpIcon = addon.icons.pvp,
        roleIcon = addon.icons.DAMAGER,
        raidIcon = ICON_LIST[8] .. "0|t",
    }
    setmetatable(placeholder, { __index = function(_, key) return key end })

    local function SyncDIYState()
        diytable = addon.db and addon.db.unit and addon.db.unit.player and addon.db.unit.player.elements or {}
        diyPlayerTable = addon.db and addon.db.unit and addon.db.unit.player or {}
    end

    local function CreateLine(lineNumber)
        if not frame.lines[lineNumber] then
            local line = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
            line:SetSize(320, 24)
            line.line = lineNumber
            if line.SetBackdrop then
                line:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                line:SetBackdropBorderColor(1, 0.9, 0.1)
            end
            line:SetAlpha(0)
            frame.lines[lineNumber] = line
        end
        return frame.lines[lineNumber]
    end

    local function ClearHighlights()
        for _, line in ipairs(frame.lines) do
            line:SetAlpha(0)
        end
        for _, element in pairs(frame.elements) do
            if element.vbar then
                element.vbar:Hide()
            end
        end
    end

    local function RenderDIYEditor(skipDisable)
        SyncDIYState()

        local raw = addon:GetUnitInfo("player")
        local frameWidth = 0
        local totalLines = 0

        if addon.ApplyGeneralStyleToTooltip then
            addon:ApplyGeneralStyleToTooltip(frame)
        end

        for lineIndex, entries in ipairs(diytable) do
            local line = CreateLine(lineIndex)
            local lineWidth = 0

            for _, elementKey in ipairs(entries) do
                local element = frame.elements[elementKey]
                if not element then
                    element = CreateFrame("Button", nil, frame)
                    element.key = elementKey
                    element:SetSize(40, 20)
                    element:SetMovable(true)
                    element.text = element:CreateFontString(nil, "ARTWORK", "GameTooltipText")
                    element.text:SetPoint("LEFT")
                    element.vbar = element:CreateTexture(nil, "OVERLAY")
                    element.vbar:SetPoint("TOPLEFT", 0, 0)
                    element.vbar:SetPoint("BOTTOMLEFT", 2, 0)
                    element.vbar:SetColorTexture(1, 0.8, 0)
                    element.vbar:Hide()
                    element:RegisterForDrag("LeftButton")
                    element:SetScript("OnDragStart", function(self)
                        if OnElementDragStart then
                            OnElementDragStart(self)
                        end
                    end)
                    element:SetScript("OnDragStop", function(self)
                        if OnElementDragStop then
                            OnElementDragStop(self)
                        end
                    end)
                    element:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(L[self.key])
                        GameTooltip:Show()
                    end)
                    element:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                    frame.elements[elementKey] = element
                end

                local config = addon.db.unit.player.elements[elementKey]
                if config and (not skipDisable or config.enable) then
                    local value = raw[elementKey] or placeholder[elementKey]
                    if config.color and config.wildcard then
                        value = addon:FormatData(value, config, raw)
                    end
                    element.text:SetText(value)
                    element:SetWidth(element.text:GetWidth() + 4)
                    element:ClearAllPoints()
                    element:SetPoint("LEFT", line, "LEFT", lineWidth, 0)
                    element:Show()
                    lineWidth = lineWidth + element:GetWidth()
                else
                    element:Hide()
                end
            end

            if lineWidth > frameWidth then
                frameWidth = lineWidth + 16
            end

            totalLines = lineIndex
        end

        totalLines = totalLines + 1
        frame:SetWidth(frameWidth + 28)
        frame:SetHeight(totalLines * 24 + 40)

        for lineIndex = 1, totalLines do
            local line = CreateLine(lineIndex)
            line:Show()
            line:SetWidth(frameWidth)
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -(lineIndex * 25) + 25 - 12)
        end

        while frame.lines[totalLines + 1] do
            frame.lines[totalLines + 1]:Hide()
            totalLines = totalLines + 1
        end

        if diytable.factionBig and diytable.factionBig.enable and frame.BigFactionIcon
            and (raw.factionGroup == "Alliance" or raw.factionGroup == "Horde") then
            frame.BigFactionIcon:SetTexture("Interface\\Timer\\" .. raw.factionGroup .. "-Logo")
            frame.BigFactionIcon:Show()
            frame:SetWidth(frameWidth + 48)
        elseif frame.BigFactionIcon then
            frame.BigFactionIcon:Hide()
        end

        addon.ColorUnitBorder(frame, diyPlayerTable, raw)
        addon.ColorUnitBackground(frame, diyPlayerTable, raw)
        frame:Show()
    end

    OnElementDragStart = function(self)
        draggingButton = self
        local cursorX, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetScale()
        self:StartMoving()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / uiScale, cursorY / uiScale)
    end

    OnElementDragStop = function(self)
        draggingButton = nil
        self:StopMovingOrSizing()

        if overButton then
            overButton.vbar:Hide()
            for _, entries in ipairs(diytable) do
                for index = #entries, 1, -1 do
                    if entries[index] == self.key then
                        tremove(entries, index)
                    end
                end
                for index = #entries, 1, -1 do
                    if entries[index] == overButton.key then
                        tinsert(entries, index, self.key)
                    end
                end
            end
            overButton = nil
        end

        if overLine then
            overLine:SetAlpha(0)
            for _, entries in ipairs(diytable) do
                for index = #entries, 1, -1 do
                    if entries[index] == self.key then
                        tremove(entries, index)
                    end
                end
            end
            if not diytable[overLine.line] then
                diytable[overLine.line] = {}
            end
            tinsert(diytable[overLine.line], self.key)
            overLine = nil
        end

        for index = #diytable, 1, -1 do
            if #diytable[index] == 0 then
                tremove(diytable, index)
            end
        end

        ClearHighlights()
        RenderDIYEditor(true)
    end

    frame:SetScript("OnUpdate", function(self, elapsed)
        if not draggingButton then
            return
        end

        self.timer = (self.timer or 0) + elapsed
        if self.timer < 0.15 then
            return
        end
        self.timer = 0

        local hasOverButton = false
        for _, entries in ipairs(diytable) do
            for _, elementKey in ipairs(entries) do
                local element = frame.elements[elementKey]
                if element and element.key ~= draggingButton.key and element:IsMouseOver() then
                    overButton = element
                    element.vbar:Show()
                    hasOverButton = true
                elseif element and element.vbar then
                    element.vbar:Hide()
                end
            end
        end

        if not hasOverButton then
            for _, line in ipairs(frame.lines) do
                if line:IsShown() and line:IsMouseOver() then
                    overLine = line
                    line:SetAlpha(1)
                else
                    line:SetAlpha(0.2)
                end
            end
        elseif overLine then
            overLine:SetAlpha(0)
            overLine = nil
        end
    end)

    frame:HookScript("OnShow", function()
        RenderDIYEditor(true)
    end)
    frame:HookScript("OnHide", function()
        ClearHighlights()
        draggingButton = nil
        overButton = nil
        overLine = nil
    end)

    SyncDIYState()
    addon:RegisterTooltipFrame(frame)
    frame.__RTRenderDIY = RenderDIYEditor
    frame.__RTSyncDIYState = SyncDIYState
    addon.__RTDIYEditor = frame
    return frame
end

LibEvent:attachTrigger("tooltip:variables:loaded", function()
    local frame = addon.__RTDIYEditor
    if frame and frame.__RTSyncDIYState then
        frame.__RTSyncDIYState()
        if frame:IsShown() and frame.__RTRenderDIY then
            frame.__RTRenderDIY(true)
        end
    end
end)

LibEvent:attachTrigger("tooltip:variable:changed", function()
    local frame = addon.__RTDIYEditor
    if frame and frame:IsShown() and frame.__RTRenderDIY then
        frame.__RTRenderDIY(true)
    end
end)

local function TryInitializeOptions()
    if addon.__RT_OptionsInitialized then
        return true
    end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return false
    end

    RebuildMediaValues()

    local rootCategory, rootLayout = Settings.RegisterVerticalLayoutCategory(addonName)
    categoryRefs.root = rootCategory
    categoryRefs.general = rootCategory

    AddSection(rootLayout, "Appearance")
    CreateCheckboxSetting(rootCategory, "general.mask", L["general.mask"])
    CreateCheckboxSetting(rootCategory, "general.skinMoreFrames", L["general.skinMoreFrames"])
    CreateRGBAColorBlock(rootCategory, "general.background", L["general.background"])
    CreateRGBAColorBlock(rootCategory, "general.borderColor", L["general.borderColor"])
    CreateSliderSetting(rootCategory, "general.scale", L["general.scale"], 0.5, 4, 0.1)
    CreateSliderSetting(rootCategory, "general.borderSize", L["general.borderSize"], 1, 6, 1)
    CreateStringDropdownSetting(rootCategory, "general.borderCorner", L["general.borderCorner"], mediaValues.border)
    CreateStringDropdownSetting(rootCategory, "general.bgfile", L["general.bgfile"], mediaValues.background)

    CreateAnchorBlock(rootCategory, "general.anchor", L["general.anchor"], GENERAL_ANCHOR_OPTIONS, rootLayout)

    AddSection(rootLayout, "Content")
    CreateCheckboxSetting(rootCategory, "item.coloredItemBorder", L["item.coloredItemBorder"])
    CreateCheckboxSetting(rootCategory, "item.showItemIcon", L["item.showItemIcon"])
    CreateCheckboxSetting(rootCategory, "item.showStackCount", L["item.showStackCount"])
    CreateCheckboxSetting(rootCategory, "item.showItemID", L["item.showItemID"])
    CreateCheckboxSetting(rootCategory, "item.showExpansionInfo", L["item.showExpansionInfo"])
    CreateCheckboxSetting(rootCategory, "quest.coloredQuestBorder", L["quest.coloredQuestBorder"])
    CreateCheckboxSetting(rootCategory, "general.alwaysShowIdInfo", L["general.alwaysShowIdInfo"])

    AddSection(rootLayout, "Visibility")
    CreateStringDropdownSetting(rootCategory, "general.visibility.inCombat", L["general.visibility.inCombat"], COMBAT_VISIBILITY_OPTIONS)
    CreateStringDropdownSetting(rootCategory, "general.visibility.inRaid", L["general.visibility.inRaid"], VISIBILITY_OPTIONS)
    CreateStringDropdownSetting(rootCategory, "general.visibility.inArena", L["general.visibility.inArena"], VISIBILITY_OPTIONS)
    CreateStringDropdownSetting(rootCategory, "general.visibility.bags", L["general.visibility.bags"], VISIBILITY_OPTIONS)
    CreateStringDropdownSetting(rootCategory, "general.visibility.actionBars", L["general.visibility.actionBars"], VISIBILITY_OPTIONS)

    AddSection(rootLayout, "Profiles")
    CreateCheckboxSetting(rootCategory, "general.SavedVariablesPerCharacter", L["general.SavedVariablesPerCharacter"])
    CreateStringDropdownSetting(rootCategory, "general.combatPolicy", L["general.combatPolicy"], { "STRICT", "BALANCED", "AGGRESSIVE" })

    local playerCategory, playerLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "Player")
    categoryRefs.player = playerCategory
    CreateCheckboxSetting(playerCategory, "unit.player.showTarget", L["unit.player.showTarget"])
    CreateCheckboxSetting(playerCategory, "unit.player.showTargetBy", L["unit.player.showTargetBy"])
    CreateCheckboxSetting(playerCategory, "unit.player.showModel", L["unit.player.showModel"])
    CreateCheckboxSetting(playerCategory, "unit.player.showItemLevel", L["unit.player.showItemLevel"])
    CreateCheckboxSetting(playerCategory, "unit.player.showPveScore", L["unit.player.showPveScore"])
    CreateCheckboxSetting(playerCategory, "unit.player.showBestKey", L["unit.player.showBestKey"])
    CreateCheckboxSetting(playerCategory, "unit.player.showRaidProgress", L["unit.player.showRaidProgress"])
    CreateCheckboxSetting(playerCategory, "unit.player.grayForDead", L["unit.player.grayForDead"])
    CreateStringDropdownSetting(playerCategory, "unit.player.coloredBorder", L["unit.player.coloredBorder"], COLOR_FUNC_OPTIONS)
    CreateColorFuncBlock(playerCategory, "unit.player.background", L["unit.player.background"])
    CreateAnchorBlock(playerCategory, "unit.player.anchor", L["unit.player.anchor"], UNIT_ANCHOR_OPTIONS, playerLayout)

    local playerElementsCategory, playerElementsLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "Player Elements")
    categoryRefs.playerElements = playerElementsCategory
    CreateElementControls(playerElementsCategory, playerElementsLayout, PLAYER_ELEMENT_OPTIONS)
    CreateSettingsButton(playerElementsLayout, "Player Layout", "Open DIY Layout Editor", function()
        local frame = CreateDIYEditor()
        frame:Show()
        if frame.__RTRenderDIY then
            frame.__RTRenderDIY(true)
        end
    end, "Drag player tooltip elements to reorder the preview layout.", true)

    local npcCategory, npcLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "NPC")
    categoryRefs.npc = npcCategory
    CreateCheckboxSetting(npcCategory, "unit.npc.showTarget", L["unit.npc.showTarget"])
    CreateCheckboxSetting(npcCategory, "unit.npc.showTargetBy", L["unit.npc.showTargetBy"])
    CreateCheckboxSetting(npcCategory, "unit.npc.showModel", L["unit.npc.showModel"])
    CreateCheckboxSetting(npcCategory, "unit.npc.grayForDead", L["unit.npc.grayForDead"])
    CreateStringDropdownSetting(npcCategory, "unit.npc.coloredBorder", L["unit.npc.coloredBorder"], COLOR_FUNC_OPTIONS)
    CreateColorFuncBlock(npcCategory, "unit.npc.background", L["unit.npc.background"])
    CreateAnchorBlock(npcCategory, "unit.npc.anchor", L["unit.npc.anchor"], UNIT_ANCHOR_OPTIONS, npcLayout)

    local npcElementsCategory, npcElementsLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "NPC Elements")
    categoryRefs.npcElements = npcElementsCategory
    CreateElementControls(npcElementsCategory, npcElementsLayout, NPC_ELEMENT_OPTIONS)

    local statusbarCategory, statusbarLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "StatusBar")
    categoryRefs.statusbar = statusbarCategory
    AddSection(statusbarLayout, "StatusBar")
    CreateCheckboxSetting(statusbarCategory, "general.statusbarText", L["general.statusbarText"])
    CreateSliderSetting(statusbarCategory, "general.statusbarHeight", L["general.statusbarHeight"], 0, 24, 1)
    CreateSliderSetting(statusbarCategory, "general.statusbarOffsetX", L["general.statusbarOffsetX"], -50, 50, 1)
    CreateSliderSetting(statusbarCategory, "general.statusbarOffsetY", L["general.statusbarOffsetY"], -50, 50, 1)
    CreateSliderSetting(statusbarCategory, "general.statusbarFontSize", L["general.statusbarFontSize"], 6, 30, 1)
    CreateStringDropdownSetting(statusbarCategory, "general.statusbarFont", L["general.statusbarFont"], mediaValues.font)
    CreateStringDropdownSetting(statusbarCategory, "general.statusbarFontFlag", L["general.statusbarFontFlag"], FONT_FLAG_OPTIONS)
    CreateStringDropdownSetting(statusbarCategory, "general.statusbarTexture", L["general.statusbarTexture"], mediaValues.statusbar)
    CreateStringDropdownSetting(statusbarCategory, "general.statusbarPosition", L["general.statusbarPosition"], { "default", "bottom", "top" })
    CreateStringDropdownSetting(statusbarCategory, "general.statusbarColor", L["general.statusbarColor"], { "default", "auto", "smooth" })
    CreateStringDropdownSetting(statusbarCategory, "general.statusbarTextFormat", L["general.statusbarTextFormat"], STATUSBAR_TEXT_FORMAT_OPTIONS)

    local spellCategory, spellLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "Spell")
    categoryRefs.spell = spellCategory
    AddSection(spellLayout, "Spell")
    CreateCheckboxSetting(spellCategory, "spell.showIcon", L["spell.showIcon"])

    local fontCategory, fontLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "Fonts")
    categoryRefs.font = fontCategory
    AddSection(fontLayout, "Header")
    CreateStringDropdownSetting(fontCategory, "general.headerFont", L["general.headerFont"], mediaValues.font)
    CreateMixedDropdownSetting(fontCategory, "general.headerFontSize", L["general.headerFontSize"], { "default", 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24 })
    CreateStringDropdownSetting(fontCategory, "general.headerFontFlag", L["general.headerFontFlag"], FONT_FLAG_OPTIONS)
    AddSection(fontLayout, "Body")
    CreateStringDropdownSetting(fontCategory, "general.bodyFont", L["general.bodyFont"], mediaValues.font)
    CreateMixedDropdownSetting(fontCategory, "general.bodyFontSize", L["general.bodyFontSize"], { "default", 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24 })
    CreateStringDropdownSetting(fontCategory, "general.bodyFontFlag", L["general.bodyFontFlag"], FONT_FLAG_OPTIONS)

    local modulesCategory, modulesLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "Modules")
    categoryRefs.modules = modulesCategory
    AddSection(modulesLayout, "Modules")
    local moduleOrder = {
        "General",
        "Anchor",
        "Target",
        "Unit",
        "Model",
        "Item",
        "Spell",
        "Quest",
        "LinkID",
        "Mount",
        "ExpansionInfo",
        "SkinFrames",
    }
    for _, moduleName in ipairs(moduleOrder) do
        CreateCheckboxSetting(modulesCategory, "modules." .. moduleName, moduleName)
    end

    local dataCategory, dataLayout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, "Data")
    categoryRefs.data = dataCategory
    AddSection(dataLayout, "Profile Data")
    CreateSettingsButton(dataLayout, "Profile Data", "Open Import / Export", function()
        local dialog = CreateVariablesDialog()
        dialog:Show()
    end, "Open RothTooltip profile import/export tools.", true)
    CreateSettingsButton(dataLayout, "Profile Refresh", "Reapply Active Profile", function()
        LibEvent:trigger("tooltip:variables:loaded")
        LibEvent:trigger("ROTHTOOLTIP_GENERAL_INIT")
        RefreshShownTooltips("reapply-profile")
    end, "Re-runs variable load side effects for the current profile.", true)
    CreateSettingsButton(dataLayout, "Profile Reset", RESET or "Reset", function()
        StaticPopup_Show("ROTHTOOLTIP_RESET_SV")
    end, "Reset account and character SavedVariables, then reload the UI.", true)

    Settings.RegisterAddOnCategory(rootCategory)
    addon.__RT_OptionsInitialized = true
    return true
end

local function OpenCategory(category)
    if not TryInitializeOptions() then
        return
    end

    if category and category.GetID then
        Settings.OpenToCategory(category:GetID())
    elseif categoryRefs.general and categoryRefs.general.GetID then
        Settings.OpenToCategory(categoryRefs.general:GetID())
    end
end

if not StaticPopupDialogs["ROTHTOOLTIP_EDIT_WILDCARD"] then
    StaticPopupDialogs["ROTHTOOLTIP_EDIT_WILDCARD"] = {
        text = "Edit Format",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = 1,
        maxLetters = 128,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
        OnShow = function(self)
            local context = addon.__RTWildcardEdit
            if self.text and context then
                self.text:SetText((context.label or "Element") .. " Format")
            end
            if self.editBox and context then
                self.editBox:SetText(tostring(GetVariable(context.keystring) or ""))
                self.editBox:HighlightText()
                self.editBox:SetFocus()
            end
        end,
        OnAccept = function(self)
            local context = addon.__RTWildcardEdit
            if context and self.editBox then
                SetVariable(context.keystring, self.editBox:GetText())
            end
        end,
        OnHide = function(self)
            if self.editBox then
                self.editBox:SetText("")
            end
            addon.__RTWildcardEdit = nil
        end,
        EditBoxOnEnterPressed = function(self)
            local popup = self:GetParent()
            if popup and popup.button1 then
                popup.button1:Click()
            end
        end,
    }
end

if not StaticPopupDialogs["ROTHTOOLTIP_RESET_SV"] then
    StaticPopupDialogs["ROTHTOOLTIP_RESET_SV"] = {
        text = "[RothTooltip] Reset SavedVariables and reload UI?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            RothTooltipDB = nil
            RothTooltipCharacterDB = nil
            ReloadUI()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded(addonName, TryInitializeOptions)
end

if IsLoggedIn and IsLoggedIn() then
    TryInitializeOptions()
else
    LibEvent:attachEventOnce("PLAYER_LOGIN", TryInitializeOptions)
end

SLASH_RothTooltip1 = "/tinytooltip"
SLASH_RothTooltip2 = "/tt"
SLASH_RothTooltip3 = "/tip"
function SlashCmdList.RothTooltip(msg)
    msg = strtrim(tostring(msg or ""):lower())

    if msg == "reset" then
        StaticPopup_Show("ROTHTOOLTIP_RESET_SV")
    elseif msg == "npc" then
        OpenCategory(categoryRefs.npc)
    elseif msg == "npc-elements" then
        OpenCategory(categoryRefs.npcElements)
    elseif msg == "player" then
        OpenCategory(categoryRefs.player)
    elseif msg == "player-elements" then
        OpenCategory(categoryRefs.playerElements)
    elseif msg == "spell" then
        OpenCategory(categoryRefs.spell)
    elseif msg == "statusbar" then
        OpenCategory(categoryRefs.statusbar)
    elseif msg == "font" then
        OpenCategory(categoryRefs.font)
    elseif msg == "modules" then
        OpenCategory(categoryRefs.modules)
    elseif msg == "data" then
        OpenCategory(categoryRefs.data)
    else
        OpenCategory(categoryRefs.general)
    end
end
