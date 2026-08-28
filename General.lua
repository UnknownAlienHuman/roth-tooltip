local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

RothTooltipDB = RothTooltipDB or {}
RothTooltipCharacterDB = RothTooltipCharacterDB or {}

local REACTION_COLORS = {
    [1] = { 1.0, 0.0, 0.0 },
    [2] = { 1.0, 0.0, 0.0 },
    [3] = { 1.0, 0.5, 0.0 },
    [4] = { 1.0, 1.0, 0.0 },
    [5] = { 0.0, 0.9, 0.1 },
    [6] = { 0.0, 0.9, 0.1 },
    [7] = { 0.0, 0.9, 0.1 },
    [8] = { 0.0, 0.9, 0.1 },
}

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function Call(fn, ...)
    if not CanAccess(fn) or type(fn) ~= "function" then return nil end
    if addon.CanAccessAllValues and not addon:CanAccessAllValues(...) then return nil end

    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    if not CanAccess(a) then a = nil end
    if not CanAccess(b) then b = nil end
    if not CanAccess(c) then c = nil end
    if not CanAccess(d) then d = nil end
    return a, b, c, d
end

local function IsOrdinaryUnit(unit)
    if not CanAccess(unit) or type(unit) ~= "string" or unit == "" then return false end
    if addon.IsUnitIdentityRestricted and addon:IsUnitIdentityRestricted(unit) then return false end
    return true
end

local function ResolveStatusBarUnit()
    local unit = addon:GetTooltipUnit(GameTooltip)
    if IsOrdinaryUnit(unit) then return unit end

    unit = addon:GetMouseFocusUnit()
    if IsOrdinaryUnit(unit) then return unit end
    return nil
end

local function GetUnitReactionColor(unit)
    local reaction = Call(UnitReaction, unit, "player")
    if type(reaction) ~= "number" then return nil end
    local color = REACTION_COLORS[reaction]
    if not color then return nil end
    return color[1], color[2], color[3]
end

local function SmoothHealthColor(bar)
    if not addon:IsObjectAccessible(bar) then return end

    local minimum, maximum = addon:SafeMethod(bar, "GetMinMaxValues")
    local current = addon:SafeMethod(bar, "GetValue")
    if not CanAccess(minimum) or not CanAccess(maximum) or not CanAccess(current) then return end
    if type(minimum) ~= "number" or type(maximum) ~= "number" or type(current) ~= "number" then return end
    if maximum <= minimum then return end

    local fraction = (current - minimum) / (maximum - minimum)
    if fraction > 1 then fraction = 1 elseif fraction < 0 then fraction = 0 end

    local r, g
    if fraction > 0.5 then
        r = (1 - fraction) * 2
        g = 1
    else
        r = 1
        g = fraction * 2
    end
    addon:SafeMethod(bar, "SetStatusBarColor", r, g, 0)
end

local function ColorStatusBar(bar)
    local general = addon.db and addon.db.general
    if type(general) ~= "table" or not addon:IsObjectAccessible(bar) then return end

    if general.statusbarColor == "smooth" then
        SmoothHealthColor(bar)
        return
    end
    if general.statusbarColor ~= "auto" then return end

    local unit = ResolveStatusBarUnit()
    if not unit then return end

    local r, g, b
    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, unit)
    if isPlayer == true then
        local _, class = Call(UnitClass, unit)
        if type(class) == "string" then
            r, g, b = GetClassColor(class)
        end
    elseif isPlayer == false then
        r, g, b = GetUnitReactionColor(unit)
    end

    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        addon:SafeMethod(bar, "SetStatusBarColor", r, g, b)
    end
end

local function GetStatusText(bar)
    local text = addon:SafeGet(bar, "TextString")
    if addon:IsObjectAccessible(text) then return text end
    return nil
end

local function ClearStatusText(bar)
    local text = GetStatusText(bar)
    if text then addon:SafeMethod(text, "SetText", "") end
end

local function Abbreviate(value)
    if type(value) ~= "number" then return nil end
    local ok, text = pcall(AbbreviateLargeNumbers, value)
    if ok and CanAccess(text) then return text end
    return tostring(value)
end

local function UpdateStatusText(bar)
    local general = addon.db and addon.db.general
    if type(general) ~= "table" or general.statusbarText ~= true or bar.forceHideText == true then
        ClearStatusText(bar)
        return
    end

    local unit = ResolveStatusBarUnit()
    if not unit or (addon.IsUnitHealthRestricted and addon:IsUnitHealthRestricted(unit)) then
        ClearStatusText(bar)
        return
    end

    local text = GetStatusText(bar)
    if not text then return end

    local dead = addon:SafeCallBoolean(UnitIsDeadOrGhost, unit)
    local maximum = Call(UnitHealthMax, unit)
    if type(maximum) ~= "number" or maximum <= 0 then
        ClearStatusText(bar)
        return
    end

    if dead == true then
        local maximumText = Abbreviate(maximum)
        if maximumText then
            addon:SafeMethod(text, "SetFormattedText", "|cff999999%s|r |cffffcc33<%s>|r", maximumText, DEAD)
        else
            addon:SafeMethod(text, "SetText", DEAD)
        end
        return
    end

    local current = Call(UnitHealth, unit)
    if type(current) ~= "number" then
        ClearStatusText(bar)
        return
    end

    local formatMode = general.statusbarTextFormat or "health/max"
    if formatMode == "none" then
        addon:SafeMethod(text, "SetText", "")
        return
    end

    local percentage = current / maximum * 100
    if formatMode == "percent" then
        addon:SafeMethod(text, "SetFormattedText", "%.0f%%", percentage)
    elseif formatMode == "health (percent)" then
        addon:SafeMethod(text, "SetFormattedText", "%s (%.0f%%)", Abbreviate(current), percentage)
    else
        addon:SafeMethod(text, "SetText", Abbreviate(current) .. " / " .. Abbreviate(maximum))
    end
end

local function SetupStatusBar()
    local bar = GameTooltipStatusBar
    if addon.__RT_GeneralStatusBarInitialized or not addon:IsObjectAccessible(bar) then return end
    addon.__RT_GeneralStatusBarInitialized = true

    local background = addon:SafeMethod(bar, "CreateTexture", nil, "BACKGROUND")
    if addon:IsObjectAccessible(background) then
        addon:SafeMethod(background, "SetAllPoints")
        addon:SafeMethod(background, "SetColorTexture", 1, 1, 1)
        addon:SafeMethod(background, "SetVertexColor", 0.2, 0.2, 0.2, 0.8)
    end

    local general = addon.db and addon.db.general or {}
    local fontSize = type(general.statusbarFontSize) == "number" and general.statusbarFontSize or 10
    local fontFlag = addon:NormalizeFontFlag(general.statusbarFontFlag or "THINOUTLINE", "THINOUTLINE")

    local text = addon:SafeMethod(bar, "CreateFontString", nil, "OVERLAY")
    if addon:IsObjectAccessible(text) then
        bar.TextString = text
        addon:SafeMethod(text, "SetPoint", "CENTER")
        local font = NumberFontNormal and NumberFontNormal:GetFont()
        if type(font) == "string" then addon:SafeMethod(text, "SetFont", font, fontSize, fontFlag) end
    end

    bar:HookScript("OnShow", function(self)
        ColorStatusBar(self)
        UpdateStatusText(self)
        local config = addon.db and addon.db.general
        if type(config) == "table" and config.statusbarHeight == 0 then
            addon:SafeMethod(self, "Hide")
        end
    end)

    bar:HookScript("OnValueChanged", function(self)
        -- The callback value itself may be inaccessible in Retail 12.1. Read
        -- only gated status-bar/unit state instead of branching on the payload.
        UpdateStatusText(self)
        ColorStatusBar(self)
    end)
end

local function RunMigrations(db, oldVersion)
    if type(db) ~= "table" or type(oldVersion) ~= "number" then return end

    if oldVersion < 2.9 then
        db.item = db.item or {}
        if db.item.showItemIcon == nil or db.item.showItemIcon == false then
            db.item.showItemIcon = true
        end
    end

    if type(db.general) == "table" then
        db.general.legacyAuraFallback = nil
        db.general.scrollEnabled = nil
        db.general.scrollMaxHeight = nil
        db.general.scrollWheelStep = nil
        db.general.scrollMinLines = nil
        db.general.autoWidthEnabled = nil
        db.general.autoWidthMin = nil
        db.general.autoWidthMax = nil
        db.general.stableWidthMode = nil
        db.general.nativeWrap = nil
        db.general.layoutPipelineEnabled = nil
    end
end

local function NormalizeSavedFontFlags()
    local general = addon.db and addon.db.general
    if type(general) ~= "table" then return end

    for _, key in ipairs({ "statusbarFontFlag", "headerFontFlag", "bodyFontFlag" }) do
        local value = general[key]
        if value == "NORMAL" or value == "NONE" then general[key] = "" end
    end
end

local function SetupTooltipFonts()
    for _, fontObject in ipairs({ GameTooltipHeaderText, GameTooltipText, Tooltip_Small }) do
        if addon:IsObjectAccessible(fontObject) then
            addon:SafeMethod(fontObject, "SetShadowOffset", 1, -1)
            addon:SafeMethod(fontObject, "SetShadowColor", 0, 0, 0, 0.9)
        end
    end
end

local function SetupItemRefCloseButton()
    if not addon:IsObjectAccessible(ItemRefCloseButton) then return end
    if C_AddOns.IsAddOnLoaded("ElvUI") then return end

    addon:SafeMethod(ItemRefCloseButton, "SetSize", 14, 14)
    addon:SafeMethod(ItemRefCloseButton, "SetPoint", "TOPRIGHT", -4, -4)
    addon:SafeMethod(ItemRefCloseButton, "SetNormalTexture", "Interface\\Buttons\\UI-StopButton")
    addon:SafeMethod(ItemRefCloseButton, "SetPushedTexture", "Interface\\Buttons\\UI-StopButton")

    local texture = addon:SafeMethod(ItemRefCloseButton, "GetNormalTexture")
    if addon:IsObjectAccessible(texture) then
        addon:SafeMethod(texture, "SetVertexColor", 0.9, 0.6, 0)
    end
end

local function InitOnce()
    if addon.__RT_GeneralInitialized then return end
    addon.__RT_GeneralInitialized = true

    SetupItemRefCloseButton()

    local oldAccountVersion = tonumber(RothTooltipDB.version) or 0
    local oldCharacterVersion = tonumber(RothTooltipCharacterDB.version) or 0

    addon.db = addon:MergeVariable(addon.db, RothTooltipDB)
    if addon.db.general.SavedVariablesPerCharacter == true then
        local defaults = CopyTable(addon.db)
        addon.db = addon:MergeVariable(defaults, RothTooltipCharacterDB)
    end

    RunMigrations(RothTooltipDB, oldAccountVersion)
    if addon.db.general.SavedVariablesPerCharacter == true then
        RunMigrations(RothTooltipCharacterDB, oldCharacterVersion)
    end

    NormalizeSavedFontFlags()
    SetupStatusBar()

    LibEvent:trigger("tooltip:variables:loaded")
    LibEvent:trigger("ROTHTOOLTIP_GENERAL_INIT")
    SetupTooltipFonts()
end

local M = {}

function M:Init()
    self.cbAddonLoaded = function(_, name)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("General") then return end
        if name == "RothTooltip" then InitOnce() end
    end

    self.cbClearedHide = function(_, tip)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("General") then return end
        if not addon:IsTooltipSafe(tip) then return end
        local general = addon.db and addon.db.general
        if type(general) ~= "table" then return end

        LibEvent:trigger("tooltip.style.border.color", tip, unpack(general.borderColor))
        LibEvent:trigger("tooltip.style.background", tip, unpack(general.background))

        local factionIcon = addon:SafeGet(tip, "BigFactionIcon")
        if addon:IsObjectAccessible(factionIcon) then addon:SafeMethod(factionIcon, "Hide") end

        local nineSlice = addon:SafeGet(tip, "NineSlice")
        if addon:IsObjectAccessible(nineSlice) then addon:SafeMethod(nineSlice, "Hide") end
    end

    self.cbShow = function(_, tip)
        if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("General") then return end
        if tip ~= GameTooltip then return end
        local general = addon.db and addon.db.general
        if type(general) ~= "table" then return end

        LibEvent:trigger(
            "tooltip.statusbar.position",
            general.statusbarPosition,
            general.statusbarOffsetX,
            general.statusbarOffsetY
        )
    end
end

function M:Enable()
    if not addon.MM or not addon.MM.AttachEvent then return end
    addon.MM:AttachEvent("General", "ADDON_LOADED", self.cbAddonLoaded, "ADDON_LOADED")
    addon.MM:AttachTrigger("General", "tooltip:cleared, tooltip:hide", self.cbClearedHide, "tooltip:cleared/hide")
    addon.MM:AttachTrigger("General", "tooltip:show", self.cbShow, "tooltip:show")
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("General", M)
end
