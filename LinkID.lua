local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function IsSecret(v) return addon:IsSecret(v) end

local function ParseGUIDId(guid)
    if (not guid or IsSecret(guid) or type(guid) ~= "string") then return end
    -- Most GUID formats: Type-0-0-0-0-EntryID-SpawnID
    local a, _, _, _, _, id = strsplit("-", guid)
    if (not a or not id) then return end
    local n = tonumber(id)
    if (not n) then return end
    if (a == "Creature" or a == "Vehicle" or a == "Pet") then
        return "NPC", n
    elseif (a == "GameObject") then
        return "Object", n
    end
    return a, n
end

local function GetSafeNumber(value)
    if (not IsSecret(value) and type(value) == "number") then
        return value
    end
    return nil
end

local function EscapePattern(text)
    if (type(text) ~= "string") then
        return ""
    end
    return (text:gsub("(%W)", "%%%1"))
end

local function HasIDLine(tooltip, label)
    if (not tooltip or type(label) ~= "string") then
        return false
    end
    return addon:FindLine(tooltip, "^" .. EscapePattern(label) .. ":") ~= nil
end

local function ShowId(tooltip, name, value, noBlankLine)
    if (not name or not value) then return end
    if (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    local always = addon.db.general.alwaysShowIdInfo
    local kind = tooltip and tooltip.__RT_LastDispatchKind
    if (always or kind == "aura" or IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then
        if (not HasIDLine(tooltip, name)) then
            if (not noBlankLine) then tooltip:AddLine(" ") end
            tooltip:AddLine(format("%s: |cffffffff%s|r", name, value), 0, 1, 0.8)
	            -- No :Show() here; Engine/Layout will resize without forcing a refresh.
        end
        LibEvent:trigger("tooltip.linkid", tooltip, name, value, noBlankLine)
    end
end

local function ResolveItemID(tooltip, context)
    local itemID = GetSafeNumber(context and context.itemID)
    if (not itemID and tooltip) then
        itemID = GetSafeNumber(tooltip.__RT_LastItemID)
    end
    return GetSafeNumber(itemID)
end

local function ResolveSpellID(tip, context)
    local spellID = GetSafeNumber(context and context.spellID)
    if (not spellID and addon.SafeGetSpellID) then
        spellID = GetSafeNumber(addon:SafeGetSpellID(tip))
    end
    return spellID
end

local function HasRefreshableIDContext(context)
    if (GetSafeNumber(context and context.id)) then return true end
    if (GetSafeNumber(context and context.itemID)) then return true end
    if (GetSafeNumber(context and context.spellID)) then return true end
    local guid = context and context.guid
    return (not IsSecret(guid) and type(guid) == "string" and guid ~= "")
end

local function ShowLinkIdInfo(tooltip, context)
    local itemID = ResolveItemID(tooltip, context)
    if (itemID) then
        ShowId(tooltip, "Item", itemID)
    end
end


--=========================================================
-- Module wrapper
--=========================================================
local M = {}

function M:Init()
    self.__hooked = false

    self.cbItem = function(_, tip, link, context)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        ShowLinkIdInfo(tip, context)
    end

    self.cbSpell = function(_, tip, context)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        local spellID = ResolveSpellID(tip, context)
        ShowId(tip, "Spell", spellID)
    end

    self.cbAura = function(_, tip, args, aid, context)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        local spellID = ResolveSpellID(tip, context)
        if (spellID) then
            ShowId(tip, "Aura", spellID)
        end
    end

    self.cbGeneric = function(_, tip, label, id, _, context)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        id = (context and context.id) or id
        if (not tip or not label or not id) then return end
        if (IsSecret(id)) then return end
        ShowId(tip, label, id)
    end

    self.cbUnit = function(_, tip, unit, guid, _, context)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        guid = (context and context.guid) or guid
        local label, id = ParseGUIDId(guid)
        if (label and id and not IsSecret(id)) then
            ShowId(tip, label, id)
        end
    end

    -- Achievement UI
    self.ShowAchievementId = function(btn)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        if (not addon.db or not addon.db.general) then return end
        if ((IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() or addon.db.general.alwaysShowIdInfo) and btn.id) then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT", 0, -32)
            GameTooltip:SetText("|cffffdd22Achievement:|r " .. btn.id, 0, 1, 0.8)
            GameTooltip:Show()
        end
    end

    self.cbQuestLogEnter = function(btn)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        if (btn and btn.questID) then
            ShowId(GameTooltip, "Quest", btn.questID)
        end
    end

    self.cbCreateButtons = function(frame, buttonTemplate)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID")) then return end
        if (not frame or not frame.buttons) then return end
        if (buttonTemplate == "StatTemplate") then
            for _, button in pairs(frame.buttons) do
                if (button and button.HookScript and not button.__RT_AchIdHooked) then
                    button.__RT_AchIdHooked = true
                    button:HookScript("OnEnter", self.ShowAchievementId)
                end
            end
        elseif (buttonTemplate == "AchievementTemplate") then
            for _, button in pairs(frame.buttons) do
                if (button and button.HookScript and not button.__RT_AchIdHooked) then
                    button.__RT_AchIdHooked = true
                    button:HookScript("OnEnter", self.ShowAchievementId)
                    button:HookScript("OnLeave", GameTooltip_Hide)
                end
            end
        end
    end

    self.cbMod = function()
        addon:RefreshManagedTooltipsMatching(function(tip, context)
            return HasRefreshableIDContext(context)
        end, "MODIFIER_STATE_CHANGED")
    end
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("LinkID", "tooltip:item", self.cbItem, "tooltip:item")
        addon.MM:AttachTrigger("LinkID", "tooltip:spell", self.cbSpell, "tooltip:spell")
        addon.MM:AttachTrigger("LinkID", "tooltip:aura", self.cbAura, "tooltip:aura")
        addon.MM:AttachTrigger("LinkID", "tooltip:unit", self.cbUnit, "tooltip:unit")
        addon.MM:AttachTrigger("LinkID", "tooltip:genericid", self.cbGeneric, "tooltip:genericid")
    end

    if (self.__hooked) then return end
    self.__hooked = true

    -- QuestMapLogTitleButton
    if (QuestMapLogTitleButton_OnEnter and hooksecurefunc) then
        hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(btn)
            local ok, err = pcall(M.cbQuestLogEnter, btn)
            if (not ok and addon and addon.DoctorLog) then
                addon:DoctorLog("lua", "LinkID:QuestMapLogTitleButton_OnEnter", tostring(err), nil)
            end
        end)
    end

    -- Achievement UI scroll frames
    if (HybridScrollFrame_CreateButtons and hooksecurefunc) then
        hooksecurefunc("HybridScrollFrame_CreateButtons", function(frame, buttonTemplate)
            local ok, err = pcall(M.cbCreateButtons, frame, buttonTemplate)
            if (not ok and addon and addon.DoctorLog) then
                addon:DoctorLog("lua", "LinkID:HybridScrollFrame_CreateButtons", tostring(err), nil)
            end
        end)
    end

    if (addon.MM and addon.MM.Track) then
        addon.MM:Track("LinkID", self.cbItem, "tooltip:item")
        addon.MM:Track("LinkID", self.cbSpell, "tooltip:spell")
        addon.MM:Track("LinkID", self.cbAura, "tooltip:aura")
        addon.MM:Track("LinkID", self.cbUnit, "tooltip:unit")
        addon.MM:Track("LinkID", self.cbGeneric, "tooltip:genericid")
    end

    if (addon.MM and addon.MM.AttachEvent) then
        addon.MM:AttachEvent("LinkID", "MODIFIER_STATE_CHANGED", self.cbMod, "MODIFIER_STATE_CHANGED")
    else
        LibEvent:attachEvent("MODIFIER_STATE_CHANGED", self.cbMod)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("LinkID", M)
end
