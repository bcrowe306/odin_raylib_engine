# FIXES

Fixes and tweaks found while using the engine and editor, worked through one
by one. Each: fix, test (engine test and/or editor drive; screenshots for UI),
document if behaviour changes, tick it off here with a short "done:" note.

## Open

- [ ] F.4 Editor window: remember its state; no Welcome when opening a project.
  The editor window should come back the way it was left. Closing and
  reopening the app should restore its last state: size, position, maximized
  / fullscreen, and the monitor it was on. Launching a new project or opening
  another one should also open in that same state. And when a project is
  created or opened, the editor should go straight to it, without the
  Welcome window.
  - Where:
    - `editor/main.odin` (~line 66): `rl.InitWindow(1600, 900, ...)` is
      hardcoded and nothing saves the window geometry today.
    - `editor/editor_settings.odin`: `Editor_SaveSettings` /
      `settings_from_ini` (user settings, `[general]`) is the natural place
      to store it (e.g. a `[window]` section: x, y, width, height,
      maximized, monitor).
    - `editor/file_ops.odin`: `Editor_SwitchProject` /
      `Editor_LaunchPendingProject` (~line 285) relaunch the editor with
      `--project <path>`; `Editor_NewProject` goes through the same path.
    - `editor/welcome.odin`: `Welcome_Render` opens itself at startup when
      `GlobalSettings.showWelcome` is set, whatever the launch reason.
  - Expected:
    - Save the window state on quit, and before the relaunch in
      `Editor_LaunchPendingProject` (so the new process reads it). Restore it
      right after `InitWindow` (on macOS some window calls only take a frame
      later - see `Runner_ApplyFullscreen` in `engine/runner.odin`). Clamp
      to a connected monitor, so a window saved on an unplugged display
      isn't lost off-screen. Size / position from the restored (not
      maximized) bounds.
    - Skip the startup Welcome when the editor was launched on a project
      (`--project`, i.e. after New Project / Open Project / a recent
      project). Help > Welcome still opens it. Plain startup still follows
      the `showWelcome` setting.
    - Drives (`GlobalDrive.enabled`) and `--hidden` keep a fixed window size
      and don't read or write the saved state.
  - Check: an editor test / drive that saves and reloads the window section
    of the settings, and that the Welcome stays closed when started with
    `--project`. Manual check on macOS: resize / move / maximize, quit,
    reopen; then File > New Project and Open Project - same window, no
    Welcome.

## Done

- [x] F.3 Code editor: overridden methods flagged as duplicate fields.
  In a Lua script, a method that overrides / implements one the engine
  declares sometimes gets a yellow squiggle (a warning) saying it's a
  duplicated field. That's a false warning: overriding is the intended
  pattern.
  - The warning comes from lua-language-server (most likely its
    `duplicate-set-field` diagnostic), shown by the code editor
    (`editor/code_editor_lsp.odin`). It's "sometimes", so check what
    triggers it:
    - Two scripts in the project declaring the same class
      (`---@class Enemy`, e.g. copied scripts or templates). LuaLS merges
      them and sees each method set twice.
    - A script's class inheriting from `ScriptInstanceBase`, whose lifecycle
      callbacks and events (`update`, `ready`, `on_body_entered`...) are
      `---@field` entries (`engine/definitions/engine_api.lua` ~9135).
    - Generated definitions (`.rayzr/definitions/project_types.lua`,
      `editor/lua_project_types.odin`) declaring the script classes or their
      methods again, so the user's `function X:foo()` is the second
      definition.
    - Stale definitions (an old `.ore/definitions` copy, or a renamed script)
      still in the workspace.
  - Expected: no warning for overriding engine callbacks or for a script's
    own methods. Fix it at the source if the engine's definitions cause it
    (class names unique per script, or don't re-declare methods in
    project_types). Otherwise turn the diagnostic off in the `.luarc.json`
    the editor writes (`luarc_text`, `editor/lua_project.odin`: add
    `"diagnostics.disable": ["duplicate-set-field"]`). Real duplicates in a
    single file are rare in game scripts.
  - Check: a drive (lua_tooling / code_editor) with two scripts overriding
    `update` / `on_body_entered` and a shared class name - no warning
    diagnostics in the editor.
  - done (#264): the cause was the editor's file history - `.rayzr/history/`
    keeps a copy of every saved script, each declaring the same `---@class`,
    and LuaLS read them as workspace files. The `.luarc.json` the editor
    writes now has `"workspace.ignoreDir": [".rayzr/history"]` (checked with
    `lua-language-server --check` on the demo project: 0 duplicate-set-field
    warnings, from dozens). Duplicate / Paste of a script also renames its
    class after the copy's file name (player_copy.lua: PlayerCopy), so a copy
    doesn't redeclare the original's class. Test: editor
    test_luarc_ignores_history_and_copies_rename.

- [x] F.1 State machine graph: two-way transitions are hard to select.
  When two states have transitions to each other (A → B and B → A), the two
  arrows sit side by side, nearly on top of each other, and it's hard to click
  the one you want. They should curve away from each other in the editor
  (each arrow bowing out to its own side), so both are clearly separate and
  easy to hover / select.
  - Where: `editor/state_machine_graph.odin`, the transitions loop (~line
    397). Today a pair both ways is drawn as two straight lines shifted 7 px
    sideways (`perp * 7`, not scaled by zoom), and hover uses
    `seg_dist(mouse, a, b) < 6`. So the hit areas of the two arrows overlap
    and the nearer one wins.
  - Expected: curved arrows (e.g. a quadratic / cubic Bézier whose control
    point is pushed out along `perp`, scaled with zoom). Hover hit-testing
    should follow the curve. The arrowhead should point along the curve's end
    tangent, and the condition label should sit at the curve's midpoint. A
    single (one-way) transition stays straight.
  - Check: the `smg.tr:<i>` drive items should sit on the curve's middle
    (state machine drives: state_graph, state_graph_live, state_guards).
  - done: two-way pairs are quadratic Beziers bowing apart (30 px x zoom), hit-tested along the curve (nearest arrow wins), arrowhead on the end tangent, label and the `smg.tr:<i>` drive item at the curve's middle; arrows to the same state loop over the box; manual arrows dashed. state_graph.drive clicks each arrow of a pair.

- [x] F.2 State machine: triggers don't switch states reliably.
  `sm_trigger` (and trigger conditions in general) don't change states
  consistently - sometimes the change happens, sometimes it doesn't, or it
  happens later than expected. This needs a proper look at the implementation,
  not a one-line patch.
  - Where: `engine/state_machine_node.odin` - `StateMachine_Step` (~line 626),
    `sm_fire` / `consume_triggers` (~576, ~647), `StateMachine_Guard`,
    `StateMachineNode_Update` (~727); Lua `sm_trigger` in
    `engine/script_bindings.odin` (~2811).
  - What the code does today, as starting points to check:
    - A trigger stays set until a transition that uses it *fires*. A trigger
      set while no arrow out of the current state uses it stays latched, and
      can fire much later from another state, unexpectedly.
    - An arrow blocked by a guard (minTime, noInterrupt, leaveWhen /
      enterWhen, can_exit_ / can_enter_) keeps its trigger set, so it fires
      whenever the guard opens. Sometimes that's useful buffering, but it's
      surprising when it isn't wanted.
    - Only one transition fires per update, the first in list order that
      passes (Any-state arrows included). The others' triggers stay set, so
      the arrow order decides the outcome.
    - Update order: a script calling `sm_trigger` after the machine has
      updated this frame is only seen next frame. Check this is consistent and
      that nothing between frames (pause, state enter) clears or skips it.
    - Unknown / misspelled trigger names: check whether `sm_trigger("nmae")`
      warns or silently does nothing.
  - Expected: a trigger has clear, documented semantics. It's used up by the
    update that checks it: it fires the first arrow it opens, or is dropped
    when no arrow out of the current state can use it now. Optionally a
    per-trigger (or per-machine) "buffer for N seconds" for input buffering.
    Unknown names should get a warning, and the editor's live view should show
    a pending trigger.
  - First step: reproduce it with an engine test (a machine with trigger
    arrows, guards and Any-state arrows, stepped frame by frame) and a drive.
    Ask the user for their failing case if it isn't covered. Then document the
    semantics in the state machine docs.
  - done (with F.5): triggers are their own list; a set trigger is used by the first Automatic arrow it opens, else cleared after the first update that checked it, or after its buffer time; set during an update = checked by the next; unknown names warn once and sm_trigger returns false; the live view shows pending triggers and the time left. Engine tests: test_sm_triggers, the guide tests (input buffering).

- [x] F.5 State machine rework: manual transitions by default, clear state
  callbacks, triggers apart from parameters, settings in the bottom tab,
  thorough docs. (Covers F.1 and F.2.)
  - States (graph nodes, as now):
    - Callbacks by name, in this order: entering runs
      `on_enter_<state>(previous)` first, then the child machine starts and
      the animation plays; `on_update_<state>(dt)` every frame while active;
      leaving stops the child machine, then `on_exit_<state>(next)` runs
      last. `sm_stop` calls the current state's `on_exit` too. The "add
      callbacks" button that writes them into the script stays.
    - Optional animation, optional child machine (a link to another State
      Machine node), Initial, exit guards and enter guards (kept).
    - New per-state **Allow Retrigger**: the state may go to itself
      (re-entered: on_exit, on_enter, animation restarted).
  - Arrows: a mode, **Manual** (the default for new arrows) or
    **Automatic**; arrows from old scenes load as Automatic (behave as
    before). Any-state arrows have modes too. Manual arrows drawn
    differently; two-way pairs curve apart (F.1).
  - Lua `sm:transition(state, {force = true})` replaces `sm_request` and
    `sm_travel` (removed):
    - needs an arrow from the current state (or Any state), Manual or
      Automatic;
    - without force: the exit / enter guards, and the arrow's conditions
      when it has any; with `force = true`: neither;
    - immediate (inside the call); returns true, or false + the reason
      ("Idle: leave after 0.5s");
    - chains (a callback calling transition again) stop at depth 8 with a
      warning naming the states; refused (warning) from inside a guard or a
      "script says" condition; at most one automatic change follows a
      manual one in the same update (history shows both).
  - Triggers apart from parameters (data, save format, Lua, the tab); they
    drive Automatic arrows only. A set trigger fires the first arrow it
    opens, or clears after one update; an optional per-trigger buffer time
    keeps it set longer (input buffering: jump pressed just before landing,
    queued combo attacks). The live view shows pending triggers and their
    time left; unknown names warn. (F.2)
  - Parameters typed: bool, int, float. Every condition kept and verified
    with its own engine test (incl. animation finished on looping
    animations, == on floats).
  - Editor: the State Machine tab gets sub-tabs - Graph (with the selection
    panel), Parameters & Triggers, Settings (player, initial, autostart).
    The Inspector shrinks to a summary + "Edit in State Machine Tab";
    selecting a State Machine switches to its tab. Live view while playing
    and every current graph feature kept.
  - Docs (part of the fix): a rewritten guide - concepts, each sub-tab with
    screenshots, a section per feature (what for, when, example),
    tutorials (platformer character with input buffering, enemy AI with
    manual transitions, combo chain), pitfalls, moving from sm_request /
    sm_travel. Every Lua function fully documented in engine_api.lua (what,
    what for, arguments, returns, edge cases, an example). Examples proven:
    the guide's scripts are real files in tests/state_machine, run by engine
    tests and runner tests in CI; drives cover the tab.
  - Gaps found in the old code (2026-10-26): no arrow mode (every arrow
    automatic; no conditions = at once); two manual calls (sm_request
    guarded, sm_travel forced); callback order (child / animation before
    on_enter; on_exit before the child stops; no on_exit on stop; no
    on_update the frame a change fires); triggers were parameters latched
    until used; parameters all floats; settings only in the Inspector; an
    Any-state arrow to the current state skipped (no self-transitions).
  - done: engine (state_machine_node.odin), save format with migration (old arrows Automatic, old trigger parameters become triggers), Lua sm_transition / sm_can_transition / sm_trigger_pending / sm_clear_trigger (sm_request / sm_travel removed), the State Machine tab's Graph / Parameters & Triggers / Settings pages, the Inspector summary, the guide engine/docs/state_machine.md with screenshots (docs_state_machine.drive) and its tutorials as real files in tests/state_machine (engine tests + runner tests in CI); drives updated.

