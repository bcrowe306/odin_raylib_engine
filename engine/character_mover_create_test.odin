package engine

import "core:testing"

// Issue #50: creating a CharacterMover crashed (SIGSEGV) when the scene had
// removed nodes - their slots in manager.nodes are nil, and the "is there
// already a player mover?" scan read through them. Saving a CharacterMover
// with children as a component hit it.
@(test)
test_character_mover_create_after_removed_nodes :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("mover_create", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	// The removed node's slot comes before the player's: the scan crosses it.
	gone := Node_CreateByTypeName(scene, "Node")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	SceneRemoveNode(scene, gone)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	hasNil := false
	for n in scene.manager.nodes do if n == nil do hasNil = true
	testing.expect(t, hasNil, "a removed node leaves a nil slot (the crash's precondition)")
	first := CharacterMoverNode_Create(scene, "Player") // (crashed here: SIGSEGV)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	second := CharacterMoverNode_Create(scene, "Enemy")
	testing.expect(t, second != nil, "created")
	testing.expect(t, first.enableKeyboardInput && first.playerIndex == 1, "the first mover is the player")
	testing.expect(t, !second.enableKeyboardInput && second.playerIndex == 0, "the second defaults to an NPC")
}
