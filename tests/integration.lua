-- Full TOC Lua bootstrap and focused owner/async/persistence regressions.
-- XML includes are traversed; native template construction/rendering is not emulated.
local test = dofile("tests/runtime.lua")
local Check, Load, secret = test.Check, test.Load, test.secret
local function FullSetup(account, character, locale)
    local hooks = test.Globals()
    RothTooltip = nil
    test.Setup()
    local state = { guid = "Creature-0-0-0-0-123-1", requests = 0, clears = 0,
        timers = {}, frames = {}, restrictions = false, isPlayer = true, ilvl = 500 }
    local function Frame(kind, name, parent, template)
        local f = test.Visual(parent)
        f.name, f.kind, f.points, f.events, f.primary, f.lines = name, kind, {}, {}, {}, {}
        function f:SetScript(event, callback) self.primary[event] = callback end
        function f:Fire(event, ...)
            if self.primary[event] then self.primary[event](self, ...) end
            for _, callback in ipairs(self.scripts[event] or {}) do callback(self, ...) end
        end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        function f:GetName() return self.name end
        function f:GetParent() return self.parent end
        function f:SetPoint(...) self.points = { ... } end
        function f:GetPoint() return unpack(self.points) end
        function f:SetAllPoints(relative) self.points = { "TOPLEFT", relative or self.parent } end
        function f:GetEffectiveScale() return self.scale or 1 end
        function f:SetScale(scale) self.scale = scale end
        function f:SetSize(w, h) self.width, self.height = w, h end
        function f:SetWidth(w) self.width = w end
        function f:SetHeight(h) self.height = h end
        function f:GetWidth() return self.width or 200 end
        function f:GetHeight() return self.height or 100 end
        function f:SetText(value) self.text = value end
        function f:GetText() return self.text end
        function f:SetFormattedText(format, ...) self.text = string.format(format, ...) end
        function f:SetFacing(value) self.facing = value end
        function f:GetFacing() return self.facing or 0 end
        function f:SetUnit(unit) self.unit = unit; self.setUnits = (self.setUnits or 0) + 1; return true end
        function f:ClearModel() self.unit = nil end
        function f:CreateFontString() return Frame("FontString", nil, self) end
        function f:CreateTexture() return Frame("Texture", nil, self) end
        function f:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
        function f:GetOwner() return self.owner end
        function f:GetAnchorType() return self.anchor end
        function f:GetPrimaryTooltipData() return self.data end
        function f:GetPrimaryTooltipInfo() return self.info end
        function f:NumLines() return #self.lines end
        function f:AddLine(text)
            local left, right = Frame("FontString"), Frame("FontString")
            left:SetText(text)
            self.lines[#self.lines + 1] = { left, right }
            if self.name then
                _G[self.name .. "TextLeft" .. #self.lines] = left
                _G[self.name .. "TextRight" .. #self.lines] = right
            end
        end
        function f:AddDoubleLine(left, right) self:AddLine(left); self.lines[#self.lines][2]:SetText(right) end
        function f:SetMockData(data, getter)
            self:Fire("OnTooltipCleared")
            self.data, self.info, self.lines = data, { getterName = getter or "GetUnit" }, {}
            for index, line in ipairs(data.lines or {}) do
                self:AddDoubleLine(line.leftText, line.rightText)
                line.lineIndex = index
            end
        end
        function f:GetMinMaxValues() return 0, 100 end
        function f:GetValue() return 75 end
        function f:IsObjectType(objectType) return self.kind == objectType end
        for _, method in ipairs({ "SetFont", "SetShadowOffset", "SetShadowColor", "SetTextColor", "SetClampedToScreen",
            "SetFrameStrata", "SetStatusBarColor", "SetStatusBarTexture", "SetMovable", "EnableMouse", "RegisterForDrag",
            "SetMaxLetters", "SetAutoFocus", "SetMultiLine", "SetFontObject", "HighlightText", "SetFocus", "ClearFocus",
            "StartMoving", "StopMovingOrSizing", "SetScrollChild", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
            "SetColorTexture" }) do
            f[method] = function() end
        end
        if template == "RothTooltipVariablesTemplate" then
            f.textarea = { text = Frame("EditBox") }
            f.export, f.import, f.reset = Frame("Button"), Frame("Button"), Frame("Button")
        end
        state.frames[#state.frames + 1] = f
        if name then _G[name] = f end
        return f
    end
    CreateFrame = Frame
    UIParent = Frame("Frame", "UIParent")
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        Frame("GameTooltip", name, UIParent)
    end
    for _, name in ipairs({ "GameTooltipHeaderText", "GameTooltipText", "NumberFontNormal", "Tooltip_Small" }) do
        Frame("FontString", name, UIParent)
    end
    GameTooltipStatusBar = Frame("StatusBar", "GameTooltipStatusBar", GameTooltip)
    GameTooltipDefaultContainer = UIParent
    CONTAINER_OFFSET_X, CONTAINER_OFFSET_Y = 20, 20
    LEVEL, PVP, TARGET, DEAD, OFFLINE, PLAYER, BOSS, ELITE = "Level", "PvP", "Target", "Dead", "Offline", "Player", "Boss", "Elite"
    Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2, UnitAura = 7, Macro = 25, Flyout = 22, PetAction = 11, Quest = 23 }
    Enum.TooltipDataLineType = { None = 0, UnitName = 2, UnitLevel = 47, UnitType = 48, QuestObjective = 8 }
    GetLocale = function() return locale or "enUS" end
    GetCursorPosition = function() return 300, 400 end
    GetScreenWidth, GetScreenHeight = function() return 1920 end, function() return 1080 end
    IsLoggedIn, IsInGroup, IsInRaid = function() return false end, function() return false end, function() return false end
    C_PvP = { IsArena = function() return false end }
    UnitGUID = function(unit) return unit == "player" and "Player-1-1" or state.guid end
    UnitTokenFromGUID = function(guid)
        if guid == "Player-1-1" then return "player" end
        if guid == state.guid then return "target" end
    end
    UnitName = function(unit) return unit == "player" and "Self" or "Unit", "Realm" end
    UnitClass = function() return "Warrior", "WARRIOR" end
    UnitLevel, UnitEffectiveLevel = function() return 90 end, function() return 90 end
    UnitFactionGroup = function() return "Alliance", "Alliance" end
    UnitClassification = function() return "normal" end
    UnitReaction = function() return 5 end
    UnitIsPlayer = function() return state.isPlayer end
    UnitIsUnit = function(a, b) return a == b end
    UnitExists = function() return true end
    UnitGroupRolesAssigned = function() return "NONE" end
    UnitIsConnected = function() return false end
    UnitHealthMax, UnitHealth = function() return 100 end, function() return 75 end
    UnitIsDeadOrGhost, UnitIsAFK, UnitIsDND = function() return false end, function() return false end, function() return false end
    UnitPVPName, UnitSex = function() return "Unit" end, function() return 2 end
    UnitRace, UnitCreatureType = function() return "Human", "Human" end, function() return "Humanoid" end
    GetGuildInfo = function() return "Guild", "Rank", 1, "Realm" end
    GetClassColor = function() return 1, 0.5, 0 end
    GetCreatureDifficultyColor = function() return { r = 1, g = 1, b = 0 } end
    C_Secrets = { CanCompareUnitTokens = function() return true end }
    for _, key in ipairs({ "HasSecretRestrictions", "ShouldAurasBeSecret", "ShouldCooldownsBeSecret", "ShouldSpellAuraBeSecret",
        "ShouldUnitStatsBeSecret", "ShouldUnitIdentityBeSecret", "ShouldUnitHealthBeSecret", "ShouldUnitHealthMaxBeSecret" }) do
        C_Secrets[key] = function() return state.restrictions end
    end
    CanInspect = function() return true end
    NotifyInspect = function(unit)
        state.requests = state.requests + 1
        for _, callback in ipairs(hooks.NotifyInspect or {}) do callback(unit) end
    end
    ClearInspectPlayer = function()
        state.clears = state.clears + 1
        for _, callback in ipairs(hooks.ClearInspectPlayer or {}) do callback() end
    end
    InspectFrame, PlayerSpellsFrame = nil, nil
    GetInspectSpecialization = function() return nil end
    C_PaperDollInfo = { GetInspectItemLevel = function() return state.ilvl end }
    C_PlayerInfo, C_ChallengeMode = {}, {}
    GetNumSavedInstances = function() return 0 end
    C_Item = {
        GetItemInfoInstant = function(value) return tonumber(tostring(value):match("item:(%d+)")) or tonumber(value), nil, nil, nil, 123 end,
        GetItemInfo = function() return "Item", "item:42", 2, 1, 1, nil, nil, 20, nil, 123, nil, nil, nil, nil, state.itemExpansionID or 10 end,
        GetItemQualityColor = function() return 0, 1, 0 end,
    }
    C_Spell = { GetSpellTexture = function() return 123 end }
    C_MountJournal = { GetMountIDs = function() return {} end }
    EXPANSION_NAME0, EXPANSION_NAME10 = "Classic", "Expansion"
    AbbreviateLargeNumbers = tostring
    local function NewTimer(kind, interval, callback)
        local timer = { kind = kind, interval = interval, callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        state.timers[#state.timers + 1] = timer
        return timer
    end
    C_Timer = {
        NewTicker = function(interval, callback) return NewTimer("ticker", interval, callback) end,
        NewTimer = function(interval, callback) return NewTimer("timer", interval, callback) end,
    }
    local pre, post = {}, {}
    TooltipDataProcessor = { AllTypes = "ALL",
        AddTooltipPreCall = function(kind, fn) assert(kind == "ALL"); pre[#pre + 1] = fn end,
        AddTooltipPostCall = function(kind, fn) assert(kind == "ALL"); post[#post + 1] = fn end }
    local categories, settings = test.MockSettings()
    local addon, loaded = {}, {}
    RothTooltipDB, RothTooltipCharacterDB = nil, nil
    local function LoadPath(path)
        path = path:gsub("\\", "/")
        assert(not loaded[path], "duplicate file: " .. path); loaded[path] = true
        if path:match("%.lua$") then Load(path, addon)
        elseif path:match("%.xml$") then
            local file = assert(io.open(path)); local xml = file:read("*a"); file:close()
            for relative in xml:gmatch('<[SI][cn][rc][il][pu][td]e?%s+file="([^"]+)"') do
                LoadPath((path:match("^(.*/)") or "") .. relative)
            end
        end
    end
    for path in io.lines("RothTooltip.toc") do
        if path ~= "" and not path:match("^#") then LoadPath(path) end
    end
    assert(loaded["locales/enUS.lua"] and loaded["Options.lua"])
    RothTooltipDB, RothTooltipCharacterDB = account, character
    addon.LibEvent:event("ADDON_LOADED", "RothTooltip")
    state.addon, state.pre, state.post, state.hooks, state.categories, state.settings =
        addon, pre, post, hooks, categories, settings
    function state:Display(data, getter)
        GameTooltip:SetMockData(data, getter)
        for _, fn in ipairs(pre) do if fn(GameTooltip, data) then return false end end
        for _, fn in ipairs(post) do fn(GameTooltip, data) end
        GameTooltip:Show()
        return true
    end
    function state:UnitData()
        return { type = 2, guid = self.guid, lines = {
            { type = 2, leftText = "Unit", rightText = "old right" },
            { type = 8, leftText = "Quest: 1/3", rightText = "keep" },
            { type = 47, leftText = "Level 90", rightText = "old level right" },
            { type = 48, leftText = "Humanoid", rightText = "old type right" },
        } }
    end
    function state:NoErrors()
        local report = addon:DoctorExportText()
        assert(report == "RothTooltip Doctor Report\nTime\tKind\tWhere\tError", report)
    end
    return state
end

Check("full TOC Lua bootstrap selects saved profiles and enables all twelve modules", function()
    local s = FullSetup()
    assert(s.addon.__RT_VariablesLoaded and #s.categories == 10)
    local count = 0
    for name in pairs(s.addon.MM.modules) do assert(s.addon.MM:IsEnabled(name), name); count = count + 1 end
    assert(count == 12 and LibStub == nil)
    s:NoErrors()
end)
Check("full bootstrap repairs malformed saved sections and preserves false", function()
    local s = FullSetup({ general = false, item = { showItemIcon = false }, modules = { Model = false } }, "bad")
    assert(s.addon.db.general.scale == 1 and s.addon.db.item.showItemIcon == false)
    assert(not s.addon.MM:IsEnabled("Model")); s:NoErrors()
end)
Check("newer saved schema is preserved without partially enabling the addon", function()
    local original = { version = 999, general = { scale = 1.2 } }
    local s = FullSetup(original)
    assert(RothTooltipDB == original and not s.addon.__RT_VariablesLoaded)
    assert(not s.addon.MM:IsEnabled("Unit"))
end)
Check("all supported locales complete the full Lua bootstrap", function()
    for _, locale in ipairs({ "enUS", "ruRU", "zhCN", "zhTW" }) do local s = FullSetup(nil, nil, locale); s:NoErrors() end
end)
Check("account and character mutable defaults never alias", function()
    local s = FullSetup()
    assert(s.addon:SelectSavedVariableScope(true))
    s.addon.db.general.background[1] = 0.45
    s.addon.db.unit.player.elements[1][1] = "name"
    assert(RothTooltipDB.general.background[1] == 0)
    assert(s.addon.__RT_DefaultDB.general.background[1] == 0)
    assert(RothTooltipDB.unit.player.elements[1][1] == "friendIcon")
    assert(s.addon:SelectSavedVariableScope(false)); s:NoErrors()
end)
Check("invalid imports are atomic and bounded", function()
    local s = FullSetup(); local original = s.addon.db
    local bad = { { general = { scale = 99 } }, { version = 99 }, { unknown = true }, { general = { scale = 0/0 } },
        { unit = { player = { elements = { name = { wildcard = "%999999999s" } } } } }, { general = { combatPolicy = "UNSAFE" } } }
    local cyclic = {}; cyclic.general = cyclic; bad[#bad + 1] = cyclic
    for _, candidate in ipairs(bad) do assert(not s.addon:ImportProfile(candidate)); assert(s.addon.db == original) end
    s:NoErrors()
end)
Check("valid JSON-style layout keys normalize without duplicate element ownership", function()
    local s = FullSetup()
    assert(s.addon:ImportProfile({ version = 3.2, general = { scale = 1.25 }, unit = { player = {
        elements = { ["1"] = { "name", "realm" }, ["2"] = { "levelValue" } } } } }))
    assert(s.addon.db.unit.player.elements[1][1] == "name" and s.addon.db.general.scale == 1.25)
    assert(not s.addon:ImportProfile({ unit = { player = { elements = { { "name", "name" } } } } }))
    s:NoErrors()
end)
Check("profile changes cannot structurally apply during combat", function()
    local s = FullSetup(); local original = s.addon.db
    InCombatLockdown = function() return true end
    assert(not s.addon:ImportProfile({}) and not s.addon:SelectSavedVariableScope(true))
    assert(not s.addon:ReapplyActiveProfile() and s.addon.db == original)
    s:NoErrors()
end)
Check("processor initialization is session-idempotent across profiles and toggles", function()
    local s = FullSetup()
    for _ = 1, 10 do s.addon:InitTooltipDataProcessor(); s.addon:ReapplyActiveProfile() end
    assert(#s.pre == 1 and #s.post == 1); s:NoErrors()
end)
Check("tooltip context is fresh and borrowed data is never retained", function()
    local s = FullSetup()
    GameTooltip:SetMockData({ type = 1, id = 20 })
    assert(s.addon:GetPrimaryTooltipContext(GameTooltip).spellID == 20)
    GameTooltip:SetMockData({ type = 0, id = 42, hyperlink = "item:42" }, "GetBagItem")
    local current = s.addon:GetPrimaryTooltipContext(GameTooltip)
    assert(current.itemID == 42 and not current.spellID and not current.dataInstanceID)
    assert(s.addon.__RT_ContextByTooltip == nil and s.addon.tooltips == nil); s:NoErrors()
end)
Check("inaccessible identities have no alternate GetUnit/GetSpell fallback", function()
    local s = FullSetup()
    GameTooltip.GetUnit = function() error("unsafe fallback") end
    GameTooltip.GetSpell = GameTooltip.GetUnit
    GameTooltip:SetMockData({ type = 2, guid = secret })
    assert(s.addon:GetPrimaryTooltipContext(GameTooltip) == nil)
    assert(s.addon:GetTooltipUnit(GameTooltip) == nil and s.addon:SafeGetSpellID(GameTooltip) == nil)
    assert(s.addon:GetPrimaryTooltipContext(GameTooltip, secret) == nil); s:NoErrors()
end)
Check("unit resolver refuses mismatched current identity", function()
    local s = FullSetup()
    UnitTokenFromGUID = function() return "target" end
    assert(s.addon:ResolveUnitToken("target", "different-guid") == nil)
    assert(s.addon:ResolveUnitToken("target", secret) == nil); s:NoErrors()
end)
Check("macro item content wins over spell content and unrelated IDs are not spells", function()
    local s = FullSetup()
    local context = s.addon:GetPrimaryTooltipContext(GameTooltip, { type = 25, id = 99, hyperlink = "item:42", spellID = 123 })
    assert(context.itemID == 42 and context.spellID == nil)
    context = s.addon:GetPrimaryTooltipContext(GameTooltip, { type = 25, id = 99 })
    assert(context.spellID == nil); s:NoErrors()
end)
Check("denied aura context is not delivered through a generic ID route", function()
    local s = FullSetup(); s.restrictions = true
    assert(s.addon:GetPrimaryTooltipContext(GameTooltip, { type = 7, id = 123 }) == nil)
    s:NoErrors()
end)
Check("visibility suppression runs before native Show; inaccessible data is not consumed", function()
    local s = FullSetup(); s.addon.db.general.visibility.inCombat = "hide"
    InCombatLockdown = function() return true end
    assert(not s:Display({ type = 1, id = 123 }))
    assert(s.pre[1](GameTooltip, secret) == nil); s:NoErrors()
end)
Check("refresh preserves source type and does not replay bag or inventory data", function()
    local s = FullSetup()
    for _, getter in ipairs({ "GetBagItem", "GetInventoryItem", "GetAction" }) do
        GameTooltip:SetMockData({ type = 0, id = 42, hyperlink = "item:42" }, getter)
        assert(not s.addon:RefreshTooltipSafe(GameTooltip))
    end
    local count = 0; GameTooltip.SetHyperlink = function(_, link) assert(link == "item:42"); count = count + 1; return true end
    GameTooltip:SetMockData({ type = 0, id = 42, hyperlink = "item:42" }, "GetHyperlink")
    assert(s.addon:RefreshTooltipSafe(GameTooltip) and count == 1); s:NoErrors()
end)
Check("modifier changes have one refresh owner", function()
    local s = FullSetup(); GameTooltip:SetMockData(s:UnitData())
    s.addon.LibEvent:event("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    assert(GameTooltip.setUnits == 1); s:NoErrors()
end)
Check("unit layout changes semantic rows and preserves quest and right-column content", function()
    local s = FullSetup(); s:Display(s:UnitData())
    assert(GameTooltip.lines[2][1].text == "Quest: 1/3" and GameTooltip.lines[2][2].text == "keep")
    assert(GameTooltip.lines[1][2].text == nil and GameTooltip.lines[3][2].text == nil)
    assert(GameTooltip.lines[4][1].text == nil and GameTooltip.lines[4][2].text == nil)
    s:NoErrors()
end)
Check("offline boolean survives ordinary unit normalization", function()
    local s = FullSetup(); local info = s.addon:GetUnitInfo("target", s.addon.db.unit.player.elements)
    assert(info.statusDC == OFFLINE); s:NoErrors()
end)
Check("model is independent of tooltip geometry and applies current dimensions", function()
    local s = FullSetup(); s.addon.db.model.width = 160
    s:Display(s:UnitData())
    local model
    for _, f in ipairs(s.frames) do if f.kind == "PlayerModel" then model = f end end
    assert(model and model.parent == UIParent and model.points[2] == UIParent and model.width == 160)
    s.addon.LibEvent:event("ADDON_RESTRICTION_STATE_CHANGED")
    assert(not model:IsShown() and model.unit == nil); s:NoErrors()
end)
Check("inspect timeout and disable never clear the global inspect channel", function()
    local s = FullSetup(); s:Display(s:UnitData()); assert(s.requests == 1)
    test.SetClock(6); s:Display(s:UnitData()); assert(s.requests == 2)
    s.addon:DisableModule("Unit"); assert(s.clears == 0); s:NoErrors()
end)
Check("external inspect supersedes pending enrichment without clearing its owner", function()
    local s = FullSetup(); s:Display(s:UnitData()); NotifyInspect("player")
    s.addon.LibEvent:event("INSPECT_READY", s.guid)
    assert(s.clears == 0 and GameTooltip.setUnits == nil)
    s:NoErrors()
end)
Check("restriction transition invalidates pending inspect results", function()
    local s = FullSetup(); s:Display(s:UnitData()); s.restrictions = true
    s.addon.LibEvent:event("ADDON_RESTRICTION_STATE_CHANGED")
    s.addon.LibEvent:event("INSPECT_READY", s.guid)
    assert(s.clears == 0 and GameTooltip.setUnits == nil); s:NoErrors()
end)
Check("inspect completion refreshes only the currently matching tooltip", function()
    local s = FullSetup(); local guid = s.guid; s:Display(s:UnitData())
    s.guid = "Creature-0-0-0-0-456-2"; GameTooltip:SetMockData(s:UnitData())
    s.addon.LibEvent:event("INSPECT_READY", guid)
    assert(GameTooltip.setUnits == nil); s:NoErrors()
end)
Check("all optional modules toggle repeatedly after a complete bootstrap", function()
    local s = FullSetup()
    for _ = 1, 20 do
        for name in pairs(s.addon.MM.modules) do
            if name ~= "General" then assert(s.addon:DisableModule(name)); assert(s.addon:EnableModule(name)) end
        end
    end
    assert(#s.pre == 1 and #s.post == 1)
    assert(#s.hooks.NotifyInspect == 1 and #s.hooks.ClearInspectPlayer == 1)
    s:NoErrors()
end)
Check("disabled inspect consumers make no background request", function()
    local s = FullSetup()
    s.addon.db.unit.player.showItemLevel, s.addon.db.unit.player.showSpecialization = false, false
    s:Display(s:UnitData()); assert(s.requests == 0); s:NoErrors()
end)
Check("profile rejects metatables, newer schemas, oversized text and invalid versions", function()
    local s = FullSetup(); local original = s.addon.db
    local bad = { { version = "future" }, { version = 0/0 }, { general = { headerFont = string.rep("x", 513) } }, secret,
        setmetatable({}, { __index = function() error("metatable executed") end }) }
    for _, value in ipairs(bad) do assert(not s.addon:ImportProfile(value)); assert(s.addon.db == original) end
    s:NoErrors()
end)
Check("cursor follow owns ANCHOR_NONE and survives native initial ClearLines", function()
    local s = FullSetup(); local config = s.addon.db.general.anchor
    config.position, config.returnInCombat, config.cx, config.cy = "cursor", false, 0, 20
    UIParent.scale, GameTooltip.scale = 2, 0.5
    GameTooltip.owner = UIParent
    s.addon.LibEvent:trigger("tooltip:anchor", GameTooltip, UIParent)
    local timer = s.timers[#s.timers]
    assert(timer and GameTooltip.anchor == "ANCHOR_NONE")
    assert(GameTooltip.points[4] == 150 and GameTooltip.points[5] == 220)
    GameTooltip:Fire("OnTooltipCleared"); assert(not timer.cancelled)
    s.addon.LibEvent:trigger("tooltip:invalidated", GameTooltip); assert(timer.cancelled)
    local clears = GameTooltip.clears; timer.callback(); assert(GameTooltip.clears == clears)
    s:NoErrors()
end)
Check("replaced cursor tick cannot cancel the new generation", function()
    local s = FullSetup(); s.addon.db.general.anchor.position = "cursor"; GameTooltip.owner = UIParent
    s.addon.LibEvent:trigger("tooltip:anchor", GameTooltip, UIParent)
    local first = s.timers[#s.timers]
    s.addon.LibEvent:trigger("tooltip:anchor", GameTooltip, UIParent)
    local second = s.timers[#s.timers]
    assert(first ~= second and first.cancelled)
    first.callback(); assert(not second.cancelled)
    s.addon:DisableModule("Anchor"); assert(second.cancelled); s:NoErrors()
end)
Check("mount retry has bounded attempts and ignores callbacks after disable", function()
    local s = FullSetup(); local scans = 0
    C_MountJournal.GetMountIDs = function() scans = scans + 1; return nil end
    s.addon.LibEvent:event("PLAYER_LOGIN")
    local timer = s.timers[#s.timers]; assert(timer)
    for _ = 1, 5 do timer.callback() end
    assert(timer.cancelled and scans == 6)
    s.addon.LibEvent:event("NEW_MOUNT_ADDED")
    timer = s.timers[#s.timers]; s.addon:DisableModule("Mount")
    scans = 0; timer.callback(); assert(scans == 0 and timer.cancelled); s:NoErrors()
end)
Check("item ID is owned once even when both ID settings are enabled", function()
    local s = FullSetup(); s.addon.db.item.showItemID = true
    local data = { type = 0, id = 42, hyperlink = "item:42", lines = { { type = 22, leftText = "Item" } } }
    s:Display(data, "GetItemByID")
    local count = 0
    for _, line in ipairs(GameTooltip.lines) do if line[1].text and line[1].text:find("^Item:") then count = count + 1 end end
    assert(count == 1); s:NoErrors()
end)
Check("refresh guard releases on failure and suppresses reentrant refresh", function()
    local s = FullSetup(); GameTooltip:SetMockData({ type = 1, id = 123 }, "GetSpellByID")
    GameTooltip.SetSpellByID = function() error("expected setter error") end
    assert(not s.addon:RefreshTooltipSafe(GameTooltip)); s.addon:DoctorClear()
    GameTooltip.SetSpellByID = function() assert(not s.addon:RefreshTooltipSafe(GameTooltip)); return true end
    assert(s.addon:RefreshTooltipSafe(GameTooltip)); s:NoErrors()
end)
Check("native item cache event is not registered by a second refresh owner", function()
    local s = FullSetup(); assert(s.addon.LibEvent.events.GET_ITEM_INFO_RECEIVED == nil); s:NoErrors()
end)
Check("completed inspect caches ordinary data without another request", function()
    local s = FullSetup(); s:Display(s:UnitData()); assert(s.requests == 1)
    s.addon.LibEvent:event("INSPECT_READY", s.guid)
    assert(GameTooltip.setUnits == 1 and s.clears == 0)
    test.SetClock(3); s:Display(s:UnitData()); assert(s.requests == 1)
    assert(s.addon:FindLine(GameTooltip, "^Item Level:")); s:NoErrors()
end)
Check("an open Inspect UI prevents background inspection", function()
    local s = FullSetup(); InspectFrame = CreateFrame("Frame"); InspectFrame:Show()
    s:Display(s:UnitData()); assert(s.requests == 0); s:NoErrors()
end)
Check("profile input ceiling is checked before JSON deserialization", function()
    local s = FullSetup(); local decodes = 0
    C_EncodingUtil = { DeserializeJSON = function() decodes = decodes + 1; return {} end }
    s.addon.Options:OpenProfileDialog()
    local dialog = s.addon.__RTVariablesDialog
    dialog.textarea.text:SetText(string.rep("x", 65537))
    dialog.import:Fire("OnClick"); assert(decodes == 0)
    s:NoErrors()
end)
Check("profile dialog rejects unknown envelopes and accepts supported legacy JSON", function()
    local s = FullSetup(); s.addon.Options:OpenProfileDialog()
    local dialog = s.addon.__RTVariablesDialog
    local original = s.addon.db
    C_EncodingUtil = { DeserializeJSON = function() return { format = "OtherAddon", encodingVersion = 1, profile = {} } end }
    dialog.textarea.text:SetText("{}"); dialog.import:Fire("OnClick"); assert(s.addon.db == original)
    C_EncodingUtil.DeserializeJSON = function() return { general = { scale = 1.75 } } end
    dialog.import:Fire("OnClick"); assert(s.addon.db.general.scale == 1.75)
    s:NoErrors()
end)
Check("unregister drops membership even when native object access was revoked", function()
    local s = FullSetup(); local tooltip = CreateFrame("GameTooltip")
    assert(s.addon:RegisterTooltipFrame(tooltip)); tooltip.inaccessible = true
    assert(s.addon:UnregisterTooltipFrame(tooltip)); assert(s.addon.tooltipSet[tooltip] == nil)
    s:NoErrors()
end)
Check("addon namespace is private and module activation order is deterministic", function()
    local s = FullSetup()
    assert(RothTooltip == nil and s.addon.G == nil and s.addon.db.variables == nil)
    assert(s.addon:ImportProfile({ version = 3.2, variables = { legacy = true } }))
    assert(s.addon.db.variables == nil)
    assert(table.concat(s.addon.MM.order, ",") ==
        "General,Anchor,Target,Unit,Model,Item,Spell,Quest,LinkID,Mount,ExpansionInfo,SkinFrames")
    s:NoErrors()
end)
Check("party zone lookup reuses and invalidates a bounded roster snapshot", function()
    local s = FullSetup(); local reads = 0
    IsInGroup = function() return true end
    GetNumGroupMembers = function() return 2 end
    GetRaidRosterInfo = function(index)
        reads = reads + 1
        if index == 1 then return "Unit-Realm", nil, nil, nil, nil, nil, "Zone A" end
        return "Other-Realm", nil, nil, nil, nil, nil, "Zone B"
    end
    assert(s.addon:GetZone("party1", "Unit", "Realm") == "Zone A")
    assert(s.addon:GetZone("party1", "Unit", "Realm") == "Zone A" and reads == 2)
    test.SetClock(3)
    assert(s.addon:GetZone("party1", "Unit", "Realm") == "Zone A" and reads == 4)
    s.addon.LibEvent:event("GROUP_ROSTER_UPDATE")
    assert(s.addon:GetZone("party1", "Unit", "Realm") == "Zone A" and reads == 6)
    s:NoErrors()
end)
Check("base expansion ID zero is rendered", function()
    local s = FullSetup()
    s.itemExpansionID = 0
    s:Display({ type = 0, id = 42, hyperlink = "item:42", lines = { { type = 22, leftText = "Item" } } },
        "GetItemByID")
    local line = s.addon:FindLine(GameTooltip, "Classic")
    assert(line ~= nil)
    s:NoErrors()
end)
Check("Settings defaults come from the canonical schema, not the active profile", function()
    local s = FullSetup({ general = { scale = 2, statusbarText = false }, modules = { Model = false } })
    assert(s.settings.ROTH_TOOLTIP_GENERAL_SCALE.default == 1)
    assert(s.settings.ROTH_TOOLTIP_GENERAL_STATUSBARTEXT.default == true)
    assert(s.settings.ROTH_TOOLTIP_GENERAL_STATUSBARFONT.default == "default")
    assert(s.settings.ROTH_TOOLTIP_GENERAL_ANCHOR_X.default == 0)
    assert(s.settings.ROTH_TOOLTIP_MODULES_MODEL.default == true)
    s:NoErrors()
end)
Check("legacy profile exceptions are exact paths, not broad leaf names", function()
    local s = FullSetup(); local original = s.addon.db
    assert(s.addon:ImportProfile({ variables = { old = true }, unit = {
        player = { showTargetBy = true }, npc = { showTargetBy = true } } }))
    assert(s.addon.db.variables == nil and s.addon.db.unit.player.showTargetBy == nil)
    local accepted = s.addon.db
    assert(not s.addon:ImportProfile({ general = { showTargetBy = true } }))
    assert(s.addon.db == accepted)
    assert(not s.addon:ImportProfile({ item = { legacyAuraFallback = true } }))
    assert(s.addon.db == accepted and s.addon.db ~= original)
    s:NoErrors()
end)
Check("live wildcard writes use the same bounded validator as imports", function()
    local s = FullSetup()
    local key = "unit.player.elements.name.wildcard"
    local original = s.addon.Options:GetVariable(key)
    assert(not s.addon.Options:SetVariable(key, "%999999s"))
    assert(s.addon.Options:GetVariable(key) == original)
    assert(s.addon.Options:SetVariable(key, "[%s]"))
    assert(s.addon.Options:GetVariable(key) == "[%s]")
    s:NoErrors()
end)
Check("temporary status text denial does not create a replacement", function()
    local s = FullSetup()
    local text = s.addon:GetStatusBarText(GameTooltipStatusBar)
    assert(text)
    local count = #s.frames
    text.inaccessible = true
    s.addon.LibEvent:event("PLAYER_REGEN_ENABLED")
    assert(#s.frames == count and s.addon:GetStatusBarText(GameTooltipStatusBar) == nil)
    text.inaccessible = false
    assert(s.addon:GetStatusBarText(GameTooltipStatusBar) == text)
    s:NoErrors()
end)
Check("inspect completion cancels its owned timeout", function()
    local s = FullSetup(); s:Display(s:UnitData())
    local timer = s.timers[#s.timers]
    assert(timer and timer.kind == "timer" and not timer.cancelled)
    s.addon.LibEvent:event("INSPECT_READY", s.guid)
    assert(timer.cancelled and GameTooltip.setUnits == 1)
    s:NoErrors()
end)
Check("inspect timeout releases the request without touching the global channel", function()
    local s = FullSetup(); s:Display(s:UnitData())
    local timer = s.timers[#s.timers]
    timer.callback()
    test.SetClock(3); s:Display(s:UnitData())
    assert(s.requests == 2 and s.clears == 0 and timer.cancelled)
    s:NoErrors()
end)
Check("stale inspect timeout cannot cancel a replacement request", function()
    local s = FullSetup(); s:Display(s:UnitData())
    local first = s.timers[#s.timers]
    test.SetClock(6); s:Display(s:UnitData())
    local second = s.timers[#s.timers]
    assert(first ~= second and first.cancelled and not second.cancelled)
    first.callback()
    assert(not second.cancelled)
    s.addon.LibEvent:event("INSPECT_READY", s.guid)
    assert(second.cancelled and GameTooltip.setUnits == 1)
    s:NoErrors()
end)
Check("direct unit normalization stops before APIs when stats are restricted", function()
    local s = FullSetup(); local calls = 0
    C_Secrets.ShouldUnitIdentityBeSecret = function() return false end
    C_Secrets.ShouldUnitStatsBeSecret = function() return true end
    UnitName = function() calls = calls + 1; return "Unsafe" end
    assert(s.addon:GetUnitInfo("target", s.addon.db.unit.player.elements) == nil and calls == 0)
    s:NoErrors()
end)
Check("profile decoder rejects inaccessible and metatable-bearing documents", function()
    local s = FullSetup(); s.addon.Options:OpenProfileDialog()
    local dialog, original = s.addon.__RTVariablesDialog, s.addon.db
    C_EncodingUtil = { DeserializeJSON = function() return secret end }
    dialog.textarea.text:SetText("{}"); dialog.import:Fire("OnClick")
    assert(s.addon.db == original)
    C_EncodingUtil.DeserializeJSON = function() return setmetatable({}, {}) end
    dialog.import:Fire("OnClick")
    assert(s.addon.db == original)
    s:NoErrors()
end)
Check("profile dialog remains single-owner across temporary access denial", function()
    local s = FullSetup(); s.addon.Options:OpenProfileDialog()
    local dialog, count = s.addon.__RTVariablesDialog, #s.frames
    dialog.inaccessible = true
    s.addon.Options:OpenProfileDialog()
    assert(#s.frames == count and s.addon.__RTVariablesDialog == dialog)
    dialog.inaccessible = false
    s.addon.Options:OpenProfileDialog()
    assert(#s.frames == count and s.addon.__RTVariablesDialog == dialog)
    s:NoErrors()
end)
Check("DIY layout stays within sixteen rows and preview remains single-owner", function()
    local s = FullSetup(); local elements = s.addon.db.unit.player.elements
    local keys = { "name", "realm", "levelValue", "className", "raceName", "guildName", "guildRank",
        "guildRealm", "factionName", "gender", "isPlayer", "role", "moveSpeed", "zone", "title", "statusAFK", "statusDND" }
    for index = #elements, 1, -1 do elements[index] = nil end
    elements[1] = { keys[1], keys[2] }
    for index = 2, 16 do elements[index] = { keys[index + 1] } end
    s.addon.Options:OpenDIYEditor()
    local preview = s.addon.Options.DIY
    local element = assert(preview.elements.name)
    element:Fire("OnDragStart")
    preview.overLine = { line = 99 }
    element:Fire("OnDragStop")
    assert(#elements == 16)
    local found = false
    for _, row in ipairs(elements) do for _, key in ipairs(row) do if key == "name" then found = true end end end
    assert(found)
    local frame, count = preview.frame, #s.frames
    frame.inaccessible = true; s.addon.Options:OpenDIYEditor()
    assert(#s.frames == count and preview.frame == frame)
    frame.inaccessible = false
    s:NoErrors()
end)
Check("DIY drag is atomic across combat entry", function()
    local s = FullSetup(); s.addon.Options:OpenDIYEditor()
    local preview, rows = s.addon.Options.DIY, s.addon.db.unit.player.elements
    local before = table.concat(rows[1], ",")
    local element = assert(preview.elements.name)
    element:Fire("OnDragStart"); preview.overLine = { line = 4 }
    InCombatLockdown = function() return true end
    element:Fire("OnDragStop")
    assert(table.concat(rows[1], ",") == before and preview.dragging == nil)
    s:NoErrors()
end)
Check("DIY stale drag cannot mutate a replacement profile", function()
    local s = FullSetup(); s.addon.Options:OpenDIYEditor()
    local preview = s.addon.Options.DIY
    local element = assert(preview.elements.name)
    element:Fire("OnDragStart")
    assert(s.addon:ImportProfile({ unit = { player = { elements = {
        ["1"] = { "name", "realm" }, ["2"] = { "levelValue" } } } } }))
    local rows = s.addon.db.unit.player.elements
    local before = table.concat(rows[1], ",") .. ";" .. table.concat(rows[2], ",")
    preview.overLine = { line = 9 }; element:Fire("OnDragStop")
    assert(table.concat(rows[1], ",") .. ";" .. table.concat(rows[2], ",") == before)
    s:NoErrors()
end)
Check("auto cursor anchor uses UIParent coordinates and follows quadrant changes", function()
    local s = FullSetup(); local cursorX, cursorY = 300, 400
    GetCursorPosition = function() return cursorX, cursorY end
    UIParent:SetSize(1000, 800); UIParent.scale = 2
    local config = s.addon.db.general.anchor
    config.position, config.returnInCombat, config.cx, config.cy = "auto", false, 0, 20
    GameTooltip.owner = UIParent
    s.addon.LibEvent:trigger("tooltip:anchor", GameTooltip, UIParent)
    local timer = s.timers[#s.timers]
    assert(GameTooltip.points[1] == "BOTTOMLEFT" and GameTooltip.points[4] == 160 and GameTooltip.points[5] == 230)
    cursorX, cursorY = 1800, 1400; timer.callback()
    assert(GameTooltip.points[1] == "TOPRIGHT" and GameTooltip.points[4] == 890 and GameTooltip.points[5] == 710)
    s:NoErrors()
end)
Check("SkinFrames releases only registry entries it actually added", function()
    local s = FullSetup()
    local existing = CreateFrame("GameTooltip")
    local ok, added = s.addon:RegisterTooltipFrame(existing)
    assert(ok and added)
    AtlasLootTooltip = existing
    s.addon.LibEvent:trigger("tooltip:variable:changed", "general.skinMoreFrames", true)
    local owned = CreateFrame("GameTooltip")
    FriendsTooltip = owned
    s.addon.LibEvent:trigger("tooltip:variable:changed", "general.skinMoreFrames", true)
    local okAgain, addedAgain = s.addon:RegisterTooltipFrame(existing)
    assert(okAgain and not addedAgain and s.addon:IsManagedTooltip(owned))
    assert(s.addon:DisableModule("SkinFrames"))
    assert(s.addon:IsManagedTooltip(existing) and not s.addon.tooltipSet[owned])
    AtlasLootTooltip, FriendsTooltip = nil, nil
    s:NoErrors()
end)
print(string.format("PASS: %d tests (%s), including complete TOC Lua bootstrap; native client NOT-RUN", test.Count(), _VERSION))
