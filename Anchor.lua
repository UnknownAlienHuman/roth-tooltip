local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local CURSOR_ANCHOR_INTERVAL = 0.05
local anchorStates = setmetatable({}, { __mode = "k" })

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function IsOrdinaryUnit(unit)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return false end
    if addon.IsUnitIdentityRestricted and addon:IsUnitIdentityRestricted(unit) then return false end
    return true
end

local function CancelTicker(ticker)
    if not CanAccess(ticker) or ticker == nil then return end
    local cancel = addon:SafeGet(ticker, "Cancel")
    if type(cancel) == "function" then pcall(cancel, ticker) end
end

local function StopAnchorTicker(tip)
    if not CanAccess(tip) or tip == nil then return end
    local state = anchorStates[tip]
    if state then CancelTicker(state.ticker) end
    anchorStates[tip] = nil
end

local function SetCursorAnchorPoint(tip, point, offsetX, offsetY, scale)
    if not addon:IsTooltipSafe(tip) then return false end
    if type(scale) ~= "number" or scale <= 0 then return false end

    local cursorX, cursorY = GetCursorPosition()
    if not CanAccess(cursorX) or not CanAccess(cursorY)
        or type(cursorX) ~= "number" or type(cursorY) ~= "number" then
        return false
    end

    local anchorX = floor(cursorX / scale + offsetX)
    local anchorY = floor(cursorY / scale + offsetY)
    local state = anchorStates[tip]
    if state and state.point == point and state.x == anchorX and state.y == anchorY then
        return true
    end

    state = state or {}
    state.point = point
    state.x = anchorX
    state.y = anchorY
    anchorStates[tip] = state

    addon:SafeMethod(tip, "ClearAllPoints")
    addon:SafeMethod(tip, "SetPoint", point, UIParent, "BOTTOMLEFT", anchorX, anchorY)
    return true
end

local function AnchorCursor(tip, point, offsetX, offsetY)
    StopAnchorTicker(tip)
    if not addon:IsTooltipSafe(tip) then return end

    local scale = addon:SafeMethod(tip, "GetEffectiveScale")
    if not CanAccess(scale) or type(scale) ~= "number" or scale <= 0 then return end

    point = type(point) == "string" and point or "BOTTOM"
    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 20
    if not SetCursorAnchorPoint(tip, point, offsetX, offsetY, scale) then return end
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end

    local state = anchorStates[tip] or {}
    state.ticker = C_Timer.NewTicker(CURSOR_ANCHOR_INTERVAL, function()
        if not addon:IsTooltipSafe(tip)
            or addon:SafeMethod(tip, "IsShown") ~= true
            or addon:SafeMethod(tip, "GetAnchorType") ~= "ANCHOR_CURSOR" then
            StopAnchorTicker(tip)
            return
        end
        SetCursorAnchorPoint(tip, point, offsetX, offsetY, scale)
    end)
    anchorStates[tip] = state
end

local function GetQuadrant()
    local cursorX, cursorY = GetCursorPosition()
    local width, height = GetScreenWidth(), GetScreenHeight()
    local scale = addon:SafeMethod(UIParent, "GetEffectiveScale")
    if not CanAccess(cursorX) or not CanAccess(cursorY) or not CanAccess(width)
        or not CanAccess(height) or not CanAccess(scale) then
        return "BOTTOMLEFT"
    end
    if type(cursorX) ~= "number" or type(cursorY) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number"
        or type(scale) ~= "number" or scale <= 0 then
        return "BOTTOMLEFT"
    end

    cursorX = cursorX / scale
    cursorY = cursorY / scale
    if cursorX > width / 2 then
        return cursorY > height / 2 and "TOPRIGHT" or "BOTTOMRIGHT"
    end
    return cursorY > height / 2 and "TOPLEFT" or "BOTTOMLEFT"
end

local function AnchorAuto(tip, offsetX, offsetY)
    local quadrant = GetQuadrant()
    local point = "BOTTOMLEFT"
    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 20

    if quadrant == "TOPRIGHT" then
        point, offsetX, offsetY = "TOPRIGHT", offsetX - 10, offsetY - 10
    elseif quadrant == "TOPLEFT" then
        point, offsetX, offsetY = "TOPLEFT", offsetX + 10, offsetY - 10
    elseif quadrant == "BOTTOMRIGHT" then
        point, offsetX, offsetY = "BOTTOMRIGHT", offsetX - 10, offsetY + 10
    else
        point, offsetX, offsetY = "BOTTOMLEFT", offsetX + 10, offsetY + 10
    end
    AnchorCursor(tip, point, offsetX, offsetY)
end

local function AnchorDefaultPosition(tip, parent, anchor, finalPass)
    StopAnchorTicker(tip)
    if type(anchor) ~= "table" then return end

    if finalPass then
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y)
    elseif anchor.position == "inherit" then
        local general = addon.db and addon.db.general
        AnchorDefaultPosition(tip, parent, general and general.anchor, true)
    else
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y, anchor.p)
    end
end

local function AnchorFrame(tip, parent, anchor, isUnitFrame, finalPass)
    if type(anchor) ~= "table" or not addon:IsTooltipSafe(tip) then return end
    StopAnchorTicker(tip)

    if anchor.hiddenInCombat == true and InCombatLockdown() then
        LibEvent:trigger("tooltip.anchor.none", tip, parent)
        return
    end
    if anchor.returnInCombat == true and InCombatLockdown() then
        AnchorDefaultPosition(tip, parent, anchor, finalPass)
        return
    end
    if anchor.returnOnUnitFrame == true and isUnitFrame then
        AnchorDefaultPosition(tip, parent, anchor, finalPass)
        return
    end

    local position = anchor.position
    if position == "cursorRight" then
        LibEvent:trigger("tooltip.anchor.cursor.right", tip, parent)
    elseif position == "cursor" then
        LibEvent:trigger("tooltip.anchor.cursor", tip, parent)
        AnchorCursor(tip, anchor.cp, anchor.cx, anchor.cy)
    elseif position == "auto" then
        LibEvent:trigger("tooltip.anchor.cursor", tip, parent)
        AnchorAuto(tip, anchor.cx, anchor.cy)
    elseif position == "inherit" and not finalPass then
        local general = addon.db and addon.db.general
        AnchorFrame(tip, parent, general and general.anchor, isUnitFrame, true)
    elseif position == "static" then
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y, anchor.p)
    end
end

local function ResolveAnchorUnit(tip)
    local context = addon:GetPrimaryTooltipContext(tip)
    local unit = type(context) == "table" and context.unitToken or nil
    if not IsOrdinaryUnit(unit) then unit = addon:GetTooltipUnit(tip) end

    local focusUnit, _, unitOwner = addon:GetMouseFocusUnit()
    local isUnitFrame = addon:IsObjectAccessible(unitOwner)
    if not IsOrdinaryUnit(unit) and IsOrdinaryUnit(focusUnit) then unit = focusUnit end
    if not IsOrdinaryUnit(unit) then unit = nil end
    return unit, isUnitFrame
end

local M = {}

function M:Init()
    self.cbAnchor = function(_, tip, parent)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Anchor") then return end
        if not CanAccess(tip) or tip ~= GameTooltip or not addon:IsTooltipSafe(tip) then return end
        if type(addon.db) ~= "table" then return end

        if not addon:IsObjectAccessible(parent) then parent = UIParent end
        local unit, isUnitFrame = ResolveAnchorUnit(tip)
        local unitConfig = addon.db.unit
        local general = addon.db.general

        local isPlayer = IsOrdinaryUnit(unit) and addon:SafeCallBoolean(UnitIsPlayer, unit) or nil
        local exists = IsOrdinaryUnit(unit) and addon:SafeCallBoolean(UnitExists, unit) or nil

        if isPlayer == true and type(unitConfig) == "table" and type(unitConfig.player) == "table" then
            AnchorFrame(tip, parent, unitConfig.player.anchor, isUnitFrame)
        elseif exists == true and type(unitConfig) == "table" and type(unitConfig.npc) == "table" then
            AnchorFrame(tip, parent, unitConfig.npc.anchor, isUnitFrame)
        elseif type(general) == "table" then
            AnchorFrame(tip, parent, general.anchor, isUnitFrame)
        end
    end

    self.cbStopTicker = function(_, tip)
        StopAnchorTicker(tip)
    end
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("Anchor", "tooltip:anchor", self.cbAnchor, "tooltip:anchor")
        addon.MM:AttachTrigger("Anchor", "tooltip:cleared, tooltip:hide", self.cbStopTicker, "tooltip:cleared/hide")
    end
end

function M:Disable()
    StopAnchorTicker(GameTooltip)
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Anchor", M)
end
