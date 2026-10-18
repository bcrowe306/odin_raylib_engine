package keymap

import "core:testing"

@(test)
test_bind_and_resolve :: proc(t: ^testing.T) {
	km := keymap_init()
	defer keymap_destroy(&km)

	keymap_bind(&km, Chord{.A, {.Ctrl}}, .SelectAll)
	action, ok := keymap_resolve(&km, Chord{.A, {.Ctrl}})
	testing.expect(t, ok, "expected chord to resolve")
	testing.expect_value(t, action, Action.SelectAll)
}

@(test)
test_resolve_unbound_chord_fails :: proc(t: ^testing.T) {
	km := keymap_init()
	defer keymap_destroy(&km)

	_, ok := keymap_resolve(&km, Chord{.Z, {.Ctrl, .Alt}})
	testing.expect(t, !ok, "expected unbound chord to fail resolution")
}

@(test)
test_rebind_overwrites :: proc(t: ^testing.T) {
	km := keymap_init()
	defer keymap_destroy(&km)

	keymap_bind(&km, Chord{.S, {.Ctrl}}, .Save)
	keymap_bind(&km, Chord{.S, {.Ctrl}}, .SaveAs)
	action, ok := keymap_resolve(&km, Chord{.S, {.Ctrl}})
	testing.expect(t, ok, "expected chord to resolve")
	testing.expect_value(t, action, Action.SaveAs)
}

@(test)
test_unbind_removes_chord :: proc(t: ^testing.T) {
	km := keymap_init()
	defer keymap_destroy(&km)

	keymap_bind(&km, Chord{.U, {.Ctrl}}, .Undo)
	keymap_unbind(&km, Chord{.U, {.Ctrl}})
	_, ok := keymap_resolve(&km, Chord{.U, {.Ctrl}})
	testing.expect(t, !ok, "expected chord to be unbound")
}

@(test)
test_default_keymap_other_platform_core_bindings :: proc(t: ^testing.T) {
	km := keymap_default(.Other)
	defer keymap_destroy(&km)

	cases := [][2]any{
		{Chord{.Left, {}}, Action.MoveLeft},
		{Chord{.Right, {.Shift}}, Action.ExtendRight},
		{Chord{.Z, {.Ctrl}}, Action.Undo},
		{Chord{.Z, {.Ctrl, .Shift}}, Action.Redo},
		{Chord{.Y, {.Ctrl}}, Action.Redo},
		{Chord{.S, {.Ctrl}}, Action.Save},
		{Chord{.A, {.Ctrl}}, Action.SelectAll},
		{Chord{.Left, {.Ctrl}}, Action.MoveWordLeft},
		{Chord{.Backspace, {}}, Action.Backspace},
		{Chord{.Tab, {}}, Action.IndentOrTab},
		{Chord{.Tab, {.Shift}}, Action.Outdent},
	}

	for case_ in cases {
		chord := case_[0].(Chord)
		expected := case_[1].(Action)
		action, ok := keymap_resolve(&km, chord)
		testing.expectf(t, ok, "expected chord %v to be bound", chord)
		testing.expect_value(t, action, expected)
	}
}

@(test)
test_default_keymap_macos_uses_super_and_alt :: proc(t: ^testing.T) {
	km := keymap_default(.MacOS)
	defer keymap_destroy(&km)

	action, ok := keymap_resolve(&km, Chord{.S, {.Super}})
	testing.expect(t, ok, "expected Cmd+S to be bound on macOS")
	testing.expect_value(t, action, Action.Save)

	action2, ok2 := keymap_resolve(&km, Chord{.Left, {.Alt}})
	testing.expect(t, ok2, "expected Alt+Left to be bound on macOS")
	testing.expect_value(t, action2, Action.MoveWordLeft)

	// Ctrl+S should NOT be bound to Save on macOS (Super is primary there).
	_, ok3 := keymap_resolve(&km, Chord{.S, {.Ctrl}})
	testing.expect(t, !ok3, "expected Ctrl+S to be unbound on macOS")

	// Cmd+Y is not a redo binding on macOS (only Cmd+Shift+Z is).
	_, ok4 := keymap_resolve(&km, Chord{.Y, {.Super}})
	testing.expect(t, !ok4, "expected Cmd+Y to be unbound on macOS")
}
