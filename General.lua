local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

RothTooltipDB = RothTooltipDB or {}
RothTooltipCharacterDB = RothTooltipCharacterDB or {}

local StatusTextByBar = setmetatable({}, { __mode = "k" })
local StatusStateByBar = setmetatable({}, { __mode = "k" })
local itemRefButtonStyled = false

local DEFAULT_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
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

local function Call(fn, ...)
    return addon:SafeCall("General", fn, ...)
end

local function IsOrdinaryUnit(unit)
    return addon:CanAccessValue(unit)
        and type(unit) == "string"
        and unit ~= ""
        and not addon:IsUnitIdentityRestricted(unit)
end

local function RunMigrations(db, oldVersion)
    if type(db) ~= "table" then return end
    oldVersion = tonumber(oldVersion) or 0

    if oldVersion < 2.9 then
        db.item = type(db.item) == "table" and db.item or {}
        if db.item.showItemIcon == nil then db.item.showItemIcon = true end
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

local function NormalizeSavedFontFlags(db)
    local general = type(db) == "table" and db.general or nil
    if type(general) ~= "table" then return end
    for _, key in ipairs({ "statusbarFontFlag", "headerFontFlag", "bodyFontFlag" }) do
        if general[key] == "NORMAL" or general[key] == "NONE" then general[key] = "" end
    end
end

local function BuildActiveDB(useCharacter)
    local defaults = addon:GetDefaultProfile()

    RunMigrations(RothTooltipDB, tonumber(RothTooltipDB.version) or 0)
    RothTooltipDB = addon:BuildProfile(RothTooltipDB, defaults)
    RothTooltipDB.general.SavedVariablesPerCharacter = useCharacter == true
    NormalizeSavedFontFlags(RothTooltipDB)

    if useCharacter == true then
        RunMigrations(RothTooltipCharacterDB, tonumber(RothTooltipCharacterDB.version) or 0)
        -- Character profiles inherit missing known keys from the detached
        -- account profile, but never share nested table identity with it.
        RothTooltipCharacterDB = addon:BuildProfile(RothTooltipCharacterDB, RothTooltipDB)
        RothTooltipCharacterDB.general.SavedVariablesPerCharacter = true
        NormalizeSavedFontFlags(RothTooltipCharacterDB)
        addon.db = RothTooltipCharacterDB
    else
        addon.db = RothTooltipDB
    end
    return addon.db
end

local function BroadcastProfile(reason)
    addon.__RT_VariablesLoaded = true
    LibEvent:trigger("tooltip:variables:loaded")
    LibEvent:trigger("ROTHTOOLTIP_GENERAL_INIT")

    if type(addon.RequestManagedTooltipRefresh) == "function" then
        addon:RequestManagedTooltipRefresh(nil, reason or "profile")
    elseif not InCombatLockdown() and type(addon.RefreshManagedTooltipsMatching) == "function" then
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
    BuildActiveDB(useCharacter == true)
    BroadcastProfile("saved-variable-scope")
    return self.db
end

function addon:ReapplyActiveProfile(reason)
    BuildActiveDB(self:IsUsingCharacterProfile())
    BroadcastProfile(reason or "reapply-profile")
    return self.db
end

function addon:ImportProfile(data)
    if type(data) ~= "table" then return false end

    local useCharacter = self:IsUsingCharacterProfile()
    local base = useCharacter and RothTooltipDB or addon:GetDefaultProfile()
    local candidate = addon:BuildProfile(data, base)
    RunMigrations(candidate, tonumber(candidate.version) or 0)
    candidate = addon:BuildProfile(candidate, base)
    candidate.general.SavedVariablesPerCharacter = useCharacter
    NormalizeSavedFontFlags(candidate)

    if useCharacter then RothTooltipCharacterDB = candidate else RothTooltipDB = candidate end
    BuildActiveDB(useCharacter)
    BroadcastProfile("import-profile")
    return true
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

local function ClearStatusText(bar)
    local text = addon:GetStatusBarText(bar)
    if text then addon:SafeMethod(text, "SetText", "") end
end

local function Abbreviate(value)
    if type(value) ~= "number" then return nil end
    local text = Call(AbbreviateLargeNumbers, value)
    return type(text) == "string" and text or tostring(value)
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

local function SmoothHealthColor(bar)
    local minimum, maximum = addon:SafeMethod(bar, "GetMinMaxValues")
    local current = addon:SafeMethod(bar, "GetValue")
    if type(minimum) ~= "number" or type(maximum) ~= "number"
        or type(current) ~= "number" or maximum <= minimum then return end

    local fraction = math.max(0, math.min(1, (current - minimum) / (maximum - minimum)))
    local red, green
    if fraction > 0.5 then red, green = (1 - fraction) * 2, 1
    else red, green = 1, fraction * 2 end
    addon:SafeMethod(bar, "SetStatusBarColor", red, green, 0)
end

local function ColorStatusBar(bar)
    local general = addon.db and addon.db.general
    local state = StatusStateByBar[bar]
    if type(general) ~= "table" or type(state) ~= "table" then return end

    if general.statusbarColor == "smooth" then SmoothHealthColor(bar) return end
    if general.statusbarColor ~= "auto" then
        if type(state.defaultColor) == "table" then
            addon:SafeMethod(bar, "SetStatusBarColor", unpack(state.defaultColor))
        end
        return
    end

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

local function HookScript(frame, scriptName, callback)
    if not addon:CanBindScripts(frame) then return false end
    local hasScript = addon:SafeGet(frame, "HasScript")
    if type(hasScript) == "function" then
        local ok, supported = pcall(hasScript, frame, scriptName)
        if not ok or not addon:CanAccessValue(supported) or supported ~= true then return false end
    end
    local hook = addon:SafeGet(frame, "HookScript")
    return type(hook) == "function" and pcall(hook, frame, scriptName, callback) or false
end

local function PositionStatusBar()
    local bar = GameTooltipStatusBar
    local general = addon.db and addon.db.general
    if not addon:IsObjectAccessible(bar) or type(general) ~= "table" then return end

    LibEvent:trigger("tooltip.style.init", GameTooltip)
    local style = addon:GetTooltipStyle(GameTooltip)
    if not style then return end

    local position = general.statusbarPosition
    local offsetX = tonumber(general.statusbarOffsetX)
    local offsetY = tonumber(general.statusbarOffsetY)
    local backdrop = addon:SafeMethod(style, "GetBackdrop")
    if type(backdrop) ~= "table" then return end

    addon:SafeMethod(style, "ClearAllPoints")
    addon:SafeMethod(bar, "ClearAllPoints")
    if addon:SafeMethod(bar, "IsShown") ~= true then position = "" end

    if position == "bottom" then
        local offset = backdrop.edgeFile == DEFAULT_BORDER and 5 or (tonumber(backdrop.edgeSize) or 1) + 1
        offsetX = offsetX and offsetX ~= 0 and offsetX or offset
        offsetY = offsetY and offsetY ~= 0 and offsetY or -offset
        addon:SafeMethod(bar, "SetPoint", "TOPLEFT", GameTooltip, "BOTTOMLEFT", offsetX, 2)
        addon:SafeMethod(bar, "SetPoint", "TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -offsetX, 2)
        addon:SafeMethod(style, "SetPoint", "TOPLEFT")
        addon:SafeMethod(style, "SetPoint", "BOTTOMRIGHT", bar, "BOTTOMRIGHT", offsetX, offsetY)
    elseif position == "top" then
        local offset = backdrop.edgeFile == DEFAULT_BORDER and 4 or tonumber(backdrop.edgeSize) or 1
        offsetX = offsetX and offsetX ~= 0 and offsetX or offset
        offsetY = offsetY and offsetY ~= 0 and offsetY or offset
        addon:SafeMethod(bar, "SetPoint", "BOTTOMLEFT", GameTooltip, "TOPLEFT", offsetX, -4)
        addon:SafeMethod(bar, "SetPoint", "BOTTOMRIGHT", GameTooltip, "TOPRIGHT", -offsetX, -4)
        addon:SafeMethod(style, "SetPoint", "TOPLEFT", bar, "TOPLEFT", -offsetX, offsetY)
        addon:SafeMethod(style, "SetPoint", "BOTTOMRIGHT")
    else
        local offset = backdrop.edgeFile == DEFAULT_BORDER and 2 or 0
        addon:SafeMethod(bar, "SetPoint", "TOPLEFT", GameTooltip, "BOTTOMLEFT", offset, -1)
        addon:SafeMethod(bar, "SetPoint", "TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -offset, -1)
        addon:SafeMethod(style, "SetAllPoints", GameTooltip)
    end
end

local function ApplyStatusBarFont()
    local bar = GameTooltipStatusBar
    local text = addon:GetStatusBarText(bar)
    local general = addon.db and addon.db.general
    if not text or type(general) ~= "table" then return end

    local _, currentSize = addon:SafeMethod(text, "GetFont")
    local defaultFont = addon:IsObjectAccessible(NumberFontNormal)
        and addon:SafeMethod(NumberFontNormal, "GetFont") or nil
    local font = addon:GetFont(general.statusbarFont, defaultFont)
    local size = tonumber(general.statusbarFontSize) or currentSize or 10
    local flag = addon:NormalizeFontFlag(general.statusbarFontFlag, "THINOUTLINE")
    if type(font) == "string" and type(size) == "number" then
        addon:SafeMethod(text, "SetFont", font, size, flag)
    end
end

local function SetupStatusBar()
    if InCombatLockdown() then return false end
    local bar = GameTooltipStatusBar
    if not addon:IsObjectAccessible(bar) then return false end

    local state = StatusStateByBar[bar]
    if type(state) ~= "table" then
        state = {}
        StatusStateByBar[bar] = state
        local red, green, blue, alpha = addon:SafeMethod(bar, "GetStatusBarColor")
        if type(red) == "number" and type(green) == "number" and type(blue) == "number" then
            state.defaultColor = { red, green, blue, type(alpha) == "number" and alpha or 1 }
        end
    end

    if not addon:IsObjectAccessible(state.background) then
        local background = addon:SafeMethod(bar, "CreateTexture", nil, "BACKGROUND")
        if addon:IsObjectAccessible(background) then
            addon:SafeMethod(background, "SetAllPoints")
            addon:SafeMethod(background, "SetColorTexture", 1, 1, 1)
            addon:SafeMethod(background, "SetVertexColor", 0.2, 0.2, 0.2, 0.8)
            state.background = background
        end
    end

    if not addon:IsObjectAccessible(StatusTextByBar[bar]) then
        local text = addon:SafeMethod(bar, "CreateFontString", nil, "OVERLAY")
        if addon:IsObjectAccessible(text) then
            StatusTextByBar[bar] = text
            addon:SafeMethod(text, "SetPoint", "CENTER")
        end
    end

    if not state.onShow then
        state.onShow = HookScript(bar, "OnShow", function(self)
            ColorStatusBar(self)
            UpdateStatusText(self)
            PositionStatusBar()
            local general = addon.db and addon.db.general
            if type(general) == "table" and tonumber(general.statusbarHeight) == 0 then
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

    addon:RefreshStatusBar()
    return state.onShow == true and state.onValueChanged == true
end

function addon:RefreshStatusBar()
    if InCombatLockdown() then return false end
    local bar = GameTooltipStatusBar
    local general = self.db and self.db.general
    if not self:IsObjectAccessible(bar) or type(general) ~= "table" then return false end

    self:SafeMethod(bar, "SetHeight", math.max(0, tonumber(general.statusbarHeight) or 4))
    self:SafeMethod(bar, "SetStatusBarTexture", self:GetBarFile(general.statusbarTexture))
    ApplyStatusBarFont()
    ColorStatusBar(bar)
    UpdateStatusText(bar)
    PositionStatusBar()
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
    if itemRefButtonStyled or InCombatLockdown() or not addon:IsObjectAccessible(ItemRefCloseButton) then return end
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

    local accountVersion = tonumber(RothTooltipDB.version) or 0
    local characterVersion = tonumber(RothTooltipCharacterDB.version) or 0
    RunMigrations(RothTooltipDB, accountVersion)
    RunMigrations(RothTooltipCharacterDB, characterVersion)
    BuildActiveDB(type(RothTooltipDB.general) == "table"
        and RothTooltipDB.general.SavedVariablesPerCharacter == true)

    SetupStatusBar()
    SetupItemRefCloseButton()
    SetupTooltipFonts()
    BroadcastProfile("initial-load")
end

local M = {}

function M:Init()
    self.cbAddonLoaded = function(_, name)
        if name == "RothTooltip" then InitOnce() end
        if addon.__RT_GeneralInitialized and not InCombatLockdown() then
            SetupStatusBar()
            SetupItemRefCloseButton()
        end
    end
    self.cbReady = function()
        if addon.__RT_GeneralInitialized then
            SetupStatusBar()
            SetupItemRefCloseButton()
        end
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
        if tooltip == GameTooltip then addon:RefreshStatusBar() end
    end
end

function M:Enable()
    addon.MM:AttachEvent("General", "ADDON_LOADED", self.cbAddonLoaded, "ADDON_LOADED")
    addon.MM:AttachEvent("General", "PLAYER_LOGIN, PLAYER_REGEN_ENABLED, ADDON_RESTRICTION_STATE_CHANGED",
        self.cbReady, "statusbar-ready")
    addon.MM:AttachTrigger("General", "tooltip:cleared, tooltip:hide", self.cbClear, "tooltip:clear")
    addon.MM:AttachTrigger("General", "tooltip:show", self.cbShow, "tooltip:show")
end

function M:Disable() end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("General", M)
