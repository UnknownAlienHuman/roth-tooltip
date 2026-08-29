local _, addon = ...

local GetItemInfo = C_Item and C_Item.GetItemInfo

local function EscapePattern(text)
    return type(text) == "string" and (text:gsub("(%W)", "%%%1")) or ""
end

local function ResolveItemInfo(tooltip, link, context)
    if type(context) ~= "table" then context = addon:GetPrimaryTooltipContext(tooltip) end
    if type(context) == "table" then
        if type(context.hyperlink) == "string" and context.hyperlink ~= "" then return context.hyperlink end
        if type(context.itemID) == "number" then return context.itemID end
    end
    if type(link) == "string" and link ~= "" then return link end
end

local function OnTooltipItem(_, tooltip, link, context)
    local config = addon.db and addon.db.item
    if type(config) ~= "table" or config.showExpansionInfo ~= true then return end
    if not addon:IsTooltipSafe(tooltip) or type(GetItemInfo) ~= "function" then return end

    local itemInfo = ResolveItemInfo(tooltip, link, context)
    if itemInfo == nil then return end

    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expansionID =
        addon:SafeCall("C_Item.GetItemInfo", GetItemInfo, itemInfo)
    if type(expansionID) ~= "number" or expansionID <= 0 then return end

    local expansionName = _G["EXPANSION_NAME" .. expansionID]
    if type(expansionName) ~= "string" or expansionName == "" then return end
    if addon:FindLine(tooltip, EscapePattern(expansionName)) then return end

    local label = addon.L and addon.L["tooltip.expansion"] or "Expansion"
    addon:SafeMethod(tooltip, "AddLine",
        string.format("|cffffdd22%s:|r |cff64cd3c%s|r", label, expansionName), 0, 1, 0.8)
end

local M = {}

function M:Init()
    self.cbItem = OnTooltipItem
end

function M:Enable()
    addon.MM:AttachTrigger("ExpansionInfo", "tooltip:item", self.cbItem, "tooltip:item")
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("ExpansionInfo", M)
