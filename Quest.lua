local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function QuestColor(questID)
    if type(questID) ~= "number" then return nil end
    local getLevel = C_QuestLog and C_QuestLog.GetQuestDifficultyLevel
    if type(getLevel) ~= "function" then return nil end

    local level = addon:SafeCall("GetQuestDifficultyLevel", getLevel, questID)
    if type(level) ~= "number" then return nil end
    if level < 0 then level = addon:SafeCall("UnitLevel", UnitLevel, "player") end
    if type(level) ~= "number" then return nil end

    local color = addon:SafeCall("GetQuestDifficultyColor", GetQuestDifficultyColor, level)
    if type(color) ~= "table" then return nil end
    local red = addon:SafeGet(color, "r")
    local green = addon:SafeGet(color, "g")
    local blue = addon:SafeGet(color, "b")
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then return nil end
    return red, green, blue
end

local function IsQuestType(typeID)
    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then return false end
    return typeID == dataTypes.Quest or typeID == dataTypes.QuestPartyProgress
end

local function OnGenericID(_, tooltip, _, id, typeID, context)
    local config = addon.db and addon.db.quest
    if type(config) ~= "table" or config.coloredQuestBorder ~= true
        or not addon:IsTooltipSafe(tooltip) then return end

    if type(context) == "table" then
        id, typeID = context.id, context.type
    end
    if not IsQuestType(typeID) then return end

    local red, green, blue = QuestColor(id)
    if red then LibEvent:trigger("tooltip.style.border.color", tooltip, red, green, blue) end
end

local M = {}
function M:Init() self.cbGeneric = OnGenericID end
function M:Enable()
    addon.MM:AttachTrigger("Quest", "tooltip:genericid", self.cbGeneric, "tooltip:quest")
end
function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Quest", M)
