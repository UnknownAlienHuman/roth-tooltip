local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local GetItemInfo = C_Item and C_Item.GetItemInfo

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function CallGetItemInfo(itemInfo)
    if type(GetItemInfo) ~= "function" then return nil end
    if addon.CanAccessAllValues and not addon:CanAccessAllValues(itemInfo) then return nil end

    local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, expansionID = pcall(GetItemInfo, itemInfo)
    if not ok or not CanAccess(expansionID) or type(expansionID) ~= "number" then return nil end
    return expansionID
end

local function EscapePattern(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("(%W)", "%%%1"))
end

local function ResolveExpansionItemInfo(tooltip, explicitLink, suppliedContext)
    local context = suppliedContext
    if not CanAccess(context) or type(context) ~= "table" then
        context = addon:GetPrimaryTooltipContext(tooltip)
    end

    if type(context) == "table" then
        local hyperlink = context.hyperlink
        if CanAccess(hyperlink) and type(hyperlink) == "string" and hyperlink ~= "" then
            return hyperlink
        end

        local itemID = context.itemID
        if CanAccess(itemID) and type(itemID) == "number" then return itemID end
    end

    if CanAccess(explicitLink) and type(explicitLink) == "string" and explicitLink ~= "" then
        return explicitLink
    end
    return nil
end

local function AddExpansionInfo(tooltip, link, context)
    local itemConfig = addon.db and addon.db.item
    if type(itemConfig) ~= "table" or itemConfig.showExpansionInfo ~= true then return end
    if not addon:IsTooltipSafe(tooltip) then return end

    local itemInfo = ResolveExpansionItemInfo(tooltip, link, context)
    if itemInfo == nil then return end

    local expansionID = CallGetItemInfo(itemInfo)
    if type(expansionID) ~= "number" or expansionID <= 0 then return end

    local expansionName = _G["EXPANSION_NAME" .. expansionID]
    if type(expansionName) ~= "string" or expansionName == "" then return end
    if addon:FindLine(tooltip, EscapePattern(expansionName)) then return end

    local label = addon.L and addon.L["tooltip.expansion"] or "Expansion"
    addon:SafeMethod(
        tooltip,
        "AddLine",
        string.format("|cffffdd22%s:|r |cff64cd3c%s|r", label, expansionName),
        0,
        1,
        0.8
    )
end

local function OnItemInfoReceived(_, itemID, success)
    if not CanAccess(itemID) or type(itemID) ~= "number" then return end
    if not CanAccess(success) or success ~= true then return end

    addon:RefreshManagedTooltipsMatching(function(_, context)
        return type(context) == "table" and context.itemID == itemID
    end, "GET_ITEM_INFO_RECEIVED")
end

local M = {}

function M:Init()
    self.cbItem = function(_, tooltip, link, context)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("ExpansionInfo") then return end
        AddExpansionInfo(tooltip, link, context)
    end
    self.cbItemInfo = OnItemInfoReceived
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("ExpansionInfo", "tooltip:item", self.cbItem, "tooltip:item")
    else
        LibEvent:attachTrigger("tooltip:item", self.cbItem)
    end

    if addon.MM and addon.MM.AttachEvent then
        addon.MM:AttachEvent("ExpansionInfo", "GET_ITEM_INFO_RECEIVED", self.cbItemInfo, "GET_ITEM_INFO_RECEIVED")
    else
        LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", self.cbItemInfo)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("ExpansionInfo", M)
end
