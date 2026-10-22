package engine

import "core:encoding/json"
import "core:fmt"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Project input actions: games query named actions ("jump", "move_left")
// instead of raw keys; project.json maps each action to bindings.
//
//   "input": {"actions": [
//     {"name": "jump", "bindings": [{"key": "SPACE"}, {"button": "RIGHT_FACE_DOWN"}]},
//     {"name": "move_left", "bindings": [{"key": "A"}, {"axis": "LEFT_X", "positive": false, "deadzone": 0.25}]},
//     {"name": "fire", "bindings": [{"mouse": "LEFT"}]}]}
//
// Names of the built-in actions (move_up, move_down, move_left, move_right,
// jump, fire, secondary, boost, interact, pause, confirm, cancel,
// custom1..4) rebind those; any other name defines a new action. Lua:
// Input.is_action_down/pressed/released(name), Input.get_axis(neg, pos).
// ============================================================================

Named_Action :: struct {
	name:    string,
	mapping: ActionMapping,
	state:   ActionState,
}

// Builtin_ActionName: the project/Lua name of a built-in action.
Builtin_ActionName :: proc(a: InputAction) -> string {
	switch a {
	case .MoveUp: return "move_up"
	case .MoveDown: return "move_down"
	case .MoveLeft: return "move_left"
	case .MoveRight: return "move_right"
	case .Jump: return "jump"
	case .Fire: return "fire"
	case .SecondaryAction: return "secondary"
	case .Boost: return "boost"
	case .Interact: return "interact"
	case .Pause: return "pause"
	case .Confirm: return "confirm"
	case .Cancel: return "cancel"
	case .Custom1: return "custom1"
	case .Custom2: return "custom2"
	case .Custom3: return "custom3"
	case .Custom4: return "custom4"
	}
	return ""
}

Builtin_ActionByName :: proc(name: string) -> (InputAction, bool) {
	lower := strings.to_lower(name, context.temp_allocator)
	for a in InputAction do if Builtin_ActionName(a) == lower do return a, true
	switch lower {
	case "up": return .MoveUp, true
	case "down": return .MoveDown, true
	case "left": return .MoveLeft, true
	case "right": return .MoveRight, true
	case "shoot": return .Fire, true
	case "secondary_action": return .SecondaryAction, true
	}
	return .MoveUp, false
}

Input_FindNamed :: proc(input: ^InputSystem, name: string) -> ^Named_Action {
	for &n in input.named do if strings.equal_fold(n.name, name) do return &n
	return nil
}

// Input_ActionStateByName: state of a built-in or project action.
Input_ActionStateByName :: proc(input: ^InputSystem, name: string) -> (ActionState, bool) {
	if input == nil do return {}, false
	if n := Input_FindNamed(input, name); n != nil do return n.state, true
	if a, ok := Builtin_ActionByName(name); ok do return input.states[a], true
	return {}, false
}

// Input_DefineAction adds (or replaces the bindings of) a project action.
Input_DefineAction :: proc(input: ^InputSystem, name: string, bindings: []InputBinding) {
	if a, ok := Builtin_ActionByName(name); ok && Input_FindNamed(input, name) == nil {
		Input_ClearActionBindings(input, a)
		for b in bindings do Input_AddBinding(input, a, b)
		return
	}
	n := Input_FindNamed(input, name)
	if n == nil {
		if input.named == nil do input.named = make([dynamic]Named_Action)
		append(&input.named, Named_Action{name = strings.clone(name)})
		n = &input.named[len(input.named) - 1]
	}
	n.mapping = {}
	for b in bindings {
		if n.mapping.bindingCount >= MAX_BINDINGS_PER_ACTION do break
		n.mapping.bindings[n.mapping.bindingCount] = b
		n.mapping.bindingCount += 1
	}
}

Input_ClearNamed :: proc(input: ^InputSystem) {
	for n in input.named do delete(n.name)
	clear(&input.named)
}

// Input_UpdateNamed evaluates the project actions (called by InputSystem_Update).
Input_UpdateNamed :: proc(input: ^InputSystem, deltaTime: f32) {
	for &n in input.named {
		prev := n.state
		down := false
		strength: f32 = 0
		for i in 0 ..< n.mapping.bindingCount {
			d, s := Input_EvaluateBinding(input, n.mapping.bindings[i])
			if d {
				down = true
				strength = max(strength, s)
			}
		}
		n.state = {
			pressed      = down && !prev.down,
			down         = down,
			released     = !down && prev.down,
			value        = strength if down else 0,
			durationHeld = (prev.durationHeld + deltaTime) if down else 0,
		}
	}
}

// --- binding text / JSON -----------------------------------------------------------

@(private = "file")
enum_name :: proc(v: $T) -> string {
	name, _ := reflect.enum_name_from_value(v)
	return name
}

@(private = "file")
enum_parse :: proc($T: typeid, name: string) -> (T, bool) {
	return reflect.enum_from_name(T, strings.to_upper(name, context.temp_allocator))
}

// InputBinding_Text: "Key A", "Mouse LEFT", "Pad RIGHT_FACE_DOWN", "Axis LEFT_X+".
InputBinding_Text :: proc(b: InputBinding, allocator := context.temp_allocator) -> string {
	switch b.deviceType {
	case .KeyboardKey:   return fmt.aprintf("Key %s", enum_name(b.key), allocator = allocator)
	case .MouseButton:   return fmt.aprintf("Mouse %s", enum_name(b.mouseButton), allocator = allocator)
	case .GamepadButton: return fmt.aprintf("Pad %s", enum_name(b.gamepadButton), allocator = allocator)
	case .GamepadAxis:   return fmt.aprintf("Axis %s%s", enum_name(b.gamepadAxis), "+" if b.axisPositive else "-", allocator = allocator)
	case .None:
	}
	return "None"
}

InputBinding_WriteJSON :: proc(sb: ^strings.Builder, b: InputBinding) {
	switch b.deviceType {
	case .KeyboardKey:   fmt.sbprintf(sb, "{{\"key\": \"%s\"}}", enum_name(b.key))
	case .MouseButton:   fmt.sbprintf(sb, "{{\"mouse\": \"%s\"}}", enum_name(b.mouseButton))
	case .GamepadButton: fmt.sbprintf(sb, "{{\"button\": \"%s\"}}", enum_name(b.gamepadButton))
	case .GamepadAxis:   fmt.sbprintf(sb, "{{\"axis\": \"%s\", \"positive\": %t, \"deadzone\": %.2f}}", enum_name(b.gamepadAxis), b.axisPositive, b.axisDeadzone)
	case .None:          strings.write_string(sb, "{}")
	}
}

InputBinding_FromJSON :: proc(obj: json.Object) -> (b: InputBinding, ok: bool) {
	str :: proc(obj: json.Object, k: string) -> string {
		s, _ := obj[k].(json.String)
		return string(s)
	}
	if k := str(obj, "key"); k != "" {
		b.key, ok = enum_parse(rl.KeyboardKey, k)
		b.deviceType = .KeyboardKey
		return
	}
	if m := str(obj, "mouse"); m != "" {
		b.mouseButton, ok = enum_parse(rl.MouseButton, m)
		b.deviceType = .MouseButton
		return
	}
	if p := str(obj, "button"); p != "" {
		b.gamepadButton, ok = enum_parse(rl.GamepadButton, p)
		b.deviceType = .GamepadButton
		return
	}
	if a := str(obj, "axis"); a != "" {
		b.gamepadAxis, ok = enum_parse(rl.GamepadAxis, a)
		b.deviceType = .GamepadAxis
		pos, _ := obj["positive"].(json.Boolean)
		b.axisPositive = bool(pos)
		b.axisDeadzone = 0.25
		#partial switch d in obj["deadzone"] {
		case json.Float: b.axisDeadzone = f32(d)
		case json.Integer: b.axisDeadzone = f32(d)
		}
		return
	}
	return {}, false
}

// Input_Action_Config: one action as stored in project.json.
Input_Action_Config :: struct {
	name:     string,
	bindings: [dynamic]InputBinding,
}

// Input_DefaultActionConfigs: the built-in actions with default bindings
// (what a project without an "input" section uses).
Input_DefaultActionConfigs :: proc(allocator := context.allocator) -> [dynamic]Input_Action_Config {
	tmp: InputSystem
	Input_ResetDefaultBindings(&tmp)
	out := make([dynamic]Input_Action_Config, allocator)
	for a in InputAction {
		cfg := Input_Action_Config{name = strings.clone(Builtin_ActionName(a), allocator), bindings = make([dynamic]InputBinding, allocator)}
		m := tmp.mappings[a]
		for i in 0 ..< m.bindingCount do append(&cfg.bindings, m.bindings[i])
		append(&out, cfg)
	}
	return out
}

Input_ActionConfigs_Destroy :: proc(list: ^[dynamic]Input_Action_Config, allocator := context.allocator) {
	for a in list {
		delete(a.name, allocator)
		delete(a.bindings)
	}
	delete(list^)
	list^ = nil
}

// Input_ApplyActionConfigs installs a project's actions.
Input_ApplyActionConfigs :: proc(input: ^InputSystem, actions: []Input_Action_Config) {
	if len(actions) == 0 do return
	Input_ClearNamed(input)
	for a in actions do Input_DefineAction(input, a.name, a.bindings[:])
}
