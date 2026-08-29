-- RothTooltip diagnostic UI and slash commands.

local _, addon = ...

local function EnsureFrame()
    if addon.__DoctorFrame and addon:IsObjectAccessible(addon.__DoctorFrame) then
        return addon.__DoctorFrame
    end
    if InCombatLockdown() then return nil end

    local ok, frame = pcall(CreateFrame, "Frame", "RothTooltipDoctorFrame", UIParent, "BackdropTemplate")
    if not ok or not addon:IsObjectAccessible(frame) then return nil end

    frame:SetSize(620, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("RothTooltip Doctor")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -34, 12)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(560)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(editBox)
    frame._editbox = editBox

    frame:Hide()
    addon.__DoctorFrame = frame
    return frame
end

function addon:ShowDoctor(text)
    local frame = EnsureFrame()
    if not frame then
        print("RothTooltip: diagnostic window cannot be created in combat.")
        return false
    end
    frame._editbox:SetText(text or "")
    frame._editbox:HighlightText(0)
    frame:Show()
    return true
end

local function ResolveModuleName(value)
    if type(value) ~= "string" or value == "" or not addon.MM then return nil end
    local wanted = value:lower()
    for moduleName in pairs(addon.MM.modules or {}) do
        if moduleName:lower() == wanted then return moduleName end
    end
end

local function ModuleCommand(action, requested)
    local moduleName = ResolveModuleName(requested)
    if not moduleName then
        print("RothTooltip: unknown module: " .. tostring(requested or ""))
        return
    end

    local success
    if action == "enable" then success = addon:EnableModule(moduleName)
    elseif action == "disable" then success = addon:DisableModule(moduleName)
    else success = addon:ToggleModule(moduleName) end

    if success then
        print(string.format("RothTooltip: module %s: %s", action, moduleName))
    else
        print(string.format("RothTooltip: module %s failed or is not permitted: %s", action, moduleName))
    end
end

local function Command(message)
    message = tostring(message or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local command, rest = message:match("^(%S+)%s*(.*)$")
    command = command and command:lower() or ""

    if command == "" or command == "help" then
        print("RothTooltip: /rtt help | errors | export | modules | enable <name> | disable <name> | toggle <name> | clear")
    elseif command == "errors" or command == "export" then
        local text = addon.DoctorExportText and addon:DoctorExportText() or "(no doctor)"
        local modules = addon.MM and addon.MM.ExportText and ("\n\n" .. addon.MM:ExportText()) or ""
        addon:ShowDoctor(text .. modules)
    elseif command == "modules" then
        addon:ShowDoctor(addon.MM and addon.MM.ExportText and addon.MM:ExportText() or "(no module manager)")
    elseif (command == "enable" or command == "disable" or command == "toggle") and rest ~= "" then
        ModuleCommand(command, rest)
    elseif command == "clear" then
        if addon.DoctorClear then addon:DoctorClear() end
        print("RothTooltip: doctor cleared")
    else
        print("RothTooltip: unknown command. /rtt help")
    end
end

SLASH_ROTHTOOLTIPDOCTOR1 = "/rtt"
SlashCmdList["ROTHTOOLTIPDOCTOR"] = Command
