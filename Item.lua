local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local GetItemInfo = C_Item and C_Item.GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
local GetItemQualityColor = C_Item and C_Item.GetItemQualityColor

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function Call(fn, ...)
    if not CanAccess(fn) or type(fn) ~= "function" then return nil end
    if addon.CanAccessAllValues and not addon:CanAccessAllValues(...) then return nil end

    local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 = pcall(fn, ...)
    if not ok then return nil end
    if not CanAccess(a1) then a1 = nil end
    if not CanAccess(a2) then a2 = nil end
    if not CanAccess(a3) then a3 = nil end
    if not CanAccess(a4) then a4 = nil end
    if not CanAccess(a5) then a5 = nil end
    if not CanAccess(a6) then a6 = nil end
    if not CanAccess(a7) then a7 = nil end
    if not CanAccess(a8) then a8 = nil end
    if not CanAccess(a9) then a9 = nil end
    if not CanAccess(a10) then a10 = nil end
    return a1, a2, a3, a4, a5, a6, a7, a8, a9, a10
end

local function NormalizeItemLink(link)
    if not CanAccess(link) or type(link) ~= "string" or link == "" then return nil end
    return link
end

local function ResolveItemContext(tip, explicitLink, suppliedContext)
    local context = suppliedContext
    if not CanAccess(context) or type(context) ~= "table" then
        context = addon:GetPrimaryTooltipContext(tip)
    end

    local itemLink
    local itemID
    if type(context) == "table" then
        itemLink = NormalizeItemLink(context.hyperlink)
        if CanAccess(context.itemID) and type(context.itemID) == "number" then
            itemID = context.itemID
        end
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
        itemInfo = itemInfo,
        link = itemLink,
        itemID = itemID,
        quality = type(quality) == "number" and quality or 0,
        stackCount = stackCount,
        texture = texture,
    }
end

local function ColorBorder(tip, r, g, b)
    if not addon:IsTooltipSafe(tip) then return end
    local itemConfig = addon.db and addon.db.item
    local general = addon.db and addon.db.general
    if type(itemConfig) ~= "table" or type(general) ~= "table" then return end

    if itemConfig.coloredItemBorder == true then
        LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
    elseif type(general.borderColor) == "table" then
        LibEvent:trigger("tooltip.style.border.color", tip, unpack(general.borderColor))
    end
end

local function ApplyItemIcon(tip, itemData)
    local itemConfig = addon.db and addon.db.item
    if type(itemConfig) ~= "table" or itemConfig.showItemIcon ~= true then return end
    if type(itemData) ~= "table" then return end

    local texture = itemData.texture
    if not CanAccess(texture) or (type(texture) ~= "number" and type(texture) ~= "string") then return end

    local line = addon:GetLine(tip, 1)
    if not addon:IsObjectAccessible(line) then return end
    local text = addon:SafeMethod(line, "GetText")
    if not CanAccess(text) or type(text) ~= "string" or text == "" then return end
    if not text:find("^|T") then
        addon:SafeMethod(
            line,
            "SetFormattedText",
            "|T%s:16:16:0:0:32:32:2:30:2:30|t %s",
            tostring(texture),
            text
        )
    end
end

local function ApplyStackCount(tip, itemData)
    local itemConfig = addon.db and addon.db.item
    if type(itemConfig) ~= "table" or itemConfig.showStackCount ~= true then return end
    if type(itemData) ~= "table" or type(itemData.stackCount) ~= "number" or itemData.stackCount <= 1 then return end

    local line = addon:GetLine(tip, 1)
    if not addon:IsObjectAccessible(line) then return end
    local text = addon:SafeMethod(line, "GetText")
    if not CanAccess(text) or type(text) ~= "string" then return end

    addon:SafeMethod(line, "SetText", text .. string.format(" |cff00eeee/%d|r", itemData.stackCount))
end

local function ApplyItemIDLine(tip, itemData)
    local itemConfig = addon.db and addon.db.item
    if type(itemConfig) ~= "table" or itemConfig.showItemID ~= true then return end
    if type(itemData) ~= "table" or type(itemData.itemID) ~= "number" then return end

    local label = addon.L and addon.L["tooltip.itemID"] or "ItemID"
    if addon:FindLine(tip, "^Item:") or addon:FindLine(tip, "^" .. label .. ":") then return end
    addon:SafeMethod(tip, "AddLine", string.format("%s: |cffffffff%d|r", label, itemData.itemID), 0, 1, 0.8)
end

local function GetQualityColor(quality)
    if type(GetItemQualityColor) ~= "function" then return 1, 1, 1 end
    local r, g, b = Call(GetItemQualityColor, quality)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return 1, 1, 1 end
    return r, g, b
end

local function OnTooltipItem(_, tip, link, context)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Item") then return end
    if not addon:IsTooltipSafe(tip) then return end
    if addon.AllowTrigger and not addon:AllowTrigger("item", tip) then return end

    local started
    if addon.MM and addon.MM.OnCallStart then
        started = addon.MM:OnCallStart("Item", "tooltip:item")
    end

    local itemData = ResolveItemContext(tip, link, context)
    if itemData then
        local r, g, b = GetQualityColor(itemData.quality)
        ColorBorder(tip, r, g, b)
        ApplyStackCount(tip, itemData)
        ApplyItemIcon(tip, itemData)
        ApplyItemIDLine(tip, itemData)
    end

    if addon.MM and addon.MM.OnCallEnd then addon.MM:OnCallEnd("Item", started) end
end

local M = {}

function M:Init()
    self.cbItem = OnTooltipItem
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("Item", "tooltip:item", self.cbItem, "tooltip:item")
    else
        LibEvent:attachTrigger("tooltip:item", self.cbItem)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Item", M)
end
