#!/usr/bin/env python3
"""Apply the final post-merge Retail 12.1 hardening pass."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str, label: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"{path}: missing patch anchor: {label}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


def replace_between(path: str, start_marker: str, end_marker: str, replacement: str, label: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if replacement in text:
        return
    try:
        start = text.index(start_marker)
        end = text.index(end_marker, start)
    except ValueError as error:
        raise SystemExit(f"{path}: missing range anchor: {label}") from error
    target.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


def patch_context_boundary() -> None:
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
        "clear stale context for inaccessible payload",
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
        "processor stale-context invalidation",
    )

    replacement = '''function addon:RefreshTooltipSafe(tooltip, reason)
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
    end

    if context.type == dataTypes.Item then
        local hyperlink = context.hyperlink
        if type(hyperlink) ~= "string" or hyperlink == "" then return false end

        local setHyperlink = ReadObjectMember(tooltip, "SetHyperlink")
        if type(setHyperlink) ~= "function" then return false end
        local ok, result = pcall(setHyperlink, tooltip, hyperlink)
        return ok and CanAccessValue(result) and result ~= false
    end

    if context.type == dataTypes.Spell then
        local spellID = context.spellID
        if type(spellID) ~= "number" then return false end

        local setSpellByID = ReadObjectMember(tooltip, "SetSpellByID")
        if type(setSpellByID) ~= "function" then return false end
        local ok, result = pcall(setSpellByID, tooltip, spellID)
        return ok and CanAccessValue(result) and result ~= false
    end

    -- Aura, macro, flyout, pet-action, and generic records must not be rebuilt
    -- as another tooltip type merely to refresh addon-owned lines.
    return false
end

'''
    replace_between(
        "Engine/Midnight.lua",
        "function addon:RefreshTooltipSafe(tooltip, reason)",
        "function addon:RefreshManagedTooltipsMatching",
        replacement,
        "type-preserving tooltip refresh",
    )


def patch_modifier_refresh() -> None:
    replacement = '''local function HasRefreshableIDContext(context)
    if not CanAccess(context) or type(context) ~= "table" then return false end

    local dataTypes = Enum and Enum.TooltipDataType
    if type(dataTypes) ~= "table" then return false end

    if context.type == dataTypes.Unit then
        return (CanAccess(context.unitToken) and type(context.unitToken) == "string" and context.unitToken ~= "")
            or (CanAccess(context.guid) and type(context.guid) == "string" and context.guid ~= "")
    end

    if context.type == dataTypes.Item then
        return GetSafeNumber(context.itemID) ~= nil
            or (CanAccess(context.hyperlink) and type(context.hyperlink) == "string" and context.hyperlink ~= "")
    end

    if context.type == dataTypes.Spell then
        return GetSafeNumber(context.spellID) ~= nil
    end

    return false
end

'''
    replace_between(
        "LinkID.lua",
        "local function HasRefreshableIDContext(context)",
        "local function GetButtonID",
        replacement,
        "type-preserving modifier refresh",
    )


def patch_style_hooks() -> None:
    replacement = '''local function InstallTooltipHooks(tooltip)
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

    -- A tooltip registered while script bindings are temporarily forbidden is
    -- left retryable. EnsureStyle() will attempt installation again after the
    -- restriction changes instead of preserving a false "hooked" state.
    if installed then HookedTooltips[tooltip] = true end
end

'''
    replace_between(
        "Engine/Style.lua",
        "local function InstallTooltipHooks(tooltip)",
        "local function EnsureStyle",
        replacement,
        "retryable tooltip hooks",
    )


def patch_mythic_plus_cache() -> None:
    replacement = '''local mythicPlusCache = {}

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
    if count >= MYTHIC_PLUS_CACHE_MAX and oldestGUID then
        mythicPlusCache[oldestGUID] = nil
    end

    local summary = Call(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    summary = SanitizeMythicPlusSummary(summary)
    if not summary then return nil end

    mythicPlusCache[guid] = { summary = summary, time = now }
    return summary
end

'''
    replace_between(
        "Unit.lua",
        "local mythicPlusCache = {}",
        "local function GetBestMythicPlusKey",
        replacement,
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
            if isNewEntry then
                inspectCacheCount = inspectCacheCount + 1
            end
        end
''',
        "avoid empty inspect cache entries",
    )

    replace_once(
        "Unit.lua",
        '''    local sameRequest = pendingInspectGUID == guid and pendingInspectUnit == unit
    if sameRequest and now - inspectLastRequest <= INSPECT_REQUEST_THROTTLE then return end

    pendingInspectGUID = guid
''',
        '''    -- NotifyInspect is a single global request channel. Throttle all
    -- targets, not only repeated requests for the same GUID.
    if now - inspectLastRequest <= INSPECT_REQUEST_THROTTLE then return end

    pendingInspectGUID = guid
''',
        "global inspect throttle",
    )


def patch_item_cache_refresh() -> None:
    insert = '''local function RefreshLoadedItem(_, itemID, success)
    if not addon:CanAccessValue(itemID) or type(itemID) ~= "number" then return end
    if not addon:CanAccessValue(success) or success ~= true then return end

    addon:RefreshManagedTooltipsMatching(function(_, context)
        return type(context) == "table" and context.type == (Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item)
            and context.itemID == itemID
    end, "GET_ITEM_INFO_RECEIVED")
end

LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", RefreshLoadedItem)

'''
    replace_once(
        "Engine/TooltipRegistry.lua",
        "RegisterKnownTooltips(false)\n",
        insert + "RegisterKnownTooltips(false)\n",
        "central item cache refresh",
    )

    target = ROOT / "ExpansionInfo.lua"
    text = target.read_text(encoding="utf-8")
    if "local function OnItemInfoReceived" in text:
        start = text.index("local function OnItemInfoReceived")
        end = text.index("local M = {}", start)
        text = text[:start] + text[end:]
    text = text.replace("    self.cbItemInfo = OnItemInfoReceived\n", "")
    event_block = '''
    if addon.MM and addon.MM.AttachEvent then
        addon.MM:AttachEvent("ExpansionInfo", "GET_ITEM_INFO_RECEIVED", self.cbItemInfo, "GET_ITEM_INFO_RECEIVED")
    else
        LibEvent:attachEvent("GET_ITEM_INFO_RECEIVED", self.cbItemInfo)
    end
'''
    text = text.replace(event_block, "")
    target.write_text(text, encoding="utf-8")


def patch_checker() -> None:
    replace_once(
        "tools/check_repo.py",
        '''    if re.search(r"\\b(?:tip|tooltip|bar)\\.(?:BigFactionIcon|TextString|forceHideText)\\s*=", all_lua_code):
        fail("addon bookkeeping was restored on a Blizzard tooltip/status bar")

    if "setmetatable({}, { __mode = \\\"k\\\" })" not in style_raw:
''',
        '''    if re.search(r"\\b(?:tip|tooltip|bar)\\.(?:BigFactionIcon|TextString|forceHideText)\\s*=", all_lua_code):
        fail("addon bookkeeping was restored on a Blizzard tooltip/status bar")
    if ".BigFactionIcon" in all_lua_code:
        fail("legacy frame-owned faction icon access was restored")

    unit_raw = (ROOT / "Unit.lua").read_text(encoding="utf-8")
    registry_raw = (ROOT / "Engine/TooltipRegistry.lua").read_text(encoding="utf-8")
    if "SanitizeMythicPlusSummary" not in unit_raw:
        fail("Mythic+ summaries are no longer sanitized before caching")
    if "GET_ITEM_INFO_RECEIVED" not in registry_raw:
        fail("managed item tooltips no longer refresh from the central item-cache event")
    if "context.type == dataTypes.Unit" not in midnight_raw
        or "context.type == dataTypes.Item" not in midnight_raw
        or "context.type == dataTypes.Spell" not in midnight_raw:
        fail("tooltip refresh is no longer type preserving")

    if "setmetatable({}, { __mode = \\\"k\\\" })" not in style_raw:
''',
        "final runtime invariants",
    )


def patch_docs() -> None:
    replace_once(
        "CHANGELOG.md",
        '''- Added a bounded 60-second Mythic+ summary cache to avoid duplicate API work on
  repeated unit hovers.
''',
        '''- Added a bounded 60-second Mythic+ summary cache to avoid duplicate API work on
  repeated unit hovers; only sanitized primitive fields are retained.
- Made tooltip refresh type-preserving, invalidated stale context immediately
  when a raw payload becomes inaccessible, and centralized item-cache refresh.
- Applied one global throttle to the single `NotifyInspect` request channel and
  stopped caching empty inspect results.
''',
        "post-final changelog",
    )

    replace_once(
        "AGENT_GUIDE.md",
        '''Inspect requests are asynchronous, throttled, and cached. Mythic+ summaries are
bounded and cached briefly. Mount journal data and saved raid progress are
collected outside repeated tooltip work.
''',
        '''Inspect requests are asynchronous, globally throttled, and cached. Mythic+
summaries are sanitized to ordinary primitive fields before entering a bounded
short-lived cache. Mount journal data and saved raid progress are collected
outside repeated tooltip work.
''',
        "cache ownership guidance",
    )


def main() -> None:
    patch_context_boundary()
    patch_modifier_refresh()
    patch_style_hooks()
    patch_mythic_plus_cache()
    patch_item_cache_refresh()
    patch_checker()
    patch_docs()
    print("Final Retail 12.1 hardening applied.")


if __name__ == "__main__":
    main()
