local addon = {}

assert(loadfile("Config.lua"))("RothTooltip", addon)
assert(loadfile("Engine/Schema.lua"))("RothTooltip", addon)

addon.L = {
    ["general.mask"] = "Translated mask",
    ["general.scale"] = "%d invalid signature",
    ["unit.player.showTargetBy"] = "STALE",
    ["unknown.arbitrary"] = "UNTRUSTED",
    ["tooltip.itemID"] = "Translated item ID",
}

assert(loadfile("Engine/Locale.lua"))("RothTooltip", addon)

assert(addon.L["general.mask"] == "Translated mask")
assert(addon.L["general.scale"] == "Scale")
assert(addon.L["unit.player.showTargetBy"] ~= "STALE")
assert(addon.L["unknown.arbitrary"] ~= "UNTRUSTED")
assert(addon.L["tooltip.itemID"] == "Translated item ID")
assert(addon.L["tooltip.spellID"] == "Spell ID")
assert(addon:Localize("unit.player.elements.moveSpeed") == "Move Speed")
assert(addon:FormatLocalized("tooltip.itemID", "Item ID") == "Translated item ID")

print("locale overlay: ok")
