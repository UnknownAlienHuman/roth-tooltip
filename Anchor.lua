local _, addon = ...
local LibEvent = addon.LibEvent

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

local function ResolveCursorPoint(mode, point, offsetX, offsetY)
    local scale = addon:SafeMethod(UIParent, "GetEffectiveScale")
    local cursorX, cursorY = GetCursorPosition()
    if not addon:CanAccessAllValues(scale, cursorX, cursorY)
        or type(scale) ~= "number" or scale <= 0
        or type(cursorX) ~= "number" or type(cursorY) ~= "number" then return nil end

    cursorX, cursorY = cursorX / scale, cursorY / scale
    point = type(point) == "string" and point or "BOTTOM"
    offsetX, offsetY = tonumber(offsetX) or 0, tonumber(offsetY) or 20

    if mode == "auto" then
        local width = addon:SafeMethod(UIParent, "GetWidth")
        local height = addon:SafeMethod(UIParent, "GetHeight")
        if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
        local right, top = cursorX > width / 2, cursorY > height / 2
        if right and top then
            point, offsetX, offsetY = "TOPRIGHT", offsetX - 10, offsetY - 10
        elseif top then
            point, offsetX, offsetY = "TOPLEFT", offsetX + 10, offsetY - 10
        elseif right then
            point, offsetX, offsetY = "BOTTOMRIGHT", offsetX - 10, offsetY + 10
        else
            point, offsetX, offsetY = "BOTTOMLEFT", offsetX + 10, offsetY + 10
        end
    end

    return point, floor(cursorX + offsetX), floor(cursorY + offsetY)
end

local function UpdateCursorAnchor(tooltip, state, point, x, y)
    if states[tooltip] ~= state or not addon:IsTooltipSafe(tooltip) then return false end
    if not point then point, x, y = ResolveCursorPoint(state.mode, state.point, state.offsetX, state.offsetY) end
    if not point then return false end
    if state.currentPoint == point and state.x == x and state.y == y then return true end
    state.currentPoint, state.x, state.y = point, x, y
    addon:SafeMethod(tooltip, "ClearAllPoints")
    addon:SafeMethod(tooltip, "SetPoint", point, UIParent, "BOTTOMLEFT", x, y)
    return true
end

local function StartCursorAnchor(tooltip, parent, mode, point, offsetX, offsetY)
    StopCursorAnchor(tooltip)
    if not addon:IsTooltipSafe(tooltip) or not addon:IsObjectAccessible(parent) then return false end

    -- Resolve ordinary cursor geometry before claiming ANCHOR_NONE. A denied or
    -- unavailable cursor path must leave enough native state for the static
    -- fallback instead of marooning the tooltip without an anchor owner.
    local resolvedPoint, x, y = ResolveCursorPoint(mode, point, offsetX, offsetY)
    if not resolvedPoint then return false end

    local setOwner = addon:SafeGet(tooltip, "SetOwner")
    if type(setOwner) ~= "function" or not pcall(setOwner, tooltip, parent, "ANCHOR_NONE") then return false end

    local state = { mode = mode, point = point, offsetX = offsetX, offsetY = offsetY }
    states[tooltip] = state
    if not UpdateCursorAnchor(tooltip, state, resolvedPoint, x, y) then states[tooltip] = nil; return false end
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return true end

    state.ticker = C_Timer.NewTicker(CURSOR_INTERVAL, function()
        if states[tooltip] ~= state then return end
        if not addon.MM:IsEnabled("Anchor") or not addon:IsTooltipSafe(tooltip)
            or addon:SafeMethod(tooltip, "IsShown") ~= true
            or addon:SafeMethod(tooltip, "GetAnchorType") ~= "ANCHOR_NONE"
            or not UpdateCursorAnchor(tooltip, state) then
            StopCursorAnchor(tooltip)
        end
    end)
    return true
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
        LibEvent:trigger("tooltip.anchor.cursor.right", tooltip, parent, anchor.cx, anchor.cy)
    elseif position == "cursor" then
        if not StartCursorAnchor(tooltip, parent, "cursor", anchor.cp, anchor.cx, anchor.cy) then
            AnchorDefault(tooltip, parent, anchor, finalPass)
        end
    elseif position == "auto" then
        if not StartCursorAnchor(tooltip, parent, "auto", nil, anchor.cx, anchor.cy) then
            AnchorDefault(tooltip, parent, anchor, finalPass)
        end
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
    if not addon:CanAccessValue(tooltip) or tooltip ~= GameTooltip or not addon:IsTooltipSafe(tooltip) or type(addon.db) ~= "table" then return end
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
    self.cbStop = function(_, tooltip)
        if addon:CanAccessValue(tooltip) and tooltip ~= nil then StopCursorAnchor(tooltip) end
    end
    self.cbProfile = function() StopCursorAnchor(GameTooltip) end
    self.cbVariable = function(_, key)
        if type(key) == "string" and key:find("anchor", 1, true) then StopCursorAnchor(GameTooltip) end
    end
end

function M:Enable()
    addon.MM:AttachTrigger("Anchor", "tooltip:anchor", self.cbAnchor, "tooltip:anchor")
    addon.MM:AttachTrigger("Anchor", "tooltip:variables:loaded", self.cbProfile)
    addon.MM:AttachTrigger("Anchor", "tooltip:variable:changed", self.cbVariable)
    addon.MM:AttachTrigger("Anchor", "tooltip:hide, tooltip:unregister, tooltip:invalidated", self.cbStop, "tooltip:clear")
end

function M:Disable()
    StopCursorAnchor(GameTooltip)
end


addon.MM:RegisterModule("Anchor", M)
