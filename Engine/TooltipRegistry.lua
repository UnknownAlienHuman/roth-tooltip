-- RothTooltip managed-tooltip registry and refresh coordinator.
--
-- This is the sole owner of the managed frame set and deferred refresh queue.
-- Feature modules request a refresh; this layer coalesces multiple requests for
-- the same visible tooltip into one type-preserving rebuild.

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

local REFRESHABLE_TYPES = {}
if Enum and type(Enum.TooltipDataType) == "table" then
    REFRESHABLE_TYPES[Enum.TooltipDataType.Unit] = true
    REFRESHABLE_TYPES[Enum.TooltipDataType.Item] = true
    REFRESHABLE_TYPES[Enum.TooltipDataType.Spell] = true
end

local refreshQueue = setmetatable({}, { __mode = "k" })
local refreshScheduled = false

addon.tooltipSet = addon.tooltipSet or setmetatable({}, { __mode = "k" })
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

    refreshQueue[tooltip] = nil
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

local function FlushRefreshQueue()
    refreshScheduled = false
    local queued = refreshQueue
    refreshQueue = setmetatable({}, { __mode = "k" })

    for tooltip, reason in pairs(queued) do
        if addon:IsManagedTooltip(tooltip) and addon:SafeMethod(tooltip, "IsShown") == true then
            addon:RefreshTooltipSafe(tooltip, reason)
        end
    end
end

function addon:RequestManagedTooltipRefresh(matchFunc, reason)
    local queued = 0
    self:ForEachVisibleManagedTooltip(function(tooltip)
        local context = self:GetPrimaryTooltipContext(tooltip)
        local matches = type(context) == "table" and REFRESHABLE_TYPES[context.type] == true
        if matches and type(matchFunc) == "function" then
            local ok, result = pcall(matchFunc, tooltip, context)
            matches = ok and self:CanAccessValue(result) and result == true
        end
        if matches then
            refreshQueue[tooltip] = reason or refreshQueue[tooltip] or "refresh"
            queued = queued + 1
        end
    end)

    if queued > 0 and not refreshScheduled then
        refreshScheduled = true
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, FlushRefreshQueue)
        else
            FlushRefreshQueue()
        end
    end
    return queued
end

local function RegisterNames(names, notifyExisting)
    for _, name in ipairs(names) do
        local tooltip = _G[name]
        if addon:IsTooltipSafe(tooltip) then
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

local function IsRelevantLoadOnDemandAddon(name)
    return type(name) == "string" and (
        name == "RothTooltip"
        or name == "AtlasLootClassic"
        or name:find("^Blizzard_PlayerSpells") ~= nil
        or name:find("^Blizzard_Collections") ~= nil
        or name:find("^Blizzard_PetBattle") ~= nil
    )
end

local function HideAndInvalidateVisibleTooltips()
    wipe(refreshQueue)
    addon:ClearTooltipContexts()
    addon:ForEachVisibleManagedTooltip(function(tooltip)
        addon:SafeMethod(tooltip, "Hide")
    end)
end

local function RetryManagedTooltipSetup()
    addon:ForEachManagedTooltip(function(tooltip)
        LibEvent:trigger("tooltip:init", tooltip)
    end)
    addon:RequestManagedTooltipRefresh(nil, "restriction-cleared")
end

local function RefreshLoadedItem(_, itemID, success)
    if not addon:CanAccessValue(itemID) or type(itemID) ~= "number" then return end
    if not addon:CanAccessValue(success) or success ~= true then return end

    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    addon:RequestManagedTooltipRefresh(function(_, context)
        return context.type == itemType and context.itemID == itemID
    end, "GET_ITEM_INFO_RECEIVED")
end

local function RefreshForModifier()
    addon:RequestManagedTooltipRefresh(nil, "MODIFIER_STATE_CHANGED")
end

RegisterKnownTooltips(false)

LibEvent:attachEvent("ADDON_LOADED", function(_, loadedAddon)
    if addon:CanAccessValue(loadedAddon) and IsRelevantLoadOnDemandAddon(loadedAddon) then
        RegisterKnownTooltips(loadedAddon == "RothTooltip")
    end
end)

LibEvent:attachEvent("PLAYER_LOGIN", function()
    RegisterKnownTooltips(true)
end)

LibEvent:attachEvent("PLAYER_ENTERING_WORLD", function()
    RegisterKnownTooltips(true)
    HideAndInvalidateVisibleTooltips()
end)

LibEvent:attachEvent("ADDON_RESTRICTION_STATE_CHANGED, PLAYER_REGEN_DISABLED",
    HideAndInvalidateVisibleTooltips)
LibEvent:attachEvent("PLAYER_REGEN_ENABLED", RetryManagedTooltipSetup)
LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", RefreshLoadedItem)
LibEvent:attachEvent("MODIFIER_STATE_CHANGED", RefreshForModifier)
