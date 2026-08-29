-- RothTooltip style lifecycle controller.
--
-- Engine/Style.lua owns regions and rendering primitives. This controller owns
-- when the active profile is applied to managed tooltips.

local _, addon = ...
local LibEvent = addon.LibEvent or LibStub:GetLibrary("LibEvent.7000")

LibEvent:attachTrigger("tooltip.scale", function(_, tooltip, scale)
    if addon:IsTooltipSafe(tooltip) and type(scale) == "number" then
        addon:SafeMethod(tooltip, "SetScale", scale)
    end
end)

local function ApplyProfileStyle()
    local general = addon.db and addon.db.general
    if type(general) ~= "table" or type(addon.ForEachManagedTooltip) ~= "function" then return end

    LibEvent:trigger("tooltip.style.font.header", GameTooltip,
        general.headerFont, general.headerFontSize, general.headerFontFlag)
    LibEvent:trigger("tooltip.style.font.body", GameTooltip,
        general.bodyFont, general.bodyFontSize, general.bodyFontFlag)

    addon:ForEachManagedTooltip(function(tooltip)
        addon:ApplyGeneralStyleToTooltip(tooltip)
    end)
end

LibEvent:attachTrigger("ROTHTOOLTIP_GENERAL_INIT", ApplyProfileStyle)
LibEvent:attachTrigger("tooltip:show", function(_, tooltip)
    addon:ApplyGeneralStyleToTooltip(tooltip)
end)
