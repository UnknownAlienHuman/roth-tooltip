-- RothTooltip visual engine
--
-- Rendering state is owned by addon weak tables and addon-created regions.
-- Blizzard tooltip methods are never replaced, and arbitrary cache fields are
-- not attached to Blizzard frames.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
local LibMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BACKGROUND = "Interface\\RaidFrame\\UI-RaidFrame-GroupBg"
local DEFAULT_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local ROTH_BACKGROUND = "Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkTexture"
local ROTH_FRAME = "Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkFrame"

local StyleByTooltip = addon.__RT_StyleByTooltip or setmetatable({}, { __mode = "k" })
local FactionIconByTooltip = addon.__RT_FactionIconByTooltip or setmetatable({}, { __mode = "k" })
local HookedTooltips = addon.__RT_StyleHookedTooltips or setmetatable({}, { __mode = "k" })

addon.__RT_StyleByTooltip = StyleByTooltip
addon.__RT_FactionIconByTooltip = FactionIconByTooltip
addon.__RT_StyleHookedTooltips = HookedTooltips

-- Reverse map TooltipDataType id -> name. Rebuild once per load so removed enum
-- members cannot survive in a stale table.
addon.TYPE_NAME = {}
if Enum and type(Enum.TooltipDataType) == "table" then
    for name, typeID in pairs(Enum.TooltipDataType) do
        if type(name) == "string" and type(typeID) == "number" then
            addon.TYPE_NAME[typeID] = name
        end
    end
end

local function IsAccessible(object)
    return addon:IsObjectAccessible(object)
end

local function HideObject(object)
    if IsAccessible(object) then addon:SafeMethod(object, "Hide") end
end

local function SetPointsToParent(frame, parent)
    if not IsAccessible(frame) or not IsAccessible(parent) then return false end
    addon:SafeMethod(frame, "ClearAllPoints")
    addon:SafeMethod(frame, "SetAllPoints", parent)
    return true
end

function addon:GetTooltipStyle(tooltip)
    if not self:IsTooltipSafe(tooltip) then return nil end
    local style = StyleByTooltip[tooltip]
    if IsAccessible(style) then return style end
    StyleByTooltip[tooltip] = nil
    return nil
end

function addon:GetBigFactionIcon(tooltip, create)
    if not self:IsTooltipSafe(tooltip) then return nil end

    local icon = FactionIconByTooltip[tooltip]
    if IsAccessible(icon) then return icon end
    FactionIconByTooltip[tooltip] = nil
    if create ~= true then return nil end

    local identity = self:SafeGet(tooltip, "identity")
    if tooltip ~= GameTooltip and identity ~= "diy" then return nil end

    icon = self:SafeMethod(tooltip, "CreateTexture", nil, "OVERLAY")
    if not IsAccessible(icon) then return nil end

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
    if style then SetPointsToParent(style, tooltip) end
end

function addon:ResetTooltipStyleFrame(tooltip)
    self:NormalizeTooltipFrame(tooltip)
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

local function HideKnownVisualMembers(frame)
    if not IsAccessible(frame) then return end
    for _, member in ipairs(KNOWN_VISUAL_MEMBERS) do
        HideObject(addon:SafeGet(frame, member))
    end
end

local function HideBlizzardTooltipVisuals(tooltip)
    if not addon:IsTooltipSafe(tooltip) then return end

    HideKnownVisualMembers(tooltip)
    for _, member in ipairs(NESTED_VISUAL_MEMBERS) do
        HideKnownVisualMembers(addon:SafeGet(tooltip, member))
    end

    local getBackdropTexture = addon:SafeGet(tooltip, "GetBackdropTexture")
    if type(getBackdropTexture) == "function" then
        local ok, background = pcall(getBackdropTexture, tooltip, "bg")
        if ok and addon:CanAccessValue(background) then HideObject(background) end
        ok, background = pcall(getBackdropTexture, tooltip, "border")
        if ok and addon:CanAccessValue(background) then HideObject(background) end
    end

    -- Do not enumerate GetRegions(): Retail 12.1 may propagate secret aspect
    -- through returned regions. Known Blizzard members plus the background draw
    -- layer are sufficient and fail closed for unknown tooltip implementations.
    addon:SafeMethod(tooltip, "DisableDrawLayer", "BACKGROUND")
end

local function CreateBorderTextures(parent, drawLayer)
    if not IsAccessible(parent) then return nil end

    local border = {}
    border.top = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER")
    border.bottom = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER")
    border.left = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER")
    border.right = addon:SafeMethod(parent, "CreateTexture", nil, drawLayer or "BORDER")

    if not IsAccessible(border.top) or not IsAccessible(border.bottom)
        or not IsAccessible(border.left) or not IsAccessible(border.right) then
        return nil
    end

    for _, texture in pairs(border) do
        addon:SafeMethod(texture, "SetTexture", WHITE_TEXTURE)
    end
    return border
end

local function LayoutBorder(parent, border, size)
    if not IsAccessible(parent) or type(border) ~= "table" then return end
    size = tonumber(size) or 1
    if size < 1 then size = 1 end

    for _, texture in pairs(border) do addon:SafeMethod(texture, "ClearAllPoints") end

    addon:SafeMethod(border.top, "SetPoint", "TOPLEFT", parent, "TOPLEFT", 0, 0)
    addon:SafeMethod(border.top, "SetPoint", "TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    addon:SafeMethod(border.top, "SetHeight", size)

    addon:SafeMethod(border.bottom, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    addon:SafeMethod(border.bottom, "SetPoint", "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    addon:SafeMethod(border.bottom, "SetHeight", size)

    addon:SafeMethod(border.left, "SetPoint", "TOPLEFT", parent, "TOPLEFT", 0, 0)
    addon:SafeMethod(border.left, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    addon:SafeMethod(border.left, "SetWidth", size)

    addon:SafeMethod(border.right, "SetPoint", "TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    addon:SafeMethod(border.right, "SetPoint", "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    addon:SafeMethod(border.right, "SetWidth", size)
end

local function SetBorderColor(border, red, green, blue, alpha)
    if type(border) ~= "table" then return end
    red = tonumber(red) or 1
    green = tonumber(green) or 1
    blue = tonumber(blue) or 1
    alpha = tonumber(alpha) or 1

    for _, texture in pairs(border) do
        addon:SafeMethod(texture, "SetVertexColor", red, green, blue, alpha)
    end
end

local function SetBorderTexture(border, texture)
    if type(border) ~= "table" or type(texture) ~= "string" then return end
    for _, region in pairs(border) do addon:SafeMethod(region, "SetTexture", texture) end

    addon:SafeMethod(border.top, "SetHorizTile", true)
    addon:SafeMethod(border.top, "SetVertTile", false)
    addon:SafeMethod(border.bottom, "SetHorizTile", true)
    addon:SafeMethod(border.bottom, "SetVertTile", false)
    addon:SafeMethod(border.left, "SetHorizTile", false)
    addon:SafeMethod(border.left, "SetVertTile", true)
    addon:SafeMethod(border.right, "SetHorizTile", false)
    addon:SafeMethod(border.right, "SetVertTile", true)
end

local function PositionInsetFrame(frame, parent, inset)
    if not IsAccessible(frame) or not IsAccessible(parent) then return end
    inset = tonumber(inset) or 1
    addon:SafeMethod(frame, "ClearAllPoints")
    addon:SafeMethod(frame, "SetPoint", "TOPLEFT", parent, "TOPLEFT", inset, -inset)
    addon:SafeMethod(frame, "SetPoint", "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
end

local function PositionMask(style, inset)
    if not style or not IsAccessible(style.mask) then return end
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

        if self.useRothBackground == true then
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

        local edgeSize = tonumber(backdrop.edgeSize) or 1
        LayoutBorder(self, self.border, edgeSize)
        LayoutBorder(self.inside, self.inside and self.inside.border, 1)
        LayoutBorder(self.outside, self.outside and self.outside.border, 1)
        SetBorderTexture(self.border, type(backdrop.edgeFile) == "string" and backdrop.edgeFile or WHITE_TEXTURE)

        if self.useRothBackground == true then
            addon:SafeMethod(self.bg, "Hide")
            addon:SafeMethod(self.rothBg, "Show")
        else
            addon:SafeMethod(self.rothBg, "Hide")
            addon:SafeMethod(self.bg, "SetTexture", type(backdrop.bgFile) == "string" and backdrop.bgFile or WHITE_TEXTURE)
            addon:SafeMethod(self.bg, "Show")
        end

        self:SetBackdropColor(unpack(self.backgroundColor))
        self:SetBackdropBorderColor(unpack(self.borderColor))
    end
end

local function CreateStyleFrame(tooltip)
    if not addon:IsTooltipSafe(tooltip) then return nil end

    local ok, style = pcall(CreateFrame, "Frame", nil, tooltip)
    if not ok or not IsAccessible(style) then return nil end

    StyleByTooltip[tooltip] = style
    style.backdrop = {
        bgFile = DEFAULT_BACKGROUND,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        edgeFile = DEFAULT_BORDER,
        edgeSize = 14,
    }
    style.backgroundColor = { 0, 0, 0, 0.9 }
    style.borderColor = { 0.6, 0.6, 0.6, 0.8 }
    style.lastBackgroundColor = { 0, 0, 0, 0.9 }
    style.useRothBackground = false
    style.hideFlatBorder = false

    local frameLevel = addon:SafeMethod(tooltip, "GetFrameLevel")
    if type(frameLevel) == "number" then addon:SafeMethod(style, "SetFrameLevel", frameLevel) end
    SetPointsToParent(style, tooltip)

    style.bg = addon:SafeMethod(style, "CreateTexture", nil, "BACKGROUND")
    if IsAccessible(style.bg) then
        addon:SafeMethod(style.bg, "SetAllPoints", style)
        addon:SafeMethod(style.bg, "SetTexture", WHITE_TEXTURE)
    end

    style.rothBg = addon:SafeMethod(style, "CreateTexture", nil, "BACKGROUND")
    if IsAccessible(style.rothBg) then
        addon:SafeMethod(style.rothBg, "SetTexture", ROTH_BACKGROUND)
        addon:SafeMethod(style.rothBg, "SetAllPoints", style)
        addon:SafeMethod(style.rothBg, "SetTexCoord", 0.0875, 0.9065, 0.0898, 0.9015)
        addon:SafeMethod(style.rothBg, "Hide")
    end

    style.rothFrame = addon:SafeMethod(style, "CreateTexture", nil, "BORDER")
    if IsAccessible(style.rothFrame) then
        addon:SafeMethod(style.rothFrame, "SetTexture", ROTH_FRAME)
        addon:SafeMethod(style.rothFrame, "SetAllPoints", style)
        addon:SafeMethod(style.rothFrame, "Hide")
    end

    style.border = CreateBorderTextures(style, "BORDER")

    local insideOK, inside = pcall(CreateFrame, "Frame", nil, style)
    style.inside = insideOK and inside or nil
    if IsAccessible(style.inside) then
        PositionInsetFrame(style.inside, style, 1)
        style.inside.border = CreateBorderTextures(style.inside, "OVERLAY")
        SetBorderColor(style.inside.border, 0.1, 0.1, 0.1, 0.8)
        addon:SafeMethod(style.inside, "Hide")
    end

    local outsideOK, outside = pcall(CreateFrame, "Frame", nil, style)
    style.outside = outsideOK and outside or nil
    if IsAccessible(style.outside) then
        addon:SafeMethod(style.outside, "SetPoint", "TOPLEFT", style, "TOPLEFT", -1, 1)
        addon:SafeMethod(style.outside, "SetPoint", "BOTTOMRIGHT", style, "BOTTOMRIGHT", 1, -1)
        style.outside.border = CreateBorderTextures(style.outside, "OVERLAY")
        SetBorderColor(style.outside.border, 0, 0, 0, 0.5)
        addon:SafeMethod(style.outside, "Hide")
    end

    style.mask = addon:SafeMethod(style, "CreateTexture", nil, "OVERLAY")
    if IsAccessible(style.mask) then
        addon:SafeMethod(style.mask, "SetTexture", "Interface\\Tooltips\\UI-Tooltip-Background")
        PositionMask(style, 3)
        addon:SafeMethod(style.mask, "SetBlendMode", "ADD")
        local lower = CreateColor and CreateColor(0, 0, 0, 0) or nil
        local upper = CreateColor and CreateColor(0.9, 0.9, 0.9, 0.4) or nil
        if lower and upper then addon:SafeMethod(style.mask, "SetGradient", "VERTICAL", lower, upper) end
        addon:SafeMethod(style.mask, "Hide")
    end

    InstallStyleMethods(style)
    style:SetBackdrop(style.backdrop)
    style:SetBackdropColor(unpack(style.backgroundColor))
    style:SetBackdropBorderColor(unpack(style.borderColor))
    addon:GetBigFactionIcon(tooltip, true)
    return style
end

local function HookScriptIfSupported(frame, scriptName, callback)
    if not IsAccessible(frame) or type(scriptName) ~= "string" or type(callback) ~= "function" then
        return false
    end
    if type(addon.CanBindScripts) == "function" and not addon:CanBindScripts(frame) then
        return false
    end

    local hasScript = addon:SafeGet(frame, "HasScript")
    if type(hasScript) == "function" then
        local ok, supported = pcall(hasScript, frame, scriptName)
        if not ok or not addon:CanAccessValue(supported) or supported ~= true then return false end
    end

    local hookScript = addon:SafeGet(frame, "HookScript")
    if type(hookScript) ~= "function" then return false end
    local ok = pcall(hookScript, frame, scriptName, callback)
    return ok
end

local function InstallTooltipHooks(tooltip)
    if HookedTooltips[tooltip] or not addon:IsTooltipSafe(tooltip) then return end
    HookedTooltips[tooltip] = true

    HookScriptIfSupported(tooltip, "OnShow", function(frame)
        LibEvent:trigger("tooltip:show", frame)
    end)
    HookScriptIfSupported(tooltip, "OnHide", function(frame)
        LibEvent:trigger("tooltip:hide", frame)
    end)
    HookScriptIfSupported(tooltip, "OnTooltipCleared", function(frame)
        addon:ResetTooltipStyleFrame(frame)
        LibEvent:trigger("tooltip:cleared", frame)
    end)
end

local function EnsureStyle(tooltip)
    if not addon:IsTooltipSafe(tooltip) then return nil end
    local style = addon:GetTooltipStyle(tooltip) or CreateStyleFrame(tooltip)
    if not style then return nil end

    InstallTooltipHooks(tooltip)
    HideBlizzardTooltipVisuals(tooltip)
    return style
end

LibEvent:attachTrigger("tooltip:init", function(_, tooltip)
    EnsureStyle(tooltip)
end)

LibEvent:attachTrigger("tooltip.style.init", function(_, tooltip)
    EnsureStyle(tooltip)
end)

LibEvent:attachTrigger("tooltip:cleared", function(_, tooltip)
    addon:ResetTooltipStyleFrame(tooltip)
end)

LibEvent:attachTrigger("tooltip.style.mask", function(_, tooltip, enabled)
    local style = EnsureStyle(tooltip)
    if style and IsAccessible(style.mask) then addon:SafeMethod(style.mask, "SetShown", enabled == true) end
end)

LibEvent:attachTrigger("tooltip.style.background", function(_, tooltip, red, green, blue, alpha)
    local style = EnsureStyle(tooltip)
    if not style then return end

    local currentRed, currentGreen, currentBlue = style:GetBackdropColor()
    red = type(red) == "number" and red or currentRed
    green = type(green) == "number" and green or currentGreen
    blue = type(blue) == "number" and blue or currentBlue
    alpha = type(alpha) == "number" and alpha or 0.9
    style.lastBackgroundColor[1] = red
    style.lastBackgroundColor[2] = green
    style.lastBackgroundColor[3] = blue
    style.lastBackgroundColor[4] = alpha
    style:SetBackdropColor(red, green, blue, alpha)
end)

LibEvent:attachTrigger("tooltip.style.bgfile", function(_, tooltip, backgroundValue)
    local style = EnsureStyle(tooltip)
    if not style then return end

    local useRoth = backgroundValue == "RothTooltipDarkTexture"
    style.useRothBackground = useRoth
    local backdrop = style:GetBackdrop()
    if type(backdrop) ~= "table" then return end

    local backgroundFile = useRoth and WHITE_TEXTURE or addon:GetBgFile(backgroundValue)
    if type(backgroundFile) ~= "string" then backgroundFile = DEFAULT_BACKGROUND end
    backdrop.bgFile = backgroundFile
    style:SetBackdrop(backdrop)
    style:SetBackdropColor(unpack(style.lastBackgroundColor))
end)

LibEvent:attachTrigger("tooltip.style.border.size", function(_, tooltip, size)
    local style = EnsureStyle(tooltip)
    if not style then return end

    size = tonumber(size) or 1
    if size < 1 then size = 1 elseif size > 8 then size = 8 end

    local backdrop = style:GetBackdrop()
    if type(backdrop) ~= "table" then return end
    backdrop.edgeSize = size
    if type(backdrop.insets) == "table" then
        backdrop.insets.top = size
        backdrop.insets.left = size
        backdrop.insets.right = size
        backdrop.insets.bottom = size
    end
    style:SetBackdrop(backdrop)
    PositionInsetFrame(style.inside, style, size)
end)

local function ResolveBorderFile(corner)
    if type(corner) == "string" and LibMedia and LibMedia:IsValid("border", corner) then
        local ok, border = pcall(LibMedia.Fetch, LibMedia, "border", corner)
        if ok and type(border) == "string" then return border end
    end
    return WHITE_TEXTURE
end

LibEvent:attachTrigger("tooltip.style.border.corner", function(_, tooltip, corner)
    local style = EnsureStyle(tooltip)
    if not style then return end

    local backdrop = style:GetBackdrop()
    if type(backdrop) ~= "table" then return end
    local size = tonumber(backdrop.edgeSize)
        or tonumber(addon.db and addon.db.general and addon.db.general.borderSize)
        or 1
    if size < 1 then size = 1 end
    if corner == "angular" and size > 6 then size = 6 end
    backdrop.edgeSize = size

    if type(backdrop.insets) == "table" then
        backdrop.insets.top = size
        backdrop.insets.left = size
        backdrop.insets.right = size
        backdrop.insets.bottom = size
    end

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
        addon:SafeMethod(style.outside, "Show")
        PositionInsetFrame(style.inside, style, size)
        addon:SafeMethod(style.inside, "Show")
    else
        backdrop.edgeFile = ResolveBorderFile(corner)
    end

    style:SetBackdrop(backdrop)
    if style.hideFlatBorder then
        SetBorderColor(style.border, 0, 0, 0, 0)
    else
        SetBorderColor(style.border, unpack(style.borderColor))
    end
end)

LibEvent:attachTrigger("tooltip.style.border.color", function(_, tooltip, red, green, blue, alpha)
    local style = EnsureStyle(tooltip)
    if not style then return end
    if style.hideFlatBorder then
        SetBorderColor(style.border, 0, 0, 0, 0)
        return
    end

    local currentRed, currentGreen, currentBlue, currentAlpha = style:GetBackdropBorderColor()
    style:SetBackdropBorderColor(
        type(red) == "number" and red or currentRed,
        type(green) == "number" and green or currentGreen,
        type(blue) == "number" and blue or currentBlue,
        type(alpha) == "number" and alpha or currentAlpha
    )
end)

local function GetFontDefaults(fontObject)
    if not IsAccessible(fontObject) then return nil, nil, nil end
    return addon:SafeMethod(fontObject, "GetFont")
end

local defaultHeaderFont, defaultHeaderSize, defaultHeaderFlag = GetFontDefaults(GameTooltipHeaderText)
local defaultBodyFont, defaultBodySize, defaultBodyFlag = GetFontDefaults(GameTooltipText)

LibEvent:attachTrigger("tooltip.style.font.header", function(_, _, fontObject, fontSize, fontFlag)
    if not IsAccessible(GameTooltipHeaderText) then return end
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
    if not IsAccessible(GameTooltipText) then return end
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
