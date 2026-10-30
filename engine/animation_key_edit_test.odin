package engine

import "core:testing"

// #177: keys moved in time (several at once, onto other keys) and put whole
// (pasted / duplicated with their curves and text).
@(test)
test_track_move_and_put_keys :: proc(t: ^testing.T) {
	tr := Property_Track{keys = make([dynamic]Track_Key, context.temp_allocator)}
	Track_SetKey(&tr, 0, {0, 0, 0, 0})
	Track_SetKey(&tr, 0.5, {50, 0, 0, 0})
	Track_SetKey(&tr, 1, {100, 0, 0, 0})
	tr.keys[1].ease = .In_Quad

	// Two keys later by 0.25 s: they keep their values, easing, order.
	Track_MoveKeys(&tr, {0, 0.5}, 0.25)
	testing.expect_value(t, len(tr.keys), 3)
	testing.expect_value(t, tr.keys[0].time, 0.25)
	testing.expect_value(t, tr.keys[1].time, 0.75)
	testing.expect_value(t, tr.keys[1].ease, Ease.In_Quad)
	testing.expect_value(t, tr.keys[2].value[0], 100)

	// Onto another key: the moved one replaces it.
	Track_MoveKeys(&tr, {0.75}, 0.25)
	testing.expect_value(t, len(tr.keys), 2)
	testing.expect_value(t, tr.keys[1].time, 1)
	testing.expect_value(t, tr.keys[1].value[0], 50)

	// Never before 0: the whole group stops there.
	Track_MoveKeys(&tr, {0.25, 1}, -1)
	testing.expect_value(t, tr.keys[0].time, 0)
	testing.expect_value(t, tr.keys[1].time, 0.75)

	// A whole key (a paste): replaces the one at its time, sorted in.
	k := tr.keys[1]
	k.time = 0
	k.text = "x"
	Track_PutKey(&tr, k)
	testing.expect_value(t, len(tr.keys), 2)
	testing.expect_value(t, tr.keys[0].value[0], 50)
	k.time = 0.5
	Track_PutKey(&tr, k)
	testing.expect_value(t, len(tr.keys), 3)
	testing.expect_value(t, tr.keys[1].time, 0.5)
}

@(test)
test_property_enum_names :: proc(t: ^testing.T) {
	em := ParticleEmitter{}
	p := Node_Property{name = "shape", kind = .Enum, ptr = &em.shape, type = type_info_of(ParticleShape)}
	names := Property_EnumNames(p)
	testing.expect_value(t, len(names), len(ParticleShape))
	testing.expect_value(t, names[2], "Rectangle")
	Property_SetTrackValue(p, {2, 0, 0, 0})
	testing.expect_value(t, em.shape, ParticleShape.Rectangle)
	testing.expect(t, Property_EnumNames(Node_Property{kind = .Float, type = type_info_of(f32)}) == nil, "not an enum: none")
}
