local _, addon = ...


local function EscapePattern(text)
    return type(text) == "string" and (text:gsub("(%W)", "%%%1")) or ""
end

local function ModifierRequested()
    return IsShiftKeyDown() == true or IsControlKeyDown() == true or IsAltKeyDown() == true
end

local function ShowID(tooltip, label, value, noBlankLine, force)
    if not addon:IsTooltipSafe(tooltip) then return end
    if type(label) ~= "string" or label == "" then return end
    if type(value) ~= "number" and type(value) ~= "string" then return end

    local general = addon.db and addon.db.general
    local always = type(general) == "table" and general.alwaysShowIdInfo == true
    if force ~= true and not always and not ModifierRequested() then return end

    if not addon:FindLine(tooltip, "^" .. EscapePattern(label) .. ":") then
        if noBlankLine ~= true then addon:SafeMethod(tooltip, "AddLine", " ") end
        addon:SafeMethod(tooltip, "AddLine",
            string.format("%s: |cffffffff%s|r", label, tostring(value)), 0, 1, 0.8)
    end
end

local function GetContext(tooltip, suppliedContext)
    if type(suppliedContext) == "table" then return suppliedContext end
    return addon:GetPrimaryTooltipContext(tooltip)
end

local function ParseGUIDID(guid)
    if not addon:CanAccessValue(guid) or type(guid) ~= "string" or guid == "" then return nil end
    local objectType, _, _, _, _, idText = strsplit("-", guid)
    local id = type(idText) == "string" and tonumber(idText) or nil
    if type(id) ~= "number" then return nil end

    if objectType == "Creature" or objectType == "Vehicle" or objectType == "Pet" then
        return "NPC", id
    elseif objectType == "GameObject" then
        return "Object", id
    end
end

local M = {}

function M:Init()
    self.cbItem = function(_, tooltip, _, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, "Item", type(context) == "table" and context.itemID or nil, nil,
            addon.db and addon.db.item and addon.db.item.showItemID == true)
    end

    self.cbSpell = function(_, tooltip, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, "Spell", type(context) == "table" and context.spellID or nil)
    end

    self.cbAura = function(_, tooltip, _, _, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, "Aura", type(context) == "table" and context.spellID or nil, nil, true)
    end

    self.cbGeneric = function(_, tooltip, label, id, _, context)
        if type(context) == "table" and type(context.id) == "number" then id = context.id end
        ShowID(tooltip, label, id)
    end

    self.cbUnit = function(_, tooltip, _, guid, _, context)
        if type(context) == "table" and type(context.guid) == "string" then guid = context.guid end
        local label, id = ParseGUIDID(guid)
        if label then ShowID(tooltip, label, id) end
    end

end

function M:Enable()
    addon.MM:AttachTrigger("LinkID", "tooltip:item", self.cbItem, "tooltip:item")
    addon.MM:AttachTrigger("LinkID", "tooltip:spell", self.cbSpell, "tooltip:spell")
    addon.MM:AttachTrigger("LinkID", "tooltip:aura", self.cbAura, "tooltip:aura")
    addon.MM:AttachTrigger("LinkID", "tooltip:unit", self.cbUnit, "tooltip:unit")
    addon.MM:AttachTrigger("LinkID", "tooltip:genericid", self.cbGeneric, "tooltip:genericid")
end


addon.MM:RegisterModule("LinkID", M)
