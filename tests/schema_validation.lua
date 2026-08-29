local addon = {}
assert(loadfile("Engine/Schema.lua"))("RothTooltip", addon)

local defaults = {
    version = 3.3,
    general = {
        scale = 1,
        borderSize = 1,
        combatPolicy = "STRICT",
        statusbarColor = "auto",
        statusbarFontSize = 10,
        headerFontSize = "default",
        visibility = {
            inCombat = "show",
            inRaid = "show",
            inArena = "show",
            bags = "show",
            actionBars = "show",
        },
        anchor = {
            position = "cursorRight",
            p = "BOTTOMRIGHT",
            cp = "BOTTOM",
            x = 0,
            cx = 0,
        },
    },
    unit = {
        player = {
            coloredBorder = "class",
            background = { colorfunc = "class", alpha = 0.9 },
            anchor = { position = "inherit", p = "BOTTOMRIGHT", cp = "BOTTOM" },
            elements = {
                name = { enable = true, color = "class", wildcard = "%s", filter = "none" },
                levelValue = { enable = true, color = "level", wildcard = "%d", filter = "none" },
                factionBig = { enable = true, filter = "none" },
                { "name", "levelValue" },
            },
        },
    },
    model = { width = 100, height = 100, facing = 0, offsetX = 0, offsetY = 0 },
    variables = {},
}

addon:SetDefaultProfile(defaults)
local stored = {
    version = 2.0,
    general = {
        scale = 999,
        borderSize = -4,
        combatPolicy = "UNKNOWN",
        statusbarColor = "rainbow",
        statusbarFontSize = 500,
        headerFontSize = 14,
        visibility = { inCombat = "explode", inRaid = "hide" },
        anchor = { position = "sideways", p = "INVALID", cp = "TOP", x = 9000, cx = -9000 },
    },
    unit = {
        player = {
            coloredBorder = "not-a-color-mode",
            background = { colorfunc = "selection", alpha = -2 },
            anchor = { position = "auto", p = "TOPLEFT", cp = "RIGHT" },
            elements = {
                name = { enable = "yes", color = "ff00ff", wildcard = string.rep("x", 200), filter = "bad-filter" },
                levelValue = { enable = true, color = "level", wildcard = "%d", filter = "reaction:5" },
                unknown = { enable = true },
                { "unknown", "name", "name" },
            },
        },
    },
    model = { width = 2, height = 9999, facing = 999, offsetX = -99999, offsetY = 99999 },
    variables = { nested = { keep = true } },
    unknownTopLevel = true,
}

local profile = addon:BuildProfile(stored)
assert(profile ~= defaults)
assert(profile.general ~= defaults.general)
assert(profile.unit.player.elements ~= defaults.unit.player.elements)
assert(profile.variables ~= stored.variables)
assert(profile.variables.nested ~= stored.variables.nested)

assert(profile.version == defaults.version)
assert(profile.general.scale == 4)
assert(profile.general.borderSize == 1)
assert(profile.general.combatPolicy == "STRICT")
assert(profile.general.statusbarColor == "auto")
assert(profile.general.statusbarFontSize == 72)
assert(profile.general.headerFontSize == 14)
assert(profile.general.visibility.inCombat == "show")
assert(profile.general.visibility.inRaid == "hide")
assert(profile.general.anchor.position == "cursorRight")
assert(profile.general.anchor.p == "BOTTOMRIGHT")
assert(profile.general.anchor.cp == "TOP")
assert(profile.general.anchor.x == 4000)
assert(profile.general.anchor.cx == -1000)

assert(profile.unit.player.coloredBorder == "class")
assert(profile.unit.player.background.colorfunc == "selection")
assert(profile.unit.player.background.alpha == 0)
assert(profile.unit.player.anchor.position == "auto")
assert(profile.unit.player.elements.name.enable == true)
assert(profile.unit.player.elements.name.color == "ff00ff")
assert(profile.unit.player.elements.name.wildcard == "%s")
assert(profile.unit.player.elements.name.filter == "none")
assert(profile.unit.player.elements.levelValue.filter == "reaction:5")
assert(profile.unit.player.elements.unknown == nil)
assert(profile.unit.player.elements[1][1] == "name")
assert(profile.unit.player.elements[1][2] == "levelValue")
assert(profile.unit.player.elements[1][3] == nil)

assert(profile.model.width == 16)
assert(profile.model.height == 1000)
assert(profile.model.facing <= math.pi * 2)
assert(profile.model.offsetX == -4000)
assert(profile.model.offsetY == 4000)
assert(profile.unknownTopLevel == nil)

profile.general.visibility.inRaid = "show"
profile.unit.player.elements.name.enable = false
profile.variables.nested.keep = false
assert(defaults.general.visibility.inRaid == "show")
assert(defaults.unit.player.elements.name.enable == true)
assert(stored.variables.nested.keep == true)

print("schema_validation: ok")
