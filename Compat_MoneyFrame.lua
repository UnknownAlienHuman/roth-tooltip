--[[
RothTooltip: Midnight (12.0) compatibility.

Blizzard 12.0.x can raise Lua errors inside tooltip money rendering when "secret values" are
involved (MoneyFrame_Update / SetTooltipMoney). This has been reported even with no addons
enabled.

We do NOT attempt to change Blizzard logic; we only prevent those runtime errors from
breaking the UI by isolating the calls behind pcall.

Trade-off: in the rare cases where Blizzard throws, the affected tooltip money row may not
update/render for that tooltip instance.
]]

local function IsLoaded(addon)
    return C_AddOns.IsAddOnLoaded(addon)
end

local function WrapGlobalFunction(name)
    local orig = _G and _G[name]
    if (type(orig) ~= "function") then return end

    -- Lua functions are not tables; never index/annotate them.
    -- Use a name-based registry instead.
    RothTooltip_MoneyFrameCompat = RothTooltip_MoneyFrameCompat or {}
    local reg = RothTooltip_MoneyFrameCompat
    reg.wrapped = reg.wrapped or {}
    reg.orig = reg.orig or {}

    if (reg.wrapped[name]) then return end
    reg.wrapped[name] = true
    reg.orig[name] = orig

    _G[name] = function(...)
        local ok, r1, r2, r3, r4, r5, r6 = pcall(orig, ...)
        if (ok) then
            return r1, r2, r3, r4, r5, r6
        end

        -- Suppress secret-value errors only.
        if (type(r1) == "string" and string.find(r1, "secret value", 1, true)) then
            return
        end

        -- Fail closed (avoid hard error loops).
        return
    end
end

local function ApplyMoneyFrameSafeguard()
    -- These are globals in Blizzard_MoneyFrame.
    WrapGlobalFunction("MoneyFrame_Update")
    WrapGlobalFunction("SetTooltipMoney")
end

if (IsLoaded("Blizzard_MoneyFrame")) then
    ApplyMoneyFrameSafeguard()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, addonName)
        if (addonName == "Blizzard_MoneyFrame") then
            ApplyMoneyFrameSafeguard()
            f:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
