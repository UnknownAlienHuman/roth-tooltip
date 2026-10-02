-- RothTooltip managed-tooltip registry and lifecycle invalidation.
--
-- This is the sole owner of the managed frame set. Feature modules may request
-- registration/unregistration through this API but do not maintain parallel
-- runtime lists or dispatch paths.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local BASE_TOOLTIP_NAMES = {
    "GameTooltip",
    "EmbeddedItemTooltip",
    "ItemRefTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "WorldMapTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "NamePlateTooltip",
}

local LOAD_ON_DEMAND_TOOLTIP_NAMES = {
    "SpellBookTooltip",
    "FloatingSpellFlyoutTooltip",
    "PlayerSpellsTooltip",
}

addon.tooltipSet = addon.tooltipSet or setmetatable({}, { __mode = "k" })
-- Retained only as a compatibility/debug snapshot. Runtime iteration uses the
-- weak set, and unregistration compacts this list immediately.
addon.tooltips = addon.tooltips or {}

function addon:IsManagedTooltip(tooltip)
    if not self:IsTooltipSafe(tooltip) or type(self.tooltipSet) ~= "table" then return false end
    if self.tooltipSet[tooltip] then return true end
    local parent = self:SafeMethod(tooltip, "GetParent")
    return self:IsObjectAccessible(parent) and self.tooltipSet[parent] == true
end

function addon:RegisterTooltipFrame(tooltip)
    if not self:IsTooltipSafe(tooltip) then return false end
    self.tooltipSet = self.tooltipSet or setmetatable({}, { __mode = "k" })
    self.tooltips = self.tooltips or {}
    if self.tooltipSet[tooltip] then return true end

    self.tooltipSet[tooltip] = true
    self.tooltips[#self.tooltips + 1] = tooltip
    LibEvent:trigger("tooltip:init", tooltip)
    return true
end

function addon:UnregisterTooltipFrame(tooltip)
    if not self:IsObjectAccessible(tooltip) or type(self.tooltipSet) ~= "table" then return false end
    if not self.tooltipSet[tooltip] then return true end

    self.tooltipSet[tooltip] = nil
    self:SetPrimaryTooltipContext(tooltip, nil)
    for index = #self.tooltips, 1, -1 do
        if self.tooltips[index] == tooltip then table.remove(self.tooltips, index) end
    end
    LibEvent:trigger("tooltip:unregister", tooltip)
    return true
end

function addon:ForEachManagedTooltip(callback)
    if type(callback) ~= "function" or type(self.tooltipSet) ~= "table" then return 0 end
    local count = 0
    for tooltip in pairs(self.tooltipSet) do
        if self:IsTooltipSafe(tooltip) then
            count = count + 1
            callback(tooltip, count)
        end
    end
    return count
end

function addon:ForEachVisibleManagedTooltip(callback)
    if type(callback) ~= "function" then return 0 end
    local count = 0
    self:ForEachManagedTooltip(function(tooltip)
        if self:SafeMethod(tooltip, "IsShown") == true then
            count = count + 1
            callback(tooltip, count)
        end
    end)
    return count
end

local function RegisterNames(names, notifyExisting)
    for _, name in ipairs(names) do
        local tooltip = _G[name]
        if addon:IsTooltipSafe(tooltip) then
            local alreadyRegistered = addon.tooltipSet[tooltip] == true
            addon:RegisterTooltipFrame(tooltip)
            if alreadyRegistered and notifyExisting == true then
                -- Idempotent retry after load-on-demand creation or a temporary
                -- ScriptBindings restriction.
                LibEvent:trigger("tooltip:init", tooltip)
            end
        end
    end
end

local function RegisterKnownTooltips(notifyExisting)
    RegisterNames(BASE_TOOLTIP_NAMES, notifyExisting)
    RegisterNames(LOAD_ON_DEMAND_TOOLTIP_NAMES, notifyExisting)
end

local function InvalidateVisibleTooltips()
    addon:ClearTooltipContexts()
    addon:ForEachVisibleManagedTooltip(function(tooltip)
        addon:SafeMethod(tooltip, "Hide")
    end)
end

local function RefreshLoadedItem(_, itemID, success)
    if not addon:CanAccessValue(itemID) or type(itemID) ~= "number" then return end
    if not addon:CanAccessValue(success) or success ~= true then return end

    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    addon:RefreshManagedTooltipsMatching(function(_, context)
        return type(context) == "table"
            and context.type == itemType
            and context.itemID == itemID
    end, "GET_ITEM_INFO_RECEIVED")
end

RegisterKnownTooltips(false)

LibEvent:attachEvent("ADDON_LOADED", function(_, loadedAddon)
    if addon:CanAccessValue(loadedAddon) and type(loadedAddon) == "string" then
        RegisterKnownTooltips(loadedAddon == "RothTooltip")
    end
end)

LibEvent:attachEvent("PLAYER_LOGIN", function()
    RegisterKnownTooltips(true)
end)

LibEvent:attachEvent("PLAYER_ENTERING_WORLD", function()
    RegisterKnownTooltips(true)
    InvalidateVisibleTooltips()
end)

LibEvent:attachEvent(
    "ADDON_RESTRICTION_STATE_CHANGED, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED",
    InvalidateVisibleTooltips
)

LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", RefreshLoadedItem)
