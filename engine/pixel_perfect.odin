package engine

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// Pixel-perfect rendering (project Video settings; docs/pixel_perfect.md).
//
// - Integer scaling: the frame is scaled to the window by a whole number
//   (bars around it) - every game pixel is the same size on screen.
// - Pixel snap: the camera and the sprites sit on whole game pixels (no
//   shimmering, no uneven pixels on scaled or moving sprites).
// - Smooth camera (with pixel snap): the world is drawn snapped into a
//   texture one pixel larger on every side; the final upscale moves it by
//   the camera's leftover fraction of a pixel, at screen resolution - slow
//   pans glide instead of stepping a whole game pixel at a time. UI layers
//   (those the camera doesn't draw) go to the frame on top, unshifted.
// ============================================================================

Render_Pixel_Settings :: struct {
	integerScaling: bool,
	snap:           bool,
	smooth:         bool, // needs snap
}

renderPixel: struct {
	using settings: Render_Pixel_Settings,
	frac:     [2]f32, // the camera's leftover (game px) after snapping, this frame
	margin:   f32,    // 1 while the world draws into worldTarget (the camera's offset)
	world:    rl.RenderTexture2D, // the smooth camera's world (virtual size + 2)
	usedWorld: bool,              // the world went to `world` this frame (the runner composites it)
}

PIXEL_MARGIN :: 1

// Render_SetPixelSettings applies the project's settings (Game_LoadProjectConfig).
Render_SetPixelSettings :: proc(s: Render_Pixel_Settings) {
	renderPixel.settings = s
	renderPixel.smooth = s.smooth && s.snap
}

// Pixel_SnapCamera puts a camera's target on a whole game pixel (at its
// zoom) and records what was left over for the smooth camera.
Pixel_SnapCamera :: proc(cam: ^rl.Camera2D) {
	cam.offset += renderPixel.margin
	if !renderPixel.snap do return
	z := cam.zoom if cam.zoom > 0.0001 else 1
	px := cam.target * z
	snapped := [2]f32{math.round(px.x), math.round(px.y)}
	renderPixel.frac = px - snapped
	cam.target = snapped / z
	cam.offset = {math.round(cam.offset.x), math.round(cam.offset.y)}
}

// Pixel_SnapSprite moves a sprite's draw position so its top-left corner is
// on a whole pixel (unrotated sprites; `o` = the origin in drawn pixels).
Pixel_SnapSprite :: #force_inline proc(pos, o: [2]f32, rotation: f32) -> [2]f32 {
	if !renderPixel.snap || rotation != 0 do return pos
	tl := pos - o
	return pos + [2]f32{math.round(tl.x), math.round(tl.y)} - tl
}

// Screen_Fill: what fills a window (or screen) whose shape differs from the
// game's virtual resolution (#174).
Screen_Fill :: enum u8 {
	Keep,   // the virtual resolution as it is, scaled to fit: bars where the shapes differ
	Expand, // the same scale, the frame grown to the window's shape: more world on the longer side, no bars
}

Screen_Fill_Name :: proc(f: Screen_Fill) -> string {return "expand" if f == .Expand else "keep"}
Screen_Fill_Parse :: proc(s: string) -> Screen_Fill {return .Expand if s == "expand" else .Keep}

// Screen_FillSize: the frame size for a design (virtual) resolution on a
// screen. Keep: the design size. Expand: scaled as Keep scales it (the
// smaller of the two ratios; a whole number with integer scaling), then
// grown on the longer side to the screen's shape - at least the design
// size, so what the design shows is always shown.
Screen_FillSize :: proc(design, screen: [2]f32, fill: Screen_Fill, integer := false) -> [2]f32 {
	if fill == .Keep || design.x <= 0 || design.y <= 0 || screen.x <= 0 || screen.y <= 0 do return design
	s := min(screen.x / design.x, screen.y / design.y)
	if integer && s >= 1 do s = math.floor(s)
	if integer {
		return {max(design.x, math.floor(screen.x / s)), max(design.y, math.floor(screen.y / s))}
	}
	return {max(design.x, math.ceil(screen.x / s - 0.01)), max(design.y, math.ceil(screen.y / s - 0.01))}
}

// Pixel_FitRect: the frame (w x h) scaled into the screen, centred - by a
// whole number with integer scaling (at least 1).
Pixel_FitRect :: proc(w, h, screenW, screenH: f32) -> rl.Rectangle {
	if w <= 0 || h <= 0 || screenW <= 0 || screenH <= 0 do return {0, 0, max(w, 1), max(h, 1)}
	s := min(screenW / w, screenH / h)
	if renderPixel.integerScaling && s >= 1 do s = math.floor(s)
	dw, dh := w * s, h * s
	return {f32(int((screenW - dw) * 0.5)), f32(int((screenH - dh) * 0.5)), dw, dh}
}

// Pixel_WorldTarget: the smooth camera's world texture for a w x h frame.
Pixel_WorldTarget :: proc(w, h: i32) -> ^rl.RenderTexture2D {
	ww, wh := w + 2 * PIXEL_MARGIN, h + 2 * PIXEL_MARGIN
	t := &renderPixel.world
	if t.id == 0 || t.texture.width != ww || t.texture.height != wh {
		if t.id != 0 do rl.UnloadRenderTexture(t^)
		t^ = rl.LoadRenderTexture(ww, wh)
		rl.SetTextureFilter(t.texture, .POINT)
	}
	return t
}

// Pixel_Release frees the world texture (window closing).
Pixel_Release :: proc() {
	if renderPixel.world.id != 0 do rl.UnloadRenderTexture(renderPixel.world)
	renderPixel.world = {}
}

// Pixel_DrawWorld (runner): the smooth camera's world into dest (the frame's
// place on screen), moved by the leftover fraction, clipped to dest.
Pixel_DrawWorld :: proc(tex: rl.Texture2D, dest: rl.Rectangle, vw, vh: f32) {
	sx, sy := dest.width / vw, dest.height / vh
	m := f32(PIXEL_MARGIN)
	d := rl.Rectangle{dest.x - (m + renderPixel.frac.x) * sx, dest.y - (m + renderPixel.frac.y) * sy, f32(tex.width) * sx, f32(tex.height) * sy}
	rl.BeginScissorMode(i32(dest.x), i32(dest.y), i32(dest.width), i32(dest.height))
	rl.DrawTexturePro(tex, {0, 0, f32(tex.width), -f32(tex.height)}, d, {0, 0}, 0, rl.WHITE)
	rl.EndScissorMode()
}
