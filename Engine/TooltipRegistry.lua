-- RothTooltip managed-tooltip registry and lifecycle invalidation.
--
-- This is the sole owner of the managed frame set and cache-driven refresh
-- events. Feature modules consume registered tooltips; they do not maintain
-- parallel frame lists.

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
addon.tooltips = addon.tooltips or setmetatable({}, { __mode = "v" })

local function RegisterNames(names, notifyExisting)
    for _, name in ipairs(names) do
        local tooltip = _G[name]
        if addon:IsTooltipSafe(tooltip) then
            local alreadyRegistered = addon.tooltipSet[tooltip] == true
            addon:RegisterTooltipFrame(tooltip)
            if alreadyRegistered and notifyExisting == true then
                -- Re-run idempotent setup after a load-on-demand or restriction
                -- transition. Style hooks that were temporarily forbidden can
                -- then be installed without adding a second frame owner.
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
