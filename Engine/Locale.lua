-- RothTooltip locale normalization.
--
-- Legacy locale files replace addon.L with partial tables. This finalizer turns
-- that payload into a validated overlay on a stable enUS runtime base. Missing
-- translations fall back to enUS/humanized text; stale removed settings are
-- rejected instead of re-entering runtime state.

local _, addon = ...

local BASE = {
    ["tooltip.itemID"] = "Item ID",
    ["tooltip.spellID"] = "Spell ID",
    ["tooltip.auraID"] = "Aura ID",
    ["tooltip.npcID"] = "NPC ID",
    ["tooltip.objectID"] = "Object ID",
    ["tooltip.questID"] = "Quest ID",
    ["tooltip.achievementID"] = "Achievement ID",
    ["tooltip.itemLevel"] = "Item Level",
    ["tooltip.pveScore"] = "Mythic+ Score",
    ["tooltip.bestKey"] = "Best Mythic+ Key",
    ["tooltip.raidProgress"] = "Raid Progress",
    ["tooltip.spec"] = "Specialization",
    ["tooltip.role"] = "Role",
    ["tooltip.expansion"] = "Expansion",

    ["general.mask"] = "Top mask",
    ["general.background"] = "Background color",
    ["general.borderColor"] = "Border color",
    ["general.scale"] = "Scale",
    ["general.borderSize"] = "Border size",
    ["general.borderCorner"] = "Border style",
    ["general.bgfile"] = "Background texture",
    ["general.statusbarHeight"] = "Status bar height",
    ["general.statusbarPosition"] = "Status bar position",
    ["general.statusbarOffsetX"] = "Status bar horizontal offset",
    ["general.statusbarOffsetY"] = "Status bar vertical offset",
    ["general.statusbarFontSize"] = "Status bar font size",
    ["general.statusbarFont"] = "Status bar font",
    ["general.statusbarFontFlag"] = "Status bar font outline",
    ["general.statusbarTexture"] = "Status bar texture",
    ["general.statusbarColor"] = "Status bar color",
    ["general.statusbarText"] = "Status bar text",
    ["general.statusbarTextFormat"] = "Status bar text format",
    ["general.alwaysShowIdInfo"] = "Always show IDs",
    ["general.skinMoreFrames"] = "Skin additional tooltip frames",
    ["general.SavedVariablesPerCharacter"] = "Use character profile",
    ["general.combatPolicy"] = "Combat policy",

    ["item.coloredItemBorder"] = "Color item border by quality",
    ["item.showItemIcon"] = "Show item icon",
    ["item.showStackCount"] = "Show maximum stack size",
    ["item.showItemID"] = "Show item ID",
    ["item.showExpansionInfo"] = "Show expansion",
    ["quest.coloredQuestBorder"] = "Color quest border by difficulty",
    ["spell.showIcon"] = "Show spell icon",

    ["unit.player.showTarget"] = "Show target",
    ["unit.player.showModel"] = "Show 3D model",
    ["unit.player.showItemLevel"] = "Show item level",
    ["unit.player.showPveScore"] = "Show Mythic+ score",
    ["unit.player.showBestKey"] = "Show best Mythic+ key",
    ["unit.player.showRaidProgress"] = "Show raid progress",
    ["unit.player.grayForDead"] = "Gray dead players",
    ["unit.player.coloredBorder"] = "Player border color",
    ["unit.player.background"] = "Player background",
    ["unit.npc.showTarget"] = "Show target",
    ["unit.npc.showModel"] = "Show 3D model",
    ["unit.npc.grayForDead"] = "Gray dead NPCs",
    ["unit.npc.coloredBorder"] = "NPC border color",
    ["unit.npc.background"] = "NPC background",

    ["dropdown.inherit"] = "inherit",
    ["dropdown.default"] = "default",
    ["dropdown.none"] = "none",
    ["dropdown.show"] = "show",
    ["dropdown.hide"] = "hide",
    ["dropdown.unitOnly"] = "unit only",
    ["dropdown.cursor"] = "cursor",
    ["dropdown.cursorRight"] = "cursor right",
    ["dropdown.auto"] = "automatic",
    ["dropdown.static"] = "static",
    ["dropdown.top"] = "top",
    ["dropdown.bottom"] = "bottom",
    ["dropdown.smooth"] = "smooth",
    ["dropdown.STRICT"] = "STRICT (safest)",
    ["dropdown.BALANCED"] = "BALANCED",
    ["dropdown.AGGRESSIVE"] = "AGGRESSIVE (risk)",
    ["<Drag element to customize the style>"] = "Drag an element to customize the layout",
}

local function Humanize(key)
    local leaf = tostring(key or ""):match("([^.]+)$") or tostring(key or "")
    leaf = leaf:gsub("([a-z])([A-Z])", "%1 %2"):gsub("_", " ")
    return leaf:gsub("^(%a)", string.upper)
end

local function FormatSignature(text)
    if type(text) ~= "string" then return "" end
    local signature = {}
    local index = 1
    while index <= #text do
        local percent = text:find("%%", index, true)
        if not percent then break end
        if text:sub(percent + 1, percent + 1) == "%" then
            index = percent + 2
        else
            local token = text:match("^%%[-+ #0]*%d*%.?%d*[cdeEfgGiouXxsq]", percent)
            if not token then return "INVALID" end
            signature[#signature + 1] = token:sub(-1)
            index = percent + #token
        end
    end
    return table.concat(signature, ",")
end

local function ConfigPathExists(path)
    if type(path) ~= "string" or type(addon.__RT_DefaultDB) ~= "table" then return false end
    local value = addon.__RT_DefaultDB
    for segment in path:gmatch("[^.]+") do
        if type(value) ~= "table" or value[segment] == nil then return false end
        value = value[segment]
    end
    return true
end

local function IsKnownLocaleKey(key)
    if BASE[key] ~= nil or ConfigPathExists(key) then return true end
    return key:find("^dropdown%.") ~= nil
        or key:find("^tooltip%.") ~= nil
        or key:find("^combatPolicy%.desc%.") ~= nil
        or key == "modules.note"
        or key == "<Drag element to customize the style>"
end

local overlay = type(addon.L) == "table" and addon.L or {}
local locale = {}
for key, value in pairs(BASE) do locale[key] = value end

for key, value in pairs(overlay) do
    if type(key) == "string" and type(value) == "string" and IsKnownLocaleKey(key) then
        local baseValue = BASE[key]
        if baseValue == nil or FormatSignature(value) == FormatSignature(baseValue) then
            locale[key] = value
        end
    end
end

setmetatable(locale, {
    __index = function(_, key)
        return BASE[key] or Humanize(key)
    end,
})

addon.L = locale
addon.LocaleBase = BASE

function addon:Localize(key, fallback)
    local value = self.L and self.L[key]
    if type(value) == "string" and value ~= "" then return value end
    if type(fallback) == "string" and fallback ~= "" then return fallback end
    return Humanize(key)
end

function addon:FormatLocalized(key, fallback, ...)
    local formatString = self:Localize(key, fallback)
    local ok, text = pcall(string.format, formatString, ...)
    if ok and type(text) == "string" then return text end
    if type(fallback) == "string" and fallback ~= formatString then
        ok, text = pcall(string.format, fallback, ...)
        if ok and type(text) == "string" then return text end
    end
    return formatString
end
