package main

import rl "vendor:raylib"
import e "engine"
import "ui"

RELEASE_BUILD :: #config(RELEASE, false)
ENABLE_EDITOR :: #config(EDITOR, !RELEASE_BUILD)

Editor :: struct {
	enabled: bool,
	hierarchy: SceneHierarchy,
	inspector: Inspector,
	selectedTargetIndex: int,
	selectedNode: ^e.Node,
	hierarchyRect: rl.Rectangle,
	viewportRect: rl.Rectangle,
	inspectorRect: rl.Rectangle,
	targetNames: [9]cstring,

	// Box2D Physics Nodes & Joint references for Inspector editing
	staticBody: ^e.StaticBodyNode,
	dynamicBody: ^e.DynamicBodyNode,
	characterMover: ^e.CharacterMoverNode,
	areaNode: ^e.AreaNode,
	raycastNode: ^e.RaycastNode,
	joint: ^e.PhysicsJoint,
}

Editor_Init :: proc(ed: ^Editor) {
	ed.enabled = ENABLE_EDITOR
	SceneHierarchy_Init(&ed.hierarchy)
	Inspector_Init(&ed.inspector)
	ed.selectedTargetIndex = 0
	ed.selectedNode = nil
	ed.targetNames = [9]cstring{
		"Particle Emitter",
		"Spaceship Node",
		"Spaceship Data",
		"Physics World",
		"StaticBody",
		"DynamicBody",
		"CharacterMover",
		"Area Sensor",
		"Raycast & Joint",
	}
}

Editor_Toggle :: proc(ed: ^Editor) {
	ed.enabled = !ed.enabled
}

Editor_Update :: proc(ed: ^Editor) {
	// Hotkey F2 or Grave (tilde) to toggle entire editor
	if rl.IsKeyPressed(.F2) || rl.IsKeyPressed(.GRAVE) {
		ed.enabled = !ed.enabled
	}

	// Hotkeys for individual panels when editor is enabled
	if ed.enabled {
		if rl.IsKeyPressed(.F3) {
			ed.hierarchy.visible = !ed.hierarchy.visible
		}
		if rl.IsKeyPressed(.F4) {
			ed.inspector.visible = !ed.inspector.visible
		}
	}
}

Editor_ComputeLayout :: proc(ed: ^Editor, sw, sh: f32) {
	if !ed.enabled {
		// Editor is off: game viewport takes full window
		ed.viewportRect = {0, 0, sw, sh}
		ed.hierarchyRect = {0, 0, 0, 0}
		ed.inspectorRect = {0, 0, 0, 0}
		return
	}

	hWidth: f32 = ed.hierarchy.width if ed.hierarchy.visible else 0
	iWidth: f32 = ed.inspector.width if ed.inspector.visible else 0

	if ed.inspector.dockSide == .Right {
		// [ Hierarchy (Left) ] [ Viewport (Middle) ] [ Inspector (Right) ]
		ed.hierarchyRect = {0, 0, hWidth, sh}
		ed.viewportRect  = {hWidth, 0, sw - hWidth - iWidth, sh}
		ed.inspectorRect = {sw - iWidth, 0, iWidth, sh}
	} else {
		// [ Inspector (Left) ] [ Viewport (Middle) ] [ Hierarchy (Right) ]
		ed.inspectorRect = {0, 0, iWidth, sh}
		ed.viewportRect  = {iWidth, 0, sw - iWidth - hWidth, sh}
		ed.hierarchyRect = {sw - hWidth, 0, hWidth, sh}
	}
}

Editor_Render :: proc(ed: ^Editor, game: ^e.Game, particleNode: ^e.ParticleEmitterNode, sh: f32) {
	if !ed.enabled {
		// Discrete toggle hint in development mode when editor UI is toggled off
		when !RELEASE_BUILD {
			if ui.GuiButton({8, 8, 85, 22}, "Editor [F2]") {
				ed.enabled = true
			}
		}
		return
	}

	// Render Scene Hierarchy Tree View
	if ed.hierarchy.visible {
		SceneHierarchy_Render(
			&ed.hierarchy,
			ed.hierarchyRect,
			&ed.selectedTargetIndex,
			ed.targetNames[:],
			ed.inspector.dockSide,
			sh,
			game,
			ed,
			particleNode,
		)
	}

	// Render Inspector
	if ed.inspector.visible {
		Inspector_Render(
			&ed.inspector,
			ed.inspectorRect,
			&ed.selectedTargetIndex,
			ed.targetNames[:],
			sh,
			game,
			particleNode,
			ed,
		)
	}

	// Top toolbar / toggle bar if any panel was closed
	if !ed.hierarchy.visible || !ed.inspector.visible {
		barX: f32 = ed.viewportRect.x + 10
		if !ed.hierarchy.visible {
			if ui.GuiButton({barX, 10, 95, 20}, "+ Hierarchy") {
				ed.hierarchy.visible = true
			}
			barX += 100
		}
		if !ed.inspector.visible {
			if ui.GuiButton({barX, 10, 95, 20}, "+ Inspector") {
				ed.inspector.visible = true
			}
		}
	}
}
