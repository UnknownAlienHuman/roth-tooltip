local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function GetValidSpellID(value)
    if not CanAccess(value) then return nil end
    if type(value) == "number" and value > 0 then return value end
    return nil
end

local function ForEachSpellTooltipFrame(tip, callback)
    if not addon:IsObjectAccessible(tip) or type(callback) ~= "function" then return end

    local seen = {}
    local function Visit(frame)
        if not addon:IsObjectAccessible(frame) or seen[frame] then return end
        seen[frame] = true
        callback(frame)
    end

    Visit(tip)
    Visit(addon:SafeGet(tip, "Tooltip"))
    Visit(addon:SafeGet(tip, "ItemTooltip"))
    Visit(addon:SafeGet(tip, "FollowerTooltip"))
end

local function ResolveSpellContext(tip, explicitContext)
    if CanAccess(explicitContext) and type(explicitContext) == "table"
        and GetValidSpellID(explicitContext.spellID) then
        return explicitContext
    end

    local resolvedContext
    ForEachSpellTooltipFrame(tip, function(frame)
        if resolvedContext then return end
        local context = addon:GetPrimaryTooltipContext(frame)
        if type(context) == "table" and GetValidSpellID(context.spellID) then
            resolvedContext = context
        end
    end)
    if resolvedContext then return resolvedContext end

    local resolvedSpellID
    ForEachSpellTooltipFrame(tip, function(frame)
        if resolvedSpellID then return end
        resolvedSpellID = GetValidSpellID(addon:SafeGetSpellID(frame))
    end)
    if resolvedSpellID then return { spellID = resolvedSpellID } end

    return nil
end

local function PrefixFontString(fontString, iconMarkup)
    if not addon:IsObjectAccessible(fontString) then return false end

    local text = addon:SafeMethod(fontString, "GetText")
    if not CanAccess(text) or type(text) ~= "string" or text == "" then return false end
    if not text:match("^|T.+|t") then
        addon:SafeMethod(fontString, "SetFormattedText", "%s%s", iconMarkup, text)
    end
    return true
end

local function TryPrefixHeader(frame, iconMarkup)
    if not addon:IsObjectAccessible(frame) then return false end

    local line = addon:GetLine(frame, 1)
    if PrefixFontString(line, iconMarkup) then return true end

    local text = addon:SafeGet(frame, "Text")
    return PrefixFontString(text, iconMarkup)
end

local function ApplySpellTextureFallback(frame, texture)
    if not addon:IsObjectAccessible(frame) then return false end

    local icon = addon:SafeGet(frame, "Icon")
    if not addon:IsObjectAccessible(icon) then return false end
    addon:SafeMethod(icon, "SetTexture", texture)
    addon:SafeMethod(icon, "Show")
    return true
end

local function HideSpellIconBorder(frame)
    if not addon:IsObjectAccessible(frame) then return end
    local border = addon:SafeGet(frame, "IconBorder")
    if not addon:IsObjectAccessible(border) then return end

    local hide = addon:SafeGet(border, "Hide")
    if type(hide) == "function" then
        addon:SafeMethod(border, "Hide")
    else
        addon:SafeMethod(border, "SetAlpha", 0)
    end
end

local function GetSpellTexture(spellID)
    if not C_Spell or type(C_Spell.GetSpellTexture) ~= "function" then return nil end
    local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if not ok or not CanAccess(texture) then return nil end
    if type(texture) ~= "number" and type(texture) ~= "string" then return nil end
    return texture
end

local function ApplySpellIcon(tip, context)
    local spellConfig = addon.db and addon.db.spell
    if type(spellConfig) ~= "table" or spellConfig.showIcon ~= true then return end
    if not addon:IsTooltipSafe(tip) then return end

    local spellContext = ResolveSpellContext(tip, context)
    local spellID = spellContext and GetValidSpellID(spellContext.spellID) or nil
    if not spellID then return end

    local texture = GetSpellTexture(spellID)
    if texture == nil then return end

    local iconMarkup = string.format("|T%s:20:20:0:0:64:64:4:60:4:60|t ", tostring(texture))
    local applied = false

    ForEachSpellTooltipFrame(tip, function(frame)
        if not applied and TryPrefixHeader(frame, iconMarkup) then applied = true end
        HideSpellIconBorder(frame)
    end)

    if applied then return end
    ForEachSpellTooltipFrame(tip, function(frame)
        if not applied and ApplySpellTextureFallback(frame, texture) then applied = true end
    end)
end

local function ApplySpellSkin(tip)
    if not addon:IsTooltipSafe(tip) then return end
    if not addon:AllowTrigger("spell", tip) then return end
    addon:ApplyGeneralStyleToTooltip(tip)
end

local function OnTooltipSpell(_, tip, context)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Spell") then return end
    if not addon:IsTooltipSafe(tip) then return end
    if addon.AllowTrigger and not addon:AllowTrigger("spell", tip) then return end

    local started
    if addon.MM and addon.MM.OnCallStart then
        started = addon.MM:OnCallStart("Spell", "tooltip:spell")
    end

    local spellContext = ResolveSpellContext(tip, context)
    ForEachSpellTooltipFrame(tip, ApplySpellSkin)
    ApplySpellIcon(tip, spellContext)

    if addon.MM and addon.MM.OnCallEnd then addon.MM:OnCallEnd("Spell", started) end
end

local M = {}

function M:Init()
    self.cbSpell = OnTooltipSpell
end

function M:Enable()
    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("Spell", "tooltip:spell", self.cbSpell, "tooltip:spell")
    else
        LibEvent:attachTrigger("tooltip:spell", self.cbSpell)
    end
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Spell", M)
end
