-- RothTooltip managed tooltip registry and lifecycle invalidation.

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

addon.tooltips = addon.tooltips or {}
addon.tooltipSet = addon.tooltipSet or setmetatable({}, { __mode = "k" })

local function RegisterNames(names, notifyExisting)
    for _, name in ipairs(names) do
        local tooltip = _G[name]
        if addon:IsObjectAccessible(tooltip) then
            local alreadyRegistered = addon.tooltipSet[tooltip] == true
            addon:RegisterTooltipFrame(tooltip)
            if alreadyRegistered and notifyExisting == true then
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

RegisterKnownTooltips(false)

LibEvent:attachEvent("ADDON_LOADED", function(_, loadedAddon)
    RegisterKnownTooltips(loadedAddon == "RothTooltip")
end)

LibEvent:attachEvent("PLAYER_LOGIN", function()
    RegisterKnownTooltips(true)
end)

LibEvent:attachEvent(
    "ADDON_RESTRICTION_STATE_CHANGED, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, PLAYER_ENTERING_WORLD",
    InvalidateVisibleTooltips
)
