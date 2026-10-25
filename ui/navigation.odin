package ui

import rl "vendor:raylib"

// ============================================================================
// Standalone UI Navigation Primitives & Key Actions (Independent of Engine)
// ============================================================================

NavAction :: enum {
	None,
	Next,       // Tab (cycles focus forward)
	Prev,       // Shift+Tab (cycles focus backward)
	Up,         // Directional Up
	Down,       // Directional Down
	Left,       // Directional Left
	Right,      // Directional Right
	Activate,   // Enter / Space (trigger button, toggle switch/checkbox, confirm)
	Cancel,     // Escape (close dropdown/popup, cancel editing)
}

NavDirection :: enum {
	Up,
	Down,
	Left,
	Right,
}

// Simulated or physical input data for navigation
NavKeyInput :: struct {
	tab:    bool,
	shift:  bool,
	up:     bool,
	down:   bool,
	left:   bool,
	right:  bool,
	enter:  bool,
	space:  bool,
	escape: bool,
}

// Convert input flags into a single navigation action
GetNavActionFromInput :: proc(input: NavKeyInput) -> NavAction {
	if input.escape do return .Cancel
	if input.tab {
		if input.shift do return .Prev
		return .Next
	}
	if input.up do return .Up
	if input.down do return .Down
	if input.left do return .Left
	if input.right do return .Right
	if input.enter || input.space do return .Activate
	return .None
}

// Read current keyboard state from raylib if window is available
GetNavActionFromRaylib :: proc() -> NavAction {
	if testHook.overrideNavAction != .None {
		action := testHook.overrideNavAction
		testHook.overrideNavAction = .None
		return action
	}
	if !rl.IsWindowReady() do return .None

	shift := IsUIKeyDown(.LEFT_SHIFT) || IsUIKeyDown(.RIGHT_SHIFT)

	if IsUIKeyPressed(.ESCAPE) do return .Cancel

	if IsUIKeyPressed(.TAB) {
		if shift do return .Prev
		return .Next
	}

	if IsUIKeyPressed(.UP) do return .Up
	if IsUIKeyPressed(.DOWN) do return .Down
	if IsUIKeyPressed(.LEFT) do return .Left
	if IsUIKeyPressed(.RIGHT) do return .Right

	if IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE) {
		return .Activate
	}

	return .None
}

// Cycle focus forward or backward through count elements:
// forward: (current + 1) % count
// backward: (current - 1 + count) % count
NavCycle :: proc(count: int, currentIdx: int, forward: bool) -> int {
	if count <= 0 do return -1
	if currentIdx < 0 || currentIdx >= count {
		return 0 if forward else count - 1
	}
	if forward {
		return (currentIdx + 1) % count
	} else {
		return (currentIdx - 1 + count) % count
	}
}

// Spatial 2D Navigation:
// Given a slice of candidate bounding boxes and the current index,
// find the best candidate in the given direction.
// Returns candidate index, or currentIdx if no candidate is in that direction.
NavFindNextSpatial :: proc(candidates: []rl.Rectangle, currentIdx: int, dir: NavDirection) -> int {
	count := len(candidates)
	if count == 0 do return -1
	if count == 1 do return 0
	if currentIdx < 0 || currentIdx >= count {
		return 0
	}

	cur := candidates[currentIdx]
	curCenter := rl.Vector2{cur.x + cur.width * 0.5, cur.y + cur.height * 0.5}

	bestIdx := currentIdx
	bestScore: f32 = 1e9

	for i in 0..<count {
		if i == currentIdx do continue
		cand := candidates[i]
		if cand.width <= 0 || cand.height <= 0 do continue

		candCenter := rl.Vector2{cand.x + cand.width * 0.5, cand.y + cand.height * 0.5}
		dx := candCenter.x - curCenter.x
		dy := candCenter.y - curCenter.y

		isInDirection := false
		primaryDist: f32 = 0
		orthoDist: f32 = 0

		switch dir {
		case .Up:
			if dy < -1.0 {
				isInDirection = true
				primaryDist = -dy
				orthoDist = abs(dx)
			}
		case .Down:
			if dy > 1.0 {
				isInDirection = true
				primaryDist = dy
				orthoDist = abs(dx)
			}
		case .Left:
			if dx < -1.0 {
				isInDirection = true
				primaryDist = -dx
				orthoDist = abs(dy)
			}
		case .Right:
			if dx > 1.0 {
				isInDirection = true
				primaryDist = dx
				orthoDist = abs(dy)
			}
		}

		if !isInDirection do continue

		// Overlap bonus: if rects overlap on orthogonal axis, prefer them strongly
		overlapBonus: f32 = 0
		if dir == .Up || dir == .Down {
			leftMax := max(cur.x, cand.x)
			rightMin := min(cur.x + cur.width, cand.x + cand.width)
			if rightMin > leftMax {
				overlapBonus = (rightMin - leftMax) * 0.5
			}
		} else {
			topMax := max(cur.y, cand.y)
			bottomMin := min(cur.y + cur.height, cand.y + cand.height)
			if bottomMin > topMax {
				overlapBonus = (bottomMin - topMax) * 0.5
			}
		}

		// Weighted score: primary distance plus orthogonal deviation penalty minus overlap
		score := primaryDist * 1.0 + orthoDist * 2.5 - overlapBonus
		if score < bestScore {
			bestScore = score
			bestIdx = i
		}
	}

	return bestIdx
}

// Render crisp focus ring indicator around a UI element's bounding rectangle
RenderFocusRing :: proc(
	rect: rl.Rectangle,
	focused: bool,
	padding: f32 = 2.0,
	color: rl.Color = {110, 168, 254, 255},
	thickness: f32 = 2.0,
) {
	if !focused || !rl.IsWindowReady() do return

	ringRect := rl.Rectangle{
		rect.x - padding,
		rect.y - padding,
		rect.width + padding * 2.0,
		rect.height + padding * 2.0,
	}
	t := GetTheme()
	if t.borderRadius > 0.5 {
		minDim := min(ringRect.width, ringRect.height)
		roundness := clamp(((t.borderRadius + padding) * 2.0) / minDim, 0.0, 1.0)
		rl.DrawRectangleRoundedLinesEx(ringRect, roundness, 20, thickness, color)
	} else {
		rl.DrawRectangleLinesEx(ringRect, thickness, color)
	}
}

// ============================================================================
// Immediate-Mode Focus Tracking State
// ============================================================================
MAX_IMMEDIATE_NAV_ITEMS :: 64

ImmediateNavState :: struct {
	focusedKey:    uintptr,
	registeredKeys: [MAX_IMMEDIATE_NAV_ITEMS]uintptr,
	registeredRects: [MAX_IMMEDIATE_NAV_ITEMS]rl.Rectangle,
	itemCount:     int,
}

immediateNav: ImmediateNavState

ImmediateNav_BeginFrame :: proc() {
	immediateNav.itemCount = 0
	Cursor_BeginFrame()
}

ImmediateNav_RegisterFocusable :: proc(key: uintptr, rect: rl.Rectangle) {
	if immediateNav.itemCount < MAX_IMMEDIATE_NAV_ITEMS {
		immediateNav.registeredKeys[immediateNav.itemCount] = key
		immediateNav.registeredRects[immediateNav.itemCount] = rect
		immediateNav.itemCount += 1
	}
}

ImmediateNav_IsFocused :: proc(key: uintptr) -> bool {
	return immediateNav.focusedKey != 0 && immediateNav.focusedKey == key
}

ImmediateNav_SetFocus :: proc(key: uintptr) {
	immediateNav.focusedKey = key
}

ImmediateNav_ClearFocus :: proc() {
	immediateNav.focusedKey = 0
}

ImmediateNav_ProcessKeyInput :: proc(input: NavKeyInput) {
	action := GetNavActionFromInput(input)
	ImmediateNav_HandleAction(action)
}

ImmediateNav_Update :: proc() {
	if !rl.IsWindowReady() do return
	Cursor_Update()
	action := GetNavActionFromRaylib()
	ImmediateNav_HandleAction(action)
}

ImmediateNav_HandleAction :: proc(action: NavAction) {
	if action == .Cancel && immediateDropdown.active {
		immediateDropdown.active = false
		return
	}
	if immediateDropdown.active do return

	count := immediateNav.itemCount
	if count == 0 do return

	curIdx := -1
	for i in 0..<count {
		if immediateNav.registeredKeys[i] == immediateNav.focusedKey {
			curIdx = i
			break
		}
	}

	switch action {
	case .Next:
		nextIdx := NavCycle(count, curIdx, true)
		if nextIdx >= 0 && nextIdx < count {
			immediateNav.focusedKey = immediateNav.registeredKeys[nextIdx]
		}
	case .Prev:
		prevIdx := NavCycle(count, curIdx, false)
		if prevIdx >= 0 && prevIdx < count {
			immediateNav.focusedKey = immediateNav.registeredKeys[prevIdx]
		}
	case .Up:
		if curIdx >= 0 {
			nextIdx := NavFindNextSpatial(immediateNav.registeredRects[:count], curIdx, .Up)
			immediateNav.focusedKey = immediateNav.registeredKeys[nextIdx]
		} else {
			immediateNav.focusedKey = immediateNav.registeredKeys[0]
		}
	case .Down:
		if curIdx >= 0 {
			nextIdx := NavFindNextSpatial(immediateNav.registeredRects[:count], curIdx, .Down)
			immediateNav.focusedKey = immediateNav.registeredKeys[nextIdx]
		} else {
			immediateNav.focusedKey = immediateNav.registeredKeys[0]
		}
	case .Left:
		if curIdx >= 0 {
			nextIdx := NavFindNextSpatial(immediateNav.registeredRects[:count], curIdx, .Left)
			immediateNav.focusedKey = immediateNav.registeredKeys[nextIdx]
		} else {
			immediateNav.focusedKey = immediateNav.registeredKeys[0]
		}
	case .Right:
		if curIdx >= 0 {
			nextIdx := NavFindNextSpatial(immediateNav.registeredRects[:count], curIdx, .Right)
			immediateNav.focusedKey = immediateNav.registeredKeys[nextIdx]
		} else {
			immediateNav.focusedKey = immediateNav.registeredKeys[0]
		}
	case .Cancel:
		immediateNav.focusedKey = 0
	case .Activate, .None:
		// Handled by individual widgets
	}
}
