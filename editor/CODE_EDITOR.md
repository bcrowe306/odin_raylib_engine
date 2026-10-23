# Code editor (the Code tab)

The editor's Code tab edits Lua scripts (and shaders) with Zed-style
editing, `lua-language-server` support and engine-aware extras. This page
lists everything it does and every shortcut; the Lua API itself is in
[`engine/SCRIPTING.md`](../engine/SCRIPTING.md).

On macOS **Cmd** is the primary modifier (Ctrl on Windows / Linux); the
tables write Cmd. Every command is also in the command palette
(Cmd+Shift+P) and can be rebound in Settings > General > Keymap.

Source: `editor/code_editor.odin` (input, drawing), `code_commands.odin`
(commands), `code_editor_lsp.odin` (completion, hover, LSP), `code_*.odin`
(features), on the `odin_editor` packages (`buffer`, `syntax`, `lsp`).
Drives (UI tests) in `tests/drive/code_*.drive`, `lua_*.drive`.

## Opening scripts

Double-click a script in Assets, the edit button beside a node's script in
the Inspector, *Open Script* in the scene tree's menu, or double-click a
console message with `file.lua:LINE`. *New Script* opens a dialog with
templates (see SCRIPTING.md). Cmd+P goes to a file; Cmd+Shift+T reopens the
last closed tab; Cmd+W closes one.

## Editing

| Shortcut | Command |
|---|---|
| Cmd+X / Cmd+C / Cmd+V | Cut / copy / paste (see Clipboard) |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| Cmd+/ | Toggle comment |
| Cmd+] / Cmd+[ | Indent / outdent |
| Alt+Up / Alt+Down | Move line(s) |
| Cmd+Shift+D, Alt+Shift+Down / Alt+Shift+Up | Duplicate line down / up |
| Cmd+Shift+K | Delete line |
| Enter | New line, indented like this one (one level more after `function ...)`, `then`, `do`, `{`, `(`, `repeat`, `else`) |
| Cmd+Enter / Cmd+Shift+Enter | Insert line below (indented like Enter) / above (this line's indentation) |
| Ctrl+J | Join lines |
| Cmd+Backspace | Delete to line start |
| Tab | Snippet expansion / next snippet placeholder / indent |

Brackets and quotes close themselves; typing a closer steps over it; a
selection typed over with a bracket is wrapped.

## Clipboard

- **Cut / copy with nothing selected** takes the whole line(s). Pasting
  such a copy inserts it as whole line(s) above the cursor's line - wherever
  the cursor is in that line - like Zed and VS Code.
- **Several cursors**: when the clipboard has as many lines as there are
  cursors, each cursor gets its own line.
- **Paste re-indents**: multi-line text pasted at the start of a line (only
  indentation before the cursor) is re-indented to that line's indentation,
  keeping its own relative indentation.
- **Clipboard history** (Cmd+Shift+V): the last 20 copies and cuts; Up /
  Down / Enter (or click) pastes one, Esc closes.
- **Copy Path / Copy Absolute Path / Copy Location** (`scripts/x.lua:12`)
  in the command palette and the context menus.

## Multi-cursor

| Shortcut | Command |
|---|---|
| Cmd+D | Select the next occurrence |
| Cmd+Shift+L | Select all occurrences |
| Cmd+Alt+Up / Down | Add a cursor above / below |
| Alt+click | Add a cursor |

## Find

| Shortcut | Command |
|---|---|
| Cmd+F / Cmd+Alt+F | Find / find and replace |
| Cmd+G / Cmd+Shift+G (F3 / Shift+F3) | Next / previous match |
| Ctrl+G | Go to line |

## Language server

Completion (Ctrl+Space, as you type), signature help (Cmd+Shift+Space),
hover, diagnostics (squiggles, gutter, status line), go to definition (F12
/ Cmd+click), find references (Shift+F12), rename (F2), format
(Cmd+Shift+I). Engine names complete from the generated project types
(SCRIPTING.md > Completion of project names). F1 opens the Scripting
Reference at the symbol.

## Debugging

Click a line number for a breakpoint; right-click it for a condition. The
Game tab shows the call stack, locals and watches; F8 / F10 / F11 /
Shift+F11 continue and step. See SCRIPTING.md > Debugging.
