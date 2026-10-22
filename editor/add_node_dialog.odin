package editor

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Add Node Modal Dialog
// Categorized node picker with real-time search and detailed node descriptions
// ============================================================================

NodeCatalogEntry :: struct {
	name:        string,
	category:    string,
	icon:        string,
	description: string,
	typeName:    string, // engine node type (see engine/node_registry.odin)
}

nodeSearchBuf: [64]u8
selectedCatalogIdx: int = 0
showAddNodeDialog: bool = false

NODE_CATALOG := [?]NodeCatalogEntry{
	// 1. Core & 2D
	{
		name        = "Empty Node",
		category    = "Core & 2D",
		icon        = ICON_FA_FILE,
		description = "Basic 2D transform node with position, rotation, scale, and hierarchy grouping.",
		typeName    = "Node",
	},
	{
		name        = "Camera 2D",
		category    = "Core & 2D",
		icon        = ICON_FA_EYE,
		description = "2D Camera viewport controller supporting target tracking, zoom levels, rotation, and screen offsets.",
		typeName    = "CameraNode",
	},
	{
		name        = "Timer",
		category    = "Core & 2D",
		icon        = ICON_FA_GEAR,
		description = "Periodic and one-shot countdown timer node for delayed actions and recurring intervals.",
		typeName    = "TimerNode",
	},
	{
		name        = "Lua Script Node",
		category    = "Core & 2D",
		icon        = ICON_FA_CODE,
		description = "Dedicated Lua scripted node that automatically executes lifecycle callbacks (ready, update, render).",
		typeName    = "ScriptNode",
	},

	// 2. Graphics & Rendering
	{
		name        = "Texture Sprite",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_IMAGE,
		description = "2D textured sprite quad with texture mapping, tinting, origin offsets, and flipping.",
		typeName    = "TextureNode",
	},
	{
		name        = "Text",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_FONT,
		description = "Text in the world: any project font (or SDF for crisp scaling), wrapping, alignment, rich text ([color=..] [size=..] [wave] [shake]), localization keys and a typewriter reveal.",
		typeName    = "TextNode",
	},
	{
		name        = "Dialogue Box",
		category    = "UI & Interface",
		icon        = ICON_FA_COMMENT,
		description = "A dialogue box: lines with a speaker type out and advance with the confirm action. Scripts: box:dialogue_show({...}); events line_shown / finished.",
		typeName    = "DialogueNode",
	},
	{
		name        = "LDtk Tilemap Level",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Full LDtk level renderer for grid-based tile layers, auto-layering, and entity placement.",
		typeName    = "LdtkLevelNode",
	},
	{
		name        = "Light",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_LIGHTBULB,
		description = "2D point or spot light with colour, energy, radius and falloff; casts shadows from physics shapes. Set the scene's Ambient to darken unlit areas.",
		typeName    = "LightNode",
	},
	{
		name        = "Tile Map",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Grid of tiles from a tileset image, painted in the viewport; optional colliders.",
		typeName    = "TileMapNode",
	},

	// 3. Audio & Sound
	{
		name        = "Sound Effect",
		category    = "Audio & Sound",
		icon        = ICON_FA_MUSIC,
		description = "Audio emitter for one-shot and recurring sound effects (.wav, .ogg) with volume and pitch control.",
		typeName    = "SoundNode",
	},
	{
		name        = "Music Streamer",
		category    = "Audio & Sound",
		icon        = ICON_FA_MUSIC,
		description = "Background streaming music player with seamless looping, crossfading, and volume attenuation.",
		typeName    = "MusicNode",
	},

	// 4. Animation & Effects
	{
		name        = "Animation Player",
		category    = "Animation & Effects",
		icon        = ICON_FA_FILM,
		description = "Keyframe animation sequencer supporting property tracks, transitions, and timeline scrubbing.",
		typeName    = "AnimationPlayerNode",
	},
	{
		name        = "State Machine",
		category    = "Animation & Effects",
		icon        = ICON_FA_DIAGRAM_PROJECT,
		description = "States, transitions and conditions on parameters; each state can play an animation on an AnimationPlayer. Scripts get on_enter_<state> / on_exit_<state>.",
		typeName    = "StateMachineNode",
	},
	{
		name        = "Frame Animator",
		category    = "Animation & Effects",
		icon        = ICON_FA_FILM,
		description = "Sprite sheet frame-by-frame animator with configurable frame durations, loops, and ping-pong modes.",
		typeName    = "FrameAnimationNode",
	},
	{
		name        = "Particle Emitter",
		category    = "Animation & Effects",
		icon        = ICON_FA_CHART_LINE,
		description = "2D particle burst and fountain generator with customizable speed, spread, lifetime, and colors.",
		typeName    = "ParticleEmitterNode",
	},

	// 5. Physics & Collision
	{
		name        = "Dynamic Physics Box",
		category    = "Physics & Collision",
		icon        = ICON_FA_CUBES,
		description = "Box2D dynamic rigid body affected by gravity, physical impulses, forces, friction, and bounce.",
		typeName    = "DynamicBodyNode",
	},
	{
		name        = "Static Platform",
		category    = "Physics & Collision",
		icon        = ICON_FA_BORDER_ALL,
		description = "Static immovable collision body that dynamic bodies collide with; perfect for ground, walls, and terrain.",
		typeName    = "StaticBodyNode",
	},
	{
		name        = "Character Mover",
		category    = "Physics & Collision",
		icon        = ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT,
		description = "Kinematic character controller with smooth velocity integration, slope climbing, and ground snapping.",
		typeName    = "CharacterMoverNode",
	},
	{
		name        = "Trigger Area",
		category    = "Physics & Collision",
		icon        = ICON_FA_EXPAND,
		description = "Physics detection volume that triggers onEnter and onExit overlap events without rigid collisions.",
		typeName    = "AreaNode",
	},
	{
		name        = "Raycast Sensor",
		category    = "Physics & Collision",
		icon        = ICON_FA_ARROW_POINTER,
		description = "Directional line-of-sight raycaster detecting intersection points, surface normals, and hit fractions.",
		typeName    = "RaycastNode",
	},
	{
		name        = "Joint",
		category    = "Physics & Collision",
		icon        = ICON_FA_LINK,
		description = "Connects two bodies: hinge (revolute), distance, slider (prismatic), weld, wheel or motor; motors, springs and limits. Pick Body A (default: parent) and Body B.",
		typeName    = "JointNode",
	},

	// 6. UI & Interface
	{
		name        = "UI Container",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Flexbox-style responsive layout container with horizontal/vertical flow, padding, and alignment.",
		typeName    = "UIContainerNode",
	},
	{
		name        = "UI Label",
		category    = "UI & Interface",
		icon        = ICON_FA_FILE,
		description = "Clean text renderer with font sizing, color styling, and multi-line wrapping.",
		typeName    = "UILabelNode",
	},
	{
		name        = "UI Button",
		category    = "UI & Interface",
		icon        = ICON_FA_ARROW_POINTER,
		description = "Interactive clickable button with hovered, normal, and pressed visual feedback and event callbacks.",
		typeName    = "UIButtonNode",
	},
	{
		name        = "UI Slider",
		category    = "UI & Interface",
		icon        = ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT,
		description = "Draggable continuous value slider for settings, volume, and numeric input.",
		typeName    = "UISliderNode",
	},
	{
		name        = "UI Checkbox",
		category    = "UI & Interface",
		icon        = ICON_FA_BORDER_ALL,
		description = "Toggle checkbox widget for boolean options and feature flags.",
		typeName    = "UICheckboxNode",
	},
	{
		name        = "UI Progress Bar",
		category    = "UI & Interface",
		icon        = ICON_FA_CHART_LINE,
		description = "Horizontal progress percentage visualizer for health bars, loading indicators, and gauges.",
		typeName    = "UIProgressBarNode",
	},
	{
		name        = "UI Text Input",
		category    = "UI & Interface",
		icon        = ICON_FA_PEN,
		description = "Single-line text field with placeholder; raises submitted and value_changed.",
		typeName    = "UITextInputNode",
	},
	{
		name        = "UI Dropdown",
		category    = "UI & Interface",
		icon        = ICON_FA_CHEVRON_DOWN,
		description = "Drop-down selector over a list of options.",
		typeName    = "UIDropdownNode",
	},
	{
		name        = "UI Radio Group",
		category    = "UI & Interface",
		icon        = ICON_FA_CIRCLE,
		description = "Mutually exclusive options.",
		typeName    = "UIRadioGroupNode",
	},
	{
		name        = "UI Toggle Switch",
		category    = "UI & Interface",
		icon        = ICON_FA_BORDER_ALL,
		description = "On/off switch.",
		typeName    = "UIToggleSwitchNode",
	},
	{
		name        = "UI Knob",
		category    = "UI & Interface",
		icon        = ICON_FA_ROTATE_RIGHT,
		description = "Rotary value control.",
		typeName    = "UIKnobNode",
	},
	{
		name        = "UI Notched Slider",
		category    = "UI & Interface",
		icon        = ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT,
		description = "Slider that snaps to detents.",
		typeName    = "UINotchedSliderNode",
	},
	{
		name        = "UI Volume Fader",
		category    = "UI & Interface",
		icon        = ICON_FA_MUSIC,
		description = "Audio fader in decibels.",
		typeName    = "UIVolumeFaderNode",
	},
	{
		name        = "UI Volume Meter",
		category    = "UI & Interface",
		icon        = ICON_FA_CHART_LINE,
		description = "Stereo level meter.",
		typeName    = "UIVolumeMeterNode",
	},
	{
		name        = "UI Separator",
		category    = "UI & Interface",
		icon        = ICON_FA_MINUS,
		description = "Horizontal divider with an optional label.",
		typeName    = "UISeparatorNode",
	},
	{
		name        = "UI XY Plot",
		category    = "UI & Interface",
		icon        = ICON_FA_CHART_LINE,
		description = "Line plot of streaming values.",
		typeName    = "UIXYPlotNode",
	},
	{
		name        = "UI List View",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Scrollable selectable list; raises selected.",
		typeName    = "UIListViewNode",
	},
	{
		name        = "UI Tree View",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Hierarchical expandable tree.",
		typeName    = "UITreeViewNode",
	},
	{
		name        = "UI Bullet List",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_CELLS,
		description = "HTML-style unordered list.",
		typeName    = "UIUnorderedListNode",
	},
	{
		name        = "UI Numbered List",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_CELLS,
		description = "HTML-style ordered list.",
		typeName    = "UIOrderedListNode",
	},
	{
		name        = "UI Table",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Sortable data table; raises row_selected and sorted.",
		typeName    = "UITableNode",
	},
	{
		name        = "UI Icon",
		category    = "UI & Interface",
		icon        = ICON_FA_IMAGE,
		description = "Vector icon.",
		typeName    = "UIIconNode",
	},
	{
		name        = "UI Toolbar",
		category    = "UI & Interface",
		icon        = ICON_FA_BORDER_ALL,
		description = "Row of icon buttons; raises item_clicked.",
		typeName    = "UIToolbarNode",
	},
	{
		name        = "UI Tab Container",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Tabbed pages container.",
		typeName    = "UITabContainerNode",
	},
}

AddNodeDialog_Open :: proc() {
	showAddNodeDialog = true
	nodeSearchBuf = [64]u8{}
	selectedCatalogIdx = 0
}

@(private = "file")
catalog_matches :: proc(item: NodeCatalogEntry, filter: string) -> bool {
	if filter == "" do return true
	return strings.contains(strings.to_lower(item.name, context.temp_allocator), filter) ||
		strings.contains(strings.to_lower(item.category, context.temp_allocator), filter) ||
		strings.contains(strings.to_lower(item.description, context.temp_allocator), filter) ||
		strings.contains(strings.to_lower(item.typeName, context.temp_allocator), filter)
}

AddNodeDialog_Render :: proc(state: ^EditorState) {
	if showAddNodeDialog && !imgui.IsPopupOpen("Add Node###AddNodeDialog") {
		imgui.OpenPopup("Add Node###AddNodeDialog")
	}
	io := imgui.GetIO()
	imgui.SetNextWindowSize({760, 500}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("Add Node###AddNodeDialog", &showAddNodeDialog, {.NoResize, .NoTitleBar}) do return

	UI_PanelTitle(ICON_FA_PLUS, "Add Node")
	parent := Editor_InsertionParent(state)
	imgui.SameLine(0, UI_SPACE)
	UI_DimText(fmt.tprintf("under %s", parent.name if parent != nil else "root"))
	imgui.Dummy({0, 4})

	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##NodeSearchFilter", fmt.ctprintf("%s  Search node types", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(nodeSearchBuf[:])), len(nodeSearchBuf), {})
	Drive_Item("addnode.search")
	filter := strings.to_lower(string(cstring(raw_data(nodeSearchBuf[:]))), context.temp_allocator)

	// Keep the selection on a visible entry.
	if selectedCatalogIdx < 0 || selectedCatalogIdx >= len(NODE_CATALOG) || !catalog_matches(NODE_CATALOG[selectedCatalogIdx], filter) {
		for item, i in NODE_CATALOG {
			if catalog_matches(item, filter) {selectedCatalogIdx = i; break}
		}
	}
	if imgui.IsKeyPressed(.DownArrow) || imgui.IsKeyPressed(.UpArrow) {
		dir := 1 if imgui.IsKeyPressed(.DownArrow) else -1
		for k := 1; k < len(NODE_CATALOG); k += 1 {
			i := (selectedCatalogIdx + dir * k + len(NODE_CATALOG) * 2) % len(NODE_CATALOG)
			if catalog_matches(NODE_CATALOG[i], filter) {selectedCatalogIdx = i; break}
		}
	}

	imgui.Dummy({0, 4})
	listH := imgui.GetContentRegionAvail().y - 44
	create := false
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	if imgui.BeginChild("##catalog", {360, listH}, {}, {}) {
		lastCat := ""
		for item, i in NODE_CATALOG {
			if !catalog_matches(item, filter) do continue
			if item.category != lastCat {
				imgui.Dummy({0, 2})
				imgui.PushFont(GlobalFonts.small)
				imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
				imgui.TextUnformatted(fmt.ctprintf("  %s", strings.to_upper(item.category, context.temp_allocator)))
				imgui.PopStyleColor()
				imgui.PopFont()
				lastCat = item.category
			}
			if imgui.Selectable(fmt.ctprintf("   %s   %s###nodeitem_%d", item.icon, item.name, i), selectedCatalogIdx == i, {}, {0, 26}) {
				selectedCatalogIdx = i
			}
			Drive_Item(fmt.tprintf("addnode:%s", item.name))
			if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
				selectedCatalogIdx = i
				create = true
			}
		}
	}
	imgui.EndChild()
	imgui.PopStyleColor()

	imgui.SameLine(0, 16)
	if imgui.BeginChild("##detail", {0, listH}, {}, {}) {
		if selectedCatalogIdx >= 0 && selectedCatalogIdx < len(NODE_CATALOG) {
			sel := NODE_CATALOG[selectedCatalogIdx]
			imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
			imgui.PushFont(GlobalFonts.semibold)
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", sel.icon, sel.name))
			imgui.PopFont()
			imgui.PopStyleColor()
			UI_DimText(sel.typeName)
			imgui.Dummy({0, 6})
			imgui.TextWrapped("%s", strings.clone_to_cstring(sel.description, context.temp_allocator))
		}
	}
	imgui.EndChild()

	imgui.Dummy({0, 6})
	if imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter) do create = true
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Cancel", "addnode.cancel", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		showAddNodeDialog = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_PrimaryButton("Create", "addnode.create", {120, 30}) do create = true
	if create {
		AddNodeDialog_CreateSelected(state)
		showAddNodeDialog = false
		imgui.CloseCurrentPopup()
	}
	imgui.EndPopup()
}

AddNodeDialog_CreateSelected :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	if selectedCatalogIdx < 0 || selectedCatalogIdx >= len(NODE_CATALOG) do return

	entry := NODE_CATALOG[selectedCatalogIdx]
	newNode := Editor_CreateNode(state, entry.typeName, strings.trim_space(strings.concatenate({entry.name}, context.temp_allocator)))
	if newNode != nil {
		Editor_Log(state, .Info, "Created new node: %s (%s)", newNode.name, entry.name)
	}
}
