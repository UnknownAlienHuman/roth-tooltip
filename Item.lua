local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemQualityColor = C_Item.GetItemQualityColor

local function ColorBorder(tip, r, g, b)
    if (addon.db.item.coloredItemBorder) then
        LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
    else
        LibEvent:trigger("tooltip.style.border.color", tip, unpack(addon.db.general.borderColor))
    end
end

local function NormalizeItemLink(link)
    if (addon:IsSecret(link) or type(link) ~= "string" or link == "") then
        return nil
    end
    return link
end

local function ResolveItemContext(tip, context)
    context = context or addon:GetPrimaryTooltipContext(tip)
    local itemLink = NormalizeItemLink(context and context.hyperlink)
    local itemID = context and context.itemID or nil
    if (addon:IsSecret(itemID) or type(itemID) ~= "number") then
        itemID = nil
    end

    local itemInfo = itemLink or itemID
    if (not itemInfo) then
        return nil
    end

    local quality, stackCount, texture
    if (GetItemInfo) then
        local _, resolvedLink, itemQuality, _, _, _, _, itemStackCount, _, itemTexture = GetItemInfo(itemInfo)
        itemLink = NormalizeItemLink(resolvedLink) or itemLink
        if (not addon:IsSecret(itemQuality) and type(itemQuality) == "number") then
            quality = itemQuality
        end
        if (not addon:IsSecret(itemStackCount) and type(itemStackCount) == "number") then
            stackCount = itemStackCount
        end
        if (not addon:IsSecret(itemTexture)) then
            texture = itemTexture
        end
    end

    if (GetItemInfoInstant) then
        local resolvedItemID, _, _, _, icon = GetItemInfoInstant(itemInfo)
        if (not itemID and not addon:IsSecret(resolvedItemID) and type(resolvedItemID) == "number") then
            itemID = resolvedItemID
        end
        if (not texture and not addon:IsSecret(icon)) then
            texture = icon
        end
    end

    return {
        itemInfo = itemInfo,
        link = itemLink,
        itemID = itemID,
        quality = quality or 0,
        stackCount = stackCount,
        texture = texture,
        context = context,
    }
end

local function ItemIcon(tip, itemData)
    if (not addon.db.item.showItemIcon or not itemData or not itemData.texture) then return end
    local line = addon:GetLine(tip,1)
    if (not line) then return end
    local text = line:GetText()
    if (addon:IsSecret(text)) then return end
    if (not strfind(text, "^|T")) then
        line:SetFormattedText("|T%s:16:16:0:0:32:32:2:30:2:30|t %s", itemData.texture, text)
    end
end

local function ItemStackCount(tip, itemData)
    if (addon.db.item.showStackCount) then
        local stackCount = itemData and itemData.stackCount
        if (stackCount and stackCount > 1) then
            local line = addon:GetLine(tip,1)
            if (not line) then return end
            local baseText = line:GetText()
            if (addon:IsSecret(baseText)) then return end
            local text = (baseText or "") .. format(" |cff00eeee/%s|r", stackCount)
            line:SetText(text)
        end
    end
end

-- Item ID line (optional)
-- Note: the addon already has a generic ID module (LinkID.lua) that can show IDs
-- when modifier keys are pressed (or always, via general.alwaysShowIdInfo).
-- This option is meant for users who only want the item ID without enabling the global ID output.
local function ItemIDLine(tip, itemData)
    if (not addon.db.item.showItemID) then return end
    local itemID = itemData and itemData.itemID
    if (addon:IsSecret(itemID) or type(itemID) ~= "number") then return end
    local label = (addon.L and addon.L["tooltip.itemID"]) or "ItemID"
    -- Avoid duplicate output if the global ID module already added a line (e.g. alwaysShowIdInfo)
    -- or if we've already added our own line in this refresh.
    if (addon:FindLine(tip, "^Item:") or addon:FindLine(tip, label .. ":")) then return end
    tip:AddLine(format("%s: |cffffffff%d|r", label, itemID), 0, 1, 0.8)
end

local function OnTooltipItem(self, tip, link, context)
    if (not tip) then return end
    if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Item")) then return end
    if (addon.AllowTrigger and not addon:AllowTrigger("item", tip)) then return end
    local started
    if (addon.MM and addon.MM.OnCallStart) then
        started = addon.MM:OnCallStart("Item", "tooltip:item")
    end

    local itemData = ResolveItemContext(tip, context)
    if (not itemData) then
        if (addon.MM and addon.MM.OnCallEnd) then
            addon.MM:OnCallEnd("Item", started)
        end
        return
    end

    local r, g, b = GetItemQualityColor(itemData.quality)
    if (not r or not g or not b) then
        r, g, b = 1, 1, 1
    end
    ColorBorder(tip, r, g, b)
    ItemStackCount(tip, itemData)
    ItemIcon(tip, itemData)
    ItemIDLine(tip, itemData)

    if (addon.MM and addon.MM.OnCallEnd) then
        addon.MM:OnCallEnd("Item", started)
    end
end

-- Module wrapper
local M = {}

function M:Init()
    self.cbItem = OnTooltipItem
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("Item", "tooltip:item", self.cbItem, "tooltip:item")
    else
        LibEvent:attachTrigger("tooltip:item", self.cbItem)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Item", M)
end
