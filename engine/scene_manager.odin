package engine

import "core:log"
import vmem "core:mem/virtual"

SceneManager :: struct {
	scenes: map[string]Scene,
	currentScene: ^Scene,
	nextScene: ^Scene
}


SceneManager_Init :: proc(manager: ^SceneManager, arena: ^vmem.Arena) {

	arena_allocator := vmem.arena_allocator(arena)
	manager.scenes = make( map[string]Scene, allocator = arena_allocator )
	manager.currentScene = nil
	manager.nextScene = nil
}


ChangeScene_ByName :: proc(manager: ^SceneManager, name: string) {
	_, ok := manager.scenes[name]
	if ok {
		scene := &manager.scenes[name]
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


ProcessSceneChange :: proc(manager: ^SceneManager) {
	if manager.nextScene != nil {
		manager.currentScene = manager.nextScene
		manager.nextScene = nil
	}
}
