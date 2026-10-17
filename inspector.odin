package main

import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "base:runtime"
import rl "vendor:raylib"

DockSide :: enum {
	Left,
	Right,
}

engineGuiFont: rl.Font

DrawEngineText :: proc(text: cstring, x, y: f32, size: f32, color: rl.Color) {
	if engineGuiFont.baseSize > 0 {
		rl.DrawTextEx(engineGuiFont, text, {x, y}, size, 1, color)
	} else {
		rl.DrawText(text, i32(x), i32(y), i32(size), color)
	}
}

ApplyMaterialDarkTheme :: proc(font: rl.Font) {
	engineGuiFont = font
	rl.GuiSetFont(font)
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiDefaultProperty.TEXT_SIZE, 15)
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BORDER_WIDTH, 1)

	// Normal State (Flat Google Material Dark 900 / 800)
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BORDER_COLOR_NORMAL, cast(i32)rl.ColorToInt(rl.Color{68, 71, 79, 255}))       // #44474F
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BASE_COLOR_NORMAL, cast(i32)rl.ColorToInt(rl.Color{30, 31, 35, 255}))         // #1E1F23
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.TEXT_COLOR_NORMAL, cast(i32)rl.ColorToInt(rl.Color{226, 226, 233, 255}))     // #E2E2E9

	// Focused / Hover State
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BORDER_COLOR_FOCUSED, cast(i32)rl.ColorToInt(rl.Color{138, 142, 153, 255}))  // #8A8E99
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BASE_COLOR_FOCUSED, cast(i32)rl.ColorToInt(rl.Color{45, 47, 53, 255}))        // #2D2F35
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.TEXT_COLOR_FOCUSED, cast(i32)rl.ColorToInt(rl.Color{255, 255, 255, 255}))     // #FFFFFF

	// Pressed / Active State (Material Blue Accent)
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BORDER_COLOR_PRESSED, cast(i32)rl.ColorToInt(rl.Color{110, 168, 254, 255})) // #6EA8FE
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BASE_COLOR_PRESSED, cast(i32)rl.ColorToInt(rl.Color{37, 99, 235, 255}))       // #2563EB
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.TEXT_COLOR_PRESSED, cast(i32)rl.ColorToInt(rl.Color{255, 255, 255, 255}))

	// Disabled State
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BORDER_COLOR_DISABLED, cast(i32)rl.ColorToInt(rl.Color{45, 47, 53, 255}))
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.BASE_COLOR_DISABLED, cast(i32)rl.ColorToInt(rl.Color{24, 25, 28, 255}))
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiControlProperty.TEXT_COLOR_DISABLED, cast(i32)rl.ColorToInt(rl.Color{115, 117, 126, 255}))

	// Background & Line Colors
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiDefaultProperty.BACKGROUND_COLOR, cast(i32)rl.ColorToInt(rl.Color{20, 21, 23, 255}))          // Surface container lowest
	rl.GuiSetStyle(.DEFAULT, cast(i32)rl.GuiDefaultProperty.LINE_COLOR, cast(i32)rl.ColorToInt(rl.Color{55, 57, 63, 255}))                // Clean thin outline

	// Control specific tuning
	rl.GuiSetStyle(.SLIDER, cast(i32)rl.GuiSliderProperty.SLIDER_WIDTH, 14)
	rl.GuiSetStyle(.SLIDER, cast(i32)rl.GuiSliderProperty.SLIDER_PADDING, 2)
}

DrawGenericStructGui :: proc(target: any, x: f32, nextY: ^f32, width: f32, labelWidth: f32 = 140, sliderHeight: f32 = 18, yPadding: f32 = 4) -> int {
	ti := type_info_of(target.id)
	base_ti := reflect.type_info_base(ti)

	struct_typeid: typeid
	struct_ptr: uintptr

	#partial switch v in base_ti.variant {
	case runtime.Type_Info_Pointer:
		elem := reflect.type_info_base(v.elem)
		struct_typeid = elem.id
		struct_ptr = uintptr((^rawptr)(target.data)^)
	case runtime.Type_Info_Struct:
		struct_typeid = base_ti.id
		struct_ptr = uintptr(target.data)
	case:
		return 0
	}

	fieldCount := reflect.struct_field_count(struct_typeid, .Top_Level)
	rendered := 0
	controlWidth := width - labelWidth

	for i in 0..<fieldCount {
		field := reflect.struct_field_at(struct_typeid, i)
		guiTag := reflect.struct_tag_get(field.tag, "gui")
		if guiTag == "" {
			continue
		}

		minStr := reflect.struct_tag_get(field.tag, "min")
		maxStr := reflect.struct_tag_get(field.tag, "max")
		fieldPtr := struct_ptr + field.offset

		#partial switch v in field.type.variant {
		case runtime.Type_Info_Float:
			valuef := cast(^f32)fieldPtr
			minf: f32 = 0
			maxf: f32 = 1
			if minStr != "" {
				if m, ok := strconv.parse_f32(minStr); ok do minf = m
			}
			if maxStr != "" {
				if m, ok := strconv.parse_f32(maxStr); ok do maxf = m
			}
			rl.GuiSlider({x + labelWidth, nextY^, controlWidth, sliderHeight}, fmt.ctprint(field.name), fmt.ctprint(valuef^), valuef, minf, maxf)
			nextY^ += sliderHeight + yPadding
			rendered += 1

		case runtime.Type_Info_Integer:
			valueI := cast(^int)fieldPtr
			valueFloat := cast(f32)valueI^
			minVal: int = 0
			maxVal: int = 100
			if minStr != "" {
				if m, ok := strconv.parse_int(minStr); ok do minVal = m
			}
			if maxStr != "" {
				if m, ok := strconv.parse_int(maxStr); ok do maxVal = m
			}
			rl.GuiSlider({x + labelWidth, nextY^, controlWidth, sliderHeight}, fmt.ctprint(field.name), fmt.ctprint(valueI^), &valueFloat, f32(minVal), f32(maxVal))
			valueI^ = int(valueFloat)
			nextY^ += sliderHeight + yPadding
			rendered += 1

		case runtime.Type_Info_Boolean:
			valueB := cast(^bool)fieldPtr
			rl.GuiCheckBox({x + labelWidth, nextY^, sliderHeight, sliderHeight}, fmt.ctprint(field.name), valueB)
			nextY^ += sliderHeight + yPadding
			rendered += 1

		case runtime.Type_Info_Array:
			for j in 0..<v.count {
				elemPtr := fieldPtr + uintptr(j) * uintptr(v.elem_size)
				#partial switch var in v.elem.variant {
				case runtime.Type_Info_Float:
					valuef := cast(^f32)elemPtr
					minf: f32 = 0
					maxf: f32 = 1
					if minStr != "" {
						if m, ok := strconv.parse_f32(minStr); ok do minf = m
					}
					if maxStr != "" {
						if m, ok := strconv.parse_f32(maxStr); ok do maxf = m
					}
					nameLabel := fmt.ctprint(field.name, "[", j, "]")
					rl.GuiSlider({x + labelWidth, nextY^, controlWidth, sliderHeight}, nameLabel, fmt.ctprint(valuef^), valuef, minf, maxf)
					nextY^ += sliderHeight + yPadding
					rendered += 1
				}
			}

		case runtime.Type_Info_Named:
			base_info := reflect.type_info_base(v.base)
			#partial switch vv in base_info.variant {
			case runtime.Type_Info_Enum:
				valueI := cast(^int)fieldPtr
				active := i32(valueI^)
				namesJoined := strings.join(vv.names, ";")
				if rl.GuiDropdownBox({x + labelWidth, nextY^, controlWidth, sliderHeight}, fmt.ctprint(namesJoined), &active, dropdownEdit) {
					dropdownEdit = !dropdownEdit
				}
				valueI^ = int(active)
				nextY^ += sliderHeight + yPadding
				rendered += 1

			case runtime.Type_Info_Array:
				if field.type.id == rl.Color {
					c := cast(^rl.Color)fieldPtr
					alpha := f32(c^.a) / 255.0
					colorBoxHeight: f32 = 50
					rl.GuiColorPicker({x + labelWidth, nextY^, controlWidth, colorBoxHeight}, fmt.ctprint(field.name), c)
					nextY^ += colorBoxHeight + yPadding
					rl.GuiColorBarAlpha({x + labelWidth, nextY^, controlWidth, sliderHeight}, "Alpha", &alpha)
					c.a = u8(alpha * 255.0)
					nextY^ += sliderHeight + yPadding
					rendered += 1
				}
			}
		}
	}

	return rendered
}
