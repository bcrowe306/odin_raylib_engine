package engine

import rl "vendor:raylib"

// ============================================================================
// Screen Layer (#175): HUDs and anything that doesn't move with the camera.
//
// Everything under a Screen Layer is drawn in screen space - the game's
// frame (its virtual resolution; with Expand fill, grown to the window's
// shape) - after the world and on top of it, whatever the camera does. The
// layer sits at one of nine points of the frame (its Anchor: top left ...
// bottom right) plus its position, so a score box anchored top-right stays
// at the top-right edge however wide the frame is. Screen Layers can nest:
// each anchors to the frame, not to its parent.
//
// In the editor the frame is the scene camera's view in the world: a
// Screen Layer's subtree is placed over the camera frame there (and edited
// like any node).
//
// The screen mapping (NodeManager.screen) turns a Screen Layer's anchor and
// position into its global position: the game sets it to the frame (origin
// 0, scale 1); the editor to the camera's view.
// ============================================================================

Screen_Anchor :: enum u8 {
	TopLeft, Top, TopRight,
	Left, Center, Right,
	BottomLeft, Bottom, BottomRight,
}

// Screen_AnchorFactor: where an anchor sits in the frame (0..1 per axis).
Screen_AnchorFactor :: proc(a: Screen_Anchor) -> [2]f32 {
	i := int(a)
	return {f32(i % 3) * 0.5, f32(i / 3) * 0.5}
}

// Screen_Mapping: from the frame (screen space) to the space nodes are
// drawn in - the frame itself in the game, the camera's view in the editor.
Screen_Mapping :: struct {
	origin: [2]f32, // where the frame's top-left is
	scale:  f32,    // world units per screen pixel (0 = 1)
	size:   [2]f32, // the frame's size (anchors); 0 = 1280 x 720
}

ScreenLayerNode :: struct {
	using node: Node,
	anchor: Screen_Anchor `gui:"true"`,
}

ScreenLayerNode_Create :: proc(scene: ^Scene, name: string = "ScreenLayer", parent: ^Node = nil) -> ^ScreenLayerNode {
	n := CreateNode(scene.manager, ScreenLayerNode)
	n.name = name
	n.layer = .Layer8 // (its own drawing - none - and a sensible layer for UI under it)
	scene->addNode(n, parent)
	return n
}

// screen_frame: the mapping's frame size and scale (defaults filled).
@(private)
screen_frame :: proc(m: Screen_Mapping) -> (size: [2]f32, scale: f32) {
	size = m.size if m.size.x > 0 && m.size.y > 0 else {1280, 720}
	scale = m.scale if m.scale != 0 else 1
	return
}

// ScreenLayer_Global: a Screen Layer's global position and scale from its
// anchor and position.
ScreenLayer_Global :: proc(m: Screen_Mapping, sl: ^ScreenLayerNode) -> (pos: [2]f32, scale: [2]f32) {
	size, s := screen_frame(m)
	return m.origin + (Screen_AnchorFactor(sl.anchor) * size + sl.position) * s, sl.scale * s
}

// ScreenLayer_PositionAt: the position that puts a Screen Layer's origin at
// a global point (the editor moving it).
ScreenLayer_PositionAt :: proc(m: Screen_Mapping, sl: ^ScreenLayerNode, global: [2]f32) -> [2]f32 {
	size, s := screen_frame(m)
	return (global - m.origin) / s - Screen_AnchorFactor(sl.anchor) * size
}

// Screen_MappingForGame: the game's mapping - the frame (its virtual size).
Screen_MappingForGame :: proc(ctx: ^GameContext) -> Screen_Mapping {
	m := Screen_Mapping{scale = 1, size = {1280, 720}}
	if ctx != nil && ctx.game != nil && ctx.game.virtualSize.x > 0 do m.size = ctx.game.virtualSize
	return m
}

// Screen_MappingForCamera: the editor's mapping - the camera's view of a
// w x h frame (no rotation), i.e. where the game shows the frame.
Screen_MappingForCamera :: proc(cam: rl.Camera2D, w, h: f32) -> Screen_Mapping {
	view := Camera2D_ViewRect(cam, w, h)
	zoom := cam.zoom if cam.zoom != 0 else 1
	return {origin = {view.x, view.y}, scale = 1 / zoom, size = {w, h}}
}
