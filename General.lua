local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function IsSecret(v) return addon:IsSecret(v) end

RothTooltipDB = RothTooltipDB or {}
RothTooltipCharacterDB = RothTooltipCharacterDB or {}

-- Reaction color (replaces Blizzard internal GameTooltip_UnitColor)
local REACTION_COLORS = {
    [1] = { 1.0, 0.0, 0.0 },  -- Hated
    [2] = { 1.0, 0.0, 0.0 },  -- Hostile
    [3] = { 1.0, 0.5, 0.0 },  -- Unfriendly
    [4] = { 1.0, 1.0, 0.0 },  -- Neutral
    [5] = { 0.0, 0.9, 0.1 },  -- Friendly
    [6] = { 0.0, 0.9, 0.1 },  -- Honored
    [7] = { 0.0, 0.9, 0.1 },  -- Revered
    [8] = { 0.0, 0.9, 0.1 },  -- Exalted
}

local function GetUnitReactionColor(unit)
    local reaction = UnitReaction(unit, "player")
    if (IsSecret(reaction)) then return 1, 1, 1 end
    local c = reaction and REACTION_COLORS[reaction]
    if (c) then return c[1], c[2], c[3] end
    return 1, 1, 1
end

-- Smooth health color gradient (replaces Blizzard internal HealthBar_OnValueChanged)
local function SmoothHealthColor(bar)
    local minVal, maxVal = bar:GetMinMaxValues()
    local curVal = bar:GetValue()
    if (IsSecret(minVal) or IsSecret(maxVal) or IsSecret(curVal)) then return end
    if (not maxVal or maxVal == 0) then return end
    local frac = (curVal - (minVal or 0)) / maxVal
    if (frac > 1) then frac = 1 elseif (frac < 0) then frac = 0 end
    local r, g
    if (frac > 0.5) then
        r = (1.0 - frac) * 2
        g = 1.0
    else
        r = 1.0
        g = frac * 2
    end
    bar:SetStatusBarColor(r, g, 0)
end

local function ResolveStatusBarUnit()
    local unit = addon:GetTooltipUnit(GameTooltip)
    if (not addon:IsSecret(unit) and type(unit) == "string" and unit ~= "") then
        return unit
    end

    local focusUnit = addon:GetMouseFocusUnit()
    if (focusUnit) then
        unit = addon:ResolveUnitToken(focusUnit)
        if (not addon:IsSecret(unit) and type(unit) == "string" and unit ~= "") then
            return unit
        end
    end

    return "mouseover"
end

local function ColorStatusBar(self, value)
    if (not addon.db or not addon.db.general) then return end

    if (addon.db.general.statusbarColor == "auto") then
        local unit = ResolveStatusBarUnit()
        local r, g, b
        local isPlayer = addon.SafeCallBoolean and addon:SafeCallBoolean(UnitIsPlayer, unit)
        if (isPlayer) then
            local class = select(2, UnitClass(unit))
            if (not IsSecret(class) and class) then
                r, g, b = GetClassColor(class)
            end
        else
            r, g, b = GetUnitReactionColor(unit)
        end
        if (not r or not g or not b) then r, g, b = 1, 1, 1 end
        self:SetStatusBarColor(r, g, b)
    elseif (value and addon.db.general.statusbarColor == "smooth") then
        SmoothHealthColor(self)
    end
end

-- Init is invoked once on ADDON_LOADED for RothTooltip.
local function InitOnce()
    if (addon.__RT_GeneralInitialized) then return end
    addon.__RT_GeneralInitialized = true

    -- CloseButton
    if (ItemRefCloseButton and not C_AddOns.IsAddOnLoaded("ElvUI")) then
        ItemRefCloseButton:SetSize(14, 14)
        ItemRefCloseButton:SetPoint("TOPRIGHT", -4, -4)
        ItemRefCloseButton:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        ItemRefCloseButton:SetPushedTexture("Interface\\Buttons\\UI-StopButton")
        local tex = ItemRefCloseButton.GetNormalTexture and ItemRefCloseButton:GetNormalTexture()
        if (tex and tex.SetVertexColor) then
            tex:SetVertexColor(0.9, 0.6, 0)
        end
    end

    -- StatusBar
    local bar = GameTooltipStatusBar
    if (bar and not bar.__RTSetup) then
        bar.__RTSetup = true

        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(1, 1, 1)
        bar.bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)

        local g = addon.db and addon.db.general
        local fontSize = (g and g.statusbarFontSize) or 10
        local fontFlag = addon:NormalizeFontFlag((g and g.statusbarFontFlag) or "THINOUTLINE", "THINOUTLINE")

        bar.TextString = bar:CreateFontString(nil, "OVERLAY")
        bar.TextString:SetPoint("CENTER")
        bar.TextString:SetFont(NumberFontNormal:GetFont(), fontSize, fontFlag)

        bar.capNumericDisplay = true
        bar.lockShow = 1

        bar:HookScript("OnShow", function(self)
            ColorStatusBar(self)
            if (addon.db and addon.db.general and addon.db.general.statusbarHeight == 0) then
                self:Hide()
            end
        end)

        bar:HookScript("OnValueChanged", function(self, hp)
            if (not addon.db or not addon.db.general) then
                if (self.TextString) then self.TextString:SetText("") end
                return
            end

            local unit = ResolveStatusBarUnit()

            local dead = UnitIsDeadOrGhost(unit)
            if (IsSecret(dead)) then dead = nil end

            if (dead) then
                local maxv = UnitHealthMax(unit)
                if (self.TextString) then
                    if (not IsSecret(maxv) and maxv) then
                        self.TextString:SetFormattedText("|cff999999%s|r |cffffcc33<%s>|r", AbbreviateLargeNumbers(maxv), DEAD)
                    else
                        self.TextString:SetFormattedText("|cff999999%s|r", DEAD)
                    end
                end
            elseif (not self.forceHideText) then
                local curv = UnitHealth(unit)
                local maxv = UnitHealthMax(unit)
                if (self.TextString) then
                    if (not IsSecret(curv) and not IsSecret(maxv) and curv and maxv) then
                        local fmt = addon.db.general.statusbarTextFormat or "health/max"
                        if (fmt == "none") then
                            self.TextString:SetText("")
                        elseif (fmt == "percent") then
                            local pct = (maxv > 0) and (curv / maxv * 100) or 0
                            self.TextString:SetFormattedText("%.0f%%", pct)
                        elseif (fmt == "health (percent)") then
                            local pct = (maxv > 0) and (curv / maxv * 100) or 0
                            self.TextString:SetFormattedText("%s (%.0f%%)", AbbreviateLargeNumbers(curv), pct)
                        else -- "health/max"
                            self.TextString:SetText(AbbreviateLargeNumbers(curv) .. " / " .. AbbreviateLargeNumbers(maxv))
                        end
                    else
                        self.TextString:SetText("")
                    end
                end
            else
                if (self.TextString) then
                    self.TextString:SetText("")
                end
            end

            ColorStatusBar(self)
        end)
    end

    -- Variables
    -- Keep pre-merge versions for migrations (MergeVariable overwrites dst.version).
    local oldAccountVersion = tonumber(RothTooltipDB and RothTooltipDB.version) or 0
    local oldCharVersion = tonumber(RothTooltipCharacterDB and RothTooltipCharacterDB.version) or 0

    addon.db = addon:MergeVariable(addon.db, RothTooltipDB)
    if (addon.db.general.SavedVariablesPerCharacter) then
        local db = CopyTable(addon.db)
        addon.db = addon:MergeVariable(db, RothTooltipCharacterDB)
    end

    --=========================================================
    -- Migrations (unified)
    --=========================================================
    local function RunMigrations(db, oldVersion)
        if (not db or type(oldVersion) ~= "number") then return end
        -- v2.9: enable item icons by default
        if (oldVersion < 2.9) then
            db.item = db.item or {}
            if (db.item.showItemIcon == false or db.item.showItemIcon == nil) then
                db.item.showItemIcon = true
            end
        end
        -- Clean up removed options (layout pipeline, scroll, auto-width — all dead code)
        if (db.general) then
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

    RunMigrations(RothTooltipDB, oldAccountVersion)
    if (addon.db and addon.db.general and addon.db.general.SavedVariablesPerCharacter) then
        RunMigrations(RothTooltipCharacterDB, oldCharVersion)
    end

    --=========================================================
    -- Migration: legacy font flags
    --
    -- Older forks stored "NORMAL" (and sometimes "NONE") as a font flag.
    -- SetFont() does NOT accept these values and will error.
    -- Normalize once at load so options/tooltips can't trigger errors.
    --=========================================================
    if (addon.db and addon.db.general) then
        local g = addon.db.general
        local keys = { "statusbarFontFlag", "headerFontFlag", "bodyFontFlag" }
        for _, k in ipairs(keys) do
            local v = g[k]
            if (v == "NORMAL" or v == "NONE") then
                g[k] = ""
            end
        end
    end

    LibEvent:trigger("tooltip:variables:loaded")

    -- Init
    LibEvent:trigger("ROTHTOOLTIP_GENERAL_INIT")

    -- ShadowText
    if (GameTooltipHeaderText) then
        GameTooltipHeaderText:SetShadowOffset(1, -1)
        GameTooltipHeaderText:SetShadowColor(0, 0, 0, 0.9)
    end
    if (GameTooltipText) then
        GameTooltipText:SetShadowOffset(1, -1)
        GameTooltipText:SetShadowColor(0, 0, 0, 0.9)
    end
    if (Tooltip_Small) then
        Tooltip_Small:SetShadowOffset(1, -1)
        Tooltip_Small:SetShadowColor(0, 0, 0, 0.9)
    end
end

--=========================================================
-- Module wrapper
--=========================================================
local M = {}

function M:Init()
    -- ADDON_LOADED for RothTooltip
    self.cbAddonLoaded = function(_, name)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("General")) then return end
        if (name == "RothTooltip") then
            InitOnce()
        end
    end

    self.cbClearedHide = function(_, tip)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("General")) then return end
        if (not addon.db or not addon.db.general) then return end

        LibEvent:trigger("tooltip.style.border.color", tip, unpack(addon.db.general.borderColor))
        LibEvent:trigger("tooltip.style.background", tip, unpack(addon.db.general.background))

        if (tip and tip.BigFactionIcon) then tip.BigFactionIcon:Hide() end

        -- In Midnight, calling SetBackdrop on tooltips can trigger SecretValue math inside Backdrop.lua.
        -- We rely on hiding Blizzard visuals + our custom skin instead.
        if (tip and tip.NineSlice) then tip.NineSlice:Hide() end
    end

    self.cbShow = function(_, tip)
        if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("General")) then return end
        if (tip ~= GameTooltip) then return end
        if (not addon.db or not addon.db.general) then return end

        LibEvent:trigger("tooltip.statusbar.position", addon.db.general.statusbarPosition, addon.db.general.statusbarOffsetX, addon.db.general.statusbarOffsetY)    
    end
end

function M:Enable()
    if (not addon.MM or not addon.MM.AttachEvent) then return end
    addon.MM:AttachEvent("General", "ADDON_LOADED", self.cbAddonLoaded, "ADDON_LOADED")
    addon.MM:AttachTrigger("General", "tooltip:cleared, tooltip:hide", self.cbClearedHide, "tooltip:cleared/hide")
    addon.MM:AttachTrigger("General", "tooltip:show", self.cbShow, "tooltip:show")
end

function M:Disable()
    -- Detach is handled by ModuleManager.
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("General", M)
    -- Enabled automatically as a core module by ModuleManager (ADDON_LOADED is required to merge SavedVariables).
end
