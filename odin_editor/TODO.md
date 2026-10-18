# odin_editor — Status / Backlog

Tracks progress against `REQUIREMENTS.md`'s 9 numbered requirements.

## Done

1. **Taskfile** — `Taskfile.yml` with `check`, `test` (+ per-package
   variants), `build`, `run`, `fmt`, `ols:fetch`, `ols:build`, `clean`.
2. **Unit tests for every feature** — 57 tests across 5 packages, all
   passing with zero tracked memory leaks:
   - `buffer`: 20 tests (editing, undo/redo, cursors, selection, multi-cursor,
     file IO).
   - `keymap`: 6 tests (bind/resolve/unbind, default bindings per platform).
   - `syntax`: 8 tests (Odin tokenizer: keywords, strings, numbers, comments,
     operators, multi-line block comments).
   - `lsp`: 10 tests (JSON-RPC framing, request encoding, dispatch of
     diagnostics/completion/signature-help, partial-message handling).
   - `editor`: 13 tests (SDL key/mod translation, action dispatch, undo/redo,
     multi-cursor add, event injection round-trip, viewport scroll math,
     clipboard text extraction, file load/save round-trip).
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
   default; `editor_render` colors tokens by kind. Completion and signature
   help are wired end-to-end (keymap triggers -> LSP request -> response
   stored on `Client` -> available for host/UI to render as a popup).
   Diagnostics are received and stored per-document
   (`client_diagnostics_for`); gutter/squiggle rendering of diagnostics is
   not yet implemented (see Backlog).
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
9. **Standalone demo app** — `example/main.odin` creates a real SDL3 window
   + SDL_ttf-rendered editor, loads a sample `.odin` file, supports
   Ctrl/Cmd+S save, window resize, and launches via `task run`. Verified the
   window opens and stays responsive.

## Backlog / known limitations

- **Completion/signature-help/diagnostics UI** — the LSP client fully
  receives and stores these, but `editor_render` doesn't yet draw a
  completion popup, signature-help tooltip, or diagnostic
  gutter markers/squiggles. The data (`ed.lsp.last_completion`,
  `last_signatures`, `client_diagnostics_for`) is available for a host to
  render; wiring it into `editor/render.odin` is the next natural step.
- **LSP UTF-16 position encoding** — the LSP spec's `character` offset is a
  UTF-16 code-unit count; this client currently treats it as a raw byte
  offset. Correct and sufficient for ASCII-heavy Odin source, but wrong for
  non-ASCII identifiers/strings/comments. Would need a UTF-16-aware
  conversion in `lsp/protocol.odin`/`client_did_change` to fully fix.
- **Incremental document sync** — `didChange` currently sends the full
  document text on every change rather than incremental edits. Simpler and
  correct, but less efficient for very large files/high edit frequency.
- **Find/replace** — noted as a stretch goal in requirement #4, not
  implemented.
- **Ctrl/Cmd+D "select next occurrence"** — noted as a stretch goal in
  requirement #6, not implemented (Ctrl/Cmd+Alt+Up/Down add-cursor-
  above/below *is* implemented).
- **OLS version pinning is brittle** — OLS tracks Odin's development branch
  very closely; `Taskfile.yml`'s `OLS_REF` pins a commit verified to build
  against this project's installed Odin version, but upgrading the Odin
  compiler will likely require re-pinning OLS to a newer commit (bisect
  forward from `OLS_REF` until it builds again).
- **Horizontal scrolling** is implemented in the view-math (`scroll_col`)
  but nothing currently drives it from input (no explicit "scroll right"
  hotkey/mouse-drag-to-edge support yet) — long lines rely on the viewport
  clamp following the cursor during horizontal cursor movement only.
