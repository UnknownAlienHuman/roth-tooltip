local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local achievementHooks = setmetatable({}, { __mode = "k" })
local globalHooks = {}

local function EscapePattern(text)
    return type(text) == "string" and (text:gsub("(%W)", "%%%1")) or ""
end

local function ModifierRequested()
    return IsShiftKeyDown() == true or IsControlKeyDown() == true or IsAltKeyDown() == true
end

local function ShowID(tooltip, label, value, noBlankLine, force)
    if not addon:IsTooltipSafe(tooltip) then return end
    if type(label) ~= "string" or label == "" then return end
    if type(value) ~= "number" and type(value) ~= "string" then return end

    local general = addon.db and addon.db.general
    local always = type(general) == "table" and general.alwaysShowIdInfo == true
    if force ~= true and not always and not ModifierRequested() then return end

    if not addon:FindLine(tooltip, "^" .. EscapePattern(label) .. ":") then
        if noBlankLine ~= true then addon:SafeMethod(tooltip, "AddLine", " ") end
        addon:SafeMethod(tooltip, "AddLine",
            string.format("%s: |cffffffff%s|r", label, tostring(value)), 0, 1, 0.8)
    end
    LibEvent:trigger("tooltip.linkid", tooltip, label, value, noBlankLine)
end

local function GetContext(tooltip, suppliedContext)
    if type(suppliedContext) == "table" then return suppliedContext end
    return addon:GetPrimaryTooltipContext(tooltip)
end

local function ParseGUIDID(guid)
    if not addon:CanAccessValue(guid) or type(guid) ~= "string" or guid == "" then return nil end
    local objectType, _, _, _, _, idText = strsplit("-", guid)
    local id = type(idText) == "string" and tonumber(idText) or nil
    if type(id) ~= "number" then return nil end

    if objectType == "Creature" or objectType == "Vehicle" or objectType == "Pet" then
        return "NPC", id
    elseif objectType == "GameObject" then
        return "Object", id
    end
end

local function RefreshableContext(context)
    if type(context) ~= "table" then return false end
    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then return false end

    if context.type == dataTypes.Unit then
        return type(context.unitToken) == "string" or type(context.guid) == "string"
    elseif context.type == dataTypes.Item then
        return type(context.hyperlink) == "string" or type(context.itemID) == "number"
    elseif context.type == dataTypes.Spell then
        return type(context.spellID) == "number"
    end
    return false
end

local function ButtonNumber(button, key)
    local value = addon:SafeGet(button, key)
    if type(value) == "number" then return value end
end

local function ShowAchievementID(button)
    if not addon.MM:IsEnabled("LinkID") or not ModifierRequested() then
        local general = addon.db and addon.db.general
        if type(general) ~= "table" or general.alwaysShowIdInfo ~= true then return end
    end

    local achievementID = ButtonNumber(button, "id")
    if not achievementID or not addon:IsTooltipSafe(GameTooltip) then return end
    addon:SafeMethod(GameTooltip, "SetOwner", button, "ANCHOR_RIGHT", 0, -32)
    addon:SafeMethod(GameTooltip, "SetText", "|cffffdd22Achievement:|r " .. achievementID, 0, 1, 0.8)
    addon:SafeMethod(GameTooltip, "Show")
end

local function HookAchievementButtons(frame, buttonTemplate)
    if not addon.MM:IsEnabled("LinkID") or not addon:IsObjectAccessible(frame) then return end
    if buttonTemplate ~= "StatTemplate" and buttonTemplate ~= "AchievementTemplate" then return end

    local buttons = addon:SafeGet(frame, "buttons")
    if type(buttons) ~= "table" then return end
    for _, button in pairs(buttons) do
        if addon:IsObjectAccessible(button) and not achievementHooks[button]
            and addon:CanBindScripts(button) then
            achievementHooks[button] = true
            addon:SafeMethod(button, "HookScript", "OnEnter", ShowAchievementID)
            if buttonTemplate == "AchievementTemplate" then
                addon:SafeMethod(button, "HookScript", "OnLeave", GameTooltip_Hide)
            end
        end
    end
end

local function TryInstallGlobalHooks()
    if type(hooksecurefunc) ~= "function" then return end

    if not globalHooks.achievements and type(HybridScrollFrame_CreateButtons) == "function" then
        hooksecurefunc("HybridScrollFrame_CreateButtons", function(frame, buttonTemplate)
            local ok, errorMessage = pcall(HookAchievementButtons, frame, buttonTemplate)
            if not ok and addon.DoctorLog then
                addon:DoctorLog("lua", "LinkID:HybridScrollFrame_CreateButtons", errorMessage, nil)
            end
        end)
        globalHooks.achievements = true
    end
end

local M = {}

function M:Init()
    self.cbItem = function(_, tooltip, _, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, "Item", type(context) == "table" and context.itemID or nil)
    end

    self.cbSpell = function(_, tooltip, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, "Spell", type(context) == "table" and context.spellID or nil)
    end

    self.cbAura = function(_, tooltip, _, _, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, "Aura", type(context) == "table" and context.spellID or nil, nil, true)
    end

    self.cbGeneric = function(_, tooltip, label, id, _, context)
        if type(context) == "table" and type(context.id) == "number" then id = context.id end
        ShowID(tooltip, label, id)
    end

    self.cbUnit = function(_, tooltip, _, guid, _, context)
        if type(context) == "table" and type(context.guid) == "string" then guid = context.guid end
        local label, id = ParseGUIDID(guid)
        if label then ShowID(tooltip, label, id) end
    end

    self.cbModifier = function()
        addon:RefreshManagedTooltipsMatching(function(_, context)
            return RefreshableContext(context)
        end, "MODIFIER_STATE_CHANGED")
    end

    self.cbTryHooks = TryInstallGlobalHooks
end

function M:Enable()
    addon.MM:AttachTrigger("LinkID", "tooltip:item", self.cbItem, "tooltip:item")
    addon.MM:AttachTrigger("LinkID", "tooltip:spell", self.cbSpell, "tooltip:spell")
    addon.MM:AttachTrigger("LinkID", "tooltip:aura", self.cbAura, "tooltip:aura")
    addon.MM:AttachTrigger("LinkID", "tooltip:unit", self.cbUnit, "tooltip:unit")
    addon.MM:AttachTrigger("LinkID", "tooltip:genericid", self.cbGeneric, "tooltip:genericid")
    addon.MM:AttachEvent("LinkID", "MODIFIER_STATE_CHANGED", self.cbModifier, "MODIFIER_STATE_CHANGED")
    addon.MM:AttachEvent("LinkID", "ADDON_LOADED, PLAYER_LOGIN", self.cbTryHooks, "install-hooks")
    TryInstallGlobalHooks()
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("LinkID", M)
