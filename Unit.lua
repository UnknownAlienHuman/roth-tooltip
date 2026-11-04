local _, addon = ...
local LibEvent = addon.LibEvent
local function IsOrdinaryUnit(unit)
    return addon:CanAccessValue(unit) and type(unit) == "string" and unit ~= ""
        and not addon:IsUnitIdentityRestricted(unit)
end

local function ColorBorder(tooltip, config, raw)
    if not addon:IsTooltipSafe(tooltip) or type(config) ~= "table" then return end
    local mode = config.coloredBorder
    local colorFunction = addon.colorfunc and addon.colorfunc[mode]
    if type(colorFunction) == "function" then
        local ok, red, green, blue = pcall(colorFunction, raw)
        if ok and type(red) == "number" and type(green) == "number" and type(blue) == "number" then
            LibEvent:trigger("tooltip.style.border.color", tooltip, red, green, blue)
            return
        end
    end

    if type(mode) == "string" and mode ~= "default" then
        local red, green, blue = addon:GetRGBColor(mode)
        LibEvent:trigger("tooltip.style.border.color", tooltip, red, green, blue)
        return
    end

    local color = addon.db and addon.db.general and addon.db.general.borderColor
    if type(color) == "table" then
        LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(color))
    end
end

local function ColorBackground(tooltip, config, raw)
    if not addon:IsTooltipSafe(tooltip) or type(config) ~= "table" then return end
    local background = config.background
    if type(background) ~= "table" then return end

    local mode = background.colorfunc
    if mode == "default" or mode == "" or mode == "inherit" then
        local color = addon.db and addon.db.general and addon.db.general.background
        if type(color) == "table" then
            local red, green, blue, alpha = unpack(color)
            if type(background.alpha) == "number" then alpha = background.alpha end
            LibEvent:trigger("tooltip.style.background", tooltip, red, green, blue, alpha)
        end
        return
    end

    local colorFunction = addon.colorfunc and addon.colorfunc[mode]
    if type(colorFunction) ~= "function" then return end
    local ok, red, green, blue = pcall(colorFunction, raw)
    if ok and type(red) == "number" and type(green) == "number" and type(blue) == "number" then
        LibEvent:trigger("tooltip.style.background", tooltip, red, green, blue,
            type(background.alpha) == "number" and background.alpha or 0.8)
    end
end

local function GrayForDead(tooltip, config, unit)
    if type(config) ~= "table" or config.grayForDead ~= true then return end
    if addon:SafeCallBoolean(UnitIsDeadOrGhost, unit) ~= true then return end

    LibEvent:trigger("tooltip.style.border.color", tooltip, 0.6, 0.6, 0.6)
    LibEvent:trigger("tooltip.style.background", tooltip, 0.1, 0.1, 0.1)

    local name = addon:SafeMethod(tooltip, "GetName")
    local lineCount = addon:SafeMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number"
        or lineCount ~= lineCount or lineCount < 0 then return end
    lineCount = math.min(128, math.floor(lineCount))
    for index = 1, lineCount do
        for _, side in ipairs({ "Left", "Right" }) do
            local line = _G[name .. "Text" .. side .. index]
            if addon:IsObjectAccessible(line) then
                local text = addon:SafeMethod(line, "GetText")
                if type(text) == "string" then
                    addon:SafeMethod(line, "SetText", text:gsub("|cff%x%x%x%x%x%x", "|cffaaaaaa"))
                end
                addon:SafeMethod(line, "SetTextColor", 0.7, 0.7, 0.7)
            end
        end
    end
end

local function ShowBigFactionIcon(tooltip, config, raw)
    local element = type(config) == "table" and type(config.elements) == "table"
        and config.elements.factionBig or nil
    local faction = type(raw) == "table" and raw.factionGroup or nil
    local icon = addon:GetBigFactionIcon(tooltip, true)
    if not addon:IsObjectAccessible(icon) then return end

    if type(element) == "table" and element.enable == true
        and (faction == "Alliance" or faction == "Horde") then
        addon:SafeMethod(icon, "SetTexture", "Interface\\Timer\\" .. faction .. "-Logo")
        addon:SafeMethod(icon, "Show")
    else
        addon:SafeMethod(icon, "Hide")
    end
end

local function SetSemanticText(left, right, text)
    if not addon:IsObjectAccessible(left) then return false end
    addon:SafeMethod(left, "SetText", text)
    if addon:IsObjectAccessible(right) then addon:SafeMethod(right, "SetText", nil) end
    return true
end

local function ApplyUnitLayout(tooltip, unit, config, raw)
    local lineTypes = Enum.TooltipDataLineType
    local header, headerRight = addon:FindLineByType(tooltip, lineTypes.UnitName)
    local level, levelRight = addon:FindLineByType(tooltip, lineTypes.UnitLevel)
    if not header or not level then return end -- Preserve unknown/legacy layouts.
    local rows = addon:GetUnitData(unit, config.elements, raw)
    if not rows[1] then return end
    SetSemanticText(header, headerRight, table.concat(rows[1], " "))
    local details = {}
    for index = 2, #rows do details[#details + 1] = table.concat(rows[index], " ") end
    SetSemanticText(level, levelRight, #details > 0 and table.concat(details, "\n") or nil)
    local unitType, unitTypeRight = addon:FindLineByType(tooltip, lineTypes.UnitType)
    SetSemanticText(unitType, unitTypeRight, nil)
    -- A guild line has no stable line type. Only remove an exact ordinary guild
    -- presentation which is already included in the configured custom rows.
    if raw.guildName and config.elements.guildName and config.elements.guildName.enable then
        local name = raw.guildName:gsub("(%W)", "%%%1")
        addon:HideLine(tooltip, "^<" .. name .. ">$")
        addon:HideLine(tooltip, "^" .. name .. "$")
    end
    -- Quest objectives, ownership, threat, NPC titles and unknown rows stay native.
end

local function PresentUnit(tooltip, unit, config, raw, isPlayer)
    ApplyUnitLayout(tooltip, unit, config, raw)
    ColorBorder(tooltip, config, raw)
    ColorBackground(tooltip, config, raw)
    GrayForDead(tooltip, config, unit)
    ShowBigFactionIcon(tooltip, config, raw)
    if isPlayer then addon:AddPlayerStats(tooltip, unit, config) end
end

local function ResolveTooltipUnit(tooltip, unit, guid, context)
    if type(context) == "table" and IsOrdinaryUnit(context.unitToken) then return context.unitToken end
    local contextGUID = type(context) == "table" and context.guid or guid
    return addon:ResolveUnitToken(unit, contextGUID)
end

local function OnTooltipUnit(_, tooltip, unit, guid, _, context)
    if not addon:IsTooltipSafe(tooltip) or not addon:AllowTrigger("unit", tooltip) then return end
    local token = ResolveTooltipUnit(tooltip, unit, guid, context)
    if not IsOrdinaryUnit(token) then return end

    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, token)
    if isPlayer == nil then return end
    local unitConfig = addon.db and addon.db.unit
    local config = type(unitConfig) == "table" and (isPlayer and unitConfig.player or unitConfig.npc) or nil
    if type(config) ~= "table" then return end

    local raw = addon:GetUnitInfo(token, config.elements)
    if type(raw) ~= "table" then return end
    PresentUnit(tooltip, token, config, raw, isPlayer)
end

local M = {}

function M:Enable()
    addon.MM:AttachTrigger("Unit", "tooltip:unit", OnTooltipUnit, "tooltip:unit")
    addon:EnableUnitStats()
end

function M:Disable()
    addon:DisableUnitStats()
end

addon.MM:RegisterModule("Unit", M)
addon.ColorUnitBorder = ColorBorder
addon.ColorUnitBackground = ColorBackground
