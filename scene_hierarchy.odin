package main

import "core:fmt"
import rl "vendor:raylib"
import e "engine"
import "ui"

SceneHierarchy :: struct {
	visible: bool,
	width: f32,
	scroll: rl.Vector2,
	contentHeight: f32,
	collapsedNodes: [dynamic]^e.Node,
}

SceneHierarchy_Init :: proc(sh: ^SceneHierarchy) {
	sh.visible = true
	sh.width = 230
	sh.scroll = {0, 0}
	sh.contentHeight = 500
}

SceneHierarchy_IsCollapsed :: proc(sh: ^SceneHierarchy, node: ^e.Node) -> bool {
	if node == nil do return false
	for n in sh.collapsedNodes {
		if n == node do return true
	}
	return false
}

SceneHierarchy_ToggleCollapsed :: proc(sh: ^SceneHierarchy, node: ^e.Node) {
	if node == nil do return
	for n, i in sh.collapsedNodes {
		if n == node {
			unordered_remove(&sh.collapsedNodes, i)
			return
		}
	}
	append(&sh.collapsedNodes, node)
}

SceneHierarchy_GetTargetIndexForNode :: proc(node: ^e.Node, ed: ^Editor, particleNode: ^e.ParticleEmitterNode) -> int {
	if node == nil do return -1
	if particleNode != nil && node == cast(^e.Node)particleNode {
		return 0
	}
	if node.name == "Spaceship" {
		return 1
	}
	if ed != nil {
		if ed.staticBody != nil && node == cast(^e.Node)ed.staticBody do return 4
		if ed.dynamicBody != nil && node == cast(^e.Node)ed.dynamicBody do return 5
		if ed.characterMover != nil && node == cast(^e.Node)ed.characterMover do return 6
		if ed.areaNode != nil && node == cast(^e.Node)ed.areaNode do return 7
		if ed.raycastNode != nil && node == cast(^e.Node)ed.raycastNode do return 8
	}
	return -1
}

SceneHierarchy_GetNodeIcon :: proc(node: ^e.Node, ed: ^Editor, particleNode: ^e.ParticleEmitterNode) -> cstring {
	if node == nil do return "- "
	if node.name == "root" do return "/ "
	if particleNode != nil && node == cast(^e.Node)particleNode do return "* "
	if node.name == "Spaceship" do return "> "
	if ed != nil {
		if ed.staticBody != nil && node == cast(^e.Node)ed.staticBody do return "[] "
		if ed.dynamicBody != nil && node == cast(^e.Node)ed.dynamicBody do return "O "
		if ed.characterMover != nil && node == cast(^e.Node)ed.characterMover do return "@ "
		if ed.areaNode != nil && node == cast(^e.Node)ed.areaNode do return "(()) "
		if ed.raycastNode != nil && node == cast(^e.Node)ed.raycastNode do return "/-> "
	}

	// Check if node is a UI Element
	if node.layer == .Layer7 {
		elem := cast(^e.UIElement)node
		#partial switch elem.widgetType {
		case .Panel, .VerticalContainer, .HorizontalContainer, .GridContainer:
			return "[#] "
		case .Button:
			return "[B] "
		case .Slider:
			return "[=] "
		case .Checkbox:
			return "[v] "
		case .Label, .TextInput:
			return "[T] "
		case .Dropdown, .RadioGroup:
			return "[v] "
		case .XYPlot:
			return "[~] "
		}
	}
	return "o "
}

SceneHierarchy_DrawTreeNode :: proc(
	sh: ^SceneHierarchy,
	manager: ^e.NodeManager,
	node: ^e.Node,
	depth: int,
	isLastChild: bool,
	x: f32,
	itemY: ^f32,
	itemW: f32,
	itemH: f32,
	selectedTargetIndex: ^int,
	ed: ^Editor,
	particleNode: ^e.ParticleEmitterNode,
) {
	if node == nil || manager == nil do return

	children := e.GetChildren(manager, node)
	defer delete(children)
	hasChildren := len(children) > 0
	isCollapsed := SceneHierarchy_IsCollapsed(sh, node)

	mappedTarget := SceneHierarchy_GetTargetIndexForNode(node, ed, particleNode)
	isSelected := false
	if ed != nil && ed.selectedNode == node {
		isSelected = true
	} else if mappedTarget != -1 && selectedTargetIndex^ == mappedTarget && (ed == nil || ed.selectedNode == nil) {
		isSelected = true
	}

	icon := SceneHierarchy_GetNodeIcon(node, ed, particleNode)
	nodeName := node.name if node.name != "" else "Node"

	rowBounds := rl.Rectangle{x, itemY^, itemW, itemH}
	clicked, toggled := ui.GuiTreeNode(
		rowBounds,
		nodeName,
		string(icon),
		depth,
		hasChildren,
		&isCollapsed,
		isSelected,
		isLastChild,
	)

	if toggled {
		SceneHierarchy_ToggleCollapsed(sh, node)
	}

	if clicked {
		if ed != nil {
			ed.selectedNode = node
		}
		if mappedTarget != -1 {
			selectedTargetIndex^ = mappedTarget
		} else {
			selectedTargetIndex^ = -1
		}
	}

	itemY^ += itemH + 4

	if !isCollapsed {
		if node.name == "Spaceship" && node.resource != nil {
			resCollapsed := false
			resBounds := rl.Rectangle{x, itemY^, itemW, itemH}
			resClicked, _ := ui.GuiTreeNode(
				resBounds,
				"Spaceship Data",
				"$ ",
				depth + 1,
				false,
				&resCollapsed,
				selectedTargetIndex^ == 2,
				len(children) == 0,
			)
			if resClicked {
				if ed != nil do ed.selectedNode = nil
				selectedTargetIndex^ = 2
			}
			itemY^ += itemH + 4
		}

		for child, cIdx in children {
			SceneHierarchy_DrawTreeNode(
				sh,
				manager,
				child,
				depth + 1,
				cIdx == len(children) - 1,
				x,
				itemY,
				itemW,
				itemH,
				selectedTargetIndex,
				ed,
				particleNode,
			)
		}
	}
}

SceneHierarchy_Render :: proc(
	sh: ^SceneHierarchy,
	rect: rl.Rectangle,
	selectedTargetIndex: ^int,
	targetNames: []cstring,
	dockSide: DockSide,
	screenHeight: f32,
	game: ^e.Game = nil,
	ed: ^Editor = nil,
	particleNode: ^e.ParticleEmitterNode = nil,
) {
	if !sh.visible do return

	rl.DrawRectangleRec(rect, rl.Color{24, 25, 28, 255})
	headerH: f32 = 42

	// Hierarchy Header
	rl.DrawRectangleRec({rect.x, 0, rect.width, headerH}, rl.Color{30, 31, 35, 255})
	rl.DrawLineEx({rect.x, headerH}, {rect.x + rect.width, headerH}, 1, rl.Color{55, 57, 63, 255})
	DrawEngineText("SCENE HIERARCHY", rect.x + 14, 13, 15, rl.Color{226, 226, 233, 255})

	// Close button to hide hierarchy panel
	closeBtnRect := rl.Rectangle{rect.x + rect.width - 26, 12, 18, 18}
	if ui.GuiButton(closeBtnRect, "x") {
		sh.visible = false
	}

	panelBounds := rl.Rectangle{
		rect.x,
		headerH,
		rect.width,
		rect.height - headerH,
	}
	content := rl.Rectangle{
		0,
		0,
		panelBounds.width - 14,
		sh.contentHeight,
	}
	view := rl.Rectangle{}
	ui.GuiScrollPanel(panelBounds, nil, content, &sh.scroll, &view)

	ui.BeginClipRect(view)

	itemH: f32 = 26
	itemY := view.y + sh.scroll.y + 8
	startY := itemY
	x := view.x + sh.scroll.x + 10
	itemW := view.width - 20

	// 1. Physics World / Game Settings Entry at Top
	worldBounds := rl.Rectangle{x, itemY, itemW, itemH}
	if ui.GuiButton(worldBounds, "# Physics World (Game)", .Left, selectedTargetIndex^ == 3) {
		if ed != nil do ed.selectedNode = nil
		selectedTargetIndex^ = 3
	}
	itemY += itemH + 8

	activeSceneName := game.sceneManager.currentScene.name if (game != nil && game.sceneManager.currentScene != nil) else "scene"
	DrawEngineText(fmt.ctprintf("SCENE TREE (%s)", activeSceneName), x + 2, itemY, 12, rl.Color{138, 142, 153, 255})
	itemY += 18

	// 2. Render Recursive Node Tree starting at scene.rootNode
	if game != nil && game.sceneManager.currentScene != nil && game.sceneManager.currentScene.rootNode != nil {
		scene := game.sceneManager.currentScene
		SceneHierarchy_DrawTreeNode(
			sh,
			scene.manager,
			scene.rootNode,
			0,
			true,
			x,
			&itemY,
			itemW,
			itemH,
			selectedTargetIndex,
			ed,
			particleNode,
		)
	}

	calculatedH := (itemY - startY) + 40
	if calculatedH > sh.contentHeight || sh.contentHeight == 0 {
		sh.contentHeight = calculatedH
	}

	ui.EndClipRect()

	// Border between hierarchy and center
	hBorderX := rect.x + rect.width if dockSide == .Right else rect.x
	rl.DrawLineEx({hBorderX, 0}, {hBorderX, screenHeight}, 1, rl.Color{55, 57, 63, 255})
}
