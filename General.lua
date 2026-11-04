local _, addon = ...
local LibEvent = addon.LibEvent

RothTooltipDB = RothTooltipDB or {}
RothTooltipCharacterDB = RothTooltipCharacterDB or {}

local StatusTextByBar = setmetatable({}, { __mode = "k" })
local StatusStateByBar = setmetatable({}, { __mode = "k" })

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

function addon:GetStatusBarText(bar)
    if not self:IsObjectAccessible(bar) then return nil end
    local text = StatusTextByBar[bar]
    if self:IsObjectAccessible(text) then return text end
    StatusTextByBar[bar] = nil
end

local function ResolveStatusBarUnit()
    local unit = addon:GetTooltipUnit(GameTooltip)
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
    if type(general) ~= "table" or not addon:IsTooltipSafe(GameTooltip) or not addon:IsObjectAccessible(bar) then return end
    if general.statusbarColor == "smooth" then
        local unit = ResolveStatusBarUnit()
        if unit and not addon:IsUnitHealthRestricted(unit) then SmoothHealthColor(bar) end
        return
    end
    if general.statusbarColor ~= "auto" then return end

    local unit = ResolveStatusBarUnit()
    if not unit then return end

    local red, green, blue
    local isPlayer = addon:SafeCallBoolean(UnitIsPlayer, unit)
    if isPlayer == true then
        local _, class = Call(UnitClass, unit)
        if type(class) == "string" then red, green, blue = Call(GetClassColor, class) end
    elseif isPlayer == false then
        local reaction = addon:CanCompareUnitTokens(unit, "player") and Call(UnitReaction, unit, "player") or nil
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
    if not addon:IsTooltipSafe(GameTooltip) or type(general) ~= "table" or general.statusbarText ~= true
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

function addon:RefreshStatusBar()
    local bar = GameTooltipStatusBar
    if not self:IsObjectAccessible(bar) then return end
    UpdateStatusText(bar)
    if self:IsTooltipSafe(GameTooltip) then ColorStatusBar(bar) end
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
    if InCombatLockdown() or not addon:IsTooltipSafe(GameTooltip) or not addon:IsObjectAccessible(bar) then return end

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

local function BuildActiveDB(useCharacter)
    local account, reason = addon:NormalizeProfile(RothTooltipDB, false)
    if not account then return nil, reason end
    local character
    character, reason = addon:NormalizeProfile(RothTooltipCharacterDB, false, account)
    if not character then return nil, reason end
    account.general.SavedVariablesPerCharacter = useCharacter == true
    character.general.SavedVariablesPerCharacter = true
    RothTooltipDB, RothTooltipCharacterDB = account, character
    addon.db = useCharacter and character or account
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
    return type(RothTooltipDB) == "table" and type(RothTooltipDB.general) == "table"
        and RothTooltipDB.general.SavedVariablesPerCharacter == true
end

function addon:GetActiveProfileStore()
    return self:IsUsingCharacterProfile() and RothTooltipCharacterDB or RothTooltipDB
end

function addon:SelectSavedVariableScope(useCharacter)
    if InCombatLockdown() or not self.__RT_VariablesLoaded then return nil end
    local db, reason = BuildActiveDB(useCharacter == true)
    if not db then self:DoctorLog("profile", "scope", reason); return nil end
    BroadcastProfile("saved-variable-scope")
    return db
end

function addon:ReapplyActiveProfile(reason)
    if InCombatLockdown() or not self.__RT_VariablesLoaded then return nil end
    local db, failure = BuildActiveDB(self:IsUsingCharacterProfile())
    if not db then self:DoctorLog("profile", "reapply", failure); return nil end
    BroadcastProfile(reason or "reapply-profile")
    return db
end

function addon:ImportProfile(data)
    if InCombatLockdown() or not self.__RT_VariablesLoaded then return false end
    local candidate = self:NormalizeProfile(data, true)
    if not candidate then return false end
    local useCharacter = self:IsUsingCharacterProfile()
    candidate.general.SavedVariablesPerCharacter = useCharacter
    if useCharacter then RothTooltipCharacterDB = candidate else RothTooltipDB = candidate end
    self.db = candidate
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

local function InitOnce()
    if addon.__RT_GeneralInitialized then return end
    addon.__RT_DefaultDB = addon.__RT_DefaultDB or addon.db
    local db, reason = BuildActiveDB(addon:IsUsingCharacterProfile())
    if not db then addon:DoctorLog("profile", "load", reason); return end
    addon.__RT_GeneralInitialized = true
    SetupStatusBar()
    SetupTooltipFonts()
    BroadcastProfile("initial-load")
end

local M = {}

function M:Init()
    self.cbAddonLoaded = function(_, name)
        if addon:CanAccessValue(name) and name == "RothTooltip" then InitOnce() end
        if addon.__RT_GeneralInitialized then
            SetupStatusBar()
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
    addon.MM:AttachTrigger("General", "tooltip:cleared, tooltip:hide, tooltip:invalidated", self.cbClear, "tooltip:clear")
    addon.MM:AttachTrigger("General", "tooltip:show", self.cbShow, "tooltip:show")
end


addon.MM:RegisterModule("General", M)
