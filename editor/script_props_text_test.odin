package editor

import "core:strings"
import "core:testing"

// #208: a script's properties table edited as text - an entry written from
// a definition, added, replaced, removed; the table made when missing; the
// lines that use self.<name>.

@(private = "file")
SCRIPT :: `---@class Enemy : ScriptInstanceBase
local Enemy = {}

-- Exported properties appear in the Inspector.
Enemy.properties = {
	speed = { type = "float", default = 100 },
	-- the drop table
	loot = { type = "array", of = "resource", class = "scripts/item.lua",
		default = {} },
	mode = { type = "enum", values = {"Idle", "Run"}, default = "Idle" },
}

function Enemy:update(dt)
	self.node.position = self.node.position + self.speed * dt
	local s = self.speedy
end

return Enemy
`

@(test)
test_script_prop_entry_lua :: proc(t: ^testing.T) {
	d := Prop_Def{name = "weapon", kind = "resource", class = "scripts/weapon.lua", label = "Weapon", tooltip = `the "main" one`}
	testing.expect_value(t, Prop_EntryLua(d), `weapon = { type = "resource", class = "scripts/weapon.lua", label = "Weapon", tooltip = "the \"main\" one" },`)
	d = Prop_Def{name = "hp", kind = "int", default = "10", min = 0, max = 100, hasRange = true, slider = true}
	testing.expect_value(t, Prop_EntryLua(d), `hp = { type = "int", default = 10, min = 0, max = 100, slider = true },`)
	d = Prop_Def{name = "mode", kind = "enum", values = {"Idle", "Run"}, default = `"Run"`}
	testing.expect_value(t, Prop_EntryLua(d), `mode = { type = "enum", values = {"Idle", "Run"}, default = "Run" },`)
	d = Prop_Def{name = "drops", kind = "array", elem = "texture"}
	testing.expect_value(t, Prop_EntryLua(d), `drops = { type = "array", of = "texture" },`)
}

@(test)
test_script_prop_text_edits :: proc(t: ^testing.T) {
	// Add: before the table's closing brace, the file's indent.
	add, ok := Prop_Upsert(SCRIPT, "Enemy", Prop_Def{name = "hp", kind = "int", default = "5"})
	testing.expect(t, ok, "added")
	testing.expectf(t, strings.contains(add, "\tmode = { type = \"enum\", values = {\"Idle\", \"Run\"}, default = \"Idle\" },\n\thp = { type = \"int\", default = 5 },\n}"), "added last: %s", add)
	// Replace a multi-line entry: its comment above stays.
	rep, ok2 := Prop_Upsert(SCRIPT, "Enemy", Prop_Def{name = "loot", kind = "array", elem = "texture"})
	testing.expect(t, ok2, "replaced")
	testing.expectf(t, strings.contains(rep, "\t-- the drop table\n\tloot = { type = \"array\", of = \"texture\" },\n\tmode"), "replaced in place: %s", rep)
	testing.expect(t, !strings.contains(rep, "default = {} },"), "old lines gone")
	// Remove.
	rem, ok3 := Prop_Remove(SCRIPT, "Enemy", "speed")
	testing.expect(t, ok3, "removed")
	testing.expect(t, !strings.contains(rem, "speed = {"), "gone")
	testing.expect(t, strings.contains(rem, "Enemy.properties = {\n\t-- the drop table"), "the rest kept")
	_, ok4 := Prop_Remove(SCRIPT, "Enemy", "nope")
	testing.expect(t, !ok4, "an unknown one: no")
	// No table yet: made after `local Cls = {}`.
	bare := "local Thing = {}\n\nfunction Thing:ready() end\n\nreturn Thing\n"
	made, ok5 := Prop_Upsert(bare, "Thing", Prop_Def{name = "speed", kind = "float", default = "1"})
	testing.expect(t, ok5, "made")
	testing.expectf(t, strings.contains(made, "local Thing = {}\n\nThing.properties = {\n\tspeed = { type = \"float\", default = 1 },\n}\n"), "table made: %s", made)
	// Uses of self.speed (not self.speedy): line 14 (1-based).
	uses := Prop_Uses(SCRIPT, "speed")
	testing.expect(t, len(uses) == 1 && uses[0] == 14, "self.speed's line")
}
