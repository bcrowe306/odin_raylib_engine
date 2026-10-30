package engine

import "core:mem"
import "core:testing"
import b2 "vendor:box2d"
import rl "vendor:raylib"
import "../ui"

// Helper to run a test closure under Odin's Tracking_Allocator and fail on any memory leaks or bad frees.
RunWithLeakTracking :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	old_alloc := context.allocator
	context.allocator = mem.tracking_allocator(&track)
	body(t)
	context.allocator = old_alloc

	for _, entry in track.allocation_map {
		testing.expectf(t, false, "Memory leak detected: %v bytes allocated at %v", entry.size, entry.location)
	}
	for bad_free in track.bad_free_array {
		testing.expectf(t, false, "Bad free detected: pointer %p at %v", bad_free.memory, bad_free.location)
	}
}

// ============================================================================
// 1. Test Full Game Lifecycle: Menu -> Level 1 -> Level 2 -> Menu -> Quit
// ============================================================================
MenuScene_TestSetup :: proc(scene: ^Scene, ctx: ^GameContext) {
	btn := CreateNodeScene(scene, Node, true)
	btn.name = "StartButton"
	btn.position = {640, 360}
	scene.update = proc(s: ^Scene, ctx: ^GameContext, dt: f32) {
		btnNode, found := GetNodeByPath(s, s.rootNode, "/StartButton")
		if found && btnNode != nil {
			btnNode.position.x += 1.0
		}
	}
}

Level1_TestSetup :: proc(scene: ^Scene, ctx: ^GameContext) {
	lvl1Floor := StaticBodyNode_Create(scene, "Level1Floor")
	lvl1Floor.position = {640, 600}
	StaticBodyNode_AddShape(lvl1Floor, MakeBoxPhysicsShape(400, 20), ctx)

	lvl1Player := DynamicBodyNode_Create(scene, "Level1Player")
	lvl1Player.position = {640, 200}
	DynamicBodyNode_AddShape(lvl1Player, MakeCirclePhysicsShape(16), ctx)

	lvl1Emitter := ParticleEmitterNode_Create(scene, "Level1Particles")
	lvl1Emitter.position = {300, 300}
}

Level2_TestSetup :: proc(scene: ^Scene, ctx: ^GameContext) {
	lvl2Floor := StaticBodyNode_Create(scene, "Level2Floor")
	lvl2Floor.position = {640, 620}
	StaticBodyNode_AddShape(lvl2Floor, MakeBoxPhysicsShape(600, 30), ctx)

	lvl2Mover := CharacterMoverNode_Create(scene, "Level2Mover")
	lvl2Mover.position = {640, 300}
	lvl2Mover.enableKeyboardInput = false
	lvl2Mover.targetSpeedX = 120.0

	lvl2Area := AreaNode_Create(scene, "Level2GoalArea")
	lvl2Area.position = {640, 560}
	AreaNode_AddShape(lvl2Area, MakeBoxPhysicsShape(100, 60), ctx)

	lvl2Ray := RaycastNode_Create(scene, "Level2Laser")
	lvl2Ray.position = {640, 500}
	lvl2Ray.direction = {0, 1}
	lvl2Ray.length = 200.0
}

@(test)
test_scene_switching_menu_levels_quit :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		testing.expect_value(t, game.state, GameState.Initialized)
		testing.expect(t, !game.shouldQuit, "Game should not be quitting initially")

		// 1. Create Scenes with dynamic setup builder procs
		menuScene := game->createScene("menu", true, MenuScene_TestSetup)
		level1 := game->createScene("level_1", false, Level1_TestSetup)
		level2 := game->createScene("level_2", false, Level2_TestSetup)

		game.state = .Running

		// --- Step A: Run Menu Scene ---
		game->run(0.016)
		testing.expect(t, game.sceneManager.currentScene != nil, "Current scene should be valid")
		testing.expect_value(t, game.sceneManager.currentScene.name, "menu")
		btnA, foundA := GetNodeByPath(menuScene, menuScene.rootNode, "/StartButton")
		testing.expect(t, foundA && btnA != nil, "Menu StartButton should exist")
		testing.expect_value(t, btnA.position.x, f32(641.0))

		// --- Step B: Transition Menu -> Level 1 ---
		game->changeScene("level_1")
		game->run(0.016)
		testing.expect_value(t, game.sceneManager.currentScene.name, "level_1")

		lvl1Player, foundP := GetNodeByPath(level1, level1.rootNode, "/Level1Player")
		testing.expect(t, foundP && lvl1Player != nil, "Level 1 dynamic player should exist")
		initialPlayerY := lvl1Player.position.y

		// Run Level 1 for several frames so Box2D steps and player moves under gravity
		for _ in 0..<5 {
			game->run(0.016)
		}
		testing.expect(t, lvl1Player.position.y > initialPlayerY, "Level 1 dynamic player should move down under gravity")

		// --- Step C: Transition Level 1 -> Level 2 ---
		game->changeScene("level_2")
		for _ in 0..<5 {
			game->run(0.016)
		}
		testing.expect_value(t, game.sceneManager.currentScene.name, "level_2")

		lvl2MoverNode, foundM := GetNodeByPath(level2, level2.rootNode, "/Level2Mover")
		testing.expect(t, foundM && lvl2MoverNode != nil, "Level 2 CharacterMover should exist")
		testing.expect(t, lvl2MoverNode.position.x > 640.0, "Level 2 CharacterMover should move horizontally")

		lvl2RayNode, foundR := GetNodeByPath(level2, level2.rootNode, "/Level2Laser")
		testing.expect(t, foundR && lvl2RayNode != nil, "Level 2 Raycast should exist")
		lvl2Ray := cast(^RaycastNode)lvl2RayNode
		testing.expect(t, lvl2Ray.isColliding, "Level 2 Raycast should hit Level2Floor")

		// --- Step D: Transition Level 2 -> Menu ---
		// Old scene objects are destroyed on switch, and returning to menu resets state completely
		game->changeScene("menu")
		game->run(0.016)
		testing.expect_value(t, game.sceneManager.currentScene.name, "menu")

		btnD, foundD := GetNodeByPath(menuScene, menuScene.rootNode, "/StartButton")
		testing.expect(t, foundD && btnD != nil, "Menu StartButton should be recreated fresh on scene load")
		// Initial position was 640.0, updated once in update to 641.0 (state was cleanly reset!)
		testing.expect_value(t, btnD.position.x, f32(641.0))

		// --- Step E: Quit Game from Menu and Terminate ---
		game->quit()
		testing.expect(t, game.shouldQuit, "game.shouldQuit should be true after game->quit()")
		testing.expect_value(t, game.state, GameState.Quitting)

		// Terminate game and free all scenes, nodes, arenas, and Box2D world
		game->terminate()
	})
}

// ============================================================================
// 2. Test Node Tree Lifecycle, Removal, Free-List Reuse, & Path Resolution
// ============================================================================
@(test)
test_node_hierarchy_removal_and_memory_cleanup :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		scene := game->createScene("hierarchy_test", true)
		ProcessSceneChange(&game.sceneManager, &game.gameContext)

		// Create parent -> child -> grandchild hierarchy
		parent := CreateNodeScene(scene, Node, false)
		parent.name = "ParentNode"
		scene->addNode(parent)

		child := CreateNodeScene(scene, Node, false)
		child.name = "ChildNode"
		child.position = {10, 20}
		scene->addNode(child, parent)

		grandchild := CreateNodeScene(scene, Node, false)
		grandchild.name = "GrandChildNode"
		grandchild.position = {5, 5}
		scene->addNode(grandchild, child)

		// Allocate custom resource on grandchild's node arena
		res := Node_AddResource(grandchild, [4]f32)
		res^ = {1, 2, 3, 4}

		exitCount := 0
		Node_Subject(grandchild, .Exited_Tree)->subscribe(proc(source: rawptr, value: EventValue, ctx: ^GameContext, user_data: rawptr) {
			cnt := cast(^int)user_data
			cnt^ += 1
		}, &exitCount)

		// Run 1 frame to flush addition queue and compute global positions
		game->run(0.016)

		// Verify path lookups: Root (/), Relative (./), Parent (../)
		foundChild, ok1 := GetNodeByPath(scene, scene.rootNode, "/ParentNode/ChildNode")
		testing.expect(t, ok1 && foundChild == child, "Should resolve /ParentNode/ChildNode")

		foundGrand, ok2 := GetNodeByPath(scene, child, "./GrandChildNode")
		testing.expect(t, ok2 && foundGrand == grandchild, "Should resolve ./GrandChildNode")

		foundParentDirect, ok4 := GetNodeByPath(scene, grandchild, "../GrandChildNode")
		testing.expect(t, ok4 && foundParentDirect == grandchild, "Should resolve ../GrandChildNode from grandchild")

		// Verify global position propagation
		parent.position = {100, 200}
		game->run(0.016)
		testing.expect_value(t, child.globalPosition, [2]f32{110, 220})
		testing.expect_value(t, grandchild.globalPosition, [2]f32{115, 225})

		// Remove parent node (should recursively remove child and grandchild and free their arenas/subjects)
		scene->removeNode(parent)
		game->run(0.016)

		testing.expect_value(t, exitCount, 1)
		stats := NodeManager_GetStats(scene.manager)
		// Only rootNode should remain active
		testing.expect_value(t, stats.count, 1)
		testing.expect_value(t, stats.free, 3)

		// Add new nodes to verify free-list slot reuse without growing capacity
		reused1 := CreateNodeScene(scene, Node, true)
		reused1.name = "Reused1"
		game->run(0.016)
		statsAfter := NodeManager_GetStats(scene.manager)
		testing.expect_value(t, statsAfter.count, 2)
		testing.expect_value(t, statsAfter.free, 2)

		game->terminate()
	})
}

// ============================================================================
// 3. Test Box2D Physics World, Shapes, Joints, & Sensor Events Without Leaks
// ============================================================================
@(test)
test_box2d_physics_nodes_shapes_and_joints_memory :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		scene := game->createScene("physics_test", true)

		// Create StaticBody, DynamicBody, Area, CharacterMover, Raycast
		staticBody := StaticBodyNode_Create(scene, "StaticPlatform")
		staticBody.position = {640, 500}
		StaticBodyNode_AddShape(staticBody, MakeBoxPhysicsShape(500, 24), &game.gameContext)
		StaticBodyNode_AddShape(staticBody, MakeCapsulePhysicsShape(16, 40), &game.gameContext)

		dynamicBody := DynamicBodyNode_Create(scene, "FallingBox")
		dynamicBody.position = {640, 200}
		boxShape := MakeBoxPhysicsShape(32, 32)
		boxShape.density = 2.0
		boxShape.restitution = 0.3
		DynamicBodyNode_AddShape(dynamicBody, boxShape, &game.gameContext)

		mover := CharacterMoverNode_Create(scene, "MoverNode")
		mover.position = {640, 350}
		mover.enableKeyboardInput = false

		area := AreaNode_Create(scene, "SensorZone")
		area.position = {640, 480}
		AreaNode_AddShape(area, MakeBoxPhysicsShape(120, 40), &game.gameContext)

		raycast := RaycastNode_Create(scene, "TestRaycast")
		raycast.position = {640, 420}
		raycast.direction = {0, 1}
		raycast.length = 150.0

		// Distance Joint between StaticPlatform and FallingBox
		joint := PhysicsJoint{}
		PhysicsJoint_Init(&joint, .Distance)
		joint.distance.enableSpring = true
		joint.distance.hertz = 3.0
		joint.distance.dampingRatio = 0.5
		joint.distance.length = 120.0

		// Run 1 frame to instantiate bodies in Box2D world
		game->run(0.016)

		DistanceJoint_Create(&joint.distance, game.physicsWorld.worldId, staticBody.bodyId, dynamicBody.bodyId)
		testing.expect(t, b2.Joint_IsValid(PhysicsJoint_GetId(&joint)), "Distance joint should be successfully created in Box2D world")

		// Step world for 10 frames and verify dynamic simulation and raycast
		for _ in 0..<10 {
			game->run(0.016)
		}
		testing.expect(t, raycast.isColliding, "Raycast pointing straight down should hit platform or area")

		// Test Joint destruction
		PhysicsJoint_Destroy(&joint)
		testing.expect(t, !b2.Joint_IsValid(PhysicsJoint_GetId(&joint)), "PhysicsJoint should be marked invalid after destruction")

		game->terminate()
	})
}

// ============================================================================
// 4. Test Particle Emitter: Burst Mode, Continuous Spawning, & Arena Memory
// ============================================================================
@(test)
test_particle_emitter_burst_and_continuous :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		scene := game->createScene("emitter_test", true)

		// 1. Continuous Emitter
		emitterNode := ParticleEmitterNode_Create(scene, "ContinuousEmitter")
		emitterNode.position = {400, 300}
		emitter := &emitterNode.emitter
		emitter.amount = 40
		emitter.lifetime = 1.0
		emitter.velocity = 50.0
		emitter.continuous = true
		emitter.burst = 0.0

		// Add custom color stops
		ColorRamp_AddStop(&emitter.colorRamp, 0.5, rl.Color{255, 120, 0, 255})
		testing.expect_value(t, emitter.colorRamp.count, 4)

		// Run frames to spawn particles
		game->run(0.016)
		game->run(0.05)
		continuousAlive := 0
		for i in 0..<len(emitter.particles) {
			if emitter.particles[i].alive do continuousAlive += 1
		}
		testing.expect(t, continuousAlive > 0, "Continuous emitter should spawn active particles")

		// 2. Burst Emitter
		burstNode := ParticleEmitterNode_Create(scene, "BurstEmitter")
		burstEmitter := &burstNode.emitter
		burstEmitter.amount = 25
		burstEmitter.burst = 25
		burstEmitter.continuous = false
		burstEmitter.lifetime = 0.5
		ParticleEmitter_Start(burstEmitter)

		game->run(0.016)
		burstAlive := 0
		for i in 0..<len(burstEmitter.particles) {
			if burstEmitter.particles[i].alive do burstAlive += 1
		}
		testing.expect(t, burstAlive > 0, "Burst emitter should create particles on start")

		// Let particles expire
		for _ in 0..<35 {
			game->run(0.02)
		}
		expiredAlive := 0
		for i in 0..<len(burstEmitter.particles) {
			if burstEmitter.particles[i].alive do expiredAlive += 1
		}
		testing.expect_value(t, expiredAlive, 0)

		game->terminate()
	})
}

// ============================================================================
// 5. Test Full UI Toolkit: Containers, Widgets, Clicks, Sliders, & Text Edit
// ============================================================================
@(test)
test_ui_widgets_and_containers_lifecycle_and_memory :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		game.uiTestInputEnabled = true

		scene := game->createScene("ui_test_scene", true)

		// Create Panel Container -> VBox -> HBox / Grid & All Widget Types
		panel := UIPanelNode_Create(scene, "MainPanel", "Settings Panel", {100, 50}, {500, 600}, .Vertical)
		vbox := UIVerticalContainerNode_Create(scene, "VBox", {460, 450}, 8, .Stretch, panel)
		_ = UILabelNode_Create(scene, "HeaderLabel", "Configuration", 18, vbox)
		_ = UISeparatorNode_Create(scene, "Sep", "Controls", vbox)

		btnClicked := false
		btn := UIButtonNode_Create(scene, "ActionButton", "Apply", {200, 36}, vbox)
		btn.onClick->subscribe(proc(source: rawptr, val: EventValue, ctx: ^GameContext, user_data: rawptr) {
			(cast(^bool)user_data)^ = true
		}, &btnClicked)

		slider := UISliderNode_Create(scene, "SpeedSlider", "Speed", 100.0, 0.0, 1000.0, vbox)
		slider.fineScale = 0.1

		checkbox := UICheckboxNode_Create(scene, "VSyncCheck", "VSync", false, vbox)
		textInput := UITextInputNode_Create(scene, "CallsignInput", "Callsign", "ALPHA", "Enter...", vbox)
		dropdown := UIDropdownNode_Create(scene, "PresetDropdown", "Preset", {"Low", "Medium", "High"}, 1, vbox)
		radio := UIRadioGroupNode_Create(scene, "DiffRadio", "Difficulty", {"Easy", "Normal", "Hard"}, 0, true, vbox)
		plot := UIXYPlotNode_Create(scene, "TelemetryPlot", "Plot", {400, 140}, vbox)
		UIXYPlotNode_AddPoint(plot, 0.0, 0.5)
		UIXYPlotNode_AddPoint(plot, 1.0, 0.9)
		UIXYPlotNode_AddSecondaryPoint(plot, 0.0, -0.2)

		grid := UIGridContainerNode_Create(scene, "Grid", {400, 60}, 2, 8, vbox)
		_ = UIProgressBarNode_Create(scene, "LoadBar", "Load", 75, 0, 100, grid)
		hbox := UIHorizontalContainerNode_Create(scene, "HBox", {200, 32}, 6, .Stretch, grid)
		_ = UILabelNode_Create(scene, "StatusLbl", "OK", 14, hbox)

		// Frame 1: Run layout so all containers compute child globalPositions & sizes
		game->run(0.016)
		testing.expect(t, btn.globalPosition.y > panel.globalPosition.y, "VBox should layout button inside Panel")
		testing.expect(t, slider.globalPosition.y > btn.globalPosition.y, "VBox should stack slider below button")

		// 1. Test Button Click via simulated mouse press & release
		btnRect := UI_GetElementRect(&btn.ui)
		game.uiTestMousePos = {btnRect.x + 20, btnRect.y + 10}
		game.uiTestMousePressed = true
		game.uiTestMouseDown = true
		game->run(0.016)
		game.uiTestMousePressed = false
		game.uiTestMouseDown = false
		game.uiTestMouseReleased = true
		game->run(0.016)
		game.uiTestMouseReleased = false
		testing.expect(t, btnClicked, "UIButtonNode should fire onClick when clicked")

		// 2. Test Slider Shift Fine Adjustment, Editable Text, and Reset
		trackRect, valBoxRect, resetRect := UISliderNode_GetSubRects(slider)
		// Start dragging with Shift held for fine adjustment
		game.uiTestShiftDown = true
		game.uiTestMousePos = {trackRect.x + 50, trackRect.y + 8}
		game.uiTestMousePressed = true
		game.uiTestMouseDown = true
		game->run(0.016)

		// Move mouse by +20px while holding Shift (fine adjustment should move much less than normal drag)
		game.uiTestMousePressed = false
		game.uiTestMousePos = {trackRect.x + 70, trackRect.y + 8}
		game->run(0.016)
		fineDelta := slider.value - 100.0
		testing.expect(t, fineDelta > 0.0 && fineDelta < 30.0, "Shift-dragging slider should apply fine adjustment")

		// Release drag
		game.uiTestShiftDown = false
		game.uiTestMouseDown = false
		game.uiTestMouseReleased = true
		game->run(0.016)
		game.uiTestMouseReleased = false

		// Click value box to enter text editing mode and type "450" + ENTER
		game.uiTestMousePos = {valBoxRect.x + 10, valBoxRect.y + 8}
		game.uiTestMousePressed = true
		game->run(0.016)
		game.uiTestMousePressed = false
		testing.expect(t, slider.isEditingText, "Clicking slider value box should open editable text mode")

		slider.editLen = 0
		game.uiTestCharQueue[0] = '4'
		game.uiTestCharQueue[1] = '5'
		game.uiTestCharQueue[2] = '0'
		game.uiTestCharCount = 3
		game->run(0.016)
		game.uiTestKeyEnter = true
		game->run(0.016)
		game.uiTestKeyEnter = false
		testing.expect_value(t, slider.value, f32(450.0))

		// Click [R] Reset button on slider to restore defaultValue (100.0)
		game.uiTestMousePos = {resetRect.x + 6, resetRect.y + 8}
		game.uiTestMousePressed = true
		game->run(0.016)
		game.uiTestMousePressed = false
		testing.expect_value(t, slider.value, f32(100.0))

		// 3. Test Checkbox Toggle
		cbRect := UI_GetElementRect(&checkbox.ui)
		game.uiTestMousePos = {cbRect.x + 8, cbRect.y + 8}
		game.uiTestMousePressed = true
		game->run(0.016)
		game.uiTestMousePressed = false
		testing.expect(t, checkbox.checked, "Clicking checkbox should toggle checked to true")

		// 4. Test TextInput typing & backspace
		UITextInputNode_Backspace(textInput, &game.gameContext)
		UITextInputNode_InsertChar(textInput, '9', &game.gameContext)
		testing.expect_value(t, UITextInputNode_GetText(textInput), "ALPH9")

		// 6. Test New Widgets: ToggleSwitch, Knob, ListView, TreeView, TabContainer, & Vertical ProgressBar
		toggleSw := UIToggleSwitchNode_Create(scene, "MyToggle", "Switch", false, vbox)
		toggleChanged := false
		toggleSw.onChange = proc(node: ^UIToggleSwitchNode, active: bool) {
			(cast(^bool)node.userData)^ = true
		}
		toggleSw.userData = &toggleChanged

		knobNode := UIKnobNode_Create(scene, "GainKnob", "Gain", 20.0, 0.0, 100.0, 20.0, "%.1f", vbox)

		listView := UIListViewNode_Create(scene, "MyList", []string{"Option A", "Option B", "Option C"}, {200, 100}, vbox)
		listSelected := -1
		listView.onSelect = proc(node: ^UIListViewNode, idx: int) {
			(cast(^int)node.userData)^ = idx
		}
		listView.userData = &listSelected

		treeView := UITreeViewNode_Create(scene, "MyTree", {220, 140}, vbox)
		append(&treeView.items, ui.TreeViewItem{id = 10, label = "Root Folder", hasChildren = true, isCollapsed = false, depth = 0})
		append(&treeView.items, ui.TreeViewItem{id = 11, label = "Sub Item 1", hasChildren = false, depth = 1})
		append(&treeView.items, ui.TreeViewItem{id = 12, label = "Sub Item 2", hasChildren = false, depth = 1, isLastChild = true})

		tabContH := UITabContainerNode_Create(scene, "TabsH", []string{"General", "Audio", "Video"}, {200, 100}, {400, 250}, .Horizontal)
		tabContV := UITabContainerNode_Create(scene, "TabsV", []string{"Tab 1", "Tab 2"}, {200, 360}, {300, 200}, .Vertical)

		vertBar := UIProgressBarNode_Create(scene, "VertBar", "VProgress", 0.6, 0.0, 1.0, vbox, .Vertical)
		testing.expect(t, vertBar.direction == .Vertical, "UIProgressBarNode should support .Vertical")
		testing.expect_value(t, knobNode.value, f32(20.0))
		testing.expect_value(t, tabContH.activeTab, 0)
		testing.expect_value(t, tabContV.activeTab, 0)

		// Frame 2: Run layout so all newly created nodes get calculated global positions
		game->run(0.016)

		// Test ToggleSwitch click
		swRect := UI_GetElementRect(&toggleSw.ui)
		game.uiTestMousePos = {swRect.x + 10, swRect.y + 10}
		game.uiTestMousePressed = true
		game->run(0.016)
		game.uiTestMousePressed = false
		testing.expect(t, toggleSw.active, "UIToggleSwitchNode should toggle to true on click")
		testing.expect(t, toggleChanged, "UIToggleSwitchNode onChange callback should fire")

		// Test ListView click
		lvRect := UI_GetElementRect(&listView.ui)
		game.uiTestMousePos = {lvRect.x + 30, lvRect.y + 36}
		game.uiTestMousePressed = true
		game->run(0.016)
		game.uiTestMousePressed = false
		testing.expect_value(t, listView.selectedIndex, 1)
		testing.expect_value(t, listSelected, 1)

		// Test TreeView click
		tvRect := UI_GetElementRect(&treeView.ui)
		game.uiTestMousePos = {tvRect.x + 40, tvRect.y + 30}
		game.uiTestMousePressed = true
		game->run(0.016)
		game.uiTestMousePressed = false
		testing.expect_value(t, treeView.selectedId, 11)

		// Test TabContainer click
		tabHRect := UI_GetElementRect(&tabContH.ui)
		tabW := tabHRect.width / 3.0
		game.uiTestMousePos = {tabHRect.x + tabW + 10, tabHRect.y + 10}
		game.uiTestMousePressed = true
		game->run(0.016)
		game.uiTestMousePressed = false
		testing.expect_value(t, tabContH.activeTab, 1)


		// 5. Test Dropdown & RadioGroup selection
		UIDropdownNode_Select(dropdown, 2, &game.gameContext)
		testing.expect_value(t, UIDropdownNode_GetSelectedText(dropdown), "High")
		UIRadioGroupNode_Select(radio, 2, &game.gameContext)
		testing.expect_value(t, radio.selectedIndex, 2)

		game->terminate()
	})
}

// ============================================================================
// 5b. Test Synchronized Engine UI Nodes Lifecycle, Events, and Interaction
// ============================================================================
@(test)
test_synchronized_ui_nodes_lifecycle_and_events :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)

		scene := game->createScene("new_ui_test_scene", true)
		vbox := UIVerticalContainerNode_Create(scene, "MainVBox", {400, 600}, 8, .Stretch)

		// 1. UIVolumeFaderNode
		fader := UIVolumeFaderNode_Create(scene, "MasterFader", "Master", 0.0, -60.0, 6.0, 0.0, vbox)
		faderChanged := false
		fader.onChange = proc(node: ^UIVolumeFaderNode, valDb: f32) {
			(cast(^bool)node.userData)^ = true
		}
		fader.userData = &faderChanged
		UIVolumeFaderNode_SetValue(fader, -12.0, &game.gameContext)
		testing.expect_value(t, fader.valueDb, f32(-12.0))
		testing.expect(t, faderChanged, "Fader onChange callback should fire")

		// 2. UIVolumeMeterNode
		meter := UIVolumeMeterNode_Create(scene, "VUMeter", "VU", -60.0, -120.0, .Vertical, {80, 200}, vbox)
		UIVolumeMeterNode_SetLevels(meter, -3.5, -6.0)
		testing.expect_value(t, meter.levelL, f32(-3.5))
		testing.expect_value(t, meter.levelR, f32(-6.0))

		// 3. UINotchedSliderNode
		notched := UINotchedSliderNode_Create(scene, "DetentedSlider", "Detents", 0.0, 0.0, 4.0, 5, []string{"0", "1", "2", "3", "4"}, true, .Horizontal, {200, 40}, vbox)
		notchedChanged := false
		notched.onChange = proc(node: ^UINotchedSliderNode, val: f32, notchIdx: int) {
			(cast(^bool)node.userData)^ = true
		}
		notched.userData = &notchedChanged
		UINotchedSliderNode_SetValue(notched, 3.0, &game.gameContext)
		testing.expect_value(t, notched.value, f32(3.0))
		testing.expect(t, notchedChanged, "Notched slider onChange callback should fire")

		// 4. UIDockSpaceNode
		dock := UIDockSpaceNode_Create(scene, "MainDock", {0, 0}, {1280, 720})
		UIDockSpaceNode_AddPanel(dock, "hierarchy", "Hierarchy", .Left)
		UIDockSpaceNode_AddPanel(dock, "inspector", "Inspector", .Right)
		UIDockSpaceNode_AddPanel(dock, "console", "Console", .Bottom)
		testing.expect_value(t, len(dock.space.panels), 3)
		UIDockSpaceNode_SetSlot(dock, "console", .Left)
		testing.expect_value(t, dock.space.panels[2].slot, ui.DockSlot.Left)
		UIDockSpaceNode_ToggleFloating(dock, "inspector")
		testing.expect(t, dock.space.panels[1].slot == .Floating, "Inspector panel should now be floating")

		// 5. UIUnorderedListNode
		ul := UIUnorderedListNode_Create(scene, "MyUL", nil, .Disc, {200, 150}, vbox)
		UIUnorderedListNode_AddItem(ul, ui.ListItem{text = "Feature 1"})
		UIUnorderedListNode_AddItem(ul, ui.ListItem{text = "Feature 2"})
		ulSelected := -1
		ul.onSelectItem = proc(node: ^UIUnorderedListNode, idx: int) {
			(cast(^int)node.userData)^ = idx
		}
		ul.userData = &ulSelected
		testing.expect_value(t, len(ul.items), 2)

		// 6. UIOrderedListNode
		ol := UIOrderedListNode_Create(scene, "MyOL", nil, .Decimal, 1, {200, 150}, vbox)
		UIOrderedListNode_AddItem(ol, ui.ListItem{text = "Step 1"})
		UIOrderedListNode_AddItem(ol, ui.ListItem{text = "Step 2"})
		olSelected := -1
		ol.onSelectItem = proc(node: ^UIOrderedListNode, idx: int) {
			(cast(^int)node.userData)^ = idx
		}
		ol.userData = &olSelected
		testing.expect_value(t, len(ol.items), 2)

		// 7. UITableNode
		cols := []ui.TableColumn{
			{title = "Entity", width = 120, align = .Start, sortable = true},
			{title = "Health", width = 80, align = .Center, sortable = true},
		}
		r1_cells := [2]ui.TableCell{{text = "Player"}, {text = "100"}}
		r2_cells := [2]ui.TableCell{{text = "Enemy"}, {text = "50"}}
		rows := []ui.TableRow{
			{cells = r1_cells[:], id = 1},
			{cells = r2_cells[:], id = 2},
		}
		tbl := UITableNode_Create(scene, "MyTable", cols, rows, {300, 150}, vbox)
		testing.expect_value(t, len(tbl.columns), 2)
		testing.expect_value(t, len(tbl.rows), 2)

		// Run frame update to execute node update & layout procs
		game->run(0.016)

		// Clean termination and verify tracking allocator catches any memory leaks
		game->terminate()
	})
}

// ============================================================================
// 5c. Test LDtk Project Parsing, Layer Extraction, IntGrid Colliders, & Entities
// ============================================================================
@(test)
test_ldtk_level_integration_and_collision_lifecycle :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)

		// 1. Direct project loading and validation
		proj, loadOk := Ldtk_LoadProjectFromFile("assets/levels/deep_space_station.ldtk")
		testing.expect(t, loadOk && proj != nil, "Ldtk project should load successfully")
		if proj != nil {
			testing.expect_value(t, proj.jsonVersion, "1.5.3")
			testing.expect_value(t, len(proj.tilesets), 1)
			testing.expect_value(t, proj.tilesets[0].identifier, "StationTileset")
			testing.expect_value(t, len(proj.levels), 1)

			lvl := Ldtk_GetLevel(proj, "Deep_Space_Station")
			testing.expect(t, lvl != nil, "Level Deep_Space_Station should exist")
			if lvl != nil {
				testing.expect_value(t, lvl.pxWid, 1920)
				testing.expect_value(t, lvl.pxHei, 1088)

				// Test IntGrid querying
				colLayer := Ldtk_GetLayer(lvl, "Collisions")
				testing.expect(t, colLayer != nil, "Collisions layer should exist")
				if colLayer != nil {
					testing.expect_value(t, Ldtk_GetIntGridValue(colLayer, 0, 0), 1)
					testing.expect_value(t, Ldtk_GetIntGridValue(colLayer, 7, 17), 0)
					testing.expect_value(t, Ldtk_GetIntGridValue(colLayer, 35, 15), 2)
				}

				// Test Entity extraction
				playerEnt := Ldtk_GetEntity(lvl, "PlayerStart")
				testing.expect(t, playerEnt != nil, "PlayerStart entity should exist")
				if playerEnt != nil {
					testing.expect_value(t, playerEnt.px.x, f32(240.0))
					testing.expect_value(t, playerEnt.px.y, f32(544.0))
					testing.expect_value(t, Ldtk_GetFieldFloat(playerEnt, "shield"), f32(100.0))
					testing.expect_value(t, Ldtk_GetFieldString(playerEnt, "callsign"), "VIPER-ONE")
				}

				turrets := Ldtk_GetEntities(lvl, "Turret")
				testing.expect_value(t, len(turrets), 3)
			}

			Ldtk_DestroyProject(proj)
		}

		// 2. Scene Graph Node lifecycle, physics colliders generation, and entity spawning
		scene := game->createScene("ldtk_test_scene", true)
		ldtkNode := LdtkLevelNode_Create(scene, "StationLevel", "assets/levels/deep_space_station.ldtk", "Deep_Space_Station")
		testing.expect(t, ldtkNode != nil && ldtkNode.level != nil, "LdtkLevelNode should initialize level")

		// Spawner callback
		spawnerCalled := false
		ldtkNode.entitySpawner = proc(levelNode: ^LdtkLevelNode, entity: ^LdtkEntityInstance, s: ^Scene, ctx: ^GameContext) -> ^Node {
			child := CreateNodeScene(s, Node)
			child.name = entity.identifier
			child.position = entity.px
			(cast(^bool)levelNode.resource)^ = true
			return child
		}
		ldtkNode.resource = &spawnerCalled

		// Build physics colliders from IntGrid
		LdtkLevelNode_BuildCollisionBodies(ldtkNode, "Collisions", []int{1}, &game.gameContext)
		testing.expect(t, ldtkNode.staticBody != nil, "StaticBodyNode should be created for level colliders")
		if ldtkNode.staticBody != nil {
			testing.expect(t, len(ldtkNode.staticBody.shapes) > 0, "Shapes should be generated from solid walls")
		}

		// Spawn entities
		LdtkLevelNode_SpawnEntities(ldtkNode, &game.gameContext)
		testing.expect(t, spawnerCalled, "Entity spawner callback should have fired")
		testing.expect(t, len(ldtkNode.spawnedEntities) >= 10, "Entities should be spawned into level")

		// Run frame update
		game->run(0.016)

		game->terminate()
	})
}

// ============================================================================
// 6. Test Two-Tier Input System: Actions, States, Rebinding, & Entity Queries
// ============================================================================
@(test)
test_two_tier_input_system_actions_and_rebinding :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)

		scene := game->createScene("input_test_scene", true)
		mover := CharacterMoverNode_Create(scene, "InputMover")
		mover.position = {400, 300}
		mover.enableKeyboardInput = true

		// Frame 1: Press physical key 'D' (mapped by default to .MoveRight)
		Input_SetSimulatedKey(&game.input, .D, true)
		game->run(0.02)

		testing.expect(t, IsActionPressed(game, .MoveRight), "Frame 1: .MoveRight should be pressed when 'D' goes down")
		testing.expect(t, IsActionDown(&game.gameContext, .MoveRight), "Frame 1: .MoveRight should be down")
		testing.expect(t, !IsActionReleased(game, .MoveRight), "Frame 1: .MoveRight should not be released")
		testing.expect_value(t, GetActionAxis(game, .MoveLeft, .MoveRight), f32(1.0))
		testing.expect(t, mover.position.x > 400.0, "CharacterMoverNode should move right when .MoveRight action is active")

		// Frame 2: Hold physical key 'D' + also hold 'W' (.MoveUp)
		Input_SetSimulatedKey(&game.input, .W, true)
		game->run(0.02)

		testing.expect(t, !IsActionPressed(game, .MoveRight), "Frame 2: .MoveRight should no longer be newly pressed")
		testing.expect(t, IsActionDown(game, .MoveRight), "Frame 2: .MoveRight should still be held down")
		testing.expect(t, GetActionState(game, .MoveRight).durationHeld > 0.03, "durationHeld should accumulate while down")
		testing.expect(t, IsActionPressed(game, .MoveUp), "Frame 2: .MoveUp should be newly pressed")
		testing.expect_value(t, GetActionVector2(game, .MoveLeft, .MoveRight, .MoveUp, .MoveDown), [2]f32{1.0, -1.0})

		// Frame 3: Release 'D' and 'W'
		Input_SetSimulatedKey(&game.input, .D, false)
		Input_SetSimulatedKey(&game.input, .W, false)
		game->run(0.02)

		testing.expect(t, IsActionReleased(game, .MoveRight), "Frame 3: .MoveRight should be released on the frame 'D' goes up")
		testing.expect(t, !IsActionDown(game, .MoveRight), "Frame 3: .MoveRight should not be down")
		testing.expect(t, IsActionReleased(game, .MoveUp), "Frame 3: .MoveUp should be released")

		// Frame 4: Idle frame after release
		game->run(0.02)
		testing.expect(t, !IsActionReleased(game, .MoveRight), "Frame 4: .MoveRight released state should clear on next frame")

		// Test Rebinding: Rebind .Fire exclusively to KeyboardKey.K
		Input_BindKey(&game.input, .Fire, .K, true)

		// Old default key (.SPACE) should no longer trigger .Fire
		Input_SetSimulatedKey(&game.input, .SPACE, true)
		game->run(0.02)
		testing.expect(t, !IsActionDown(game, .Fire), "Old key .SPACE should not trigger .Fire after rebinding to .K")

		// New rebound key (.K) should trigger .Fire
		Input_SetSimulatedKey(&game.input, .SPACE, false)
		Input_SetSimulatedKey(&game.input, .K, true)
		game->run(0.02)
		testing.expect(t, IsActionPressed(game, .Fire), "New rebound key .K should trigger .Fire pressed")
		testing.expect(t, IsActionDown(game, .Fire), "New rebound key .K should trigger .Fire down")

		game->terminate()
	})
}

// ============================================================================
// 7. Test Node ready & update lifecycle procs, scene switching object destruction, & state reset
// ============================================================================
NodeLifecycleTestTracker :: struct {
	parentReadyCount: int,
	childReadyCount: int,
	childFoundByParentInReady: bool,
	parentUpdateCount: int,
	childUpdateCount: int,
	parentDestroyCount: int,
	childDestroyCount: int,
}
lifecycleTracker: NodeLifecycleTestTracker

NodeReadyTestParent_Ready :: proc(node: ^Node, ctx: ^GameContext) {
	lifecycleTracker.parentReadyCount += 1
	// The ready proc runs only once when the scene is loaded and ALL other initial scene nodes are preset!
	// Therefore, relative child lookup by path must succeed!
	childNode, found := GetNodeByPath(ctx.scene, node, "./ChildNode")
	if found && childNode != nil {
		lifecycleTracker.childFoundByParentInReady = true
	}
}

NodeReadyTestParent_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	lifecycleTracker.parentUpdateCount += 1
}

NodeReadyTestParent_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	lifecycleTracker.parentDestroyCount += 1
}

NodeReadyTestChild_Ready :: proc(node: ^Node, ctx: ^GameContext) {
	lifecycleTracker.childReadyCount += 1
}

NodeReadyTestChild_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	lifecycleTracker.childUpdateCount += 1
}

NodeReadyTestChild_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	lifecycleTracker.childDestroyCount += 1
}

NodeReadyScene_Setup :: proc(scene: ^Scene, ctx: ^GameContext) {
	parent := CreateNodeScene(scene, Node, true)
	parent.name = "ParentNode"
	parent.position = {100, 100}
	parent.ready = NodeReadyTestParent_Ready
	parent.update = NodeReadyTestParent_Update
	parent.onDestroy = NodeReadyTestParent_Destroy

	child := CreateNodeScene(scene, Node, false)
	child.name = "ChildNode"
	child.position = {20, 20}
	child.ready = NodeReadyTestChild_Ready
	child.update = NodeReadyTestChild_Update
	child.onDestroy = NodeReadyTestChild_Destroy
	scene->addNode(child, parent)
}

DummyScene_Setup :: proc(scene: ^Scene, ctx: ^GameContext) {
	dummy := CreateNodeScene(scene, Node, true)
	dummy.name = "DummyNode"
}

@(test)
test_node_ready_update_lifecycle_and_scene_destruction_reset :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		lifecycleTracker = NodeLifecycleTestTracker{}

		game := new(Game)
		InitializeGame(game)

		_ = game->createScene("ready_scene", true, NodeReadyScene_Setup)
		_ = game->createScene("dummy_scene", false, DummyScene_Setup)

		// Frame 1: Scene loads, builds initial nodes, calls ready ONCE on all nodes, then update runs
		game->run(0.016)

		testing.expect_value(t, lifecycleTracker.parentReadyCount, 1)
		testing.expect_value(t, lifecycleTracker.childReadyCount, 1)
		testing.expect(t, lifecycleTracker.childFoundByParentInReady, "Parent should find ChildNode during ready since all initial nodes are preset")
		testing.expect_value(t, lifecycleTracker.parentUpdateCount, 1)
		testing.expect_value(t, lifecycleTracker.childUpdateCount, 1)

		// Frame 2: ready must NOT run again; update continues
		game->run(0.016)
		testing.expect_value(t, lifecycleTracker.parentReadyCount, 1)
		testing.expect_value(t, lifecycleTracker.childReadyCount, 1)
		testing.expect_value(t, lifecycleTracker.parentUpdateCount, 2)
		testing.expect_value(t, lifecycleTracker.childUpdateCount, 2)

		// Switch scenes: "ready_scene" must be unloaded and all its nodes destroyed!
		game->changeScene("dummy_scene")
		game->run(0.016)
		testing.expect_value(t, game.sceneManager.currentScene.name, "dummy_scene")
		testing.expect_value(t, lifecycleTracker.parentDestroyCount, 1)
		testing.expect_value(t, lifecycleTracker.childDestroyCount, 1)

		// Switch back to "ready_scene": all state reset, fresh nodes instantiated, ready runs once again!
		game->changeScene("ready_scene")
		game->run(0.016)
		testing.expect_value(t, game.sceneManager.currentScene.name, "ready_scene")
		testing.expect_value(t, lifecycleTracker.parentReadyCount, 2) // Called once for fresh parent
		testing.expect_value(t, lifecycleTracker.childReadyCount, 2)  // Called once for fresh child
		testing.expect_value(t, lifecycleTracker.parentUpdateCount, 3)
		testing.expect_value(t, lifecycleTracker.childUpdateCount, 3)

		game->terminate()
	})
}

// ============================================================================
// 8. Test MusicNode Playback Controls, Looping, Streaming Update, & Resource Cleanup
// ============================================================================
@(test)
test_music_node_playback_controls_and_memory :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)

		scene := game->createScene("music_test_scene", true)

		// 1. Test ResourceManager AudioMusic caching, ref-counting, and querying
		musicPath := "assets/audio/cannon-gunshot-1.wav"
		audioMus, okLoad := game.resourceManager->loadAudioMusic(musicPath)
		testing.expect(t, okLoad, "loadAudioMusic should succeed for existing audio file")
		testing.expect(t, audioMus != nil, "audioMus pointer should be non-nil")
		testing.expect_value(t, audioMus.refCount, 1)

		// Calling load again on the same path increments refCount without reallocating
		audioMus2, okLoad2 := game.resourceManager->loadAudioMusic(musicPath)
		testing.expect(t, okLoad2 && audioMus2 == audioMus, "Duplicate loadAudioMusic should return cached pointer")
		testing.expect_value(t, audioMus.refCount, 2)

		// Query by fileName
		audioMusByName, okName := game.resourceManager->getAudioMusic("cannon-gunshot-1.wav")
		testing.expect(t, okName && audioMusByName == audioMus, "getAudioMusic by fileName should return cached pointer")
		testing.expect_value(t, audioMus.refCount, 3)

		game.resourceManager->unloadAudioMusic("cannon-gunshot-1.wav")
		testing.expect_value(t, audioMus.refCount, 2)
		game.resourceManager->unloadAudioMusic("cannon-gunshot-1.wav")
		testing.expect_value(t, audioMus.refCount, 1)

		// 2. Create MusicNode with autoplay=true and looping=false
		musicNode := MusicNode_Create(
			scene,
			&game.resourceManager,
			musicPath,
			"BackgroundMusic",
			autoplay = true,
			looping = false,
		)
		testing.expect(t, musicNode != nil, "MusicNode should be created")
		testing.expect_value(t, musicNode.name, "BackgroundMusic")
		testing.expect_value(t, musicNode.autoplay, true)
		testing.expect_value(t, musicNode.looping, false)
		testing.expect_value(t, musicNode.volume, f32(1.0))
		testing.expect_value(t, musicNode.pitch, f32(1.0))
		testing.expect_value(t, musicNode.pan, f32(0.5))

		// Provide a simulated length for headless test environment if raylib audio device is not opened
		if musicNode.timeLength <= 0 {
			musicNode.timeLength = 2.0
		}

		// 3. Test volume, pitch, pan, looping setters
		MusicNode_SetVolume(musicNode, 0.75)
		testing.expect_value(t, musicNode.volume, f32(0.75))

		MusicNode_SetPitch(musicNode, 1.25)
		testing.expect_value(t, musicNode.pitch, f32(1.25))

		MusicNode_SetPan(musicNode, 0.2)
		testing.expect_value(t, musicNode.pan, f32(0.2))
		// Pan 0 is left, 1 right on the mixer (-1 left .. 1 right; #216).
		testing.expect_value(t, music_mixer_pan(0), f32(-1))
		testing.expect_value(t, music_mixer_pan(0.5), f32(0))
		testing.expect_value(t, music_mixer_pan(1), f32(1))

		// 4. Test Autoplay on Ready:
		// Running 1 frame triggers scene loading & ready callback, which starts autoplay
		game->run(0.016)
		testing.expect(t, MusicNode_IsPlaying(musicNode), "Autoplay should set isPlaying to true after ready")
		testing.expect(t, !musicNode.isPaused, "Music should not be paused")

		// 5. Test streaming update and playback progress
		game->run(0.5)
		testing.expect(t, MusicNode_GetTimePlayed(musicNode) > 0.4, "timePlayed should advance during update")
		testing.expect(t, MusicNode_GetProgress(musicNode) > 0.2, "progress should advance")

		// 6. Test Pause & Resume
		playedBeforePause := MusicNode_GetTimePlayed(musicNode)
		MusicNode_Pause(musicNode)
		testing.expect(t, musicNode.isPaused, "musicNode.isPaused should be true")
		testing.expect(t, !MusicNode_IsPlaying(musicNode), "MusicNode_IsPlaying should return false when paused")

		game->run(0.5)
		testing.expect_value(t, MusicNode_GetTimePlayed(musicNode), playedBeforePause)

		MusicNode_Resume(musicNode)
		testing.expect(t, !musicNode.isPaused, "musicNode.isPaused should be false after resume")
		testing.expect(t, MusicNode_IsPlaying(musicNode), "MusicNode_IsPlaying should return true after resume")

		// 7. Test Seek
		MusicNode_Seek(musicNode, 1.5)
		testing.expect_value(t, MusicNode_GetTimePlayed(musicNode), f32(1.5))
		testing.expect_value(t, MusicNode_GetProgress(musicNode), f32(0.75))

		// Advance past end (length = 2.0) with looping = false -> music should stop
		game->run(0.6)
		testing.expect(t, !MusicNode_IsPlaying(musicNode), "Non-looping music should finish and stop when reaching end")
		testing.expect_value(t, MusicNode_GetTimePlayed(musicNode), musicNode.timeLength)

		// 8. Test Looping Playback
		MusicNode_SetLooping(musicNode, true)
		testing.expect(t, musicNode.looping, "Looping should be set to true")
		MusicNode_Play(musicNode)
		testing.expect(t, MusicNode_IsPlaying(musicNode), "Music should be playing")

		// Seek close to end and advance past length -> should wrap around and continue playing
		MusicNode_Seek(musicNode, 1.9)
		game->run(0.3)
		testing.expect(t, MusicNode_IsPlaying(musicNode), "Looping music should continue playing after wrap-around")
		testing.expect(t, MusicNode_GetTimePlayed(musicNode) < 1.0, "timePlayed should wrap around when looping")

		// 9. Test Stop
		MusicNode_Stop(musicNode)
		testing.expect(t, !MusicNode_IsPlaying(musicNode), "Music should not be playing after stop")
		testing.expect_value(t, MusicNode_GetTimePlayed(musicNode), f32(0.0))

		// 10. Terminate and verify clean memory deallocation (zero leaks, zero bad frees)
		game->terminate()
	})
}

// ============================================================================
// 9. Test CameraNode: Pan, Zoom, Rotate, Offset, Smoothing, Deadzones, Limits, Shake & Memory
// ============================================================================
@(test)
test_camera_node_features_and_memory :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)

		scene := game->createScene("camera_test_scene", true)

		// 1. Create moving Target Node
		targetNode := CreateNodeScene(scene, Node, true)
		targetNode.name = "PlayerTarget"
		targetNode.position = {640, 360}

		// 2. Create CameraNode and verify initial state
		cam := CameraNode_Create(scene, "MainCamera", isCurrent = true)
		testing.expect(t, cam != nil, "CameraNode should be created")
		testing.expect(t, scene.camera == cam, "Scene camera should point to CameraNode")
		testing.expect_value(t, cam.followMode, CameraFollowMode.SingleTarget)
		testing.expect_value(t, cam.zoom, f32(1.0))
		testing.expect_value(t, cam.rotation, f32(0.0))

		// 3. Set Target and verify follow smoothing
		CameraNode_SetTarget(cam, targetNode)
		CameraNode_SetOffset(cam, {0, -50})
		testing.expect_value(t, cam.target, targetNode)
		testing.expect_value(t, cam.offset, [2]f32{0, -50})

		// Frame 1: Ready initializes camera position to target + offset
		game->run(0.016)
		testing.expect(t, game.gameContext.camera == cam, "GameContext camera should point to Scene camera")
		testing.expect_value(t, cam.targetPosition, [2]f32{640, 310})

		// Move player target and run multiple frames with SmoothDamp
		targetNode.position = {800, 500}
		for _ in 0..<10 {
			game->run(0.05)
		}
		// Camera should have smoothed towards {800, 450}
		testing.expect(t, cam.currentPosition.x > 750.0, "Camera X should smoothly follow player to right")
		testing.expect(t, cam.currentPosition.y > 400.0, "Camera Y should smoothly follow player downwards")

		// 4. Test Manual Mode & Panning
		CameraNode_SetTarget(cam, nil)
		CameraNode_SetTargetPosition(cam, {200, 100})
		CameraNode_Pan(cam, {50, 25})
		testing.expect_value(t, cam.targetPosition, [2]f32{250, 125})
		testing.expect_value(t, cam.followMode, CameraFollowMode.Manual)

		// 5. Test Zoom and Rotation controls
		CameraNode_SetZoom(cam, 2.5)
		testing.expect_value(t, cam.targetZoom, f32(2.5))
		CameraNode_ZoomBy(cam, 1.2)
		testing.expect_value(t, cam.targetZoom, f32(3.0))

		CameraNode_SetRotation(cam, 45.0)
		testing.expect_value(t, cam.targetRotation, f32(45.0))
		CameraNode_RotateBy(cam, -15.0)
		testing.expect_value(t, cam.targetRotation, f32(30.0))

		for _ in 0..<15 {
			game->run(0.05)
		}
		testing.expect(t, cam.zoom > 2.8, "Camera zoom should smoothly reach targetZoom")
		testing.expect(t, cam.rotation > 25.0, "Camera rotation should smoothly reach targetRotation")

		// 6. Test Deadzones / Margins (Target inside deadzone does not move camera)
		targetNode.position = {500, 500}
		targetNode.globalPosition = {500, 500}
		CameraNode_SetTarget(cam, targetNode)
		cam.offset = {0, 0}
		CameraNode_Reset(cam)
		testing.expect_value(t, cam.currentPosition, [2]f32{500, 500})

		CameraNode_SetDeadzones(cam, left = 0.3, right = 0.3, top = 0.3, bottom = 0.3, horizontal = true, vertical = true)
		// Small movement within deadzone should keep camera targetPosition unchanged
		targetNode.position = {510, 510}
		targetNode.globalPosition = {510, 510}
		game->run(0.016)
		testing.expect_value(t, cam.targetPosition, [2]f32{500, 500})

		// 7. Test Boundaries / Limits (Camera cannot go outside bounds)
		CameraNode_SetLimits(cam, left = 0.0, right = 1000.0, top = 0.0, bottom = 800.0)
		testing.expect(t, cam.hasLimits, "hasLimits should be true")

		// Push target far to the right (+99999, +99999)
		targetNode.position = {99999.0, 99999.0}
		targetNode.globalPosition = {99999.0, 99999.0}
		for _ in 0..<20 {
			game->run(0.05)
		}
		// Visible view half-extents at zoom 3.0 are: viewW/2 = 1280/3/2 = ~213.3, viewH/2 = 720/3/2 = 120
		// Max camera center X must not exceed rightLimit - halfW (1000 - 213.3 = ~786.7)
		testing.expect(t, cam.currentPosition.x <= 800.0, "Camera position X should be clamped by rightLimit")
		testing.expect(t, cam.currentPosition.y <= 700.0, "Camera position Y should be clamped by bottomLimit")

		// 8. Test Multi-Target & Auto-Zoom
		CameraNode_ClearLimits(cam)
		CameraNode_ClearTargets(cam)
		target2 := CreateNodeScene(scene, Node, true)
		target2.name = "Target2"
		target2.position = {1200, 360}
		target2.globalPosition = {1200, 360}
		targetNode.position = {200, 360}
		targetNode.globalPosition = {200, 360}

		CameraNode_AddTargetNode(cam, targetNode, influence = {1, 1}, radius = 40.0)
		CameraNode_AddTargetNode(cam, target2, influence = {1, 1}, radius = 40.0)
		testing.expect_value(t, cam.followMode, CameraFollowMode.MultiTarget)
		testing.expect_value(t, len(cam.targets), 2)

		for _ in 0..<15 {
			game->run(0.05)
		}
		// Weighted average center of 200 and 1200 is 700
		testing.expect(t, cam.currentPosition.x > 650.0 && cam.currentPosition.x < 750.0, "Multi-target camera should center between targets")
		testing.expect(t, cam.zoom < 2.0, "Auto-zoom should zoom out to encapsulate both targets")

		// 9. Test Screen Shake (Preset & Offset evaluation)
		CameraNode_ApplyShakePreset(cam, CameraShakePreset.Explosion)
		testing.expect(t, CameraNode_IsShaking(cam), "Camera should be shaking after Explosion preset")
		testing.expect_value(t, cam.shakePreset, CameraShakePreset.Explosion)

		game->run(0.05)
		hasShakeOffset := (cam.shakeOffset.x != 0.0 || cam.shakeOffset.y != 0.0 || cam.shakeRotation != 0.0 || cam.shakeZoom != 0.0)
		testing.expect(t, hasShakeOffset, "Shake should generate non-zero offset/rotation/zoom displacement")

		CameraNode_StopShake(cam)
		testing.expect(t, !CameraNode_IsShaking(cam), "Camera should stop shaking")
		testing.expect_value(t, cam.shakeOffset, [2]f32{0, 0})

		// 10. Test Rooms & Magnets
		room := CameraRoom{
			id = "BossRoom",
			rect = {x = 100, y = 100, width = 600, height = 400},
			zoom = 1.5,
			priority = 10,
			openSides = {},
			enabled = true,
		}
		CameraNode_AddRoom(cam, room)
		testing.expect_value(t, len(cam.rooms), 1)

		magnet := CameraMagnet{
			id = "AnchorPoint",
			position = {400, 300},
			shape = .Circle,
			mode = .Attract,
			radius = 150.0,
			useFullForce = true,
			enabled = true,
		}
		CameraNode_AddMagnet(cam, magnet)
		testing.expect_value(t, len(cam.magnets), 1)

		// 11. Test ScreenToWorld and WorldToScreen Coordinate Transformations
		CameraNode_Reset(cam)
		cam.currentPosition = {640, 360}
		cam.currentOffset = {0, 0}
		cam.currentRotation = 0.0
		cam.rotation = 0.0
		cam.currentZoom = 1.0
		cam.zoom = 1.0

		worldPt := [2]f32{740, 410}
		scrPt := CameraNode_WorldToScreen(cam, worldPt, 1280, 720)
		// Offset is center {640, 360}, Target is {640, 360}, Zoom is 1.0 -> screen pt is {740, 410}
		testing.expect_value(t, scrPt, [2]f32{740, 410})
		recoveredWorld := CameraNode_ScreenToWorld(cam, scrPt, 1280, 720)
		testing.expect_value(t, recoveredWorld, worldPt)

		// 12. Terminate and verify clean memory deallocation (zero leaks, zero bad frees)
		game->terminate()
	})
}

// ============================================================================
// 10. Test UI Key Navigation: Tab, Shift+Tab, Directional Arrows, Enter & Space
// ============================================================================
@(test)
test_ui_keyboard_navigation_tab_arrows_enter_space :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		game.uiTestInputEnabled = true

		scene := game->createScene("ui_nav_test_scene", true)

		panel := UIPanelNode_Create(scene, "NavPanel", "Navigation Test", {100, 100}, {600, 500}, .Vertical)
		vbox := UIVerticalContainerNode_Create(scene, "NavVBox", {560, 440}, 8, .Stretch, panel)

		btn1Clicked := false
		btn1 := UIButtonNode_Create(scene, "Button1", "Btn 1", {120, 30}, vbox)
		btn1.onClick->subscribe(proc(source: rawptr, val: EventValue, ctx: ^GameContext, user_data: rawptr) {
			(cast(^bool)user_data)^ = true
		}, &btn1Clicked)

		btn2Clicked := false
		btn2 := UIButtonNode_Create(scene, "Button2", "Btn 2", {120, 30}, vbox)
		btn2.onClick->subscribe(proc(source: rawptr, val: EventValue, ctx: ^GameContext, user_data: rawptr) {
			(cast(^bool)user_data)^ = true
		}, &btn2Clicked)

		chk := UICheckboxNode_Create(scene, "TestChk", "Checkbox", false, vbox)
		toggle := UIToggleSwitchNode_Create(scene, "TestToggle", "Toggle", false, vbox)
		slider := UISliderNode_Create(scene, "TestSlider", "Slider", 50.0, 0.0, 100.0, vbox)
		radio := UIRadioGroupNode_Create(scene, "TestRadio", "Radio", {"Choice 1", "Choice 2", "Choice 3"}, 0, false, vbox)
		tabs := UITabContainerNode_Create(scene, "TestTabs", {"First", "Second", "Third"}, {10, 10}, {300, 100}, .Horizontal, 28, vbox)

		// Frame 1: Compute layout
		game->run(0.016)

		testing.expect(t, UI_GetFocusedElement(scene) == nil, "Initial state should have no focused UI element")

		// 1. Tab forward: focuses first focusable element (btn1)
		game.uiTestKeyTab = true
		game->run(0.016)
		game.uiTestKeyTab = false
		testing.expect(t, UI_GetFocusedElement(scene) == &btn1.ui, "Tab 1 should focus Button 1")
		testing.expect(t, btn1.ui.focused, "btn1.ui.focused should be true")

		// 2. Tab forward again: focuses btn2
		game.uiTestKeyTab = true
		game->run(0.016)
		game.uiTestKeyTab = false
		testing.expect(t, UI_GetFocusedElement(scene) == &btn2.ui, "Tab 2 should focus Button 2")

		// 3. Enter key on btn2: should fire onClick
		game.uiTestKeyEnter = true
		game->run(0.016)
		game.uiTestKeyEnter = false
		testing.expect(t, btn2Clicked, "Enter key should activate focused Button 2")

		// 4. Shift+Tab backward: should cycle back to btn1
		game.uiTestShiftDown = true
		game.uiTestKeyTab = true
		game->run(0.016)
		game.uiTestShiftDown = false
		game.uiTestKeyTab = false
		testing.expect(t, UI_GetFocusedElement(scene) == &btn1.ui, "Shift+Tab should focus back to Button 1")

		// 5. Space key on btn1: should fire onClick
		game.uiTestKeySpace = true
		game->run(0.016)
		game.uiTestKeySpace = false
		testing.expect(t, btn1Clicked, "Space key should activate focused Button 1")

		// 6. Down arrow from btn1 (spatial navigation): should navigate down to btn2
		game.uiTestKeyDown = true
		game->run(0.016)
		game.uiTestKeyDown = false
		testing.expect(t, UI_GetFocusedElement(scene) == &btn2.ui, "Down arrow from btn1 should navigate spatially to btn2")

		// Down arrow from btn2: should navigate down to chk
		game.uiTestKeyDown = true
		game->run(0.016)
		game.uiTestKeyDown = false
		testing.expect(t, UI_GetFocusedElement(scene) == &chk.ui, "Down arrow from btn2 should navigate to checkbox")

		// 7. Space key on checkbox: toggles checked
		testing.expect(t, !chk.checked, "chk should initially be unchecked")
		game.uiTestKeySpace = true
		game->run(0.016)
		game.uiTestKeySpace = false
		testing.expect(t, chk.checked, "Space key should toggle checkbox to checked")

		// 8. Down arrow to toggle switch
		game.uiTestKeyDown = true
		game->run(0.016)
		game.uiTestKeyDown = false
		testing.expect(t, UI_GetFocusedElement(scene) == &toggle.ui, "Down arrow should navigate to toggle switch")

		testing.expect(t, !toggle.active, "toggle switch should initially be inactive")
		game.uiTestKeyEnter = true
		game->run(0.016)
		game.uiTestKeyEnter = false
		testing.expect(t, toggle.active, "Enter key should toggle toggle switch to active")

		// Right arrow turns toggle on, Left arrow turns toggle off
		game.uiTestKeyLeft = true
		game->run(0.016)
		game.uiTestKeyLeft = false
		testing.expect(t, !toggle.active, "Left arrow should toggle switch to inactive")

		game.uiTestKeyRight = true
		game->run(0.016)
		game.uiTestKeyRight = false
		testing.expect(t, toggle.active, "Right arrow should toggle switch to active")

		// 9. Down arrow to slider
		game.uiTestKeyDown = true
		game->run(0.016)
		game.uiTestKeyDown = false
		testing.expect(t, UI_GetFocusedElement(scene) == &slider.ui, "Down arrow should navigate to slider")

		// Slider consumes Left / Right arrow keys to decrease / increase value
		initVal := slider.value
		game.uiTestKeyRight = true
		game->run(0.016)
		game.uiTestKeyRight = false
		testing.expect(t, slider.value > initVal, "Right arrow should increase slider value")

		higherVal := slider.value
		game.uiTestKeyLeft = true
		game->run(0.016)
		game.uiTestKeyLeft = false
		testing.expect(t, slider.value < higherVal, "Left arrow should decrease slider value")

		// 10. Down arrow from slider to radio group
		game.uiTestKeyDown = true
		game->run(0.016)
		game.uiTestKeyDown = false
		testing.expect(t, UI_GetFocusedElement(scene) == &radio.ui, "Down arrow should navigate to radio group")

		// Radio consumes Down/Up/Left/Right arrows to cycle options
		testing.expect_value(t, radio.selectedIndex, 0)
		game.uiTestKeyDown = true
		game->run(0.016)
		game.uiTestKeyDown = false
		testing.expect_value(t, radio.selectedIndex, 1)

		game.uiTestKeyUp = true
		game->run(0.016)
		game.uiTestKeyUp = false
		testing.expect_value(t, radio.selectedIndex, 0)

		// 11. Tab container focus and arrow navigation
		UI_SetFocus(scene, &tabs.ui)
		testing.expect(t, UI_GetFocusedElement(scene) == &tabs.ui, "Focus set to tab container")
		testing.expect_value(t, tabs.activeTab, 0)

		// Tab container consumes Right / Left arrow to switch tabs
		game.uiTestKeyRight = true
		game->run(0.016)
		game.uiTestKeyRight = false
		testing.expect_value(t, tabs.activeTab, 1)

		game.uiTestKeyLeft = true
		game->run(0.016)
		game.uiTestKeyLeft = false
		testing.expect_value(t, tabs.activeTab, 0)

		game->terminate()
	})
}

@(test)
test_ui_icon_and_toolbar_nodes :: proc(t: ^testing.T) {
	RunWithLeakTracking(t, proc(t: ^testing.T) {
		game := new(Game)
		InitializeGame(game)
		game.uiTestInputEnabled = true

		scene := game->createScene("ui_icon_toolbar_scene", true)

		// 1. Create UIIconNode
		iconNode := UIIconNode_Create(scene, "RocketIcon", icon = .Rocket, size = {32, 32}, iconSize = 24)
		testing.expect_value(t, iconNode.icon, Icon.Rocket)
		testing.expect_value(t, iconNode.iconSize, f32(24))

		// 2. Create UIButtonNode with Icon
		btnWithIcon := UIButtonNode_Create(scene, "SaveBtn", "Save", {120, 36}, icon = .FloppyDisk, iconSize = 18)
		testing.expect_value(t, btnWithIcon.icon, Icon.FloppyDisk)

		// 3. Create UIToolbarNode
		toolbar := UIToolbarNode_Create(scene, "AppToolbar", size = {500, 38})
		UIToolbarNode_AddItem(toolbar, 1, .File, "New", "Create File", .Button)
		UIToolbarNode_AddItem(toolbar, 2, .FolderOpen, "Open", "Open File", .Button)
		UIToolbarNode_AddItem(toolbar, 3, .FloppyDisk, "Save", "Save File", .Button)
		UIToolbarNode_AddItem(toolbar, 4, .None, itemType = .Separator)
		UIToolbarNode_AddItem(toolbar, 5, .Play, "Run", "Run scene", .Toggle, isSelected = true)

		testing.expect_value(t, len(toolbar.items), 5)
		testing.expect_value(t, toolbar.items[0].icon, Icon.File)
		testing.expect_value(t, toolbar.items[2].icon, Icon.FloppyDisk)
		testing.expect_value(t, toolbar.items[4].itemType, ToolbarItemType.Toggle)
		testing.expect_value(t, toolbar.items[4].isSelected, true)

		// Frame: compute layout & update
		game->run(0.016)

		game->terminate()
	})
}
