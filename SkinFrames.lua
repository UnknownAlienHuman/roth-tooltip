local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

-- Extra tooltip-like frames are registered by global name because many are
-- created lazily by load-on-demand Blizzard modules. Missing globals are not
-- errors; each frame is validated again by addon:RegisterTooltipFrame().
local EXTRA_FRAME_NAMES = {
    -- Third-party addon tooltips
    "AtlasLootTooltip",

    -- Blizzard UI frames present across current Retail 12.x modules
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

    -- Garrison/mission table tooltips retained for legacy content
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
    local general = addon.db and addon.db.general
    if type(general) ~= "table" or general.skinMoreFrames ~= true then return end

    for _, name in ipairs(EXTRA_FRAME_NAMES) do
        local frame = _G[name]
        if frame then addon:RegisterTooltipFrame(frame) end
    end

    local questScrollFrame = QuestScrollFrame
    local storyTooltip = questScrollFrame and questScrollFrame.StoryTooltip
    if storyTooltip then addon:RegisterTooltipFrame(storyTooltip) end
end

local M = {}

function M:Init()
    self.cbVarsLoaded = RegisterExtraTooltipFrames
    self.cbLogin = RegisterExtraTooltipFrames
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("SkinFrames", "tooltip:variables:loaded", self.cbVarsLoaded, "tooltip:variables:loaded")
    else
        LibEvent:attachTrigger("tooltip:variables:loaded", self.cbVarsLoaded)
    end

    if addon.MM and addon.MM.AttachEvent then
        addon.MM:AttachEvent("SkinFrames", "PLAYER_LOGIN, ADDON_LOADED", self.cbLogin, "PLAYER_LOGIN/ADDON_LOADED")
    else
        LibEvent:attachEvent("PLAYER_LOGIN", self.cbLogin)
        LibEvent:attachEvent("ADDON_LOADED", self.cbLogin)
    end

    if addon.db then self.cbVarsLoaded() end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("SkinFrames", M)
end
