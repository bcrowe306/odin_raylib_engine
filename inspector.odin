package main

import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "base:runtime"
import rl "vendor:raylib"
import "asteroids"
import e "engine"
import "ui"

DockSide :: enum {
	Left,
	Right,
}

DrawEngineText :: e.DrawEngineText

dropdownEdit: bool

Inspector :: struct {
	visible: bool,
	width: f32,
	dockSide: DockSide,
	scroll: rl.Vector2,
	contentHeight: f32,
	selectedColorStop: int,
	draggingColorStop: bool,
}

Inspector_Init :: proc(insp: ^Inspector) {
	insp.visible = true
	insp.width = 400
	insp.dockSide = .Right
	insp.scroll = {0, 0}
	insp.contentHeight = 1400
	insp.selectedColorStop = 0
	insp.draggingColorStop = false
}

DrawPhysicsShapesGui :: proc(
	shapes: ^[dynamic]e.PhysicsShape,
	bodyId: rawptr,
	ownerNode: ^e.Node,
	forceSensor: bool,
	x: f32,
	nextY: ^f32,
	itemWidth: f32,
	labelWidth: f32,
	sliderHeight: f32,
	yPadding: f32,
) {
	DrawEngineText("Box2D Shapes", x, nextY^, 15, rl.Color{110, 168, 254, 255})

	// Add Shape Buttons (+ Box, + Circle, + Capsule, + Segment)
	btnW := (itemWidth - 110) / 4
	btnX := x + 110
	if ui.GuiButton({btnX, nextY^ - 2, btnW - 2, 20}, "+Box") {
		s := e.MakeBoxPhysicsShape(40, 40)
		if forceSensor { s.isSensor = true; s.enableSensorEvents = true }
		append(shapes, s)
	}
	if ui.GuiButton({btnX + btnW, nextY^ - 2, btnW - 2, 20}, "+Circ") {
		s := e.MakeCirclePhysicsShape(20)
		if forceSensor { s.isSensor = true; s.enableSensorEvents = true }
		append(shapes, s)
	}
	if ui.GuiButton({btnX + btnW * 2, nextY^ - 2, btnW - 2, 20}, "+Caps") {
		s := e.MakeCapsulePhysicsShape(14, 28)
		if forceSensor { s.isSensor = true; s.enableSensorEvents = true }
		append(shapes, s)
	}
	if ui.GuiButton({btnX + btnW * 3, nextY^ - 2, btnW - 2, 20}, "+Seg") {
		s := e.MakeSegmentPhysicsShape({-30, 0}, {30, 0})
		if forceSensor { s.isSensor = true; s.enableSensorEvents = true }
		append(shapes, s)
	}
	nextY^ += 26

	removeIdx := -1
	for i := 0; i < len(shapes^); i += 1 {
		shape := &shapes^[i]
		oldType := shape.type

		// Shape Sub-header
		rl.DrawRectangleRec({x, nextY^, itemWidth + 40, 22}, rl.Color{35, 37, 43, 255})
		DrawEngineText(fmt.ctprintf("Shape [%d] (%v)", i, shape.type), x + 6, nextY^ + 3, 14, rl.Color{180, 205, 255, 255})
		if ui.GuiButton({x + itemWidth - 20, nextY^ + 1, 56, 20}, "Remove") {
			removeIdx = i
		}
		nextY^ += 26

		DrawGenericStructGui(shape, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)

		// If shape type changed in dropdown, recreate Box2D shape on next update
		if shape.type != oldType {
			e.PhysicsShape_Destroy(shape)
		}
		nextY^ += 8
	}

	if removeIdx >= 0 && removeIdx < len(shapes^) {
		e.PhysicsShape_Destroy(&shapes^[removeIdx])
		ordered_remove(shapes, removeIdx)
	}
}

DrawPhysicsJointGui :: proc(
	joint: ^e.PhysicsJoint,
	game: ^e.Game,
	bodyA: ^e.StaticBodyNode,
	bodyB: ^e.DynamicBodyNode,
	x: f32,
	nextY: ^f32,
	itemWidth: f32,
	labelWidth: f32,
	sliderHeight: f32,
	yPadding: f32,
) {
	if joint == nil do return

	oldType := joint.type
	DrawGenericStructGui(joint, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	nextY^ += 6

	if joint.type != oldType && game != nil && bodyA != nil && bodyB != nil {
		e.PhysicsJoint_Destroy(joint)
		e.PhysicsJoint_Create(joint, game.physicsWorld.worldId, bodyA.bodyId, bodyB.bodyId)
	}

	// Render the active joint type's fields
	switch joint.type {
	case .Distance:
		DrawEngineText("Distance Joint Properties", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
		DrawGenericStructGui(&joint.distance, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	case .Filter:
		DrawEngineText("Filter Joint (Disables BodyA/B Collision)", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
	case .Motor:
		DrawEngineText("Motor Joint Properties", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
		DrawGenericStructGui(&joint.motor, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	case .Mouse:
		DrawEngineText("Mouse Joint Properties", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
		DrawGenericStructGui(&joint.mouse, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	case .Prismatic:
		DrawEngineText("Prismatic Joint Properties", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
		DrawGenericStructGui(&joint.prismatic, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	case .Revolute:
		DrawEngineText("Revolute Joint Properties", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
		DrawGenericStructGui(&joint.revolute, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	case .Weld:
		DrawEngineText("Weld Joint Properties", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
		DrawGenericStructGui(&joint.weld, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	case .Wheel:
		DrawEngineText("Wheel Joint Properties", x, nextY^, 15, rl.Color{110, 168, 254, 255})
		nextY^ += 22
		DrawGenericStructGui(&joint.wheel, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	}

	e.PhysicsJoint_Sync(joint)

	nextY^ += 8
	if ui.GuiButton({x + labelWidth, nextY^, itemWidth - labelWidth, sliderHeight + 4}, "Rebuild Joint") {
		if game != nil && bodyA != nil && bodyB != nil {
			e.PhysicsJoint_Destroy(joint)
			e.PhysicsJoint_Create(joint, game.physicsWorld.worldId, bodyA.bodyId, bodyB.bodyId)
		}
	}
	nextY^ += sliderHeight + yPadding + 6
}

DrawInputSystemGui :: proc(input: ^e.InputSystem, x: f32, nextY: ^f32, itemWidth: f32, labelWidth: f32, sliderHeight: f32, yPadding: f32) {
	if input == nil do return

	DrawEngineText("Two-Tier Input System (Actions -> Keys)", x, nextY^, 15, rl.Color{110, 168, 254, 255})
	if ui.GuiButton({x + itemWidth - 40, nextY^ - 2, 80, 20}, "Reset Keys") {
		e.Input_ResetDefaultBindings(input)
	}
	nextY^ += 24

	DrawGenericStructGui(input, x, nextY, itemWidth, labelWidth, sliderHeight, yPadding)
	nextY^ += 4

	if input.isListeningForRebind {
		DrawEngineText(
			fmt.ctprintf("Press any key to rebind [%v] (ESC to cancel)...", input.rebindTargetAction),
			x,
			nextY^,
			13,
			rl.Color{250, 204, 21, 255},
		)
		nextY^ += 20
	}

	// Display core game actions, their bound physical keys, live state, and Rebind button
	coreActions := [?]e.InputAction{
		.MoveUp,
		.MoveDown,
		.MoveLeft,
		.MoveRight,
		.Jump,
		.Fire,
		.SecondaryAction,
		.Boost,
		.Interact,
		.Pause,
	}

	for action in coreActions {
		st := input.states[action]
		bindStr := e.Input_GetActionBindingsString(input, action)

		rowRect := rl.Rectangle{x, nextY^, itemWidth + 40, 22}
		bgCol := rl.Color{37, 99, 235, 80} if st.down else rl.Color{32, 34, 40, 255}
		rl.DrawRectangleRec(rowRect, bgCol)

		stateTag := "DOWN" if st.down else "IDLE"
		stateCol := rl.Color{74, 222, 128, 255} if st.down else rl.Color{140, 146, 160, 255}
		DrawEngineText(fmt.ctprintf("%v", action), x + 6, nextY^ + 4, 13, rl.Color{226, 230, 240, 255})
		DrawEngineText(fmt.ctprint(bindStr), x + 102, nextY^ + 4, 12, rl.Color{170, 184, 210, 255})
		DrawEngineText(fmt.ctprint(stateTag), x + itemWidth - 52, nextY^ + 4, 12, stateCol)

		rebindLabel: cstring = "..." if (input.isListeningForRebind && input.rebindTargetAction == action) else "Bind"
		if ui.GuiButton({x + itemWidth - 8, nextY^ + 1, 46, 20}, rebindLabel) {
			e.Input_StartRebind(input, action)
		}
		nextY^ += 25
	}
}

Inspector_Render :: proc(
	insp: ^Inspector,
	rect: rl.Rectangle,
	selectedTargetIndex: ^int,
	targetNames: []cstring,
	screenHeight: f32,
	game: ^e.Game,
	particleNode: ^e.ParticleEmitterNode,
	ed: ^Editor = nil,
) {
	if !insp.visible do return

	headerH: f32 = 42

	// Inspector Background
	rl.DrawRectangleRec(rect, rl.Color{24, 25, 28, 255})

	// Inspector Header Bar
	rl.DrawRectangleRec({rect.x, 0, rect.width, headerH}, rl.Color{30, 31, 35, 255})
	rl.DrawLineEx({rect.x, headerH}, {rect.x + rect.width, headerH}, 1, rl.Color{55, 57, 63, 255})
	DrawEngineText("INSPECTOR", rect.x + 16, 13, 16, rl.Color{226, 226, 233, 255})

	// Close Button to hide inspector panel
	closeBtnRect := rl.Rectangle{rect.x + rect.width - 132, 11, 20, 20}
	if ui.GuiButton(closeBtnRect, "x") {
		insp.visible = false
	}

	// Dock Side Switch Button
	dockBtnText: cstring = "< Dock Left" if insp.dockSide == .Right else "Dock Right >"
	dockBtnRect := rl.Rectangle{rect.x + rect.width - 105, 10, 95, 22}
	if ui.GuiButton(dockBtnRect, dockBtnText) {
		insp.dockSide = .Left if insp.dockSide == .Right else .Right
	}

	// Target Selection Tabs inside Inspector (3 columns for clean display of all targets)
	selectorY := headerH + 4
	targetCount := len(targetNames)
	cols := 3
	rows := (targetCount + cols - 1) / cols
	rowH: f32 = 22
	selectorH := f32(rows) * (rowH + 3) + 4
	targetBtnW := (rect.width - 24) / f32(cols)
	for tIdx in 0..<targetCount {
		r := tIdx / cols
		c := tIdx % cols
		tBtnX := rect.x + 12 + f32(c) * targetBtnW
		tBtnY := selectorY + f32(r) * (rowH + 3)
		label := targetNames[tIdx]
		if ui.GuiButton({tBtnX, tBtnY, targetBtnW - 3, rowH}, label, .Center, selectedTargetIndex^ == tIdx) {
			selectedTargetIndex^ = tIdx
			if ed != nil do ed.selectedNode = nil
		}
	}
	rl.DrawLineEx({rect.x, selectorY + selectorH}, {rect.x + rect.width, selectorY + selectorH}, 1, rl.Color{45, 47, 53, 255})

	// Inspector Scroll Panel
	panelY := selectorY + selectorH + 4
	panelBounds := rl.Rectangle{
		rect.x,
		panelY,
		rect.width,
		rect.height - panelY,
	}

	content := rl.Rectangle{
		0,
		0,
		panelBounds.width - 5,
		insp.contentHeight,
	}

	view := rl.Rectangle{}
	ui.GuiScrollPanel(panelBounds, nil, content, &insp.scroll, &view)

	ui.BeginClipRect(view)

	nextY := view.y + insp.scroll.y + 8
	startY := nextY
	x := view.x + insp.scroll.x + 10
	itemWidth := panelBounds.width - 30
	labelWidth: f32 = 135
	sliderHeight: f32 = 20
	yPadding: f32 = 4

	// Selected Target Rendering
	switch selectedTargetIndex^ {
	case 0:
		// Target: Particle Emitter Node & Emitter
		DrawEngineText("Particle Emitter Node", x, nextY, 16, rl.Color{110, 168, 254, 255})
		nextY += 24

		if particleNode != nil {
			DrawGenericStructGui(cast(^e.Node)particleNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 16

			DrawEngineText("Emitter Settings & FX", x, nextY, 16, rl.Color{110, 168, 254, 255})
			nextY += 24

			e.ParticleEmitter_DrawColorRampGui(&particleNode.emitter, x, &nextY, itemWidth, &insp.selectedColorStop, &insp.draggingColorStop, view)
			nextY += 12

			btnW := (itemWidth - labelWidth - 4) / 2
			if ui.GuiButton({x + labelWidth, nextY, btnW, sliderHeight + 4}, "Start") {
				if particleNode.emitter.start != nil {
					particleNode.emitter->start()
				} else {
					e.ParticleEmitter_Start(&particleNode.emitter)
				}
			}
			if ui.GuiButton({x + labelWidth + btnW + 4, nextY, btnW, sliderHeight + 4}, "Stop") {
				if particleNode.emitter.stop != nil {
					particleNode.emitter->stop()
				} else {
					e.ParticleEmitter_Stop(&particleNode.emitter)
				}
			}
			nextY += sliderHeight + yPadding + 8

			DrawGenericStructGui(&particleNode.emitter, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

	case 1:
		// Target: Ship Node
		DrawEngineText("Ship Node Transform & State", x, nextY, 16, rl.Color{110, 168, 254, 255})
		nextY += 24

		if game != nil && game.sceneManager.currentScene != nil && game.sceneManager.currentScene.manager != nil {
			scene := game.sceneManager.currentScene
			shipNode: ^e.Node = nil
			for n in scene.manager.nodes {
				if n != nil && n.name == "Spaceship" {
					shipNode = n
					break
				}
			}
			if shipNode == nil {
				for n in scene.manager.nodes {
					if n != nil && n != scene.rootNode {
						shipNode = n
						break
					}
				}
			}
			if shipNode != nil {
				DrawGenericStructGui(shipNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			}
		}

	case 2:
		// Target: Spaceship Data
		DrawEngineText("Spaceship Physics & Input", x, nextY, 16, rl.Color{110, 168, 254, 255})
		nextY += 24

		if game != nil && game.sceneManager.currentScene != nil && game.sceneManager.currentScene.manager != nil {
			scene := game.sceneManager.currentScene
			shipNode: ^e.Node = nil
			for n in scene.manager.nodes {
				if n != nil && n.name == "Spaceship" {
					shipNode = n
					break
				}
			}
			if shipNode == nil {
				for n in scene.manager.nodes {
					if n != nil && n != scene.rootNode {
						shipNode = n
						break
					}
				}
			}
			if shipNode != nil && shipNode.resource != nil {
				shipData := cast(^asteroids.Spaceship)shipNode.resource
				DrawGenericStructGui(shipData, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			} else {
				DrawEngineText("Spaceship resource data not active", x, nextY, 14, rl.GRAY)
				nextY += 20
			}
		}

	case 3:
		// Target: Game, Box2D Physics World, & Two-Tier Input System
		DrawEngineText("Game & Box2D Physics World", x, nextY, 16, rl.Color{110, 168, 254, 255})
		nextY += 24
		if game != nil {
			DrawGenericStructGui(&game.physicsWorld, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 12
			DrawEngineText("Game Display Settings", x, nextY, 15, rl.Color{110, 168, 254, 255})
			nextY += 22
			DrawGenericStructGui(game, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 12
			DrawInputSystemGui(&game.input, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

	case 4:
		// Target: StaticBodyNode
		DrawEngineText("StaticBody Node", x, nextY, 16, rl.Color{74, 222, 128, 255})
		nextY += 24
		if ed != nil && ed.staticBody != nil {
			DrawGenericStructGui(cast(^e.Node)ed.staticBody, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			DrawGenericStructGui(ed.staticBody, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 12
			DrawPhysicsShapesGui(&ed.staticBody.shapes, &ed.staticBody.bodyId, cast(^e.Node)ed.staticBody, false, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

	case 5:
		// Target: DynamicBodyNode
		DrawEngineText("DynamicBody Node", x, nextY, 16, rl.Color{96, 165, 250, 255})
		nextY += 24
		if ed != nil && ed.dynamicBody != nil {
			// Quick Action Buttons (Impulse / Reset Position)
			btnW := (itemWidth - labelWidth - 4) / 2
			if ui.GuiButton({x + labelWidth, nextY, btnW, sliderHeight + 4}, "Jump Impulse") {
				e.DynamicBodyNode_ApplyImpulse(ed.dynamicBody, {0, -25000})
			}
			if ui.GuiButton({x + labelWidth + btnW + 4, nextY, btnW, sliderHeight + 4}, "Respawn Top") {
				ed.dynamicBody.position = {640, 140}
				ed.dynamicBody.linearVelocity = {0, 0}
			}
			nextY += sliderHeight + yPadding + 6

			DrawGenericStructGui(cast(^e.Node)ed.dynamicBody, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			DrawGenericStructGui(ed.dynamicBody, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 12
			DrawPhysicsShapesGui(&ed.dynamicBody.shapes, &ed.dynamicBody.bodyId, cast(^e.Node)ed.dynamicBody, false, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

	case 6:
		// Target: CharacterMoverNode
		DrawEngineText("CharacterMover Node (Box2D v3)", x, nextY, 16, rl.Color{250, 204, 21, 255})
		nextY += 24
		if ed != nil && ed.characterMover != nil {
			if ui.GuiButton({x + labelWidth, nextY, itemWidth - labelWidth, sliderHeight + 4}, "Respawn Character") {
				ed.characterMover.position = {540, 240}
				ed.characterMover.velocity = {0, 0}
			}
			nextY += sliderHeight + yPadding + 6

			DrawGenericStructGui(cast(^e.Node)ed.characterMover, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			DrawGenericStructGui(ed.characterMover, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 12
			DrawPhysicsShapesGui(&ed.characterMover.shapes, &ed.characterMover.bodyId, cast(^e.Node)ed.characterMover, false, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

	case 7:
		// Target: AreaNode (Sensor)
		DrawEngineText("Area Node (Sensor)", x, nextY, 16, rl.Color{168, 85, 247, 255})
		nextY += 24
		if ed != nil && ed.areaNode != nil {
			DrawGenericStructGui(cast(^e.Node)ed.areaNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			DrawGenericStructGui(ed.areaNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 12
			DrawPhysicsShapesGui(&ed.areaNode.shapes, &ed.areaNode.bodyId, cast(^e.Node)ed.areaNode, true, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

	case 8:
		// Target: RaycastNode & PhysicsJoint
		DrawEngineText("Raycast Node", x, nextY, 16, rl.Color{56, 189, 248, 255})
		nextY += 24
		if ed != nil && ed.raycastNode != nil {
			if ed.raycastNode.isColliding && ed.raycastNode.hitNode != nil {
				DrawEngineText(fmt.ctprintf("Hit Node: %s", ed.raycastNode.hitNode.name), x, nextY, 14, rl.Color{248, 113, 113, 255})
			} else {
				DrawEngineText("Hit Node: <None>", x, nextY, 14, rl.GRAY)
			}
			nextY += 22

			DrawGenericStructGui(cast(^e.Node)ed.raycastNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			DrawGenericStructGui(ed.raycastNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

		if ed != nil && ed.joint != nil {
			nextY += 16
			DrawEngineText("Box2D Joint Inspector", x, nextY, 16, rl.Color{251, 191, 36, 255})
			nextY += 24
			DrawPhysicsJointGui(ed.joint, game, ed.staticBody, ed.dynamicBody, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
		}

	case:
		// Generic Scene Node or UI Widget/Container selected from Tree View
		if ed != nil && ed.selectedNode != nil {
			nodeName := ed.selectedNode.name if ed.selectedNode.name != "" else "Node"
			DrawEngineText(fmt.ctprintf("Node: %s", nodeName), x, nextY, 16, rl.Color{110, 168, 254, 255})
			nextY += 24
			DrawGenericStructGui(ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)

			// If selected node is a UI Widget or Container, also inspect its UIElement & specific widget fields
			if ed.selectedNode.layer == .Layer7 {
				elem := cast(^e.UIElement)ed.selectedNode
				if elem.widgetType != .None {
					nextY += 10
					DrawEngineText(fmt.ctprintf("UI Widget (%v)", elem.widgetType), x, nextY, 15, rl.Color{110, 168, 254, 255})
					nextY += 22
					DrawGenericStructGui(elem, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)

					#partial switch elem.widgetType {
					case .Panel, .VerticalContainer, .HorizontalContainer, .GridContainer:
						DrawGenericStructGui(cast(^e.UIContainerNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .Label:
						DrawGenericStructGui(cast(^e.UILabelNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .Button:
						DrawGenericStructGui(cast(^e.UIButtonNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .Slider:
						DrawGenericStructGui(cast(^e.UISliderNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .Checkbox:
						DrawGenericStructGui(cast(^e.UICheckboxNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .TextInput:
						DrawGenericStructGui(cast(^e.UITextInputNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .Dropdown:
						DrawGenericStructGui(cast(^e.UIDropdownNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .RadioGroup:
						DrawGenericStructGui(cast(^e.UIRadioGroupNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .XYPlot:
						DrawGenericStructGui(cast(^e.UIXYPlotNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .Separator:
						DrawGenericStructGui(cast(^e.UISeparatorNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					case .ProgressBar:
						DrawGenericStructGui(cast(^e.UIProgressBarNode)ed.selectedNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
					}
				}
			}
		}
	}

	calculatedHeight := (nextY - startY) + 80
	if calculatedHeight > insp.contentHeight || insp.contentHeight == 0 {
		insp.contentHeight = calculatedHeight
	}

	ui.EndClipRect()

	// Border between inspector and center
	iBorderX := rect.x if insp.dockSide == .Right else rect.x + rect.width
	rl.DrawLineEx({iBorderX, 0}, {iBorderX, screenHeight}, 1, rl.Color{55, 57, 63, 255})
}

ApplyMaterialDarkTheme :: proc(font: rl.Font) {
	e.engineGuiFont = font
	ui.guiFont = font
}

DrawCollisionLayersBitSetGui :: proc(label: string, layersPtr: ^e.CollisionLayerSet, x: f32, nextY: ^f32, controlWidth: f32, labelWidth: f32, yPadding: f32) {
	DrawEngineText(fmt.ctprint(label), x, nextY^ + 2, 13, rl.Color{200, 202, 210, 255})
	cols := 8
	rows := 2
	cellW := (controlWidth - 14) / f32(cols)
	cellH: f32 = 18

	for r in 0..<rows {
		for c in 0..<cols {
			bitIdx := r * cols + c
			layer := e.CollisionLayer(bitIdx)
			bx := x + labelWidth + f32(c) * (cellW + 2)
			by := nextY^ + f32(r) * (cellH + 2)
			rect := rl.Rectangle{bx, by, cellW, cellH}

			isActive := layer in layersPtr^
			if ui.GuiButton(rect, fmt.ctprintf("%d", bitIdx + 1), .Center, isActive) {
				if isActive {
					layersPtr^ -= {layer}
				} else {
					layersPtr^ += {layer}
				}
			}
		}
	}
	nextY^ += f32(rows) * (cellH + 2) + yPadding
}

DrawGenericStructGui :: proc(target: any, x: f32, nextY: ^f32, width: f32, labelWidth: f32 = 140, sliderHeight: f32 = 20, yPadding: f32 = 4) -> int {
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
			ui.GuiSlider({x, nextY^, width, sliderHeight}, fmt.ctprint(field.name), fmt.ctprint(valuef^), valuef, minf, maxf, false, fieldPtr, labelWidth)
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
			ui.GuiSlider({x, nextY^, width, sliderHeight}, fmt.ctprint(field.name), fmt.ctprint(valueI^), &valueFloat, f32(minVal), f32(maxVal), true, fieldPtr, labelWidth)
			valueI^ = int(valueFloat)
			nextY^ += sliderHeight + yPadding
			rendered += 1

		case runtime.Type_Info_Boolean:
			valueB := cast(^bool)fieldPtr
			ui.GuiCheckBox({x + labelWidth, nextY^, sliderHeight, sliderHeight}, fmt.ctprint(field.name), valueB)
			nextY^ += sliderHeight + yPadding
			rendered += 1

		case runtime.Type_Info_Bit_Set:
			if field.type.id == e.CollisionLayerSet {
				DrawCollisionLayersBitSetGui(field.name, cast(^e.CollisionLayerSet)fieldPtr, x, nextY, controlWidth, labelWidth, yPadding)
				rendered += 1
			}

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
					ui.GuiSlider({x, nextY^, width, sliderHeight}, nameLabel, fmt.ctprint(valuef^), valuef, minf, maxf, false, elemPtr, labelWidth)
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
				defer delete(namesJoined)
				DrawEngineText(fmt.ctprint(field.name), x, nextY^ + (sliderHeight - 13) * 0.5, 13, rl.Color{205, 210, 222, 255})
				if ui.GuiDropdownBox({x + labelWidth, nextY^, controlWidth, sliderHeight}, fmt.ctprint(namesJoined), &active, dropdownEdit, fieldPtr) {
					dropdownEdit = !dropdownEdit
				}
				valueI^ = int(active)
				nextY^ += sliderHeight + yPadding
				rendered += 1

			case runtime.Type_Info_Bit_Set:
				if field.type.id == e.CollisionLayerSet {
					DrawCollisionLayersBitSetGui(field.name, cast(^e.CollisionLayerSet)fieldPtr, x, nextY, controlWidth, labelWidth, yPadding)
					rendered += 1
				}

			case runtime.Type_Info_Array:
				if field.type.id == rl.Color {
					c := cast(^rl.Color)fieldPtr
					alpha := f32(c^.a) / 255.0
					colorBoxHeight: f32 = 50
					ui.GuiColorPicker({x + labelWidth, nextY^, controlWidth, colorBoxHeight}, fmt.ctprint(field.name), c)
					nextY^ += colorBoxHeight + yPadding
					ui.GuiColorBarAlpha({x + labelWidth, nextY^, controlWidth, sliderHeight}, "Alpha", &alpha, fieldPtr + 3)
					c.a = u8(alpha * 255.0)
					nextY^ += sliderHeight + yPadding
					rendered += 1
				}
			}
		}
	}

	return rendered
}
