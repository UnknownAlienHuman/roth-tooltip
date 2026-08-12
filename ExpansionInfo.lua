local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local GetItemInfo = C_Item.GetItemInfo

local function ResolveExpansionItemInfo(tooltip, context)
    context = context or addon:GetPrimaryTooltipContext(tooltip)
    local hyperlink = context and context.hyperlink
    if (not addon:IsSecret(hyperlink) and type(hyperlink) == "string" and hyperlink ~= "") then
        return context, hyperlink
    end

    local itemID = context and context.itemID
    if (not addon:IsSecret(itemID) and type(itemID) == "number") then
        return context, itemID
    end

    return context, nil
end

-- Добавляет строку с названием эпохи предмета в tooltip.
local function AddExpansionInfo(tooltip, link, context)
    if (not addon.db or not addon.db.item or not addon.db.item.showExpansionInfo) then return end
    if (not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden())) then return end

    local itemInfo
    context, itemInfo = ResolveExpansionItemInfo(tooltip, context)
    if (not itemInfo) then return end

    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expID = GetItemInfo(itemInfo)
    if (not expID or addon:IsSecret(expID) or type(expID) ~= "number" or expID <= 0) then return end

    local expName = _G["EXPANSION_NAME" .. expID]
    if (not expName) then return end

    -- Избегаем дублирования
    if (addon:FindLine(tooltip, expName)) then return end

    tooltip:AddLine(format("|cffffdd22%s:|r |cff64cd3c%s|r",
        (addon.L and addon.L["tooltip.expansion"]) or "Expansion", expName), 0, 1, 0.8)
end

-- Module wrapper
local M = {}

function M:Init()
    self.cbItem = function(_, tooltip, link, context)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("ExpansionInfo")) then return end
        local ok, err = pcall(AddExpansionInfo, tooltip, link, context)
        if (not ok and addon.DoctorLog) then
            addon:DoctorLog("lua", "ExpansionInfo:tooltip:item", tostring(err), nil)
        end
    end
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("ExpansionInfo", "tooltip:item", self.cbItem, "tooltip:item")
    else
        LibEvent:attachTrigger("tooltip:item", self.cbItem)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("ExpansionInfo", M)
end
