package ui

import rl "vendor:raylib"

// ============================================================================
// Automatic UI Mouse Cursor Manager
// ============================================================================

CursorPriority :: enum {
	Default  = 0,
	Hover    = 1,
	Interact = 2,
	Dragging = 3,
}

currentFrameCursor: rl.MouseCursor = .DEFAULT
currentCursorPriority: CursorPriority = .Default
lastAppliedCursor: rl.MouseCursor = .DEFAULT

SetUICursor :: proc(cursor: rl.MouseCursor, priority: CursorPriority = .Hover) {
	if priority >= currentCursorPriority {
		currentFrameCursor = cursor
		currentCursorPriority = priority
	}
}

Cursor_BeginFrame :: proc() {
	currentFrameCursor = .DEFAULT
	currentCursorPriority = .Default
}

Cursor_Update :: proc() {
	if !rl.IsWindowReady() do return
	if currentFrameCursor != lastAppliedCursor {
		rl.SetMouseCursor(currentFrameCursor)
		lastAppliedCursor = currentFrameCursor
	}
}
