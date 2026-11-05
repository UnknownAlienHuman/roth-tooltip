local _, addon = ...
local LibEvent = addon.LibEvent

local function ValidSpellID(value)
    if addon:CanAccessValue(value) and type(value) == "number" and value > 0 then return value end
end

local function ForEachSpellFrame(tooltip, callback)
    if not addon:IsObjectAccessible(tooltip) or type(callback) ~= "function" then return end

    local seen = {}
    local function Visit(frame)
        if not addon:IsObjectAccessible(frame) or seen[frame] then return end
        seen[frame] = true
        callback(frame)
    end

    Visit(tooltip)
    Visit(addon:SafeGet(tooltip, "Tooltip"))
    Visit(addon:SafeGet(tooltip, "ItemTooltip"))
    Visit(addon:SafeGet(tooltip, "FollowerTooltip"))
end

local function ResolveSpellID(tooltip, context)
    if type(context) == "table" then
        local spellID = ValidSpellID(context.spellID)
        if spellID then return spellID end
    end

    local resolved
    ForEachSpellFrame(tooltip, function(frame)
        if resolved then return end
        local frameContext = addon:GetPrimaryTooltipContext(frame)
        resolved = type(frameContext) == "table" and ValidSpellID(frameContext.spellID) or nil
    end)
    return resolved
end

local function PrefixHeader(frame, markup)
    local line = addon:GetLine(frame, 1)
    if not addon:IsObjectAccessible(line) then
        line = addon:SafeGet(frame, "Text")
    end
    if not addon:IsObjectAccessible(line) then return false end

    local text = addon:SafeMethod(line, "GetText")
    if type(text) ~= "string" or text == "" then return false end
    if not text:find("^|T") then
        addon:SafeMethod(line, "SetFormattedText", "%s%s", markup, text)
    end
    return true
end

local function ApplySpellIcon(tooltip, context)
    local config = addon.db and addon.db.spell
    if type(config) ~= "table" or config.showIcon ~= true then return end

    local spellID = ResolveSpellID(tooltip, context)
    if not spellID or not C_Spell or type(C_Spell.GetSpellTexture) ~= "function" then return end
    local texture = addon:SafeCall("C_Spell.GetSpellTexture", C_Spell.GetSpellTexture, spellID)
    if type(texture) ~= "number" and type(texture) ~= "string" then return end

    local markup = string.format("|T%s:20:20:0:0:64:64:4:60:4:60|t ", tostring(texture))
    local applied = false
    ForEachSpellFrame(tooltip, function(frame)
        if not applied and PrefixHeader(frame, markup) then applied = true end
    end)
end

local function OnTooltipSpell(_, tooltip, context)
    if not addon:IsTooltipSafe(tooltip) or not addon:AllowTrigger("spell", tooltip) then return end

    ForEachSpellFrame(tooltip, function(frame)
        if addon:IsManagedTooltip(frame) then addon:ApplyGeneralStyleToTooltip(frame) end
    end)
    ApplySpellIcon(tooltip, context)
end

local M = {}

function M:Init()
    self.cbSpell = OnTooltipSpell
end

function M:Enable()
    addon.MM:AttachTrigger("Spell", "tooltip:spell", self.cbSpell, "tooltip:spell")
end


addon.MM:RegisterModule("Spell", M)
