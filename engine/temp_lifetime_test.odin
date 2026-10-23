package engine

import "core:fmt"
import "core:testing"

// The temp arena is freed every frame (runner, editor): nodes keep their
// own copy of a name they were created with, so a temp string is fine.
@(test)
test_node_names_survive_temp_free :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("names", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	base := "Level"
	sb := StaticBodyNode_Create(scene, fmt.tprintf("%s_Colliders", base))
	cam := CameraNode_Create(scene, fmt.tprintf("%s_Camera", base))
	lbl := UILabelNode_Create(scene, fmt.tprintf("%s_Label", base))
	free_all(context.temp_allocator)
	_ = fmt.tprintf("%s", "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX") // reuse the arena
	testing.expect_value(t, sb.name, "Level_Colliders")
	testing.expect_value(t, cam.name, "Level_Camera")
	testing.expect_value(t, lbl.name, "Level_Label")
}
