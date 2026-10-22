package engine

import "core:testing"

@(test)
test_batch_order :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("batch", true)
	texA := new(Texture, context.temp_allocator)
	texA.texture.id = 11
	texB := new(Texture, context.temp_allocator)
	texB.texture.id = 22
	sprite :: proc(scene: ^Scene, name: string, tex: ^Texture, x, y: f32) -> ^Node {
		tn := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
		tn.name = name
		tn.texture = tex
		tn.size = {10, 10}
		tn.origin = {0, 0}
		tn.globalPosition = {x, y}
		tn.globalScale = {1, 1}
		return tn
	}
	names :: proc(nodes: []^Node) -> string {
		s := ""
		for n in nodes do s = concat(s, n.name)
		return s
	}

	// Separate sprites, textures interleaved: grouped by texture.
	a1 := sprite(scene, "a1", texA, 0, 0)
	b1 := sprite(scene, "b1", texB, 20, 0)
	a2 := sprite(scene, "a2", texA, 40, 0)
	b2 := sprite(scene, "b2", texB, 60, 0)
	testing.expect_value(t, names(Render_BatchOrder({a1, b1, a2, b2})), "a1a2b1b2")

	// a2 overlaps b1 (drawn before it): a2 stays after b1; b2 (clear of a2)
	// joins b1.
	a2.globalPosition = {25, 0}
	testing.expect_value(t, names(Render_BatchOrder({a1, b1, a2, b2})), "a1b1b2a2")
	// b2 under a2 too: nothing moves.
	b2.globalPosition = {30, 0}
	testing.expect_value(t, names(Render_BatchOrder({a1, b1, a2, b2})), "a1b1a2b2")
	b2.globalPosition = {60, 0}

	// A draw without bounds is a barrier.
	a2.globalPosition = {40, 0}
	barrier := Node_CreateByTypeName(scene, "Node")
	barrier.name = "x"
	testing.expect_value(t, names(Render_BatchOrder({a1, b1, barrier, a2, b2})), "a1b1xa2b2")

	// A sprite with a material keeps its place but can be passed.
	m := sprite(scene, "m", texA, 100, 0)
	Material_SetShader(m, "builtin:grayscale")
	testing.expect_value(t, names(Render_BatchOrder({a1, m, a2, b1})), "a1a2mb1")
	m.globalPosition = {40, 0} // now under a2: a2 can't pass it
	testing.expect_value(t, names(Render_BatchOrder({a1, m, a2, b1})), "a1ma2b1")
}

@(private = "file")
concat :: proc(a, b: string) -> string {
	out := make([]u8, len(a) + len(b), context.temp_allocator)
	copy(out, a)
	copy(out[len(a):], b)
	return string(out)
}
