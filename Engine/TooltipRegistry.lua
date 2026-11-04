-- RothTooltip managed-tooltip registry and lifecycle invalidation.
--
-- This is the sole owner of the managed frame set. Feature modules may request
-- registration/unregistration through this API but do not maintain parallel
-- runtime lists or dispatch paths.

local _, addon = ...
local LibEvent = addon.LibEvent

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
function addon:IsManagedTooltip(tooltip)
    if not self:IsTooltipSafe(tooltip) or type(self.tooltipSet) ~= "table" then return false end
    if self.tooltipSet[tooltip] then return true end
    local parent = self:SafeMethod(tooltip, "GetParent")
    return self:IsObjectAccessible(parent) and self.tooltipSet[parent] == true
end

function addon:RegisterTooltipFrame(tooltip)
    if not self:IsTooltipSafe(tooltip) then return false end
    self.tooltipSet = self.tooltipSet or setmetatable({}, { __mode = "k" })
    if self.tooltipSet[tooltip] then return true end

    self.tooltipSet[tooltip] = true
    LibEvent:trigger("tooltip:init", tooltip)
    return true
end

function addon:UnregisterTooltipFrame(tooltip)
    if not self:CanAccessValue(tooltip) or tooltip == nil then return false end
    if not self.tooltipSet[tooltip] then return true end

    self.tooltipSet[tooltip] = nil
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
    -- Release addon-owned presentation without hiding/replaying native data.
    for tooltip in pairs(addon.tooltipSet) do
        LibEvent:trigger("tooltip:invalidated", tooltip)
    end
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

-- One modifier owner; Unit and LinkID must not both rebuild the same tooltip.
LibEvent:attachEvent("MODIFIER_STATE_CHANGED", function()
    if addon.MM:IsEnabled("Unit") or addon.MM:IsEnabled("LinkID") then
        addon:RefreshManagedTooltipsMatching()
    end
end)
