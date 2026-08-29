local _, addon = ...
local Options = addon.Options

if not Options then return end

local MAX_PROFILE_TEXT_BYTES = 262144

local function PrintMessage(message, errorState)
    local color = errorState and "|cffff3333" or "|cff00ffff"
    print("|cffffe4e1[RothTooltip]|r" .. color .. tostring(message or "") .. "|r")
end

local function SerializeProfile()
    if not C_EncodingUtil or type(C_EncodingUtil.SerializeJSON) ~= "function" then return nil end
    local ok, result = pcall(C_EncodingUtil.SerializeJSON, addon.db)
    if ok and type(result) == "string" and #result <= MAX_PROFILE_TEXT_BYTES then return result end
end

local function DeserializeProfile(text)
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    if text == "" or #text > MAX_PROFILE_TEXT_BYTES then return nil end
    if not C_EncodingUtil or type(C_EncodingUtil.DeserializeJSON) ~= "function" then return nil end
    local ok, result = pcall(C_EncodingUtil.DeserializeJSON, text)
    if ok and type(result) == "table" then return result end
end

local function EnsureResetPopup()
    if StaticPopupDialogs["ROTHTOOLTIP_RESET_SV"] then return end
    StaticPopupDialogs["ROTHTOOLTIP_RESET_SV"] = {
        text = "[RothTooltip] Reset account and character profiles, then reload UI?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            RothTooltipDB = nil
            RothTooltipCharacterDB = nil
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function Options:ShowResetPopup()
    EnsureResetPopup()
    StaticPopup_Show("ROTHTOOLTIP_RESET_SV")
end

local function CreateProfileDialog()
    if addon.__RTVariablesDialog and addon:IsObjectAccessible(addon.__RTVariablesDialog) then
        return addon.__RTVariablesDialog
    end
    if InCombatLockdown() then return nil end

    local ok, dialog = pcall(CreateFrame, "Frame", nil, UIParent, "RothTooltipVariablesTemplate")
    if not ok or not addon:IsObjectAccessible(dialog) then return nil end

    dialog:SetFrameStrata("DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    dialog:Hide()

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() dialog:Hide() end)

    dialog.export:SetScript("OnClick", function()
        local serialized = SerializeProfile()
        if not serialized then
            PrintMessage(" JSON export is unavailable or exceeds 256 KiB.", true)
            return
        end
        dialog.textarea.text:SetText(serialized)
        dialog.textarea.text:SetFocus(true)
        dialog.textarea.text:HighlightText()
    end)

    dialog.import:SetScript("OnClick", function()
        local data = DeserializeProfile(dialog.textarea.text:GetText())
        if not data or not addon:ImportProfile(data) then
            PrintMessage(" Invalid or oversized profile payload.", true)
            return
        end
        dialog.textarea.text:SetText("")
        PrintMessage(" Profile imported.")
    end)

    if dialog.reset then
        dialog.reset:SetScript("OnClick", function() Options:ShowResetPopup() end)
    end

    addon.__RTVariablesDialog = dialog
    return dialog
end

function Options:OpenProfileDialog()
    if InCombatLockdown() then
        PrintMessage(" Profile editor cannot be created in combat.", true)
        return
    end
    local dialog = CreateProfileDialog()
    if dialog then dialog:Show() end
end

EnsureResetPopup()
