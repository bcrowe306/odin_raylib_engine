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

## Context menus

**Right-click in the code** moves the caret to the click (unless it is
inside a selection) and opens the menu. First comes what is under the click:

- a **string naming a node** (`find_node("Player")`, a `get_node` path from
  the script's node, any node name of the open scene): *Select in the Scene
  Tree*;
- a **string naming a project file** (`"textures/ship.png"`): *Reveal in
  Assets*, and *Open* for scripts and shaders;
- a **symbol**: Go to Definition, Find All References, Rename Symbol,
  Scripting Reference (F1);
- a **selection**: Copy as Markdown (a fenced `lua` block) and **Wrap In** -
  `if condition then ... end` (the condition selected, type to replace it),
  `do ... end`, `local function name() ... end`; the lines are indented.

Then Cut / Copy / Paste / Paste from History, the **Selection**, **Go To**,
**Lines** and **Refactor** submenus, Format Document, Find / Replace, and
Copy Path / Copy Location. Every entry shows its shortcut; entries the
language server provides are disabled until it is ready. Esc closes a menu.

**Right-click a line number**: Add / Remove Breakpoint, Add / Edit
Condition..., **Run to Here** (while paused: continues to that line with a
temporary breakpoint), Select Line, Copy Location.

**Right-click a tab**: Save, Save As..., Find Usages of This Script, Close,
Close Others, Close to the Right, Close Saved, Close All, Copy Path, Copy
Absolute Path, Reveal in Assets, Reveal in Finder. Tabs with unsaved changes
are never closed by the bulk closes.

## Selection

| Shortcut (macOS / Windows, Linux) | Command |
|---|---|
| Cmd+A | Select all |
| Cmd+L | Select line (again: the next line too) |
| Ctrl+Shift+Right / Alt+Shift+Right | **Expand selection** to the next enclosing unit |
| Ctrl+Shift+Left / Alt+Shift+Left | **Shrink selection** back one step |

Expand selection grows through the code's structure (Zed's "select larger
syntax node"): the word -> a call (`find_node("Player")`) -> a string's
contents -> the string -> inside brackets -> the brackets -> the line ->
the body of the enclosing `function` / `if` / `for` / `while` / `do` /
`repeat` block or `{ }` table -> the whole block -> the next block out ->
the file. The structure comes from `code_structure.odin`: bracket pairs and
blocks outside strings and comments, computed once per edit only when a
feature needs it.

## Multi-cursor

| Shortcut | Command |
|---|---|
| Cmd+D | Select the next occurrence |
| Cmd+Shift+L | Select all occurrences |
| Cmd+Alt+D | **Skip occurrence**: select the next one instead of this one |
| Cmd+Alt+Up / Down | Add a cursor above / below |
| Shift+Alt+I | **A cursor at the end of every selected line** |
| Cmd+U | **Undo cursor**: back to the cursors before the last added |
| Cmd+Shift+M | **Select inside** the quotes / brackets around the caret (again: the next pair out) |
| Alt+click | Add a cursor (on one: remove it) |
| Alt+drag | **Column (box) selection**: a cursor per line, the same columns |

## Brackets and indentation

- The **bracket pair at the caret** is outlined. **Cmd+Shift+\\** jumps to
  the matching bracket; away from a bracket, to the closer of the brackets
  around the caret.
- **Rainbow brackets**: brackets are coloured by nesting depth (gold,
  violet, blue, repeating); an unmatched bracket is red.
- **Indent guides**: a thin line at each indentation level (blank lines
  take the next code line's); the guide of the block around the caret is
  brighter.
- Both are in Settings > Code Editor (`rainbow_brackets`, `indent_guides`
  in settings.ini).

## Display

- **Other uses of the caret's word** get a faint background (identifiers
  only, not strings or comments).
- **Visible whitespace**: dots for spaces and lines for tabs - inside
  selections by default (Settings > Code Editor > Show Whitespace: None /
  In Selections / All).
- **Soft wrap** (Alt+Z, or Settings > Code Editor): long lines wrap at the
  Code area's width at a space, continuation rows indented like the line
  and marked in the gutter; Up / Down move by screen row. There is no
  horizontal scrolling while it is on.

## Inlay hints

Parameter names appear before call arguments - `Audio.play_sound(path:
"hit.wav", volume: 0.5)`, `self.node:set_rotation(degrees: angle)` - for
the engine API (from `engine/definitions/engine_api.lua`, compiled into the
editor) and for the functions the file defines. A hint is left out when the
argument already says it (`x` for `x`, `self.speed` for `speed`). Hints are
inline: the text after them moves right, and clicks and carets skip them.
**Ctrl+Alt+H** (or Settings > Code Editor > Inlay Hints) turns them off.
They are computed per line when first shown and cached until the next edit.

## Breadcrumbs and sticky scroll

- **Breadcrumbs** (a bar above the code): the file › the function › the
  blocks around the caret (`PlayerShip:update › if self.cooldown_timer > 0
  then`). Click one to go to its first line.
- **Sticky scroll**: while the top of the view is inside a block, the
  first lines of up to 3 enclosing blocks stay pinned at the top with
  their line numbers (and a shadow under them). Click one to go there.
- Both can be turned off in Settings > Code Editor.

## Overview strip and git gutter

- **Overview strip** (right edge, beside the scrollbar - the minimap): the
  whole file at a glance - errors and warnings, find matches, uses of the
  caret's word, breakpoints, changes since the last commit, the caret, and
  the visible part. Click or drag in it to scroll there.
- **Git gutter**: lines added (green bar), modified (blue bar) and removed
  (red triangle) since the last commit, at the gutter's right edge. The
  committed text is read with `git show HEAD:<file>` on a worker thread
  when the script opens and when it is saved; the comparison (a Myers line
  diff) runs once per edit after typing pauses. Files outside git or not
  committed show nothing.

## Folding

A `function` / `if` / `for` / `while` / `repeat` / `do` ... `end` block, a
`{ }` table spanning lines or a run of comment lines folds to its first and
last line, with a **… N lines** chip after the first (click it to unfold).

| Shortcut | Command |
|---|---|
| (gutter arrow) | Fold / unfold - the arrow shows when the mouse is over the gutter, and always on a folded line |
| Cmd+Alt+[ / Cmd+Alt+] | Fold the innermost block around the caret / unfold |
| Cmd+Alt+Shift+[ / ] | Fold all functions, tables and comment runs / unfold all |

Up / Down step over a fold; a caret inside a block that gets folded moves
to its first line. Folds stay with their block through edits above them
and disappear when the block does.

The display (rows on screen: folds and wrapped lines) comes from
`code_display.odin`, rebuilt only when the text, the wrap width or the
folds change; drawing touches only the visible rows.

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
