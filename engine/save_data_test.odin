package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_save_data :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "ore_save_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	Save_SetDirectory(dir)
	defer Save_Reset()
	file, _ := filepath.join({dir, "save.json"}, context.temp_allocator)

	run :: proc(t: ^testing.T, game: ^Game, code: string) {
		L := game.scriptManager.L
		if lua.L_dostring(L, strings.clone_to_cstring(code, context.temp_allocator)) != 0 {
			testing.expectf(t, false, "lua: %s", lua.tostring(L, -1))
			lua.pop(L, 1)
		}
	}
	global :: proc(game: ^Game, name: cstring) -> string {
		L := game.scriptManager.L
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}

	{
		game := new(Game)
		InitializeGame(game)
		run(t, game, `
Save.set("coins", 42)
Save.set("speed", 1.5)
Save.set("name", "Ada \"the\" pilot")
Save.set("unlocked", {"level_1", "level_2"})
Save.set("settings", {music = 0.5, fullscreen = true})
Save.set("gone", 1)
Save.delete("gone")
Save.set("empty", {})
ok_flush = tostring(Save.flush())
has_coins = tostring(Save.has("coins")) .. tostring(Save.has("gone"))
keys = table.concat(Save.keys(), ",")
`)
		testing.expect_value(t, global(game, "ok_flush"), "true")
		testing.expect_value(t, global(game, "has_coins"), "truefalse")
		testing.expect_value(t, global(game, "keys"), "coins,empty,name,settings,speed,unlocked")
		data, err := os.read_entire_file(file, context.temp_allocator)
		testing.expect(t, err == nil, "save.json written")
		text := string(data)
		testing.expect(t, strings.contains(text, `"coins": 42`), text)
		testing.expect(t, strings.contains(text, `"unlocked": ["level_1", "level_2"]`), text)
		testing.expect(t, strings.contains(text, `"name": "Ada \"the\" pilot"`), text)
		testing.expect(t, !strings.contains(text, `"gone"`), text)
		// Changed after the flush: written when the game quits.
		run(t, game, `Save.set("coins", 43)`)
		game->terminate()
	}
	{
		game := new(Game)
		InitializeGame(game)
		defer game->terminate()
		run(t, game, `
local s = Save.get("settings")
loaded = Save.get("coins") .. "|" .. Save.get("speed") .. "|" .. Save.get("name") .. "|" ..
	Save.get("unlocked")[2] .. "|" .. tostring(s.fullscreen) .. "|" .. s.music .. "|" ..
	Save.get("missing", "def") .. "|" .. math.type(Save.get("coins")) .. "|" .. math.type(Save.get("speed"))
`)
		testing.expect_value(t, global(game, "loaded"), `43|1.5|Ada "the" pilot|level_2|true|0.5|def|integer|float`)

		// Slots: another file; switching back reads the first again.
		run(t, game, `
Save.slot("slot2")
Save.set("coins", 7)
Save.slot("save")
in_save = Save.get("coins")
Save.slot("slot2")
in_slot2 = Save.get("coins") .. " " .. Save.slot()
`)
		testing.expect_value(t, global(game, "in_save"), "43")
		testing.expect_value(t, global(game, "in_slot2"), "7 slot2")
		slot2, _ := filepath.join({dir, "slot2.json"}, context.temp_allocator)
		testing.expect(t, os.exists(slot2), "slot2.json written")

		// Values that can't be saved become null (and nothing breaks).
		run(t, game, `
Save.set("fn", function() end)
Save.clear()
Save.set("only", true)
Save.flush()
`)
		data, _ := os.read_entire_file(slot2, context.temp_allocator)
		testing.expect_value(t, strings.trim_space(string(data)), `{"only": true}`)
	}
	// A broken file starts empty instead of failing.
	_ = os.write_entire_file(file, transmute([]u8)string("{not json"))
	{
		Save_Reset()
		Save_SetDirectory(dir)
		game := new(Game)
		InitializeGame(game)
		defer game->terminate()
		run(t, game, `broken = tostring(Save.get("coins"))`)
		testing.expect_value(t, global(game, "broken"), "nil")
	}
	// The platform folder is named after the game.
	Save_Reset()
	Save_SetGameName("My: Game")
	testing.expect(t, strings.has_suffix(Save_UserDataDir("My: Game"), "My_ Game"), Save_UserDataDir("My: Game"))
}
