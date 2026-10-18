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
              completion/signature-help popups, event injection hook --
              this is the package a host embeds
  control/    remote-control hook: localhost TCP server that pushes real SDL
              events into a running host app, reports state, takes screenshots
  example/    standalone SDL3 demo/test app (package main)
  tools/edctl command-line client for the control hook (package main)
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
task test           # odin test every package (buffer/keymap/syntax/lsp/editor/control)
task test:e2e       # in-process end-to-end suite (real window, real OLS if built)
task test:remote    # drive the running demo via the control hook (needs OLS)
task build          # build the standalone example app
task build:edctl    # build the control-hook CLI client (tools/edctl/edctl)
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
flags (see below), and `example/e2e.odin` (`task test:e2e`) uses it for the
full end-to-end suite, including live OLS completion/signature-help checks.

### Remote control hook (drive a running app from outside)

The `control` package lets an external process drive a *running* host app
over a loopback TCP socket. Commands become real SDL events pushed with
`sdl.PushEvent`, so they arrive through the host's own `SDL_PollEvent` loop
exactly like physical keyboard/mouse input (host-level shortcuts included).
It can also dump state as JSON, block until a condition holds, assert on
state, and save PNG screenshots. Hosting it takes three calls:

```odin
import "odin_editor/control"

srv: control.Server
control.server_start(&srv, 7777, window, platform) // binds 127.0.0.1 only
defer control.server_stop(&srv)

// per frame:
control.server_poll(&srv, &editor)                   // before SDL_PollEvent
for sdl.PollEvent(&event) { ... }
ed.editor_update(&editor)
ed.editor_render(&editor, renderer, font, theme, 0, 0)
control.server_after_render(&srv, &editor, renderer) // before RenderPresent
sdl.RenderPresent(renderer)
```

Run the demo with the hook and talk to it with `tools/edctl`:

```sh
task build build:edctl
./example/editor_demo --control 7777 path/to/file.odin &
./tools/edctl/edctl --port 7777 --retry 10 \
    "wait lsp-ready 10000" "cursor 9 0" "type fmt." "wait completion" \
    "expect completion-has println" "screenshot /tmp/popup.png" state
./tools/edctl/edctl --port 7777 < tools/lsp_smoke.edctl   # or a script file
```

Protocol: one command per line, exactly one reply line per command (`ok …`,
`err <reason>`, `fail expected … got …`, `timeout <cond>`, or JSON for
`state`). A client's commands run in order; a command that pushes events
holds the next one until the following frame, so `state`/`wait`/`expect`
always observe the result of the input before them.

| command | effect |
|---|---|
| `key <chord> [n]` | press a key `n` times. Chords: `primary+space`, `shift+end`, `down`, `cmd+s`, `.`; `primary` = Cmd on macOS, Ctrl elsewhere |
| `type <text>` | one TEXT_INPUT event per character (like real typing, so `.`/`(` triggers fire) |
| `text <text>` | a single TEXT_INPUT event with the whole string. Escapes: `\n` `\t` `\\` |
| `click <x> <y>` / `wheel <dy>` | mouse button press / wheel scroll at window pixels |
| `cursor <line> <col>` | place the cursor directly (0-based) |
| `open <path>` | `editor_load_file` |
| `state` | JSON: text, cursor, LSP status, completion items/selection/rect, signature label/active parameter/rect |
| `wait <cond> [ms]` | block until `completion`, `no-completion`, `signature`, `no-signature`, `lsp-ready` or `lsp-idle` (default 5000 ms) |
| `wait frames <n>` | block for `n` frames |
| `expect <field> <value>` | assert `line`, `cursor`, `text-contains`, `completion-selected`, `completion-has`, `signature` (label contains) or `signature-param` |
| `screenshot <file.png>` | save the next rendered frame |
| `quit` | push SDL_EVENT_QUIT |

`--control-only` makes the demo accept input *only* from the hook: the window
is created non-focusable and real keyboard/mouse events are dropped
(`control.event_is_injected` tells them apart), so a scripted run can't be
disturbed by — or steal — the user's typing. `task test:remote` uses it.
The hook is opt-in and listens on loopback only; don't enable it in builds
you ship.

## Standalone demo app

```sh
task run                  # interactive window, opens example/assets/sample.odin.txt
task run -- path/to/x.odin # open a specific file
task run -- --script       # runs the injection-hook script, then stays interactive
task run -- --script-only  # runs the script, prints the resulting buffer, and exits
task run -- --control 7777 # also enable the remote control hook (see above)
task run -- --no-lsp       # don't attach OLS even if it's built
```

If `third_party/ols/ols` has been built, the demo attaches it automatically
(rooted at the opened file's directory).

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

Once attached, `editor_update` each frame polls for responses, sends the
deferred `didOpen` once `initialize` has completed, pushes a full-text
`didChange` whenever the buffer changed, and refreshes the popups.

- **Completion** opens on `.`, on the first identifier character of a word,
  or with Ctrl/Cmd+Space. The list filters locally as you type (prefix
  matches first, then fuzzy), Up/Down/PageUp/PageDown select, Enter/Tab
  accept (honoring the item's `textEdit`/`insertText`, as one undo step),
  Escape dismisses, and moving the cursor out of the word closes it.
- **Signature help** opens on `(` / `,` or Ctrl/Cmd+Shift+Space, re-queries
  as the cursor moves so the active parameter is highlighted, and closes once
  the cursor leaves the call's parentheses (OLS keeps answering just past the
  closing `)`, so the client checks paren depth itself) or on Escape.

Responses to superseded requests are dropped, so a slow reply can't
overwrite a newer one.

Note: OLS derives package paths from directory names, so keep the opened
file in a directory whose name is a valid identifier (no dots) or
completion silently returns nothing.

## Git workflow

All work happens locally on feature branches (e.g.
`feature/odin-editor-scaffold`) with descriptive commits per package/feature;
no remote push happens as part of this effort.
