-- RothTooltip - Style Engine
local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary('LibEvent.7000')
local LibMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)

-- Reverse map TooltipDataType id -> name (memoized)
addon.TYPE_NAME = addon.TYPE_NAME or {}
if (Enum and Enum.TooltipDataType and type(Enum.TooltipDataType) == "table") then
    for k, v in pairs(Enum.TooltipDataType) do
        if (type(v) == "number") then
            addon.TYPE_NAME[v] = k
        end
    end
end

function addon:NormalizeTooltipFrame(tip)
    if (not tip) then return end
    local style = tip.__RTStyle
    if (style) then
        style:ClearAllPoints()
        style:SetAllPoints(tip)
    end
end

function addon:ResetTooltipStyleFrame(tip)
    local style = tip and tip.__RTStyle
    if (style) then
        style:ClearAllPoints()
        style:SetAllPoints(tip)
    end
end

local function HideBlizzardTooltipVisuals(tip)
    if (not tip) then return end
    if (tip.IsForbidden and tip:IsForbidden()) then return end
    local function hide(r)
        if (r and r.Hide) then r:Hide() end
    end

    hide(tip.NineSlice)
    hide(tip.Center)
    hide(tip.TopEdge)
    hide(tip.BottomEdge)
    hide(tip.LeftEdge)
    hide(tip.RightEdge)
    hide(tip.TopLeftCorner)
    hide(tip.TopRightCorner)
    hide(tip.BottomLeftCorner)
    hide(tip.BottomRightCorner)
    hide(tip.TopOverlay)
    hide(tip.BottomOverlay)
    hide(tip.LeftOverlay)
    hide(tip.RightOverlay)
    hide(tip.Background)
    hide(tip.Bg)
    hide(tip.Border)

    if (tip.GetBackdropTexture) then
        hide(tip:GetBackdropTexture("bg"))
        hide(tip:GetBackdropTexture("border"))
    end

    hide(tip.BackdropFrame)
    hide(tip.Backdrop)

    local function HideBackgroundTextures(frame)
        if (not frame) then return end
        if (frame.IsForbidden and frame:IsForbidden()) then return end
        if (not frame.GetRegions) then return end

        local cache = frame.__RT_HideBgCache
        if (cache) then
            for tex in pairs(cache) do hide(tex) end
            return
        end

        cache = {}
        frame.__RT_HideBgCache = cache

        local style = frame.__RTStyle
        local function IsProtected(tex)
            if (not style) then return false end
            if (tex == style.bg or tex == style.rothBg or tex == style.rothFrame or tex == style.mask) then
                return true
            end
            if (style.border) then
                if (tex == style.border.top or tex == style.border.bottom or tex == style.border.left or tex == style.border.right) then
                    return true
                end
            end
            return false
        end

        for _, r in ipairs({frame:GetRegions()}) do
            if (r and r.IsObjectType and r:IsObjectType("Texture") and (not IsProtected(r))) then
                local layer = r.GetDrawLayer and r:GetDrawLayer()
                if (layer == "BACKGROUND" or layer == "BORDER") then
                    hide(r)
                    cache[r] = true
                end
            end
        end
    end

    HideBackgroundTextures(tip)
    HideBackgroundTextures(tip.Tooltip)
    HideBackgroundTextures(tip.ItemTooltip)
    HideBackgroundTextures(tip.FollowerTooltip)
    HideBackgroundTextures(tip.BackdropFrame)
    HideBackgroundTextures(tip.Backdrop)
end

local function CreateBorderTextures(parent, drawLayer)
    local t = {}
    t.top = parent:CreateTexture(nil, drawLayer or "BORDER")
    t.bottom = parent:CreateTexture(nil, drawLayer or "BORDER")
    t.left = parent:CreateTexture(nil, drawLayer or "BORDER")
    t.right = parent:CreateTexture(nil, drawLayer or "BORDER")
    local tex = "Interface\\Buttons\\WHITE8X8"
    t.top:SetTexture(tex); t.bottom:SetTexture(tex); t.left:SetTexture(tex); t.right:SetTexture(tex)
    return t
end

local function LayoutBorder(parent, border, size)
    size = tonumber(size) or 1
    if (size < 1) then size = 1 end
    border.top:ClearAllPoints(); border.bottom:ClearAllPoints(); border.left:ClearAllPoints(); border.right:ClearAllPoints()
    border.top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); border.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0); border.top:SetHeight(size)
    border.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0); border.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0); border.bottom:SetHeight(size)
    border.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); border.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0); border.left:SetWidth(size)
    border.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0); border.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0); border.right:SetWidth(size)
end

local function SetBorderColor(border, r, g, b, a)
    border.top:SetVertexColor(r, g, b, a); border.bottom:SetVertexColor(r, g, b, a); border.left:SetVertexColor(r, g, b, a); border.right:SetVertexColor(r, g, b, a)
end

-- Triggers
LibEvent:attachTrigger("tooltip.style.init", function(self, tip)
    if (not tip or tip.__RTStyle) then return end
    local defaultBackdrop = {
        bgFile   = "Interface\\RaidFrame\\UI-RaidFrame-GroupBg",
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
    }
    if (tip.NineSlice) then tip.NineSlice:Hide() end
    local style = CreateFrame("Frame", nil, tip)
    tip.__RTStyle = style
    style:SetFrameLevel(tip:GetFrameLevel())
    style:SetAllPoints()
    style.__rt_backdrop = { bgFile = defaultBackdrop.bgFile, insets = { left = 3, right = 3, top = 3, bottom = 3 }, edgeFile = defaultBackdrop.edgeFile, edgeSize = defaultBackdrop.edgeSize }
    style.__rt_bgColor = { 0, 0, 0, 0.9 }; style.__rt_borderColor = { 0.6, 0.6, 0.6, 0.8 }
    style.bg = style:CreateTexture(nil, "BACKGROUND"); style.bg:SetAllPoints(style); style.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    style.rothBg = style:CreateTexture(nil, "BACKGROUND"); style.rothBg:SetTexture("Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkTexture"); style.rothBg:SetAllPoints(style); style.rothBg:SetTexCoord(0.0875, 0.9065, 0.0898, 0.9015); style.rothBg:Hide()
    style.rothFrame = style:CreateTexture(nil, "BORDER"); style.rothFrame:SetTexture("Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkFrame"); style.rothFrame:SetAllPoints(style); style.rothFrame:Hide()
    style.border = CreateBorderTextures(style, "BORDER")
    style.inside = CreateFrame("Frame", nil, style); style.inside:SetPoint("TOPLEFT", style, "TOPLEFT", 1, -1); style.inside:SetPoint("BOTTOMRIGHT", style, "BOTTOMRIGHT", -1, 1)
    style.inside.border = CreateBorderTextures(style.inside, "OVERLAY"); SetBorderColor(style.inside.border, 0.1, 0.1, 0.1, 0.8); style.inside:Hide()
    style.outside = CreateFrame("Frame", nil, style); style.outside:SetPoint("TOPLEFT", style, "TOPLEFT", -1, 1); style.outside:SetPoint("BOTTOMRIGHT", style, "BOTTOMRIGHT", 1, -1)
    style.outside.border = CreateBorderTextures(style.outside, "OVERLAY"); SetBorderColor(style.outside.border, 0, 0, 0, 0.5); style.outside:Hide()
    style.mask = style:CreateTexture(nil, "OVERLAY"); style.mask:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background"); style.mask:SetPoint("TOPLEFT", 3, -3); style.mask:SetPoint("BOTTOMRIGHT", style, "TOPRIGHT", -3, -32); style.mask:SetBlendMode("ADD"); style.mask:SetGradient("VERTICAL", CreateColor(0,0,0,0), CreateColor(0.9,0.9,0.9,0.4)); style.mask:Hide()
    function style:GetBackdrop() return self.__rt_backdrop end
    function style:SetBackdrop(bd)
        if (type(bd) == "table") then self.__rt_backdrop = bd end
        local s = self.__rt_backdrop and self.__rt_backdrop.edgeSize or 1
        LayoutBorder(self, self.border, s)
        local edge = (self.__rt_backdrop and self.__rt_backdrop.edgeFile) or "Interface\\Buttons\\WHITE8X8"
        if (self.border and edge) then
            self.border.top:SetTexture(edge); self.border.bottom:SetTexture(edge); self.border.left:SetTexture(edge); self.border.right:SetTexture(edge)
            if (self.border.top.SetHorizTile) then self.border.top:SetHorizTile(true); self.border.top:SetVertTile(false); self.border.bottom:SetHorizTile(true); self.border.bottom:SetVertTile(false); self.border.left:SetHorizTile(false); self.border.left:SetVertTile(true); self.border.right:SetHorizTile(false); self.border.right:SetVertTile(true) end
        end
        if (self.inside and self.inside.border) then LayoutBorder(self.inside, self.inside.border, 1) end
        if (self.outside and self.outside.border) then LayoutBorder(self.outside, self.outside.border, 1) end
        if (self.__RT_UseRothBg) then if (self.bg) then self.bg:Hide() end; if (self.rothBg) then self.rothBg:Show() end
        else if (self.rothBg) then self.rothBg:Hide() end; if (self.bg) then local bg = self.__rt_backdrop and self.__rt_backdrop.bgFile; self.bg:SetTexture(bg or "Interface\\Buttons\\WHITE8X8"); self.bg:Show() end end
        local r, g, b, a = unpack(self.__rt_bgColor); self:SetBackdropColor(r, g, b, a)
        local br, bgc, bb, ba = unpack(self.__rt_borderColor); self:SetBackdropBorderColor(br, bgc, bb, ba)
    end
    function style:GetBackdropColor() return unpack(self.__rt_bgColor) end
    function style:SetBackdropColor(r, g, b, a)
        self.__rt_bgColor[1] = r or self.__rt_bgColor[1]; self.__rt_bgColor[2] = g or self.__rt_bgColor[2]; self.__rt_bgColor[3] = b or self.__rt_bgColor[3]; self.__rt_bgColor[4] = a or self.__rt_bgColor[4]
        if (self.__RT_UseRothBg and self.rothBg and self.rothBg:IsShown()) then self.rothBg:SetVertexColor(self.__rt_bgColor[1], self.__rt_bgColor[2], self.__rt_bgColor[3], self.__rt_bgColor[4])
        elseif (self.bg) then self.bg:SetVertexColor(self.__rt_bgColor[1], self.__rt_bgColor[2], self.__rt_bgColor[3], self.__rt_bgColor[4]) end
    end
    function style:GetBackdropBorderColor() return unpack(self.__rt_borderColor) end
    function style:SetBackdropBorderColor(r, g, b, a)
        self.__rt_borderColor[1] = r or self.__rt_borderColor[1]; self.__rt_borderColor[2] = g or self.__rt_borderColor[2]; self.__rt_borderColor[3] = b or self.__rt_borderColor[3]; self.__rt_borderColor[4] = a or self.__rt_borderColor[4]
        SetBorderColor(self.border, self.__rt_borderColor[1], self.__rt_borderColor[2], self.__rt_borderColor[3], self.__rt_borderColor[4])
    end
    style:SetBackdrop(style.__rt_backdrop); style:SetBackdropColor(0, 0, 0, 0.9); style:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    tip:HookScript("OnShow", function(self) LibEvent:trigger("tooltip:show", self) end)
    tip:HookScript("OnHide", function(self) LibEvent:trigger("tooltip:hide", self) end)
    addon:InitTooltipDataProcessor()
    tip:HookScript("OnTooltipCleared", function(self) addon:ResetTooltipStyleFrame(self); LibEvent:trigger("tooltip:cleared", self) end)
    if (tip == GameTooltip or tip.identity == "diy") then
        tip.GetBackdrop = function(self) return self.__RTStyle:GetBackdrop() end
        tip.GetBackdropColor = function(self) return self.__RTStyle:GetBackdropColor() end
        tip.GetBackdropBorderColor = function(self) return self.__RTStyle:GetBackdropBorderColor() end
        if (not tip.BigFactionIcon) then tip.BigFactionIcon = tip:CreateTexture(nil, "OVERLAY"); tip.BigFactionIcon:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 18, 0); tip.BigFactionIcon:SetBlendMode("ADD"); tip.BigFactionIcon:SetScale(0.24); tip.BigFactionIcon:SetAlpha(0.40) end
    end
    if (tip.DisableDrawLayer) then tip:DisableDrawLayer("BACKGROUND") end
    LibEvent:trigger("tooltip:init", tip)
    for _, v in pairs(addon.tooltips) do if (tip == v) then return end end
    addon.tooltips[#addon.tooltips+1] = tip
    if (addon.tooltipSet) then addon.tooltipSet[tip] = true end
end)

LibEvent:attachTrigger("tooltip.style.mask", function(self, frame, boolean) LibEvent:trigger("tooltip.style.init", frame); frame.__RTStyle.mask:SetShown(boolean) end)
LibEvent:attachTrigger("tooltip.style.background", function(self, frame, r, g, b, a)
    LibEvent:trigger("tooltip.style.init", frame); a = tonumber(a) or 0.9; frame.__RTStyle.__RT_LastBgColor = frame.__RTStyle.__RT_LastBgColor or {}; frame.__RTStyle.__RT_LastBgColor[1] = r; frame.__RTStyle.__RT_LastBgColor[2] = g; frame.__RTStyle.__RT_LastBgColor[3] = b; frame.__RTStyle.__RT_LastBgColor[4] = a
    if (frame.__RTStyle.__RT_UseRothBg and frame.__RTStyle.rothBg and frame.__RTStyle.rothBg:IsShown()) then frame.__RTStyle.rothBg:SetVertexColor(r or 1, g or 1, b or 1, a); local rr, gg, bb, aa = frame.__RTStyle:GetBackdropColor(); if (aa ~= 0) then frame.__RTStyle:SetBackdropColor(0, 0, 0, 0) end; return end
    local rr, gg, bb, aa = frame.__RTStyle:GetBackdropColor(); if (rr ~= r or gg ~= g or bb ~= b or aa ~= a) then frame.__RTStyle:SetBackdropColor(r or rr, g or gg, b or bb, a) end
end)
LibEvent:attachTrigger("tooltip.style.bgfile", function(self, frame, bgvalue)
    LibEvent:trigger("tooltip.style.init", frame); local useRoth = (bgvalue == "RothTooltipDarkTexture"); frame.__RTStyle.__RT_UseRothBg = useRoth; if (frame.__RTStyle.rothBg) then frame.__RTStyle.rothBg:SetShown(useRoth) end
    local bgfile = useRoth and "Interface\\Buttons\\WHITE8X8" or addon:GetBgFile(bgvalue); local backdrop = frame.__RTStyle:GetBackdrop(); local r, g, b, a = frame.__RTStyle:GetBackdropColor(); local rr, gg, bb, aa = frame.__RTStyle:GetBackdropBorderColor()
    if (backdrop.bgFile ~= bgfile) then backdrop.bgFile = bgfile; frame.__RTStyle:SetBackdrop(backdrop); frame.__RTStyle:SetBackdropColor(r, g, b, tonumber(a)); frame.__RTStyle:SetBackdropBorderColor(rr, gg, bb, aa) end
    local c = frame.__RTStyle.__RT_LastBgColor; if (c) then LibEvent:trigger("tooltip.style.background", frame, c[1], c[2], c[3], c[4]) end
end)
LibEvent:attachTrigger("tooltip.style.border.size", function(self, frame, size)
    LibEvent:trigger("tooltip.style.init", frame); local sz = tonumber(size) or 1; if (sz < 1) then sz = 1 elseif (sz > 8) then sz = 8 end
    local backdrop = frame.__RTStyle:GetBackdrop(); backdrop.edgeSize = sz; if (backdrop.insets) then backdrop.insets.top = sz; backdrop.insets.left = sz; backdrop.insets.right = sz; backdrop.insets.bottom = sz end
    local r, g, b, a = frame.__RTStyle:GetBackdropColor(); local br, bgc, bb, ba = frame.__RTStyle:GetBackdropBorderColor(); frame.__RTStyle:SetBackdrop(backdrop); frame.__RTStyle:SetBackdropColor(r, g, b, tonumber(a)); frame.__RTStyle:SetBackdropBorderColor(br, bgc, bb, tonumber(ba))
    if (frame.__RTStyle.inside) then frame.__RTStyle.inside:SetPoint("TOPLEFT", frame.__RTStyle, "TOPLEFT", sz, -sz); frame.__RTStyle.inside:SetPoint("BOTTOMRIGHT", frame.__RTStyle, "BOTTOMRIGHT", -sz, sz) end
end)
LibEvent:attachTrigger("tooltip.style.border.corner", function(self, frame, corner)
    LibEvent:trigger("tooltip.style.init", frame); local backdrop = frame.__RTStyle:GetBackdrop(); local r, g, b, a = frame.__RTStyle:GetBackdropColor(); local br, bgc, bb, ba = frame.__RTStyle:GetBackdropBorderColor()
    local sz = tonumber(backdrop.edgeSize) or tonumber(addon.db and addon.db.general and addon.db.general.borderSize) or 1; if (sz < 1) then sz = 1 end; if (corner == "angular" and sz > 6) then sz = 6 end; backdrop.edgeSize = sz; if (backdrop.insets) then backdrop.insets.top = sz; backdrop.insets.left = sz; backdrop.insets.right = sz; backdrop.insets.bottom = sz end
    frame.__RTStyle.__RT_HideFlatBorder = false; local edgeFile = "Interface\\Buttons\\WHITE8X8"; if (frame.__RTStyle.rothFrame) then frame.__RTStyle.rothFrame:Hide() end
    if (corner == "RothTooltipDarkFrame") then frame.__RTStyle.__RT_HideFlatBorder = true; edgeFile = "Interface\\Buttons\\WHITE8X8"; frame.__RTStyle.mask:SetPoint("TOPLEFT", 3, -3); frame.__RTStyle.mask:SetPoint("BOTTOMRIGHT", frame.__RTStyle, "TOPRIGHT", -3, -32); if (frame.__RTStyle.inside) then frame.__RTStyle.inside:Hide() end; if (frame.__RTStyle.outside) then frame.__RTStyle.outside:Hide() end; if (frame.__RTStyle.rothFrame) then frame.__RTStyle.rothFrame:Show() end
    elseif (corner == "angular") then edgeFile = "Interface\\Buttons\\WHITE8X8"; frame.__RTStyle.mask:SetPoint("TOPLEFT", 1, -1); frame.__RTStyle.mask:SetPoint("BOTTOMRIGHT", frame.__RTStyle, "TOPRIGHT", -1, -32); if (frame.__RTStyle.outside) then frame.__RTStyle.outside:Show() end; if (frame.__RTStyle.inside) then frame.__RTStyle.inside:Show(); frame.__RTStyle.inside:SetPoint("TOPLEFT", frame.__RTStyle, "TOPLEFT", sz, -sz); frame.__RTStyle.inside:SetPoint("BOTTOMRIGHT", frame.__RTStyle, "BOTTOMRIGHT", -sz, sz) end
    elseif (LibMedia and LibMedia:IsValid("border", corner)) then edgeFile = LibMedia:Fetch("border", corner); frame.__RTStyle.mask:SetPoint("TOPLEFT", 3, -3); frame.__RTStyle.mask:SetPoint("BOTTOMRIGHT", frame.__RTStyle, "TOPRIGHT", -3, -32); if (frame.__RTStyle.inside) then frame.__RTStyle.inside:Hide() end; if (frame.__RTStyle.outside) then frame.__RTStyle.outside:Hide() end
    else edgeFile = "Interface\\Buttons\\WHITE8X8"; frame.__RTStyle.mask:SetPoint("TOPLEFT", 3, -3); frame.__RTStyle.mask:SetPoint("BOTTOMRIGHT", frame.__RTStyle, "TOPRIGHT", -3, -32); if (frame.__RTStyle.inside) then frame.__RTStyle.inside:Hide() end; if (frame.__RTStyle.outside) then frame.__RTStyle.outside:Hide() end end
    backdrop.edgeFile = edgeFile; frame.__RTStyle:SetBackdrop(backdrop); frame.__RTStyle:SetBackdropColor(r, g, b, a)
    if (frame.__RTStyle.__RT_HideFlatBorder) then frame.__RTStyle:SetBackdropBorderColor(0, 0, 0, 0) else frame.__RTStyle:SetBackdropBorderColor(br, bgc, bb, ba) end
end)
LibEvent:attachTrigger("tooltip.style.border.color", function(self, frame, r, g, b, a) LibEvent:trigger("tooltip.style.init", frame); if (frame.__RTStyle.__RT_HideFlatBorder) then frame.__RTStyle:SetBackdropBorderColor(0, 0, 0, 0); return end; local rr, gg, bb, aa = frame.__RTStyle:GetBackdropBorderColor(); if (rr ~= r or gg ~= g or bb ~= b or aa ~= a) then frame.__RTStyle:SetBackdropBorderColor(r or rr, g or gg, b or bb, a or aa) end end)

local defaultHeaderFont, defaultHeaderSize, defaultHeaderFlag = GameTooltipHeaderText:GetFont()
LibEvent:attachTrigger("tooltip.style.font.header", function(self, frame, fontObject, fontSize, fontFlag)
    local font, size, flag = GameTooltipHeaderText:GetFont(); if (fontObject == "default" and fontSize == "default" and fontFlag == "default") then if (size == defaultHeaderSize and flag == defaultHeaderFlag) then return end end
    font = addon:GetFont(fontObject, defaultHeaderFont); if (fontSize == "default") then size = defaultHeaderSize elseif (type(fontSize) == "number") then size = fontSize end
    if (fontFlag == "default") then flag = defaultHeaderFlag else flag = fontFlag or flag end; flag = addon:NormalizeFontFlag(flag, defaultHeaderFlag); GameTooltipHeaderText:SetFont(font, size, flag)
end)
local defaultBodyFont, defaultBodySize, defaultBodyFlag = GameTooltipText:GetFont()
LibEvent:attachTrigger("tooltip.style.font.body", function(self, frame, fontObject, fontSize, fontFlag)
    local font, size, flag = GameTooltipText:GetFont(); font = addon:GetFont(fontObject, defaultBodyFont); if (fontSize == "default") then size = defaultBodySize elseif (type(fontSize) == "number") then size = fontSize end
    if (fontFlag == "default") then flag = defaultBodyFlag else flag = fontFlag or flag end; flag = addon:NormalizeFontFlag(flag, defaultBodyFlag); GameTooltipText:SetFont(font, size, flag)
end)

function addon:ApplyGeneralStyleToTooltip(tip)
    if (not tip) then return end
    HideBlizzardTooltipVisuals(tip)
    LibEvent:trigger("tooltip.style.init", tip)
    if (self.db and self.db.general) then
        local g = self.db.general
        LibEvent:trigger("tooltip.scale", tip, g.scale)
        LibEvent:trigger("tooltip.style.mask", tip, g.mask)
        LibEvent:trigger("tooltip.style.bgfile", tip, g.bgfile)
        LibEvent:trigger("tooltip.style.border.corner", tip, g.borderCorner)
        LibEvent:trigger("tooltip.style.border.size", tip, g.borderSize)
        LibEvent:trigger("tooltip.style.border.color", tip, unpack(g.borderColor))
        LibEvent:trigger("tooltip.style.background", tip, unpack(g.background))
    end
end
