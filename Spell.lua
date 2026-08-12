local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function GetValidSpellID(value)
    if (not addon:IsSecret(value) and type(value) == "number") then
        return value
    end
    return nil
end

local function ForEachSpellTooltipFrame(tip, callback)
    if (not tip or type(callback) ~= "function") then
        return
    end

    local seen = {}
    local function Visit(frame)
        if (frame and seen[frame]) then
            return
        end
        if (frame and not seen[frame]) then
            seen[frame] = true
            callback(frame)
        end
    end

    Visit(tip)
    Visit(tip.Tooltip)
    Visit(tip.ItemTooltip)
    Visit(tip.FollowerTooltip)
end

local function ResolveSpellContext(tip, explicitContext)
    if (explicitContext and GetValidSpellID(explicitContext.spellID)) then
        return explicitContext
    end

    local resolvedContext = nil
    ForEachSpellTooltipFrame(tip, function(frame)
        if (resolvedContext) then
            return
        end

        local frameContext = addon:GetPrimaryTooltipContext(frame)
        if (frameContext and GetValidSpellID(frameContext.spellID)) then
            resolvedContext = frameContext
        end
    end)

    if (resolvedContext) then
        return resolvedContext
    end

    local resolvedSpellID = nil
    ForEachSpellTooltipFrame(tip, function(frame)
        if (resolvedSpellID) then
            return
        end
        resolvedSpellID = GetValidSpellID(addon:SafeGetSpellID(frame))
    end)

    if (resolvedSpellID) then
        return { spellID = resolvedSpellID }
    end

    return explicitContext
end

local function TryPrefixHeader(frame, iconMarkup)
    if (not frame) then
        return false
    end

    local line = addon:GetLine(frame, 1)
    if (line and line.GetText and line.SetFormattedText) then
        local text = line:GetText()
        if (not addon:IsSecret(text) and text and text ~= "") then
            if (not string.match(text, "^|T.+|t")) then
                line:SetFormattedText("%s%s", iconMarkup, text)
            end
            return true
        end
    end

    local fs = frame.Text
    if (fs and fs.GetText and fs.SetFormattedText) then
        local text = fs:GetText()
        if (not addon:IsSecret(text) and text and text ~= "") then
            if (not string.match(text, "^|T.+|t")) then
                fs:SetFormattedText("%s%s", iconMarkup, text)
            end
            return true
        end
    end

    return false
end

local function ApplySpellTextureFallback(frame, texture)
    if (not frame) then
        return false
    end

    local texObj = frame.Icon
    if (texObj and texObj.SetTexture) then
        texObj:SetTexture(texture)
        if (texObj.Show) then
            texObj:Show()
        end
        return true
    end

    return false
end

local function HideSpellIconBorder(frame)
    if (not frame) then
        return
    end

    local border = frame.IconBorder
    if (border and border.Hide) then
        border:Hide()
    elseif (border and border.SetAlpha) then
        border:SetAlpha(0)
    end
end

local function SpellIcon(tip, context)
    if (not addon.db or not addon.db.spell or not addon.db.spell.showIcon) then return end
    if (not tip) then return end

    local spellContext = ResolveSpellContext(tip, context)
    local spellID = GetValidSpellID(spellContext and spellContext.spellID)
    if (not spellID) then return end

    local texture = C_Spell.GetSpellTexture(spellID)
    if (not texture or addon:IsSecret(texture)) then return end

    local icon = string.format("|T%s:20:20:0:0:64:64:4:60:4:60|t ", texture)
    local applied = false
    ForEachSpellTooltipFrame(tip, function(frame)
        if (not applied and TryPrefixHeader(frame, icon)) then
            applied = true
        end
        HideSpellIconBorder(frame)
    end)

    if (applied) then
        return
    end

    ForEachSpellTooltipFrame(tip, function(frame)
        if (not applied and ApplySpellTextureFallback(frame, texture)) then
            applied = true
        end
    end)
end

-- Some spell tooltip pipelines render through nested tooltip frames.
-- Keep spell skinning lightweight and idempotent.
local function ApplySpellSkin(tip)
    if (not tip) then return end
    if (not addon:AllowTrigger("spell", tip)) then return end

    addon:ApplyGeneralStyleToTooltip(tip)
end

local function OnTooltipSpell(self, tip, context)
    if (not tip) then return end
    if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Spell")) then return end
    if (addon.AllowTrigger and not addon:AllowTrigger("spell", tip)) then return end
    local started
    if (addon.MM and addon.MM.OnCallStart) then
        started = addon.MM:OnCallStart("Spell", "tooltip:spell")
    end

    local spellContext = ResolveSpellContext(tip, context)
    ForEachSpellTooltipFrame(tip, ApplySpellSkin)
    SpellIcon(tip, spellContext)
    if (addon.MM and addon.MM.OnCallEnd) then
        addon.MM:OnCallEnd("Spell", started)
    end
end

-- Clear cached spell id when tooltips reset to avoid applying spell overrides to non-spell tooltips.
local function OnTooltipCleared(self, tip)
    if (tip) then
        tip.__RT_LastSpellID = nil
        tip.__RT_LegacySpellDispatchPending = nil
    end
end

-- Module wrapper
local M = {}

function M:Init()
    self.cbSpell = OnTooltipSpell
    self.cbCleared = OnTooltipCleared
end

function M:Enable()
    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("Spell", "tooltip:spell", self.cbSpell, "tooltip:spell")
        addon.MM:AttachTrigger("Spell", "tooltip:cleared", self.cbCleared, "tooltip:cleared")
    else
        LibEvent:attachTrigger("tooltip:spell", self.cbSpell)
        LibEvent:attachTrigger("tooltip:cleared", self.cbCleared)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Spell", M)
end
