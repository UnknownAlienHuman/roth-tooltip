local _, addon = ...

-- These frames are created by load-on-demand Blizzard modules or selected
-- third-party addons. Missing globals are expected; only relevant ADDON_LOADED
-- events resynchronize the set.
local EXTRA_FRAME_NAMES = {
    "AtlasLootTooltip",
    "AutoCompleteBox",
    "FriendsTooltip",
    "GeneralDockManagerOverflowButtonList",
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
    if addon:RegisterTooltipFrame(tooltip) then owned[tooltip] = true end
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

    local questScrollFrame = QuestScrollFrame
    local storyTooltip = addon:IsObjectAccessible(questScrollFrame)
        and addon:SafeGet(questScrollFrame, "StoryTooltip") or nil
    RegisterOwned(storyTooltip)
end

local function RelevantAddon(name)
    return type(name) == "string" and (
        name == "RothTooltip"
        or name == "AtlasLootClassic"
        or name == "AtlasLoot"
        or name:find("^Blizzard_PlayerSpells") ~= nil
        or name:find("^Blizzard_Collections") ~= nil
        or name:find("^Blizzard_PetBattle") ~= nil
        or name:find("^Blizzard_Garrison") ~= nil
        or name:find("^Blizzard_FriendsFrame") ~= nil
    )
end

local function OnAddonLoaded(_, name)
    if RelevantAddon(name) then SyncExtraFrames() end
end

local function OnVariableChanged(_, key)
    if key == "general.skinMoreFrames" then SyncExtraFrames() end
end

local M = {}

function M:Init()
    self.cbSync = SyncExtraFrames
    self.cbAddonLoaded = OnAddonLoaded
    self.cbVariable = OnVariableChanged
end

function M:Enable()
    addon.MM:AttachTrigger("SkinFrames", "tooltip:variables:loaded", self.cbSync, "variables-loaded")
    addon.MM:AttachTrigger("SkinFrames", "tooltip:variable:changed", self.cbVariable, "variable-changed")
    addon.MM:AttachEvent("SkinFrames", "PLAYER_LOGIN", self.cbSync, "PLAYER_LOGIN")
    addon.MM:AttachEvent("SkinFrames", "ADDON_LOADED", self.cbAddonLoaded, "ADDON_LOADED")
    if addon.db then SyncExtraFrames() end
end

function M:Disable()
    UnregisterOwned()
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("SkinFrames", M)
