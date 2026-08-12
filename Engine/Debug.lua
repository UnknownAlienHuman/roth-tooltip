-- RothTooltip Engine: Debug UI
-- Slash commands + export window

local _, addon = ...

local function EnsureFrame()
    if (addon.__DoctorFrame and addon.__DoctorFrame:IsObjectType("Frame")) then
        return addon.__DoctorFrame
    end

    local f = CreateFrame("Frame", "RothTooltipDoctorFrame", UIParent, "BackdropTemplate")
    f:SetSize(620, 480)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0,0,0,0.9)
    f:SetBackdropBorderColor(0.6,0.6,0.6,0.9)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("RothTooltip Doctor")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -34, 12)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetWidth(560)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)

    scroll:SetScrollChild(eb)
    f._editbox = eb

    f:Hide()
    addon.__DoctorFrame = f
    return f
end

function addon:ShowDoctor(text)
    local f = EnsureFrame()
    f._editbox:SetText(text or "")
    f._editbox:HighlightText(0)
    f:Show()
end

local function Cmd(msg)
    msg = msg or ""
    msg = msg:gsub("^%s+", ""):gsub("%s+$", "")

    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if (cmd == "" or cmd == "help") then
        print("RothTooltip: /rtt help | errors | export | modules | enable <name> | disable <name> | toggle <name> | clear")
        return
    end

    if (cmd == "errors" or cmd == "export") then
        local text = addon.DoctorExportText and addon:DoctorExportText() or "(no doctor)"
        local modules = (addon.MM and addon.MM.ExportText) and ("\n\n" .. addon.MM:ExportText()) or ""
        addon:ShowDoctor(text .. modules)
        return
    end

    if (cmd == "modules") then
        local modules = (addon.MM and addon.MM.ExportText) and addon.MM:ExportText() or "(no module manager)"
        addon:ShowDoctor(modules)
        return
    end

    if (cmd == "enable" and rest ~= "") then
        addon:EnableModule(rest)
        print("RothTooltip: module enabled: " .. rest)
        return
    end

    if (cmd == "disable" and rest ~= "") then
        addon:DisableModule(rest)
        print("RothTooltip: module disabled: " .. rest)
        return
    end

    if (cmd == "toggle" and rest ~= "") then
        addon:ToggleModule(rest)
        print("RothTooltip: module toggled: " .. rest)
        return
    end

    if (cmd == "clear") then
        if (addon.DoctorClear) then addon:DoctorClear() end
        print("RothTooltip: doctor cleared")
        return
    end

    print("RothTooltip: unknown command. /rtt help")
end

SLASH_ROTHTOOLTIPDOCTOR1 = "/rtt"
SlashCmdList["ROTHTOOLTIPDOCTOR"] = Cmd
