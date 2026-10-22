package editor

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Multi-Asset Preview Panel Subsystem
// Previews Textures, Audio Playback, Sprite Animations, Scene Data & Lua Script References
// ============================================================================

ScriptReference :: struct {
	sourceType: string, // "Active Scene", "Scene File", "Component"
	sourceName: string, // "battle_arena.scene.json" or "PlayerSpaceship.component.json"
	nodeName:   string, // "PlayerShip"
	nodeType:   string, // "TextureNode"
	isLiveNode: bool,
	liveNode:   ^e.Node,
}

// ----------------------------------------------------------------------------
// Asset & Node Selection Event Hooks
// ----------------------------------------------------------------------------

PreviewPanel_OnAssetSelected :: proc(state: ^EditorState, fullPath: string) {
	if state == nil || fullPath == "" do return

	ext := strings.to_lower(filepath.ext(fullPath), context.temp_allocator)

	switch ext {
	case ".png", ".jpg", ".jpeg", ".bmp", ".tga":
		PreviewPanel_LoadTexture(state, fullPath)
		if state.previewAutoSwitch {
			state.previewTab = .Texture
		}

	case ".wav", ".mp3", ".ogg", ".flac":
		PreviewPanel_LoadAudio(state, fullPath)
		if state.previewAutoSwitch {
			state.previewTab = .Audio
		}

	case ".scene.json", ".json":
		if strings.ends_with(fullPath, ".scene.json") {
			state.previewScenePath = strings.clone(fullPath)
			if state.previewAutoSwitch {
				state.previewTab = .Scene
			}
		} else if strings.ends_with(fullPath, ".component.json") {
			// Components can preview their script or texture
			state.previewScenePath = strings.clone(fullPath)
		}

	case ".lua":
		state.previewScriptPath = strings.clone(fullPath)
		if state.previewAutoSwitch {
			state.previewTab = .Script
		}
	}
}

PreviewPanel_OnNodeSelected :: proc(state: ^EditorState, node: ^e.Node) {
	if state == nil || node == nil do return

	if node.typeId == typeid_of(e.TextureNode) {
		tn := cast(^e.TextureNode)node
		if tn.filePath != "" {
			resolved := e.Project_ResolveAssetPath(&state.game.gameContext, tn.filePath)
			PreviewPanel_LoadTexture(state, resolved)
			if state.previewAutoSwitch {
				state.previewTab = .Texture
			}
		}
	} else if node.typeId == typeid_of(e.FrameAnimationNode) {
		PreviewPanel_LoadAnimationFromNode(state, cast(^e.FrameAnimationNode)node)
		if state.previewAutoSwitch {
			state.previewTab = .Animation
		}
	} else if node.typeId == typeid_of(e.SoundNode) {
		sn := cast(^e.SoundNode)node
		_ = sn
		if state.previewAutoSwitch {
			state.previewTab = .Audio
		}
	} else if node.scriptInstance != nil {
		inst := cast(^e.ScriptInstance)node.scriptInstance
		if inst.modulePath != "" {
			resolved := e.Project_ResolveAssetPath(&state.game.gameContext, inst.modulePath)
			state.previewScriptPath = strings.clone(resolved)
			if state.previewAutoSwitch {
				state.previewTab = .Script
			}
		}
	} else if node == state.activeScene.rootNode {
		if state.previewAutoSwitch {
			state.previewTab = .Scene
		}
	}
}

// ----------------------------------------------------------------------------
// Resource Loaders
// ----------------------------------------------------------------------------

PreviewPanel_LoadTexture :: proc(state: ^EditorState, fullPath: string) {
	if state.previewTexturePath == fullPath && state.previewTextureLoaded do return

	if state.previewTextureLoaded {
		rl.UnloadTexture(state.previewTexture)
		state.previewTextureLoaded = false
	}

	pathC := strings.clone_to_cstring(fullPath, context.temp_allocator)
	tex := rl.LoadTexture(pathC)
	if tex.id > 0 {
		state.previewTexture = tex
		state.previewTextureLoaded = true
		state.previewTexturePath = strings.clone(fullPath)
	}
}

PreviewPanel_LoadAudio :: proc(state: ^EditorState, fullPath: string) {
	if state.previewSoundPath == fullPath && state.previewSoundLoaded do return

	if state.previewSoundLoaded {
		if state.previewAudioPlaying {
			rl.StopSound(state.previewSound)
			state.previewAudioPlaying = false
		}
		rl.UnloadSound(state.previewSound)
		state.previewSoundLoaded = false
	}

	if !rl.IsAudioDeviceReady() {
		rl.InitAudioDevice()
	}

	pathC := strings.clone_to_cstring(fullPath, context.temp_allocator)
	snd := rl.LoadSound(pathC)
	if rl.IsSoundReady(snd) {
		state.previewSound = snd
		state.previewSoundLoaded = true
		state.previewSoundPath = strings.clone(fullPath)
		state.previewAudioPlaying = false
		state.previewAudioTimer = 0.0

		// Estimate duration: frameCount / sampleRate
		rate: f32 = 44100.0
		if snd.stream.sampleRate > 0 do rate = f32(snd.stream.sampleRate)
		state.previewAudioDuration = f32(snd.frameCount) / rate
		if state.previewAudioDuration <= 0 do state.previewAudioDuration = 1.0
	}
}

PreviewPanel_PlayAudio :: proc(state: ^EditorState) {
	if state == nil do return
	if rl.IsSoundReady(state.previewSound) {
		rl.SetSoundVolume(state.previewSound, state.previewAudioVolume)
		rl.PlaySound(state.previewSound)
		state.previewAudioPlaying = true
		state.previewAudioTimer = 0.0
	}
}

PreviewPanel_StopAudio :: proc(state: ^EditorState) {
	if state == nil do return
	if rl.IsSoundReady(state.previewSound) {
		rl.StopSound(state.previewSound)
	}
	state.previewAudioPlaying = false
	state.previewAudioTimer = 0.0
}

PreviewPanel_LoadAnimationFromNode :: proc(state: ^EditorState, fan: ^e.FrameAnimationNode) {
	if fan == nil || len(fan.frames) == 0 do return

	// Clear previous
	for &tex in state.previewAnimFrames {
		rl.UnloadTexture(tex)
	}
	clear(&state.previewAnimFrames)
	clear(&state.previewAnimPaths)

	for frame in fan.frames {
		if frame != nil && frame.texture.id > 0 {
			append(&state.previewAnimFrames, frame.texture)
			append(&state.previewAnimPaths, strings.clone(frame.filePath))
		}
	}

	state.previewAnimIndex = 0
	state.previewAnimTimer = 0.0
	state.previewAnimPlaying = true
	state.previewAnimLoadedPath = "Active FrameAnimationNode"
}

PreviewPanel_LoadAnimationFromFolder :: proc(state: ^EditorState, folderPath: string) {
	if state.previewAnimLoadedPath == folderPath && len(state.previewAnimFrames) > 0 do return

	for &tex in state.previewAnimFrames {
		rl.UnloadTexture(tex)
	}
	clear(&state.previewAnimFrames)
	clear(&state.previewAnimPaths)

	if h, err := os.open(folderPath); err == nil {
		fis, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)

		for fi in fis {
			if strings.has_suffix(fi.name, ".png") {
				p, _ := filepath.join({folderPath, fi.name}, context.temp_allocator)
				pathC := strings.clone_to_cstring(p, context.temp_allocator)
				tex := rl.LoadTexture(pathC)
				if tex.id > 0 {
					append(&state.previewAnimFrames, tex)
					append(&state.previewAnimPaths, strings.clone(fi.name))
				}
			}
		}
	}

	state.previewAnimIndex = 0
	state.previewAnimTimer = 0.0
	state.previewAnimPlaying = true
	state.previewAnimLoadedPath = strings.clone(folderPath)
}

// ----------------------------------------------------------------------------
// Main Panel Window Renderer
// ----------------------------------------------------------------------------

PreviewPanel_Render :: proc(state: ^EditorState) {
	defer imgui.End()
	if !imgui.Begin("Preview###PreviewPanelWindow") do return

	// Header: what is previewed, and a compact icon switcher (the preview
	// follows the selection automatically).
	assetName := "Nothing selected"
	if state.selectedAssetPath != "" {
		assetName = filepath.base(state.selectedAssetPath)
	} else if state.selectedNode != nil {
		assetName = state.selectedNode.name
	}
	modes := [?]struct {
		tab:  PreviewPanelTab,
		icon: string,
		tip:  string,
	}{
		{.Texture, ICON_FA_IMAGE, "Texture"},
		{.Audio, ICON_FA_MUSIC, "Audio"},
		{.Animation, ICON_FA_FILM, "Animation"},
		{.Scene, ICON_FA_CLAPPERBOARD, "Scene"},
		{.Script, ICON_FA_CODE, "Script"},
	}
	imgui.AlignTextToFramePadding()
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(assetName, context.temp_allocator))
	imgui.PopFont()
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - f32(len(modes)) * 26)
	imgui.PushStyleVarImVec2(.ItemSpacing, {0, 0})
	for m in modes {
		if UI_IconButton(m.icon, fmt.tprintf("preview.%v", m.tab), m.tip, state.previewTab == m.tab, size = 26) do state.previewTab = m.tab
		imgui.SameLine()
	}
	imgui.PopStyleVar()
	imgui.NewLine()

	switch state.previewTab {
	case .Texture: PreviewPanel_RenderTexture(state)
	case .Audio: PreviewPanel_RenderAudio(state)
	case .Animation: PreviewPanel_RenderAnimation(state)
	case .Scene: PreviewPanel_RenderScene(state)
	case .Script: PreviewPanel_RenderScript(state)
	}
}

// ----------------------------------------------------------------------------
// 1. Texture Preview Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderTexture :: proc(state: ^EditorState) {
	// Fallback check: if no texture loaded yet, attempt to load selected asset or default ship texture
	if !state.previewTextureLoaded {
		fallback := "assets/demo_project/textures/Spaceship_1.png"
		if state.selectedAssetPath != "" && strings.has_suffix(state.selectedAssetPath, ".png") {
			fallback = state.selectedAssetPath
		}
		if os.exists(fallback) {
			PreviewPanel_LoadTexture(state, fallback)
		}
	}

	// Quick Selector Combo for all textures
	texDir := "assets/demo_project/textures"
	if os.is_dir(texDir) {
		if h, err := os.open(texDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			curName := filepath.base(state.previewTexturePath)
			imgui.SetNextItemWidth(260)
			if imgui.BeginCombo("##TexSelectCombo", fmt.ctprintf("%s %s", ICON_FA_IMAGE, curName)) {
				for fi in fis {
					if strings.has_suffix(fi.name, ".png") {
						isSel := (fi.name == curName)
						if imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_IMAGE, fi.name), isSel) {
							p, _ := filepath.join({texDir, fi.name}, context.temp_allocator)
							PreviewPanel_LoadTexture(state, p)
						}
					}
				}
				imgui.EndCombo()
			}
		}
	}

	if !state.previewTextureLoaded || state.previewTexture.id == 0 {
		imgui.TextDisabled("No texture loaded. Select an image file (.png, .jpg) in the Asset Browser.")
		return
	}

	tex := state.previewTexture
	texW := f32(tex.width)
	texH := f32(tex.height)

	// Information badges
	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.75, 0.80, 0.88, 1.0}, fmt.ctprintf("[%dx%d px | ID: %d]", int(texW), int(texH), tex.id))

	imgui.SameLine()
	imgui.SetNextItemWidth(100)
	imgui.SliderFloat("Zoom", &state.previewTextureZoom, 0.25, 4.0, "%.2fx")

	imgui.SameLine()
	imgui.Checkbox("Fit", &state.previewTextureFit)
	preview_texture_import(state)

	imgui.Separator()

	// Canvas Region
	avail := imgui.GetContentRegionAvail()
	if avail.x <= 10 || avail.y <= 10 do return

	dispW := texW * state.previewTextureZoom
	dispH := texH * state.previewTextureZoom

	if state.previewTextureFit {
		aspect := texW / max(texH, 1.0)
		availAspect := avail.x / max(avail.y, 1.0)
		if availAspect > aspect {
			dispH = avail.y - 10.0
			dispW = dispH * aspect
		} else {
			dispW = avail.x - 10.0
			dispH = dispW / aspect
		}
	}

	if imgui.BeginChild("##TexCanvas", avail, {.Borders}, {.HorizontalScrollbar}) {
		// Draw checkerboard background for alpha transparency inspection
		p0 := imgui.GetCursorScreenPos()
		drawList := imgui.GetWindowDrawList()
		if drawList != nil {
			colA := col32(28, 32, 42, 255)
			colB := col32(38, 44, 58, 255)
			gridSz: f32 = 16.0
			for gy: f32 = 0; gy < dispH; gy += gridSz {
				for gx: f32 = 0; gx < dispW; gx += gridSz {
					c := (((int(gx/gridSz) + int(gy/gridSz)) % 2) == 0) ? colA : colB
					rx := p0.x + gx
					ry := p0.y + gy
					rw := min(gridSz, dispW - gx)
					rh := min(gridSz, dispH - gy)
					imgui.DrawList_AddRectFilled(drawList, imgui.Vec2{rx, ry}, imgui.Vec2{rx + rw, ry + rh}, c)
				}
			}
		}

		// Render the Texture image
		imgui.Image(
			transmute(imgui.TextureID)&state.previewTexture,
			imgui.Vec2{dispW, dispH},
			imgui.Vec2{0, 0},
			imgui.Vec2{1, 1},
			imgui.Vec4{1, 1, 1, 1},
			imgui.Vec4{0.25, 0.35, 0.50, 0.60},
		)

		if imgui.IsItemHovered() {
			mPos := imgui.GetIO().MousePos
			relX := int((mPos.x - p0.x) / max(dispW, 1.0) * texW)
			relY := int((mPos.y - p0.y) / max(dispH, 1.0) * texH)
			Editor_Tooltip(fmt.tprintf("Pixel: (%d, %d)", relX, relY))
		}
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// 2. Audio Playback Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderAudio :: proc(state: ^EditorState) {
	// Fallback check: if no sound loaded yet, load cannon-gunshot-1.wav
	if !state.previewSoundLoaded {
		fallback := "assets/demo_project/audio/cannon-gunshot-1.wav"
		if state.selectedAssetPath != "" && strings.has_suffix(state.selectedAssetPath, ".wav") {
			fallback = state.selectedAssetPath
		}
		if os.exists(fallback) {
			PreviewPanel_LoadAudio(state, fallback)
		}
	}

	// Quick Selector Combo for all audio clips
	audioDir := "assets/demo_project/audio"
	if os.is_dir(audioDir) {
		if h, err := os.open(audioDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			curName := filepath.base(state.previewSoundPath)
			imgui.SetNextItemWidth(260)
			if imgui.BeginCombo("##AudioSelectCombo", fmt.ctprintf("%s %s", ICON_FA_MUSIC, curName)) {
				for fi in fis {
					if strings.has_suffix(fi.name, ".wav") || strings.has_suffix(fi.name, ".ogg") || strings.has_suffix(fi.name, ".mp3") {
						isSel := (fi.name == curName)
						if imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_MUSIC, fi.name), isSel) {
							p, _ := filepath.join({audioDir, fi.name}, context.temp_allocator)
							PreviewPanel_LoadAudio(state, p)
						}
					}
				}
				imgui.EndCombo()
			}
		}
	}

	if !state.previewSoundLoaded {
		imgui.TextDisabled("No audio loaded. Select an audio file (.wav, .ogg) in the Asset Browser.")
		return
	}

	sndName := filepath.base(state.previewSoundPath)
	duration := state.previewAudioDuration

	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.75, 0.85, 0.95, 1.0}, fmt.ctprintf("[Duration: %.2fs | 44.1 kHz]", duration))

	imgui.Separator()

	// 1. Interactive Audio Controls Toolbar
	imgui.PushStyleVarImVec2(imgui.StyleVar.ItemSpacing, imgui.Vec2{8, 4})

	// Play button
	if state.previewAudioPlaying {
		imgui.PushStyleColorImVec4(imgui.Col.Button, imgui.Vec4{0.0, 0.65, 0.50, 1.0})
	}
	if imgui.Button(fmt.ctprintf("%s Play###AudioPlayBtn", ICON_FA_PLAY), imgui.Vec2{72, 28}) {
		PreviewPanel_PlayAudio(state)
	}
	if state.previewAudioPlaying {
		imgui.PopStyleColor()
	}

	// Stop button
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s Stop###AudioStopBtn", ICON_FA_STOP), imgui.Vec2{72, 28}) {
		PreviewPanel_StopAudio(state)
	}

	// Loop toggle
	imgui.SameLine()
	imgui.Checkbox("Loop", &state.previewAudioLoop)

	// Volume slider
	imgui.SameLine()
	imgui.SetNextItemWidth(120)
	if imgui.SliderFloat("Volume", &state.previewAudioVolume, 0.0, 1.0, "%.0f%%") {
		if rl.IsSoundReady(state.previewSound) {
			rl.SetSoundVolume(state.previewSound, state.previewAudioVolume)
		}
	}

	imgui.PopStyleVar()

	// Advance playback timer
	if state.previewAudioPlaying {
		dt := rl.GetFrameTime()
		state.previewAudioTimer += dt
		if state.previewAudioTimer >= duration {
			if state.previewAudioLoop {
				state.previewAudioTimer = 0.0
				rl.PlaySound(state.previewSound)
			} else {
				state.previewAudioPlaying = false
				state.previewAudioTimer = 0.0
			}
		}
	}

	// 2. Playback Scrubber & Progress Bar
	prog := math.clamp(state.previewAudioTimer / max(duration, 0.001), f32(0.0), f32(1.0))
	timeStr := fmt.tprintf("%.2fs / %.2fs", state.previewAudioTimer, duration)
	timeC := strings.clone_to_cstring(timeStr, context.temp_allocator)
	imgui.ProgressBar(prog, imgui.Vec2{-1, 16}, timeC)

	// 3. Real-Time Animated Spectrum Waveform Visualizer
	avail := imgui.GetContentRegionAvail()
	if avail.x > 20 && avail.y > 40 {
		if imgui.BeginChild("##WaveformChild", imgui.Vec2{-1, max(avail.y, 60)}, {.Borders}, {}) {
			p0 := imgui.GetCursorScreenPos()
			wSize := imgui.GetWindowSize()
			drawList := imgui.GetWindowDrawList()

			if drawList != nil {
				// Dark studio waveform background
				imgui.DrawList_AddRectFilled(drawList, p0, imgui.Vec2{p0.x + wSize.x, p0.y + wSize.y}, col32(16, 20, 28, 255))

				// Center line
				midY := p0.y + wSize.y * 0.5
				imgui.DrawList_AddLine(drawList, imgui.Vec2{p0.x, midY}, imgui.Vec2{p0.x + wSize.x, midY}, col32(45, 55, 75, 180), 1.0)

				barCount := 36
				barW := (wSize.x - 20.0) / f32(barCount)
				baseAmp: f32 = 8.0
				nowT := f32(rl.GetTime())

				for i := 0; i < barCount; i += 1 {
					bx := p0.x + 10.0 + f32(i) * barW

					// Frequency height response
					barHeight: f32 = baseAmp
					if state.previewAudioPlaying {
						freq := f32(i) * 0.4
						wave := math.sin(nowT * 14.0 + freq) * math.cos(nowT * 8.0 - f32(i) * 0.2)
						barHeight = baseAmp + math.abs(wave) * (wSize.y * 0.42)
					}

					bTop := midY - barHeight * 0.5
					bBot := midY + barHeight * 0.5

					// Dynamic audio visualizer color gradient (Teal -> Emerald -> Amber)
					barCol := col32(0, 206, 201, 220)
					if i > 24 {
						barCol = col32(255, 195, 18, 240)
					} else if i > 14 {
						barCol = col32(46, 213, 115, 230)
					}

					imgui.DrawList_AddRectFilled(drawList, imgui.Vec2{bx + 1, bTop}, imgui.Vec2{bx + barW - 2, bBot}, barCol, 2.0)
				}
			}
		}
		imgui.EndChild()
	}
}

// ----------------------------------------------------------------------------
// 3. Animation Preview Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderAnimation :: proc(state: ^EditorState) {
	// Auto-load exhaust animation frames if empty
	if len(state.previewAnimFrames) == 0 {
		exhaustFolder := "assets/demo_project/textures/exhaust"
		if os.is_dir(exhaustFolder) {
			PreviewPanel_LoadAnimationFromFolder(state, exhaustFolder)
		}
	}

	// Animation Set Selector
	curAnimName := state.previewAnimLoadedPath
	imgui.SetNextItemWidth(260)
	if imgui.BeginCombo("##AnimSetCombo", fmt.ctprintf("%s %s", ICON_FA_FILM, curAnimName)) {
		if imgui.Selectable("Engine Exhaust (5 frames)", curAnimName == "assets/demo_project/textures/exhaust") {
			PreviewPanel_LoadAnimationFromFolder(state, "assets/demo_project/textures/exhaust")
		}
		if state.activeScene != nil && state.activeScene.rootNode != nil {
			if imgui.Selectable("Active Scene Exhaust Node", curAnimName == "Active FrameAnimationNode") {
				// Search for FrameAnimationNode
				for n in state.activeScene.manager.nodes {
					if n != nil && n.typeId == typeid_of(e.FrameAnimationNode) {
						PreviewPanel_LoadAnimationFromNode(state, cast(^e.FrameAnimationNode)n)
						break
					}
				}
			}
		}
		imgui.EndCombo()
	}

	frameCount := len(state.previewAnimFrames)
	if frameCount == 0 {
		imgui.TextDisabled("No animation frames found. Add an animation or select a FrameAnimationNode.")
		return
	}

	// 1. Playback Controls Toolbar
	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.75, 0.85, 0.95, 1.0}, fmt.ctprintf("[%d Frames | Frame: %d / %d]", frameCount, state.previewAnimIndex + 1, frameCount))

	imgui.Separator()

	imgui.PushStyleVarImVec2(imgui.StyleVar.ItemSpacing, imgui.Vec2{6, 4})

	// First Frame
	if imgui.Button(fmt.ctprintf("%s###AnimFirst", ICON_FA_BACKWARD_STEP), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = 0
	}
	// Prev Frame
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s###AnimPrev", ICON_FA_CHEVRON_LEFT), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = (state.previewAnimIndex - 1 + frameCount) % frameCount
	}
	// Play / Pause
	imgui.SameLine()
	playIcon := state.previewAnimPlaying ? ICON_FA_PAUSE : ICON_FA_PLAY
	if imgui.Button(fmt.ctprintf("%s###AnimPlay", playIcon), imgui.Vec2{36, 26}) {
		state.previewAnimPlaying = !state.previewAnimPlaying
	}
	// Next Frame
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s###AnimNext", ICON_FA_CHEVRON_RIGHT), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = (state.previewAnimIndex + 1) % frameCount
	}
	// Last Frame
	imgui.SameLine()
	if imgui.Button(fmt.ctprintf("%s###AnimLast", ICON_FA_FORWARD_STEP), imgui.Vec2{30, 26}) {
		state.previewAnimIndex = frameCount - 1
	}

	// FPS drag
	imgui.SameLine()
	imgui.SetNextItemWidth(80)
	imgui.DragFloat("##AnimFPS", &state.previewAnimFPS, 1.0, 1.0, 60.0, "%.0f FPS")

	// Loop
	imgui.SameLine()
	imgui.Checkbox("Loop", &state.previewAnimLoop)

	imgui.PopStyleVar()

	// Advance animation frame
	if state.previewAnimPlaying && state.previewAnimFPS > 0 {
		dt := rl.GetFrameTime()
		state.previewAnimTimer += dt
		frameDur := 1.0 / state.previewAnimFPS
		if state.previewAnimTimer >= frameDur {
			state.previewAnimTimer = 0.0
			state.previewAnimIndex += 1
			if state.previewAnimIndex >= frameCount {
				if state.previewAnimLoop {
					state.previewAnimIndex = 0
				} else {
					state.previewAnimIndex = frameCount - 1
					state.previewAnimPlaying = false
				}
			}
		}
	}

	// 2. Active Frame Viewport
	state.previewAnimIndex = math.clamp(state.previewAnimIndex, 0, frameCount - 1)
	activeTex := state.previewAnimFrames[state.previewAnimIndex]

	avail := imgui.GetContentRegionAvail()
	filmstripHeight: f32 = 64.0
	viewH := max(avail.y - filmstripHeight - 12.0, 80.0)

	if imgui.BeginChild("##AnimViewChild", imgui.Vec2{-1, viewH}, {.Borders}, {}) {
		p0 := imgui.GetCursorScreenPos()
		wSize := imgui.GetWindowSize()

		dispSz: f32 = min(wSize.x - 20.0, wSize.y - 20.0)
		posX := p0.x + (wSize.x - dispSz) * 0.5
		posY := p0.y + (wSize.y - dispSz) * 0.5

		imgui.SetCursorScreenPos(imgui.Vec2{posX, posY})
		imgui.Image(
			transmute(imgui.TextureID)&activeTex,
			imgui.Vec2{dispSz, dispSz},
			imgui.Vec2{0, 0},
			imgui.Vec2{1, 1},
			imgui.Vec4{1, 1, 1, 1},
			imgui.Vec4{0.0, 0.85, 0.75, 0.40},
		)
	}
	imgui.EndChild()

	// 3. Filmstrip of All Thumbnails
	if imgui.BeginChild("##AnimFilmstrip", imgui.Vec2{-1, filmstripHeight}, {}, {.HorizontalScrollbar}) {
		imgui.PushStyleVarImVec2(imgui.StyleVar.ItemSpacing, imgui.Vec2{6, 2})
		for idx in 0..<frameCount {
			if idx > 0 do imgui.SameLine()
			thumbTex := state.previewAnimFrames[idx]
			isCur := (idx == state.previewAnimIndex)

			borderCol := isCur ? imgui.Vec4{0.0, 0.85, 0.75, 1.0} : imgui.Vec4{0.25, 0.30, 0.40, 0.50}

			imgui.PushIDInt(c.int(idx))
			if imgui.ImageButton(
				fmt.ctprintf("###thumb_%d", idx),
				transmute(imgui.TextureID)&thumbTex,
				imgui.Vec2{48, 48},
				imgui.Vec2{0, 0},
				imgui.Vec2{1, 1},
				imgui.Vec4{0.1, 0.12, 0.16, 1.0},
				imgui.Vec4{1, 1, 1, 1},
			) {
				state.previewAnimIndex = idx
			}
			imgui.PopID()
			Editor_Tooltip(fmt.tprintf("Frame %d", idx + 1))
		}
		imgui.PopStyleVar()
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// 4. Scene Data Inspection Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderScene :: proc(state: ^EditorState) {
	scene := state.activeScene
	if scene == nil {
		imgui.TextDisabled("No active scene in editor.")
		return
	}

	// Header summary cards
	imgui.TextColored(imgui.Vec4{0.0, 0.85, 0.75, 1.0}, fmt.ctprintf("%s  %s", ICON_FA_CLAPPERBOARD, scene.name))
	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.46, 0.85, 0.45, 1.0}, "[ACTIVE VIEWPORT SCENE]")

	imgui.Separator()

	// Metrics Overview Grid
	nodeCount := len(scene.manager.nodes) if scene.manager != nil else 0
	camTarget := scene.camera.currentPosition if scene.camera != nil else [2]f32{640, 360}
	camZoom := scene.camera.currentZoom if scene.camera != nil else 1.0
	grav := state.game.physicsWorld.gravity

	if imgui.BeginTable("##SceneMetricsTable", 4, imgui.TableFlags_BordersInnerV | imgui.TableFlags_BordersOuter) {
		imgui.TableNextRow()
		imgui.TableSetColumnIndex(0); imgui.TextDisabled("Total Nodes:"); imgui.Text(fmt.ctprintf("%d", nodeCount))
		imgui.TableSetColumnIndex(1); imgui.TextDisabled("Camera Focus:"); imgui.Text(fmt.ctprintf("[%.0f, %.0f]", camTarget.x, camTarget.y))
		imgui.TableSetColumnIndex(2); imgui.TextDisabled("Camera Zoom:"); imgui.Text(fmt.ctprintf("%.2fx", camZoom))
		imgui.TableSetColumnIndex(3); imgui.TextDisabled("World Gravity:"); imgui.Text(fmt.ctprintf("[%.1f, %.1f]", grav.x, grav.y))
		imgui.EndTable()
	}

	imgui.Spacing()

	// Complete Hierarchy Breakdown Table
	imgui.TextColored(imgui.Vec4{0.85, 0.90, 0.95, 1.0}, "Scene Node Breakdown:")
	if imgui.BeginTable("##SceneNodeTable", 6, imgui.TableFlags_Resizable | imgui.TableFlags_Reorderable | imgui.TableFlags_RowBg | imgui.TableFlags_Borders | imgui.TableFlags_ScrollY) {
		imgui.TableSetupColumn("Node Name", {.WidthStretch})
		imgui.TableSetupColumn("Type", {.WidthFixed}, 120)
		imgui.TableSetupColumn("Layer", {.WidthFixed}, 60)
		imgui.TableSetupColumn("Position", {.WidthFixed}, 110)
		imgui.TableSetupColumn("Scale", {.WidthFixed}, 90)
		imgui.TableSetupColumn("Script Attached", {.WidthStretch})
		imgui.TableHeadersRow()

		if scene.manager != nil {
			for n in scene.manager.nodes {
				if n == nil do continue

				imgui.TableNextRow()
				isSelected := (n == state.selectedNode)
				if isSelected {
					imgui.TableSetBgColor(.RowBg0, col32(0, 168, 150, 60))
				}

				imgui.TableSetColumnIndex(0)
				nameStr := fmt.ctprintf("%s  %s", ICON_FA_FILE, n.name)
				if imgui.Selectable(nameStr, isSelected, {.SpanAllColumns}) {
					state.selectedNode = n
				}

				imgui.TableSetColumnIndex(1)
				imgui.Text(fmt.ctprintf("%v", n.typeId))

				imgui.TableSetColumnIndex(2)
				imgui.Text(fmt.ctprintf("%v", n.layer))

				imgui.TableSetColumnIndex(3)
				imgui.Text(fmt.ctprintf("[%.1f, %.1f]", n.position.x, n.position.y))

				imgui.TableSetColumnIndex(4)
				imgui.Text(fmt.ctprintf("[%.2f, %.2f]", n.scale.x, n.scale.y))

				imgui.TableSetColumnIndex(5)
				if n.scriptInstance != nil {
					inst := cast(^e.ScriptInstance)n.scriptInstance
					imgui.TextColored(imgui.Vec4{0.95, 0.77, 0.15, 1.0}, fmt.ctprintf("%s %s", ICON_FA_CODE, inst.modulePath))
				} else {
					imgui.TextDisabled("None")
				}
			}
		}
		imgui.EndTable()
	}
}

// ----------------------------------------------------------------------------
// 5. Lua Script Inspection & References Subsystem
// ----------------------------------------------------------------------------

PreviewPanel_RenderScript :: proc(state: ^EditorState) {
	// Fallback to player_ship.lua if nothing selected
	if state.previewScriptPath == "" {
		state.previewScriptPath = "assets/demo_project/scripts/player_ship.lua"
	}

	// Quick Selector Combo for all Lua scripts in project
	scriptsDir := "assets/demo_project/scripts"
	if os.is_dir(scriptsDir) {
		if h, err := os.open(scriptsDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			curName := filepath.base(state.previewScriptPath)
			imgui.SetNextItemWidth(260)
			if imgui.BeginCombo("##ScriptSelectCombo", fmt.ctprintf("%s %s", ICON_FA_CODE, curName)) {
				for fi in fis {
					if strings.has_suffix(fi.name, ".lua") {
						isSel := (fi.name == curName)
						if imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_CODE, fi.name), isSel) {
							p, _ := filepath.join({scriptsDir, fi.name}, context.temp_allocator)
							state.previewScriptPath = strings.clone(p)
						}
					}
				}
				imgui.EndCombo()
			}
		}
	}

	scriptPath := state.previewScriptPath
	scriptName := filepath.base(scriptPath)

	imgui.SameLine()
	imgui.TextColored(imgui.Vec4{0.95, 0.77, 0.15, 1.0}, fmt.ctprintf("%s [Lua 5.4 Module]", scriptName))

	imgui.Separator()

	// 1. Exported Properties Table (inspected via engine ScriptManager)
	props, hasProps := e.Script_InspectProperties(scriptPath, state.game.gameContext.scriptManager)
	if hasProps && len(props) > 0 {
		imgui.TextColored(imgui.Vec4{0.0, 0.85, 0.75, 1.0}, fmt.ctprintf("Exported Script Properties (%d):", len(props)))
		if imgui.BeginTable("##ScriptPropsTable", 5, imgui.TableFlags_Resizable | imgui.TableFlags_RowBg | imgui.TableFlags_Borders) {
			imgui.TableSetupColumn("Property", {.WidthFixed}, 130)
			imgui.TableSetupColumn("Type", {.WidthFixed}, 80)
			imgui.TableSetupColumn("Default Value", {.WidthFixed}, 110)
			imgui.TableSetupColumn("Range [Min .. Max]", {.WidthFixed}, 140)
			imgui.TableSetupColumn("Inspector Label", {.WidthStretch})
			imgui.TableHeadersRow()

			for prop in props {
				imgui.TableNextRow()
				imgui.TableSetColumnIndex(0); imgui.Text(fmt.ctprintf("%s", prop.name))
				imgui.TableSetColumnIndex(1); imgui.Text(fmt.ctprintf("%v", prop.type))

				imgui.TableSetColumnIndex(2)
				#partial switch prop.type {
				case .Float: imgui.Text(fmt.ctprintf("%.2f", prop.defaultVal.valFloat))
				case .Int: imgui.Text(fmt.ctprintf("%d", prop.defaultVal.valInt))
				case .String: imgui.Text(fmt.ctprintf("\"%s\"", prop.defaultVal.valString))
				case .Boolean: imgui.Text(fmt.ctprintf("%t", prop.defaultVal.valBool))
				case .Vector2: imgui.Text(fmt.ctprintf("[%.1f, %.1f]", prop.defaultVal.valVec2.x, prop.defaultVal.valVec2.y))
				case: imgui.Text("-")
				}

				imgui.TableSetColumnIndex(3)
				if prop.min != 0 || prop.max != 0 {
					imgui.Text(fmt.ctprintf("[%.1f .. %.1f]", prop.min, prop.max))
				} else {
					imgui.TextDisabled("Unlimited")
				}

				imgui.TableSetColumnIndex(4)
				imgui.Text(fmt.ctprintf("%s", prop.label if prop.label != "" else prop.name))
			}
			imgui.EndTable()
		}
	}

	imgui.Spacing()

	// 2. SCRIPT REFERENCES & USAGE: Where this script is used across project scenes & components
	refs := PreviewPanel_FindScriptReferences(state, scriptName)
	defer delete(refs)

	imgui.TextColored(imgui.Vec4{0.95, 0.77, 0.15, 1.0}, fmt.ctprintf("%s  Script References & Usage Across Project (%d occurrences):", ICON_FA_MAGNIFYING_GLASS, len(refs)))

	if len(refs) == 0 {
		imgui.TextDisabled("No active nodes or scene references currently use this script.")
	} else {
		if imgui.BeginTable("##ScriptRefsTable", 5, imgui.TableFlags_Resizable | imgui.TableFlags_RowBg | imgui.TableFlags_Borders) {
			imgui.TableSetupColumn("Source / Container", {.WidthFixed}, 160)
			imgui.TableSetupColumn("Node Name", {.WidthFixed}, 150)
			imgui.TableSetupColumn("Node Type", {.WidthFixed}, 120)
			imgui.TableSetupColumn("Scope", {.WidthFixed}, 110)
			imgui.TableSetupColumn("Action", {.WidthFixed}, 120)
			imgui.TableHeadersRow()

			for ref, idx in refs {
				imgui.TableNextRow()
				imgui.TableSetColumnIndex(0)
				icon := (ref.sourceType == "Component") ? ICON_FA_CUBES : ICON_FA_CLAPPERBOARD
				imgui.Text(fmt.ctprintf("%s  %s", icon, ref.sourceName))

				imgui.TableSetColumnIndex(1)
				imgui.TextColored(imgui.Vec4{0.90, 0.95, 1.0, 1.0}, fmt.ctprintf("%s", ref.nodeName))

				imgui.TableSetColumnIndex(2)
				imgui.Text(fmt.ctprintf("%s", ref.nodeType))

				imgui.TableSetColumnIndex(3)
				if ref.isLiveNode {
					imgui.TextColored(imgui.Vec4{0.0, 0.85, 0.65, 1.0}, "Live In Viewport")
				} else {
					imgui.TextDisabled("Serialized File")
				}

				imgui.TableSetColumnIndex(4)
				if ref.isLiveNode && ref.liveNode != nil {
					imgui.PushIDInt(c.int(idx))
					if imgui.Button("Select Node") {
						state.selectedNode = ref.liveNode
						Editor_Log(state, .Info, "Selected script node: %s", ref.nodeName)
					}
					imgui.PopID()
				} else {
					imgui.TextDisabled("-")
				}
			}
			imgui.EndTable()
		}
	}

	imgui.Spacing()

	// 3. Lua Source Code Previewer with Syntax Viewer
	if bytes, err := os.read_entire_file(scriptPath, context.temp_allocator); err == nil {
		lines := strings.split_lines(string(bytes), context.temp_allocator)
		header := fmt.ctprintf("Lua Source Code (%d lines)###ScriptSourceHeader", len(lines))
		if imgui.CollapsingHeader(header, {.DefaultOpen}) {
			avail := imgui.GetContentRegionAvail()
			if imgui.BeginChild("##ScriptSourceCodeChild", imgui.Vec2{-1, min(avail.y, 220)}, {.Borders}, {}) {
				imgui.PushStyleColorImVec4(imgui.Col.Text, imgui.Vec4{0.80, 0.85, 0.92, 1.0})
				for line, lineIdx in lines {
					lineNumStr := fmt.tprintf("%3d |  ", lineIdx + 1)
					imgui.TextDisabled(strings.clone_to_cstring(lineNumStr, context.temp_allocator))
					imgui.SameLine()
					// Highlight comment lines
					trimmed := strings.trim_space(line)
					if strings.has_prefix(trimmed, "--") {
						imgui.TextColored(imgui.Vec4{0.45, 0.55, 0.65, 1.0}, strings.clone_to_cstring(line, context.temp_allocator))
					} else {
						imgui.Text(strings.clone_to_cstring(line, context.temp_allocator))
					}
				}
				imgui.PopStyleColor()
			}
			imgui.EndChild()
		}
	}
}

// Scans active scene, disk scenes, and components to find all references to a script
PreviewPanel_FindScriptReferences :: proc(state: ^EditorState, scriptBaseName: string) -> [dynamic]ScriptReference {
	refs := make([dynamic]ScriptReference, context.allocator)

	// 1. Scan Active Scene nodes
	if state.activeScene != nil && state.activeScene.manager != nil {
		for n in state.activeScene.manager.nodes {
			if n == nil do continue

			matches := false
			if n.scriptInstance != nil {
				inst := cast(^e.ScriptInstance)n.scriptInstance
				if strings.contains(inst.modulePath, scriptBaseName) {
					matches = true
				}
			} else if n.typeId == typeid_of(e.ScriptNode) {
				sn := cast(^e.ScriptNode)n
				if strings.contains(sn.scriptPath, scriptBaseName) {
					matches = true
				}
			}

			if matches {
				append(&refs, ScriptReference{
					sourceType = "Active Scene",
					sourceName = state.activeScene.name,
					nodeName   = n.name,
					nodeType   = fmt.tprintf("%v", n.typeId),
					isLiveNode = true,
					liveNode   = n,
				})
			}
		}
	}

	// 2. Scan Project Scene Files on Disk
	scenesDir := "assets/demo_project/scenes"
	if os.is_dir(scenesDir) {
		if h, err := os.open(scenesDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			for fi in fis {
				if strings.ends_with(fi.name, ".scene.json") {
					p, _ := filepath.join({scenesDir, fi.name}, context.temp_allocator)
					if bytes, rErr := os.read_entire_file(p, context.temp_allocator); rErr == nil {
						// Fast substring check
						if strings.contains(string(bytes), scriptBaseName) {
							// Parse to find specific nodes
							if val, pErr := json.parse(bytes, allocator = context.temp_allocator); pErr == .None {
								if rootObj, isObj := val.(json.Object); isObj {
									if rNode, hasRoot := rootObj["root"].(json.Object); hasRoot {
										find_script_refs_in_json_node(rNode, fi.name, "Scene File", scriptBaseName, &refs)
									}
								}
							}
						}
					}
				}
			}
		}
	}

	// 3. Scan Components on Disk
	compDir := "assets/demo_project/components"
	if os.is_dir(compDir) {
		if h, err := os.open(compDir); err == nil {
			fis, _ := os.read_dir(h, -1, context.temp_allocator)
			os.close(h)

			for fi in fis {
				if strings.ends_with(fi.name, ".component.json") {
					p, _ := filepath.join({compDir, fi.name}, context.temp_allocator)
					if bytes, rErr := os.read_entire_file(p, context.temp_allocator); rErr == nil {
						if strings.contains(string(bytes), scriptBaseName) {
							nameVal := fi.name
							typeVal := "Component"
							if val, pErr := json.parse(bytes, allocator = context.temp_allocator); pErr == .None {
								if compObj, isObj := val.(json.Object); isObj {
									if n, ok := compObj["name"].(json.String); ok do nameVal = n
									if t, ok := compObj["type"].(json.String); ok do typeVal = t
								}
							}
							append(&refs, ScriptReference{
								sourceType = "Component",
								sourceName = fi.name,
								nodeName   = nameVal,
								nodeType   = typeVal,
								isLiveNode = false,
								liveNode   = nil,
							})
						}
					}
				}
			}
		}
	}

	return refs
}

@(private="file")
find_script_refs_in_json_node :: proc(
	nodeObj: json.Object,
	sourceName: string,
	sourceType: string,
	scriptBaseName: string,
	refs: ^[dynamic]ScriptReference,
) {
	nodeName := "Node"
	if n, ok := nodeObj["name"].(json.String); ok do nodeName = n
	nodeType := "Node"
	if t, ok := nodeObj["type"].(json.String); ok do nodeType = t

	// Check script object
	if sObj, hasScript := nodeObj["script"].(json.Object); hasScript {
		if p, hasPath := sObj["path"].(json.String); hasPath {
			if strings.contains(p, scriptBaseName) {
				append(refs, ScriptReference{
					sourceType = sourceType,
					sourceName = sourceName,
					nodeName   = nodeName,
					nodeType   = nodeType,
					isLiveNode = false,
					liveNode   = nil,
				})
			}
		}
	}

	// Recursively check children
	if childrenArr, hasChildren := nodeObj["children"].(json.Array); hasChildren {
		for childVal in childrenArr {
			if childObj, isObj := childVal.(json.Object); isObj {
				find_script_refs_in_json_node(childObj, sourceName, sourceType, scriptBaseName, refs)
			}
		}
	}
}

// preview_texture_import: the previewed project texture's import settings
// (project.json "texture_import"), applied to every loaded copy at once.
@(private = "file")
preview_texture_import :: proc(state: ^EditorState) {
	root := strings.concatenate({state.projectPath, "/"}, context.temp_allocator)
	if state.projectPath == "" || !strings.has_prefix(state.previewTexturePath, root) do return
	rel := state.previewTexturePath[len(root):]
	imp := e.Texture_ImportFor(nil, rel)
	changed := false
	UI_DimText("Import")
	imgui.SameLine()
	imgui.SetNextItemWidth(96)
	if f, ok := UI_Combo("preview.import.filter", int(imp.filter), {"Point", "Bilinear", "Trilinear"}); ok {
		imp.filter = e.Texture_Filter(f)
		changed = true
	}
	UI_Tooltip("Filtering: Point keeps pixel art crisp; Bilinear / Trilinear smooth scaled images (Trilinear uses mipmaps)")
	imgui.SameLine()
	imgui.SetNextItemWidth(84)
	if w, ok := UI_Combo("preview.import.wrap", int(imp.wrap), {"Repeat", "Clamp"}); ok {
		imp.wrap = e.Texture_Wrap(w)
		changed = true
	}
	UI_Tooltip("Wrap: Repeat tiles the texture past its edges (parallax, shaders); Clamp stretches the edge pixels")
	imgui.SameLine()
	if imgui.Checkbox("Mipmaps##imp", &imp.mipmaps) do changed = true
	Drive_Item("preview.import.mipmaps")
	UI_Tooltip("Smaller copies for drawing the texture far smaller than its size")
	if changed {
		imp.path = rel
		e.ProjectConfig_SetTextureImport(&state.projectConfig, imp)
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
		e.Texture_ImportsSet(state.projectConfig.textureImport[:])
		e.ResourceManager_ReapplyImports(&state.game.resourceManager)
		e.Texture_ApplyImport(&state.previewTexture, imp)
		Editor_Log(state, .Info, "Import settings of %s: %v filter, %v wrap%s", rel, imp.filter, imp.wrap, ", mipmaps" if imp.mipmaps else "")
	}
}
