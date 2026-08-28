local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local achievementHooks = setmetatable({}, { __mode = "k" })

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function GetSafeNumber(value)
    if not CanAccess(value) or type(value) ~= "number" then return nil end
    return value
end

local function EscapePattern(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("(%W)", "%%%1"))
end

local function ParseGUIDID(guid)
    if not CanAccess(guid) or type(guid) ~= "string" or guid == "" then return nil end

    local objectType, _, _, _, _, idText = strsplit("-", guid)
    if type(objectType) ~= "string" or type(idText) ~= "string" then return nil end
    local id = tonumber(idText)
    if type(id) ~= "number" then return nil end

    if objectType == "Creature" or objectType == "Vehicle" or objectType == "Pet" then
        return "NPC", id
    elseif objectType == "GameObject" then
        return "Object", id
    end
    return nil
end

local function HasIDLine(tooltip, label)
    if not addon:IsTooltipSafe(tooltip) or type(label) ~= "string" then return false end
    return addon:FindLine(tooltip, "^" .. EscapePattern(label) .. ":") ~= nil
end

local function ModifierRequested()
    return IsShiftKeyDown() == true or IsControlKeyDown() == true or IsAltKeyDown() == true
end

local function ShowID(tooltip, label, value, noBlankLine, force)
    if not addon:IsTooltipSafe(tooltip) then return end
    if not CanAccess(label) or type(label) ~= "string" or label == "" then return end
    if not CanAccess(value) or (type(value) ~= "number" and type(value) ~= "string") then return end

    local general = addon.db and addon.db.general
    local always = type(general) == "table" and general.alwaysShowIdInfo == true
    if force ~= true and not always and not ModifierRequested() then return end

    if not HasIDLine(tooltip, label) then
        if noBlankLine ~= true then addon:SafeMethod(tooltip, "AddLine", " ") end
        addon:SafeMethod(
            tooltip,
            "AddLine",
            string.format("%s: |cffffffff%s|r", label, tostring(value)),
            0,
            1,
            0.8
        )
    end
    LibEvent:trigger("tooltip.linkid", tooltip, label, value, noBlankLine)
end

local function GetContext(tooltip, suppliedContext)
    if CanAccess(suppliedContext) and type(suppliedContext) == "table" then return suppliedContext end
    return addon:GetPrimaryTooltipContext(tooltip)
end

local function ResolveItemID(tooltip, context)
    context = GetContext(tooltip, context)
    if type(context) ~= "table" then return nil end
    return GetSafeNumber(context.itemID)
end

local function ResolveSpellID(tooltip, context)
    context = GetContext(tooltip, context)
    if type(context) == "table" then
        local spellID = GetSafeNumber(context.spellID)
        if spellID then return spellID end
    end
    return GetSafeNumber(addon:SafeGetSpellID(tooltip))
end

local function HasRefreshableIDContext(context)
    if not CanAccess(context) or type(context) ~= "table" then return false end
    if GetSafeNumber(context.id) then return true end
    if GetSafeNumber(context.itemID) then return true end
    if GetSafeNumber(context.spellID) then return true end
    return CanAccess(context.guid) and type(context.guid) == "string" and context.guid ~= ""
end

local function GetButtonID(button, key)
    if not addon:IsObjectAccessible(button) then return nil end
    return GetSafeNumber(addon:SafeGet(button, key))
end

local function ShowAchievementID(button)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
    if not ModifierRequested() then
        local general = addon.db and addon.db.general
        if type(general) ~= "table" or general.alwaysShowIdInfo ~= true then return end
    end

    local achievementID = GetButtonID(button, "id")
    if not achievementID or not addon:IsTooltipSafe(GameTooltip) then return end

    addon:SafeMethod(GameTooltip, "SetOwner", button, "ANCHOR_RIGHT", 0, -32)
    addon:SafeMethod(GameTooltip, "SetText", "|cffffdd22Achievement:|r " .. tostring(achievementID), 0, 1, 0.8)
    addon:SafeMethod(GameTooltip, "Show")
end

local function OnQuestLogEnter(button)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
    local questID = GetButtonID(button, "questID")
    if questID then ShowID(GameTooltip, "Quest", questID) end
end

local function HookAchievementButtons(frame, buttonTemplate)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
    if not addon:IsObjectAccessible(frame) or not CanAccess(buttonTemplate) or type(buttonTemplate) ~= "string" then return end
    if buttonTemplate ~= "StatTemplate" and buttonTemplate ~= "AchievementTemplate" then return end

    local buttons = addon:SafeGet(frame, "buttons")
    if type(buttons) ~= "table" then return end

    for _, button in pairs(buttons) do
        if addon:IsObjectAccessible(button) and not achievementHooks[button] then
            achievementHooks[button] = true
            addon:SafeMethod(button, "HookScript", "OnEnter", ShowAchievementID)
            if buttonTemplate == "AchievementTemplate" then
                addon:SafeMethod(button, "HookScript", "OnLeave", GameTooltip_Hide)
            end
        end
    end
end

local M = {}

function M:Init()
    self.__hooked = false

    self.cbItem = function(_, tip, _, context)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
        ShowID(tip, "Item", ResolveItemID(tip, context))
    end

    self.cbSpell = function(_, tip, context)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
        ShowID(tip, "Spell", ResolveSpellID(tip, context))
    end

    self.cbAura = function(_, tip, _, _, context)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
        -- Aura payload itself is never inspected. The ordinary spell ID copied
        -- into the sanitized tooltip context is sufficient.
        ShowID(tip, "Aura", ResolveSpellID(tip, context), nil, true)
    end

    self.cbGeneric = function(_, tip, label, id, _, context)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
        if CanAccess(context) and type(context) == "table" then
            id = GetSafeNumber(context.id) or GetSafeNumber(id)
        else
            id = GetSafeNumber(id)
        end
        ShowID(tip, label, id)
    end

    self.cbUnit = function(_, tip, _, guid, _, context)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("LinkID") then return end
        if CanAccess(context) and type(context) == "table"
            and CanAccess(context.guid) and type(context.guid) == "string" then
            guid = context.guid
        end
        local label, id = ParseGUIDID(guid)
        if label and id then ShowID(tip, label, id) end
    end

    self.cbModifier = function()
        addon:RefreshManagedTooltipsMatching(function(_, context)
            return HasRefreshableIDContext(context)
        end, "MODIFIER_STATE_CHANGED")
    end
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("LinkID", "tooltip:item", self.cbItem, "tooltip:item")
        addon.MM:AttachTrigger("LinkID", "tooltip:spell", self.cbSpell, "tooltip:spell")
        addon.MM:AttachTrigger("LinkID", "tooltip:aura", self.cbAura, "tooltip:aura")
        addon.MM:AttachTrigger("LinkID", "tooltip:unit", self.cbUnit, "tooltip:unit")
        addon.MM:AttachTrigger("LinkID", "tooltip:genericid", self.cbGeneric, "tooltip:genericid")
    end

    if not self.__hooked then
        self.__hooked = true

        if type(QuestMapLogTitleButton_OnEnter) == "function" and type(hooksecurefunc) == "function" then
            hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(button)
                local ok, err = pcall(OnQuestLogEnter, button)
                if not ok and addon.DoctorLog then
                    addon:DoctorLog("lua", "LinkID:QuestMapLogTitleButton_OnEnter", tostring(err), nil)
                end
            end)
        end

        if type(HybridScrollFrame_CreateButtons) == "function" and type(hooksecurefunc) == "function" then
            hooksecurefunc("HybridScrollFrame_CreateButtons", function(frame, buttonTemplate)
                local ok, err = pcall(HookAchievementButtons, frame, buttonTemplate)
                if not ok and addon.DoctorLog then
                    addon:DoctorLog("lua", "LinkID:HybridScrollFrame_CreateButtons", tostring(err), nil)
                end
            end)
        end
    end

    if addon.MM and addon.MM.Track then
        addon.MM:Track("LinkID", self.cbItem, "tooltip:item")
        addon.MM:Track("LinkID", self.cbSpell, "tooltip:spell")
        addon.MM:Track("LinkID", self.cbAura, "tooltip:aura")
        addon.MM:Track("LinkID", self.cbUnit, "tooltip:unit")
        addon.MM:Track("LinkID", self.cbGeneric, "tooltip:genericid")
    end

    if addon.MM and addon.MM.AttachEvent then
        addon.MM:AttachEvent("LinkID", "MODIFIER_STATE_CHANGED", self.cbModifier, "MODIFIER_STATE_CHANGED")
    else
        LibEvent:attachEvent("MODIFIER_STATE_CHANGED", self.cbModifier)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("LinkID", M)
end
