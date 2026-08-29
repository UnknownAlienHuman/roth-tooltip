local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

RothTooltipDB = RothTooltipDB or {}
RothTooltipCharacterDB = RothTooltipCharacterDB or {}

local StatusTextByBar = setmetatable({}, { __mode = "k" })
local StatusStateByBar = setmetatable({}, { __mode = "k" })
local itemRefButtonStyled = false

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

local function Copy(value)
    if type(CopyTable) == "function" then return CopyTable(value) end
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[Copy(key)] = Copy(child) end
    return result
end

local function Call(fn, ...)
    return addon:SafeCall("General", fn, ...)
end

local function IsOrdinaryUnit(unit)
    return addon:CanAccessValue(unit)
        and type(unit) == "string"
        and unit ~= ""
        and not addon:IsUnitIdentityRestricted(unit)
end

function addon:GetStatusBarText(bar)
    if not self:IsObjectAccessible(bar) then return nil end
    local text = StatusTextByBar[bar]
    if self:IsObjectAccessible(text) then return text end
    StatusTextByBar[bar] = nil
end

local function ResolveStatusBarUnit()
    local unit = addon:GetTooltipUnit(GameTooltip)
    if IsOrdinaryUnit(unit) then return unit end
    unit = addon:GetMouseFocusUnit()
    if IsOrdinaryUnit(unit) then return unit end
end

local function SmoothHealthColor(bar)
    local minimum, maximum = addon:SafeMethod(bar, "GetMinMaxValues")
    local current = addon:SafeMethod(bar, "GetValue")
    if type(minimum) ~= "number" or type(maximum) ~= "number"
        or type(current) ~= "number" or maximum <= minimum then return end

    local fraction = math.max(0, math.min(1, (current - minimum) / (maximum - minimum)))
    local red, green
    if fraction > 0.5 then
        red, green = (1 - fraction) * 2, 1
    else
        red, green = 1, fraction * 2
    end
    addon:SafeMethod(bar, "SetStatusBarColor", red, green, 0)
end

local function ColorStatusBar(bar)
    local general = addon.db and addon.db.general
    if type(general) ~= "table" or not addon:IsObjectAccessible(bar) then return end
    if general.statusbarColor == "smooth" then SmoothHealthColor(bar) return end
    if general.statusbarColor ~= "auto" then return end

    local unit = ResolveStatusBarUnit()
    if not unit then return end

    local red, green, blue
    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, unit)
    if isPlayer == true then
        local _, class = Call(UnitClass, unit)
        if type(class) == "string" then red, green, blue = Call(GetClassColor, class) end
    elseif isPlayer == false then
        local reaction = Call(UnitReaction, unit, "player")
        local color = type(reaction) == "number" and REACTION_COLORS[reaction] or nil
        if color then red, green, blue = color[1], color[2], color[3] end
    end

    if type(red) == "number" and type(green) == "number" and type(blue) == "number" then
        addon:SafeMethod(bar, "SetStatusBarColor", red, green, blue)
    end
end

local function ClearStatusText(bar)
    local text = addon:GetStatusBarText(bar)
    if text then addon:SafeMethod(text, "SetText", "") end
end

local function Abbreviate(value)
    if type(value) ~= "number" then return nil end
    local text = Call(AbbreviateLargeNumbers, value)
    if type(text) == "string" then return text end
    return tostring(value)
end

local function UpdateStatusText(bar)
    local general = addon.db and addon.db.general
    if type(general) ~= "table" or general.statusbarText ~= true
        or addon:SafeGet(bar, "forceHideText") == true then
        ClearStatusText(bar)
        return
    end

    local unit = ResolveStatusBarUnit()
    if not unit or addon:IsUnitHealthRestricted(unit) then ClearStatusText(bar) return end
    local text = addon:GetStatusBarText(bar)
    if not text then return end

    local maximum = Call(UnitHealthMax, unit)
    if type(maximum) ~= "number" or maximum <= 0 then ClearStatusText(bar) return end

    if addon:SafeCallBoolean(UnitIsDeadOrGhost, unit) == true then
        addon:SafeMethod(text, "SetFormattedText", "|cff999999%s|r |cffffcc33<%s>|r",
            Abbreviate(maximum), DEAD)
        return
    end

    local current = Call(UnitHealth, unit)
    if type(current) ~= "number" then ClearStatusText(bar) return end
    local formatMode = general.statusbarTextFormat or "health/max"
    if formatMode == "none" then
        addon:SafeMethod(text, "SetText", "")
    elseif formatMode == "percent" then
        addon:SafeMethod(text, "SetFormattedText", "%.0f%%", current / maximum * 100)
    elseif formatMode == "health (percent)" then
        addon:SafeMethod(text, "SetFormattedText", "%s (%.0f%%)",
            Abbreviate(current), current / maximum * 100)
    else
        addon:SafeMethod(text, "SetText", Abbreviate(current) .. " / " .. Abbreviate(maximum))
    end
end

local function HookScript(frame, scriptName, callback)
    if not addon:CanBindScripts(frame) then return false end
    local hasScript = addon:SafeGet(frame, "HasScript")
    if type(hasScript) == "function" then
        local ok, supported = pcall(hasScript, frame, scriptName)
        if not ok or not addon:CanAccessValue(supported) or supported ~= true then return false end
    end
    local hook = addon:SafeGet(frame, "HookScript")
    if type(hook) ~= "function" then return false end
    return pcall(hook, frame, scriptName, callback)
end

local function SetupStatusBar()
    local bar = GameTooltipStatusBar
    if not addon:IsObjectAccessible(bar) then return end

    local state = StatusStateByBar[bar]
    if type(state) ~= "table" then
        state = {}
        StatusStateByBar[bar] = state
    end

    if not state.background then
        local background = addon:SafeMethod(bar, "CreateTexture", nil, "BACKGROUND")
        if addon:IsObjectAccessible(background) then
            addon:SafeMethod(background, "SetAllPoints")
            addon:SafeMethod(background, "SetColorTexture", 1, 1, 1)
            addon:SafeMethod(background, "SetVertexColor", 0.2, 0.2, 0.2, 0.8)
            state.background = background
        end
    end

    local general = addon.db and addon.db.general or {}
    if not addon:IsObjectAccessible(StatusTextByBar[bar]) then
        local text = addon:SafeMethod(bar, "CreateFontString", nil, "OVERLAY")
        if addon:IsObjectAccessible(text) then
            StatusTextByBar[bar] = text
            addon:SafeMethod(text, "SetPoint", "CENTER")
            local font = addon:IsObjectAccessible(NumberFontNormal)
                and addon:SafeMethod(NumberFontNormal, "GetFont") or nil
            if type(font) == "string" then
                addon:SafeMethod(text, "SetFont", font,
                    tonumber(general.statusbarFontSize) or 10,
                    addon:NormalizeFontFlag(general.statusbarFontFlag or "THINOUTLINE", "THINOUTLINE"))
            end
        end
    end

    if not state.onShow then
        state.onShow = HookScript(bar, "OnShow", function(self)
            ColorStatusBar(self)
            UpdateStatusText(self)
            local config = addon.db and addon.db.general
            if type(config) == "table" and config.statusbarHeight == 0 then
                addon:SafeMethod(self, "Hide")
            end
        end)
    end

    if not state.onValueChanged then
        state.onValueChanged = HookScript(bar, "OnValueChanged", function(self)
            UpdateStatusText(self)
            ColorStatusBar(self)
        end)
    end
end

local function RunMigrations(db, oldVersion)
    if type(db) ~= "table" then return end
    oldVersion = tonumber(oldVersion) or 0

    if oldVersion < 2.9 then
        db.item = db.item or {}
        if db.item.showItemIcon == nil or db.item.showItemIcon == false then db.item.showItemIcon = true end
    end

    if type(db.unit) == "table" then
        if type(db.unit.player) == "table" then db.unit.player.showTargetBy = nil end
        if type(db.unit.npc) == "table" then db.unit.npc.showTargetBy = nil end
    end

    if type(db.general) == "table" then
        for _, key in ipairs({
            "legacyAuraFallback", "scrollEnabled", "scrollMaxHeight", "scrollWheelStep",
            "scrollMinLines", "autoWidthEnabled", "autoWidthMin", "autoWidthMax",
            "stableWidthMode", "nativeWrap", "layoutPipelineEnabled",
        }) do
            db.general[key] = nil
        end
    end
end

local function NormalizeSavedFontFlags()
    local general = addon.db and addon.db.general
    if type(general) ~= "table" then return end
    for _, key in ipairs({ "statusbarFontFlag", "headerFontFlag", "bodyFontFlag" }) do
        if general[key] == "NORMAL" or general[key] == "NONE" then general[key] = "" end
    end
end

local function BuildActiveDB(useCharacter)
    local defaults = Copy(addon.__RT_DefaultDB or addon.db or {})
    RothTooltipDB = addon:MergeVariable(defaults, RothTooltipDB)
    RothTooltipDB.general = RothTooltipDB.general or {}
    RothTooltipDB.general.SavedVariablesPerCharacter = useCharacter == true

    if useCharacter == true then
        local characterDefaults = Copy(RothTooltipDB)
        RothTooltipCharacterDB = addon:MergeVariable(characterDefaults, RothTooltipCharacterDB)
        RothTooltipCharacterDB.general = RothTooltipCharacterDB.general or {}
        RothTooltipCharacterDB.general.SavedVariablesPerCharacter = true
        addon.db = RothTooltipCharacterDB
    else
        addon.db = RothTooltipDB
    end
    NormalizeSavedFontFlags()
    return addon.db
end

local function BroadcastProfile(reason)
    addon.__RT_VariablesLoaded = true
    LibEvent:trigger("tooltip:variables:loaded")
    LibEvent:trigger("ROTHTOOLTIP_GENERAL_INIT")
    if type(addon.RefreshManagedTooltipsMatching) == "function" then
        addon:RefreshManagedTooltipsMatching(nil, reason or "profile")
    end
end

function addon:IsUsingCharacterProfile()
    return type(RothTooltipDB.general) == "table"
        and RothTooltipDB.general.SavedVariablesPerCharacter == true
end

function addon:GetActiveProfileStore()
    return self:IsUsingCharacterProfile() and RothTooltipCharacterDB or RothTooltipDB
end

function addon:SelectSavedVariableScope(useCharacter)
    if not self.__RT_DefaultDB then self.__RT_DefaultDB = Copy(self.db or {}) end
    BuildActiveDB(useCharacter == true)
    BroadcastProfile("saved-variable-scope")
    return self.db
end

function addon:ReapplyActiveProfile(reason)
    if not self.__RT_DefaultDB then self.__RT_DefaultDB = Copy(self.db or {}) end
    BuildActiveDB(self:IsUsingCharacterProfile())
    BroadcastProfile(reason or "reapply-profile")
    return self.db
end

function addon:ImportProfile(data)
    if type(data) ~= "table" then return false end
    if not self.__RT_DefaultDB then self.__RT_DefaultDB = Copy(self.db or {}) end

    local candidate = Copy(data)
    self:FixNumericKey(candidate)
    candidate = self:MergeVariable(Copy(self.__RT_DefaultDB), candidate)
    RunMigrations(candidate, tonumber(candidate.version) or 0)

    local useCharacter = self:IsUsingCharacterProfile()
    candidate.general = candidate.general or {}
    candidate.general.SavedVariablesPerCharacter = useCharacter
    if useCharacter then
        RothTooltipCharacterDB = candidate
    else
        RothTooltipDB = candidate
    end

    BuildActiveDB(useCharacter)
    BroadcastProfile("import-profile")
    return true
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
    if itemRefButtonStyled or not addon:IsObjectAccessible(ItemRefCloseButton) then return end
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function"
        and C_AddOns.IsAddOnLoaded("ElvUI") then
        itemRefButtonStyled = true
        return
    end

    addon:SafeMethod(ItemRefCloseButton, "SetSize", 14, 14)
    addon:SafeMethod(ItemRefCloseButton, "SetPoint", "TOPRIGHT", -4, -4)
    addon:SafeMethod(ItemRefCloseButton, "SetNormalTexture", "Interface\\Buttons\\UI-StopButton")
    addon:SafeMethod(ItemRefCloseButton, "SetPushedTexture", "Interface\\Buttons\\UI-StopButton")
    local texture = addon:SafeMethod(ItemRefCloseButton, "GetNormalTexture")
    if addon:IsObjectAccessible(texture) then addon:SafeMethod(texture, "SetVertexColor", 0.9, 0.6, 0) end
    itemRefButtonStyled = true
end

local function InitOnce()
    if addon.__RT_GeneralInitialized then return end
    addon.__RT_GeneralInitialized = true
    addon.__RT_DefaultDB = Copy(addon.db or {})

    RunMigrations(RothTooltipDB, tonumber(RothTooltipDB.version) or 0)
    RunMigrations(RothTooltipCharacterDB, tonumber(RothTooltipCharacterDB.version) or 0)
    BuildActiveDB(addon:IsUsingCharacterProfile())
    SetupStatusBar()
    SetupItemRefCloseButton()
    SetupTooltipFonts()
    BroadcastProfile("initial-load")
end

local M = {}

function M:Init()
    self.cbAddonLoaded = function(_, name)
        if name == "RothTooltip" then InitOnce() end
        if addon.__RT_GeneralInitialized then
            SetupStatusBar()
            SetupItemRefCloseButton()
        end
    end

    self.cbRestriction = function()
        if addon.__RT_GeneralInitialized then SetupStatusBar() end
    end

    self.cbClear = function(_, tooltip)
        if not addon:IsTooltipSafe(tooltip) then return end
        local general = addon.db and addon.db.general
        if type(general) ~= "table" then return end

        if type(general.borderColor) == "table" then
            LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(general.borderColor))
        end
        if type(general.background) == "table" then
            LibEvent:trigger("tooltip.style.background", tooltip, unpack(general.background))
        end
        local factionIcon = addon:GetBigFactionIcon(tooltip, false)
        if addon:IsObjectAccessible(factionIcon) then addon:SafeMethod(factionIcon, "Hide") end
    end

    self.cbShow = function(_, tooltip)
        if tooltip ~= GameTooltip then return end
        local general = addon.db and addon.db.general
        if type(general) == "table" then
            LibEvent:trigger("tooltip.statusbar.position", general.statusbarPosition,
                general.statusbarOffsetX, general.statusbarOffsetY)
        end
    end
end

function M:Enable()
    addon.MM:AttachEvent("General", "ADDON_LOADED", self.cbAddonLoaded, "ADDON_LOADED")
    addon.MM:AttachEvent("General", "ADDON_RESTRICTION_STATE_CHANGED, PLAYER_REGEN_ENABLED",
        self.cbRestriction, "restriction-change")
    addon.MM:AttachTrigger("General", "tooltip:cleared, tooltip:hide", self.cbClear, "tooltip:clear")
    addon.MM:AttachTrigger("General", "tooltip:show", self.cbShow, "tooltip:show")
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("General", M)
