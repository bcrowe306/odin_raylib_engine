package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// #87: the components the project templates ship (templates/*/components)
// all load as linked instances.
@(test)
test_template_components_load :: proc(t: ^testing.T) {
	h, err := os.open("templates")
	if !testing.expect(t, err == nil, "the templates folder") do return
	templates, _ := os.read_dir(h, -1, context.temp_allocator)
	os.close(h)
	loaded := 0
	for tpl in templates {
		if tpl.type != .Directory do continue
		dir, _ := filepath.join({"templates", tpl.name, "components"}, context.temp_allocator)
		ch, cerr := os.open(dir)
		if cerr != nil do continue
		files, _ := os.read_dir(ch, -1, context.temp_allocator)
		os.close(ch)
		game := new(Game)
		InitializeGame(game)
		root, _ := filepath.join({"templates", tpl.name}, context.temp_allocator)
		AssetManager_SetProjectDir(&game.assetManager, root)
		scene := game->createScene(tpl.name, false)
		for f in files {
			if !strings.has_suffix(f.name, ".component.json") do continue
			rel := strings.concatenate({"components/", f.name}, context.temp_allocator)
			inst := Scene_InstantiateComponent(scene, rel, nil, &game.gameContext)
			testing.expectf(t, inst != nil && !inst.componentMissing, "%s: %s loads", tpl.name, rel)
			loaded += 1
		}
		game->terminate()
	}
	testing.expect(t, loaded >= 8, "the shmup's and the platformer's components")
}
