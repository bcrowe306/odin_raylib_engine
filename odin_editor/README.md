# odin_editor

A modular, embeddable code editor for Odin + SDL3 projects, with VSCode/Zed-style
editing, Odin-aware syntax highlighting, and an embedded
[Odin Language Server (OLS)](https://github.com/DanielGavin/ols) client for
completion, signature help, and diagnostics.

See `REQUIREMENTS.md` for the full feature scope this module implements.

## Package layout

```
odin_editor/
  buffer/     text buffer core: lines, cursors/selections, undo/redo, file IO
  keymap/     platform-aware hotkey table (VSCode/Zed-equivalent defaults)
  syntax/     pluggable tokenizer; ships an Odin-language highlighter
  lsp/        JSON-RPC client implementing the LSP subset OLS needs
  editor/     SDL3 glue: input, actions, rendering, clipboard, file API,
              event injection hook -- this is the package a host embeds
  example/    standalone SDL3 demo/test app (package main)
  third_party/ols  fetched on demand by `task ols:fetch`/`ols:build`, not vendored
```

Every package except `editor` and `example` is SDL-independent and unit
tested on its own (`buffer`, `keymap`, `syntax`, `lsp`). `editor` depends on
`vendor:sdl3`/`vendor:sdl3/ttf` for input translation, clipboard, and
rendering, but its logic (action dispatch, viewport math, event injection)
is still unit tested without needing a real window.

## Building & testing

This project uses [Task](https://taskfile.dev) (`brew install go-task` or
see their install docs). From inside `odin_editor/`:

```sh
task check          # odin check every package (fast type-check)
task test           # odin test every package (buffer/keymap/syntax/lsp/editor)
task build          # build the standalone example app
task run            # build & launch the standalone example app
task fmt             # odin fmt every package
task ols:fetch       # clone OLS and check out a known-compatible commit
task ols:build       # build the `ols` binary (needed for live LSP features)
task clean           # remove build outputs
```

You can also drive each package directly without Task:

```sh
odin check buffer -no-entry-point
odin test buffer -define:ODIN_TEST_THREADS=1
odin build example -out:/tmp/odin_editor_demo
```

## Embedding in a host application

```odin
import ed "odin_editor/editor"
import km "odin_editor/keymap"

editor := ed.editor_init(km.Platform.MacOS) // or .Other for Win/Linux
defer ed.editor_destroy(&editor)

ed.editor_load_file(&editor, "some/file.odin")

// per frame:
for sdl.PollEvent(&event) {
    ed.editor_handle_event(&editor, event)
}
ed.editor_update(&editor)           // polls LSP responses, drains injected events
ed.editor_render(&editor, renderer, font, ed.default_theme(), x, y)
```

Save/load is a plain API the host drives explicitly — there is no global
editor state, so multiple `Editor` instances can coexist (e.g. multiple open
tabs/panes), each owning its own buffer, keymap, and (optionally) its own
LSP client instance via `editor_attach_lsp`.

### Event injection hook (automated testing / scripting)

`editor` exposes `editor_inject_key`, `editor_inject_text`,
`editor_inject_event`, and `editor_pump_injected_events` so a host, test, or
demo script can drive the editor deterministically without a real display or
input device:

```odin
ed.editor_inject_text(&editor, "hello world")
ed.editor_inject_key(&editor, sdl.K_HOME)
ed.editor_pump_injected_events(&editor)
```

`example/main.odin` demonstrates this via `--script` / `--script-only` CLI
flags (see below).

## Standalone demo app

```sh
task run                  # interactive window, opens example/assets/sample.odin.txt
task run -- --script       # runs the injection-hook script, then stays interactive
task run -- --script-only  # runs the script, prints the resulting buffer, and exits
```

Interactive hotkeys follow VSCode/Zed conventions (Cmd on macOS, Ctrl
elsewhere) for navigation, selection, clipboard, undo/redo, and save
(Ctrl/Cmd+S writes back to the opened file).

## Odin Language Server (OLS)

OLS tracks Odin's development branch closely, so an arbitrary "latest" OLS
checkout frequently fails to compile against whatever Odin compiler version
is actually installed. `Taskfile.yml`'s `OLS_REF` pins a specific OLS commit
known to build cleanly against this project's target Odin version; override
it (`task ols:build OLS_REF=<sha>`) if you're on a different Odin version and
need a different pin.

```sh
task ols:fetch   # clone third_party/ols, checkout OLS_REF
task ols:build   # odin build -collection:src=third_party/ols/src -> third_party/ols/ols
```

Then attach it to an editor instance:

```odin
ed.editor_attach_lsp(&editor, []string{"odin_editor/third_party/ols/ols"}, project_root)
```

Once `editor.lsp_enabled` is true, `editor_update` polls for responses each
frame; `editor_request_completion`/`editor_request_signature_help` are
triggered automatically from the default completion/signature-help hotkeys.

## Git workflow

All work happens locally on feature branches (e.g.
`feature/odin-editor-scaffold`) with descriptive commits per package/feature;
no remote push happens as part of this effort.
