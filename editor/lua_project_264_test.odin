package editor

import "core:strings"
import "core:testing"

// #264: lua-language-server skips the editor's file history (old copies of
// every script declared each class again: "duplicate field"), and a
// duplicated script gets its own class name.
@(test)
test_luarc_ignores_history_and_copies_rename :: proc(t: ^testing.T) {
	rc := luarc_text()
	testing.expect(t, strings.contains(rc, `"workspace.ignoreDir": [".rayzr/history"]`), rc)

	src := `---@class PlayerShip : ScriptInstanceBase
local PlayerShip = {}
PlayerShip.properties = {}
local PlayerShipSpeed = 3
function PlayerShip:update(dt) self.x = PlayerShipSpeed end
return PlayerShip
`
	got := script_copy_renamed(src, "scripts/player_ship_copy.lua")
	testing.expect(t, strings.contains(got, "---@class PlayerShipCopy : ScriptInstanceBase"), got)
	testing.expect(t, strings.contains(got, "local PlayerShipCopy = {}"), got)
	testing.expect(t, strings.contains(got, "function PlayerShipCopy:update(dt)"), got)
	testing.expect(t, strings.contains(got, "return PlayerShipCopy\n"), got)
	testing.expect(t, strings.contains(got, "local PlayerShipSpeed = 3"), "other names that start the same are kept")
	testing.expect(t, !strings.contains(got, "PlayerShip:") && !strings.contains(got, "PlayerShip "), got)
	// No `return Name`, or a file name that isn't a Lua name: unchanged.
	testing.expect_value(t, script_copy_renamed("print(1)\n", "scripts/a_copy.lua"), "print(1)\n")
	testing.expect_value(t, script_copy_renamed(src, "scripts/2 fast_copy.lua"), src)
	free_all(context.temp_allocator)
}
