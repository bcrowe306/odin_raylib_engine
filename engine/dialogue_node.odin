package engine

import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// DialogueNode: a dialogue box on a UI layer. Scripts queue lines (a
// speaker and rich text, or localization keys); each line types out at
// revealSpeed characters per second; the advance action (default
// "confirm") shows the rest of a line, then the next one; after the last
// the box closes. Events: "line_shown"(index, 1-based) when a line is fully
// shown, "finished" when the box closes.
//
// A line may name a voice sound (played when the line starts). Mode
// Subtitles shows the lines on the subtitle track instead of a box
// (subtitles.odin: cutscene voice-over, barks): each line stays for its
// voice's length (else its reading time), then the next one follows by
// itself; the advance action skips. With the player's subtitles turned off
// the lines still play and time out (events too), unseen.
// ============================================================================

Dialogue_Line :: struct {
	speaker: string,
	text:    string,
	voice:   string, // a sound played with the line ("" = none)
}

Dialogue_Mode :: enum u8 {Box, Subtitles}

DialogueNode :: struct {
	using ui:      UIElement,
	font:          string `gui:"true"`,
	fontSize:      f32 `gui:"true" min:"8" max:"96"`,
	textColor:     rl.Color `gui:"true"`,
	speakerColor:  rl.Color `gui:"true"`,
	panelColor:    rl.Color `gui:"true"`,
	borderColor:   rl.Color `gui:"true"`,
	padding:       f32 `gui:"true" min:"0" max:"100"`,
	revealSpeed:   f32 `gui:"true" min:"0" max:"500"`, // characters per second (0 = whole lines)
	advanceAction: string `gui:"true"`,                 // input action that advances ("confirm")
	localized:     bool `gui:"true"`,                   // lines are locale keys
	mode:          Dialogue_Mode `gui:"true"`,          // a box, or the subtitle track
	lipSync:       string `gui:"true"`,                 // a LipSyncNode (path) moving a mouth with the voices

	lines:         [dynamic]Dialogue_Line,
	current:       int,  // index into lines; -1 = closed
	revealed:      f32,
	lineDone:      bool,
	time:          f32,
	started:       bool, // the current line's voice / subtitle began
	lineTime:      f32,  // Subtitles mode: seconds left on this line
	subId:         u64,
	voice:         Mixer_Voice_Handle,
	voiceSound:    ^AudioSound,
	onLineShown:   EventSubject,
	onFinished:    EventSubject,
}

DialogueNode_Create :: proc(scene: ^Scene, name: string = "Dialogue", parent: ^Node = nil) -> ^DialogueNode {
	d := CreateNode(scene.manager, DialogueNode)
	DialogueNode_Init(d)
	d.name = strings.clone(name, d.allocator) // owned: callers pass temp strings too
	scene->addNode(d, parent)
	return d
}

DialogueNode_Init :: proc(d: ^DialogueNode) {
	UIElement_Init(&d.ui, .Label, {900, 170})
	d.position = {190, 520}
	d.fontSize = 24
	d.textColor = {238, 240, 246, 255}
	d.speakerColor = {250, 204, 21, 255}
	d.panelColor = {15, 18, 28, 230}
	d.borderColor = {92, 141, 255, 255}
	d.padding = 20
	d.revealSpeed = 40
	d.advanceAction = "confirm"
	d.lines = make([dynamic]Dialogue_Line, d.allocator)
	d.current = -1
	d.update = DialogueNode_Update
	d.render = DialogueNode_Render
	d.onDestroy = DialogueNode_Destroy
	InitializeSubject(&d.onLineShown, "line_shown", d)
	InitializeSubject(&d.onFinished, "finished", d)
}

DialogueNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	d := cast(^DialogueNode)node
	line_end(d)
	DestroySubject(&d.onLineShown)
	DestroySubject(&d.onFinished)
}

// DialogueNode_Show opens the box with these lines (replacing any).
DialogueNode_Show :: proc(d: ^DialogueNode, lines: []Dialogue_Line) {
	line_end(d)
	clear(&d.lines)
	for l in lines do append(&d.lines, Dialogue_Line{strings.clone(l.speaker, d.allocator), strings.clone(l.text, d.allocator), strings.clone(l.voice, d.allocator)})
	d.current = 0 if len(d.lines) > 0 else -1
	d.revealed = 0
	d.lineDone = false
	d.started = false
}

// line_start: the current line's voice and (Subtitles mode) subtitle.
@(private = "file")
line_start :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	d.started = true
	gc := ctx if ctx != nil else d.gameContext
	l := d.lines[d.current]
	length: f32
	if l.voice != "" && gc != nil && gc.game != nil {
		rm := &gc.game.resourceManager
		if s, ok := rm.loadAudioSound(rm, Project_ResolveAssetPath(gc, l.voice)); ok {
			d.voiceSound = s
			length = f32(len(s.pcm) / 2) / MIXER_RATE
			if Audio_Ready() do d.voice = Mixer_PlaySound(s.pcm, Audio_BusFor(rm, s.filePath, "SFX"), owner = s)
		}
		if ls := dialogue_lipsync(d); ls != nil do LipSyncNode_Follow(ls, l.voice, d.voice)
	}
	if d.mode == .Subtitles {
		speaker, text := line_text(d, ctx)
		d.lineTime = length + 0.3 if length > 0 else Subtitles_ReadingTime(text)
		d.subId = Subtitles_Show(text, speaker, d.lineTime, .Dialogue)
		d.lineDone = true
		d.onLineShown->notify(d, d.current + 1, ctx)
	}
}

// line_end: stops the line's voice and takes its subtitle down.
@(private = "file")
line_end :: proc(d: ^DialogueNode) {
	if ls := dialogue_lipsync(d); ls != nil && ls.playing do LipSyncNode_Stop(ls)
	Mixer_StopVoice(d.voice)
	d.voice = {}
	if d.voiceSound != nil {
		if gc := d.gameContext; gc != nil && gc.game != nil do ResourceManager_ReleaseSound(&gc.game.resourceManager, d.voiceSound)
		d.voiceSound = nil
	}
	Subtitles_Hide(d.subId)
	d.subId = 0
	d.started = false
}

DialogueNode_IsOpen :: proc(d: ^DialogueNode) -> bool {
	return d.current >= 0 && d.current < len(d.lines)
}

@(private = "file")
line_text :: proc(d: ^DialogueNode, ctx: ^GameContext) -> (speaker, text: string) {
	l := d.lines[d.current]
	gc := ctx if ctx != nil else d.gameContext
	if d.localized && gc != nil {
		return Locale_Get(gc.game, l.speaker) if l.speaker != "" else "", Locale_Get(gc.game, l.text)
	}
	return l.speaker, l.text
}

// DialogueNode_Advance: the rest of the line, else the next line (closing
// after the last).
DialogueNode_Advance :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	if !DialogueNode_IsOpen(d) do return
	if !d.lineDone {
		d.revealed = 1e9
		d.lineDone = true
		d.onLineShown->notify(d, d.current + 1, ctx)
		return
	}
	line_end(d)
	d.current += 1
	d.revealed = 0
	d.lineDone = false
	if d.current >= len(d.lines) {
		d.current = -1
		d.onFinished->notify(d, nil, ctx)
	}
}

DialogueNode_Close :: proc(d: ^DialogueNode, ctx: ^GameContext) {
	if !DialogueNode_IsOpen(d) do return
	line_end(d)
	d.current = -1
	d.onFinished->notify(d, nil, ctx)
}

DialogueNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	d := cast(^DialogueNode)node
	d.time += dt
	if !DialogueNode_IsOpen(d) do return
	if !d.started do line_start(d, ctx)
	if d.mode == .Subtitles {
		d.lineTime -= dt
		if d.lineTime <= 0 {
			DialogueNode_Advance(d, ctx) // the next line by itself
			return
		}
	} else if !d.lineDone {
		_, text := line_text(d, ctx)
		total := Text_PlainLength(text, true)
		d.revealed += d.revealSpeed * dt if d.revealSpeed > 0 else f32(total)
		if int(d.revealed) >= total {
			d.lineDone = true
			d.onLineShown->notify(d, d.current + 1, ctx)
		}
	}
	gc := ctx if ctx != nil else d.gameContext
	if gc != nil && gc.input != nil && d.advanceAction != "" {
		if st, ok := Input_ActionStateByName(gc.input, d.advanceAction); ok && st.pressed {
			DialogueNode_Advance(d, ctx)
		}
	}
}

DialogueNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	d := cast(^DialogueNode)node
	if !rl.IsWindowReady() || !DialogueNode_IsOpen(d) || d.mode == .Subtitles do return // (Subtitles: on the track)
	rect := UI_GetElementRect(&d.ui)
	rl.DrawRectangleRounded(rect, 0.08, 8, d.panelColor)
	rl.DrawRectangleRoundedLinesEx(rect, 0.08, 8, 2, d.borderColor)
	speaker, text := line_text(d, ctx)
	f := Text_GetFont(d.font, d.fontSize, false, ctx)
	measure :: proc(r: rune, size: f32, data: rawptr) -> f32 {return Text_MeasureRune(cast(^Text_Font)data, r, size)}
	y := rect.y + d.padding
	if speaker != "" {
		sg, ss := Text_Layout(speaker, {d.speakerColor, d.fontSize * 0.9, {}}, 0, 0, 1, false, measure, f)
		Text_DrawGlyphs(f, sg, {rect.x + d.padding, y}, 0, 1, -1, d.time)
		y += ss.y + d.fontSize * 0.35
	}
	glyphs, _ := Text_Layout(text, {d.textColor, d.fontSize, {}}, rect.width - 2 * d.padding, 0, 1.25, true, measure, f)
	reveal := -1 if d.lineDone else int(d.revealed)
	Text_DrawGlyphs(f, glyphs, {rect.x + d.padding, y}, 0, 1, reveal, d.time)
	if d.lineDone {
		// "More" marker, bobbing.
		bob := f32(int(d.time * 3) % 2) * 3
		p := [2]f32{rect.x + rect.width - d.padding, rect.y + rect.height - d.padding + bob}
		rl.DrawTriangle(p + {-12, -10}, p + {-6, 0}, p + {0, -10}, d.borderColor)
	}
}

// dialogue_lipsync: the Lip Sync node `lipSync` names (nil: none).
@(private = "file")
dialogue_lipsync :: proc(d: ^DialogueNode) -> ^LipSyncNode {
	if d.lipSync == "" || d.gameContext == nil || d.gameContext.scene == nil do return nil
	n := Node_ResolvePath(d.gameContext.scene.manager, d, d.lipSync)
	if n == nil || n.typeId != LipSyncNode do return nil
	return cast(^LipSyncNode)n
}
