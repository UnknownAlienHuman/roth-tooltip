local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local CURSOR_INTERVAL = 0.05
local states = setmetatable({}, { __mode = "k" })

local function IsOrdinaryUnit(unit)
    return addon:CanAccessValue(unit)
        and type(unit) == "string"
        and unit ~= ""
        and not addon:IsUnitIdentityRestricted(unit)
end

local function StopCursorAnchor(tooltip)
    local state = states[tooltip]
    if type(state) == "table" and state.ticker then
        local cancel = addon:SafeGet(state.ticker, "Cancel")
        if type(cancel) == "function" then pcall(cancel, state.ticker) end
    end
    states[tooltip] = nil
end

local function SetCursorPoint(tooltip, point, offsetX, offsetY, scale)
    if not addon:IsTooltipSafe(tooltip) or type(scale) ~= "number" or scale <= 0 then return false end
    local cursorX, cursorY = GetCursorPosition()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then return false end

    local x = floor(cursorX / scale + offsetX)
    local y = floor(cursorY / scale + offsetY)
    local state = states[tooltip]
    if type(state) == "table" and state.point == point and state.x == x and state.y == y then
        return true
    end

    state = state or {}
    state.point, state.x, state.y = point, x, y
    states[tooltip] = state
    addon:SafeMethod(tooltip, "ClearAllPoints")
    addon:SafeMethod(tooltip, "SetPoint", point, UIParent, "BOTTOMLEFT", x, y)
    return true
end

local function AnchorToCursor(tooltip, point, offsetX, offsetY)
    StopCursorAnchor(tooltip)
    if not addon:IsTooltipSafe(tooltip) then return end

    local scale = addon:SafeMethod(tooltip, "GetEffectiveScale")
    if type(scale) ~= "number" or scale <= 0 then return end
    point = type(point) == "string" and point or "BOTTOM"
    offsetX, offsetY = tonumber(offsetX) or 0, tonumber(offsetY) or 20
    if not SetCursorPoint(tooltip, point, offsetX, offsetY, scale) then return end
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end

    local state = states[tooltip] or {}
    state.ticker = C_Timer.NewTicker(CURSOR_INTERVAL, function()
        if not addon:IsTooltipSafe(tooltip)
            or addon:SafeMethod(tooltip, "IsShown") ~= true
            or addon:SafeMethod(tooltip, "GetAnchorType") ~= "ANCHOR_CURSOR" then
            StopCursorAnchor(tooltip)
            return
        end
        SetCursorPoint(tooltip, point, offsetX, offsetY, scale)
    end)
    states[tooltip] = state
end

local function CursorQuadrant()
    local cursorX, cursorY = GetCursorPosition()
    local width, height = GetScreenWidth(), GetScreenHeight()
    local scale = addon:SafeMethod(UIParent, "GetEffectiveScale")
    if type(cursorX) ~= "number" or type(cursorY) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number"
        or type(scale) ~= "number" or scale <= 0 then
        return "BOTTOMLEFT"
    end

    cursorX, cursorY = cursorX / scale, cursorY / scale
    if cursorX > width / 2 then
        return cursorY > height / 2 and "TOPRIGHT" or "BOTTOMRIGHT"
    end
    return cursorY > height / 2 and "TOPLEFT" or "BOTTOMLEFT"
end

local function AnchorAuto(tooltip, offsetX, offsetY)
    local quadrant = CursorQuadrant()
    local point = "BOTTOMLEFT"
    offsetX, offsetY = tonumber(offsetX) or 0, tonumber(offsetY) or 20

    if quadrant == "TOPRIGHT" then
        point, offsetX, offsetY = "TOPRIGHT", offsetX - 10, offsetY - 10
    elseif quadrant == "TOPLEFT" then
        point, offsetX, offsetY = "TOPLEFT", offsetX + 10, offsetY - 10
    elseif quadrant == "BOTTOMRIGHT" then
        point, offsetX, offsetY = "BOTTOMRIGHT", offsetX - 10, offsetY + 10
    else
        point, offsetX, offsetY = "BOTTOMLEFT", offsetX + 10, offsetY + 10
    end
    AnchorToCursor(tooltip, point, offsetX, offsetY)
end

local function AnchorDefault(tooltip, parent, anchor, finalPass)
    StopCursorAnchor(tooltip)
    if type(anchor) ~= "table" then return end

    if not finalPass and anchor.position == "inherit" then
        local general = addon.db and addon.db.general
        AnchorDefault(tooltip, parent, general and general.anchor, true)
        return
    end
    LibEvent:trigger("tooltip.anchor.static", tooltip, parent, anchor.x, anchor.y, anchor.p)
end

local function ApplyAnchor(tooltip, parent, anchor, isUnitFrame, finalPass)
    if type(anchor) ~= "table" or not addon:IsTooltipSafe(tooltip) then return end
    StopCursorAnchor(tooltip)

    if anchor.hiddenInCombat == true and InCombatLockdown() then
        LibEvent:trigger("tooltip.anchor.none", tooltip, parent)
        return
    end
    if anchor.returnInCombat == true and InCombatLockdown() then
        AnchorDefault(tooltip, parent, anchor, finalPass)
        return
    end
    if anchor.returnOnUnitFrame == true and isUnitFrame then
        AnchorDefault(tooltip, parent, anchor, finalPass)
        return
    end

    local position = anchor.position
    if position == "cursorRight" then
        LibEvent:trigger("tooltip.anchor.cursor.right", tooltip, parent)
    elseif position == "cursor" then
        LibEvent:trigger("tooltip.anchor.cursor", tooltip, parent)
        AnchorToCursor(tooltip, anchor.cp, anchor.cx, anchor.cy)
    elseif position == "auto" then
        LibEvent:trigger("tooltip.anchor.cursor", tooltip, parent)
        AnchorAuto(tooltip, anchor.cx, anchor.cy)
    elseif position == "inherit" and not finalPass then
        local general = addon.db and addon.db.general
        ApplyAnchor(tooltip, parent, general and general.anchor, isUnitFrame, true)
    elseif position == "static" then
        LibEvent:trigger("tooltip.anchor.static", tooltip, parent, anchor.x, anchor.y, anchor.p)
    end
end

local function ResolveAnchorUnit(tooltip)
    local context = addon:GetPrimaryTooltipContext(tooltip)
    local unit = type(context) == "table" and context.unitToken or nil
    if not IsOrdinaryUnit(unit) then unit = addon:GetTooltipUnit(tooltip) end

    local focusUnit, _, unitOwner = addon:GetMouseFocusUnit()
    local isUnitFrame = addon:IsObjectAccessible(unitOwner)
    if not IsOrdinaryUnit(unit) and IsOrdinaryUnit(focusUnit) then unit = focusUnit end
    if not IsOrdinaryUnit(unit) then unit = nil end
    return unit, isUnitFrame
end

local function OnAnchor(_, tooltip, parent)
    if tooltip ~= GameTooltip or not addon:IsTooltipSafe(tooltip) or type(addon.db) ~= "table" then return end
    if not addon:IsObjectAccessible(parent) then parent = UIParent end

    local unit, isUnitFrame = ResolveAnchorUnit(tooltip)
    local unitConfig = addon.db.unit
    local general = addon.db.general
    local isPlayer = IsOrdinaryUnit(unit) and addon:SafeCallBoolean(UnitIsPlayer, unit) or nil
    local exists = IsOrdinaryUnit(unit) and addon:SafeCallBoolean(UnitExists, unit) or nil

    if isPlayer == true and type(unitConfig) == "table" and type(unitConfig.player) == "table" then
        ApplyAnchor(tooltip, parent, unitConfig.player.anchor, isUnitFrame)
    elseif exists == true and type(unitConfig) == "table" and type(unitConfig.npc) == "table" then
        ApplyAnchor(tooltip, parent, unitConfig.npc.anchor, isUnitFrame)
    elseif type(general) == "table" then
        ApplyAnchor(tooltip, parent, general.anchor, isUnitFrame)
    end
end

local M = {}

function M:Init()
    self.cbAnchor = OnAnchor
    self.cbStop = function(_, tooltip) StopCursorAnchor(tooltip) end
end

function M:Enable()
    addon.MM:AttachTrigger("Anchor", "tooltip:anchor", self.cbAnchor, "tooltip:anchor")
    addon.MM:AttachTrigger("Anchor", "tooltip:cleared, tooltip:hide", self.cbStop, "tooltip:clear")
end

function M:Disable()
    StopCursorAnchor(GameTooltip)
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Anchor", M)
