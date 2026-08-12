
-------------------------------------
-- Core Author:M
-------------------------------------

local addonName, addon = ...

local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
local LibMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)

local AFK = AFK
local DND = DND
local MALE = MALE
local BOSS = BOSS
local DEAD = DEAD
local ELITE = ELITE
local FEMALE = FEMALE
local TARGET = TARGET
local PLAYER = PLAYER
local RARE = GARRISON_MISSION_RARE
local OFFLINE = FRIENDS_LIST_OFFLINE
local BASE_MOVEMENT_SPEED = BASE_MOVEMENT_SPEED or 7
local TOOLTIP_UPDATE_TIME = TOOLTIP_UPDATE_TIME or 0.2


--=========================================================
-- Font flag normalization
--
-- WoW API SetFont() only accepts a limited set of flags.
-- Many legacy forks used "NORMAL" to mean "no outline".
-- Passing "NORMAL" to SetFont() errors: bad argument #3.
--=========================================================
function addon:NormalizeFontFlag(flag, defaultFlag)
    if (flag == "default") then
        flag = defaultFlag
    end
    if (flag == nil) then
        return ""
    end
    if (type(flag) ~= "string") then
        return ""
    end
    flag = flag:upper()
    if (flag == "NORMAL" or flag == "NONE") then
        return ""
    end
    return flag
end

--=========================================================
-- Midnight (12.0+) compatibility
--
-- WoW 12.0 introduces "SecretValue" for many APIs to prevent addons from
-- performing logic on hidden data. Any math/comparison/string ops on a
-- SecretValue can throw.
--
-- The goal here is simple: never do Lua-side logic on SecretValue.
-- We fall back to placeholders or skip optional features.
--=========================================================
local __IsSecretBase = (type(issecretvalue) == "function") and issecretvalue or nil

-- Robust SecretValue detection:
-- Some SecretValue values do not report via issecretvalue(), but still hard-error
-- on any Lua comparison. Detect via a protected self-compare.
local function IsSecret(v)
    if (__IsSecretBase and __IsSecretBase(v)) then
        return true
    end
    -- Never do boolean tests or comparisons on unknown values.
    -- Self-compare inside pcall is the most reliable generic probe.
    local ok = pcall(function() return v == v end)
    return not ok
end

function addon:IsSecret(v)
    return IsSecret(v)
end

local function SafeBoolean(v)
    if (IsSecret(v)) then return nil end
    if (v == nil) then return nil end
    if (type(v) == "boolean") then return v end
    return v and true or false
end

function addon:SafeBoolean(v)
    return SafeBoolean(v)
end

function addon:SafeCallBoolean(fn, ...)
    if (type(fn) ~= "function") then return nil end
    local ok, value = pcall(fn, ...)
    if (not ok) then return nil end
    return SafeBoolean(value)
end



function addon:SafeToString(v, placeholder)
    -- Avoid any logic on SecretValue. First gate by IsSecret (pcall-safe).
    if (IsSecret(v)) then return placeholder or "??" end
    if (v == nil) then return placeholder end
    if (type(v) == "string") then return v end
    local ok, s = pcall(tostring, v)
    if (ok) then return s end
    return placeholder or "??"
end


-- Safe wrapper around tooltip:GetSpell()
-- In Midnight, GameTooltip:GetSpell() can hard-error for certain TooltipData pipelines
-- (notably UnitAura/NamePlate aura tooltips) because Blizzard compares secret TooltipData fields.
-- Always use pcall when probing spell data from a tooltip.
function addon:SafeGetSpell(tip)
    if (not tip or not tip.GetSpell) then return nil end
    local ok, a, b, c = pcall(tip.GetSpell, tip)
    if (not ok) then return nil end
    return a, b, c
end

-- Returns a non-secret numeric spellID when available, otherwise nil.
function addon:SafeGetSpellID(tip)
    local context = tip and self:GetPrimaryTooltipContext(tip)
    local contextSpellID = context and context.spellID
    if (contextSpellID and type(contextSpellID) == "number" and not self:IsSecret(contextSpellID)) then
        return contextSpellID
    end

    -- Prefer cached ids from TooltipDataProcessor dispatch (covers Action/UnitAura
    -- tooltips where :GetSpell() can be nil or unsafe).
    local cached = tip and tip.__RT_LastSpellID
    if (cached and type(cached) == "number" and not self:IsSecret(cached)) then
        return cached
    end

    local _, b, c = self:SafeGetSpell(tip)
    local id = c or b
    if (id and not self:IsSecret(id)) then
        return id
    end
    return nil
end

--=========================================================
-- Unit token resolution (SecretValue-safe)
--
-- TooltipData (and our LibEvent bridge) may pass a unit token as
-- a SecretValue. SecretValues cannot be compared (==/~=) or used
-- in conditionals. We avoid Lua-side operations by mapping such a
-- value back to a safe, canonical unit token via UnitIsUnit.
--
-- Prefer modern GUID-based resolution first, then fall back to UnitIsUnit
-- across a wider set of common unit tokens.
--=========================================================
local STATIC_UNIT_TOKENS = {
    "mouseover",
    "target",
    "focus",
    "player",
    "pet",
    "vehicle",
    "targettarget",
    "focustarget",
    "mouseovertarget",
    "pettarget",
}

local INDEXED_UNIT_TOKEN_GROUPS = {
    { prefix = "boss", max = 8 },
    { prefix = "arena", max = 5 },
    { prefix = "party", max = 4 },
    { prefix = "partypet", max = 4 },
    { prefix = "raid", max = 40 },
    { prefix = "raidpet", max = 40 },
    { prefix = "nameplate", max = 40 },
}

local function ResolveGuidUnitToken(guid)
    if (type(guid) ~= "string" or guid == "" or IsSecret(guid) or not UnitTokenFromGUID) then
        return nil
    end
    local ok, unit = pcall(UnitTokenFromGUID, guid)
    if (not ok or IsSecret(unit) or type(unit) ~= "string" or unit == "") then
        return nil
    end
    return unit
end

local function ResolveCandidateToken(unit, token)
    if (type(token) ~= "string") then
        return nil
    end
    local ok, same = pcall(UnitIsUnit, unit, token)
    if (ok and not IsSecret(same) and same == true) then
        return token
    end
end

function addon:ResolveUnitToken(unit, guid)
    local guidToken = ResolveGuidUnitToken(guid)
    if (guidToken) then
        return guidToken
    end

    -- SecretValue-safe: never boolean-test a potentially secret value.
    if (IsSecret(unit)) then
        for i = 1, #STATIC_UNIT_TOKENS do
            local token = ResolveCandidateToken(unit, STATIC_UNIT_TOKENS[i])
            if (token) then
                return token
            end
        end
        for i = 1, #INDEXED_UNIT_TOKEN_GROUPS do
            local group = INDEXED_UNIT_TOKEN_GROUPS[i]
            for index = 1, group.max do
                local token = ResolveCandidateToken(unit, group.prefix .. index)
                if (token) then
                    return token
                end
            end
        end
        return nil
    end

    if (unit == nil) then
        return nil
    end

    if (type(unit) == "string") then
        return unit
    end

    for i = 1, #STATIC_UNIT_TOKENS do
        local token = ResolveCandidateToken(unit, STATIC_UNIT_TOKENS[i])
        if (token) then
            return token
        end
    end

    for i = 1, #INDEXED_UNIT_TOKEN_GROUPS do
        local group = INDEXED_UNIT_TOKEN_GROUPS[i]
        for index = 1, group.max do
            local token = ResolveCandidateToken(unit, group.prefix .. index)
            if (token) then
                return token
            end
        end
    end

    return nil
end

local function GetSafeTooltipPrimaryData(tooltip, data)
    if (type(data) == "table") then
        return data
    end
    if (not tooltip or not tooltip.GetPrimaryTooltipData) then
        return nil
    end
    local ok, tooltipData = pcall(tooltip.GetPrimaryTooltipData, tooltip)
    if (not ok or IsSecret(tooltipData) or type(tooltipData) ~= "table") then
        return nil
    end
    return tooltipData
end

local function SafeTooltipIsType(tooltip, tooltipType)
    if (type(tooltipType) ~= "number" or not tooltip or not tooltip.IsTooltipType) then
        return false
    end
    local ok, result = pcall(tooltip.IsTooltipType, tooltip, tooltipType)
    if (not ok or IsSecret(result)) then
        return false
    end
    return result == true
end

local function SafeTooltipQuery(func, tooltip)
    if (type(func) ~= "function" or not tooltip) then
        return nil, nil, nil
    end
    local ok, a, b, c = pcall(func, tooltip)
    if (not ok) then
        return nil, nil, nil
    end
    if (IsSecret(a)) then a = nil end
    if (IsSecret(b)) then b = nil end
    if (IsSecret(c)) then c = nil end
    return a, b, c
end

local function NormalizeTooltipLink(value)
    if (IsSecret(value) or type(value) ~= "string" or value == "") then
        return nil
    end
    return value
end

local function ResolveContextItemID(hyperlink)
    if (not hyperlink or not C_Item or not C_Item.GetItemInfoInstant) then
        return nil
    end
    local itemID = C_Item.GetItemInfoInstant(hyperlink)
    if (not IsSecret(itemID) and type(itemID) == "number") then
        return itemID
    end
    return nil
end

function addon:GetPrimaryTooltipContext(tooltip, data)
    if (not tooltip) then
        return nil
    end

    local tooltipData = GetSafeTooltipPrimaryData(tooltip, data)
    local cached = tooltip.__RT_PrimaryContext
    if (cached and cached.data and tooltipData and cached.data == tooltipData) then
        return cached
    end

    local tooltipType = tooltipData and tooltipData.type
    if (IsSecret(tooltipType) or (tooltipType ~= nil and type(tooltipType) ~= "number")) then
        tooltipType = nil
    end

    local context = {
        data = tooltipData,
        type = tooltipType,
    }

    local id = tooltipData and tooltipData.id
    if (not IsSecret(id) and type(id) == "number") then
        context.id = id
    end

    local guid = tooltipData and tooltipData.guid
    if (not IsSecret(guid) and type(guid) == "string" and guid ~= "") then
        context.guid = guid
    end

    context.hyperlink = NormalizeTooltipLink(tooltipData and (tooltipData.hyperlink or tooltipData.link))

    local dataTypes = Enum and Enum.TooltipDataType
    local itemType = dataTypes and dataTypes.Item
    local spellType = dataTypes and dataTypes.Spell
    local unitType = dataTypes and dataTypes.Unit
    local auraType = dataTypes and dataTypes.UnitAura
    local actionType = dataTypes and dataTypes.Action
    local petActionType = dataTypes and dataTypes.PetAction
    local flyoutType = dataTypes and dataTypes.Flyout
    local macroType = dataTypes and dataTypes.Macro

    if (itemType and SafeTooltipIsType(tooltip, itemType)) then
        local _, hyperlink, itemID = SafeTooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedItem, tooltip)
        context.hyperlink = NormalizeTooltipLink(hyperlink) or context.hyperlink
        if (type(itemID) == "number") then
            context.itemID = itemID
        end
    end

    if (spellType and SafeTooltipIsType(tooltip, spellType)) then
        local _, spellID = SafeTooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedSpell, tooltip)
        if (type(spellID) == "number") then
            context.spellID = spellID
        end
    end

    if (unitType and SafeTooltipIsType(tooltip, unitType)) then
        local _, unitToken, displayedGuid = SafeTooltipQuery(TooltipUtil and TooltipUtil.GetDisplayedUnit, tooltip)
        if (type(displayedGuid) == "string" and displayedGuid ~= "") then
            context.guid = displayedGuid
        end
        context.unitToken = self:ResolveUnitToken(unitToken, context.guid)
    end

    if (not context.itemID and type(context.id) == "number" and context.type == itemType) then
        context.itemID = context.id
    end
    if (not context.itemID and context.hyperlink) then
        context.itemID = ResolveContextItemID(context.hyperlink)
    end

    local useDataIdAsSpellID =
        context.type == spellType
        or context.type == auraType
        or context.type == actionType
        or context.type == petActionType
        or context.type == flyoutType
        or context.type == macroType

    if (not context.spellID) then
        local spellID = tooltipData and (tooltipData.spellID or tooltipData.spellId)
        if (not IsSecret(spellID) and type(spellID) == "number") then
            context.spellID = spellID
        elseif (useDataIdAsSpellID and type(context.id) == "number") then
            context.spellID = context.id
        end
    end

    if (not context.unitToken and context.guid) then
        context.unitToken = self:ResolveUnitToken(nil, context.guid)
    end

    if (not tooltipData) then
        if (not context.hyperlink and tooltip.GetItem) then
            local ok, _, link = pcall(tooltip.GetItem, tooltip)
            if (ok) then
                context.hyperlink = NormalizeTooltipLink(link)
            end
        end

        if (not context.itemID and context.hyperlink) then
            context.itemID = ResolveContextItemID(context.hyperlink)
        end

        if (not context.spellID) then
            local _, spellID, maybeSpellID = self:SafeGetSpell(tooltip)
            local resolvedSpellID = maybeSpellID or spellID
            if (not IsSecret(resolvedSpellID) and type(resolvedSpellID) == "number") then
                context.spellID = resolvedSpellID
                if (not context.type) then
                    context.type = spellType
                end
            end
        end

        if (not context.unitToken and tooltip.GetUnit) then
            local ok, _, unitToken = pcall(tooltip.GetUnit, tooltip)
            if (ok) then
                context.unitToken = self:ResolveUnitToken(unitToken, context.guid)
            end
        end
    end

    if (not context.type) then
        if (context.itemID or context.hyperlink) then
            context.type = itemType
        elseif (context.unitToken or context.guid) then
            context.type = unitType
        elseif (context.spellID) then
            context.type = spellType
        end
    end

    if (not context.id) then
        context.id = context.itemID or context.spellID
    end

    if (not context.type and not context.id and not context.hyperlink and not context.guid and not context.unitToken and not context.spellID) then
        return nil
    end

    return context
end

function addon:SetPrimaryTooltipContext(tooltip, context)
    if (not tooltip) then
        return
    end

    tooltip.__RT_PrimaryContext = context
    tooltip.__RT_LastItemLink = context and context.hyperlink or nil
    tooltip.__RT_LastItemID = context and context.itemID or nil
    tooltip.__RT_LastSpellID = context and context.spellID or nil
    tooltip.__RT_LastUnitToken = context and context.unitToken or nil
    tooltip.__RT_LastUnitGUID = context and context.guid or nil

    if (context and type(context.id) == "number" and not context.itemID and not context.spellID) then
        tooltip.__RT_LastGenericID = context.id
        tooltip.__RT_LastGenericType = context.type
    else
        tooltip.__RT_LastGenericID = nil
        tooltip.__RT_LastGenericType = nil
    end
end

-- language & global vars
addon.L, addon.G = {}, {}
setmetatable(addon.L, {__index = function(_, k) return k end})
setmetatable(addon.G, {__index = function(_, k) return _G[k] or k end})

local function GetFocusAttribute(frame, key)
    if (not frame or not frame.GetAttribute) then
        return nil
    end
    local ok, value = pcall(frame.GetAttribute, frame, key)
    if (not ok or IsSecret(value)) then
        return nil
    end
    return value
end

local function ExtractMouseFocusUnit(frame)
    if (not frame) then
        return nil, nil
    end

    local current = frame
    local guard = 0
    while (current and guard < 32) do
        local unit = current.unit
        if (not IsSecret(unit) and unit) then
            return unit, current
        end

        unit = GetFocusAttribute(current, "unit")
        if (unit) then
            return unit, current
        end

        current = current.GetParent and current:GetParent() or nil
        guard = guard + 1
    end

    return nil, nil
end

function addon:FindMouseFocus(predicate)
    local now
    if (debugprofilestop) then
        now = debugprofilestop()
    else
        now = ((GetTime and GetTime()) or 0) * 1000
    end

    local cache = self.__RTMouseFocusCache
    local frames
    if (cache and (now - cache.time) <= 16) then
        frames = cache.frames
    else
        frames = GetMouseFoci and GetMouseFoci()
        if (type(frames) ~= "table") then
            frames = nil
        end
        self.__RTMouseFocusCache = {
            time = now,
            frames = frames,
        }
    end

    if (type(frames) ~= "table") then
        return nil
    end

    for index = 1, #frames do
        local frame = frames[index]
        if (frame and (not frame.IsForbidden or not frame:IsForbidden())) then
            if (not predicate or predicate(frame, index)) then
                return frame, index
            end
        end
    end

    return nil
end

function addon:GetMouseFocus()
    return self:FindMouseFocus()
end

function addon:GetMouseFocusUnit()
    local focus = self:FindMouseFocus(function(frame)
        local unit = ExtractMouseFocusUnit(frame)
        return unit ~= nil
    end)
    if (not focus) then
        return nil, nil, nil
    end
    local unit, owner = ExtractMouseFocusUnit(focus)
    return unit, focus, owner
end

-- tooltips
addon.tooltips = {
    GameTooltip,
    EmbeddedItemTooltip,
    ItemRefTooltip,
    ShoppingTooltip1,
    ShoppingTooltip2,
    WorldMapTooltip,
    ItemRefShoppingTooltip1,
    ItemRefShoppingTooltip2,
    NamePlateTooltip,
}

-- fast membership lookup for managed tooltips
addon.tooltipSet = {}
for _, tip in pairs(addon.tooltips) do
    if (tip) then addon.tooltipSet[tip] = true end
end

--=========================================================
-- TooltipDataProcessor orchestrator for managed retail tooltips.
--=========================================================
function addon:InitTooltipDataProcessor()
    if (self.__RT_TDPInitialized) then
        return self.__RT_UseTDP == true
    end

    local TDP = TooltipDataProcessor
    if (not TDP or not TDP.AddTooltipPostCall) then
        self.__RT_UseTDP = false
        self.__RT_TDPInitialized = true
        return false
    end

    local E = Enum and Enum.TooltipDataType
    local T_ITEM  = (E and E.Item) or 0
    local T_SPELL = (E and E.Spell) or 1
    local T_UNIT  = (E and E.Unit) or 2
    local T_AURA  = (E and E.UnitAura) or 7
    local ACTION_LIKE_TYPES = {}
    local actionTypeSeen = {}

    local function AddActionLikeType(typeId)
        if (type(typeId) ~= "number") then return end
        if (actionTypeSeen[typeId]) then return end
        actionTypeSeen[typeId] = true
        ACTION_LIKE_TYPES[#ACTION_LIKE_TYPES + 1] = typeId
    end

    AddActionLikeType(E and E.PetAction)
    AddActionLikeType(E and E.Flyout)
    AddActionLikeType(E and E.Macro)

    local function LooksLikeBlizzardSpellTooltip(t)
        local n = t and t.GetName and t:GetName()
        if (type(n) ~= "string") then return false end
        if (n == "SpellBookTooltip") then return true end
        if (n:find("PlayerSpells") and n:find("Tooltip")) then return true end
        if (n:find("Spell") and n:find("Tooltip")) then return true end
        return false
    end

    local function Managed(tip)
        if (not tip or not addon.tooltipSet) then return false end
        if (tip.IsForbidden and tip:IsForbidden()) then return false end
        if (addon.tooltipSet[tip]) then return true end
        local p = tip.GetParent and tip:GetParent()
        if (p and addon.tooltipSet[p]) then return true end
        if (LooksLikeBlizzardSpellTooltip(tip)) then return true end
        if (p and LooksLikeBlizzardSpellTooltip(p)) then return true end
        return false
    end

    local function Mark(tip, kind)
        if (not tip) then return end
        tip.__RT_LastDispatchKind = kind
        tip.__RT_LastDispatchTime = GetTime()
    end

    local function BuildContext(tip, data)
        local context = addon:GetPrimaryTooltipContext(tip, data)
        addon:SetPrimaryTooltipContext(tip, context)
        return context
    end


    local function WantTrigger(ev)
        if (addon.MM and addon.MM.HasTriggerSubscribers) then
            return addon.MM:HasTriggerSubscribers(ev) == true
        end
        return true
    end

    function addon:IsActionBar(tip)
        local focus = self:FindMouseFocus(function(frame)
            if (frame.action) then return true end
            if (GetFocusAttribute(frame, "action") ~= nil) then return true end
            local name = frame.GetName and frame:GetName()
            if (name and (name:find("ActionButton") or name:find("MultiBar") or name:find("PetActionButton") or name:find("PossessButton"))) then
                return true
            end
            local parent = frame.GetParent and frame:GetParent()
            local pname = parent and parent.GetName and parent:GetName()
            if (pname and (pname:find("ActionButton") or pname:find("MultiBar") or pname:find("PetActionButton") or pname:find("PossessButton"))) then
                return true
            end
            return false
        end)
        return focus ~= nil
    end

    function addon:IsBag(tip)
        local focus = self:FindMouseFocus(function(frame)
            local parent = frame.GetParent and frame:GetParent()
            local pname = parent and parent.GetName and parent:GetName()
            if (pname and pname:find("ContainerFrame")) then return true end
            if (frame.GetItemContextMatchResult) then return true end
            local name = frame.GetName and frame:GetName()
            if (name and (name:find("ContainerFrame") or name:find("BagItem"))) then return true end
            return false
        end)
        return focus ~= nil
    end

    local function CheckVisibility(tip, data)
        if (tip.IsForbidden and tip:IsForbidden()) then return false end
        local cfg = addon.db and addon.db.general and addon.db.general.visibility
        if (not cfg) then return true end

        -- Bags
        if (cfg.bags == "hide" and addon:IsBag(tip)) then return false end

        -- Action Bars
        if (cfg.actionBars == "hide" and addon:IsActionBar(tip)) then return false end

        -- In Combat
        if (InCombatLockdown()) then
            local mode = cfg.inCombat or "show"
            if (mode == "hide") then return false end
            if (mode == "unitOnly" and data and data.type ~= T_UNIT) then return false end
        end

        -- In Raid
        if (cfg.inRaid == "hide" and IsInRaid()) then return false end

        -- In Arena
        if (cfg.inArena == "hide" and C_PvP.IsArena()) then return false end

        return true
    end

    local function DispatchItem(tip, data)
        if not CheckVisibility(tip, data) then tip:Hide(); return end
        if (not Managed(tip)) then return end
        if (not addon:AllowTrigger("item", tip)) then return end
        local context = BuildContext(tip, data)
        local link = context and context.hyperlink
        if (link) then
            if (WantTrigger("tooltip:item")) then
                Mark(tip, "item")
                LibEvent:trigger("tooltip:item", tip, link, context)
            end
        end
    end

    local function DispatchSpell(tip, data)
        if not CheckVisibility(tip, data) then tip:Hide(); return end
        if (not Managed(tip)) then return end
        if (not addon:AllowTrigger("spell", tip)) then return end

        local context = BuildContext(tip, data)

        if (WantTrigger("tooltip:spell")) then
            Mark(tip, "spell")
            LibEvent:trigger("tooltip:spell", tip, context)
        end
    end

    local GetSpellTextureSafe = C_Spell.GetSpellTexture

    local function DispatchAction(tip, data)
        if not CheckVisibility(tip, data) then tip:Hide(); return end
        if (not Managed(tip)) then return end

        local wantSpell = WantTrigger("tooltip:spell")
        local wantItem  = WantTrigger("tooltip:item")
        local context = BuildContext(tip, data)

        -- Action tooltips can represent spells, items, macros, flyouts, etc.
        -- Prefer spell dispatch if we can validate a spell texture.
        local sid = context and context.spellID
        if (sid) then
            local tex = GetSpellTextureSafe(sid)
            if (tex and not addon:IsSecret(tex)) then
                if (wantSpell and addon:AllowTrigger("spell", tip)) then
                    Mark(tip, "spell")
                    LibEvent:trigger("tooltip:spell", tip, context)
                end
                return
            end
        end

        local link = context and context.hyperlink
        if (link) then
            if (wantItem and addon:AllowTrigger("item", tip)) then
                Mark(tip, "item")
                LibEvent:trigger("tooltip:item", tip, link, context)
            end
            return
        end

        -- Unknown action payload: native Blizzard C API handles sizing.
    end


    local function DispatchUnit(tip, data)
        if not CheckVisibility(tip, data) then tip:Hide(); return end
        if (not Managed(tip)) then return end
        if (not addon:AllowTrigger("unit", tip)) then return end

        local context = BuildContext(tip, data)
        local guid = context and context.guid
        local unit = context and context.unitToken

        if (WantTrigger("tooltip:unit") and unit) then
            Mark(tip, "unit")
            LibEvent:trigger("tooltip:unit", tip, unit, guid, context and context.type, context)
        end
    end

    local function DispatchAura(tip, data)
        if not CheckVisibility(tip, data) then tip:Hide(); return end
        if (not Managed(tip)) then return end
        if (not addon:AllowTrigger("aura", tip)) then return end

        local context = BuildContext(tip, data)
        local aid = context and context.spellID
        local args = data and data.args
        if (addon:IsSecret(args)) then args = nil end
        if (WantTrigger("tooltip:aura")) then
            Mark(tip, "aura")
            -- Preserve the existing trigger contract while context propagates.
            LibEvent:trigger("tooltip:aura", tip, args, aid, context)
        end
    end

    local ok = pcall(function()
        TDP.AddTooltipPostCall(T_ITEM, DispatchItem)
        TDP.AddTooltipPostCall(T_SPELL, DispatchSpell)
        for i = 1, #ACTION_LIKE_TYPES do
            TDP.AddTooltipPostCall(ACTION_LIKE_TYPES[i], DispatchAction)
        end
        TDP.AddTooltipPostCall(T_UNIT, DispatchUnit)
        TDP.AddTooltipPostCall(T_AURA, DispatchAura)
    end)

    -- Optional: attach a lightweight generic id dispatcher for other TooltipData types.
    -- Each add is protected so unsupported types cannot break our core registrations.
    if (ok and addon.TYPE_NAME) then
        local EXCLUDE = {
            [T_ITEM] = true,
            [T_SPELL] = true,
            [T_UNIT] = true,
            [T_AURA] = true,
        }
        for i = 1, #ACTION_LIKE_TYPES do
            EXCLUDE[ACTION_LIKE_TYPES[i]] = true
        end
        local function DispatchGeneric(tip, data)
            if (not Managed(tip)) then return end
            if (not addon:AllowTrigger("other", tip)) then return end

            local context = BuildContext(tip, data)
            local id = context and context.id
            if (type(id) ~= "number") then return end

            if (WantTrigger("tooltip:genericid")) then
                Mark(tip, "genericid")
                local tooltipType = context and context.type
                local label = addon.TYPE_NAME[tooltipType] or "ID"
                LibEvent:trigger("tooltip:genericid", tip, label, id, tooltipType, context)
            end
        end

        for typeId in pairs(addon.TYPE_NAME) do
            if (type(typeId) == "number" and not EXCLUDE[typeId]) then
                pcall(function()
                    TDP.AddTooltipPostCall(typeId, DispatchGeneric)
                end)
            end
        end
    end

    self.__RT_UseTDP = ok and true or false
    self.__RT_TDPInitialized = true
end

-- Register additional Blizzard tooltips that can be loaded on demand (notably spell-related tooltips).
-- Some spell UI tooltips are NOT GameTooltip and would otherwise bypass our skin + spell overrides.
function addon:RegisterTooltipFrame(tip)
    if (not tip) then return end
    if (self.tooltipSet and self.tooltipSet[tip]) then return end
    self.tooltips[#self.tooltips+1] = tip
    if (self.tooltipSet) then self.tooltipSet[tip] = true end

    -- Initialize triggers (safe even if variables are not loaded yet).
    LibEvent:trigger("tooltip:init", tip)
end

local function RegisterKnownTooltipFrames()
    local names = {
        "SpellBookTooltip",
        "FloatingSpellFlyoutTooltip",
        "PlayerSpellsTooltip",
    }
    for _, n in ipairs(names) do
        local t = _G[n]
        if (t) then addon:RegisterTooltipFrame(t) end
    end
end

RegisterKnownTooltipFrames()
addon:InitTooltipDataProcessor()
LibEvent:attachEvent("PLAYER_LOGIN,ADDON_LOADED", function()
    RegisterKnownTooltipFrames()
end)

function addon:RefreshTooltipSafe(tip, reason)
    if (not tip or not tip.IsShown or not tip:IsShown()) then
        return false
    end
    if (tip.IsForbidden and tip:IsForbidden()) then
        return false
    end

    local context = self:GetPrimaryTooltipContext(tip)

    local unit = context and context.unitToken
    if (not unit) then
        unit = self:GetTooltipUnit(tip)
    end
    if (type(unit) == "string" and unit ~= "" and tip.SetUnit) then
        local ok, result = pcall(tip.SetUnit, tip, unit)
        if (ok and result ~= false) then
            return true
        end
    end

    local hyperlink = context and context.hyperlink
    if (type(hyperlink) == "string" and hyperlink ~= "" and tip.SetHyperlink) then
        local ok, result = pcall(tip.SetHyperlink, tip, hyperlink)
        if (ok and result ~= false) then
            return true
        end
    end

    local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if (context and unitType and context.type == unitType) then
        return false
    end

    if (tip.GetPrimaryTooltipData and tip.RebuildFromTooltipInfo) then
        local ok, data = pcall(tip.GetPrimaryTooltipData, tip)
        if (ok and not self:IsSecret(data) and type(data) == "table") then
            local rebuilt = pcall(tip.RebuildFromTooltipInfo, tip)
            if (rebuilt) then
                return true
            end
        end
    end

    return false
end


-- 圖標集
addon.icons = {
    Alliance   = "|TInterface\\TargetingFrame\\UI-PVP-ALLIANCE:14:14:0:0:64:64:10:36:2:38|t",
    Horde      = "|TInterface\\TargetingFrame\\UI-PVP-HORDE:14:14:0:0:64:64:4:38:2:36|t",
    Neutral    = "|TInterface\\Timer\\Panda-Logo:14|t",
    pvp        = "|TInterface\\TargetingFrame\\UI-PVP-FFA:14:14:0:0:64:64:10:36:0:38|t",
    class      = "|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:0:256:256:%d:%d:%d:%d|t",
    battlepet  = "|TInterface\\Timer\\Panda-Logo:15|t",
    pettype    = "|TInterface\\TargetingFrame\\PetBadge-%s:14|t",
    questboss  = "|TInterface\\TargetingFrame\\PortraitQuestBadge:0|t",
    friend     = "|TInterface\\AddOns\\RothTooltip\\texture\\friend:14:14:0:0:32:32:1:30:2:30|t",
    bnetfriend = "|TInterface\\ChatFrame\\UI-ChatIcon-BattleNet:14:14:0:0:32:32:1:30:2:30|t",
    TANK       = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t",
    HEALER     = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t",
    DAMAGER    = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t",
}

-- 背景
addon.bgs = {
    gradual = "Interface\\Buttons\\GreyscaleRamp64",
    dark    = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    alpha   = "Interface\\Tooltips\\UI-Tooltip-Background",
    rock    = "Interface\\FrameGeneral\\UI-Background-Rock",
    marble  = "Interface\\FrameGeneral\\UI-Background-Marble",
    RothTooltipDarkTexture = "Interface\\AddOns\\RothTooltip\\texture\\RothTooltipDarkTexture",
}

--配置 (对elements鍵的值进行合并校验,不含factionBig,npcTitle键)
local function AutoValidateElements(src, dst)
    local keys = {}
    for k, v in ipairs(dst) do
        keys[k] = true
        for i = #v, 1, -1 do
            if (not src[v[i]]) then
                tremove(v, i)
            else
                keys[v[i]] = true
            end
        end
    end
    for k, v in pairs(src) do
        if (type(k) ~= "number" and not dst[k]) then
            dst[k] = v
            if (k == "factionBig" or k == "npcTitle") then
            elseif (not keys[k]) then
                tinsert(dst[1], 1, k)
            end
        end
    end
    return dst
end

--字符型数字键转为数字键
function addon:FixNumericKey(t)
    local key
    local tbl = {}
    for k, v in pairs(t) do
        if (type(k) == "string" and string.match(k,"^[1-9]%d*$")) then
            key = tonumber(k)
            t[k] = nil
            tbl[key] = v
        end
    end
    for k, v in pairs(tbl) do
        if (not t[k]) then t[k] = v end
    end
    for k, v in pairs(t) do
        if (type(v) == "table") then
            t[k] = self:FixNumericKey(v)
        end
    end
    return t
end

-- 配置合併
function addon:MergeVariable(src, dst)
    dst.version = src.version
    for k, v in pairs(src) do
        if (dst[k] == nil) then
            dst[k] = v
        elseif (type(dst[k]) == "table" and k~="elements") then
            self:MergeVariable(v, dst[k])
        elseif (type(dst[k]) == "table" and k=="elements") then
            dst[k] = AutoValidateElements(v, dst[k])
        end
    end
    return dst
end

-- 找行
function addon:FindLine(tooltip, keyword)
    if (not tooltip or not keyword) then return end
    local name = tooltip.GetName and tooltip:GetName()
    if (not name) then return end

    local line, text
    for i = 2, tooltip:NumLines() do
        line = _G[name .. "TextLeft" .. i]
        text = line and line:GetText()
        -- Tooltip text can be SecretValue in 12.0+. Never pattern-match on it.
        if (not IsSecret(text) and text and strfind(text, keyword)) then
            return line, i, _G[name .. "TextRight" .. i]
        end
    end
end

-- 刪行
function addon:HideLine(tooltip, keyword)
    if (not tooltip or not keyword) then return end
    local name = tooltip.GetName and tooltip:GetName()
    if (not name) then return end

    local line, text
    for i = 2, tooltip:NumLines() do
        line = _G[name .. "TextLeft" .. i]
        text = line and line:GetText()
        if (not IsSecret(text) and text and strfind(text, keyword)) then
            line:SetText(nil)
            break
        end
    end
end

-- 刪行
function addon:HideLines(tooltip, number, endNumber)
    if (not tooltip) then return end
    local name = tooltip.GetName and tooltip:GetName()
    if (not name) then return end

    endNumber = endNumber or 999
    for i = number, tooltip:NumLines() do
        if (endNumber >= i) then
            local fs = _G[name .. "TextLeft" .. i]
            if (fs) then
                fs:SetText(nil)
            end
        end
    end
end

-- 取行
function addon:GetLine(tooltip, number)
    if (not tooltip) then return end
    local name = tooltip.GetName and tooltip:GetName()
    if (not name) then return end

    local num = tooltip:NumLines()
    if (number > num) then
        tooltip:AddLine(" ")
        return self:GetLine(tooltip, num+1)
    end
    return _G[name .. "TextLeft" .. number], _G[name .. "TextRight" .. number]
end

-- 顔色
function addon:GetHexColor(color, g, b)
    if (g and b) then
        return ("%02x%02x%02x"):format(color*255, g*255, b*255)
    elseif color.r then
        return ("%02x%02x%02x"):format(color.r*255, color.g*255, color.b*255)
    else
        local r, g, b = unpack(color)
        return ("%02x%02x%02x"):format(r*255, g*255, b*255)
    end
end

-- 顔色
function addon:GetRGBColor(hex)
    if (not hex) then return 1, 1, 1 end
    if (type(hex) ~= "string") then return 1, 1, 1 end
    hex = hex:gsub("^#", "")
    if (string.match(hex, "^%x%x%x%x%x%x%x%x$")) then
        hex = strsub(hex, 3, 8)
    end
    if (string.match(hex, "^%x%x%x%x%x%x$")) then
        local r = tonumber(strsub(hex,1,2),16) or 255
        local g = tonumber(strsub(hex,3,4),16) or 255
        local b = tonumber(strsub(hex,5,6),16) or 255
        return r/255, g/255, b/255
    end
    return 1, 1, 1
end

--字體
function addon:GetFont(font, default)
    if (font == "default") then
        font = default
    elseif (font and _G[font]) then
        font = _G[font].GetFont and _G[font]:GetFont()
    elseif(font and LibMedia and LibMedia:IsValid("font", font)) then
        font = LibMedia:Fetch("font", font)
    end
    return font or default
end

--背景
function addon:GetBgFile(bgvalue)
    if (self.bgs[bgvalue]) then
        return self.bgs[bgvalue]
    end
    if (LibMedia) then
        return LibMedia:Fetch("background", bgvalue)
    end
end

--Bar
function addon:GetBarFile(bgvalue)
    if (bgvalue and LibMedia and LibMedia:IsValid("statusbar", bgvalue)) then
        return LibMedia:Fetch("statusbar", bgvalue)
    else
        return bgvalue
    end
end

--GetUnit (SecretValue-safe)
function addon:GetTooltipUnit(tooltip)
    if (not tooltip) then return end
    local context = self:GetPrimaryTooltipContext(tooltip)
    if (context and type(context.unitToken) == "string") then
        return context.unitToken
    end
    if (not tooltip.GetUnit) then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if (not ok) then return end
    if (addon:IsSecret(unit)) then
        unit = addon:ResolveUnitToken(unit, context and context.guid)
    end
    if (addon:IsSecret(unit)) then return end
    return unit
end

-- 任務怪
function addon:GetQuestBossIcon(unit)
    if (self:SafeCallBoolean(UnitIsQuestBoss, unit)) then
        return self.icons.questboss
    end
end

-- PVP圖標
function addon:GetPVPIcon(unit)
    if (self:SafeCallBoolean(UnitIsPVPFreeForAll, unit)) then
        return self.icons.pvp
    end
end

-- 角色圖標
function addon:GetRoleIcon(unit)
    local role = UnitGroupRolesAssigned(unit)
    if (IsSecret(role)) then role = nil end
    if (role) then
        return self.icons[strupper(role)]
    end
end

-- 陣營圖標
function addon:GetFactionIcon(factionGroup)
    return self.icons[factionGroup]
end

-- 標記圖標
function addon:GetRaidIcon(unit)
    local index = GetRaidTargetIndex(unit)

    -- Midnight (12.0+): raid target index may be a SecretValue.
    -- Never do boolean tests on a SecretValue.
    if (addon:IsSecret(index) or (issecretvalue and issecretvalue(index))) then
        return
    end
    if (index) then
        local icon = ICON_LIST[index]
        if (icon) then
            return icon .. "0|t"
        end
    end
end

-- 職業圖標
function addon:GetClassIcon(class)
    if (not class) then return end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[strupper(class)]
    if (type(coords) ~= "table") then return end
    local x1, x2, y1, y2 = unpack(coords)
    if (not x1 or not x2 or not y1 or not y2) then return end
    return format(self.icons.class, x1*256, x2*256, y1*256, y2*256)
end

--好友图标
function addon:GetFriendIcon(unit)
    if (not self:SafeCallBoolean(UnitIsPlayer, unit)) then
        return
    end
    local guid = UnitGUID(unit)
    if (IsSecret(guid)) then guid = nil end

    local isFriend = guid and self:SafeCallBoolean(C_FriendList and C_FriendList.IsFriend, guid)
    if (isFriend) then
        return self.icons.friend
    end

    local playerGuid = UnitGUID("player")
    if (IsSecret(playerGuid)) then playerGuid = nil end

    if (guid and playerGuid and guid ~= playerGuid) then
        local accountInfo = C_BattleNet.GetAccountInfoByGUID(guid)
        local bnFriend = accountInfo and self:SafeBoolean(accountInfo.isFriend)
        if (bnFriend) then
            return self.icons.bnetfriend
        end
    end
end

-- 戰寵
function addon:GetBattlePet(unit)
    local wildPet = self:SafeCallBoolean(UnitIsWildBattlePet, unit)
    local companionPet = self:SafeCallBoolean(UnitIsBattlePetCompanion, unit)
    if (wildPet or companionPet) then
        local petType = UnitBattlePetType(unit)
        return self.icons.battlepet, format(self.icons.pettype, PET_TYPE_SUFFIX[petType] or "")
    end
end

-- 移動速度
function addon:GetUnitSpeed(unit)
    local _, speed, flightSpeed, swimSpeed = GetUnitSpeed(unit)
    -- In 12.0+ these may be SecretValue; never do math on them.
    if (IsSecret(speed) or IsSecret(flightSpeed) or IsSecret(swimSpeed)) then return end
    if (not speed or speed == 0) then return end
	speed = speed/BASE_MOVEMENT_SPEED*100
    swimSpeed = swimSpeed/BASE_MOVEMENT_SPEED*100
	flightSpeed = flightSpeed/BASE_MOVEMENT_SPEED*100
	local isOtherPlayersPet = self:SafeCallBoolean(UnitIsOtherPlayersPet, unit)
    local swimming = self:SafeCallBoolean(IsSwimming, unit)
    local flying = self:SafeCallBoolean(IsFlying, unit)
	if (isOtherPlayersPet) then
    elseif (swimming) then
		speed = swimSpeed
	elseif (flying) then
		speed = flightSpeed
	end
    return speed+0.5
end

-- 頭銜 @param2:true為前綴
function addon:GetTitle(name, pvpName)
    if (not pvpName) then return end
    if (name == pvpName) then return end
    local pos = string.find(pvpName, name)
    local title = pvpName:gsub(name, "", 1)
    title = title:gsub(",", ""):gsub("，", "")
    title = strtrim(title)
    return title, pos ~= 1
end

-- 性別
function addon:GetGender(gender)
    if (gender == 2) then
        return MALE, "male"
    elseif (gender == 3) then
        return FEMALE, "female"
    end
end

-- NPC頭銜
function addon:GetNpcTitle(tip)
    local line, index = self:FindLine(tip, "^"..LEVEL)
    if (not line or index <= 2) then return end
    return self:GetLine(tip, 2)
end

--地區
function addon:GetZone(unit, unitname, realm)
    local inGroup = self:SafeCallBoolean(IsInGroup)
    if (not inGroup) then return end
    local t, i = string.match(unit, "(.-)(%d+)")
    if (i and t == "raid") then
        return select(7, GetRaidRosterInfo(i))
    elseif (i and t == "party") then
        local name, zone
        local fullname = unitname .. "-" .. realm
        for j = 1, 5 do
            name, _, _, _, _, _, zone = GetRaidRosterInfo(j)
            if (name and not string.find(name, "-") and name == unitname) then
                return zone
            elseif (name and string.find(name, "-") and name == fullname) then
                return zone
            end
        end
    end
end

-- 全信息
local t = {}
function addon:GetUnitInfo(unit)
    local name, realm = UnitName(unit)
    local pvpName = UnitPVPName(unit)
    local gender = UnitSex(unit)
    local level = UnitLevel(unit)
    local effectiveLevel = UnitEffectiveLevel(unit)
    local raceName, race = UnitRace(unit)
    local className, class = UnitClass(unit)
    local factionGroup, factionName = UnitFactionGroup(unit)
    local reaction = UnitReaction(unit, "player")
    local guildName, guildRank, guildIndex, guildRealm = GetGuildInfo(unit)
    local classif = UnitClassification(unit)
    local role = UnitGroupRolesAssigned(unit)
    local creature = UnitCreatureType(unit)
    local connected = self:SafeCallBoolean(UnitIsConnected, unit)
    local isAFK = self:SafeCallBoolean(UnitIsAFK, unit)
    local isDND = self:SafeCallBoolean(UnitIsDND, unit)
    local isPlayerUnit = self:SafeCallBoolean(UnitIsPlayer, unit)

    -- 12.0+ SecretValue sanitization
    if (IsSecret(name)) then name = nil end
    if (IsSecret(realm)) then realm = nil end
    if (IsSecret(pvpName)) then pvpName = nil end
    if (IsSecret(gender)) then gender = nil end
    if (IsSecret(raceName)) then raceName = nil end
    if (IsSecret(race)) then race = nil end
    if (IsSecret(className)) then className = nil end
    if (IsSecret(class)) then class = nil end
    if (IsSecret(factionGroup)) then factionGroup = nil end
    if (IsSecret(factionName)) then factionName = nil end
    if (IsSecret(reaction)) then reaction = nil end
    if (IsSecret(guildName)) then guildName = nil end
    if (IsSecret(guildRank)) then guildRank = nil end
    if (IsSecret(guildIndex)) then guildIndex = nil end
    if (IsSecret(guildRealm)) then guildRealm = nil end
    if (IsSecret(classif)) then classif = nil end
    if (IsSecret(role)) then role = "NONE" end
    if (IsSecret(creature)) then creature = nil end

    local levelNum = (not IsSecret(level)) and level or nil
    local effectiveLevelNum = (not IsSecret(effectiveLevel)) and effectiveLevel or nil

    local levelValue = "??"
    if (type(levelNum) == "number" and levelNum >= 0) then
        levelValue = levelNum
    end

    local classifBoss
    if (classif == "worldboss") then classifBoss = BOSS end
    if (type(levelNum) == "number" and levelNum == -1) then classifBoss = BOSS end

    t.raidIcon     = self:GetRaidIcon(unit)
    t.pvpIcon      = self:GetPVPIcon(unit)
    t.factionIcon  = self:GetFactionIcon(factionGroup)
    t.classIcon    = self:GetClassIcon(class)
    t.roleIcon     = self:GetRoleIcon(unit)
    t.questIcon    = self:GetQuestBossIcon(unit)
    t.friendIcon   = self:GetFriendIcon(unit)
    --t.battlepetIcon = self:GetBattlePet(unit)
    t.factionName  = factionName
    t.role         = (role and role ~= "NONE") and role
    t.name         = name
    t.gender       = self:GetGender(gender)
    t.realm        = realm or GetRealmName()
    t.levelValue   = levelValue
    t.className    = className
    t.raceName     = raceName
    t.guildName    = guildName
    t.guildRank    = guildRank
    t.guildIndex   = guildName and guildIndex
    t.guildRealm   = guildRealm
    t.statusAFK    = isAFK and AFK or nil
    t.statusDND    = isDND and DND or nil
    t.statusDC     = (connected == false) and OFFLINE or nil
    t.reactionName = reaction and _G["FACTION_STANDING_LABEL"..reaction]
    t.creature     = creature
    t.classifBoss  = classifBoss
    t.classifElite = classif == "elite" and ELITE
    t.classifRare  = (classif == "rare" or classif == "rareelite") and RARE
    t.isPlayer     = isPlayerUnit and PLAYER or nil
    t.moveSpeed    = self:GetUnitSpeed(unit)
    t.zone         = self:GetZone(unit, t.name, t.realm)
    t.unit         = unit                     --unit
    t.level        = levelNum                 --1~123|-1
    t.effectiveLevel = effectiveLevelNum or levelNum
    t.race         = race                     --nil|NightElf|Troll...
    t.class        = class                    --DRUID|HUNTER...
    t.factionGroup = factionGroup             --Alliance|Horde|Neutral
    t.reaction     = reaction                 --nil|1|2|3|4|5|6|7|8
    t.classif      = classif                  --normal|worldboss|elite|rare|rareelite
    t.title, t.titleIsPrefix = self:GetTitle(name, pvpName)
    if (t.classifBoss) then t.classifElite = false end
    return t
end

-- Filter
function addon:CheckFilter(config, raw)
    if (IsAltKeyDown() or IsControlKeyDown()) then return true end
    if (not config.enable) then return end
    if (config.filter == "" or config.filter == "none") then
        return true
    end
    if (config.filter) then
        local key, oppo, func
        key = strsplit(":", config.filter)
        key, oppo = key:gsub("not%s+", "")
        func = self.filterfunc[key]
        if (func) then
            local res = func(raw, select(2,strsplit(":", config.filter)))
            if (oppo > 0) then
                return not res
            else
                return res
            end
        end
    end
    return true
end

-- 格式化數據
function addon:FormatData(value, config, raw)
    local color, wildcard = config.color, config.wildcard
    if (self.colorfunc[color]) then
        color = select(4, self.colorfunc[color](raw))
    end
    if (color == "" or color == "default" or color == "none") then
        return (wildcard):format(value)
    else
        if (type(color)=="table") then color = self:GetHexColor(color) end
        return ("|cff"..color..wildcard.."|r"):format(value)
    end
end

-- 獲取數據
function addon:GetUnitData(unit, elements, raw)
    local data = {}
    local config, name, title
    if (not raw) then
        raw = self:GetUnitInfo(unit)
    end
    for i, v in ipairs(elements) do
        data[i] = {}
        for ii, e in ipairs(v) do
            config = elements[e]
            if (self:CheckFilter(config, raw) and raw[e]) then
                if (e == "name") then name = #data[i]+1 end   --name位置
                if (e == "title") then title = #data[i]+1 end --title位置
                if (config.color and config.wildcard) then
                    if (e == "title" and name == #data[i] and raw.titleIsPrefix) then
                        tinsert(data[i], name, self:FormatData(raw[e], config, raw))
                    elseif (e == "name" and title == #data[i] and not raw.titleIsPrefix) then
                        tinsert(data[i], title, self:FormatData(raw[e], config, raw))
                    else
                        tinsert(data[i], self:FormatData(raw[e], config, raw))
                    end
                else
                    tinsert(data[i], self:SafeToString(raw[e], ""))
                end
            end
        end
    end
    for i = #data, 1, -1 do
        if (not data[i][1]) then tremove(data, i) end
    end
    return data
end

-- HookScript
function addon:TinyHookScript(script, func, scripts)
    if (self:HasScript(script)) then
        self:HookScript(script, func)
    elseif (scripts) then
        for _, newscript in ipairs(scripts) do
            if (self[newscript]) then
                hooksecurefunc(self, newscript, func)
            end
        end
    end
end


addon.filterfunc, addon.colorfunc = {}, {}

addon.colorfunc.class = function(raw)
    if (CUSTOM_CLASS_COLORS) then
        local color = CUSTOM_CLASS_COLORS[raw.class]
        if color then
            return color.r, color.g, color.b, addon:GetHexColor(color.r, color.g, color.b)
        end
        return 1, 1, 1, "ffffff"
    end
    if (not raw or not raw.class) then
        return 1, 1, 1, "ffffff"
    end
    local r, g, b = GetClassColor(raw.class)
    if (not r or not g or not b) then
        return 1, 1, 1, "ffffff"
    end
    return r, g, b, addon:GetHexColor(r, g, b)
end

addon.colorfunc.level = function(raw)
    local lvl = raw and raw.effectiveLevel
    if (IsSecret(lvl)) then lvl = nil end
    if (type(lvl) ~= "number" or lvl <= 0) then lvl = 999 end
    local color = GetCreatureDifficultyColor(lvl)
    return color.r, color.g, color.b, addon:GetHexColor(color)
end

addon.colorfunc.reaction = function(raw)
    local color = FACTION_BAR_COLORS[raw.reaction or 4]
    return color.r, color.g, color.b, addon:GetHexColor(color)
end

addon.colorfunc.itemQuality = function(raw)
    local color = ITEM_QUALITY_COLORS[raw.itemQuality or 0]
    return color.r, color.g, color.b, addon:GetHexColor(color)
end

addon.colorfunc.selection = function(raw)
    local r, g, b = UnitSelectionColor(raw.unit)
    return r, g, b, addon:GetHexColor(r, g, b)
end

addon.colorfunc.faction = function(raw)
    if (raw.factionGroup == "Neutral") then
        return 0.9, 0.7, 0, "e5b200"
    elseif (raw.factionGroup == UnitFactionGroup("player")) then
        return 0, 1, 0.2, "00cc33"
    else
        return 1, 0.2, 0, "dd3300"
    end
end

addon.filterfunc.reaction6 = function(raw, reaction)
    return (raw.reaction or 4) >= 6
end

addon.filterfunc.reaction5 = function(raw, reaction)
    return (raw.reaction or 4) >= 5
end

addon.filterfunc.reaction = function(raw, reaction)
    return (raw.reaction or 4) >= (tonumber(reaction) or 5)
end

addon.filterfunc.inraid = function(raw)
    return IsInRaid()
end

addon.filterfunc.incombat = function(raw)
    return InCombatLockdown()
end

addon.filterfunc.samerealm = function(raw)
    return raw.realm == GetRealmName()
end

addon.filterfunc.samecrossrealm = function(raw)
    return UnitRealmRelationship(raw.unit) ~= LE_REALM_RELATION_COALESCED
end

addon.filterfunc.inpvp = function(raw)
    return select(2, IsInInstance()) == "pvp"
end

addon.filterfunc.inarena = function(raw)
    return select(2, IsInInstance()) == "arena"
end

addon.filterfunc.ininstance = function(raw)
    return IsInInstance()
end

addon.filterfunc.sameguild = function(raw)
    local name, _, _, server = GetGuildInfo("player")
    if (name and name == raw.guildName and server == raw.guildRealm) then
        return true
    end
end

LibEvent:attachTrigger("tooltip.scale", function(self, frame, scale)
    frame:SetScale(scale)
end)

LibEvent:attachTrigger("tooltip.anchor.cursor", function(self, frame, parent)
    frame:SetOwner(parent, "ANCHOR_CURSOR")
end)

LibEvent:attachTrigger("tooltip.anchor.cursor.right", function(self, frame, parent, offsetX, offsetY)
    frame:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", tonumber(offsetX) or 36, tonumber(offsetY) or -12)
end)

LibEvent:attachTrigger("tooltip.anchor.static", function(self, frame, parent, offsetX, offsetY, anchorPoint)
    local anchor = select(2, frame:GetPoint())
    if (anchor == UIParent or anchor == GameTooltipDefaultContainer) then
        frame:ClearAllPoints()
        frame:SetPoint(anchorPoint or "BOTTOMRIGHT", UIParent, anchorPoint or "BOTTOMRIGHT", tonumber(offsetX) or (-CONTAINER_OFFSET_X-13), tonumber(offsetY) or CONTAINER_OFFSET_Y)
    end
end)

LibEvent:attachTrigger("tooltip.anchor.none", function(self, frame, parent)
    frame:SetOwner(parent, "ANCHOR_NONE")
    frame:Hide()
end)



LibEvent:attachTrigger("tooltip.statusbar.height", function(self, height)
    GameTooltipStatusBar:SetHeight(height or 12)
end)

LibEvent:attachTrigger("tooltip.statusbar.text", function(self, boolean)
    GameTooltipStatusBar.forceHideText = not boolean
end)

LibEvent:attachTrigger("tooltip.statusbar.font", function(self, font, size, flag)
    if (not GameTooltipStatusBar.TextString) then return end
    local origFont, origSize, origFlag = GameTooltipStatusBar.TextString:GetFont()
    font = addon:GetFont(font, NumberFontNormal:GetFont())
    if (flag == "default") then flag = "THINOUTLINE" end
    flag = addon:NormalizeFontFlag(flag, "THINOUTLINE")
    if (font ~= origFont or size ~= origSize or flag ~= origFlag) then
        GameTooltipStatusBar.TextString:SetFont(font or origFont, size or origSize, flag or origFlag)
    end
end)

LibEvent:attachTrigger("tooltip.statusbar.texture", function(self, bgvalue)
    GameTooltipStatusBar:SetStatusBarTexture(addon:GetBarFile(bgvalue))
end)

LibEvent:attachTrigger("tooltip.statusbar.position", function(self, position, offsetX, offsetY)
    LibEvent:trigger("tooltip.style.init", GameTooltip)
    GameTooltip.__RTStyle:ClearAllPoints()
    GameTooltipStatusBar:ClearAllPoints()
    local backdrop = GameTooltip.__RTStyle:GetBackdrop()
    if (not GameTooltipStatusBar:IsShown()) then position = "" end
    if (position == "bottom") then
        local offset = backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border" and 5 or backdrop.edgeSize + 1
        if (not offsetX or offsetX == 0) then offsetX = offset end
        if (not offsetY or offsetY == 0) then offsetY = -offset end
        GameTooltipStatusBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", offsetX, 2)
        GameTooltipStatusBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -offsetX, 2)
        GameTooltip.__RTStyle:SetPoint("TOPLEFT")
        GameTooltip.__RTStyle:SetPoint("BOTTOMRIGHT", GameTooltipStatusBar, "BOTTOMRIGHT", offsetX, offsetY)
    elseif (position == "top") then
        local offset = backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border" and 4 or backdrop.edgeSize
        if (not offsetX or offsetX == 0) then offsetX = offset end
        if (not offsetY or offsetY == 0) then offsetY = offset end
        GameTooltipStatusBar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", offsetX, -4)
        GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", -offsetX, -4)
        GameTooltip.__RTStyle:SetPoint("TOPLEFT", GameTooltipStatusBar, "TOPLEFT", -offsetX, offsetY)
        GameTooltip.__RTStyle:SetPoint("BOTTOMRIGHT")
    else
        local offset = backdrop.edgeFile == "Interface\\Tooltips\\UI-Tooltip-Border" and 2 or 0
        GameTooltipStatusBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", offset, -1)
        GameTooltipStatusBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -offset, -1)
        GameTooltip.__RTStyle:SetAllPoints()
    end
end)



-- Midnight: Blizzard can apply backdrop styles on nested tooltip frames (notably GameTooltip.ItemTooltip)
-- after our initial skinning. If we only match the root tooltip, spell tooltips can "revert" while
-- item/unit tooltips appear fine. Treat a tooltip as managed if it is in our set OR its parent is.
local function LooksLikeBlizzardSpellTooltip(t)
    local n = t and t.GetName and t:GetName()
    if (type(n) ~= "string") then return false end
    if (n == "SpellBookTooltip") then return true end
    if (n:find("PlayerSpells") and n:find("Tooltip")) then return true end
    if (n:find("Spell") and n:find("Tooltip")) then return true end
    return false
end

local function IsManagedTooltipFrame(tip)
    if (not tip or not addon.tooltipSet) then return false end
    if (tip.IsForbidden and tip:IsForbidden()) then return false end
    if (addon.tooltipSet[tip]) then return true end
    local p = tip.GetParent and tip:GetParent()
    if (p and addon.tooltipSet[p]) then return true end
    if (LooksLikeBlizzardSpellTooltip(tip)) then return true end
    if (p and LooksLikeBlizzardSpellTooltip(p)) then return true end
    return false
end

function addon:ForEachVisibleManagedTooltip(callback)
    if (type(callback) ~= "function" or type(self.tooltips) ~= "table") then
        return 0
    end

    local seen = {}
    local count = 0
    for _, tip in pairs(self.tooltips) do
        if (tip and not seen[tip] and IsManagedTooltipFrame(tip) and tip.IsShown and tip:IsShown()) then
            seen[tip] = true
            count = count + 1
            callback(tip, count)
        end
    end
    return count
end

function addon:RefreshManagedTooltipsMatching(matchFunc, reason)
    local refreshed = 0
    self:ForEachVisibleManagedTooltip(function(tip)
        local context = self:GetPrimaryTooltipContext(tip)
        local matches = true
        if (type(matchFunc) == "function") then
            matches = matchFunc(tip, context) and true or false
        end
        if (matches and self:RefreshTooltipSafe(tip, reason)) then
            refreshed = refreshed + 1
        end
    end)
    return refreshed
end

if (SharedTooltip_SetBackdropStyle) then
    hooksecurefunc("SharedTooltip_SetBackdropStyle", function(self, style, embedded)
        if (IsManagedTooltipFrame(self)) then
            addon:ApplyGeneralStyleToTooltip(self)
        end
    end)
end

if (GameTooltip_SetBackdropStyle) then
    hooksecurefunc("GameTooltip_SetBackdropStyle", function(self, style)
        if (IsManagedTooltipFrame(self)) then
            addon:ApplyGeneralStyleToTooltip(self)
        end
    end)
end

LibEvent:attachTrigger("ROTHTOOLTIP_GENERAL_INIT", function(self)
    LibEvent:trigger("tooltip.style.font.header", GameTooltip, addon.db.general.headerFont, addon.db.general.headerFontSize, addon.db.general.headerFontFlag)
    LibEvent:trigger("tooltip.style.font.body", GameTooltip, addon.db.general.bodyFont, addon.db.general.bodyFontSize, addon.db.general.bodyFontFlag)
    LibEvent:trigger("tooltip.statusbar.height", addon.db.general.statusbarHeight)
    LibEvent:trigger("tooltip.statusbar.text", addon.db.general.statusbarText)
    LibEvent:trigger("tooltip.statusbar.font", addon.db.general.statusbarFont, addon.db.general.statusbarFontSize, addon.db.general.statusbarFontFlag)
    LibEvent:trigger("tooltip.statusbar.texture", addon.db.general.statusbarTexture)
    for _, tip in pairs(addon.tooltips) do
        LibEvent:trigger("tooltip.style.init", tip)
        LibEvent:trigger("tooltip.scale", tip, addon.db.general.scale)
        LibEvent:trigger("tooltip.style.mask", tip, addon.db.general.mask)
        LibEvent:trigger("tooltip.style.bgfile", tip, addon.db.general.bgfile)
        LibEvent:trigger("tooltip.style.border.corner", tip, addon.db.general.borderCorner)
        LibEvent:trigger("tooltip.style.border.size", tip, addon.db.general.borderSize)
        LibEvent:trigger("tooltip.style.border.color", tip, unpack(addon.db.general.borderColor))
        LibEvent:trigger("tooltip.style.background", tip, unpack(addon.db.general.background))
    end
end)

-- Re-apply the current skin whenever a tooltip is shown.
-- This keeps a consistent look for items/spells/units even if Blizzard
-- re-applies a default tooltip layout.
LibEvent:attachTrigger("tooltip:show", function(self, tip)
    addon:ApplyGeneralStyleToTooltip(tip)
end)

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(self, parent)
    LibEvent:trigger("tooltip:anchor", self, parent)
end)


-- tooltip:init
-- tooltip:anchor
-- tooltip:show
-- tooltip:hide
-- tooltip:unit
-- tooltip:item
-- tooltip:spell
--x tooltip:quest
--x tooltip:cleared
