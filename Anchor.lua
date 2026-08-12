local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
local CURSOR_ANCHOR_INTERVAL = 0.05

local function StopAnchorTicker(tip)
    if (not tip) then return end
    local ticker = tip.__RTAnchorTicker
    if (ticker) then
        tip.__RTAnchorTicker = nil
        ticker:Cancel()
    end
    tip.__RTAnchorPoint = nil
    tip.__RTAnchorX = nil
    tip.__RTAnchorY = nil
end

local function SetCursorAnchorPoint(tip, cp, cx, cy, scale)
    local x, y = GetCursorPosition()
    local anchorX = floor(x / scale + cx)
    local anchorY = floor(y / scale + cy)

    if (tip.__RTAnchorPoint == cp and tip.__RTAnchorX == anchorX and tip.__RTAnchorY == anchorY) then
        return
    end

    tip.__RTAnchorPoint = cp
    tip.__RTAnchorX = anchorX
    tip.__RTAnchorY = anchorY
    tip:ClearAllPoints()
    tip:SetPoint(cp, UIParent, "BOTTOMLEFT", anchorX, anchorY)
end

local function AnchorCursor(tip, parent, cp, cx, cy)
    StopAnchorTicker(tip)
    local scale = tip:GetEffectiveScale()
    cp, cx, cy = cp or "BOTTOM", cx or 0, cy or 20

    SetCursorAnchorPoint(tip, cp, cx, cy, scale)

    tip.__RTAnchorTicker = C_Timer.NewTicker(CURSOR_ANCHOR_INTERVAL, function()
        if (not tip:IsShown()) or (tip:GetAnchorType() ~= "ANCHOR_CURSOR") then
            StopAnchorTicker(tip)
            return
        end
        SetCursorAnchorPoint(tip, cp, cx, cy, scale)
    end)
end

local function GetQuadrant()
    local x, y = GetCursorPosition()
    local w, h = GetScreenWidth(), GetScreenHeight()
    local s = UIParent:GetEffectiveScale()
    x, y = x/s, y/s
    if (x > w/2) then
        return (y > h/2) and "TOPRIGHT" or "BOTTOMRIGHT"
    else
        return (y > h/2) and "TOPLEFT" or "BOTTOMLEFT"
    end
end

local function AnchorAuto(tip, parent, cx, cy)
    local quad = GetQuadrant()
    local cp = "BOTTOMLEFT"
    if (quad == "TOPRIGHT") then cp = "TOPRIGHT"; cx = cx - 10; cy = cy - 10
    elseif (quad == "TOPLEFT") then cp = "TOPLEFT"; cx = cx + 10; cy = cy - 10
    elseif (quad == "BOTTOMRIGHT") then cp = "BOTTOMRIGHT"; cx = cx - 10; cy = cy + 10
    elseif (quad == "BOTTOMLEFT") then cp = "BOTTOMLEFT"; cx = cx + 10; cy = cy + 10
    end
    AnchorCursor(tip, parent, cp, cx, cy)
end

local function AnchorDefaultPosition(tip, parent, anchor, finally)
    StopAnchorTicker(tip)
    if (finally) then
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y)
    elseif (anchor.position == "inherit") then
        AnchorDefaultPosition(tip, parent, addon.db.general.anchor, true)
    else
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y, anchor.p)
    end
end

local function AnchorFrame(tip, parent, anchor, isUnitFrame, finally)
    if (not anchor) then return end
    StopAnchorTicker(tip)
    if (anchor.hiddenInCombat and InCombatLockdown()) then
        return LibEvent:trigger("tooltip.anchor.none", tip, parent)
    end
    if (anchor.returnInCombat and InCombatLockdown()) then return AnchorDefaultPosition(tip, parent, anchor, finally) end
    if (anchor.returnOnUnitFrame and isUnitFrame) then return AnchorDefaultPosition(tip, parent, anchor, finally) end
    if (anchor.position == "cursorRight") then
        LibEvent:trigger("tooltip.anchor.cursor.right", tip, parent)
    elseif (anchor.position == "cursor") then
        LibEvent:trigger("tooltip.anchor.cursor", tip, parent)
        AnchorCursor(tip, parent, anchor.cp, anchor.cx, anchor.cy)
    elseif (anchor.position == "auto") then
        LibEvent:trigger("tooltip.anchor.cursor", tip, parent)
        AnchorAuto(tip, parent, anchor.cx or 0, anchor.cy or 20)
    elseif (anchor.position == "inherit" and not finally) then
        AnchorFrame(tip, parent, addon.db.general.anchor, isUnitFrame, true)
    elseif (anchor.position == "static") then
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y, anchor.p)
    end
end

local function ResolveAnchorUnit(tip)
    local context = addon:GetPrimaryTooltipContext(tip)
    local unit = context and context.unitToken

    if (addon:IsSecret(unit) or type(unit) ~= "string" or unit == "") then
        unit = addon:GetTooltipUnit(tip)
    end

    local focusUnit, _, owner = addon:GetMouseFocusUnit()
    local isUnitFrame = owner ~= nil
    if ((addon:IsSecret(unit) or type(unit) ~= "string" or unit == "") and focusUnit) then
        unit = addon:ResolveUnitToken(focusUnit, context and context.guid)
    end

    if ((addon:IsSecret(unit) or type(unit) ~= "string" or unit == "") and tip == GameTooltip) then
        unit = "mouseover"
    end

    if (addon:IsSecret(unit) or type(unit) ~= "string" or unit == "") then
        unit = nil
    end

    return unit, isUnitFrame
end

--=========================================================
-- Module wrapper
--=========================================================
local M = {}

function M:Init()
    self.cbAnchor = function(_, tip, parent)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Anchor")) then return end
        if (tip ~= GameTooltip) then return end
        if (not addon.db) then return end

        local unit, isUnitFrame = ResolveAnchorUnit(tip)

        local isPlayer = unit and addon.SafeCallBoolean and addon:SafeCallBoolean(UnitIsPlayer, unit)
        local exists = unit and addon.SafeCallBoolean and addon:SafeCallBoolean(UnitExists, unit)

        if (isPlayer) then
            AnchorFrame(tip, parent, addon.db.unit.player.anchor, isUnitFrame)
        elseif (exists) then
            AnchorFrame(tip, parent, addon.db.unit.npc.anchor, isUnitFrame)
        else
            AnchorFrame(tip, parent, addon.db.general.anchor, isUnitFrame)
        end
    end

    self.cbStopTicker = function(_, tip)
        StopAnchorTicker(tip)
    end
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("Anchor", "tooltip:anchor", self.cbAnchor, "tooltip:anchor")
        addon.MM:AttachTrigger("Anchor", "tooltip:cleared, tooltip:hide", self.cbStopTicker, "tooltip:cleared/hide")
    end
end

function M:Disable()
    StopAnchorTicker(GameTooltip)
end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Anchor", M)
end
