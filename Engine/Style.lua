-- RothTooltip visual owner for Retail 12.1.
--
-- All bookkeeping lives in weak addon tables. Blizzard tooltip methods are not
-- replaced, potentially restricted GetRegions() results are not enumerated, and
-- new visual children are never created during combat.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
local LibMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BACKGROUND = "Interface\\RaidFrame\\UI-RaidFrame-GroupBg"
local DEFAULT_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local ROTH_BACKGROUND = "Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkTexture"
local ROTH_FRAME = "Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkFrame"

local StyleByTooltip = setmetatable({}, { __mode = "k" })
local FactionIconByTooltip = setmetatable({}, { __mode = "k" })
local HookStateByTooltip = setmetatable({}, { __mode = "k" })
local VisualsHiddenByTooltip = setmetatable({}, { __mode = "k" })

addon.TYPE_NAME = {}
if Enum and type(Enum.TooltipDataType) == "table" then
    for name, typeID in pairs(Enum.TooltipDataType) do
        if type(name) == "string" and type(typeID) == "number" then addon.TYPE_NAME[typeID] = name end
    end
end

local function Accessible(object)
    return addon:IsObjectAccessible(object)
end

local function Hide(object)
    if Accessible(object) then addon:SafeMethod(object, "Hide") end
end

local function CanCreateVisual(parent)
    if InCombatLockdown() or not addon:IsTooltipSafe(parent) then return false end
    local aspect = Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ChangeParent
    if type(aspect) == "number" and addon:HasForbiddenAspects(parent, aspect) then return false end
    return true
end

function addon:GetTooltipStyle(tooltip)
    if not self:IsTooltipSafe(tooltip) then return nil end
    local style = StyleByTooltip[tooltip]
    if Accessible(style) then return style end
    StyleByTooltip[tooltip] = nil
end

function addon:GetBigFactionIcon(tooltip, create)
    if not self:IsTooltipSafe(tooltip) then return nil end
    local icon = FactionIconByTooltip[tooltip]
    if Accessible(icon) then return icon end
    FactionIconByTooltip[tooltip] = nil
    if create ~= true or not CanCreateVisual(tooltip) then return nil end

    local identity = self:SafeGet(tooltip, "identity")
    if tooltip ~= GameTooltip and identity ~= "diy" then return nil end
    icon = self:SafeMethod(tooltip, "CreateTexture", nil, "OVERLAY")
    if not Accessible(icon) then return nil end

    self:SafeMethod(icon, "SetPoint", "TOPRIGHT", tooltip, "TOPRIGHT", 18, 0)
    self:SafeMethod(icon, "SetBlendMode", "ADD")
    self:SafeMethod(icon, "SetScale", 0.24)
    self:SafeMethod(icon, "SetAlpha", 0.40)
    self:SafeMethod(icon, "Hide")
    FactionIconByTooltip[tooltip] = icon
    return icon
end

function addon:NormalizeTooltipFrame(tooltip)
    local style = self:GetTooltipStyle(tooltip)
    if not style then return end
    self:SafeMethod(style, "ClearAllPoints")
    self:SafeMethod(style, "SetAllPoints", tooltip)
end

function addon:ResetTooltipStyleFrame(tooltip)
    self:NormalizeTooltipFrame(tooltip)
end

function addon:ReleaseTooltipStyle(tooltip)
    VisualsHiddenByTooltip[tooltip] = nil
    local style = StyleByTooltip[tooltip]
    if Accessible(style) then self:SafeMethod(style, "Hide") end
    local icon = FactionIconByTooltip[tooltip]
    if Accessible(icon) then self:SafeMethod(icon, "Hide") end
end

local KNOWN_VISUAL_MEMBERS = {
    "NineSlice", "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopOverlay", "BottomOverlay", "LeftOverlay", "RightOverlay",
    "Background", "Bg", "Border", "BackdropFrame", "Backdrop",
}

local NESTED_VISUAL_MEMBERS = {
    "Tooltip", "ItemTooltip", "FollowerTooltip", "BackdropFrame", "Backdrop",
}

local function HideKnownMembers(frame)
    if not Accessible(frame) then return end
    for _, member in ipairs(KNOWN_VISUAL_MEMBERS) do Hide(addon:SafeGet(frame, member)) end
end

local function HideBlizzardVisuals(tooltip)
    if VisualsHiddenByTooltip[tooltip] or not addon:IsManagedTooltip(tooltip) then return end
    HideKnownMembers(tooltip)
    for _, member in ipairs(NESTED_VISUAL_MEMBERS) do HideKnownMembers(addon:SafeGet(tooltip, member)) end

    local getBackdropTexture = addon:SafeGet(tooltip, "GetBackdropTexture")
    if type(getBackdropTexture) == "function" then
        local background = addon:SafeCall("GetBackdropTexture:bg", getBackdropTexture, tooltip, "bg")
        Hide(background)
        local border = addon:SafeCall("GetBackdropTexture:border", getBackdropTexture, tooltip, "border")
        Hide(border)
    end

    addon:SafeMethod(tooltip, "DisableDrawLayer", "BACKGROUND")
    VisualsHiddenByTooltip[tooltip] = true
end

local function CreateBorder(parent, drawLayer)
    if not Accessible(parent) then return nil end
    local border = {
        top = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER"),
        bottom = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER"),
        left = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER"),
        right = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER"),
    }
    for _, texture in pairs(border) do
        if not Accessible(texture) then return nil end
        addon:SafeMethod(texture, "SetTexture", WHITE_TEXTURE)
    end
    return border
end

local function LayoutBorder(parent, border, size)
    if not Accessible(parent) or type(border) ~= "table" then return end
    size = math.max(1, tonumber(size) or 1)
    for _, texture in pairs(border) do addon:SafeMethod(texture, "ClearAllPoints") end

    addon:SafeMethod(border.top, "SetPoint", "TOPLEFT", parent, "TOPLEFT")
    addon:SafeMethod(border.top, "SetPoint", "TOPRIGHT", parent, "TOPRIGHT")
    addon:SafeMethod(border.top, "SetHeight", size)
    addon:SafeMethod(border.bottom, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT")
    addon:SafeMethod(border.bottom, "SetPoint", "BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    addon:SafeMethod(border.bottom, "SetHeight", size)
    addon:SafeMethod(border.left, "SetPoint", "TOPLEFT", parent, "TOPLEFT")
    addon:SafeMethod(border.left, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT")
    addon:SafeMethod(border.left, "SetWidth", size)
    addon:SafeMethod(border.right, "SetPoint", "TOPRIGHT", parent, "TOPRIGHT")
    addon:SafeMethod(border.right, "SetPoint", "BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    addon:SafeMethod(border.right, "SetWidth", size)
end

local function SetBorderColor(border, red, green, blue, alpha)
    if type(border) ~= "table" then return end
    red, green, blue, alpha = tonumber(red) or 1, tonumber(green) or 1,
        tonumber(blue) or 1, tonumber(alpha) or 1
    for _, texture in pairs(border) do
        addon:SafeMethod(texture, "SetVertexColor", red, green, blue, alpha)
    end
end

local function SetBorderTexture(border, texture)
    if type(border) ~= "table" or type(texture) ~= "string" then return end
    for _, region in pairs(border) do addon:SafeMethod(region, "SetTexture", texture) end
    addon:SafeMethod(border.top, "SetHorizTile", true)
    addon:SafeMethod(border.bottom, "SetHorizTile", true)
    addon:SafeMethod(border.left, "SetVertTile", true)
    addon:SafeMethod(border.right, "SetVertTile", true)
end

local function PositionInset(frame, parent, inset)
    if not Accessible(frame) or not Accessible(parent) then return end
    inset = tonumber(inset) or 1
    addon:SafeMethod(frame, "ClearAllPoints")
    addon:SafeMethod(frame, "SetPoint", "TOPLEFT", parent, "TOPLEFT", inset, -inset)
    addon:SafeMethod(frame, "SetPoint", "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
end

local function PositionMask(style, inset)
    if not style or not Accessible(style.mask) then return end
    inset = tonumber(inset) or 3
    addon:SafeMethod(style.mask, "ClearAllPoints")
    addon:SafeMethod(style.mask, "SetPoint", "TOPLEFT", style, "TOPLEFT", inset, -inset)
    addon:SafeMethod(style.mask, "SetPoint", "BOTTOMRIGHT", style, "TOPRIGHT", -inset, -32)
end

local function InstallStyleMethods(style)
    function style:GetBackdrop()
        return self.backdrop
    end

    function style:GetBackdropColor()
        return unpack(self.backgroundColor)
    end

    function style:GetBackdropBorderColor()
        return unpack(self.borderColor)
    end

    function style:SetBackdropColor(red, green, blue, alpha)
        local color = self.backgroundColor
        if type(red) == "number" then color[1] = red end
        if type(green) == "number" then color[2] = green end
        if type(blue) == "number" then color[3] = blue end
        if type(alpha) == "number" then color[4] = alpha end

        if self.useRothBackground then
            addon:SafeMethod(self.bg, "Hide")
            addon:SafeMethod(self.rothBg, "Show")
            addon:SafeMethod(self.rothBg, "SetVertexColor", unpack(color))
        else
            addon:SafeMethod(self.rothBg, "Hide")
            addon:SafeMethod(self.bg, "Show")
            addon:SafeMethod(self.bg, "SetVertexColor", unpack(color))
        end
    end

    function style:SetBackdropBorderColor(red, green, blue, alpha)
        local color = self.borderColor
        if type(red) == "number" then color[1] = red end
        if type(green) == "number" then color[2] = green end
        if type(blue) == "number" then color[3] = blue end
        if type(alpha) == "number" then color[4] = alpha end
        SetBorderColor(self.border, unpack(color))
    end

    function style:SetBackdrop(backdrop)
        if type(backdrop) == "table" then self.backdrop = backdrop end
        backdrop = self.backdrop
        if type(backdrop) ~= "table" then return end

        LayoutBorder(self, self.border, backdrop.edgeSize)
        LayoutBorder(self.inside, self.inside and self.inside.border, 1)
        LayoutBorder(self.outside, self.outside and self.outside.border, 1)
        SetBorderTexture(self.border, type(backdrop.edgeFile) == "string" and backdrop.edgeFile or WHITE_TEXTURE)

        if self.useRothBackground then
            addon:SafeMethod(self.bg, "Hide")
            addon:SafeMethod(self.rothBg, "Show")
        else
            addon:SafeMethod(self.rothBg, "Hide")
            addon:SafeMethod(self.bg, "SetTexture",
                type(backdrop.bgFile) == "string" and backdrop.bgFile or WHITE_TEXTURE)
            addon:SafeMethod(self.bg, "Show")
        end
        self:SetBackdropColor(unpack(self.backgroundColor))
        self:SetBackdropBorderColor(unpack(self.borderColor))
    end
end

local function CreateStyle(tooltip)
    if not CanCreateVisual(tooltip) then return nil end
    local ok, style = pcall(CreateFrame, "Frame", nil, tooltip)
    if not ok or not Accessible(style) then return nil end

    style.backdrop = {
        bgFile = DEFAULT_BACKGROUND,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        edgeFile = DEFAULT_BORDER,
        edgeSize = 14,
    }
    style.backgroundColor = { 0, 0, 0, 0.9 }
    style.borderColor = { 0.6, 0.6, 0.6, 0.8 }
    style.lastBackgroundColor = { 0, 0, 0, 0.9 }
    StyleByTooltip[tooltip] = style

    local level = addon:SafeMethod(tooltip, "GetFrameLevel")
    if type(level) == "number" then addon:SafeMethod(style, "SetFrameLevel", level) end
    addon:SafeMethod(style, "SetAllPoints", tooltip)

    style.bg = addon:SafeMethod(style, "CreateTexture", nil, "BACKGROUND")
    style.rothBg = addon:SafeMethod(style, "CreateTexture", nil, "BACKGROUND")
    style.rothFrame = addon:SafeMethod(style, "CreateTexture", nil, "BORDER")
    if Accessible(style.bg) then addon:SafeMethod(style.bg, "SetAllPoints", style) end
    if Accessible(style.rothBg) then
        addon:SafeMethod(style.rothBg, "SetTexture", ROTH_BACKGROUND)
        addon:SafeMethod(style.rothBg, "SetAllPoints", style)
        addon:SafeMethod(style.rothBg, "SetTexCoord", 0.0875, 0.9065, 0.0898, 0.9015)
        addon:SafeMethod(style.rothBg, "Hide")
    end
    if Accessible(style.rothFrame) then
        addon:SafeMethod(style.rothFrame, "SetTexture", ROTH_FRAME)
        addon:SafeMethod(style.rothFrame, "SetAllPoints", style)
        addon:SafeMethod(style.rothFrame, "Hide")
    end

    style.border = CreateBorder(style, "BORDER")
    local insideOK, inside = pcall(CreateFrame, "Frame", nil, style)
    style.inside = insideOK and inside or nil
    if Accessible(style.inside) then
        PositionInset(style.inside, style, 1)
        style.inside.border = CreateBorder(style.inside, "OVERLAY")
        SetBorderColor(style.inside.border, 0.1, 0.1, 0.1, 0.8)
        addon:SafeMethod(style.inside, "Hide")
    end

    local outsideOK, outside = pcall(CreateFrame, "Frame", nil, style)
    style.outside = outsideOK and outside or nil
    if Accessible(style.outside) then
        addon:SafeMethod(style.outside, "SetPoint", "TOPLEFT", style, "TOPLEFT", -1, 1)
        addon:SafeMethod(style.outside, "SetPoint", "BOTTOMRIGHT", style, "BOTTOMRIGHT", 1, -1)
        style.outside.border = CreateBorder(style.outside, "OVERLAY")
        SetBorderColor(style.outside.border, 0, 0, 0, 0.5)
        addon:SafeMethod(style.outside, "Hide")
    end

    style.mask = addon:SafeMethod(style, "CreateTexture", nil, "OVERLAY")
    if Accessible(style.mask) then
        addon:SafeMethod(style.mask, "SetTexture", "Interface\\Tooltips\\UI-Tooltip-Background")
        PositionMask(style, 3)
        addon:SafeMethod(style.mask, "SetBlendMode", "ADD")
        if type(CreateColor) == "function" then
            addon:SafeMethod(style.mask, "SetGradient", "VERTICAL",
                CreateColor(0, 0, 0, 0), CreateColor(0.9, 0.9, 0.9, 0.4))
        end
        addon:SafeMethod(style.mask, "Hide")
    end

    InstallStyleMethods(style)
    style:SetBackdrop(style.backdrop)
    addon:SafeMethod(style, "Show")
    return style
end

local function HookOne(tooltip, state, scriptName, callback)
    if state[scriptName] or not addon:CanBindScripts(tooltip) then return end
    local hasScript = addon:SafeGet(tooltip, "HasScript")
    if type(hasScript) == "function" then
        local ok, supported = pcall(hasScript, tooltip, scriptName)
        if not ok or not addon:CanAccessValue(supported) or supported ~= true then return end
    end
    local hook = addon:SafeGet(tooltip, "HookScript")
    if type(hook) == "function" and pcall(hook, tooltip, scriptName, callback) then
        state[scriptName] = true
    end
end

local function InstallTooltipHooks(tooltip)
    if not addon:IsManagedTooltip(tooltip) then return end
    local state = HookStateByTooltip[tooltip] or {}
    HookStateByTooltip[tooltip] = state

    HookOne(tooltip, state, "OnShow", function(frame)
        VisualsHiddenByTooltip[frame] = nil
        LibEvent:trigger("tooltip:show", frame)
    end)
    HookOne(tooltip, state, "OnHide", function(frame)
        LibEvent:trigger("tooltip:hide", frame)
    end)
    HookOne(tooltip, state, "OnTooltipCleared", function(frame)
        addon:ResetTooltipStyleFrame(frame)
        LibEvent:trigger("tooltip:cleared", frame)
    end)
end

local function EnsureStyle(tooltip)
    if not addon:IsManagedTooltip(tooltip) then return nil end
    local style = addon:GetTooltipStyle(tooltip) or CreateStyle(tooltip)
    if not style then return nil end

    addon:SafeMethod(style, "Show")
    InstallTooltipHooks(tooltip)
    HideBlizzardVisuals(tooltip)
    return style
end

LibEvent:attachTrigger("tooltip:init, tooltip.style.init", function(_, tooltip)
    EnsureStyle(tooltip)
end)

LibEvent:attachTrigger("tooltip:unregister", function(_, tooltip)
    addon:ReleaseTooltipStyle(tooltip)
end)

LibEvent:attachTrigger("tooltip:cleared", function(_, tooltip)
    addon:ResetTooltipStyleFrame(tooltip)
end)

LibEvent:attachTrigger("tooltip.style.mask", function(_, tooltip, enabled)
    local style = EnsureStyle(tooltip)
    if style and Accessible(style.mask) then addon:SafeMethod(style.mask, "SetShown", enabled == true) end
end)

LibEvent:attachTrigger("tooltip.style.background", function(_, tooltip, red, green, blue, alpha)
    local style = EnsureStyle(tooltip)
    if not style then return end
    local currentRed, currentGreen, currentBlue = style:GetBackdropColor()
    red, green, blue = tonumber(red) or currentRed, tonumber(green) or currentGreen, tonumber(blue) or currentBlue
    alpha = tonumber(alpha) or 0.9
    style.lastBackgroundColor = { red, green, blue, alpha }
    style:SetBackdropColor(red, green, blue, alpha)
end)

LibEvent:attachTrigger("tooltip.style.bgfile", function(_, tooltip, value)
    local style = EnsureStyle(tooltip)
    if not style then return end
    style.useRothBackground = value == "RothTooltipDarkTexture"
    local backdrop = style:GetBackdrop()
    backdrop.bgFile = style.useRothBackground and WHITE_TEXTURE
        or addon:GetBgFile(value) or DEFAULT_BACKGROUND
    style:SetBackdrop(backdrop)
    style:SetBackdropColor(unpack(style.lastBackgroundColor))
end)

LibEvent:attachTrigger("tooltip.style.border.size", function(_, tooltip, size)
    local style = EnsureStyle(tooltip)
    if not style then return end
    size = math.max(1, math.min(8, tonumber(size) or 1))
    local backdrop = style:GetBackdrop()
    backdrop.edgeSize = size
    if type(backdrop.insets) == "table" then
        backdrop.insets.top, backdrop.insets.left = size, size
        backdrop.insets.right, backdrop.insets.bottom = size, size
    end
    style:SetBackdrop(backdrop)
    PositionInset(style.inside, style, size)
end)

local function ResolveBorder(value)
    if type(value) == "string" and LibMedia and LibMedia:IsValid("border", value) then
        local ok, resolved = pcall(LibMedia.Fetch, LibMedia, "border", value)
        if ok and type(resolved) == "string" then return resolved end
    end
    return WHITE_TEXTURE
end

LibEvent:attachTrigger("tooltip.style.border.corner", function(_, tooltip, corner)
    local style = EnsureStyle(tooltip)
    if not style then return end
    local backdrop = style:GetBackdrop()
    local size = math.max(1, tonumber(backdrop.edgeSize) or 1)
    if corner == "angular" then size = math.min(size, 6) end
    backdrop.edgeSize = size

    style.hideFlatBorder = false
    addon:SafeMethod(style.rothFrame, "Hide")
    addon:SafeMethod(style.inside, "Hide")
    addon:SafeMethod(style.outside, "Hide")
    PositionMask(style, 3)

    if corner == "RothTooltipDarkFrame" then
        style.hideFlatBorder = true
        backdrop.edgeFile = WHITE_TEXTURE
        addon:SafeMethod(style.rothFrame, "Show")
    elseif corner == "angular" then
        backdrop.edgeFile = WHITE_TEXTURE
        PositionMask(style, 1)
        PositionInset(style.inside, style, size)
        addon:SafeMethod(style.inside, "Show")
        addon:SafeMethod(style.outside, "Show")
    else
        backdrop.edgeFile = ResolveBorder(corner)
    end

    style:SetBackdrop(backdrop)
    if style.hideFlatBorder then SetBorderColor(style.border, 0, 0, 0, 0)
    else SetBorderColor(style.border, unpack(style.borderColor)) end
end)

LibEvent:attachTrigger("tooltip.style.border.color", function(_, tooltip, red, green, blue, alpha)
    local style = EnsureStyle(tooltip)
    if not style then return end
    if style.hideFlatBorder then SetBorderColor(style.border, 0, 0, 0, 0) return end
    local currentRed, currentGreen, currentBlue, currentAlpha = style:GetBackdropBorderColor()
    style:SetBackdropBorderColor(tonumber(red) or currentRed, tonumber(green) or currentGreen,
        tonumber(blue) or currentBlue, tonumber(alpha) or currentAlpha)
end)

local defaultHeaderFont, defaultHeaderSize, defaultHeaderFlag =
    addon:SafeMethod(GameTooltipHeaderText, "GetFont")
local defaultBodyFont, defaultBodySize, defaultBodyFlag = addon:SafeMethod(GameTooltipText, "GetFont")

LibEvent:attachTrigger("tooltip.style.font.header", function(_, _, fontObject, fontSize, fontFlag)
    if not Accessible(GameTooltipHeaderText) then return end
    local currentFont, currentSize, currentFlag = addon:SafeMethod(GameTooltipHeaderText, "GetFont")
    local font = addon:GetFont(fontObject, defaultHeaderFont or currentFont)
    local size = fontSize == "default" and defaultHeaderSize or tonumber(fontSize) or currentSize
    local flag = fontFlag == "default" and defaultHeaderFlag or fontFlag or currentFlag
    flag = addon:NormalizeFontFlag(flag, defaultHeaderFlag)
    if type(font) == "string" and type(size) == "number" then
        addon:SafeMethod(GameTooltipHeaderText, "SetFont", font, size, flag)
    end
end)

LibEvent:attachTrigger("tooltip.style.font.body", function(_, _, fontObject, fontSize, fontFlag)
    if not Accessible(GameTooltipText) then return end
    local currentFont, currentSize, currentFlag = addon:SafeMethod(GameTooltipText, "GetFont")
    local font = addon:GetFont(fontObject, defaultBodyFont or currentFont)
    local size = fontSize == "default" and defaultBodySize or tonumber(fontSize) or currentSize
    local flag = fontFlag == "default" and defaultBodyFlag or fontFlag or currentFlag
    flag = addon:NormalizeFontFlag(flag, defaultBodyFlag)
    if type(font) == "string" and type(size) == "number" then
        addon:SafeMethod(GameTooltipText, "SetFont", font, size, flag)
    end
end)

function addon:ApplyGeneralStyleToTooltip(tooltip)
    local style = EnsureStyle(tooltip)
    if not style then return false end
    local general = self.db and self.db.general
    if type(general) ~= "table" then return true end

    LibEvent:trigger("tooltip.scale", tooltip, general.scale)
    LibEvent:trigger("tooltip.style.mask", tooltip, general.mask)
    LibEvent:trigger("tooltip.style.bgfile", tooltip, general.bgfile)
    LibEvent:trigger("tooltip.style.border.corner", tooltip, general.borderCorner)
    LibEvent:trigger("tooltip.style.border.size", tooltip, general.borderSize)
    if type(general.borderColor) == "table" then
        LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(general.borderColor))
    end
    if type(general.background) == "table" then
        LibEvent:trigger("tooltip.style.background", tooltip, unpack(general.background))
    end
    return true
end

local function OnBackdropChanged(tooltip)
    if not addon:IsManagedTooltip(tooltip) then return end
    VisualsHiddenByTooltip[tooltip] = nil
    addon:ApplyGeneralStyleToTooltip(tooltip)
end

if type(hooksecurefunc) == "function" then
    if type(SharedTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", OnBackdropChanged)
    end
    if type(GameTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("GameTooltip_SetBackdropStyle", OnBackdropChanged)
    end
end
