local addon = {}

assert(loadfile("Config.lua"))("RothTooltip", addon)
assert(loadfile("Engine/Schema.lua"))("RothTooltip", addon)

local defaults = addon.__RT_DefaultDB
assert(type(defaults) == "table")

local stored = {
    version = 1,
    unknownRoot = "drop-me",
    general = {
        scale = "wrong-type",
        background = { 0.1, 0.2, 0.3, 0.4 },
        anchor = { position = "static", x = 77, unknown = true },
        unknown = true,
    },
    unit = {
        player = {
            elements = {
                name = { enable = false, color = "ffffff", wildcard = "%s", filter = "none" },
                ["1"] = { "name", "name", "removedElement" },
                ["2"] = { "guildName" },
            },
        },
    },
    variables = {
        extension = { enabled = true },
    },
}

local account = addon:BuildProfile(stored)
local character = addon:BuildProfile({}, account)

assert(account ~= defaults)
assert(account.general ~= defaults.general)
assert(account.general.background ~= defaults.general.background)
assert(character ~= account)
assert(character.general ~= account.general)
assert(character.unit.player.elements ~= account.unit.player.elements)

assert(account.unknownRoot == nil)
assert(account.general.unknown == nil)
assert(account.general.scale == defaults.general.scale)
assert(account.general.anchor.position == "static")
assert(account.general.anchor.x == 77)
assert(account.general.anchor.cx == defaults.general.anchor.cx)
assert(account.variables.extension.enabled == true)

local seen = {}
for _, row in ipairs(account.unit.player.elements) do
    for _, key in ipairs(row) do
        assert(type(key) == "string")
        assert(account.unit.player.elements[key] ~= nil)
        assert(not seen[key], "duplicate element in merged layout: " .. key)
        seen[key] = true
    end
end
assert(seen.name)
assert(seen.guildName)
assert(not seen.removedElement)

account.general.background[1] = 0.99
account.unit.player.elements.name.enable = true
account.variables.extension.enabled = false
assert(defaults.general.background[1] ~= 0.99)
assert(defaults.unit.player.elements.name.enable == true)
assert(character.general.background[1] ~= 0.99)
assert(character.unit.player.elements.name.enable == false)
assert(character.variables.extension.enabled == true)

local rebuilt = addon:BuildProfile(account)
assert(rebuilt.general.statusbarFont == "default")
assert(rebuilt.general.anchor.x == 77)
assert(rebuilt.general.anchor.cy == 20)

print("schema ownership: ok")
