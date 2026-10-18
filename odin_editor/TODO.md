# odin_editor — Status / Backlog

Tracks progress against `REQUIREMENTS.md`'s numbered requirements.

## Done

1. **Taskfile** — `Taskfile.yml` with `check`, `test` (+ per-package
   variants), `build`, `run`, `fmt`, `ols:fetch`, `ols:build`, `clean`.
2. **Unit tests for every feature** — 115 tests across 6 packages, all
   passing with zero tracked memory leaks:
   - `buffer`: 24 tests (editing, undo/redo incl. cursor restoration,
     cursors, selection, multi-cursor, file IO, change-version tracking).
   - `keymap`: 7 tests (bind/resolve/unbind, default bindings per platform,
     F8 navigation).
   - `syntax`: 8 tests (Odin tokenizer: keywords, strings, numbers, comments,
     operators, multi-line block comments).
   - `lsp`: 20 tests (JSON-RPC framing, request encoding, dispatch,
     textEdit/activeParameter parsing, stale-response dropping, dead-server
     detection, URI percent-encoding, symlink-resolved diagnostic keys,
     UTF-16 column conversion).
   - `editor`: 50 tests (input, actions, injection, viewport, clipboard,
     file IO, completion/signature UI, LSP sync, popup layout, crash
     supervisor, visual columns, mouse gestures, diagnostics conversion /
     gutter severity / F8 / hover dwell / tooltip layout + wrapping).
   - `control`: 6 tests (chord/command/mouse-target parsing, escapes,
     errors, state JSON).
3. **OLS integration** — `lsp` package implements the JSON-RPC/LSP subset
   needed (initialize, didOpen/didChange/didClose/didSave, completion,
   signatureHelp, publishDiagnostics, hover types). Verified against a real
   `ols` binary built from a pinned, compatible commit (see README "Odin
   Language Server"): initialize handshake and a live completion request
   both round-trip correctly.
4. **Normal editor functions** — multi-line buffer, cursor movement
   (char/word/line/page/doc), selections (extend variants of all movement),
   select-all/line/word, multi-cursor (add above/below), clipboard
   (cut/copy/paste via SDL3), undo/redo (with grouped/atomic multi-edit
   actions), tab/shift-tab indent/outdent, auto-indent on newline, scrolling
   with viewport clamping, mouse click-to-position, mouse wheel scroll.
5. **Syntax highlighting & LSP features** — pluggable tokenizer
   (`syntax.Language`/`LineTokenizer`) with an Odin highlighter shipped by
   default; `editor_render` colors tokens by kind. **Completion popup** and
   **signature-help tooltip** are rendered (`editor/render_popups.odin`) and
   driven by `editor/lsp_ui.odin`: auto-trigger on `.`/identifier typing and
   `(`/`,`, manual Ctrl/Cmd+Space and Ctrl/Cmd+Shift+Space, local prefix +
   fuzzy filtering, Up/Down/PageUp/PageDown/Enter/Tab/Escape, accept via
   `textEdit`/`insertText` as one undo step, active-parameter highlight,
   close when the cursor leaves the word / call parens. LSP lifecycle fixed
   along the way: `initialized` notification, `didOpen` deferred until
   initialize completes, automatic full-text `didChange` before every
   request, absolute `file://` URIs, stale responses dropped. Verified
   against real OLS three ways: unit tests with synthetic responses
   (`editor/lsp_ui_test.odin`), the in-process e2e suite (`task test:e2e`,
   61 checks), and the visual UI tests (`task test:visual`).
   Diagnostics are rendered too (see 13).
6. **VSCode/Zed hotkeys** — `keymap.keymap_default(platform)` covers
   navigation, selection/extend, editing, clipboard, undo/redo (+Ctrl+Y on
   non-mac), save/open, multi-cursor add, completion/signature-help
   triggers, escape — parameterized for macOS (Cmd/Alt) vs Windows/Linux
   (Ctrl).
7. **Local git / feature branches** — all work committed locally on
   `feature/odin-editor-scaffold`, one commit per package/milestone. No
   remote push performed.
8. **File save/load API + event injection** — `editor_load_file`,
   `editor_save_file`, `editor_save_file_as`, `editor_save`,
   `editor_set_text`/`editor_to_string` (in-memory round trips), all
   LSP-synced (didOpen/didChange/didSave) when a language server is
   attached. `editor_inject_event`/`editor_inject_key`/`editor_inject_text`/
   `editor_pump_injected_events` let a host or test script drive the editor
   without real SDL input; demonstrated in `example/main.odin` via
   `--script`/`--script-only`.
10. **Remote control hook** — `control/` package + `tools/edctl` CLI: a
    loopback TCP line protocol that pushes real SDL events into a running
    host (`sdl.PushEvent`, so they flow through the host's own PollEvent
    loop), reports JSON state, waits on conditions (popup visible, LSP
    ready/idle, N frames), asserts (`expect`), and saves PNG screenshots.
    `--control-only` drops real input and keeps the window unfocusable for
    undisturbed scripted runs. `tools/lsp_smoke.edctl` (55 commands) is the
    scripted OLS completion/signature-help regression.
11. **OLS crash isolation** — SIGPIPE ignored, dead server detected (EOF /
    broken pipe / failed write / exit), popups closed, server restarted with
    backoff and the document re-opened; gives up after 3 crashes/minute and
    keeps editing. Verified by unit tests and `tools/lsp_crash.edctl`.
12. **Mouse & cursor integration** — click/drag select with auto-scroll,
    double/triple-click word/line (+ word/line drag), Shift+click extend,
    Alt+click add/remove cursor, gutter line selection, vertical/horizontal
    wheel, completion-list click and wheel, I-beam/arrow pointer, clicks
    outside the editor left to the host. Tabs now expand to tab stops in
    rendering, hit-testing, scrolling and popup placement (`scroll_col` is a
    visual column). Undo/redo put cursors back at the edit sites. Verified
    by unit tests and `tools/mouse_smoke.edctl` (67 commands).
13. **Diagnostics UI** — gutter severity markers, wavy underlines by
    severity (dotted hints), hover tooltip after a 350 ms dwell (text or
    gutter), F8/Shift+F8 next/previous problem, Escape to dismiss,
    per-severity counts (demo window title). UTF-16 columns converted both
    ways (requests, completion textEdits, diagnostics); URIs percent-encoded
    and matched by resolved path; didSave carries the text (OLS re-indexes
    from it). Found and patched an OLS use-after-free that kept fixed errors
    on screen (`patches/ols/`). Verified by unit tests and
    `tools/diagnostics_smoke.edctl` (46 commands, live OLS).
14. **Visual UI test suite** — `task test:visual` runs every `tools/*.edctl`
    script against the live demo (+ OLS), fails on any unmet expectation,
    and saves 26 feature screenshots, per-suite contact sheets
    (`tools/contact_sheet`) and an `index.md` gallery under
    `test_output/visual/`. Run (and look at) after every feature.
9. **Standalone demo app** — `example/main.odin` creates a real SDL3 window
   + SDL_ttf-rendered editor, loads a sample `.odin` file, supports
   Ctrl/Cmd+S save, window resize, and launches via `task run`. Verified the
   window opens and stays responsive.

## Backlog / known limitations

- **Diagnostics leftovers** — no problems panel/list, no quick fixes
  (codeAction), `tags` (unnecessary/deprecated → faded/strikethrough) are
  ignored, and ranges aren't shifted locally while typing (they're
  replaced on the server's next publish, which for parse errors is
  immediate but for `odin check` errors is the next save).
- **OLS reports `odin check` columns in code points, not UTF-16** — for a
  line with an astral character (e.g. an emoji) before the error, the
  squiggle lands one cell early per such character. Upstream issue; BMP
  text (é, ü, CJK) is exact.
- **Completion polish** — no documentation side panel, snippets aren't requested (no
  `snippetSupport`), and `isIncomplete` lists aren't re-queried as you type
  (filtering is purely local after the first response). Signature help shows
  only the active overload (no overload cycling).
- **Undo coalescing** — every TEXT_INPUT event is its own undo step, so
  undoing typed text goes back one character at a time (VSCode merges runs
  of typing). Needs time/word-boundary based grouping in `buffer`.
- **Up/Down keep the byte column, not the visual column** — moving between
  tab- and space-indented lines drifts horizontally. Needs a sticky
  "preferred visual column" on the cursor.
- **Mouse leftovers** — no right-click context menu, no drag-and-drop of
  selected text, no hover tooltips (LSP hover), and horizontal auto-scroll
  only applies to character drags.
- **Horizontal scroll clamp is O(lines)** — `editor_clamp_scroll` scans
  every line for the widest one on each scroll/cursor move; fine for normal
  files, should be cached for very large ones.
- **OLS + directory names** — OLS derives package paths from directory
  names; files in a directory whose name contains a `.` get no completions.
  Worth surfacing to users (or opening such files with a symlinked root).
- **Incremental document sync** — `didChange` currently sends the full
  document text on every change rather than incremental edits. Simpler and
  correct, but less efficient for very large files/high edit frequency.
- **Find/replace** — noted as a stretch goal in requirement #4, not
  implemented.
- **Ctrl/Cmd+D "select next occurrence"** — noted as a stretch goal in
  requirement #6, not implemented (Ctrl/Cmd+Alt+Up/Down add-cursor-
  above/below *is* implemented).
- **No font fallback** — glyphs missing from the monospace font (emoji,
  many symbols) render as blank cells. Needs a fallback font chain
  (SDL_ttf `TTF_AddFallbackFont`) plus wide-glyph (2-cell) column math.
- **OLS version pinning is brittle** — OLS tracks Odin's development branch
  very closely; `Taskfile.yml`'s `OLS_REF` pins a commit verified to build
  against this project's installed Odin version, but upgrading the Odin
  compiler will likely require re-pinning OLS to a newer commit (bisect
  forward from `OLS_REF` until it builds again).
