---
name: odin-editor-e2e
description: Run the odin_editor end-to-end test suite (task test:e2e) after making changes to odin_editor/buffer, keymap, syntax, lsp, editor, or example, to verify every editor feature behaves correctly when driven through the real SDL event-injection hook, in addition to (not instead of) odin check/odin test.
---

# odin_editor End-to-End Test Skill

`odin_editor` is a modular, embeddable SDL3 code editor. Unit tests cover
each package in isolation, but this skill runs the **real demo app**
(`example/editor_demo --e2e`) and drives it exclusively through the
public `editor_inject_key` / `editor_inject_text` SDL event-injection hook
— the same mechanism a host app or scripted demo uses — exercising typing,
navigation, selection, multi-cursor, clipboard, undo/redo, indent/outdent,
newline auto-indent, backspace/delete, file save/load, syntax
highlighting, viewport scrolling, rendering, and live Odin Language
Server (`ols`) completion, end to end.

Always run this whenever `.odin` files under `odin_editor/buffer`,
`odin_editor/keymap`, `odin_editor/syntax`, `odin_editor/lsp`,
`odin_editor/editor`, or `odin_editor/example` are created, modified, or
moved — in addition to the normal `odin check` / `odin test` workflow,
not instead of it.

## Workflow

1. **Run package checks and unit tests first** (fast, no window required):
   ```bash
   cd odin_editor
   task check
   task test
   ```
   All packages must type-check cleanly and all unit tests must pass with
   zero memory leaks before running the e2e suite.

2. **Build OLS once per environment, if not already built**:
   The suite's `[lsp]` checks gate on `third_party/ols/ols` existing and
   SKIP (not fail) gracefully if it's missing — but build it once so the
   live-LSP checks (`initialize` handshake + real completion request) are
   actually exercised:
   ```bash
   task ols:build
   ```

3. **Run the full end-to-end suite**:
   ```bash
   task test:e2e
   ```
   This builds `example/editor_demo` and runs it with `--e2e`, which:
   - opens a real SDL3 window + renderer (so rendering is exercised, not
     mocked),
   - resets the buffer and drives every feature purely through injected
     SDL key/text events (never calling internal buffer/action APIs
     directly),
   - prints a grouped `[PASS]`/`[FAIL]` report with a final
     `Total: N passed, M failed, T checks` line,
   - exits with status code `0` only if every check passed, `1` otherwise.

4. **Interpret the result**:
   - Exit code `0` and `Total: N passed, 0 failed` → the suite is green;
     proceed.
   - Any `[FAIL]` line or non-zero exit code is a real regression — do not
     ignore it. Read the failing check's `detail` (e.g. `got "..."` /
     `start=... end=...`) to see the actual vs. expected value, then fix
     the underlying editor code (not the test) unless investigation shows
     the test's expectation was wrong.
   - A crash with no final report (process aborts, e.g. SIGSEGV/SIGABRT)
     counts as a hard failure even though no `[FAIL]` line is printed —
     Odin has no exception handling, so a crash mid-suite means the exact
     check that triggered it must be found by re-running with fewer
     checks enabled or by adding temporary debug prints, not ignored.

5. **Clean up build artifacts** when done iterating:
   ```bash
   task clean
   ```

## Notes

- The suite lives in `odin_editor/example/e2e.odin`; the `--e2e` CLI flag
  is wired in `odin_editor/example/main.odin`.
- Add a new check for any new feature by following the existing pattern:
  reset editor state with `editor_set_text`, drive it via
  `editor_inject_key`/`editor_inject_text` + `editor_pump_injected_events`,
  then assert on buffer/cursor/selection state with `e2e_check`.
- Platform-correct modifiers matter: macOS uses `Super` (Cmd) as the
  primary modifier and `Alt` for word-jump, while other platforms use
  `Ctrl` for both — reuse the `primary_mod`/`word_mod` values computed in
  `main()` rather than hardcoding `KMOD_CTRL`.
