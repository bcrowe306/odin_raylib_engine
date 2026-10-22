package engine

import "core:log"
import "core:mem"
import vmem "core:mem/virtual"

// Scenes are heap-allocated and stored by pointer so `currentScene`,
// `nextScene` and `gameContext.scene` stay valid when the map grows.
SceneManager :: struct {
	scenes: map[string]^Scene,
	currentScene: ^Scene,
	nextScene: ^Scene,
	allocator: mem.Allocator,
}


SceneManager_Init :: proc(manager: ^SceneManager, arena: ^vmem.Arena) {

	arena_allocator := vmem.arena_allocator(arena)
	manager.allocator = arena_allocator
	manager.scenes = make( map[string]^Scene, allocator = arena_allocator )
	manager.currentScene = nil
	manager.nextScene = nil
}

SceneManager_Terminate :: proc(manager: ^SceneManager) {
	if manager == nil do return
	for _, scene in manager.scenes {
		TerminateScene(scene)
	}
	clear(&manager.scenes)
	manager.currentScene = nil
	manager.nextScene = nil
}


ChangeScene_ByName :: proc(manager: ^SceneManager, name: string) {
	scene, ok := manager.scenes[name]
	if ok {
		manager.nextScene = scene
	}
	else {
		log.errorf("Scene: %s, not found", name)
	}
}

ChangeScene_ByPtr :: proc(manager: ^SceneManager, scene: ^Scene) {
	if scene != nil {
		manager.nextScene = scene
	}
	else {
		log.error("Cannot change scene. Scene is nil")
	}
}


ProcessSceneChange :: proc(manager: ^SceneManager, gameContext: ^GameContext = nil) {
	if manager.nextScene != nil {
		oldScene := manager.currentScene
		newScene := manager.nextScene

		if oldScene != nil && oldScene != newScene {
			if oldScene.onExit != nil {
				oldScene->onExit(gameContext)
			}
			// When scenes switch, destroy all objects in exiting scene and reset its state!
			Scene_Unload(oldScene, gameContext)
		}

		manager.currentScene = newScene
		manager.nextScene = nil

		if gameContext != nil {
			gameContext.scene = newScene
			if gameContext.game != nil {
				gameContext.game.activeDropdown = nil
			}
		}

		// Disable physics bodies in inactive scenes and enable physics bodies in the active scene
		for _, scene in manager.scenes {
			Scene_SetPhysicsEnabled(scene, scene == manager.currentScene)
		}

		// Load the new scene fresh: instantiate initial nodes & call ready on all initial nodes
		if !newScene.isLoaded {
			Scene_Load(newScene, gameContext)
		}

		if newScene.onEnter != nil {
			newScene->onEnter(gameContext)
		}
	}
}
