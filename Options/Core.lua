local addonName, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

addon.Options = addon.Options or {}
local Options = addon.Options

Options.addonName = addonName
Options.categories = Options.categories or {}
Options.EMPTY = Options.EMPTY or {}

local function HumanizeKey(value)
    if type(value) == "number" then return tostring(value) end
    value = tostring(value or "")
    if value == "" then return "" end
    return value:gsub("([a-z])([A-Z])", "%1 %2"):gsub("^(%a)", strupper)
end

addon.L = addon.L or {}
setmetatable(addon.L, {
    __index = function(self, key)
        local segments = { strsplit(".", key) }
        local leaf = segments[#segments]
        return rawget(self, leaf) or HumanizeKey(leaf)
    end,
})
Options.L = addon.L

function Options:SetNestedValue(target, keystring, value)
    if type(target) ~= "table" or type(keystring) ~= "string" or keystring == "" then return false end
    local keys = { strsplit(".", keystring) }
    local scope = target
    for index = 1, #keys - 1 do
        local key = keys[index]
        if type(scope[key]) ~= "table" then scope[key] = {} end
        scope = scope[key]
    end
    scope[keys[#keys]] = value
    return true
end

function Options:GetVariable(keystring, source)
    if keystring == "general.SavedVariablesPerCharacter" then
        return addon:IsUsingCharacterProfile() == true
    end
    if type(keystring) ~= "string" or keystring == "" then return nil end

    local value = source or addon.db
    for _, key in ipairs({ strsplit(".", keystring) }) do
        if type(value) ~= "table" or value[key] == nil then return nil end
        value = value[key]
    end
    return value
end

function Options:ForEachManagedTooltip(callback)
    if type(callback) ~= "function" or type(addon.ForEachManagedTooltip) ~= "function" then return 0 end
    return addon:ForEachManagedTooltip(callback)
end

function Options:TriggerManagedTooltips(eventName, ...)
    if type(eventName) ~= "string" then return end
    local arguments = { ... }
    self:ForEachManagedTooltip(function(tooltip)
        LibEvent:trigger(eventName, tooltip, unpack(arguments))
    end)
end

function Options:RefreshShownTooltips(reason)
    if type(addon.RefreshManagedTooltipsMatching) == "function" then
        return addon:RefreshManagedTooltipsMatching(nil, reason or "settings")
    end
    return 0
end

local function NeedsVisibleRefresh(keystring)
    if keystring == "general.alwaysShowIdInfo" then return true end
    for _, prefix in ipairs({
        "item.",
        "quest.",
        "spell.",
        "unit.",
        "general.visibility.",
        "general.combatPolicy",
        "general.statusbarColor",
        "general.statusbarText",
        "general.statusbarTextFormat",
    }) do
        if keystring:find(prefix, 1, true) == 1 then return true end
    end
    return false
end

function Options:ApplyRuntimeChange(keystring, value)
    local general = addon.db and addon.db.general
    if type(general) ~= "table" then return end

    if keystring == "general.mask" then
        self:TriggerManagedTooltips("tooltip.style.mask", value)
    elseif keystring == "general.scale" then
        self:TriggerManagedTooltips("tooltip.scale", value)
    elseif keystring == "general.background" and type(value) == "table" then
        self:TriggerManagedTooltips("tooltip.style.background", unpack(value))
    elseif keystring == "general.borderColor" and type(value) == "table" then
        self:TriggerManagedTooltips("tooltip.style.border.color", unpack(value))
    elseif keystring == "general.borderSize" then
        self:TriggerManagedTooltips("tooltip.style.border.size", value)
    elseif keystring == "general.borderCorner" then
        self:TriggerManagedTooltips("tooltip.style.border.corner", value)
        if value == "angular" then
            self:TriggerManagedTooltips("tooltip.style.border.size", general.borderSize)
        end
    elseif keystring == "general.bgfile" then
        self:TriggerManagedTooltips("tooltip.style.bgfile", value)
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
        LibEvent:trigger("tooltip.statusbar.position", general.statusbarPosition,
            general.statusbarOffsetX, general.statusbarOffsetY)
    elseif keystring:find("general.statusbarFont", 1, true) == 1 then
        LibEvent:trigger("tooltip.statusbar.font", general.statusbarFont,
            general.statusbarFontSize, general.statusbarFontFlag)
    elseif keystring:find("general.headerFont", 1, true) == 1 then
        self:TriggerManagedTooltips("tooltip.style.font.header", general.headerFont,
            general.headerFontSize, general.headerFontFlag)
    elseif keystring:find("general.bodyFont", 1, true) == 1 then
        self:TriggerManagedTooltips("tooltip.style.font.body", general.bodyFont,
            general.bodyFontSize, general.bodyFontFlag)
    end

    if type(addon.RefreshStatusBar) == "function"
        and keystring:find("general.statusbar", 1, true) == 1 then
        addon:RefreshStatusBar()
    end
end

function Options:SetVariable(keystring, value, target)
    if keystring == "general.SavedVariablesPerCharacter" then
        addon:SelectSavedVariableScope(value == true)
        LibEvent:trigger("tooltip:variable:changed", keystring, value == true)
        return true
    end

    target = target or addon.db
    if not self:SetNestedValue(target, keystring, value) then return false end

    local moduleName = keystring:match("^modules%.(.+)$")
    if moduleName then
        if addon.MM and addon.MM.core and addon.MM.core[moduleName] then
            self:SetNestedValue(target, keystring, true)
            value = true
        end
        if value == true then addon:EnableModule(moduleName)
        else addon:DisableModule(moduleName) end
    end

    self:ApplyRuntimeChange(keystring, value)
    LibEvent:trigger("tooltip:variable:changed", keystring, value)
    if NeedsVisibleRefresh(keystring) then self:RefreshShownTooltips(keystring) end
    return true
end

function Options:MakeSettingName(keystring, suffix)
    local name = "ROTH_TOOLTIP_" .. tostring(keystring or "UNKNOWN"):gsub("[^%w]+", "_"):upper()
    if suffix and suffix ~= "" then
        name = name .. "_" .. tostring(suffix):gsub("[^%w]+", "_"):upper()
    end
    return name
end

function Options:Humanize(value)
    return HumanizeKey(value)
end

function Options:OpenCategory(category)
    if type(self.TryInitialize) == "function" and not self:TryInitialize() then return end
    category = category or self.categories.general
    if category and type(category.GetID) == "function" then Settings.OpenToCategory(category:GetID()) end
end
