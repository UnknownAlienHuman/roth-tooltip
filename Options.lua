local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
local Options = addon.Options

if not Options then return end

local L = Options.L
local EMPTY = Options.EMPTY
local CUSTOM_COLOR = "__CUSTOM__"

local VISIBILITY = { "show", "hide" }
local COMBAT_VISIBILITY = { "show", "hide", "unitOnly" }
local GENERAL_ANCHORS = { "default", "cursorRight", "cursor", "auto", "static" }
local UNIT_ANCHORS = { "inherit", "default", "cursorRight", "cursor", "static" }
local STATIC_POINTS = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "TOP", "BOTTOM" }
local CURSOR_POINTS = { "BOTTOM", "TOP", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local FILTERS = {
    "none", "ininstance", "incombat", "inraid", "samerealm", "samecrossrealm",
    "inpvp", "inarena", "reaction5", "reaction6",
    "not ininstance", "not incombat", "not inraid", "not samerealm",
    "not samecrossrealm", "not inpvp", "not inarena", "not reaction5", "not reaction6",
}
local ELEMENT_COLORS = {
    "default", "class", "level", "reaction", "itemQuality", "selection", "faction", CUSTOM_COLOR,
}
local COLOR_FUNCTIONS = { "default", "class", "level", "reaction", "itemQuality", "selection", "faction" }
local FONT_FLAGS = { "default", "NORMAL", "OUTLINE", "THINOUTLINE" }
local STATUS_FORMATS = { "health/max", "percent", "health (percent)", "none" }

local PLAYER_ELEMENTS = {
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

local NPC_ELEMENTS = {
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

local media = {
    background = {},
    border = {},
    font = {},
    statusbar = {},
}

local function NormalizeHex(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^#", "")
    if value:match("^%x%x%x%x%x%x$") or value:match("^%x%x%x%x%x%x%x%x$") then
        return strupper(value)
    end
end

local function IsHex(value)
    return NormalizeHex(value) ~= nil
end

local function Clamp(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return math.max(0, math.min(1, value))
end

local function ColorHex(red, green, blue, alpha)
    return ("%02X%02X%02X%02X"):format(
        floor(Clamp(alpha, 1) * 255 + 0.5),
        floor(Clamp(red, 1) * 255 + 0.5),
        floor(Clamp(green, 1) * 255 + 0.5),
        floor(Clamp(blue, 1) * 255 + 0.5)
    )
end

local function SettingsColor(value)
    if type(value) == "table" then
        return ColorHex(value[1] or value.r, value[2] or value.g,
            value[3] or value.b, value[4] or value.a or 1)
    end
    local normalized = NormalizeHex(value)
    if normalized then return #normalized == 6 and "FF" .. normalized or normalized end
    return "FFFFFFFF"
end

local function StoredAlpha(value)
    if type(value) == "table" then return Clamp(value[4] or value.a, 1) end
    local normalized = NormalizeHex(value)
    if normalized and #normalized == 8 then
        return (tonumber(normalized:sub(1, 2), 16) or 255) / 255
    end
    return 1
end

local function RGBHex(value)
    local normalized = NormalizeHex(value)
    if not normalized then return nil end
    return #normalized == 8 and normalized:sub(3, 8) or normalized
end

local function OptionText(value)
    if value == CUSTOM_COLOR then return CUSTOM or "Custom" end
    return L["dropdown." .. tostring(value)] or Options:Humanize(value)
end

local function AddUnique(target, values)
    local seen = {}
    for _, value in ipairs(target) do seen[value] = true end
    for _, value in ipairs(values or EMPTY) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            target[#target + 1] = value
            seen[value] = true
        end
    end
end

local function RebuildMedia()
    for _, values in pairs(media) do wipe(values) end
    AddUnique(media.background, { "gradual", "dark", "alpha", "rock", "marble", "RothTooltipDarkTexture" })
    AddUnique(media.border, { "default", "angular", "RothTooltipDarkFrame" })
    AddUnique(media.font, { "default", "ChatFontNormal", "GameFontNormal", "QuestFont", "CombatLogFont" })
    AddUnique(media.statusbar, { "Interface\\AddOns\\RothTooltip\\texture\\StatusBar" })

    local sharedMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)
    if sharedMedia then
        AddUnique(media.background, sharedMedia:List("background"))
        AddUnique(media.border, sharedMedia:List("border"))
        AddUnique(media.font, sharedMedia:List("font"))
        AddUnique(media.statusbar, sharedMedia:List("statusbar"))
    end
end

local function TextOptions(values)
    return function()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs(values or EMPTY) do container:Add(value, OptionText(value)) end
        return container:GetData()
    end
end

local function AddSection(layout, title, tooltip)
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title, tooltip))
    end
end

local function Checkbox(category, keystring, label, tooltip)
    local default = Options:GetVariable(keystring) == true
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring),
        Settings.VarType.Boolean,
        label,
        default and Settings.Default.True or Settings.Default.False,
        function() return Options:GetVariable(keystring) == true end,
        function(value) Options:SetVariable(keystring, value == true) end
    )
    return Settings.CreateCheckbox(category, setting, tooltip)
end

local function Slider(category, keystring, label, minimum, maximum, step, tooltip, fallback)
    local current = tonumber(Options:GetVariable(keystring)) or fallback or minimum
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring),
        Settings.VarType.Number,
        label,
        current,
        function() return tonumber(Options:GetVariable(keystring)) or current end,
        function(value)
            if step and step < 1 then
                local precision = step < 0.1 and 2 or 1
                value = tonumber(format("%." .. precision .. "f", value)) or value
            else
                value = floor((tonumber(value) or 0) + 0.5)
            end
            Options:SetVariable(keystring, value)
        end
    )
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    if options and options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
        if step and step < 1 then
            local precision = step < 0.1 and 2 or 1
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
                function(value) return format("%." .. precision .. "f", value) end)
        else
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
                function(value) return tostring(floor((tonumber(value) or 0) + 0.5)) end)
        end
    end
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function Dropdown(category, keystring, label, values, tooltip, fallback)
    fallback = fallback or values[1]
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring),
        Settings.VarType.String,
        label,
        tostring(fallback),
        function() return tostring(Options:GetVariable(keystring) or fallback) end,
        function(value) Options:SetVariable(keystring, value) end
    )
    return Settings.CreateDropdown(category, setting, TextOptions(values), tooltip)
end

local function MixedDropdown(category, keystring, label, values, tooltip)
    local fallback = tostring(values[1])
    local options = function()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs(values) do container:Add(tostring(value), OptionText(value)) end
        return container:GetData()
    end
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring),
        Settings.VarType.String,
        label,
        fallback,
        function() return tostring(Options:GetVariable(keystring) or fallback) end,
        function(value) Options:SetVariable(keystring, tonumber(value) or value) end
    )
    return Settings.CreateDropdown(category, setting, options, tooltip)
end

local function ColorSwatch(category, keystring, label, tooltip)
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring, "RGB"),
        Settings.VarType.String,
        label,
        SettingsColor(Options:GetVariable(keystring)),
        function() return SettingsColor(Options:GetVariable(keystring)) end,
        function(value)
            local red, green, blue = addon:GetRGBColor(value)
            Options:SetVariable(keystring, { red, green, blue, StoredAlpha(Options:GetVariable(keystring)) })
        end
    )
    return Settings.CreateColorSwatch(category, setting, tooltip)
end

local function AlphaSlider(category, keystring, label, tooltip)
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring, "ALPHA"),
        Settings.VarType.Number,
        label,
        1,
        function() return StoredAlpha(Options:GetVariable(keystring)) end,
        function(value)
            local current = Options:GetVariable(keystring)
            local red, green, blue = 1, 1, 1
            if type(current) == "table" then
                red, green, blue = tonumber(current[1]) or 1,
                    tonumber(current[2]) or 1, tonumber(current[3]) or 1
            else
                red, green, blue = addon:GetRGBColor(current)
            end
            Options:SetVariable(keystring, { red, green, blue, tonumber(format("%.2f", value)) or value })
        end
    )
    local options = Settings.CreateSliderOptions(0, 1, 0.01)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function ColorBlock(category, keystring, label, tooltip)
    ColorSwatch(category, keystring, label, tooltip)
    AlphaSlider(category, keystring, label .. " Opacity", tooltip)
end

local function ColorFunctionBlock(category, baseKey, label)
    Dropdown(category, baseKey .. ".colorfunc", label .. " Color", COLOR_FUNCTIONS)
    Slider(category, baseKey .. ".alpha", label .. " Opacity", 0, 1, 0.01)
end

local function AnchorBlock(category, baseKey, label, values, layout)
    AddSection(layout, label)
    local position = Dropdown(category, baseKey .. ".position", label .. " Position", values)
    Checkbox(category, baseKey .. ".hiddenInCombat", label .. " Hide in Combat")
    Checkbox(category, baseKey .. ".returnInCombat", label .. " Return in Combat")
    Checkbox(category, baseKey .. ".returnOnUnitFrame", label .. " Return on Unit Frame")

    local function Bind(initializer, predicate)
        if initializer and position and initializer.SetParentInitializer then
            initializer:SetParentInitializer(position, predicate)
        end
    end

    local staticPoint = Dropdown(category, baseKey .. ".p", label .. " Static Point", STATIC_POINTS, nil, "BOTTOMRIGHT")
    local staticX = Slider(category, baseKey .. ".x", label .. " Static X", -1000, 1000, 1, nil, 0)
    local staticY = Slider(category, baseKey .. ".y", label .. " Static Y", -1000, 1000, 1, nil, 0)
    local cursorPoint = Dropdown(category, baseKey .. ".cp", label .. " Cursor Point", CURSOR_POINTS, nil, "BOTTOM")
    local cursorX = Slider(category, baseKey .. ".cx", label .. " Cursor X", -300, 300, 1, nil, 0)
    local cursorY = Slider(category, baseKey .. ".cy", label .. " Cursor Y", -300, 300, 1, nil, 20)

    Bind(staticPoint, function() return Options:GetVariable(baseKey .. ".position") == "static" end)
    Bind(staticX, function() return Options:GetVariable(baseKey .. ".position") == "static" end)
    Bind(staticY, function() return Options:GetVariable(baseKey .. ".position") == "static" end)
    Bind(cursorPoint, function() return Options:GetVariable(baseKey .. ".position") == "cursor" end)
    Bind(cursorX, function()
        local value = Options:GetVariable(baseKey .. ".position")
        return value == "cursor" or value == "auto"
    end)
    Bind(cursorY, function()
        local value = Options:GetVariable(baseKey .. ".position")
        return value == "cursor" or value == "auto"
    end)
end

local function Button(layout, name, text, callback, tooltip)
    if not layout or not CreateSettingsButtonInitializer then return nil end
    local initializer = CreateSettingsButtonInitializer(name or "", text, callback, tooltip, true)
    layout:AddInitializer(initializer)
    return initializer
end

local function ElementColorMode(keystring)
    local value = Options:GetVariable(keystring)
    return IsHex(value) and CUSTOM_COLOR or tostring(value or "default")
end

local function ElementColorDropdown(category, keystring, label)
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring, "MODE"),
        Settings.VarType.String,
        label,
        "default",
        function() return ElementColorMode(keystring) end,
        function(value)
            if value == CUSTOM_COLOR then
                local current = Options:GetVariable(keystring)
                Options:SetVariable(keystring, IsHex(current) and current or "ffffff")
            else
                Options:SetVariable(keystring, value)
            end
        end
    )
    return Settings.CreateDropdown(category, setting, TextOptions(ELEMENT_COLORS))
end

local function ElementColorSwatch(category, keystring, label, parent)
    local setting = Settings.RegisterProxySetting(
        category,
        Options:MakeSettingName(keystring, "CUSTOM"),
        Settings.VarType.String,
        label,
        "FFFFFFFF",
        function() return SettingsColor(Options:GetVariable(keystring)) end,
        function(value) Options:SetVariable(keystring, strlower(RGBHex(value) or "ffffff")) end
    )
    local initializer = Settings.CreateColorSwatch(category, setting)
    if parent and initializer.SetParentInitializer then
        initializer:SetParentInitializer(parent, function() return ElementColorMode(keystring) == CUSTOM_COLOR end)
    end
end

local function EnsureWildcardPopup()
    if StaticPopupDialogs["ROTHTOOLTIP_EDIT_WILDCARD"] then return end
    StaticPopupDialogs["ROTHTOOLTIP_EDIT_WILDCARD"] = {
        text = "Edit Format",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 128,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self)
            local context = Options.wildcardContext
            if self.text and context then self.text:SetText((context.label or "Element") .. " Format") end
            if self.editBox and context then
                self.editBox:SetText(tostring(Options:GetVariable(context.keystring) or ""))
                self.editBox:HighlightText()
                self.editBox:SetFocus()
            end
        end,
        OnAccept = function(self)
            local context = Options.wildcardContext
            if context and self.editBox then Options:SetVariable(context.keystring, self.editBox:GetText()) end
        end,
        OnHide = function(self)
            if self.editBox then self.editBox:SetText("") end
            Options.wildcardContext = nil
        end,
        EditBoxOnEnterPressed = function(self)
            local popup = self:GetParent()
            if popup and popup.button1 then popup.button1:Click() end
        end,
    }
end

local function OpenWildcard(keystring, label)
    EnsureWildcardPopup()
    Options.wildcardContext = { keystring = keystring, label = label }
    StaticPopup_Show("ROTHTOOLTIP_EDIT_WILDCARD")
end

local function ElementControls(category, layout, entries)
    for _, entry in ipairs(entries) do
        AddSection(layout, L[entry.key])
        Checkbox(category, entry.key .. ".enable", L[entry.key])
        if entry.color then
            local mode = ElementColorDropdown(category, entry.key .. ".color", L[entry.key] .. " Color")
            ElementColorSwatch(category, entry.key .. ".color", L[entry.key] .. " Custom Color", mode)
        end
        if entry.filter then Dropdown(category, entry.key .. ".filter", L[entry.key] .. " Filter", FILTERS) end
        if entry.wildcard then
            Button(layout, L[entry.key], "Edit Format",
                function() OpenWildcard(entry.key .. ".wildcard", L[entry.key]) end,
                "Edit the string.format template for this element.")
        end
    end
end

function Options:TryInitialize()
    if self.initialized then return true end
    if addon.__RT_VariablesLoaded ~= true then return false end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return false end

    RebuildMedia()
    EnsureWildcardPopup()

    local root, rootLayout = Settings.RegisterVerticalLayoutCategory("Roth Tooltip")
    self.categories.root = root
    self.categories.general = root

    AddSection(rootLayout, "Appearance")
    Checkbox(root, "general.mask", L["general.mask"])
    Checkbox(root, "general.skinMoreFrames", L["general.skinMoreFrames"])
    ColorBlock(root, "general.background", L["general.background"])
    ColorBlock(root, "general.borderColor", L["general.borderColor"])
    Slider(root, "general.scale", L["general.scale"], 0.5, 4, 0.1)
    Slider(root, "general.borderSize", L["general.borderSize"], 1, 6, 1)
    Dropdown(root, "general.borderCorner", L["general.borderCorner"], media.border)
    Dropdown(root, "general.bgfile", L["general.bgfile"], media.background)
    AnchorBlock(root, "general.anchor", L["general.anchor"], GENERAL_ANCHORS, rootLayout)

    AddSection(rootLayout, "Content")
    Checkbox(root, "item.coloredItemBorder", L["item.coloredItemBorder"])
    Checkbox(root, "item.showItemIcon", L["item.showItemIcon"])
    Checkbox(root, "item.showStackCount", L["item.showStackCount"])
    Checkbox(root, "item.showItemID", L["item.showItemID"])
    Checkbox(root, "item.showExpansionInfo", L["item.showExpansionInfo"])
    Checkbox(root, "quest.coloredQuestBorder", L["quest.coloredQuestBorder"])
    Checkbox(root, "general.alwaysShowIdInfo", L["general.alwaysShowIdInfo"])

    AddSection(rootLayout, "Visibility")
    Dropdown(root, "general.visibility.inCombat", L["general.visibility.inCombat"], COMBAT_VISIBILITY)
    Dropdown(root, "general.visibility.inRaid", L["general.visibility.inRaid"], VISIBILITY)
    Dropdown(root, "general.visibility.inArena", L["general.visibility.inArena"], VISIBILITY)
    Dropdown(root, "general.visibility.bags", L["general.visibility.bags"], VISIBILITY)
    Dropdown(root, "general.visibility.actionBars", L["general.visibility.actionBars"], VISIBILITY)

    AddSection(rootLayout, "Profiles and policy")
    Checkbox(root, "general.SavedVariablesPerCharacter", L["general.SavedVariablesPerCharacter"])
    Dropdown(root, "general.combatPolicy", L["general.combatPolicy"], { "STRICT", "BALANCED", "AGGRESSIVE" })

    local player, playerLayout = Settings.RegisterVerticalLayoutSubcategory(root, "Player")
    self.categories.player = player
    Checkbox(player, "unit.player.showTarget", L["unit.player.showTarget"])
    Checkbox(player, "unit.player.showModel", L["unit.player.showModel"])
    Checkbox(player, "unit.player.showItemLevel", L["unit.player.showItemLevel"])
    Checkbox(player, "unit.player.showPveScore", L["unit.player.showPveScore"])
    Checkbox(player, "unit.player.showBestKey", L["unit.player.showBestKey"])
    Checkbox(player, "unit.player.showRaidProgress", L["unit.player.showRaidProgress"])
    Checkbox(player, "unit.player.grayForDead", L["unit.player.grayForDead"])
    Dropdown(player, "unit.player.coloredBorder", L["unit.player.coloredBorder"], COLOR_FUNCTIONS)
    ColorFunctionBlock(player, "unit.player.background", L["unit.player.background"])
    AnchorBlock(player, "unit.player.anchor", L["unit.player.anchor"], UNIT_ANCHORS, playerLayout)

    local playerElements, playerElementsLayout = Settings.RegisterVerticalLayoutSubcategory(root, "Player Elements")
    self.categories.playerElements = playerElements
    ElementControls(playerElements, playerElementsLayout, PLAYER_ELEMENTS)
    Button(playerElementsLayout, "Player Layout", "Open DIY Layout Editor",
        function() Options:OpenDIYEditor() end,
        "Drag enabled player-tooltip elements to reorder the preview layout.")

    local npc, npcLayout = Settings.RegisterVerticalLayoutSubcategory(root, "NPC")
    self.categories.npc = npc
    Checkbox(npc, "unit.npc.showTarget", L["unit.npc.showTarget"])
    Checkbox(npc, "unit.npc.showModel", L["unit.npc.showModel"])
    Checkbox(npc, "unit.npc.grayForDead", L["unit.npc.grayForDead"])
    Dropdown(npc, "unit.npc.coloredBorder", L["unit.npc.coloredBorder"], COLOR_FUNCTIONS)
    ColorFunctionBlock(npc, "unit.npc.background", L["unit.npc.background"])
    AnchorBlock(npc, "unit.npc.anchor", L["unit.npc.anchor"], UNIT_ANCHORS, npcLayout)

    local npcElements, npcElementsLayout = Settings.RegisterVerticalLayoutSubcategory(root, "NPC Elements")
    self.categories.npcElements = npcElements
    ElementControls(npcElements, npcElementsLayout, NPC_ELEMENTS)

    local statusbar, statusLayout = Settings.RegisterVerticalLayoutSubcategory(root, "Status Bar")
    self.categories.statusbar = statusbar
    AddSection(statusLayout, "Status Bar")
    Checkbox(statusbar, "general.statusbarText", L["general.statusbarText"])
    Slider(statusbar, "general.statusbarHeight", L["general.statusbarHeight"], 0, 24, 1)
    Slider(statusbar, "general.statusbarOffsetX", L["general.statusbarOffsetX"], -50, 50, 1)
    Slider(statusbar, "general.statusbarOffsetY", L["general.statusbarOffsetY"], -50, 50, 1)
    Slider(statusbar, "general.statusbarFontSize", L["general.statusbarFontSize"], 6, 30, 1)
    Dropdown(statusbar, "general.statusbarFont", L["general.statusbarFont"], media.font)
    Dropdown(statusbar, "general.statusbarFontFlag", L["general.statusbarFontFlag"], FONT_FLAGS)
    Dropdown(statusbar, "general.statusbarTexture", L["general.statusbarTexture"], media.statusbar)
    Dropdown(statusbar, "general.statusbarPosition", L["general.statusbarPosition"], { "default", "bottom", "top" })
    Dropdown(statusbar, "general.statusbarColor", L["general.statusbarColor"], { "default", "auto", "smooth" })
    Dropdown(statusbar, "general.statusbarTextFormat", L["general.statusbarTextFormat"], STATUS_FORMATS)

    local spell, spellLayout = Settings.RegisterVerticalLayoutSubcategory(root, "Spell")
    self.categories.spell = spell
    AddSection(spellLayout, "Spell")
    Checkbox(spell, "spell.showIcon", L["spell.showIcon"])

    local fonts, fontLayout = Settings.RegisterVerticalLayoutSubcategory(root, "Fonts")
    self.categories.font = fonts
    AddSection(fontLayout, "Header")
    Dropdown(fonts, "general.headerFont", L["general.headerFont"], media.font)
    MixedDropdown(fonts, "general.headerFontSize", L["general.headerFontSize"],
        { "default", 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24 })
    Dropdown(fonts, "general.headerFontFlag", L["general.headerFontFlag"], FONT_FLAGS)
    AddSection(fontLayout, "Body")
    Dropdown(fonts, "general.bodyFont", L["general.bodyFont"], media.font)
    MixedDropdown(fonts, "general.bodyFontSize", L["general.bodyFontSize"],
        { "default", 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24 })
    Dropdown(fonts, "general.bodyFontFlag", L["general.bodyFontFlag"], FONT_FLAGS)

    local modules, moduleLayout = Settings.RegisterVerticalLayoutSubcategory(root, "Modules")
    self.categories.modules = modules
    AddSection(moduleLayout, "Optional modules")
    for _, moduleName in ipairs({
        "Anchor", "Target", "Unit", "Model", "Item", "Spell",
        "Quest", "LinkID", "Mount", "ExpansionInfo", "SkinFrames",
    }) do
        Checkbox(modules, "modules." .. moduleName, moduleName)
    end

    local data, dataLayout = Settings.RegisterVerticalLayoutSubcategory(root, "Data")
    self.categories.data = data
    AddSection(dataLayout, "Profile Data")
    Button(dataLayout, "Profile Data", "Open Import / Export",
        function() Options:OpenProfileDialog() end,
        "Export or replace the active account/character profile.")
    Button(dataLayout, "Profile Refresh", "Reapply Active Profile",
        function() addon:ReapplyActiveProfile("settings-reapply") end,
        "Re-run migrations, module state and runtime side effects for the active profile.")
    Button(dataLayout, "Profile Reset", RESET or "Reset",
        function() Options:ShowResetPopup() end,
        "Reset account and character profiles, then reload the UI.")

    Settings.RegisterAddOnCategory(root)
    self.initialized = true
    addon.__RT_OptionsInitialized = true
    return true
end

LibEvent:attachTrigger("tooltip:variables:loaded", function()
    Options:TryInitialize()
end)

LibEvent:attachEvent("PLAYER_LOGIN, ADDON_LOADED", function()
    if addon.__RT_VariablesLoaded == true and not Options.initialized then Options:TryInitialize() end
end)

SLASH_RothTooltip1 = "/tinytooltip"
SLASH_RothTooltip2 = "/tt"
SLASH_RothTooltip3 = "/tip"
function SlashCmdList.RothTooltip(message)
    message = strtrim(tostring(message or ""):lower())
    if message == "reset" then
        Options:ShowResetPopup()
    elseif message == "npc" then
        Options:OpenCategory(Options.categories.npc)
    elseif message == "npc-elements" then
        Options:OpenCategory(Options.categories.npcElements)
    elseif message == "player" then
        Options:OpenCategory(Options.categories.player)
    elseif message == "player-elements" then
        Options:OpenCategory(Options.categories.playerElements)
    elseif message == "spell" then
        Options:OpenCategory(Options.categories.spell)
    elseif message == "statusbar" then
        Options:OpenCategory(Options.categories.statusbar)
    elseif message == "font" then
        Options:OpenCategory(Options.categories.font)
    elseif message == "modules" then
        Options:OpenCategory(Options.categories.modules)
    elseif message == "data" then
        Options:OpenCategory(Options.categories.data)
    else
        Options:OpenCategory(Options.categories.general)
    end
end
