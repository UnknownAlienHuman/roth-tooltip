-- RothTooltip mount-source enrichment.
--
-- The mount journal is cached outside tooltip callbacks. Aura callbacks consume
-- only the ordinary spell ID from the sanitized tooltip context.

local _, addon = ...

local mounts = {}
local mountScanTicker
local lastMountByTooltip = setmetatable({}, { __mode = "k" })

local function Call(fn, ...)
    return addon:SafeCall("Mount", fn, ...)
end

local function EscapePattern(text)
    return type(text) == "string" and (text:gsub("(%W)", "%%%1")) or ""
end

local function RebuildMountCache()
    if not C_MountJournal or type(C_MountJournal.GetMountIDs) ~= "function" then return false end
    local mountIDs = Call(C_MountJournal.GetMountIDs)
    if type(mountIDs) ~= "table" then return false end

    local rebuilt = {}
    for _, mountID in ipairs(mountIDs) do
        if type(mountID) == "number" then
            local _, spellID, _, _, _, _, _, _, _, _, isCollected =
                Call(C_MountJournal.GetMountInfoByID, mountID)
            local _, _, source = Call(C_MountJournal.GetMountInfoExtraByID, mountID)
            if type(spellID) == "number" and type(source) == "string" and source ~= "" then
                rebuilt[spellID] = {
                    source = source,
                    isCollected = isCollected == true,
                }
            end
        end
    end

    mounts = rebuilt
    return true
end

local function StopMountScanTicker()
    if not mountScanTicker then return end
    local ticker = mountScanTicker
    mountScanTicker = nil
    local cancel = addon:SafeGet(ticker, "Cancel")
    if type(cancel) == "function" then pcall(cancel, ticker) end
end

local function ScheduleMountScan()
    if RebuildMountCache() then
        StopMountScanTicker()
        return
    end

    StopMountScanTicker()
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end
    local attempts = 0
    mountScanTicker = C_Timer.NewTicker(2, function()
        attempts = attempts + 1
        if RebuildMountCache() or attempts >= 5 then StopMountScanTicker() end
    end)
end

local function AddMountSource(tooltip, sourceInfo)
    if not addon:IsTooltipSafe(tooltip) or type(sourceInfo) ~= "table" then return end
    local source = sourceInfo.source
    if type(source) ~= "string" or source == "" then return end

    local sourcePattern = "^" .. EscapePattern(source) .. "$"
    local collectedPattern = "^" .. EscapePattern(source) .. ".+" .. EscapePattern(COLLECTED or "Collected") .. "$"
    if addon:FindLine(tooltip, sourcePattern) or addon:FindLine(tooltip, collectedPattern) then return end

    addon:SafeMethod(tooltip, "AddLine", " ")
    if sourceInfo.isCollected == true then
        addon:SafeMethod(tooltip, "AddDoubleLine", source, COLLECTED or "Collected",
            1, 1, 1, 0.1, 1, 0.1)
    else
        addon:SafeMethod(tooltip, "AddLine", source, 1, 1, 1)
    end
end

local function OnTooltipAura(_, tooltip, _, _, context)
    if not addon:IsTooltipSafe(tooltip) or not addon:AllowTrigger("aura", tooltip) then return end
    if type(context) ~= "table" or type(context.spellID) ~= "number" then return end

    local spellID = context.spellID
    local sourceInfo = mounts[spellID]
    if sourceInfo and lastMountByTooltip[tooltip] ~= spellID then
        AddMountSource(tooltip, sourceInfo)
        lastMountByTooltip[tooltip] = spellID
    end
end

local function ClearTooltipState(_, tooltip)
    if addon:CanAccessValue(tooltip) and tooltip ~= nil then lastMountByTooltip[tooltip] = nil end
end

local M = {}

function M:Init()
    self.cbScan = ScheduleMountScan
    self.cbAura = OnTooltipAura
    self.cbClear = ClearTooltipState
end

function M:Enable()
    if IsLoggedIn and IsLoggedIn() then
        self.cbScan()
    else
        addon.MM:AttachEvent("Mount", "PLAYER_LOGIN", self.cbScan, "PLAYER_LOGIN")
    end
    -- New mounts are rare; one complete rebuild is cheaper and safer than
    -- depending on an undocumented event payload. Search-filter updates do not
    -- change journal ownership and no longer trigger full rescans.
    addon.MM:AttachEvent("Mount", "NEW_MOUNT_ADDED", self.cbScan, "NEW_MOUNT_ADDED")
    addon.MM:AttachTrigger("Mount", "tooltip:aura", self.cbAura, "tooltip:aura")
    addon.MM:AttachTrigger("Mount", "tooltip:cleared, tooltip:hide", self.cbClear, "tooltip:clear")
end

function M:Disable()
    StopMountScanTicker()
    wipe(lastMountByTooltip)
end

function M:OnTooltip(_) end
function M:OnStyleChanged(_) end

addon.MM:RegisterModule("Mount", M)
