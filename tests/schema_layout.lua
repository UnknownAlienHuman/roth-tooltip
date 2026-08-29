local addon = {}
assert(loadfile("Engine/Schema.lua"))("RothTooltip", addon)

local defaults = {
    version = 1,
    unit = {
        player = {
            elements = {
                a = { enable = true, color = "default", wildcard = "%s", filter = "none" },
                b = { enable = true, color = "default", wildcard = "%s", filter = "none" },
                c = { enable = true, color = "default", wildcard = "%s", filter = "none" },
                d = { enable = true, color = "default", wildcard = "%s", filter = "none" },
                factionBig = { enable = true, filter = "none" },
                { "a", "b" },
                { "c" },
                { "d" },
            },
        },
    },
}
addon:SetDefaultProfile(defaults)

local empty = addon:BuildProfile({})
local rows = empty.unit.player.elements
assert(#rows == 3)
assert(rows[1][1] == "a" and rows[1][2] == "b")
assert(rows[2][1] == "c" and rows[2][2] == nil)
assert(rows[3][1] == "d" and rows[3][2] == nil)

local customized = addon:BuildProfile({
    unit = {
        player = {
            elements = {
                { "c", "a", "c", "unknown" },
            },
        },
    },
})
rows = customized.unit.player.elements
assert(rows[1][1] == "c" and rows[1][2] == "a")
assert(rows[1][3] == "b", "missing row-one default should return to row one")
assert(rows[2] == nil or #rows[2] == 0, "already placed row-two element must not duplicate")
assert(rows[3][1] == "d", "new/missing row-three element should retain its default row")

print("schema_layout: ok")
