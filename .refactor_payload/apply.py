#!/usr/bin/env python3
"""Apply the audited Retail 12.1 single-runtime refactor once."""

from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / ".refactor_payload"
SCRIPT = Path(__file__).resolve()


def replace_once(path: str, old: str, new: str, label: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"{path}: missing patch anchor: {label}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


def write_text(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def copy_payload() -> None:
    for source in sorted(PAYLOAD.rglob("*")):
        if not source.is_file() or source.resolve() == SCRIPT:
            continue
        relative = source.relative_to(PAYLOAD)
        destination = ROOT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def patch_core() -> None:
    replace_once(
        "Core.lua",
        '''            LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(general.borderColor))
            LibEvent:trigger("tooltip.style.background", tooltip, unpack(general.background))
''',
        '''            if type(general.borderColor) == "table" then
                LibEvent:trigger("tooltip.style.border.color", tooltip, unpack(general.borderColor))
            end
            if type(general.background) == "table" then
                LibEvent:trigger("tooltip.style.background", tooltip, unpack(general.background))
            end
''',
        "guard general style color tables",
    )


def patch_midnight() -> None:
    path = ROOT / "Engine/Midnight.lua"
    text = path.read_text(encoding="utf-8")
    marker = "local function QuerySecretPredicate"
    if marker not in text:
        raise SystemExit("Engine/Midnight.lua: QuerySecretPredicate anchor missing")
    _, tail = text.split(marker, 1)
    head = '''-- RothTooltip Engine: authoritative Retail 12.1 runtime boundary.
--
-- Raw Blizzard payloads are normalized here into ordinary primitive context.
-- Feature modules never receive raw TooltipData, AuraData, or args vectors.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local function CanAccessValue(value)
    return addon:CanAccessValue(value)
end

local function CanAccessAllValues(...)
    return addon:CanAccessAllValues(...)
end

local function ReadObjectMember(object, key)
    return addon:SafeGet(object, key)
end

local function CallObjectMethod(object, method, ...)
    return addon:SafeMethod(object, method, ...)
end

'''
    path.write_text(head + marker + tail, encoding="utf-8")

    replace_once(
        "Engine/Midnight.lua",
        '''function addon:AreCooldownsRestricted()
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldCooldownsBeSecret)
end

function addon:AreUnitStatsRestricted()''',
        '''function addon:AreCooldownsRestricted()
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldCooldownsBeSecret)
end

function addon:IsSpellAuraRestricted(spellIdentifier)
    if not CanAccessValue(spellIdentifier) then return true end
    local valueType = type(spellIdentifier)
    if valueType ~= "number" and valueType ~= "string" then return true end
    return QuerySecretPredicate(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret, spellIdentifier)
end

function addon:AreUnitStatsRestricted()''',
        "spell-specific aura predicate",
    )

    replace_once(
        "Engine/Midnight.lua",
        "local function ResolveItemID(itemInfo)",
        '''local function ResolveDisplayedSpellID(tooltip)
    local _, spellID = TooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedSpell, tooltip)
    if type(spellID) == "number" and spellID > 0 then return spellID end

    local getSpell = ReadObjectMember(tooltip, "GetSpell")
    if type(getSpell) ~= "function" then return nil end

    local ok, _, second, third = pcall(getSpell, tooltip)
    if not ok then return nil end
    if not CanAccessValue(second) then second = nil end
    if not CanAccessValue(third) then third = nil end
    if type(third) == "number" and third > 0 then return third end
    if type(second) == "number" and second > 0 then return second end
    return nil
end

local function ResolveItemID(itemInfo)''',
        "displayed spell resolver",
    )

    path = ROOT / "Engine/Midnight.lua"
    text = path.read_text(encoding="utf-8")
    text = text.replace("    local actionType = dataTypes and dataTypes.Action or nil\n", "", 1)
    path.write_text(text, encoding="utf-8")

    replace_once(
        "Engine/Midnight.lua",
        '''    local useDataIDAsSpellID = context.type == spellType
        or context.type == auraType
        or context.type == actionType
        or context.type == petActionType
        or context.type == flyoutType
        or context.type == macroType

    if not context.spellID and useDataIDAsSpellID and type(context.id) == "number" then
        context.spellID = context.id
    end
''',
        '''    -- TooltipData.id is the authoritative spell identifier for Spell and
    -- UnitAura payloads. PetAction/Flyout/Macro ids are their own record ids,
    -- so those types must be resolved through an explicit spell field or the
    -- tooltip's documented spell accessor instead of treating id as spellID.
    if not context.spellID
        and (context.type == spellType or context.type == auraType)
        and type(context.id) == "number" then
        context.spellID = context.id
    end

    local actionLike = context.type == petActionType
        or context.type == flyoutType
        or context.type == macroType
    if actionLike then
        context.spellID = ReadNumber(tooltipData, "spellID")
            or ReadNumber(tooltipData, "spellId")
            or ResolveDisplayedSpellID(tooltip)
    end

    if context.type == auraType and type(context.spellID) == "number"
        and self:IsSpellAuraRestricted(context.spellID) then
        context.spellID = nil
    end
''',
        "action-like spell context",
    )

    replace_once(
        "Engine/Midnight.lua",
        '''function addon:SafeGetSpell(tooltip)
    if not self:IsObjectAccessible(tooltip) then return nil end
    local fn = ReadObjectMember(tooltip, "GetSpell")
    if type(fn) ~= "function" then return nil end

    local ok, a, b, c = pcall(fn, tooltip)
    if not ok then return nil end
    if not CanAccessValue(a) then a = nil end
    if not CanAccessValue(b) then b = nil end
    if not CanAccessValue(c) then c = nil end
    return a, b, c
end
''',
        '''function addon:SafeGetSpell(tooltip)
    if not self:IsObjectAccessible(tooltip) then return nil end
    local fn = ReadObjectMember(tooltip, "GetSpell")
    if type(fn) ~= "function" then return nil end

    local ok, name, spellID, alternateSpellID = pcall(fn, tooltip)
    if not ok then return nil end
    if not CanAccessValue(name) then name = nil end
    if not CanAccessValue(spellID) then spellID = nil end
    if not CanAccessValue(alternateSpellID) then alternateSpellID = nil end
    return name, spellID, alternateSpellID
end
''',
        "safe spell tuple",
    )

    replace_once(
        "Engine/Midnight.lua",
        '''function addon:SetPrimaryTooltipContext(tooltip, context)
    if not self:IsObjectAccessible(tooltip) then return end
    ContextByTooltip[tooltip] = CopyOrdinaryContext(context)
end
''',
        '''function addon:SetPrimaryTooltipContext(tooltip, context)
    if not self:IsObjectAccessible(tooltip) then return end
    ContextByTooltip[tooltip] = CopyOrdinaryContext(context)
end

function addon:ClearTooltipContexts()
    for tooltip in pairs(ContextByTooltip) do
        ContextByTooltip[tooltip] = nil
    end
end
''',
        "context invalidation API",
    )

    replace_once(
        "Engine/Midnight.lua",
        '''    local clean = CopyOrdinaryContext(context)
    if clean then
        ContextByTooltip[tooltip] = clean
    end
    return clean
''',
        '''    local clean = CopyOrdinaryContext(context)
    ContextByTooltip[tooltip] = clean
    return clean
''',
        "clear stale context on failed sanitize",
    )

    replace_once(
        "Engine/Midnight.lua",
        "function addon:RegisterTooltipFrame(tooltip)",
        '''local function LooksLikeBlizzardSpellTooltip(tooltip)
    local name = FrameName(tooltip)
    if not name then return false end
    if name == "SpellBookTooltip" then return true end
    if name:find("PlayerSpells", 1, true) and name:find("Tooltip", 1, true) then return true end
    return name:find("Spell", 1, true) ~= nil and name:find("Tooltip", 1, true) ~= nil
end

function addon:IsManagedTooltip(tooltip)
    if not self:IsTooltipSafe(tooltip) then return false end
    if type(self.tooltipSet) == "table" and self.tooltipSet[tooltip] then return true end

    local parent = CallObjectMethod(tooltip, "GetParent")
    if self:IsObjectAccessible(parent) and type(self.tooltipSet) == "table" and self.tooltipSet[parent] then
        return true
    end
    if LooksLikeBlizzardSpellTooltip(tooltip) then return true end
    return self:IsObjectAccessible(parent) and LooksLikeBlizzardSpellTooltip(parent)
end

function addon:RegisterTooltipFrame(tooltip)''',
        "managed tooltip predicate",
    )

    replace_once(
        "Engine/Midnight.lua",
        '''function addon:RegisterTooltipFrame(tooltip)
    if not self:IsObjectAccessible(tooltip) then return false end
    if self.tooltipSet and self.tooltipSet[tooltip] then return true end

    self.tooltips = self.tooltips or {}
    self.tooltipSet = self.tooltipSet or {}
    self.tooltips[#self.tooltips + 1] = tooltip
    self.tooltipSet[tooltip] = true
    LibEvent:trigger("tooltip:init", tooltip)
    return true
end
''',
        '''function addon:RegisterTooltipFrame(tooltip)
    if not self:IsObjectAccessible(tooltip) then return false end

    self.tooltips = self.tooltips or {}
    if type(self.tooltipSet) ~= "table" then
        self.tooltipSet = setmetatable({}, { __mode = "k" })
    end
    if self.tooltipSet[tooltip] then return true end

    self.tooltips[#self.tooltips + 1] = tooltip
    self.tooltipSet[tooltip] = true
    LibEvent:trigger("tooltip:init", tooltip)
    return true
end
''',
        "weak managed tooltip set",
    )

    replace_once(
        "Engine/Midnight.lua",
        "        if tooltip and not seen[tooltip] and self:IsObjectAccessible(tooltip) then\n",
        "        if tooltip and not seen[tooltip] and self:IsManagedTooltip(tooltip) then\n",
        "managed visible-tooltip iteration",
    )

    replace_once(
        "Engine/Midnight.lua",
        '''function addon:GetLine(tooltip, number)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if type(number) ~= "number" then return nil end

    local name = CallObjectMethod(tooltip, "GetName")
    local lineCount = CallObjectMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return nil end

    if number > lineCount then
        CallObjectMethod(tooltip, "AddLine", " ")
        lineCount = CallObjectMethod(tooltip, "NumLines")
        if type(lineCount) ~= "number" or number > lineCount then return nil end
    end
    return _G[name .. "TextLeft" .. number], _G[name .. "TextRight" .. number]
end
''',
        '''function addon:GetLine(tooltip, number)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if type(number) ~= "number" or number < 1 then return nil end

    local name = CallObjectMethod(tooltip, "GetName")
    local lineCount = CallObjectMethod(tooltip, "NumLines")
    if type(name) ~= "string" or type(lineCount) ~= "number" then return nil end

    local added = 0
    while lineCount < number and added < 64 do
        CallObjectMethod(tooltip, "AddLine", " ")
        local nextCount = CallObjectMethod(tooltip, "NumLines")
        if type(nextCount) ~= "number" or nextCount <= lineCount then break end
        lineCount = nextCount
        added = added + 1
    end
    if lineCount < number then return nil end
    return _G[name .. "TextLeft" .. number], _G[name .. "TextRight" .. number]
end
''',
        "bounded line allocation",
    )

    path = ROOT / "Engine/Midnight.lua"
    text = path.read_text(encoding="utf-8")
    start = text.index("function addon:GetUnitSpeed(unit)")
    end = text.index("\nfunction addon:GetTitle", start)
    speed = '''function addon:GetUnitSpeed(unit)
    if not CanAccessValue(unit) or type(unit) ~= "string" or unit == "" then return nil end
    if self:IsUnitIdentityRestricted(unit) or self:AreUnitStatsRestricted() then return nil end

    local currentSpeed, runSpeed = SafeValues(GetUnitSpeed, unit)
    local speed = type(currentSpeed) == "number" and currentSpeed or runSpeed
    if type(speed) ~= "number" then return nil end

    local baseSpeed = BASE_MOVEMENT_SPEED or 7
    if type(baseSpeed) ~= "number" or baseSpeed <= 0 then return nil end
    return speed / baseSpeed * 100 + 0.5
end
'''
    text = text[:start] + speed + text[end:]
    start = text.index("function addon:GetZone(unit, unitName, realm)")
    end = text.index("\nfunction addon:GetUnitInfo", start)
    zone = '''local function GetRosterNameAndZone(index)
    if type(index) ~= "number" or type(GetRaidRosterInfo) ~= "function" then return nil, nil end
    if not CanAccessAllValues(index) then return nil, nil end

    local ok, name, _, _, _, _, _, zone = pcall(GetRaidRosterInfo, index)
    if not ok then return nil, nil end
    if not CanAccessValue(name) or type(name) ~= "string" then name = nil end
    if not CanAccessValue(zone) or type(zone) ~= "string" then zone = nil end
    return name, zone
end

function addon:GetZone(unit, unitName, realm)
    if not CanAccessAllValues(unit, unitName, realm) then return nil end
    if type(unit) ~= "string" or type(unitName) ~= "string" or type(realm) ~= "string" then return nil end
    if self:SafeCallBoolean(IsInGroup) ~= true then return nil end

    local prefix, indexText = unit:match("^(raid)(%d+)$")
    if prefix == "raid" then
        local _, zone = GetRosterNameAndZone(tonumber(indexText))
        return zone
    end

    prefix, indexText = unit:match("^(party)(%d+)$")
    if prefix ~= "party" then return nil end

    local fullName = unitName .. "-" .. realm
    local count = SafeValues(GetNumGroupMembers)
    if type(count) ~= "number" or count < 1 then count = 5 end
    count = math.min(count, 40)

    for rosterIndex = 1, count do
        local name, zone = GetRosterNameAndZone(rosterIndex)
        if name == unitName or name == fullName then return zone end
    end
    return nil
end
'''
    path.write_text(text[:start] + zone + text[end:], encoding="utf-8")

    replace_once(
        "Engine/Midnight.lua",
        '''    local spellID = context.spellID
    if type(spellID) == "number" then
        local setSpellByID = ReadObjectMember(tooltip, "SetSpellByID")
        if type(setSpellByID) == "function" then
            local ok, result = pcall(setSpellByID, tooltip, spellID)
            if ok and CanAccessValue(result) and result ~= false then return true end
        end
    end
''',
        '''    local spellID = context.spellID
    local spellType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell or nil
    if type(spellID) == "number" and context.type == spellType then
        local setSpellByID = ReadObjectMember(tooltip, "SetSpellByID")
        if type(setSpellByID) == "function" then
            local ok, result = pcall(setSpellByID, tooltip, spellID)
            if ok and CanAccessValue(result) and result ~= false then return true end
        end
    end
''',
        "direct spell-only refresh",
    )

    path = ROOT / "Engine/Midnight.lua"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "    -- RebuildFromTooltipInfo can replay restricted raw payload. Retail 12.1\n"
        "    -- refreshes only from an ordinary unit token, hyperlink, or spell ID.\n",
        "    -- Never replay cached raw tooltip information. Retail 12.1 refreshes\n"
        "    -- only from an ordinary unit token, hyperlink, or spell ID.\n",
    )
    path.write_text(text, encoding="utf-8")


def patch_config_and_options() -> None:
    replace_once("Config.lua", "version = 3.1,", "version = 3.2,", "schema version")

    path = ROOT / "Config.lua"
    lines = [
        line for line in path.read_text(encoding="utf-8").splitlines()
        if "showTargetBy" not in line
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    path = ROOT / "Options.lua"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        '    CreateCheckboxSetting(playerCategory, "unit.player.showTargetBy", L["unit.player.showTargetBy"])\n',
        "",
    )
    text = text.replace(
        '    CreateCheckboxSetting(npcCategory, "unit.npc.showTargetBy", L["unit.npc.showTargetBy"])\n',
        "",
    )
    marker = "        if diytable.factionBig and diytable.factionBig.enable and frame.BigFactionIcon\n"
    if marker not in text:
        raise SystemExit("Options.lua: DIY faction icon anchor missing")
    start = text.index(marker)
    end = text.index("\n\n        addon.ColorUnitBorder", start)
    replacement = '''        local factionIcon = addon:GetBigFactionIcon(frame, true)
        if diytable.factionBig and diytable.factionBig.enable
            and addon:IsObjectAccessible(factionIcon)
            and (raw.factionGroup == "Alliance" or raw.factionGroup == "Horde") then
            addon:SafeMethod(factionIcon, "SetTexture", "Interface\\\\Timer\\\\" .. raw.factionGroup .. "-Logo")
            addon:SafeMethod(factionIcon, "Show")
            frame:SetWidth(frameWidth + 48)
        elseif addon:IsObjectAccessible(factionIcon) then
            addon:SafeMethod(factionIcon, "Hide")
        end'''
    path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")

    locale_keys = (
        '["unit.player.showTargetBy"]',
        '["unit.npc.showTargetBy"]',
        '["TargetBy"]',
        '["showTargetBy"]',
    )
    for name in ("enUS.lua", "ruRU.lua", "zhCN.lua", "zhTW.lua"):
        locale = ROOT / "locales" / name
        lines = [
            line for line in locale.read_text(encoding="utf-8").splitlines()
            if not any(key in line for key in locale_keys)
        ]
        locale.write_text("\n".join(lines) + "\n", encoding="utf-8")


def patch_general() -> None:
    replace_once(
        "General.lua",
        '''        if type(class) == "string" then
            r, g, b = GetClassColor(class)
        end
''',
        '''        if type(class) == "string" then
            r, g, b = Call(GetClassColor, class)
        end
''',
        "safe class color call",
    )

    replace_once(
        "General.lua",
        '''local function GetStatusText(bar)
    local text = addon:SafeGet(bar, "TextString")
    if addon:IsObjectAccessible(text) then return text end
    return nil
end
''',
        '''local StatusTextByBar = addon.__RT_StatusTextByBar or setmetatable({}, { __mode = "k" })
addon.__RT_StatusTextByBar = StatusTextByBar

function addon:GetStatusBarText(bar)
    if not self:IsObjectAccessible(bar) then return nil end
    local text = StatusTextByBar[bar]
    if self:IsObjectAccessible(text) then return text end
    StatusTextByBar[bar] = nil
    return nil
end

local function GetStatusText(bar)
    return addon:GetStatusBarText(bar)
end
''',
        "weak status text ownership",
    )

    replace_once(
        "General.lua",
        '''    if type(general) ~= "table" or general.statusbarText ~= true
        or addon:SafeGet(bar, "forceHideText") == true then
''',
        '''    if type(general) ~= "table" or general.statusbarText ~= true
        or addon.__RT_StatusBarTextEnabled ~= true then
''',
        "status text enable state",
    )

    replace_once(
        "General.lua",
        '''    local text = addon:SafeMethod(bar, "CreateFontString", nil, "OVERLAY")
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
''',
        '''    addon.__RT_StatusBarTextEnabled = general.statusbarText == true

    local text = addon:SafeMethod(bar, "CreateFontString", nil, "OVERLAY")
    if addon:IsObjectAccessible(text) then
        StatusTextByBar[bar] = text
        addon:SafeMethod(text, "SetPoint", "CENTER")
        local font = addon:IsObjectAccessible(NumberFontNormal)
            and addon:SafeMethod(NumberFontNormal, "GetFont") or nil
        if type(font) == "string" then addon:SafeMethod(text, "SetFont", font, fontSize, fontFlag) end
    end

    local function HookStatusBarScript(scriptName, callback)
        if type(addon.CanBindScripts) == "function" and not addon:CanBindScripts(bar) then return end
        local hasScript = addon:SafeGet(bar, "HasScript")
        if type(hasScript) == "function" then
            local ok, supported = pcall(hasScript, bar, scriptName)
            if not ok or not addon:CanAccessValue(supported) or supported ~= true then return end
        end
        local hookScript = addon:SafeGet(bar, "HookScript")
        if type(hookScript) == "function" then pcall(hookScript, bar, scriptName, callback) end
    end

    HookStatusBarScript("OnShow", function(self)
        ColorStatusBar(self)
        UpdateStatusText(self)
        local config = addon.db and addon.db.general
        if type(config) == "table" and config.statusbarHeight == 0 then
            addon:SafeMethod(self, "Hide")
        end
    end)

    HookStatusBarScript("OnValueChanged", function(self)
        -- The callback value itself may be inaccessible in Retail 12.1. Read
        -- only gated status-bar/unit state instead of branching on the payload.
        UpdateStatusText(self)
        ColorStatusBar(self)
    end)
''',
        "safe status bar hooks",
    )

    replace_once(
        "General.lua",
        '''    if type(db.general) == "table" then
        db.general.legacyAuraFallback = nil
''',
        '''    if type(db.unit) == "table" then
        if type(db.unit.player) == "table" then
            db.unit.player.showTargetBy = nil
        end
        if type(db.unit.npc) == "table" then
            db.unit.npc.showTargetBy = nil
        end
    end

    if type(db.general) == "table" then
        db.general.legacyAuraFallback = nil
''',
        "Targeted By migration",
    )

    replace_once(
        "General.lua",
        '    if C_AddOns.IsAddOnLoaded("ElvUI") then return end\n',
        '''    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function"
        and C_AddOns.IsAddOnLoaded("ElvUI") then return end
''',
        "safe addon-loaded check",
    )

    replace_once(
        "General.lua",
        '''        LibEvent:trigger("tooltip.style.border.color", tip, unpack(general.borderColor))
        LibEvent:trigger("tooltip.style.background", tip, unpack(general.background))

        local factionIcon = addon:SafeGet(tip, "BigFactionIcon")
''',
        '''        if type(general.borderColor) == "table" then
            LibEvent:trigger("tooltip.style.border.color", tip, unpack(general.borderColor))
        end
        if type(general.background) == "table" then
            LibEvent:trigger("tooltip.style.background", tip, unpack(general.background))
        end

        local factionIcon = addon:GetBigFactionIcon(tip, false)
''',
        "general visual reset ownership",
    )


def patch_unit() -> None:
    replace_once(
        "Unit.lua",
        "local RAID_CACHE_TTL = 300\n",
        '''local RAID_CACHE_TTL = 300
local MYTHIC_PLUS_CACHE_TTL = 60
local MYTHIC_PLUS_CACHE_MAX = 64
''',
        "Mythic+ cache constants",
    )

    replace_once(
        "Unit.lua",
        '''local function GetBestMythicPlusKey(unit)
    if not IsOrdinaryUnit(unit) then return nil end
    if not C_PlayerInfo or type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) ~= "function" then return nil end

    local summary = Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    if type(summary) ~= "table" then return nil end

    local runs = ReadField(summary, "runs")
''',
        '''local mythicPlusCache = {}

local function GetMythicPlusSummary(unit)
    if not IsOrdinaryUnit(unit) then return nil end
    if not C_PlayerInfo or type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) ~= "function" then return nil end

    local guid = Call(UnitGUID, unit)
    if type(guid) ~= "string" or guid == "" then return nil end

    local now = GetTime and GetTime() or 0
    local cached = mythicPlusCache[guid]
    if type(cached) == "table" and type(cached.time) == "number"
        and now - cached.time <= MYTHIC_PLUS_CACHE_TTL then
        return cached.summary
    end

    local count = 0
    local oldestGUID, oldestTime
    for cacheGUID, entry in pairs(mythicPlusCache) do
        local entryTime = type(entry) == "table" and entry.time or nil
        if type(entryTime) ~= "number" or now - entryTime > MYTHIC_PLUS_CACHE_TTL then
            mythicPlusCache[cacheGUID] = nil
        else
            count = count + 1
            if oldestTime == nil or entryTime < oldestTime then
                oldestGUID = cacheGUID
                oldestTime = entryTime
            end
        end
    end
    if count >= MYTHIC_PLUS_CACHE_MAX and oldestGUID then
        mythicPlusCache[oldestGUID] = nil
    end

    local summary = Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    if type(summary) ~= "table" then return nil end
    mythicPlusCache[guid] = { summary = summary, time = now }
    return summary
end

local function GetBestMythicPlusKey(unit, summary)
    if not IsOrdinaryUnit(unit) then return nil end
    if type(summary) ~= "table" then summary = GetMythicPlusSummary(unit) end
    if type(summary) ~= "table" then return nil end

    local runs = ReadField(summary, "runs")
''',
        "bounded Mythic+ summary cache",
    )

    replace_once(
        "Unit.lua",
        '''local function InvalidateRaidCache()
    raidProgressCache = nil
    raidProgressCacheTime = 0
end
''',
        '''local function InvalidateProgressCaches()
    raidProgressCache = nil
    raidProgressCacheTime = 0
    wipe(mythicPlusCache)
end
''',
        "progress cache invalidation",
    )

    replace_once(
        "Unit.lua",
        '''    local guid = GetSafeUnitGUID(unit)
    local now = GetTime and GetTime() or 0
    local cache = GetCachedInspect(guid, now)

    if playerConfig.showItemLevel == true then
''',
        '''    local guid = GetSafeUnitGUID(unit)
    local now = GetTime and GetTime() or 0
    local cache = GetCachedInspect(guid, now)
    local ratingSummary
    if playerConfig.showPveScore == true or playerConfig.showBestKey == true then
        ratingSummary = GetMythicPlusSummary(unit)
    end

    -- Spec is displayed independently of the item-level toggle, so request one
    -- throttled inspect whenever no fresh inspect record exists.
    if not isSelf and not cache then
        RequestInspect(unit, guid, now)
    end

    if playerConfig.showItemLevel == true then
''',
        "one summary and inspect request per hover",
    )

    replace_once(
        "Unit.lua",
        '''        elseif cache and type(cache.ilvl) == "number" then
            itemLevel = cache.ilvl
        else
            RequestInspect(unit, guid, now)
        end
''',
        '''        elseif cache and type(cache.ilvl) == "number" then
            itemLevel = cache.ilvl
        end
''',
        "deduplicate inspect request",
    )

    replace_once(
        "Unit.lua",
        '''        if isSelf and C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
            score = Call(C_ChallengeMode.GetOverallDungeonScore)
        elseif not isSelf and C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
            local summary = Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
            score = ReadNumber(summary, "currentSeasonScore")
        end
''',
        '''        if isSelf and C_ChallengeMode and type(C_ChallengeMode.GetOverallDungeonScore) == "function" then
            score = Call(C_ChallengeMode.GetOverallDungeonScore)
        end
        if type(score) ~= "number" then
            score = ReadNumber(ratingSummary, "currentSeasonScore")
        end
''',
        "reuse Mythic+ summary for score",
    )

    replace_once(
        "Unit.lua",
        "        local level, mapName = GetBestMythicPlusKey(unit)\n",
        "        local level, mapName = GetBestMythicPlusKey(unit, ratingSummary)\n",
        "reuse Mythic+ summary for key",
    )
    replace_once(
        "Unit.lua",
        "    self.cbInvalidate = InvalidateRaidCache\n",
        "    self.cbInvalidate = InvalidateProgressCaches\n",
        "invalidate all progress caches",
    )
    replace_once(
        "Unit.lua",
        '''    local icon = addon:SafeGet(tip, "BigFactionIcon")
    if not addon:IsObjectAccessible(icon) then return end
''',
        '''    local icon = addon:GetBigFactionIcon(tip, true)
    if not addon:IsObjectAccessible(icon) then return end
''',
        "external faction icon ownership",
    )


def patch_small_modules() -> None:
    replace_once(
        "Anchor.lua",
        '''    if finalPass then
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y)
''',
        '''    if finalPass then
        LibEvent:trigger("tooltip.anchor.static", tip, parent, anchor.x, anchor.y, anchor.p)
''',
        "inherited static point",
    )

    replace_once(
        "Item.lua",
        '    addon:SafeMethod(line, "SetText", text .. string.format(" |cff00eeee/%d|r", itemData.stackCount))\n',
        '''    text = text:gsub("%s+|cff00eeee/%d+|r$", "")
    addon:SafeMethod(line, "SetText", text .. string.format(" |cff00eeee/%d|r", itemData.stackCount))
''',
        "idempotent stack suffix",
    )

    replace_once(
        "LinkID.lua",
        '''local function HasRefreshableIDContext(context)
    if not CanAccess(context) or type(context) ~= "table" then return false end
    if GetSafeNumber(context.id) then return true end
    if GetSafeNumber(context.itemID) then return true end
    if GetSafeNumber(context.spellID) then return true end
    return CanAccess(context.guid) and type(context.guid) == "string" and context.guid ~= ""
end
''',
        '''local function HasRefreshableIDContext(context)
    if not CanAccess(context) or type(context) ~= "table" then return false end

    if CanAccess(context.unitToken) and type(context.unitToken) == "string"
        and context.unitToken ~= "" then
        return true
    end
    if CanAccess(context.guid) and type(context.guid) == "string" and context.guid ~= "" then
        return true
    end
    if GetSafeNumber(context.itemID)
        or (CanAccess(context.hyperlink) and type(context.hyperlink) == "string" and context.hyperlink ~= "") then
        return true
    end

    local spellType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell or nil
    return context.type == spellType and GetSafeNumber(context.spellID) ~= nil
end
''',
        "precise modifier refresh contexts",
    )

    replace_once(
        "LinkID.lua",
        '''        if addon:IsObjectAccessible(button) and not achievementHooks[button] then
            achievementHooks[button] = true
            addon:SafeMethod(button, "HookScript", "OnEnter", ShowAchievementID)
            if buttonTemplate == "AchievementTemplate" then
                addon:SafeMethod(button, "HookScript", "OnLeave", GameTooltip_Hide)
            end
        end
''',
        '''        if addon:IsObjectAccessible(button) and not achievementHooks[button]
            and (type(addon.CanBindScripts) ~= "function" or addon:CanBindScripts(button)) then
            achievementHooks[button] = true
            addon:SafeMethod(button, "HookScript", "OnEnter", ShowAchievementID)
            if buttonTemplate == "AchievementTemplate" then
                addon:SafeMethod(button, "HookScript", "OnLeave", GameTooltip_Hide)
            end
        end
''',
        "achievement script binding gate",
    )

    path = ROOT / "Mount.lua"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        '        addon.MM:AttachEvent("Mount", "MOUNT_JOURNAL_SEARCH_UPDATED", self.cbRefreshMounts, "MOUNT_JOURNAL_SEARCH_UPDATED")\n',
        "",
    )
    text = text.replace(
        '        LibEvent:attachEvent("MOUNT_JOURNAL_SEARCH_UPDATED", self.cbRefreshMounts)\n',
        "",
    )
    path.write_text(text, encoding="utf-8")

    replace_once(
        "SkinFrames.lua",
        '''    local questScrollFrame = QuestScrollFrame
    local storyTooltip = questScrollFrame and questScrollFrame.StoryTooltip
    if storyTooltip then addon:RegisterTooltipFrame(storyTooltip) end
''',
        '''    local questScrollFrame = QuestScrollFrame
    local storyTooltip = addon:IsObjectAccessible(questScrollFrame)
        and addon:SafeGet(questScrollFrame, "StoryTooltip") or nil
    if storyTooltip then addon:RegisterTooltipFrame(storyTooltip) end
''',
        "safe story tooltip child access",
    )

    replace_once(
        "Model.lua",
        '''    local config = addon.db and addon.db.model or {}
    local frame = CreateFrame("PlayerModel", nil, UIParent)
    if not addon:IsObjectAccessible(frame) then return nil end
''',
        '''    local config = addon.db and addon.db.model or {}
    local ok, frame = pcall(CreateFrame, "PlayerModel", nil, UIParent)
    if not ok or not addon:IsObjectAccessible(frame) then return nil end
''',
        "contained model creation",
    )


def remove_obsolete_paths() -> None:
    for relative in (
        "Compat_MoneyFrame.lua",
        "Engine/TooltipBootstrap.lua",
        "Engine/Runtime12_1.lua",
        "todo.md",
        ".github/workflows/normalize-runtime.yml",
        ".github/workflows/audit-source-export.yml",
        ".github/workflows/audit-donors-export.yml",
    ):
        path = ROOT / relative
        if path.is_file() or path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)


def main() -> None:
    copy_payload()
    patch_core()
    patch_midnight()
    patch_config_and_options()
    patch_general()
    patch_unit()
    patch_small_modules()
    remove_obsolete_paths()
    print("Retail 12.1 single-runtime refactor applied.")


if __name__ == "__main__":
    main()
