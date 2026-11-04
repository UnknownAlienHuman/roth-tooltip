local _, addon = ...
local Options = addon.Options

if not Options then return end

local function PrintMessage(message, errorState)
    local color = errorState and "|cffff3333" or "|cff00ffff"
    print("|cffffe4e1[RothTooltip]|r" .. color .. tostring(message or "") .. "|r")
end

local MAX_PROFILE_BYTES = 65536

local function SerializeProfile()
    if not C_EncodingUtil or type(C_EncodingUtil.SerializeJSON) ~= "function" then return nil end
    local ok, result = pcall(C_EncodingUtil.SerializeJSON, { format = "RothTooltip", encodingVersion = 1, profile = addon.db })
    if ok and type(result) == "string" and #result <= MAX_PROFILE_BYTES then return result end
end

local function DeserializeProfile(text)
    if type(text) ~= "string" or text == "" or #text > MAX_PROFILE_BYTES then return nil end
    if not C_EncodingUtil or type(C_EncodingUtil.DeserializeJSON) ~= "function" then return nil end
    local ok, result = pcall(C_EncodingUtil.DeserializeJSON, text)
    if not ok or type(result) ~= "table" then return nil end
    if result.format ~= nil then
        if result.format ~= "RothTooltip" or result.encodingVersion ~= 1 then return nil end
        return result.profile
    end
    return result -- Legacy unwrapped JSON still passes the same strict schema.

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

    local ok, dialog = pcall(CreateFrame, "Frame", nil, UIParent, "RothTooltipVariablesTemplate")
    if not ok or not addon:IsObjectAccessible(dialog) then return nil end

    dialog.textarea.text:SetMaxLetters(MAX_PROFILE_BYTES)
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
            PrintMessage(" JSON export is unavailable.", true)
            return
        end
        dialog.textarea.text:SetText(serialized)
        dialog.textarea.text:SetFocus(true)
        dialog.textarea.text:HighlightText()
    end)

    dialog.import:SetScript("OnClick", function()
        local data = DeserializeProfile(dialog.textarea.text:GetText())
        if not data or not addon:ImportProfile(data) then
            PrintMessage(" Invalid profile payload.", true)
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
    local dialog = CreateProfileDialog()
    if dialog then dialog:Show() end
end

EnsureResetPopup()
