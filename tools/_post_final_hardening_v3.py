#!/usr/bin/env python3
"""Canonicalize the final Retail 12.1 runtime after all prior finalizers."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str, label: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old in text:
        target.write_text(text.replace(old, new, 1), encoding="utf-8")
        return
    if new not in text:
        raise SystemExit(f"{path}: missing patch anchor: {label}")


def replace_range(path: str, start_marker: str, end_marker: str, replacement: str, label: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    try:
        start = text.index(start_marker)
        end = text.index(end_marker, start)
    except ValueError as error:
        raise SystemExit(f"{path}: missing range anchor: {label}") from error
    target.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


def canonicalize_context_and_refresh() -> None:
    replace_once(
        "Engine/Midnight.lua",
        '''function addon:GetPrimaryTooltipContext(tooltip, suppliedData)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if not CanAccessValue(suppliedData) then return nil end

    if suppliedData == nil then
''',
        '''function addon:GetPrimaryTooltipContext(tooltip, suppliedData)
    if not self:IsObjectAccessible(tooltip) then return nil end
    if not CanAccessValue(suppliedData) then
        ContextByTooltip[tooltip] = nil
        return nil
    end

    if suppliedData == nil then
''',
        "stale context invalidation",
    )

    replace_once(
        "Engine/TooltipProcessor.lua",
        '''local function BuildContext(tooltip, tooltipData)
    if not addon:CanAccessValue(tooltipData) then return nil end
    return addon:GetPrimaryTooltipContext(tooltip, tooltipData)
end
''',
        '''local function BuildContext(tooltip, tooltipData)
    if not addon:CanAccessValue(tooltipData) then
        addon:SetPrimaryTooltipContext(tooltip, nil)
        return nil
    end
    return addon:GetPrimaryTooltipContext(tooltip, tooltipData)
end
''',
        "processor context invalidation",
    )

    canonical = '''function addon:RefreshTooltipSafe(tooltip, reason)
    if not self:IsObjectAccessible(tooltip) then return false end
    if CallObjectMethod(tooltip, "IsShown") ~= true then return false end

    local context = self:GetPrimaryTooltipContext(tooltip)
    if not context then return false end

    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then return false end

    if context.type == dataTypes.Unit then
        local unit = context.unitToken
        if type(unit) ~= "string" or self:IsUnitIdentityRestricted(unit) then return false end
        local setUnit = ReadObjectMember(tooltip, "SetUnit")
        if type(setUnit) ~= "function" then return false end
        local ok, result = pcall(setUnit, tooltip, unit)
        return ok and CanAccessValue(result) and result ~= false
    elseif context.type == dataTypes.Item then
        local hyperlink = context.hyperlink
        if type(hyperlink) ~= "string" or hyperlink == "" then return false end
        local setHyperlink = ReadObjectMember(tooltip, "SetHyperlink")
        if type(setHyperlink) ~= "function" then return false end
        local ok, result = pcall(setHyperlink, tooltip, hyperlink)
        return ok and CanAccessValue(result) and result ~= false
    elseif context.type == dataTypes.Spell then
        local spellID = context.spellID
        if type(spellID) ~= "number" then return false end
        local setSpellByID = ReadObjectMember(tooltip, "SetSpellByID")
        if type(setSpellByID) ~= "function" then return false end
        local ok, result = pcall(setSpellByID, tooltip, spellID)
        return ok and CanAccessValue(result) and result ~= false
    end

    -- Aura, macro, flyout, pet-action, and generic records are never rebuilt
    -- as a different tooltip type merely to refresh addon-owned lines.
    return false
end

'''
    replace_range(
        "Engine/Midnight.lua",
        "function addon:RefreshTooltipSafe(tooltip, reason)",
        "function addon:RefreshManagedTooltipsMatching",
        canonical,
        "type-preserving refresh",
    )


def canonicalize_modifier_refresh() -> None:
    canonical = '''local function HasRefreshableIDContext(context)
    if not CanAccess(context) or type(context) ~= "table" then return false end

    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then return false end

    if context.type == dataTypes.Unit then
        return (CanAccess(context.unitToken) and type(context.unitToken) == "string" and context.unitToken ~= "")
            or (CanAccess(context.guid) and type(context.guid) == "string" and context.guid ~= "")
    elseif context.type == dataTypes.Item then
        return GetSafeNumber(context.itemID) ~= nil
            or (CanAccess(context.hyperlink) and type(context.hyperlink) == "string" and context.hyperlink ~= "")
    elseif context.type == dataTypes.Spell then
        return GetSafeNumber(context.spellID) ~= nil
    end
    return false
end

'''
    replace_range(
        "LinkID.lua",
        "local function HasRefreshableIDContext(context)",
        "local function GetButtonID",
        canonical,
        "modifier refresh",
    )


def canonicalize_style_hooks() -> None:
    canonical = '''local function InstallTooltipHooks(tooltip)
    if HookedTooltips[tooltip] or not addon:IsTooltipSafe(tooltip) then return end

    local installed = false
    installed = HookScriptIfSupported(tooltip, "OnShow", function(frame)
        LibEvent:trigger("tooltip:show", frame)
    end) or installed
    installed = HookScriptIfSupported(tooltip, "OnHide", function(frame)
        LibEvent:trigger("tooltip:hide", frame)
    end) or installed
    installed = HookScriptIfSupported(tooltip, "OnTooltipCleared", function(frame)
        addon:ResetTooltipStyleFrame(frame)
        LibEvent:trigger("tooltip:cleared", frame)
    end) or installed

    -- A tooltip first seen during a temporary ScriptBindings restriction stays
    -- retryable instead of retaining a false hooked state.
    if installed then HookedTooltips[tooltip] = true end
end

'''
    replace_range(
        "Engine/Style.lua",
        "local function InstallTooltipHooks(tooltip)",
        "local function EnsureStyle",
        canonical,
        "retryable hooks",
    )


def canonicalize_mythic_plus_and_inspect() -> None:
    canonical = '''local mythicPlusCache = {}

local function SanitizeMythicPlusSummary(summary)
    if not CanAccess(summary) or type(summary) ~= "table" then return nil end

    local clean = { runs = {} }
    local currentSeasonScore = ReadNumber(summary, "currentSeasonScore")
    if currentSeasonScore ~= nil then clean.currentSeasonScore = currentSeasonScore end

    local sourceRuns = ReadField(summary, "runs")
    if type(sourceRuns) == "table" then
        for _, run in ipairs(sourceRuns) do
            if CanAccess(run) and type(run) == "table" then
                local level = ReadNumber(run, "bestRunLevel")
                local score = ReadNumber(run, "bestRunScore")
                if score == nil then score = ReadNumber(run, "mapScore") end
                local modeID = ReadNumber(run, "challengeModeID")
                if level ~= nil or score ~= nil or modeID ~= nil then
                    clean.runs[#clean.runs + 1] = {
                        bestRunLevel = level,
                        bestRunScore = score,
                        challengeModeID = modeID,
                    }
                end
            end
        end
    end

    if clean.currentSeasonScore == nil and #clean.runs == 0 then return nil end
    return clean
end

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
    if count >= MYTHIC_PLUS_CACHE_MAX and oldestGUID then mythicPlusCache[oldestGUID] = nil end

    local summary = Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    summary = SanitizeMythicPlusSummary(summary)
    if not summary then return nil end
    mythicPlusCache[guid] = { summary = summary, time = now }
    return summary
end

'''
    replace_range(
        "Unit.lua",
        "local mythicPlusCache = {}",
        "local function GetBestMythicPlusKey",
        canonical,
        "sanitized Mythic+ cache",
    )

    replace_once(
        "Unit.lua",
        '''        local now = GetTime and GetTime() or 0
        PruneInspectCache(now)
        local isNewEntry = inspectCache[guid] == nil
        inspectCache[guid] = {
            ilvl = itemLevel,
            specID = specID,
            time = now,
        }
        if isNewEntry then
            inspectCacheCount = inspectCacheCount + 1
        end
''',
        '''        if itemLevel ~= nil or specID ~= nil then
            local now = GetTime and GetTime() or 0
            PruneInspectCache(now)
            local isNewEntry = inspectCache[guid] == nil
            inspectCache[guid] = {
                ilvl = itemLevel,
                specID = specID,
                time = now,
            }
            if isNewEntry then inspectCacheCount = inspectCacheCount + 1 end
        end
''',
        "nonempty inspect cache",
    )

    old_throttle = '''    local sameRequest = pendingInspectGUID == guid and pendingInspectUnit == unit
    if sameRequest and now - inspectLastRequest <= INSPECT_REQUEST_THROTTLE then return end

    pendingInspectGUID = guid
'''
    new_throttle = '''    -- NotifyInspect is one global request channel. Throttle all targets,
    -- not only repeated requests for the same GUID.
    if now - inspectLastRequest <= INSPECT_REQUEST_THROTTLE then return end

    pendingInspectGUID = guid
'''
    replace_once("Unit.lua", old_throttle, new_throttle, "global inspect throttle")


def canonicalize_item_refresh() -> None:
    target = ROOT / "Engine/TooltipRegistry.lua"
    text = target.read_text(encoding="utf-8")
    marker = "RegisterKnownTooltips(false)"
    marker_pos = text.index(marker)
    listener_pos = text.find("local function RefreshLoadedItem")
    if listener_pos >= 0 and listener_pos < marker_pos:
        start = listener_pos
    else:
        start = marker_pos

    listener = '''local function RefreshLoadedItem(_, itemID, success)
    if not addon:CanAccessValue(itemID) or type(itemID) ~= "number" then return end
    if not addon:CanAccessValue(success) or success ~= true then return end

    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    addon:RefreshManagedTooltipsMatching(function(_, context)
        return type(context) == "table" and context.type == itemType and context.itemID == itemID
    end, "GET_ITEM_INFO_RECEIVED")
end

LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", RefreshLoadedItem)

RegisterKnownTooltips(false)'''
    text = text[:start] + listener + text[marker_pos + len(marker):]
    target.write_text(text, encoding="utf-8")

    target = ROOT / "ExpansionInfo.lua"
    text = target.read_text(encoding="utf-8")
    if "local function OnItemInfoReceived" in text:
        start = text.index("local function OnItemInfoReceived")
        end = text.index("local M = {}", start)
        text = text[:start] + text[end:]
    text = text.replace("    self.cbItemInfo = OnItemInfoReceived\n", "")
    attach_call = 'addon.MM:AttachEvent("ExpansionInfo", "GET_ITEM_INFO_RECEIVED"'
    if attach_call in text:
        call_pos = text.index(attach_call)
        block_start = text.rfind("\n    if addon.MM and addon.MM.AttachEvent then", 0, call_pos)
        block_end = text.index("\n    end", call_pos) + len("\n    end")
        text = text[:block_start] + text[block_end:]
    text = text.replace('        LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", self.cbItemInfo)\n', "")
    target.write_text(text, encoding="utf-8")


def harden_checker() -> None:
    path = ROOT / "tools/check_repo.py"
    text = path.read_text(encoding="utf-8")
    old = '''    if "GET_ITEM_INFO_RECEIVED" not in registry:
        fail("managed item tooltips no longer refresh from the central item-cache event")
'''
    new = '''    if registry.count("local function RefreshLoadedItem") != 1:
        fail("managed item tooltips must have exactly one central item-cache listener")
    if registry.count('LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", RefreshLoadedItem)') != 1:
        fail("central item-cache event registration must exist exactly once")
'''
    if old in text:
        text = text.replace(old, new, 1)
    elif new not in text:
        raise SystemExit("tools/check_repo.py: hardened item listener anchor missing")
    path.write_text(text, encoding="utf-8")


def main() -> None:
    canonicalize_context_and_refresh()
    canonicalize_modifier_refresh()
    canonicalize_style_hooks()
    canonicalize_mythic_plus_and_inspect()
    canonicalize_item_refresh()
    harden_checker()
    print("Canonical Retail 12.1 normalization applied.")


if __name__ == "__main__":
    main()
