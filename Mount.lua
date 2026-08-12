--[[
Roth Tooltip - Mount aura helpers

Adds mount source lines to aura tooltips when the aura represents a mount spell.
Ported to the Midnight engine (module wrapper + safe secret-value handling).
]]

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")
if (not addon) then return end
if (not C_MountJournal) then return end

local mounts = {}
local mountScanTicker = nil

local function IsSecret(v)
    if (addon and addon.IsSecret) then
        return addon:IsSecret(v)
    end
    if (type(issecretvalue) == "function") then
        return issecretvalue(v)
    end
    return false
end

local function EscapePattern(s)
    if (type(s) ~= "string") then return "" end
    return (s:gsub("(%W)", "%%%1"))
end

local function GetAllMountSource()
    wipe(mounts)

    local mountIDs = C_MountJournal.GetMountIDs()
    if (type(mountIDs) ~= "table") then return end

    local _, spellID, isCollected, source
    for _, mountID in ipairs(mountIDs) do
        _, spellID, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        _, _, source = C_MountJournal.GetMountInfoExtraByID(mountID)

        if (not IsSecret(spellID) and type(spellID) == "number") then
            mounts[spellID] = {
                source = (not IsSecret(source) and source) or nil,
                isCollected = (not IsSecret(isCollected) and isCollected) or nil,
            }
        end
    end

    if (next(mounts)) then return true end
end

local function StopMountScanTicker()
    if (mountScanTicker) then
        mountScanTicker:Cancel()
        mountScanTicker = nil
    end
end

local function ScheduleMountScan()
    if (GetAllMountSource()) then
        StopMountScanTicker()
        return
    end

    StopMountScanTicker()

    local attempts = 0
    mountScanTicker = C_Timer.NewTicker(2, function()
        attempts = attempts + 1
        if GetAllMountSource() or attempts >= 5 then
            StopMountScanTicker()
        end
    end)
end

local function OnPlayerLogin_Mount()
    -- Delay mount journal scan slightly after login; journal data can populate late.
    ScheduleMountScan()
end

local function OnNewMountAdded()
    ScheduleMountScan()
end

local function ResolveMountSpellID(tip, context)
    context = context or addon:GetPrimaryTooltipContext(tip)

    local spellID = context and context.spellID or nil
    if (not IsSecret(spellID) and type(spellID) == "number") then
        return spellID
    end

    return nil
end

local function OnTooltipAura_Mount(self, tip, args, aid, context)
    if (addon.MM and addon.MM.IsEnabled and not addon.MM:IsEnabled("Mount")) then return end
    if (not tip) then return end
    if (addon.AllowTrigger and not addon:AllowTrigger("aura", tip)) then return end

    local started
    if (addon.MM and addon.MM.OnCallStart) then
        started = addon.MM:OnCallStart("Mount", "tooltip:aura")
    end

    local spellID = ResolveMountSpellID(tip, context)

    if (spellID) then
        local info = mounts[spellID]
        if (info and info.source) then
            if (tip.__RT_LastMountSpellID == spellID) then
                if (addon.MM and addon.MM.OnCallEnd) then
                    addon.MM:OnCallEnd("Mount", started)
                end
                return
            end

            local hasSourceLine = addon.FindLine and addon:FindLine(tip, "^" .. EscapePattern(info.source) .. "$")
            local hasCollectedLine = addon.FindLine and addon:FindLine(tip, "^" .. EscapePattern(info.source) .. ".+" .. EscapePattern(COLLECTED) .. "$")
            if (not hasSourceLine and not hasCollectedLine) then
                tip:AddLine(" ")
                if (info.isCollected) then
                    tip:AddDoubleLine(info.source, COLLECTED, 1, 1, 1, 0.1, 1, 0.1)
                else
                    tip:AddLine(info.source, 1, 1, 1)
                end
            end
            tip.__RT_LastMountSpellID = spellID
            -- No :Show() here; Engine/Layout will resize without forcing a refresh.
        end
    end

    if (addon.MM and addon.MM.OnCallEnd) then
        addon.MM:OnCallEnd("Mount", started)
    end
end

local function OnTooltipCleared_Mount(self, tip)
    if (tip) then
        tip.__RT_LastMountSpellID = nil
    end
end

-- Module wrapper
local M = {}

function M:Init()
    self.cbLogin = OnPlayerLogin_Mount
    self.cbNewMount = OnNewMountAdded
    self.cbAura = OnTooltipAura_Mount
    self.cbCleared = OnTooltipCleared_Mount
end

function M:Enable()
    if (addon.MM and addon.MM.AttachEvent) then
        if (IsLoggedIn and IsLoggedIn()) then
            self.cbLogin()
        else
            addon.MM:AttachEvent("Mount", "PLAYER_LOGIN", self.cbLogin, "PLAYER_LOGIN")
        end
        addon.MM:AttachEvent("Mount", "NEW_MOUNT_ADDED", self.cbNewMount, "NEW_MOUNT_ADDED")
        addon.MM:AttachEvent("Mount", "MOUNT_JOURNAL_SEARCH_UPDATED", self.cbNewMount, "MOUNT_JOURNAL_SEARCH_UPDATED")
    else
        if (IsLoggedIn and IsLoggedIn()) then
            self.cbLogin()
        else
            LibEvent:attachEvent("PLAYER_LOGIN", self.cbLogin)
        end
        LibEvent:attachEvent("NEW_MOUNT_ADDED", self.cbNewMount)
        LibEvent:attachEvent("MOUNT_JOURNAL_SEARCH_UPDATED", self.cbNewMount)
    end

    if (addon.MM and addon.MM.AttachTrigger) then
        addon.MM:AttachTrigger("Mount", "tooltip:aura", self.cbAura, "tooltip:aura")
        addon.MM:AttachTrigger("Mount", "tooltip:cleared", self.cbCleared, "tooltip:cleared")
    else
        LibEvent:attachTrigger("tooltip:aura", self.cbAura)
        LibEvent:attachTrigger("tooltip:cleared", self.cbCleared)
    end
end

function M:Disable()
    StopMountScanTicker()
end
function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

if (addon.MM and addon.MM.RegisterModule) then
    addon.MM:RegisterModule("Mount", M)
end
