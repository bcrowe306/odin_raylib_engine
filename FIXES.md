# FIXES

Fixes and tweaks found while using the engine and editor, worked through one
by one. Each: fix, test (engine test and/or editor drive; screenshots for UI),
document if behaviour changes, tick it off here with a short "done:" note.

## Open

- [ ] F.1 State machine graph: two-way transitions are hard to select.
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

- [ ] F.2 State machine: triggers don't switch states reliably.
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

- [ ] F.3 Code editor: overridden methods flagged as duplicate fields.
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

## Done
