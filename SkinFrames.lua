local _, addon = ...

-- These frames are created by load-on-demand Blizzard modules or third-party
-- addons. Missing globals are expected; ADDON_LOADED resynchronizes the set.
local EXTRA_FRAME_NAMES = {
    "AtlasLootTooltip",
    "AutoCompleteBox",
    "FriendsTooltip",
    "QueueStatusFrame",
    "BattlePetTooltip",
    "PetBattlePrimaryAbilityTooltip",
    "PetBattlePrimaryUnitTooltip",
    "FloatingBattlePetTooltip",
    "FloatingPetBattleAbilityTooltip",
    "GarrisonMissionMechanicTooltip",
    "GarrisonMissionMechanicFollowerCounterTooltip",
    "GarrisonBonusAreaTooltip",
    "FloatingGarrisonFollowerTooltip",
    "FloatingGarrisonFollowerAbilityTooltip",
    "FloatingGarrisonMissionTooltip",
    "GarrisonFollowerAbilityTooltip",
    "GarrisonFollowerTooltip",
}

local owned = setmetatable({}, { __mode = "k" })

local function RegisterOwned(tooltip)
    if not addon:IsTooltipSafe(tooltip) then return end
    local registered, added = addon:RegisterTooltipFrame(tooltip)
    if registered and added then owned[tooltip] = true end
end

local function UnregisterOwned()
    if type(addon.UnregisterTooltipFrame) ~= "function" then return end
    for tooltip in pairs(owned) do
        addon:UnregisterTooltipFrame(tooltip)
        owned[tooltip] = nil
    end
end

local function SyncExtraFrames()
    local enabled = addon.MM:IsEnabled("SkinFrames")
        and addon.db and addon.db.general and addon.db.general.skinMoreFrames == true
    if not enabled then UnregisterOwned() return end

    for _, name in ipairs(EXTRA_FRAME_NAMES) do RegisterOwned(_G[name]) end

    local getStoryTooltip = QuestMapLog_GetStoryTooltip
    local storyTooltip = type(getStoryTooltip) == "function"
        and addon:SafeCall("QuestMapLog_GetStoryTooltip", getStoryTooltip) or nil
    RegisterOwned(storyTooltip)
end

local function OnVariableChanged(_, key)
    if key == "general.skinMoreFrames" then SyncExtraFrames() end
end

local M = {}

function M:Init()
    self.cbSync = SyncExtraFrames
    self.cbVariable = OnVariableChanged
end

function M:Enable()
    addon.MM:AttachTrigger("SkinFrames", "tooltip:variables:loaded", self.cbSync, "variables-loaded")
    addon.MM:AttachTrigger("SkinFrames", "tooltip:variable:changed", self.cbVariable, "variable-changed")
    addon.MM:AttachEvent("SkinFrames", "PLAYER_LOGIN, ADDON_LOADED", self.cbSync, "frame-sync")
    if addon.db then SyncExtraFrames() end
end

function M:Disable()
    UnregisterOwned()
end


addon.MM:RegisterModule("SkinFrames", M)
