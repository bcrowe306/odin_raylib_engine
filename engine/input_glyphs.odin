package engine

import "core:fmt"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Button prompts (TODO E.4): Input.glyph("jump") is the image of the button
// the player presses for an action, for the device they use now - Space on
// the keyboard, A on an Xbox pad, Cross on a PlayStation one, B (bottom) on
// a Switch... Kenney's Input Prompts (CC0, engine/prompts) are
// in the engine; the path is "prompts:<family>/<name>" (any image path
// takes it: TextureNode, UI images, set_texture), e.g.
// "prompts:xbox/xbox_button_a". Families: keyboard (keys and mouse), xbox,
// playstation, switch, steamdeck; other pads use the Xbox images (raylib
// maps every pad to that layout).
// ============================================================================

PROMPTS_PREFIX :: "prompts:"

@(private = "file")
Prompt_Sheet :: struct {
	family: string,
	png:    []u8,
	xml:    string,
	rects:  map[string]rl.Rectangle, // parsed when first needed
}

@(private = "file")
prompt_sheets := [?]Prompt_Sheet {
	{family = "keyboard", png = #load("prompts/keyboard.png"), xml = #load("prompts/keyboard.xml", string)},
	{family = "xbox", png = #load("prompts/xbox.png"), xml = #load("prompts/xbox.xml", string)},
	{family = "playstation", png = #load("prompts/playstation.png"), xml = #load("prompts/playstation.xml", string)},
	{family = "switch", png = #load("prompts/switch.png"), xml = #load("prompts/switch.xml", string)},
	{family = "steamdeck", png = #load("prompts/steamdeck.png"), xml = #load("prompts/steamdeck.xml", string)},
}

@(private = "file")
prompt_sheet :: proc(family: string) -> ^Prompt_Sheet {
	for &s in prompt_sheets do if s.family == family {
		if s.rects == nil do s.rects = parse_atlas(s.xml, png_height(s.png))
		return &s
	}
	return nil
}

// (A PNG's height: IHDR, big-endian, bytes 20-23.)
@(private = "file")
png_height :: proc(png: []u8) -> f32 {
	if len(png) < 24 do return 0
	return f32(u32(png[20]) << 24 | u32(png[21]) << 16 | u32(png[22]) << 8 | u32(png[23]))
}

// Kenney's <SubTexture name="..." x=".." y=".." width=".." height=".."/>;
// y counts from the sheet's bottom edge (flipped here).
@(private = "file")
parse_atlas :: proc(xml: string, sheetHeight: f32) -> map[string]rl.Rectangle {
	rects := make(map[string]rl.Rectangle, allocator = Engine_HeapAllocator())
	attr :: proc(tag, key: string) -> string {
		i := strings.index(tag, strings.concatenate({" ", key, "=\""}, context.temp_allocator))
		if i < 0 do return ""
		rest := tag[i + len(key) + 3:]
		j := strings.index_byte(rest, '"')
		return rest[:j] if j >= 0 else ""
	}
	num :: proc(s: string) -> f32 {v, _ := strconv.parse_f32(s); return v}
	rest := xml
	for {
		i := strings.index(rest, "<SubTexture")
		if i < 0 do break
		rest = rest[i:]
		j := strings.index(rest, "/>")
		if j < 0 do break
		tag := rest[:j]
		rest = rest[j:]
		name := attr(tag, "name")
		if name == "" do continue
		h := num(attr(tag, "height"))
		rects[name] = {num(attr(tag, "x")), sheetHeight - num(attr(tag, "y")) - h, num(attr(tag, "width")), h}
	}
	return rects
}

// Prompt_Exists: a "prompts:" path names an image in the sheets.
Prompt_Exists :: proc(path: string) -> bool {
	family, name, ok := split_prompt(path)
	if !ok do return false
	s := prompt_sheet(family)
	return s != nil && name in s.rects
}

@(private = "file")
split_prompt :: proc(path: string) -> (family, name: string, ok: bool) {
	if !strings.has_prefix(path, PROMPTS_PREFIX) do return
	rest := strings.trim_suffix(path[len(PROMPTS_PREFIX):], ".png")
	i := strings.index_byte(rest, '/')
	if i < 0 do return
	return rest[:i], rest[i + 1:], true
}

// Prompt_Image: a prompt's image (texture_load; the caller unloads it).
Prompt_Image :: proc(path: string) -> (rl.Image, bool) {
	family, name, ok := split_prompt(path)
	if !ok do return {}, false
	s := prompt_sheet(family)
	if s == nil do return {}, false
	r, found := s.rects[name]
	if !found do return {}, false
	sheet := rl.LoadImageFromMemory(".png", raw_data(s.png), i32(len(s.png)))
	defer rl.UnloadImage(sheet)
	if sheet.data == nil do return {}, false
	img := rl.ImageFromImage(sheet, r)
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	return img, true
}

// Prompt_Rect: where a prompt is in its family's sheet.
Prompt_Rect :: proc(path: string) -> (rl.Rectangle, bool) {
	family, name, ok := split_prompt(path)
	if !ok do return {}, false
	s := prompt_sheet(family)
	if s == nil do return {}, false
	return s.rects[name]
}

// Prompt_SheetImage: a family's whole sheet (tests; the caller unloads it).
Prompt_SheetImage :: proc(family: string) -> rl.Image {
	s := prompt_sheet(family)
	if s == nil do return {}
	return rl.LoadImageFromMemory(".png", raw_data(s.png), i32(len(s.png)))
}

// Prompt_Names: every image of a family (the docs, the editor).
Prompt_Names :: proc(family: string, allocator := context.temp_allocator) -> []string {
	s := prompt_sheet(family)
	if s == nil do return nil
	out := make([dynamic]string, 0, len(s.rects), allocator)
	for k in s.rects do append(&out, k)
	return out[:]
}

// --- which image ------------------------------------------------------------------

// Input_Glyph: the prompt path for an action - its first binding for the
// device (keyboard: a key or mouse button; a pad family: a button or
// stick direction). device "": the player's device now. "" when the action
// has no binding for it.
Input_Glyph :: proc(input: ^InputSystem, action: string, player := 1, device := "") -> string {
	m := Input_MappingOf(input, action)
	if m == nil do return ""
	dev := device if device != "" else Input_PlayerDevice(input, player)
	padName := Input_PadName(input, Input_PlayerPad(input, player))
	for i in 0 ..< m.bindingCount {
		p := Binding_Glyph(m.bindings[i], dev, padName)
		if p != "" do return p
	}
	return ""
}

// Binding_Glyph: a binding's prompt path for a device ("" if the binding
// isn't for it).
Binding_Glyph :: proc(b: InputBinding, device: string, padName := "") -> string {
	family := device
	if family == "generic" || family == "none" do family = "xbox"
	name := ""
	switch b.deviceType {
	case .None:
	case .KeyboardKey: if family == "keyboard" do name = key_glyph(b.key)
	case .MouseButton: if family == "keyboard" do name = mouse_glyph(b.mouseButton)
	case .GamepadButton: if family != "keyboard" do name = button_glyph(family, b.gamepadButton, padName)
	case .GamepadAxis: if family != "keyboard" do name = axis_glyph(family, b.gamepadAxis, b.axisPositive)
	}
	if name == "" do return ""
	path := strings.concatenate({PROMPTS_PREFIX, family, "/", name}, context.temp_allocator)
	return path if Prompt_Exists(path) else ""
}

@(private = "file")
key_glyph :: proc(k: rl.KeyboardKey) -> string {
	#partial switch k {
	case .APOSTROPHE: return "keyboard_apostrophe"
	case .COMMA, .KP_DECIMAL: return "keyboard_comma" if k == .COMMA else "keyboard_period"
	case .MINUS, .KP_SUBTRACT: return "keyboard_minus"
	case .PERIOD: return "keyboard_period"
	case .SLASH, .KP_DIVIDE: return "keyboard_slash_forward"
	case .BACKSLASH: return "keyboard_slash_back"
	case .SEMICOLON: return "keyboard_semicolon"
	case .EQUAL: return "keyboard_equals"
	case .LEFT_BRACKET: return "keyboard_bracket_open"
	case .RIGHT_BRACKET: return "keyboard_bracket_close"
	case .GRAVE: return "keyboard_tilde"
	case .SPACE: return "keyboard_space"
	case .ESCAPE: return "keyboard_escape"
	case .ENTER: return "keyboard_enter"
	case .KP_ENTER: return "keyboard_numpad_enter"
	case .KP_ADD: return "keyboard_numpad_plus"
	case .KP_MULTIPLY: return "keyboard_asterisk"
	case .TAB: return "keyboard_tab"
	case .BACKSPACE: return "keyboard_backspace"
	case .INSERT: return "keyboard_insert"
	case .DELETE: return "keyboard_delete"
	case .RIGHT: return "keyboard_arrow_right"
	case .LEFT: return "keyboard_arrow_left"
	case .DOWN: return "keyboard_arrow_down"
	case .UP: return "keyboard_arrow_up"
	case .PAGE_UP: return "keyboard_page_up"
	case .PAGE_DOWN: return "keyboard_page_down"
	case .HOME: return "keyboard_home"
	case .END: return "keyboard_end"
	case .CAPS_LOCK: return "keyboard_capslock"
	case .SCROLL_LOCK: return "keyboard_scroll_lock"
	case .NUM_LOCK: return "keyboard_numlock"
	case .PRINT_SCREEN: return "keyboard_printscreen"
	case .PAUSE: return "keyboard_pause"
	case .LEFT_SHIFT, .RIGHT_SHIFT: return "keyboard_shift"
	case .LEFT_CONTROL, .RIGHT_CONTROL: return "keyboard_ctrl"
	case .LEFT_ALT, .RIGHT_ALT: return "keyboard_option" if ODIN_OS == .Darwin else "keyboard_alt"
	case .LEFT_SUPER, .RIGHT_SUPER: return "keyboard_command" if ODIN_OS == .Darwin else "keyboard_win"
	}
	v := int(k)
	switch {
	case v >= int(rl.KeyboardKey.A) && v <= int(rl.KeyboardKey.Z):
		return strings.concatenate({"keyboard_", string([]u8{u8('a' + v - int(rl.KeyboardKey.A))})}, context.temp_allocator)
	case v >= int(rl.KeyboardKey.ZERO) && v <= int(rl.KeyboardKey.NINE):
		return strings.concatenate({"keyboard_", string([]u8{u8('0' + v - int(rl.KeyboardKey.ZERO))})}, context.temp_allocator)
	case v >= int(rl.KeyboardKey.KP_0) && v <= int(rl.KeyboardKey.KP_9):
		return strings.concatenate({"keyboard_", string([]u8{u8('0' + v - int(rl.KeyboardKey.KP_0))})}, context.temp_allocator)
	case v >= int(rl.KeyboardKey.F1) && v <= int(rl.KeyboardKey.F12):
		return fmt.tprintf("keyboard_f%d", v - int(rl.KeyboardKey.F1) + 1)
	}
	return ""
}

@(private = "file")
mouse_glyph :: proc(m: rl.MouseButton) -> string {
	#partial switch m {
	case .LEFT: return "mouse_left"
	case .RIGHT: return "mouse_right"
	case .MIDDLE: return "mouse_scroll"
	case .SIDE, .BACK: return "mouse_side_back"
	case .EXTRA, .FORWARD: return "mouse_side_forward"
	}
	return "mouse"
}

// raylib's buttons are positions (RIGHT_FACE_DOWN: the bottom face button).
@(private = "file")
button_glyph :: proc(family: string, b: rl.GamepadButton, padName: string) -> string {
	@(static) xbox := [rl.GamepadButton]string {
		.UNKNOWN = "", .LEFT_FACE_UP = "xbox_dpad_up", .LEFT_FACE_RIGHT = "xbox_dpad_right",
		.LEFT_FACE_DOWN = "xbox_dpad_down", .LEFT_FACE_LEFT = "xbox_dpad_left",
		.RIGHT_FACE_UP = "xbox_button_y", .RIGHT_FACE_RIGHT = "xbox_button_b",
		.RIGHT_FACE_DOWN = "xbox_button_a", .RIGHT_FACE_LEFT = "xbox_button_x",
		.LEFT_TRIGGER_1 = "xbox_lb", .LEFT_TRIGGER_2 = "xbox_lt", .RIGHT_TRIGGER_1 = "xbox_rb",
		.RIGHT_TRIGGER_2 = "xbox_rt", .MIDDLE_LEFT = "xbox_button_view", .MIDDLE = "xbox_guide",
		.MIDDLE_RIGHT = "xbox_button_menu", .LEFT_THUMB = "xbox_stick_l_press", .RIGHT_THUMB = "xbox_stick_r_press",
	}
	@(static) ps := [rl.GamepadButton]string {
		.UNKNOWN = "", .LEFT_FACE_UP = "playstation_dpad_up", .LEFT_FACE_RIGHT = "playstation_dpad_right",
		.LEFT_FACE_DOWN = "playstation_dpad_down", .LEFT_FACE_LEFT = "playstation_dpad_left",
		.RIGHT_FACE_UP = "playstation_button_triangle", .RIGHT_FACE_RIGHT = "playstation_button_circle",
		.RIGHT_FACE_DOWN = "playstation_button_cross", .RIGHT_FACE_LEFT = "playstation_button_square",
		.LEFT_TRIGGER_1 = "playstation_trigger_l1", .LEFT_TRIGGER_2 = "playstation_trigger_l2",
		.RIGHT_TRIGGER_1 = "playstation_trigger_r1", .RIGHT_TRIGGER_2 = "playstation_trigger_r2",
		.MIDDLE_LEFT = "playstation5_button_create", .MIDDLE = "",
		.MIDDLE_RIGHT = "playstation5_button_options", .LEFT_THUMB = "playstation_stick_l_press", .RIGHT_THUMB = "playstation_stick_r_press",
	}
	@(static) sw := [rl.GamepadButton]string {
		.UNKNOWN = "", .LEFT_FACE_UP = "switch_dpad_up", .LEFT_FACE_RIGHT = "switch_dpad_right",
		.LEFT_FACE_DOWN = "switch_dpad_down", .LEFT_FACE_LEFT = "switch_dpad_left",
		// Nintendo's letters sit elsewhere: bottom B, right A, top X, left Y.
		.RIGHT_FACE_UP = "switch_button_x", .RIGHT_FACE_RIGHT = "switch_button_a",
		.RIGHT_FACE_DOWN = "switch_button_b", .RIGHT_FACE_LEFT = "switch_button_y",
		.LEFT_TRIGGER_1 = "switch_button_l", .LEFT_TRIGGER_2 = "switch_button_zl",
		.RIGHT_TRIGGER_1 = "switch_button_r", .RIGHT_TRIGGER_2 = "switch_button_zr",
		.MIDDLE_LEFT = "switch_button_minus", .MIDDLE = "switch_button_home",
		.MIDDLE_RIGHT = "switch_button_plus", .LEFT_THUMB = "switch_stick_l_press", .RIGHT_THUMB = "switch_stick_r_press",
	}
	@(static) deck := [rl.GamepadButton]string {
		.UNKNOWN = "", .LEFT_FACE_UP = "steamdeck_dpad_up", .LEFT_FACE_RIGHT = "steamdeck_dpad_right",
		.LEFT_FACE_DOWN = "steamdeck_dpad_down", .LEFT_FACE_LEFT = "steamdeck_dpad_left",
		.RIGHT_FACE_UP = "steamdeck_button_y", .RIGHT_FACE_RIGHT = "steamdeck_button_b",
		.RIGHT_FACE_DOWN = "steamdeck_button_a", .RIGHT_FACE_LEFT = "steamdeck_button_x",
		.LEFT_TRIGGER_1 = "steamdeck_button_l1", .LEFT_TRIGGER_2 = "steamdeck_button_l2",
		.RIGHT_TRIGGER_1 = "steamdeck_button_r1", .RIGHT_TRIGGER_2 = "steamdeck_button_r2",
		.MIDDLE_LEFT = "steamdeck_button_view", .MIDDLE = "steamdeck_button_guide",
		.MIDDLE_RIGHT = "steamdeck_button_options", .LEFT_THUMB = "steamdeck_stick_l_press", .RIGHT_THUMB = "steamdeck_stick_r_press",
	}
	switch family {
	case "playstation":
		// A DualShock 4 (macOS: "Wireless Controller") has Share / Options.
		n := strings.to_lower(padName, context.temp_allocator)
		ds4 := strings.contains(n, "dualshock") || strings.contains(n, "ps4") || n == "wireless controller"
		if ds4 && b == .MIDDLE_LEFT do return "playstation4_button_share"
		if ds4 && b == .MIDDLE_RIGHT do return "playstation4_button_options"
		return ps[b]
	case "switch": return sw[b]
	case "steamdeck": return deck[b]
	}
	return xbox[b]
}

@(private = "file")
axis_glyph :: proc(family: string, a: rl.GamepadAxis, positive: bool) -> string {
	prefix := "xbox"
	switch family {
	case "playstation": prefix = "playstation"
	case "switch": prefix = "switch"
	case "steamdeck": prefix = "steamdeck"
	}
	stick :: proc(prefix, side: string, a: rl.GamepadAxis, positive: bool) -> string {
		dir := ""
		if a == .LEFT_X || a == .RIGHT_X do dir = "right" if positive else "left"
		else do dir = "down" if positive else "up"
		return strings.concatenate({prefix, "_stick_", side, "_", dir}, context.temp_allocator)
	}
	switch a {
	case .LEFT_X, .LEFT_Y: return stick(prefix, "l", a, positive)
	case .RIGHT_X, .RIGHT_Y: return stick(prefix, "r", a, positive)
	case .LEFT_TRIGGER, .RIGHT_TRIGGER:
		left := a == .LEFT_TRIGGER
		switch family {
		case "playstation": return "playstation_trigger_l2" if left else "playstation_trigger_r2"
		case "switch": return "switch_button_zl" if left else "switch_button_zr"
		case "steamdeck": return "steamdeck_button_l2" if left else "steamdeck_button_r2"
		}
		return "xbox_lt" if left else "xbox_rt"
	}
	return ""
}
