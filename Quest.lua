local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function ColorBorder(tip, r, g, b)
    if (not addon.db or not addon.db.quest) then return end
    if (addon.db.quest.coloredQuestBorder) then
        LibEvent:trigger("tooltip.style.border.color", tip, r, g, b)
    end
end

--=========================================================
-- Module wrapper
--=========================================================
local M = {}

function M:Init()
    self.__hooked = false

    self.cbSetHyperlink = function(selfTip, link)
        -- hooksecurefunc passes (tooltip, link)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Quest")) then return end
        if (not link or type(link) ~= "string") then return end

        local schema, id = string.match(link, "|?H?(%a+):(%d+):")
        if (schema ~= "quest" or not id) then return end

        -- Level can be SecretValue; keep strict guards.
        local ok, level = pcall(function() return C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id) end)
        if (not ok or addon:IsSecret(level) or type(level) ~= "number") then return end

        local qLevel = level
        if (qLevel < 0) then
            local ok2, pl = pcall(UnitLevel, "player")
            if (not ok2 or addon:IsSecret(pl) or type(pl) ~= "number") then return end
            qLevel = pl
        end

        local ok3, color = pcall(GetQuestDifficultyColor, qLevel)
        if (not ok3 or type(color) ~= "table") then return end
        ColorBorder(selfTip, color.r or 1, color.g or 1, color.b or 1)
    end
end

function M:Enable()
    if (self.__hooked) then return end
    self.__hooked = true

    if (ItemRefTooltip and hooksecurefunc) then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(tip, link)
            -- Protect hook body; errors here would otherwise be global.
            local ok, err = pcall(M.cbSetHyperlink, tip, link)
            if (not ok and addon and addon.DoctorLog) then
                addon:DoctorLog("lua", "Quest:ItemRefTooltip:SetHyperlink", tostring(err), nil)
            end
        end)
    end

    if (addon.MM and addon.MM.Track) then
        addon.MM:Track("Quest", self.cbSetHyperlink, "ItemRefTooltip:SetHyperlink")
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Quest", M)
end
