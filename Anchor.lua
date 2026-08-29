local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local CURSOR_INTERVAL = 0.05
local states = setmetatable({}, { __mode = "k" })
local defaultAnchorHookInstalled = false

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

local function CursorPositionInUIParent()
    local cursorX, cursorY = GetCursorPosition()
    local scale = addon:SafeMethod(UIParent, "GetEffectiveScale")
    if type(cursorX) ~= "number" or type(cursorY) ~= "number"
        or type(scale) ~= "number" or scale <= 0 then
        return nil
    end
    return cursorX / scale, cursorY / scale
end

local function SetCursorPoint(tooltip, point, offsetX, offsetY)
    if not addon:IsTooltipSafe(tooltip) then return false end
    local cursorX, cursorY = CursorPositionInUIParent()
    if not cursorX then return false end

    local x = floor(cursorX + offsetX)
    local y = floor(cursorY + offsetY)
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

    point = type(point) == "string" and point or "BOTTOM"
    offsetX, offsetY = tonumber(offsetX) or 0, tonumber(offsetY) or 20
    if not SetCursorPoint(tooltip, point, offsetX, offsetY) then return end
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end

    local state = states[tooltip] or {}
    state.ticker = C_Timer.NewTicker(CURSOR_INTERVAL, function()
        if not addon:IsTooltipSafe(tooltip)
            or addon:SafeMethod(tooltip, "IsShown") ~= true
            or addon:SafeMethod(tooltip, "GetAnchorType") ~= "ANCHOR_CURSOR" then
            StopCursorAnchor(tooltip)
            return
        end
        SetCursorPoint(tooltip, point, offsetX, offsetY)
    end)
    states[tooltip] = state
end

local function CursorQuadrant()
    local cursorX, cursorY = CursorPositionInUIParent()
    local width, height = GetScreenWidth(), GetScreenHeight()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number" then
        return "BOTTOMLEFT"
    end

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
    elseif position == "static" or position == "default" then
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

local function InstallDefaultAnchorHook()
    if defaultAnchorHookInstalled or type(hooksecurefunc) ~= "function"
        or type(GameTooltip_SetDefaultAnchor) ~= "function" then return end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if addon.MM:IsEnabled("Anchor") then
            LibEvent:trigger("tooltip:anchor", tooltip, parent)
        end
    end)
    defaultAnchorHookInstalled = true
end

local M = {}

function M:Init()
    self.cbAnchor = OnAnchor
    self.cbStop = function(_, tooltip) StopCursorAnchor(tooltip) end
end

function M:Enable()
    InstallDefaultAnchorHook()
    addon.MM:AttachTrigger("Anchor", "tooltip:anchor", self.cbAnchor, "tooltip:anchor")
    addon.MM:AttachTrigger("Anchor", "tooltip:cleared, tooltip:hide", self.cbStop, "tooltip:clear")
    addon.MM:AttachTrigger("Anchor", "tooltip.anchor.cursor", function(_, tooltip, parent)
        if addon:IsTooltipSafe(tooltip) and addon:IsObjectAccessible(parent) then
            addon:SafeMethod(tooltip, "SetOwner", parent, "ANCHOR_CURSOR")
        end
    end, "anchor-cursor")
    addon.MM:AttachTrigger("Anchor", "tooltip.anchor.cursor.right", function(_, tooltip, parent, x, y)
        if addon:IsTooltipSafe(tooltip) and addon:IsObjectAccessible(parent) then
            addon:SafeMethod(tooltip, "SetOwner", parent, "ANCHOR_CURSOR_RIGHT",
                tonumber(x) or 36, tonumber(y) or -12)
        end
    end, "anchor-cursor-right")
    addon.MM:AttachTrigger("Anchor", "tooltip.anchor.static", function(_, tooltip, _, x, y, point)
        if not addon:IsTooltipSafe(tooltip) then return end
        point = type(point) == "string" and point or "BOTTOMRIGHT"
        addon:SafeMethod(tooltip, "ClearAllPoints")
        addon:SafeMethod(tooltip, "SetPoint", point, UIParent, point,
            tonumber(x) or (-CONTAINER_OFFSET_X - 13), tonumber(y) or CONTAINER_OFFSET_Y)
    end, "anchor-static")
    addon.MM:AttachTrigger("Anchor", "tooltip.anchor.none", function(_, tooltip, parent)
        if addon:IsTooltipSafe(tooltip) and addon:IsObjectAccessible(parent) then
            addon:SafeMethod(tooltip, "SetOwner", parent, "ANCHOR_NONE")
            addon:SafeMethod(tooltip, "Hide")
        end
    end, "anchor-none")
end

function M:Disable()
    StopCursorAnchor(GameTooltip)
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Anchor", M)
