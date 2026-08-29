local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local achievementHooks = setmetatable({}, { __mode = "k" })
local globalHooks = {}

local function EscapePattern(text)
    return type(text) == "string" and (text:gsub("(%W)", "%%%1")) or ""
end

local function Label(key, fallback)
    return type(addon.Localize) == "function" and addon:Localize(key, fallback)
        or (addon.L and addon.L[key]) or fallback
end

local function ModifierRequested()
    return IsShiftKeyDown() == true or IsControlKeyDown() == true or IsAltKeyDown() == true
end

local function ShowID(tooltip, label, value, noBlankLine)
    if not addon:IsTooltipSafe(tooltip) then return end
    if type(label) ~= "string" or label == "" then return end
    if type(value) ~= "number" and type(value) ~= "string" then return end

    local general = addon.db and addon.db.general
    local always = type(general) == "table" and general.alwaysShowIdInfo == true
    if not always and not ModifierRequested() then return end

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
        return Label("tooltip.npcID", "NPC ID"), id
    elseif objectType == "GameObject" then
        return Label("tooltip.objectID", "Object ID"), id
    end
end

local function GenericLabel(typeID, fallback)
    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) == "table" then
        if typeID == dataTypes.Quest or typeID == dataTypes.QuestPartyProgress then
            return Label("tooltip.questID", "Quest ID")
        elseif typeID == dataTypes.Achievement then
            return Label("tooltip.achievementID", "Achievement ID")
        elseif typeID == dataTypes.Item then
            return Label("tooltip.itemID", "Item ID")
        elseif typeID == dataTypes.Spell then
            return Label("tooltip.spellID", "Spell ID")
        end
    end
    fallback = type(fallback) == "string" and fallback or "ID"
    return fallback:find("ID", 1, true) and fallback or (fallback .. " ID")
end

local function ButtonNumber(button, key)
    local value = addon:SafeGet(button, key)
    if type(value) == "number" then return value end
end

local function InstallButtonHook(button, scriptName, callback, stateKey)
    if not addon:IsObjectAccessible(button) or not addon:CanBindScripts(button) then return false end
    local state = achievementHooks[button]
    if type(state) ~= "table" then state = {}; achievementHooks[button] = state end
    if state[stateKey] then return true end

    local hook = addon:SafeGet(button, "HookScript")
    if type(hook) ~= "function" then return false end
    local ok = pcall(hook, button, scriptName, callback)
    if ok then state[stateKey] = true end
    return ok
end

local function ShowAchievementID(button)
    if not addon.MM:IsEnabled("LinkID") then return end
    local general = addon.db and addon.db.general
    if type(general) ~= "table" or (general.alwaysShowIdInfo ~= true and not ModifierRequested()) then return end

    local achievementID = ButtonNumber(button, "id")
    if not achievementID or not addon:IsTooltipSafe(GameTooltip) then return end
    addon:SafeMethod(GameTooltip, "SetOwner", button, "ANCHOR_RIGHT", 0, -32)
    addon:SafeMethod(GameTooltip, "SetText",
        string.format("|cffffdd22%s:|r %d", Label("tooltip.achievementID", "Achievement ID"), achievementID),
        0, 1, 0.8)
    addon:SafeMethod(GameTooltip, "Show")
end

local function HookAchievementButtons(frame, buttonTemplate)
    if not addon.MM:IsEnabled("LinkID") or not addon:IsObjectAccessible(frame) then return end
    if buttonTemplate ~= "StatTemplate" and buttonTemplate ~= "AchievementTemplate" then return end

    local buttons = addon:SafeGet(frame, "buttons")
    if type(buttons) ~= "table" then return end
    for _, button in pairs(buttons) do
        InstallButtonHook(button, "OnEnter", ShowAchievementID, "enter")
        if buttonTemplate == "AchievementTemplate" then
            InstallButtonHook(button, "OnLeave", GameTooltip_Hide, "leave")
        end
    end
end

local function TryInstallGlobalHooks()
    if globalHooks.achievements or type(hooksecurefunc) ~= "function"
        or type(HybridScrollFrame_CreateButtons) ~= "function" then return end

    local ok = pcall(hooksecurefunc, "HybridScrollFrame_CreateButtons", function(frame, buttonTemplate)
        local success, errorMessage = pcall(HookAchievementButtons, frame, buttonTemplate)
        if not success and addon.DoctorLog then
            addon:DoctorLog("lua", "LinkID:HybridScrollFrame_CreateButtons", errorMessage, nil)
        end
    end)
    if ok then globalHooks.achievements = true end
end

local M = {}

function M:Init()
    self.cbItem = function(_, tooltip, _, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, Label("tooltip.itemID", "Item ID"),
            type(context) == "table" and context.itemID or nil)
    end
    self.cbSpell = function(_, tooltip, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, Label("tooltip.spellID", "Spell ID"),
            type(context) == "table" and context.spellID or nil)
    end
    self.cbAura = function(_, tooltip, _, _, context)
        context = GetContext(tooltip, context)
        ShowID(tooltip, Label("tooltip.auraID", "Aura ID"),
            type(context) == "table" and context.spellID or nil)
    end
    self.cbGeneric = function(_, tooltip, label, id, typeID, context)
        if type(context) == "table" and type(context.id) == "number" then
            id, typeID = context.id, context.type
        end
        ShowID(tooltip, GenericLabel(typeID, label), id)
    end
    self.cbUnit = function(_, tooltip, _, guid, _, context)
        if type(context) == "table" and type(context.guid) == "string" then guid = context.guid end
        local label, id = ParseGUIDID(guid)
        if label then ShowID(tooltip, label, id) end
    end
    self.cbTryHooks = TryInstallGlobalHooks
end

function M:Enable()
    addon.MM:AttachTrigger("LinkID", "tooltip:item", self.cbItem, "tooltip:item")
    addon.MM:AttachTrigger("LinkID", "tooltip:spell", self.cbSpell, "tooltip:spell")
    addon.MM:AttachTrigger("LinkID", "tooltip:aura", self.cbAura, "tooltip:aura")
    addon.MM:AttachTrigger("LinkID", "tooltip:unit", self.cbUnit, "tooltip:unit")
    addon.MM:AttachTrigger("LinkID", "tooltip:genericid", self.cbGeneric, "tooltip:genericid")
    addon.MM:AttachEvent("LinkID", "ADDON_LOADED, PLAYER_LOGIN", self.cbTryHooks, "install-hooks")
    TryInstallGlobalHooks()
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("LinkID", M)
