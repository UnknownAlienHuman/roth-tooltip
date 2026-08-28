local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function ReadNumber(tbl, key)
    if not CanAccess(tbl) or type(tbl) ~= "table" then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    if not ok or not CanAccess(value) or type(value) ~= "number" then return nil end
    return value
end

local function ColorBorder(tip, r, g, b)
    local questConfig = addon.db and addon.db.quest
    if type(questConfig) ~= "table" or questConfig.coloredQuestBorder ~= true then return end
    if not addon:IsTooltipSafe(tip) then return end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
    LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
end

local function GetQuestLevel(questID)
    local fn = C_QuestLog and C_QuestLog.GetQuestDifficultyLevel
    if type(fn) ~= "function" then return nil end

    local ok, level = pcall(fn, questID)
    if not ok or not CanAccess(level) or type(level) ~= "number" then return nil end
    if level >= 0 then return level end

    ok, level = pcall(UnitLevel, "player")
    if not ok or not CanAccess(level) or type(level) ~= "number" then return nil end
    return level
end

local function OnSetHyperlink(tip, link)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Quest") then return end
    if not addon:IsTooltipSafe(tip) then return end
    if not CanAccess(link) or type(link) ~= "string" or link == "" then return end

    local questIDText = link:match("quest:(%d+)")
    if type(questIDText) ~= "string" then return end
    local questID = tonumber(questIDText)
    if type(questID) ~= "number" then return end

    local level = GetQuestLevel(questID)
    if type(level) ~= "number" then return end

    local ok, color = pcall(GetQuestDifficultyColor, level)
    if not ok or not CanAccess(color) or type(color) ~= "table" then return end

    local r = ReadNumber(color, "r") or 1
    local g = ReadNumber(color, "g") or 1
    local b = ReadNumber(color, "b") or 1
    ColorBorder(tip, r, g, b)
end

local M = {}

function M:Init()
    self.__hooked = false
    self.cbSetHyperlink = OnSetHyperlink
end

function M:Enable()
    if self.__hooked then return end
    self.__hooked = true

    if addon:IsObjectAccessible(ItemRefTooltip) and type(hooksecurefunc) == "function" then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(tip, link)
            local ok, err = pcall(M.cbSetHyperlink, tip, link)
            if not ok and addon.DoctorLog then
                addon:DoctorLog("lua", "Quest:ItemRefTooltip:SetHyperlink", tostring(err), nil)
            end
        end)
    end

    if addon.MM and addon.MM.Track then
        addon.MM:Track("Quest", self.cbSetHyperlink, "ItemRefTooltip:SetHyperlink")
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Quest", M)
end
