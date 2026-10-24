package engine

import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// VisibilityNotifierNode: a rectangle (centred on the node, scaled with it)
// that knows whether the camera sees it.
//
// - Events: "screen_entered" / "screen_exited" (connect them, or define
//   on_screen_entered / on_screen_exited on the node's script).
// - An optional action on its parent: Pause (stops updating, scripts and
//   physics; resumed when seen again), Disable (also stops drawing) or
//   Remove (free it once it has been seen and leaves - bullets, debris).
//
// The check runs once per frame for every notifier of the scene, outside
// the update tree (a paused / disabled parent can still be woken up):
// Visibility_Update after the transforms, against the scene camera's view
// (or the virtual screen without one). Notifiers are kept in their node
// manager's `notifiers` list (added / removed with the node), so the pass
// touches only them.
// ============================================================================

Visibility_Action :: enum u8 {
	None,
	Pause_Parent,   // parent.paused while off screen
	Disable_Parent, // parent.enabled = false while off screen (no drawing either)
	Remove_Parent,  // removed once it was on screen and left
}

VisibilityNotifierNode :: struct {
	using node: Node,
	size:   [2]f32 `gui:"true" min:"1" max:"4096"`,
	margin: f32 `gui:"true" min:"0" max:"1024"`, // grows the camera view (wake up a little before)
	action: Visibility_Action `gui:"true"`,
	// Runtime.
	onScreen: bool `gui:"true" save:"false"`, // the camera sees it now (read it from scripts: node.onScreen)
	seen:     bool, // was on screen once
	checked:  bool, // checked at least once
	onEntered: EventSubject, // "screen_entered"
	onExited:  EventSubject, // "screen_exited"
}

VisibilityNotifierNode_Create :: proc(scene: ^Scene, name: string = "VisibilityNotifier", parent: ^Node = nil) -> ^VisibilityNotifierNode {
	v := CreateNode(scene.manager, VisibilityNotifierNode)
	v.name = strings.clone(name, v.allocator)
	v.size = {64, 64}
	v.renderable = true // (shown with the debug bounds; picks in the editor)
	v.drawBounds = VisibilityNotifierNode_DrawBounds
	v.onDestroy = VisibilityNotifierNode_Destroy
	InitializeSubject(&v.onEntered, "screen_entered", v)
	InitializeSubject(&v.onExited, "screen_exited", v)
	scene->addNode(v, parent)
	return v
}

VisibilityNotifierNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	v := cast(^VisibilityNotifierNode)node
	DestroySubject(&v.onEntered)
	DestroySubject(&v.onExited)
}

// VisibilityNotifierNode_Rect: its world rectangle (axis-aligned).
VisibilityNotifierNode_Rect :: proc(v: ^VisibilityNotifierNode) -> rl.Rectangle {
	s := v.size * [2]f32{abs(v.globalScale.x), abs(v.globalScale.y)}
	return {v.globalPosition.x - s.x * 0.5, v.globalPosition.y - s.y * 0.5, s.x, s.y}
}

VisibilityNotifierNode_DrawBounds :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	v := cast(^VisibilityNotifierNode)node
	col := rl.Color{250, 204, 21, 200} if v.onScreen else rl.Color{250, 204, 21, 90}
	rl.DrawRectangleLinesEx(VisibilityNotifierNode_Rect(v), 1, col)
}

// Visibility_ViewRect: what the scene's camera shows (the virtual screen
// at the origin without a current camera).
Visibility_ViewRect :: proc(scene: ^Scene, ctx: ^GameContext) -> rl.Rectangle {
	vw, vh: f32 = 1280, 720
	if ctx != nil && ctx.game != nil && ctx.game.virtualSize.x > 0 do vw, vh = ctx.game.virtualSize.x, ctx.game.virtualSize.y
	if scene.camera != nil && scene.camera.enabled && scene.camera.isCurrent {
		return Camera2D_ViewRect(CameraNode_GetCamera2D(scene.camera, vw, vh), vw, vh)
	}
	return {0, 0, vw, vh}
}

// Visibility_Update checks every notifier of the scene against the view
// (call after the transforms are up to date). Events and actions run after
// the pass, so a handler that removes or adds nodes doesn't disturb it.
Visibility_Update :: proc(scene: ^Scene, ctx: ^GameContext) {
	if scene == nil || scene.manager == nil || len(scene.manager.notifiers) == 0 do return
	view := Visibility_ViewRect(scene, ctx)
	Change :: struct {
		v:   ^VisibilityNotifierNode,
		now: bool,
	}
	changes := make([dynamic]Change, 0, 8, context.temp_allocator)
	for n in scene.manager.notifiers {
		v := cast(^VisibilityNotifierNode)n
		if v.removing do continue
		r := VisibilityNotifierNode_Rect(v)
		m := v.margin
		now := r.x <= view.x + view.width + m && r.x + r.width >= view.x - m && r.y <= view.y + view.height + m && r.y + r.height >= view.y - m
		if v.checked && now == v.onScreen do continue
		append(&changes, Change{v, now})
	}
	for c in changes {
		v := c.v
		if v.removing do continue // (an earlier handler removed it)
		first := !v.checked
		v.checked = true
		v.onScreen = c.now
		if c.now do v.seen = true
		parent := GetParent(scene.manager, v)
		if parent != nil && parent != scene.rootNode {
			switch v.action {
			case .None:
			case .Pause_Parent:   parent.paused = !c.now
			case .Disable_Parent: parent.enabled = c.now
			case .Remove_Parent:
				if !c.now && v.seen && !parent.removing {
					RemoveNode(scene.manager, parent)
					continue
				}
			}
		}
		// No "exited" for one that starts off screen.
		if c.now do v.onEntered->notify(v, nil, ctx)
		else if !first do v.onExited->notify(v, nil, ctx)
	}
}
