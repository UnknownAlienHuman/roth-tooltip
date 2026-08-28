-- Roth Tooltip - Mount source enrichment
--
-- Mount journal data is cached outside tooltip callbacks. Aura callbacks read
-- only the ordinary spell ID copied into RothTooltip's sanitized context; raw
-- AuraData and tooltip args are never inspected.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

local mounts = {}
local mountScanTicker
local lastMountByTooltip = setmetatable({}, { __mode = "k" })

local function CanAccess(value)
    return not addon.CanAccessValue or addon:CanAccessValue(value)
end

local function Call(fn, ...)
    if not CanAccess(fn) or type(fn) ~= "function" then return nil end
    if addon.CanAccessAllValues and not addon:CanAccessAllValues(...) then return nil end

    local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 = pcall(fn, ...)
    if not ok then return nil end
    if not CanAccess(a1) then a1 = nil end
    if not CanAccess(a2) then a2 = nil end
    if not CanAccess(a3) then a3 = nil end
    if not CanAccess(a4) then a4 = nil end
    if not CanAccess(a5) then a5 = nil end
    if not CanAccess(a6) then a6 = nil end
    if not CanAccess(a7) then a7 = nil end
    if not CanAccess(a8) then a8 = nil end
    if not CanAccess(a9) then a9 = nil end
    if not CanAccess(a10) then a10 = nil end
    if not CanAccess(a11) then a11 = nil end
    if not CanAccess(a12) then a12 = nil end
    return a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12
end

local function EscapePattern(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("(%W)", "%%%1"))
end

local function GetAllMountSources()
    if not C_MountJournal or type(C_MountJournal.GetMountIDs) ~= "function" then return false end

    wipe(mounts)
    local mountIDs = Call(C_MountJournal.GetMountIDs)
    if type(mountIDs) ~= "table" then return false end

    for _, mountID in ipairs(mountIDs) do
        if CanAccess(mountID) and type(mountID) == "number" then
            local _, spellID, _, _, _, _, _, _, _, _, isCollected = Call(C_MountJournal.GetMountInfoByID, mountID)
            local _, _, source = Call(C_MountJournal.GetMountInfoExtraByID, mountID)

            if type(spellID) == "number" and type(source) == "string" and source ~= "" then
                mounts[spellID] = {
                    source = source,
                    isCollected = isCollected == true,
                }
            end
        end
    end

    return next(mounts) ~= nil
end

local function StopMountScanTicker()
    if not mountScanTicker then return end
    local ticker = mountScanTicker
    mountScanTicker = nil
    local cancel = addon:SafeGet(ticker, "Cancel")
    if type(cancel) == "function" then pcall(cancel, ticker) end
end

local function ScheduleMountScan()
    if GetAllMountSources() then
        StopMountScanTicker()
        return
    end

    StopMountScanTicker()
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end

    local attempts = 0
    mountScanTicker = C_Timer.NewTicker(2, function()
        attempts = attempts + 1
        if GetAllMountSources() or attempts >= 5 then StopMountScanTicker() end
    end)
end

local function ResolveMountSpellID(tip, suppliedContext)
    local context = suppliedContext
    if not CanAccess(context) or type(context) ~= "table" then
        context = addon:GetPrimaryTooltipContext(tip)
    end
    if type(context) ~= "table" then return nil end

    local spellID = context.spellID
    if not CanAccess(spellID) or type(spellID) ~= "number" then return nil end
    return spellID
end

local function AddMountSource(tip, sourceInfo)
    if not addon:IsTooltipSafe(tip) or type(sourceInfo) ~= "table" then return end
    local source = sourceInfo.source
    if type(source) ~= "string" or source == "" then return end

    local sourcePattern = "^" .. EscapePattern(source) .. "$"
    local collectedPattern = "^" .. EscapePattern(source) .. ".+" .. EscapePattern(COLLECTED or "Collected") .. "$"
    if addon:FindLine(tip, sourcePattern) or addon:FindLine(tip, collectedPattern) then return end

    addon:SafeMethod(tip, "AddLine", " ")
    if sourceInfo.isCollected == true then
        addon:SafeMethod(tip, "AddDoubleLine", source, COLLECTED or "Collected", 1, 1, 1, 0.1, 1, 0.1)
    else
        addon:SafeMethod(tip, "AddLine", source, 1, 1, 1)
    end
end

local function OnTooltipAura(_, tip, _, _, context)
    if addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Mount") then return end
    if not addon:IsTooltipSafe(tip) then return end
    if addon.AllowTrigger and not addon:AllowTrigger("aura", tip) then return end

    local started
    if addon.MM and addon.MM.OnCallStart then
        started = addon.MM:OnCallStart("Mount", "tooltip:aura")
    end

    local spellID = ResolveMountSpellID(tip, context)
    local sourceInfo = type(spellID) == "number" and mounts[spellID] or nil
    if sourceInfo and lastMountByTooltip[tip] ~= spellID then
        AddMountSource(tip, sourceInfo)
        lastMountByTooltip[tip] = spellID
    end

    if addon.MM and addon.MM.OnCallEnd then addon.MM:OnCallEnd("Mount", started) end
end

local function ClearTooltipState(_, tip)
    if CanAccess(tip) and tip ~= nil then lastMountByTooltip[tip] = nil end
end

local M = {}

function M:Init()
    self.cbLogin = ScheduleMountScan
    self.cbRefreshMounts = ScheduleMountScan
    self.cbAura = OnTooltipAura
    self.cbClear = ClearTooltipState
end

function M:Enable()
    if addon.MM and addon.MM.AttachEvent then
        if IsLoggedIn and IsLoggedIn() then
            self.cbLogin()
        else
            addon.MM:AttachEvent("Mount", "PLAYER_LOGIN", self.cbLogin, "PLAYER_LOGIN")
        end
        addon.MM:AttachEvent("Mount", "NEW_MOUNT_ADDED", self.cbRefreshMounts, "NEW_MOUNT_ADDED")
        addon.MM:AttachEvent("Mount", "MOUNT_JOURNAL_SEARCH_UPDATED", self.cbRefreshMounts, "MOUNT_JOURNAL_SEARCH_UPDATED")
    else
        LibEvent:attachEvent("PLAYER_LOGIN", self.cbLogin)
        LibEvent:attachEvent("NEW_MOUNT_ADDED", self.cbRefreshMounts)
        LibEvent:attachEvent("MOUNT_JOURNAL_SEARCH_UPDATED", self.cbRefreshMounts)
    end

    if addon.MM and addon.MM.AttachTrigger then
        addon.MM:AttachTrigger("Mount", "tooltip:aura", self.cbAura, "tooltip:aura")
        addon.MM:AttachTrigger("Mount", "tooltip:cleared, tooltip:hide", self.cbClear, "tooltip:cleared/hide")
    else
        LibEvent:attachTrigger("tooltip:aura", self.cbAura)
        LibEvent:attachTrigger("tooltip:cleared", self.cbClear)
        LibEvent:attachTrigger("tooltip:hide", self.cbClear)
    end
end

function M:Disable()
    StopMountScanTicker()
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if addon.MM and addon.MM.RegisterModule then
    addon.MM:RegisterModule("Mount", M)
end
