package engine

// ============================================================================
// Origin: the point of what a node draws that sits at its position, and that
// it rotates and scales around. Stored as a fraction of the drawn size
// (Node.pivot; {0.5, 0.5} = the centre, the default), so it stays put when
// the size changes (text, nine-slices, animation frames). Shown as "Origin"
// in the Inspector; scripts: node:set_property("origin", 0.5, 1) (bottom
// centre). Saved as "pivot".
//
// Nodes with an origin: TextureNode, FrameAnimationNode, AnimationPlayerNode,
// NineSliceNode, TextNode. (Bodies, areas and lines are drawn around their
// position already: their shapes / points have offsets of their own.)
// A TextureNode's `origin` (pixels) still overrides when not {0, 0}.
// ============================================================================

// Node_HasOrigin: the node draws a rectangle its origin is a point of.
Node_HasOrigin :: proc(node: ^Node) -> bool {
	if node == nil do return false
	switch node.typeId {
	case TextureNode, FrameAnimationNode, AnimationPlayerNode, NineSliceNode, TextNode: return true
	}
	return false
}

// Node_OriginSize: the size (unscaled px) of what the node draws now - the
// rectangle its pivot is a fraction of ({} when it draws nothing yet).
Node_OriginSize :: proc(node: ^Node, ctx: ^GameContext = nil) -> [2]f32 {
	switch node.typeId {
	case TextureNode:
		return (cast(^TextureNode)node).size
	case FrameAnimationNode:
		fan := cast(^FrameAnimationNode)node
		if len(fan.frames) == 0 do return {}
		t := fan.frames[int(fan.currentFrame) % len(fan.frames)]
		if t == nil do return {}
		return Texture_Size(t)
	case AnimationPlayerNode:
		apn := cast(^AnimationPlayerNode)node
		return Animation_FrameSize(AnimationPlayerNode_GetAnimation(apn), apn.currentFrame)
	case NineSliceNode:
		return (cast(^NineSliceNode)node).size
	case TextNode:
		_, size, _ := TextNode_Layout(cast(^TextNode)node, ctx)
		return size
	}
	return {}
}

// Node_OriginPx: the origin in px from the top-left of a drawn rectangle of
// `size` (unscaled).
Node_OriginPx :: proc(node: ^Node, size: [2]f32) -> [2]f32 {
	if node.typeId == TextureNode {
		if o := (cast(^TextureNode)node).origin; o != {0, 0} do return o // the pixel override
	}
	return node.pivot * size
}

// Node_SetOriginPx sets the origin from pixels of the drawn rectangle.
Node_SetOriginPx :: proc(node: ^Node, px: [2]f32, size: [2]f32) {
	node.pivot = {px.x / size.x if size.x != 0 else 0.5, px.y / size.y if size.y != 0 else 0.5}
	if node.typeId == TextureNode do (cast(^TextureNode)node).origin = {}
}
