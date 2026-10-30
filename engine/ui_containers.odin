package engine

import "core:strings"
import "core:math"
import rl "vendor:raylib"
import uilib "../ui"

// ============================================================================
// UI Layout Containers (Vertical, Horizontal, Grid, Tab, & Window Panel)
// (Layout algorithms and styling are cleanly backed by standalone `ui` package)
// ============================================================================
UILayoutDirection :: uilib.LayoutDirection
UIAlignment :: uilib.Alignment
UITabDirection :: uilib.TabDirection

UIContainerNode :: struct {
	using ui: UIElement,
	title: string `gui:"true"`,
	direction: UILayoutDirection `gui:"true"`,
	alignment: UIAlignment `gui:"true"`,
	spacing: f32 `gui:"true" min:"0" max:"64"`,
	paddingTop: f32 `gui:"true" min:"0" max:"100"`,
	paddingBottom: f32 `gui:"true" min:"0" max:"100"`,
	paddingLeft: f32 `gui:"true" min:"0" max:"100"`,
	paddingRight: f32 `gui:"true" min:"0" max:"100"`,
	columns: int `gui:"true" min:"1" max:"12"`,
	autoSizeHeight: bool `gui:"true"`,
	drawBackground: bool `gui:"true"`,
	drawBorder: bool `gui:"true"`,
	showHeader: bool `gui:"true"`,
	headerHeight: f32 `gui:"true" min:"20" max:"64"`,
	backgroundColor: rl.Color `gui:"true"`,
	headerColor: rl.Color `gui:"true"`,
	borderColor: rl.Color `gui:"true"`,
	titleColor: rl.Color `gui:"true"`,
	computedContentHeight: f32,
}

UIPanelNode :: UIContainerNode
UIVerticalContainerNode :: UIContainerNode
UIHorizontalContainerNode :: UIContainerNode
UIGridContainerNode :: UIContainerNode

UIPanel :: UIContainerNode
UIVerticalContainer :: UIContainerNode
UIHorizontalContainer :: UIContainerNode
UIGridContainer :: UIContainerNode
UIVBox :: UIContainerNode
UIHBox :: UIContainerNode

UIPanelNode_Create :: proc(
	scene: ^Scene,
	name: string = "Panel",
	title: string = "Panel",
	position: [2]f32 = {100, 80},
	size: [2]f32 = {440, 520},
	direction: UILayoutDirection = .Vertical,
	parent: ^Node = nil,
) -> ^UIContainerNode {
	c := CreateNode(scene.manager, UIContainerNode)
	c.name = strings.clone(name, c.allocator) // owned: callers pass temp strings too
	UIElement_Init(&c.ui, .Panel, size)
	c.position = position
	c.globalPosition = position
	c.title = title
	c.direction = direction
	c.alignment = .Stretch
	c.spacing = 8
	c.paddingTop = 14
	c.paddingBottom = 14
	c.paddingLeft = 14
	c.paddingRight = 14
	c.drawBackground = true
	c.drawBorder = true
	c.showHeader = title != ""
	c.headerHeight = 36
	c.backgroundColor = rl.Color{22, 24, 30, 240}
	c.headerColor = rl.Color{28, 32, 42, 255}
	c.borderColor = rl.Color{55, 62, 78, 255}
	c.titleColor = rl.Color{238, 240, 246, 255}
	c.update = UIContainerNode_Update
	c.render = UIContainerNode_Render
	scene->addNode(c, parent)
	return c
}

UIVerticalContainerNode_Create :: proc(
	scene: ^Scene,
	name: string = "VBox",
	size: [2]f32 = {400, 300},
	spacing: f32 = 8,
	alignment: UIAlignment = .Stretch,
	parent: ^Node = nil,
) -> ^UIContainerNode {
	c := CreateNode(scene.manager, UIContainerNode)
	c.name = strings.clone(name, c.allocator) // owned: callers pass temp strings too
	UIElement_Init(&c.ui, .VerticalContainer, size)
	c.position = {0, 0}
	c.globalPosition = {0, 0}
	c.title = ""
	c.direction = .Vertical
	c.alignment = .Stretch
	c.spacing = spacing
	c.paddingTop = 0
	c.paddingBottom = 0
	c.paddingLeft = 0
	c.paddingRight = 0
	c.drawBackground = false
	c.drawBorder = false
	c.showHeader = false
	c.update = UIContainerNode_Update
	c.render = UIContainerNode_Render
	scene->addNode(c, parent)
	return c
}

UIHorizontalContainerNode_Create :: proc(
	scene: ^Scene,
	name: string = "HBox",
	size: [2]f32 = {400, 40},
	spacing: f32 = 8,
	alignment: UIAlignment = .Stretch,
	parent: ^Node = nil,
) -> ^UIContainerNode {
	c := CreateNode(scene.manager, UIContainerNode)
	c.name = strings.clone(name, c.allocator) // owned: callers pass temp strings too
	UIElement_Init(&c.ui, .HorizontalContainer, size)
	c.position = {0, 0}
	c.globalPosition = {0, 0}
	c.title = ""
	c.direction = .Horizontal
	c.alignment = .Stretch
	c.spacing = spacing
	c.paddingTop = 0
	c.paddingBottom = 0
	c.paddingLeft = 0
	c.paddingRight = 0
	c.drawBackground = false
	c.drawBorder = false
	c.showHeader = false
	c.update = UIContainerNode_Update
	c.render = UIContainerNode_Render
	scene->addNode(c, parent)
	return c
}

UIGridContainerNode_Create :: proc(
	scene: ^Scene,
	name: string = "Grid",
	size: [2]f32 = {400, 300},
	columns: int = 2,
	spacing: f32 = 8,
	parent: ^Node = nil,
) -> ^UIContainerNode {
	c := CreateNode(scene.manager, UIContainerNode)
	c.name = strings.clone(name, c.allocator) // owned: callers pass temp strings too
	UIElement_Init(&c.ui, .GridContainer, size)
	c.position = {0, 0}
	c.globalPosition = {0, 0}
	c.title = ""
	c.direction = .Grid
	c.columns = columns
	c.alignment = .Stretch
	c.spacing = spacing
	c.paddingTop = 0
	c.paddingBottom = 0
	c.paddingLeft = 0
	c.paddingRight = 0
	c.drawBackground = false
	c.drawBorder = false
	c.showHeader = false
	c.update = UIContainerNode_Update
	c.render = UIContainerNode_Render
	scene->addNode(c, parent)
	return c
}

// ============================================================================
// 5. UITabContainerNode (Horizontal/Vertical Multi-Tab Container)
// ============================================================================

UITabContainerNode :: struct {
	using container: UIContainerNode,
	tabDirection: UITabDirection `gui:"true"`,
	tabNames: [dynamic]string `gui:"true"`,
	activeTab: int `gui:"true" min:"0" max:"16"`,
	tabSize: f32 `gui:"true" min:"20" max:"64"`,
	contentRect: rl.Rectangle,
}

UITabContainer :: UITabContainerNode

UITabContainerNode_Create :: proc(
	scene: ^Scene,
	name: string = "TabContainer",
	tabNames: []string,
	position: [2]f32 = {100, 80},
	size: [2]f32 = {440, 400},
	direction: UITabDirection = .Horizontal,
	tabSize: f32 = 30,
	parent: ^Node = nil,
) -> ^UITabContainerNode {
	tc := CreateNode(scene.manager, UITabContainerNode)
	tc.name = strings.clone(name, tc.allocator) // owned: callers pass temp strings too
	UIElement_Init(&tc.ui, .TabContainer, size)
	tc.position = position
	tc.globalPosition = position
	tc.title = ""
	tc.tabDirection = direction
	tc.tabSize = tabSize
	tc.activeTab = 0
	tc.direction = .Vertical
	tc.alignment = .Stretch
	tc.spacing = 8
	tc.paddingTop = 12
	tc.paddingBottom = 12
	tc.paddingLeft = 14
	tc.paddingRight = 14
	tc.drawBackground = true
	tc.drawBorder = true
	tc.backgroundColor = rl.Color{22, 24, 30, 242}
	tc.borderColor = rl.Color{55, 62, 78, 255}

	for t in tabNames {
		append(&tc.tabNames, t)
	}

	tc.onDestroy = UITabContainerNode_Destroy
	tc.update = UITabContainerNode_Update
	tc.render = UITabContainerNode_Render
	scene->addNode(tc, parent)
	return tc
}

UITabContainerNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	tc := cast(^UITabContainerNode)node
	delete(tc.tabNames)
}

UITabContainerNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	tc := cast(^UITabContainerNode)node
	if !UI_TakesInput(tc) do return

	rect := UI_GetElementRect(&tc.ui)
	mousePos := UI_GetMousePos(gameContext)
	isClick := UI_IsMousePressed(gameContext)

	// Update active tab on click
	tabCount := len(tc.tabNames)
	if isClick && tabCount > 0 {
		if tc.tabDirection == .Horizontal {
			tabW := rect.width / f32(tabCount)
			for i in 0..<tabCount {
				tabR := rl.Rectangle{rect.x + f32(i) * tabW, rect.y, tabW, tc.tabSize}
				if uilib.PointInRect(mousePos, tabR) {
					tc.activeTab = i
					break
				}
			}
		} else {
			tabH := rect.height / f32(tabCount)
			for i in 0..<tabCount {
				tabR := rl.Rectangle{rect.x, rect.y + f32(i) * tabH, tc.tabSize, tabH}
				if uilib.PointInRect(mousePos, tabR) {
					tc.activeTab = i
					break
				}
			}
		}
	}

	// Keyboard navigation when focused
	if tc.focused && !tc.justFocused && tabCount > 0 {
		if tc.tabDirection == .Horizontal {
			if UI_IsKeyPressedLeft(gameContext) {
				tc.activeTab = (tc.activeTab - 1 + tabCount) % tabCount
			} else if UI_IsKeyPressedRight(gameContext) {
				tc.activeTab = (tc.activeTab + 1) % tabCount
			}
		} else {
			if UI_IsKeyPressedUp(gameContext) {
				tc.activeTab = (tc.activeTab - 1 + tabCount) % tabCount
			} else if UI_IsKeyPressedDown(gameContext) {
				tc.activeTab = (tc.activeTab + 1) % tabCount
			}
		}
	}

	if gameContext != nil && gameContext.scene != nil && gameContext.scene.manager != nil {
		UIContainerNode_LayoutChildren(&tc.container, gameContext.scene.manager)
	}
}

UITabContainerNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	tc := cast(^UITabContainerNode)node
	rect := UI_GetElementRect(&tc.ui)

	tc.contentRect = uilib.RenderTabContainer(
		rect,
		tc.tabNames[:],
		tc.activeTab,
		tc.tabDirection,
		tc.tabSize,
		tc.backgroundColor,
		tc.borderColor,
		focused = tc.focused,
	)
}

UI_IsContainerNode :: proc(elem: ^UIElement) -> bool {
	if elem == nil do return false
	return elem.widgetType == .Panel ||
	       elem.widgetType == .VerticalContainer ||
	       elem.widgetType == .HorizontalContainer ||
	       elem.widgetType == .GridContainer ||
	       elem.widgetType == .TabContainer
}

UIContainerNode_LayoutChildren :: proc(c: ^UIContainerNode, manager: ^NodeManager) {
	if c == nil || manager == nil do return

	children := GetChildren(manager, cast(^Node)c)
	defer delete(children)

	// Filter active UIElement children
	uiChildren := make([dynamic]^UIElement)
	defer delete(uiChildren)
	for child in children {
		if child != nil && child.enabled && child.isUI {
			elem := cast(^UIElement)child
			if elem.widgetType != .None {
				append(&uiChildren, elem)
			}
		}
	}

	childCount := len(uiChildren)
	if childCount == 0 do return

	containerOrigin := UI_GetElementPos(&c.ui)
	containerOrigin = {math.round(containerOrigin.x), math.round(containerOrigin.y)}

	headerH: f32 = math.round(c.headerHeight) if c.showHeader else 0
	if c.widgetType == .TabContainer {
		tc := cast(^UITabContainerNode)c
		if tc.tabDirection == .Horizontal {
			headerH += tc.tabSize
		}
	}

	pad := uilib.Padding{
		left   = math.round(c.paddingLeft),
		top    = math.round(c.paddingTop),
		right  = math.round(c.paddingRight),
		bottom = math.round(c.paddingBottom),
	}
	if c.widgetType == .TabContainer {
		tc := cast(^UITabContainerNode)c
		if tc.tabDirection == .Vertical {
			pad.left += tc.tabSize
		}
	}

	// Prepare item size pointers and position storage
	itemSizes := make([]^[2]f32, childCount)
	defer delete(itemSizes)
	outPositions := make([][2]f32, childCount)
	defer delete(outPositions)

	for i in 0..<childCount {
		elem := uiChildren[i]
		itemSizes[i] = &elem.size
	}

	#partial switch c.direction {
	case .Vertical:
		c.computedContentHeight = uilib.ComputeVerticalLayout(
			c.size,
			itemSizes,
			outPositions,
			c.alignment,
			c.spacing,
			pad,
			headerH,
		)

	case .Horizontal:
		_ = uilib.ComputeHorizontalLayout(
			c.size,
			itemSizes,
			outPositions,
			c.alignment,
			c.spacing,
			pad,
			headerH,
		)
		maxChildH: f32 = 0
		for i in 0..<childCount {
			if uiChildren[i].size.y > maxChildH do maxChildH = uiChildren[i].size.y
		}
		c.computedContentHeight = headerH + pad.top + maxChildH + pad.bottom

	case .Grid:
		c.computedContentHeight = uilib.ComputeGridLayout(
			c.size,
			itemSizes,
			outPositions,
			c.columns,
			c.spacing,
			pad,
			headerH,
		)
	}

	for i in 0..<childCount {
		elem := uiChildren[i]
		elem.position = outPositions[i]
		elem.globalPosition = containerOrigin + elem.position

		if UI_IsContainerNode(elem) {
			UIContainerNode_LayoutChildren(cast(^UIContainerNode)elem, manager)
		}
	}

	if c.autoSizeHeight && c.computedContentHeight > 0 {
		c.size.y = c.computedContentHeight
	}
}

UIContainerNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	c := cast(^UIContainerNode)node
	if !c.enabled do return
	if gameContext != nil && gameContext.scene != nil && gameContext.scene.manager != nil {
		UIContainerNode_LayoutChildren(c, gameContext.scene.manager)
	}
}

UIContainerNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	c := cast(^UIContainerNode)node
	rect := UI_GetElementRect(&c.ui)
	uilib.RenderContainerPanel(
		rect,
		c.title,
		c.drawBackground,
		c.drawBorder,
		c.showHeader,
		c.headerHeight,
		c.backgroundColor,
		c.headerColor,
		c.borderColor,
		c.titleColor,
	)
}

// ============================================================================
// 3. UIDockSpaceNode (Multi-Zone Flexible Window-Resize Invariant DockSpace Node)
// ============================================================================
UIDockSlot :: uilib.DockSlot
UIDockPanel :: uilib.DockPanel

UIDockSpaceNode :: struct {
	using ui: UIElement,
	space: uilib.DockSpace,
	simWidthRatio: f32 `gui:"true" min:"0.5" max:"1.0"`,
	userData: rawptr,
}
UIDockSpace :: UIDockSpaceNode

UIDockSpaceNode_Create :: proc(
	scene: ^Scene,
	name: string = "DockSpace",
	position: [2]f32 = {0, 0},
	size: [2]f32 = {1280, 720},
	parent: ^Node = nil,
) -> ^UIDockSpaceNode {
	ds := CreateNode(scene.manager, UIDockSpaceNode)
	ds.name = strings.clone(name, ds.allocator) // owned: callers pass temp strings too
	UIElement_Init(&ds.ui, .DockSpace, size)
	ds.position = position
	ds.globalPosition = position
	ds.simWidthRatio = 1.0
	uilib.DockSpace_Init(&ds.space, rl.Rectangle{position.x, position.y, size.x, size.y})
	ds.update = UIDockSpaceNode_Update
	ds.render = UIDockSpaceNode_Render
	ds.onDestroy = UIDockSpaceNode_Destroy
	scene->addNode(ds, parent)
	return ds
}

UIDockSpaceNode_AddPanel :: proc(
	ds: ^UIDockSpaceNode,
	id: string,
	title: string,
	slot: uilib.DockSlot,
	floatPos: [2]f32 = {100, 100},
	floatSize: [2]f32 = {300, 240},
) {
	uilib.DockSpace_AddPanel(&ds.space, id, title, slot, {floatPos.x, floatPos.y}, {floatSize.x, floatSize.y})
}

UIDockSpaceNode_SetSlot :: proc(ds: ^UIDockSpaceNode, id: string, slot: uilib.DockSlot) {
	uilib.DockSpace_SetSlot(&ds.space, id, slot)
}

UIDockSpaceNode_ToggleFloating :: proc(ds: ^UIDockSpaceNode, id: string) {
	uilib.DockSpace_ToggleFloating(&ds.space, id)
}

UIDockSpaceNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	ds := cast(^UIDockSpaceNode)node
	if !ds.enabled do return
	rect := UI_GetElementRect(&ds.ui)
	uilib.DockSpace_UpdateLayout(&ds.space, rect)
}

UIDockSpaceNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	ds := cast(^UIDockSpaceNode)node
	uilib.DockSpace_RenderOverlays(&ds.space)
}

UIDockSpaceNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	ds := cast(^UIDockSpaceNode)node
	uilib.DockSpace_Destroy(&ds.space)
}
