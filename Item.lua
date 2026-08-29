local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local GetItemInfo = C_Item and C_Item.GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
local GetItemQualityColor = C_Item and C_Item.GetItemQualityColor

local function Call(fn, ...)
    return addon:SafeCall("Item", fn, ...)
end

local function EscapePattern(text)
    return type(text) == "string" and (text:gsub("(%W)", "%%%1")) or ""
end

local function NormalizeItemLink(link)
    if addon:CanAccessValue(link) and type(link) == "string" and link ~= "" then return link end
end

local function ResolveItemContext(tooltip, explicitLink, suppliedContext)
    local context = suppliedContext
    if type(context) ~= "table" then context = addon:GetPrimaryTooltipContext(tooltip) end

    local itemLink
    local itemID
    if type(context) == "table" then
        itemLink = NormalizeItemLink(context.hyperlink)
        if type(context.itemID) == "number" then itemID = context.itemID end
    end
    itemLink = itemLink or NormalizeItemLink(explicitLink)

    local itemInfo = itemLink or itemID
    if itemInfo == nil then return nil end

    local quality, stackCount, texture
    if type(GetItemInfo) == "function" then
        local _, resolvedLink, itemQuality, _, _, _, _, itemStackCount, _, itemTexture = Call(GetItemInfo, itemInfo)
        itemLink = NormalizeItemLink(resolvedLink) or itemLink
        if type(itemQuality) == "number" then quality = itemQuality end
        if type(itemStackCount) == "number" then stackCount = itemStackCount end
        if type(itemTexture) == "number" or type(itemTexture) == "string" then texture = itemTexture end
    end

    if type(GetItemInfoInstant) == "function" then
        local resolvedItemID, _, _, _, icon = Call(GetItemInfoInstant, itemInfo)
        if itemID == nil and type(resolvedItemID) == "number" then itemID = resolvedItemID end
        if texture == nil and (type(icon) == "number" or type(icon) == "string") then texture = icon end
    end

    return {
        link = itemLink,
        itemID = itemID,
        quality = type(quality) == "number" and quality or 0,
        stackCount = stackCount,
        texture = texture,
    }
end

local function QualityColor(quality)
    if type(GetItemQualityColor) ~= "function" then return 1, 1, 1 end
    local first, second, third = Call(GetItemQualityColor, quality)
    if type(first) == "table" then
        local red = addon:SafeGet(first, "r") or addon:SafeGet(first, 1)
        local green = addon:SafeGet(first, "g") or addon:SafeGet(first, 2)
        local blue = addon:SafeGet(first, "b") or addon:SafeGet(first, 3)
        if type(red) == "number" and type(green) == "number" and type(blue) == "number" then
            return red, green, blue
        end
    elseif type(first) == "number" and type(second) == "number" and type(third) == "number" then
        return first, second, third
    end
    return 1, 1, 1
end

local function ApplyBorder(tooltip, quality)
    local itemConfig = addon.db and addon.db.item
    local general = addon.db and addon.db.general
    if type(itemConfig) ~= "table" or type(general) ~= "table" then return end

    if itemConfig.coloredItemBorder == true then
        LibEvent:trigger("tooltip.style.border.color", tooltip, QualityColor(quality))
    elseif type(general.borderColor) == "table" then
        LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(general.borderColor))
    end
end

local function ApplyStackCount(tooltip, itemData)
    local config = addon.db and addon.db.item
    if type(config) ~= "table" or config.showStackCount ~= true then return end
    if type(itemData.stackCount) ~= "number" or itemData.stackCount <= 1 then return end

    local line = addon:GetLine(tooltip, 1)
    if not addon:IsObjectAccessible(line) then return end
    local text = addon:SafeMethod(line, "GetText")
    if type(text) ~= "string" or text == "" then return end

    text = text:gsub("%s+|cff00eeee/%d+|r$", "")
    addon:SafeMethod(line, "SetText", text .. string.format(" |cff00eeee/%d|r", itemData.stackCount))
end

local function ApplyItemIcon(tooltip, itemData)
    local config = addon.db and addon.db.item
    if type(config) ~= "table" or config.showItemIcon ~= true then return end
    local texture = itemData.texture
    if type(texture) ~= "number" and type(texture) ~= "string" then return end

    local line = addon:GetLine(tooltip, 1)
    if not addon:IsObjectAccessible(line) then return end
    local text = addon:SafeMethod(line, "GetText")
    if type(text) ~= "string" or text == "" or text:find("^|T") then return end

    addon:SafeMethod(line, "SetFormattedText",
        "|T%s:16:16:0:0:32:32:2:30:2:30|t %s", tostring(texture), text)
end

local function ApplyItemIDLine(tooltip, itemData)
    local config = addon.db and addon.db.item
    if type(config) ~= "table" or config.showItemID ~= true or type(itemData.itemID) ~= "number" then return end

    local label = type(addon.Localize) == "function"
        and addon:Localize("tooltip.itemID", "Item ID") or "Item ID"
    if addon:FindLine(tooltip, "^" .. EscapePattern(label) .. ":") then return end
    addon:SafeMethod(tooltip, "AddLine",
        string.format("%s: |cffffffff%d|r", label, itemData.itemID), 0, 1, 0.8)
end

local function OnTooltipItem(_, tooltip, link, context)
    if not addon:IsTooltipSafe(tooltip) or not addon:AllowTrigger("item", tooltip) then return end
    local itemData = ResolveItemContext(tooltip, link, context)
    if not itemData then return end

    ApplyBorder(tooltip, itemData.quality)
    ApplyStackCount(tooltip, itemData)
    ApplyItemIcon(tooltip, itemData)
    ApplyItemIDLine(tooltip, itemData)
end

local M = {}
function M:Init() self.cbItem = OnTooltipItem end
function M:Enable() addon.MM:AttachTrigger("Item", "tooltip:item", self.cbItem, "tooltip:item") end
function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Item", M)
