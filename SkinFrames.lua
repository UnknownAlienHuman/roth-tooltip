local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

-- Extra Blizzard tooltip-like frames (menus, drop-down backdrops, misc UI tooltips).
-- We register by global name because many of these are created lazily.
local EXTRA_FRAME_NAMES = {
    -- Third-party addon tooltips
    "AtlasLootTooltip",
    -- Blizzard UI frames (still active in 12.0)
    "AutoCompleteBox",
    "FriendsTooltip",
    "GeneralDockManagerOverflowButtonList",
    "QueueStatusFrame",
    -- Battle pet tooltips
    "BattlePetTooltip",
    "PetBattlePrimaryAbilityTooltip",
    "PetBattlePrimaryUnitTooltip",
    "FloatingBattlePetTooltip",
    "FloatingPetBattleAbilityTooltip",
    -- Garrison/Mission table tooltips (still used for legacy content)
    "GarrisonMissionMechanicTooltip",
    "GarrisonMissionMechanicFollowerCounterTooltip",
    "GarrisonBonusAreaTooltip",
    "FloatingGarrisonFollowerTooltip",
    "FloatingGarrisonFollowerAbilityTooltip",
    "FloatingGarrisonMissionTooltip",
    "GarrisonFollowerAbilityTooltip",
    "GarrisonFollowerTooltip",
}

local function RegisterExtraTooltipFrames()
    if (not addon.db or not addon.db.general or not addon.db.general.skinMoreFrames) then return end

    for _, name in ipairs(EXTRA_FRAME_NAMES) do
        local f = _G[name]
        if (f) then
            addon:RegisterTooltipFrame(f)
        end
    end

    -- Quest story tooltip is a child and isn't always present.
    if (QuestScrollFrame and QuestScrollFrame.StoryTooltip) then
        addon:RegisterTooltipFrame(QuestScrollFrame.StoryTooltip)
    end
end

local function OnPlayerLoginOrAddonLoaded()
    RegisterExtraTooltipFrames()
end

-- Module wrapper
local M = {}

function M:Init()
    self.cbVarsLoaded = RegisterExtraTooltipFrames
    self.cbLogin = OnPlayerLoginOrAddonLoaded
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("SkinFrames", "tooltip:variables:loaded", self.cbVarsLoaded, "tooltip:variables:loaded")
    else
        LibEvent:attachTrigger("tooltip:variables:loaded", self.cbVarsLoaded)
    end

    -- Some frames appear later; re-register on login/addon loads.
    if (addon.MM and addon.MM.AttachEvent) then
        addon.MM:AttachEvent("SkinFrames", "PLAYER_LOGIN, ADDON_LOADED", self.cbLogin, "PLAYER_LOGIN/ADDON_LOADED")
    else
        LibEvent:attachEvent("PLAYER_LOGIN", self.cbLogin)
        LibEvent:attachEvent("ADDON_LOADED", self.cbLogin)
    end

    -- If enabled after variables are already loaded, run once immediately.
    if (addon.db) then
        self.cbVarsLoaded()
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("SkinFrames", M)
end
