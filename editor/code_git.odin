package editor

import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Git gutter: lines added / modified / removed since the last commit. The
// committed text (`git show HEAD:<file>`) is read on a worker thread when a
// script opens or is saved; the buffer is compared to it with a line diff
// (Myers, on line hashes) once per edit, after typing pauses. Files outside
// git or not committed show nothing.
// ============================================================================

Code_Git_State :: enum {
	Unknown,
	Loading,
	None,  // not in a git repository / not committed
	Ready,
}

Code_Git :: struct {
	state:      Code_Git_State,
	base:       [dynamic]u64, // the committed lines' hashes
	job:        ^Git_Job,
	changes:    [dynamic]Code_Change_Mark,
	version:    int,       // buffer version `changes` is for (-1 = stale)
	editedAt:   time.Tick, // last time the version moved (debounce)
	seenVersion: int,
}

@(private = "file")
Git_Job :: struct {
	dir, name: string,
	output:    string,
	ok:        bool,
	done:      bool,
	thread:    ^thread.Thread,
}

CHANGE_ADDED := imgui.Vec4{0.298, 0.808, 0.553, 0.9}
CHANGE_MODIFIED := imgui.Vec4{0.361, 0.553, 1.000, 0.9}
CHANGE_DELETED := imgui.Vec4{0.937, 0.373, 0.373, 0.9}

// code_git_load starts reading the committed version (open / save).
code_git_load :: proc(doc: ^Code_Doc) {
	g := &doc.git
	if g.job != nil do return // one at a time
	job := new(Git_Job)
	job.dir = strings.clone(filepath.dir(doc.path, context.temp_allocator))
	job.name = strings.clone(filepath.base(doc.path))
	job.thread = thread.create_and_start_with_poly_data(job, proc(job: ^Git_Job) {
		cmd := []string{"git", "-C", job.dir, "show", strings.concatenate({"HEAD:./", job.name}, context.temp_allocator)}
		st, out, errOut, err := os.process_exec({command = cmd}, context.allocator)
		delete(errOut)
		if err == nil && st.exit_code == 0 {
			job.output = string(out)
			job.ok = true
		} else {
			delete(out)
		}
		sync.atomic_store(&job.done, true)
	})
	g.job = job
	if g.state == .Unknown do g.state = .Loading
}

@(private = "file")
git_job_free :: proc(job: ^Git_Job) {
	thread.join(job.thread)
	thread.destroy(job.thread)
	delete(job.dir)
	delete(job.name)
	delete(job.output)
	free(job)
}

// code_git_poll takes a finished read (each frame for the active doc).
code_git_poll :: proc(doc: ^Code_Doc) {
	g := &doc.git
	if g.job == nil || !sync.atomic_load(&g.job.done) do return
	job := g.job
	g.job = nil
	clear(&g.base)
	if job.ok {
		for l in strings.split_lines(strings.trim_suffix(job.output, "\n"), context.temp_allocator) {
			append(&g.base, hash.fnv64a(transmute([]u8)strings.trim_right(l, "\r")))
		}
		g.state = .Ready
	} else {
		g.state = .None
	}
	g.version = -1
	git_job_free(job)
}

code_git_destroy :: proc(doc: ^Code_Doc) {
	g := &doc.git
	if g.job != nil do git_job_free(g.job) // waits for git (quick)
	delete(g.base)
	delete(g.changes)
	g^ = {}
}

// Code_ChangedLines: the doc's changes since the last commit (recomputed
// at most once per edit, 250 ms after typing stops).
Code_ChangedLines :: proc(doc: ^Code_Doc) -> []Code_Change_Mark {
	g := &doc.git
	code_git_poll(doc)
	if g.state != .Ready do return nil
	b := &doc.buffer
	if g.seenVersion != b.version {
		g.seenVersion = b.version
		g.editedAt = time.tick_now()
	}
	if g.version != b.version && (g.version < 0 || time.duration_milliseconds(time.tick_since(g.editedAt)) > 250) {
		g.version = b.version
		code_git_diff(doc)
	}
	return g.changes[:]
}

// code_git_change_at: a line's change (for the gutter), if any.
code_git_change_at :: proc(doc: ^Code_Doc, line: int) -> (imgui.Vec4, bool) {
	for c in doc.git.changes do if c.line == line do return c.color, true
	return {}, false
}

// code_git_diff: Myers' O(ND) line diff of the committed lines against the
// buffer, as gutter marks: added / modified lines, a removal on the line
// after it.
@(private = "file")
code_git_diff :: proc(doc: ^Code_Doc) {
	g := &doc.git
	clear(&g.changes)
	b := &doc.buffer
	nb := buf.buffer_line_count(b)
	cur := make([]u64, nb, context.temp_allocator)
	for i in 0 ..< nb do cur[i] = hash.fnv64a(transmute([]u8)strings.trim_right(buf.buffer_line_str(b, i), "\r"))
	a := g.base[:]
	// A trailing empty line (file ending in a newline) isn't a change.
	if nb > 0 && buf.buffer_line_len(b, nb - 1) == 0 do cur = cur[:nb - 1]
	n, m := len(a), len(cur)
	if n + m > 40000 do return // huge: skip
	// Trim the common head and tail.
	head := 0
	for head < n && head < m && a[head] == cur[head] do head += 1
	tail := 0
	for tail < n - head && tail < m - head && a[n - 1 - tail] == cur[m - 1 - tail] do tail += 1
	a = a[head:n - tail]
	c := cur[head:m - tail]
	n, m = len(a), len(c)
	if n == 0 && m == 0 do return
	// Myers: V per D, traced back for the edit script.
	maxD := n + m
	offset := maxD
	v := make([]int, 2 * maxD + 2, context.temp_allocator)
	trace := make([dynamic][]int, context.temp_allocator)
	found := false
	for d in 0 ..= maxD {
		snap := make([]int, len(v), context.temp_allocator)
		copy(snap, v)
		append(&trace, snap)
		for k := -d; k <= d; k += 2 {
			x: int
			if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
				x = v[offset + k + 1]
			} else {
				x = v[offset + k - 1] + 1
			}
			y := x - k
			for x < n && y < m && a[x] == c[y] {x += 1; y += 1}
			v[offset + k] = x
			if x >= n && y >= m {found = true; break}
		}
		if found do break
		if d > 4000 do return // very different: skip
	}
	// Walk back: deleted a-lines and inserted c-lines, in order.
	Edit :: struct {ins: bool, ai, ci: int}
	edits := make([dynamic]Edit, context.temp_allocator)
	x, y := n, m
	for d := len(trace) - 1; d > 0; d -= 1 {
		vv := trace[d]
		k := x - y
		prevK: int
		if k == -d || (k != d && vv[offset + k - 1] < vv[offset + k + 1]) do prevK = k + 1
		else do prevK = k - 1
		px := vv[offset + prevK]
		py := px - prevK
		for x > px && y > py {x -= 1; y -= 1}
		if x == px do append(&edits, Edit{true, x, y - 1})  // insertion of c[y-1]
		else do append(&edits, Edit{false, x - 1, y})        // deletion of a[x-1]
		x, y = px, py
	}
	// Group consecutive edits at the same place: modified / added / removed.
	insLines := make(map[int]bool, 16, context.temp_allocator)
	delAt := make(map[int]int, 16, context.temp_allocator) // c-index -> deletions before it
	for e in edits {
		if e.ins do insLines[e.ci] = true
		else do delAt[e.ci] += 1
	}
	for ci, count in delAt {
		// Deletions right before inserted lines turn them into modifications.
		left := count
		for k := ci; left > 0 && insLines[k]; k += 1 {
			append(&g.changes, Code_Change_Mark{head + k, CHANGE_MODIFIED})
			delete_key(&insLines, k)
			left -= 1
		}
		if left > 0 do append(&g.changes, Code_Change_Mark{head + ci, CHANGE_DELETED})
	}
	for ci in insLines do append(&g.changes, Code_Change_Mark{head + ci, CHANGE_ADDED})
}
