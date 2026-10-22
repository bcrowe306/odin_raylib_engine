---@meta
--- Lua API Definitions for Odin Raylib Engine
--- Language Server Protocol (LSP) stubs for autocomplete and type checking.

---@class RaycastHit
---@field hit boolean Whether the ray struck a physics shape
---@field point_x number World X hit coordinate
---@field point_y number World Y hit coordinate
---@field normal_x number World surface normal X
---@field normal_y number World surface normal Y
---@field fraction number Hit fraction from 0.0 to 1.0 along ray length
---@field node? Node Engine node attached to the struck body, if any

---@class Node
---Represents an engine scene hierarchy node with transform, lifecycle, and optional physics.
local Node = {}

---Gets the concrete runtime type of the node (e.g. "Node", "TextureNode", "DynamicBodyNode", "CameraNode").
---@return string
function Node:get_type() end

---Gets the display/debug name of the node.
---@return string
function Node:get_name() end

---Sets the display/debug name of the node.
---@param name string
function Node:set_name(name) end

---Gets the local position of the node.
---@return number x Local X position
---@return number y Local Y position
function Node:get_position() end

---Sets the local position of the node.
---@param x number Local X position
---@param y number Local Y position
function Node:set_position(x, y) end

---Translates the node position by the given delta offset.
---@param dx number Delta X
---@param dy number Delta Y
function Node:translate(dx, dy) end

---Gets the local rotation of the node in degrees.
---@return number rotation Rotation in degrees
function Node:get_rotation() end

---Sets the local rotation of the node in degrees.
---@param degrees number Rotation in degrees
function Node:set_rotation(degrees) end

---Rotates the node by delta degrees.
---@param degrees number Delta degrees
function Node:rotate(degrees) end

---Gets the local scale factor of the node.
---@return number sx Scale X
---@return number sy Scale Y
function Node:get_scale() end

---Sets the local scale factor of the node.
---@param sx number Scale X
---@param sy? number Scale Y (defaults to sx if omitted)
function Node:set_scale(sx, sy) end

---Shows another image on a TextureNode (project-relative path, e.g. a
---`texture` script property). Returns false if it isn't a TextureNode or
---the file can't be loaded.
---@param path TexturePath|string Project-relative texture path
---@return boolean ok
function Node:set_texture(path) end

---Gets the world-space global position of the node calculated from parent transforms.
---@return number x Global world X position
---@return number y Global world Y position
function Node:get_global_position() end

---Gets the world-space global rotation of the node in degrees.
---@return number rotation Global world rotation in degrees
function Node:get_global_rotation() end

---Checks if the node is actively updated in the scene loop.
---@return boolean
function Node:is_enabled() end

---Enables or disables updates for the node and its children.
---@param enabled boolean
function Node:set_enabled(enabled) end

---Checks if the node is rendered in the scene draw loop.
---@return boolean
function Node:is_visible() end

---Sets whether the node is rendered.
---@param visible boolean
function Node:set_visible(visible) end

---Gets the parent node, or nil if this is a root node.
---@return Node?
function Node:get_parent() end

---Returns an array of all direct child nodes.
---@return Node[]
function Node:get_children() end

---Adds a tag (group) to the node; false when it already has it.
---@param tag NodeTag|string
---@return boolean
function Node:add_tag(tag) end

---@param tag NodeTag|string
---@return boolean removed
function Node:remove_tag(tag) end

---@param tag NodeTag|string
---@return boolean
function Node:has_tag(tag) end

---@return string[]
function Node:get_tags() end

---Finds a direct child node by its exact name.
---@param name NodeName|string
---@return Node?
function Node:get_child(name) end

---Finds a node by path relative to this one: "Gun", "Body/Gun", "../Player", "." (self).
---@param path string Relative node path
---@return Node? node The node, or nil if there is none
function Node:get_node(path) end

---Reparents a child node under this node.
---@param child Node
function Node:add_child(child) end

---Detaches a child node from this node.
---@param child Node
function Node:remove_child(child) end

---Removes this node and all its children from the active scene.
function Node:destroy() end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

---@alias NodeEvent
---| "entered_tree"       # (all nodes) the node joined the scene
---| "exited_tree"        # (all nodes) the node is being removed
---| "child_added"        # (all nodes) value: the child Node
---| "child_removed"      # (all nodes) value: the child Node
---| "parent_added"       # (all nodes) value: the new parent Node
---| "parent_removed"     # (all nodes) value: the old parent Node
---| "timeout"            # TimerNode: the duration elapsed
---| "tick"               # TimerNode: every frame while running, value: elapsed seconds
---| "body_entered"       # AreaNode: value: the Node that entered
---| "body_exited"        # AreaNode: value: the Node that left (nil if it was destroyed)
---| "collision_started"  # Static/Dynamic body, CharacterMover: value: the other Node
---| "collision_ended"    # Static/Dynamic body, CharacterMover: value: the other Node
---| "hit_started"        # RaycastNode: value: the Node the ray started hitting
---| "hit_ended"          # RaycastNode: value: the Node it stopped hitting
---| "animation_finished" # FrameAnimationNode / AnimationPlayerNode (non-looping); value: animation name
---| "state_changed"      # StateMachineNode: value: the state entered
---| "finished"           # SoundNode / MusicNode: playback ended
---| "clicked"            # UIButtonNode
---| "value_changed"      # UI slider/checkbox/text input/dropdown/radio/knob/fader; value: new value
---| "submitted"          # UITextInputNode: value: text
---| "selected"           # UI list views: value: selected index
---| "row_selected"       # UITableNode: value: row index
---| "sorted"             # UITableNode
---| "item_clicked"       # UI toolbar: value: item id
---| "level_loaded"       # LdtkLevelNode: colliders/entities built; value: level identifier
---| "entity_spawned"     # LdtkLevelNode: value: the spawned Node

---Connects a handler to an event of this node (from any script). Handlers
---are removed automatically when the connecting script or this node is
---destroyed. A script also receives its own node's events as methods named
---`on_<event>` (e.g. `function MyScript:on_timeout() end`).
---@param event NodeEvent|string Event name (custom names work with `emit`)
---@param handler fun(value: any, source: Node) Called with the event value and this node
---@return integer id Connection id for `disconnect`
function Node:connect(event, handler) end

---Removes a connection made with `connect`.
---@param id integer Connection id
---@return boolean removed
function Node:disconnect(id) end

---Raises a custom event on this node: calls the node script's `on_<event>`
---method and every handler connected to that event name.
---@param event string Event name
---@param value? any Value passed to handlers
function Node:emit(event, value) end

-- ----------------------------------------------------------------------------
-- DynamicBodyNode Physics Methods
-- ----------------------------------------------------------------------------

---Applies a continuous force to this node (requires DynamicBodyNode).
---@param fx number Force X in Newtons
---@param fy number Force Y in Newtons
function Node:apply_force(fx, fy) end

---Applies an instantaneous impulse to this node (requires DynamicBodyNode).
---@param ix number Impulse X
---@param iy number Impulse Y
function Node:apply_impulse(ix, iy) end

---Gets the linear velocity of the physics body or character mover in world units per second.
---@return number vx Linear velocity X
---@return number vy Linear velocity Y
function Node:get_linear_velocity() end

---Sets the linear velocity of the physics body or character mover directly.
---@param vx number Linear velocity X
---@param vy number Linear velocity Y
function Node:set_linear_velocity(vx, vy) end

---Gets the angular velocity of the physics body in degrees per second.
---@return number omega Angular velocity in degrees/sec
function Node:get_angular_velocity() end

---Sets the angular velocity of the physics body in degrees per second.
---@param omega number Angular velocity in degrees/sec
function Node:set_angular_velocity(omega) end

---Gets the gravity scale multiplier for this physics body.
---@return number
function Node:get_gravity_scale() end

---Sets the gravity scale multiplier for this physics body.
---@param scale number
function Node:set_gravity_scale(scale) end

---Checks whether rotation is locked on this body.
---@return boolean
function Node:is_fixed_rotation() end

---Locks or unlocks rotation on this physics body.
---@param fixed boolean
function Node:set_fixed_rotation(fixed) end

---Sets the linear drag/damping coefficient.
---@param damping number
function Node:set_linear_damping(damping) end

---Sets the angular drag/damping coefficient.
---@param damping number
function Node:set_angular_damping(damping) end

---Checks if the physics body is awake and participating in simulation.
---@return boolean
function Node:is_awake() end

---Wakes up or puts the body to sleep.
---@param awake boolean
function Node:set_awake(awake) end

-- ----------------------------------------------------------------------------
-- Materials (any node): shader, blend mode, shader parameters
-- ----------------------------------------------------------------------------

---@alias BuiltinShader
---| "builtin:flash"     # flash_color, amount: tint toward a colour (hit flash)
---| "builtin:outline"   # outline_color, width: outline around the sprite
---| "builtin:dissolve"  # threshold, edge_width, edge_color: burn away
---| "builtin:grayscale" # amount
---| "builtin:wave"      # amplitude, frequency, speed: horizontal wave

---@alias BlendMode "alpha"|"additive"|"multiply"|"add_colors"|"subtract_colors"|"premultiplied"

---Sets the node's shader: a built-in or a project fragment shader (.fs). nil removes it.
---@param shader BuiltinShader|string|nil
function Node:set_shader(shader) end

---Sets a shader parameter (a uniform of the shader): a number, up to four
---numbers, a table {r, g, b, a} / {x, y}, or a texture path.
---@param name string
---@param x number|number[]|string
---@param y? number
---@param z? number
---@param w? number
function Node:set_shader_param(name, x, y, z, w) end

---Gets a shader parameter (its value, else the shader's default): up to four
---numbers, or the texture path.
---@param name string
---@return number|string|nil x
---@return number? y
---@return number? z
---@return number? w
function Node:get_shader_param(name) end

---Sets how the node is blended with what's behind it.
---@param mode BlendMode
function Node:set_blend_mode(mode) end

-- ----------------------------------------------------------------------------
-- LightNode Methods (2D lights; Scene.set_ambient darkens unlit areas)
-- ----------------------------------------------------------------------------

---Sets the light's colour (0..1).
---@param r number
---@param g number
---@param b number
function Node:light_set_color(r, g, b) end

---Sets the light's energy (brightness multiplier, 0..8).
---@param energy number
function Node:light_set_energy(energy) end

---@return number energy
function Node:light_get_energy() end

---Sets the light's radius (world units).
---@param radius number
function Node:light_set_radius(radius) end

-- ----------------------------------------------------------------------------
-- Properties (any node) and collision layers (body nodes)
-- ----------------------------------------------------------------------------

---Sets any Inspector property by its path ("gravityScale", "emitter.amount",
---"joint.revolute.motorSpeed", "tint", ...). Vectors as {x, y} or x, y;
---colours as {r, g, b[, a]} 0..1; enums by name.
---@param path string
---@param value any
---@param y? number
function Node:set_property(path, value, y) end

---Pauses this node and its children (except "always" ones).
---@param paused boolean
function Node:set_paused(paused) end

---@return boolean paused By itself, a parent or the game
function Node:is_paused() end

---@param mode "inherit"|"pausable"|"always"
function Node:set_pause_mode(mode) end

---Sets the text of a TextNode (restarting its typewriter), UI label or button.
---@param text string
function Node:set_text(text) end

---@return string
function Node:get_text() end

---TextNode: types the text out again (revealSpeed > 0).
function Node:text_restart() end

---@class DialogueLine
---@field speaker? string
---@field text string Rich text ([color=..] [size=..] [wave] [shake]), or a locale key when the box is localized

---DialogueNode: opens the box with these lines (strings or {speaker, text}),
---or one line: box:dialogue_show(text, speaker). Each line types out; the
---advance action (default "confirm") shows the rest, then the next line.
---Events: "line_shown"(index), "finished".
---@param lines string|(string|DialogueLine)[]
---@param speaker? string
function Node:dialogue_show(lines, speaker) end

---Shows the rest of the line, else the next one.
function Node:dialogue_next() end

function Node:dialogue_close() end

---@return boolean
function Node:dialogue_is_open() end

---LineNode: replaces its points (local to the node).
---@param points number[][] { {x, y}, ... }
function Node:line_set_points(points) end

---LineNode: appends a point (local to the node).
---@param x number
---@param y number
function Node:line_add_point(x, y) end

---LineNode: removes every point.
function Node:line_clear() end

---TrailNode: drops the recorded ribbon (e.g. after a teleport).
function Node:trail_clear() end

---@class NavOptions
---@field diagonal? boolean 8 directions (default true); no cutting past blocked corners
---@field smooth? boolean Straighten where the line of sight is clear (default true)
---@field walkable_painted? boolean TileMap: painted tiles are the floor (default: not `solid`)

---A* path on this TileMap's or LDtk level's grid (TileMap: painted tiles
---are walls when the map is solid; LDtk: IntGrid cells whose collision rule
---is Solid). Waypoints from the start to the end, or nil when unreachable.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param opts? NavOptions
---@return number[][]? path { {x, y}, ... }
function Node:nav_find_path(x1, y1, x2, y2, opts) end

---Whether the grid cell at a world position is walkable.
---@param x number
---@param y number
---@param opts? NavOptions
---@return boolean
function Node:nav_is_walkable(x, y, opts) end

---Reads an Inspector property by its path (vectors and colours as tables).
---@param path string
---@return any
function Node:get_property(path) end

---The collision layers this body's shapes are on: project layer names
---(Project Settings > Physics), "LayerN" or numbers 1-16; several or a table.
---@param ... string|integer|table
function Node:set_collision_layer(...) end

---The collision layers this body's shapes collide with.
---@param ... string|integer|table
function Node:set_collision_mask(...) end

-- ----------------------------------------------------------------------------
-- StateMachineNode Methods
--
-- States, transitions and conditions are set up in the Inspector. Entering a
-- state plays its animation on the AnimationPlayer; the machine's and its
-- parent's scripts get on_enter_<state>(previous) / on_exit_<state>(next),
-- and the machine emits "state_changed"(state).
-- ----------------------------------------------------------------------------

---Sets a parameter that transition conditions test (booleans become 1 / 0).
---@param name string
---@param value number|boolean
function Node:sm_set(name, value) end

---@param name string
---@return number value
function Node:sm_get(name) end

---Sets a trigger: it stays set until a transition that tests it fires.
---@param name string
function Node:sm_trigger(name) end

---Switches to a state now, ignoring conditions.
---@param state string
---@param blend? number Crossfade seconds for the state's animation
---@return boolean ok false when there is no such state
function Node:sm_travel(state, blend) end

---@return string state The current state ("" before it starts)
function Node:sm_state() end

---@return string state The state before the current one
function Node:sm_previous() end

---@return number seconds Time spent in the current state
function Node:sm_time() end

---Starts (or restarts) in a state, or in the initial state.
---@param state? string
function Node:sm_start(state) end

---Stops checking transitions (the current state stays).
function Node:sm_stop() end

-- ----------------------------------------------------------------------------
-- CharacterMoverNode Methods
--
-- Two control modes (Inspector: Control Mode):
--   Script (Godot style; new scripts on a CharacterMover use the platformer
--     template): the script sets the velocity and calls
--     character_move_and_slide() every frame.
--   BuiltIn: the node moves itself (speed, acceleration, jump, gravity,
--     optional keyboard input); character_move() steers it.
-- ----------------------------------------------------------------------------

---Moves by the velocity (x dt), sliding along whatever it touches; the velocity
---loses the part going into surfaces. Updates the floor / wall / ceiling state.
---Switches the node to Script mode.
---@param dt? number Defaults to the frame's delta time
---@return boolean collided
function Node:character_move_and_slide(dt) end

---Gets the velocity in pixels per second (+y is down).
---@return number vx
---@return number vy
function Node:character_get_velocity() end

---Sets the velocity in pixels per second (+y is down).
---@param vx number
---@param vy number
function Node:character_set_velocity(vx, vy) end

---Gets the gravity acting on the character: world gravity x its gravity scale.
---@return number gx
---@return number gy
function Node:character_get_gravity() end

---Sets the multiplier of the world gravity for this character.
---@param scale number
function Node:character_set_gravity_scale(scale) end

---Was the character standing on a floor after the last move?
---@return boolean
function Node:character_is_on_floor() end

---Was the character touching a wall after the last move?
---@return boolean
function Node:character_is_on_wall() end

---Was the character touching a ceiling after the last move?
---@return boolean
function Node:character_is_on_ceiling() end

---The floor's normal (0, -1 on flat ground; tilted on slopes).
---@return number nx
---@return number ny
function Node:character_get_floor_normal() end

---The wall's normal (points away from the wall).
---@return number nx
---@return number ny
function Node:character_get_wall_normal() end

---How far the last move actually went.
---@return number dx
---@return number dy
function Node:character_get_last_motion() end

---"script": the script moves it with character_move_and_slide; "builtin": it moves itself.
---@param mode "script"|"builtin"
function Node:character_set_control_mode(mode) end

---BuiltIn mode: steers the character horizontally and jumps if grounded.
---@param dirX number Horizontal direction (-1.0 to 1.0), times the node's max speed
---@param jump? boolean Whether to jump if grounded
function Node:character_move(dirX, jump) end

---Same as character_is_on_floor().
---@return boolean
function Node:character_is_grounded() end

---BuiltIn mode: sets the maximum horizontal run speed.
---@param speed number
function Node:character_set_speed(speed) end

---BuiltIn mode: sets the jump speed.
---@param speed number
function Node:character_set_jump_speed(speed) end

-- ----------------------------------------------------------------------------
-- AreaNode (Sensor Trigger) Methods
-- ----------------------------------------------------------------------------

---Checks whether any physics nodes are currently inside this sensor area.
---@return boolean
function Node:area_is_overlapping() end

---Returns the number of bodies currently overlapping this sensor area.
---@return number
function Node:area_get_overlap_count() end

---Returns an array of all nodes currently overlapping this sensor area.
---@return Node[]
function Node:area_get_overlapping_nodes() end

-- ----------------------------------------------------------------------------
-- RaycastNode Methods
-- ----------------------------------------------------------------------------

---Executes the raycast immediately against the physics world.
function Node:raycast_cast() end

---Checks whether the raycast is currently intersecting a physics obstacle.
---@return boolean
function Node:raycast_is_colliding() end

---Gets the world-space intersection point of the raycast hit.
---@return number x
---@return number y
function Node:raycast_get_hit_point() end

---Gets the world-space surface normal at the raycast intersection.
---@return number nx
---@return number ny
function Node:raycast_get_hit_normal() end

---Gets the fraction from 0.0 to 1.0 along the ray length where the hit occurred.
---@return number fraction
function Node:raycast_get_hit_fraction() end

---Gets the Node struck by the raycast, or nil if none.
---@return Node?
function Node:raycast_get_hit_node() end

---Sets the local direction vector for the raycast node.
---@param dx number
---@param dy number
function Node:raycast_set_direction(dx, dy) end

---Sets the maximum reach length in pixels for the raycast node.
---@param length number
function Node:raycast_set_length(length) end

-- ----------------------------------------------------------------------------
-- ParticleEmitterNode Methods
-- ----------------------------------------------------------------------------

---Starts continuous or burst particle emission.
function Node:particle_start() end

---Stops particle emission.
function Node:particle_stop() end

---Checks if particles are actively being emitted.
---@return boolean
function Node:particle_is_emitting() end

---Sets the maximum particle pool count for this emitter.
---@param amount integer
function Node:particle_set_amount(amount) end

---Sets the base lifetime in seconds for newly spawned particles.
---@param lifetime number
function Node:particle_set_lifetime(lifetime) end

-- ----------------------------------------------------------------------------
-- TextureNode Methods
-- ----------------------------------------------------------------------------

---Gets the base unscaled pixel width and height of the texture.
---@return number width
---@return number height
function Node:texture_get_size() end

---Sets the local pivot origin for texture rotation and scaling.
---@param ox number Origin X in pixels
---@param oy number Origin Y in pixels
function Node:texture_set_origin(ox, oy) end

---Gets the file path string from which this texture was loaded.
---@return string
function Node:texture_get_path() end

-- ----------------------------------------------------------------------------
-- AnimationPlayerNode Methods
-- ----------------------------------------------------------------------------

---Plays an animation, optionally switching to the specified animation name first.
---With `blend` > 0 the previous pose crossfades into the new animation over that many seconds.
---Event tracks fire while playing: method tracks call `self:<method>(frame)` on the
---track's target node script; sound tracks play their audio file on the key's frame.
---@param name? string Animation name
---@param blend? number Crossfade time in seconds (default 0)
function Node:animation_play(name, blend) end

---Stops animation playback and freezes at current frame.
function Node:animation_stop() end

---Pauses animation playback.
function Node:animation_pause() end

---Resumes animation playback from the current frame.
function Node:animation_resume() end

---Resets the animation to the first frame.
function Node:animation_reset() end

---Sets playback speed in frames per second.
---@param fps number
function Node:animation_set_fps(fps) end

---Gets the name of the currently active animation track.
---@return string
function Node:animation_get_current() end

-- ----------------------------------------------------------------------------
-- TimerNode Methods
-- ----------------------------------------------------------------------------

---Starts or restarts the timer from zero.
function Node:timer_start() end

---Stops the timer.
function Node:timer_stop() end

---Checks if the timer is actively running.
---@return boolean
function Node:timer_is_running() end

---Gets the elapsed time in seconds since start.
---@return number
function Node:timer_get_elapsed() end

---Sets the timer expiration duration in seconds.
---@param durationSec number
function Node:timer_set_duration(durationSec) end

---Sets whether the timer automatically restarts upon expiring.
---@param loop boolean
function Node:timer_set_loop(loop) end

-- ----------------------------------------------------------------------------
-- SoundNode & MusicNode Methods
-- ----------------------------------------------------------------------------

---Plays the sound effect associated with this SoundNode.
function Node:sound_play() end

---Stops playing the sound effect.
function Node:sound_stop() end

---Pauses the sound effect.
function Node:sound_pause() end

---Resumes the paused sound effect.
function Node:sound_resume() end

---Plays or resumes the background music on this MusicNode.
function Node:music_play() end

---Stops background music on this MusicNode.
function Node:music_stop() end

---Pauses background music on this MusicNode.
function Node:music_pause() end

---Resumes paused background music on this MusicNode.
function Node:music_resume() end

---Fades this MusicNode's volume to `volume` (0..1) over `seconds`, starting
---it if it isn't playing.
---@param volume number
---@param seconds number
---@param stop_at_end? boolean Stop when the fade reaches 0
function Node:music_fade(volume, seconds, stop_at_end) end

-- ----------------------------------------------------------------------------
-- CameraNode (Node-invoked) Methods
-- ----------------------------------------------------------------------------

---Sets the zoom level on this CameraNode.
---@param zoom number
function Node:camera_set_zoom(zoom) end

---Gets the configured zoom level on this CameraNode.
---@return number
function Node:camera_get_zoom() end

---Sets the target Node to follow.
---@param target Node?
function Node:camera_set_target(target) end

---Adds a node to the group this camera frames (see Camera.add_target).
---@param target Node
---@param options? CameraTargetOptions
function Node:camera_add_target(target, options) end

---Takes a node out of this camera's group.
---@param target Node
function Node:camera_remove_target(target) end

---Stops this camera following anything.
function Node:camera_clear_targets() end

---The node this camera follows (single target), or nil.
---@return Node?
function Node:camera_get_target() end

---Every node this camera follows.
---@return Node[]
function Node:camera_get_targets() end

---Sets the fixed world position for the camera target.
---@param x number
---@param y number
function Node:camera_set_target_position(x, y) end

---Triggers trauma screen shake on this CameraNode.
---@param strength number Shake intensity (0.0 to 1.0)
---@param duration? number Duration in seconds (default 0.5)
function Node:camera_shake(strength, duration) end

---Immediately cancels any active screen shake.
function Node:camera_stop_shake() end

---Checks if screen shake is currently active.
---@return boolean
function Node:camera_is_shaking() end

---Constrains camera movement within bounding rectangle limits.
---@param left number
---@param right number
---@param top number
---@param bottom number
function Node:camera_set_limits(left, right, top, bottom) end

---Clears all bounding rectangle limits.
function Node:camera_clear_limits() end

-- ----------------------------------------------------------------------------
-- LDtk Node Methods (on an LdtkLevelNode; see engine/LDTK.md)
-- ----------------------------------------------------------------------------

---@class LdtkColor
---@field r integer
---@field g integer
---@field b integer
---@field a integer

---@class LdtkTileRect
---@field tileset_uid integer
---@field x number
---@field y number
---@field w number
---@field h number

---@class LdtkEntityRef
---@field field string EntityRef field name
---@field iid string Referenced entity iid
---@field index integer Element of an array field (0 = single field)
---@field level? string Level holding the target

---@class LdtkEntity
---@field identifier string Entity definition identifier (e.g. "Turret")
---@field iid string Unique instance id (EntityRef fields point to it)
---@field x number X in level pixels (pivot point)
---@field y number Y in level pixels (pivot point)
---@field world_x number X in world coordinates
---@field world_y number Y in world coordinates
---@field cx integer Grid cell X
---@field cy integer Grid cell Y
---@field width number
---@field height number
---@field pivot_x number
---@field pivot_y number
---@field level string Level identifier
---@field color LdtkColor Smart colour
---@field tile? LdtkTileRect The entity's LDtk tile
---@field tags string[]
---@field fields table<string, any> Field values (arrays as Lua arrays; Point = {cx, cy}; Enum = value id; EntityRef = iid; Tile = LdtkTileRect)
---@field enums table<string, string> Enum fields: field name -> enum name
---@field refs LdtkEntityRef[] EntityRef values of its fields
---@field node? Node The spawned node (while the level is built)

---@class LdtkLevel
---@field identifier string
---@field iid string
---@field uid integer
---@field world string World identifier
---@field world_x integer
---@field world_y integer
---@field depth integer World depth
---@field width integer Pixels
---@field height integer Pixels
---@field x number Level origin in world coordinates
---@field y number
---@field bg_color LdtkColor
---@field fields table<string, any> Level fields
---@field layers string[] Layer identifiers (top first)
---@field neighbours LdtkNeighbour[]

---@class LdtkNeighbour
---@field level string Level identifier
---@field iid string
---@field dir string n s e w nw ne sw se < > o

---@class LdtkWorld
---@field identifier string
---@field iid string
---@field layout string Free, GridVania, LinearHorizontal, LinearVertical
---@field grid_width integer
---@field grid_height integer
---@field levels string[]

---@class LdtkLayer
---@field identifier string
---@field type string IntGrid, Entities, Tiles, AutoLayer
---@field grid_size integer
---@field width integer Cells
---@field height integer Cells
---@field visible boolean
---@field opacity number
---@field parallax_x number
---@field parallax_y number
---@field parallax_scaling boolean
---@field offset_x number
---@field offset_y number
---@field entities integer
---@field tiles integer

---@class LdtkIntGridValue
---@field value integer
---@field identifier string
---@field color LdtkColor
---@field collision string none, solid, one_way, trigger

---@class LdtkTile
---@field id integer Tile id in its tileset
---@field tileset_uid integer
---@field flip_x boolean
---@field flip_y boolean
---@field custom_data string Tileset custom data of the tile
---@field enums string[] Enum values tagging the tile

---@class LdtkEnumValue
---@field id string
---@field index integer
---@field color LdtkColor
---@field tile? LdtkTileRect

---@class LdtkEntityDef
---@field identifier string
---@field width number
---@field height number
---@field color LdtkColor
---@field tags string[]
---@field fields {identifier: string, type: string, enum?: string}[]

---@class LdtkLink
---@field source Node
---@field target? Node
---@field field string
---@field source_iid string
---@field target_iid string
---@field index integer

---Gets the current level identifier.
---@return string
function Node:ldtk_get_level_identifier() end

---Lists level identifiers (every level, or one world's).
---@param world? string
---@return string[]
function Node:ldtk_get_levels(world) end

---Switches to another level (identifier or iid); colliders and entities are rebuilt.
---@param identifier LdtkLevel|string
---@return boolean ok
function Node:ldtk_load_level(identifier) end

---Gets a level's details (the current level by default).
---@param level? string
---@return LdtkLevel?
function Node:ldtk_get_level(level) end

---Gets the current level size in pixels.
---@return number width
---@return number height
function Node:ldtk_get_level_size() end

---Gets a level field value (nil if absent or null).
---@param name string
---@param level? string Another level (default: the current one)
---@return any
function Node:ldtk_get_level_field(name, level) end

---Gets every field of a level.
---@param level? string
---@return table<string, any>
function Node:ldtk_get_level_fields(level) end

---Lists a level's neighbours.
---@param level? string
---@return LdtkNeighbour[]
function Node:ldtk_get_neighbours(level) end

---The level at a world position (world mode: any loaded level; otherwise looked up in the world layout).
---@param x number
---@param y number
---@return string?
function Node:ldtk_level_at(x, y) end

---Lists the project's worlds.
---@return LdtkWorld[]
function Node:ldtk_get_worlds() end

---Gets the current world identifier.
---@return string
function Node:ldtk_get_world() end

---Switches world (its first level, or `level`).
---@param world string
---@param level? string
---@return boolean ok
function Node:ldtk_set_world(world, level) end

---World mode: every level of the world at its world position (rebuilds).
---@param on boolean
function Node:ldtk_set_world_mode(on) end

---@return boolean
function Node:ldtk_is_world_mode() end

---Lists a level's layers (top first).
---@param level? string
---@return LdtkLayer[]
function Node:ldtk_get_layers(level) end

---Shows or hides a layer (in every loaded level).
---@param name LdtkLayer|string
---@param visible boolean
function Node:ldtk_set_layer_visible(name, visible) end

---@param name LdtkLayer|string
---@return boolean
function Node:ldtk_is_layer_visible(name) end

---Gets the IntGrid value at a world position (0 = empty).
---@param layer string IntGrid layer identifier, e.g. "Collisions"
---@param x number World X
---@param y number World Y
---@return integer
function Node:ldtk_get_int_grid(layer, x, y) end

---Gets the identifier of the IntGrid value at a world position ("" if none / unnamed).
---@param layer string
---@param x number
---@param y number
---@return string
function Node:ldtk_get_int_grid_name(layer, x, y) end

---Gets the IntGrid value of a cell.
---@param layer string
---@param cx integer
---@param cy integer
---@param level? string
---@return integer
function Node:ldtk_get_int_grid_cell(layer, cx, cy, level) end

---Lists an IntGrid layer's values (name, colour, collision).
---@param layer string
---@return LdtkIntGridValue[]
function Node:ldtk_get_int_grid_values(layer) end

---World position -> layer cell.
---@param layer string
---@param x number
---@param y number
---@return integer cx
---@return integer cy
function Node:ldtk_world_to_cell(layer, x, y) end

---Layer cell -> world position of its centre.
---@param layer string
---@param cx integer
---@param cy integer
---@param level? string
---@return number x
---@return number y
function Node:ldtk_cell_to_world(layer, cx, cy, level) end

---Collision at a world position: "solid", "one_way", "trigger" or "none", plus the layer and value name.
---@param x number
---@param y number
---@return string type
---@return string? layer
---@return string|integer|nil value
function Node:ldtk_get_collision(x, y) end

---The trigger areas built from IntGrid values set to Trigger ("<Layer>_<value>" -> AreaNode).
---Connect to their "body_entered" / "body_exited" events.
---@return table<string, Node>
function Node:ldtk_get_triggers() end

---Gets the tile of a Tiles/AutoLayer layer at a world position.
---@param layer string
---@param x number
---@param y number
---@return LdtkTile?
function Node:ldtk_get_tile(layer, x, y) end

---Gets the enum values tagging the tile at a world position (tileset enum tags).
---@param layer string
---@param x number
---@param y number
---@return string[]
function Node:ldtk_get_tile_enums(layer, x, y) end

---Gets an enum's values (colour, tile, index).
---@param name LdtkEnumName
---@return LdtkEnumValue[]?
function Node:ldtk_get_enum(name) end

---Every enum: name -> value ids.
---@return table<string, string[]>
function Node:ldtk_get_enums() end

---Lists the loaded levels' entities, optionally only those with an identifier.
---@param identifier? LdtkEntity
---@return LdtkEntity[]
function Node:ldtk_get_entities(identifier) end

---Lists the loaded levels' entities with a tag.
---@param tag string
---@return LdtkEntity[]
function Node:ldtk_get_entities_by_tag(tag) end

---Gets an entity anywhere in the project by iid.
---@param iid string
---@return LdtkEntity?
function Node:ldtk_get_entity(iid) end

---Gets the node spawned for an entity (by iid).
---@param iid string
---@return Node?
function Node:ldtk_get_entity_node(iid) end

---Lists the project's entity definitions.
---@return LdtkEntityDef[]
function Node:ldtk_get_entity_defs() end

---Lists the resolved EntityRef links between spawned entities.
---@return LdtkLink[]
function Node:ldtk_get_links() end

-- On any node spawned from an LDtk entity:

---The LDtk entity this node was spawned from (nil otherwise).
---@return LdtkEntity?
function Node:ldtk_entity() end

---The LdtkLevelNode that spawned this node.
---@return Node?
function Node:ldtk_level_node() end

---A field of this node's entity.
---@param name string
---@return any
function Node:ldtk_field(name) end

---The node an EntityRef field points to (the first one for arrays).
---@param field string
---@return Node?
function Node:ldtk_ref(field) end

---Nodes referenced by a field, or every reference ({field, iid, node}) without one.
---@param field? string
---@return Node[]|{field: string, iid: string, node: Node?}[]
function Node:ldtk_refs(field) end

---Entities whose EntityRef fields point at this one.
---@param field? string
---@return {node: Node, field: string}[]
function Node:ldtk_referenced_by(field) end


-- ============================================================================
-- Global Modules

---@alias EaseName "linear"|"constant"|"in_sine"|"out_sine"|"in_out_sine"|"in_quad"|"out_quad"|"in_out_quad"|"in_cubic"|"out_cubic"|"in_out_cubic"|"in_quart"|"out_quart"|"in_out_quart"|"in_expo"|"out_expo"|"in_out_expo"|"in_back"|"out_back"|"in_out_back"|"in_elastic"|"out_elastic"|"in_out_elastic"|"in_bounce"|"out_bounce"|"in_out_bounce"

---@class TweenOptions
---@field delay? number Seconds before it starts (it starts from the value at that time)
---@field loops? integer Extra runs (-1 = forever)
---@field yoyo? boolean Every other run goes back
---@field on_complete? fun(node: Node) Called when it finishes

---@class TweenModule
---Animates node properties over time with easing.
local TweenModule = {}

---Tweens a property to a value: "position", "scale", "rotation", any numeric
---or colour property ("tint", "emitter.amount", ...; colours as {r, g, b[, a]} 0..1),
---or a material parameter ("shader:amount"). Returns the tween's id.
---@param node Node
---@param property string
---@param value number|number[]
---@param duration number Seconds
---@param ease? EaseName Default "out_quad"
---@param options? TweenOptions
---@return integer id
function TweenModule.to(node, property, value, duration, ease, options) end

---Stops a tween (it stays where it is).
---@param id integer
---@return boolean found
function TweenModule.cancel(id) end

---Stops a node's tweens (all, or one property's).
---@param node Node
---@param property? string
---@return integer count
function TweenModule.cancel_all(node, property) end

---@param id integer
---@return boolean
function TweenModule.is_running(id) end

---Maps progress 0..1 through an easing curve (for your own animation).
---@param ease EaseName
---@param t number
---@return number
function TweenModule.ease(ease, t) end

-- ============================================================================

---@alias SaveValue nil|boolean|number|string|table

---@class SaveModule
---Persistent save data: plain values (booleans, numbers, strings, tables of
---those) stored as JSON in the player's user-data folder
---(macOS ~/Library/Application Support/<game>, Windows %APPDATA%\<game>,
---Linux ~/.local/share/<game>). Read on first use; written by Save.flush()
---and when the game quits.
local SaveModule = {}

---Stores a value (nil removes the key). Tables are stored by reference:
---changes to a table you got from Save.get are saved too.
---@param key string
---@param value SaveValue
function SaveModule.set(key, value) end

---@param key string
---@param default? SaveValue Returned when the key isn't set
---@return SaveValue
function SaveModule.get(key, default) end

---@param key string
---@return boolean
function SaveModule.has(key) end

---@param key string
function SaveModule.delete(key) end

---@return string[] keys Sorted
function SaveModule.keys() end

---Removes every key (the file is rewritten on the next flush).
function SaveModule.clear() end

---Writes the save file now.
---@return boolean ok
function SaveModule.flush() end

---Switches to another save file (<name>.json; default "save"), writing the
---current one first. Returns the current slot.
---@param name? string
---@return string slot
function SaveModule.slot(name) end

---@return string path The current save file
function SaveModule.path() end

-- ============================================================================

---@class EngineModule
---Core engine statistics, frame timing, and display information.
local EngineModule = {}

---Gets current display refresh frames per second.
---@return integer
function EngineModule.get_fps() end

---Gets the last frame duration in seconds.
---@return number
function EngineModule.get_delta_time() end

---Gets running time in seconds since the engine launched.
---@return number
function EngineModule.get_time() end

---Gets current physical window width and height in screen pixels.
---@return integer width
---@return integer height
function EngineModule.get_window_size() end

---Gets virtual canvas reference resolution (e.g. 1280x720).
---@return number width
---@return number height
function EngineModule.get_virtual_size() end

---Pauses the game: nodes with pause mode "pausable" (the default) stop
---updating and physics stops; "always" nodes keep running (pause menus).
---@param paused boolean
function EngineModule.set_paused(paused) end

---@return boolean
function EngineModule.is_paused() end


---@class InputModule
---Engine input subsystem for keyboard, mouse, and mapped action queries.
---Actions are named in Settings > Project > Input (project.json "input"):
---built-in names (move_up, move_down, move_left, move_right, jump, fire,
---secondary, boost, interact, pause, confirm, cancel, custom1..4) plus any
---the project adds, each bound to keys, mouse buttons or gamepad input.
local InputModule = {}

---Checks if an action was pressed this frame (just triggered).
---@param action InputAction Action name from the project's Input settings (e.g. "move_up", "fire", "jump", "dash")
---@return boolean
function InputModule.is_action_pressed(action) end

---Checks if an action is currently held down.
---@param action InputAction
---@return boolean
function InputModule.is_action_down(action) end

---Checks if an action was released this frame.
---@param action InputAction
---@return boolean
function InputModule.is_action_released(action) end

---Calculates a 1D axis value between -1.0 and 1.0 from negative and positive action names.
---@param neg_action InputAction Action name representing negative direction (e.g. "move_left")
---@param pos_action InputAction Action name representing positive direction (e.g. "move_right")
---@return number axis Value from -1.0 to 1.0
function InputModule.get_axis(neg_action, pos_action) end

---Calculates a normalized 2D direction vector from 4 directional action inputs.
---@param left? InputAction
---@param right? InputAction
---@param up? InputAction
---@param down? InputAction
---@return number x Normalized X axis
---@return number y Normalized Y axis
function InputModule.get_vector(left, right, up, down) end

---Queries raw keyboard key press state for a single frame.
---@param key string Key name like "SPACE", "W", "A", "S", "D", "ENTER", "ESCAPE"
---@return boolean
function InputModule.is_key_pressed(key) end

---Queries raw keyboard key held state.
---@param key string Key name
---@return boolean
function InputModule.is_key_down(key) end

---Queries raw keyboard key release state for a single frame.
---@param key string Key name
---@return boolean
function InputModule.is_key_released(key) end

---Queries mouse button pressed state for a single frame.
---@param button string "LEFT", "RIGHT", "MIDDLE", "SIDE", "EXTRA"
---@return boolean
function InputModule.is_mouse_button_pressed(button) end

---Queries mouse button held state.
---@param button string "LEFT", "RIGHT", "MIDDLE"
---@return boolean
function InputModule.is_mouse_button_down(button) end

---Queries mouse button release state for a single frame.
---@param button string "LEFT", "RIGHT", "MIDDLE"
---@return boolean
function InputModule.is_mouse_button_released(button) end

---Gets the current mouse cursor position in screen pixels.
---@return number x Mouse X
---@return number y Mouse Y
function InputModule.get_mouse_position() end

---Gets mouse wheel scroll delta for this frame.
---@return number
function InputModule.get_mouse_wheel_move() end


---@class AudioModule
---Engine audio playback and volume control.
local AudioModule = {}

---Plays a sound effect from the given file path. Calls in quick succession
---overlap (up to 4 voices per sound) instead of restarting it.
---@param path AudioPath|string File path, e.g. "assets/audio/laser.wav"
---@param volume? number 0..1 (default 1), times the sfx bus
---@param pitch? number Default 1
function AudioModule.play_sound(path, volume, pitch) end

---Plays a one-shot heard from a world position: quieter with distance from
---the listener (the camera, or Audio.set_listener) and panned to its side.
---@param path AudioPath|string
---@param x number
---@param y number
---@param volume? number
function AudioModule.play_sound_at(path, x, y, volume) end

---@alias AudioBus "master"|"music"|"sfx"

---Sets a bus volume (0..1) and applies it to what's playing.
---@param bus AudioBus
---@param volume number
function AudioModule.set_bus_volume(bus, volume) end

---@param bus AudioBus
---@return number volume
function AudioModule.get_bus_volume(bus) end

---A low-pass filter on the whole mix (e.g. underwater, a pause menu).
---@param hz number Cutoff in Hz; 0 turns it off
function AudioModule.set_lowpass(hz) end

---Reverb on the whole mix.
---@param mix number 0..1 (0 turns it off)
---@param size? number Room size 0..1 (default 0.5)
function AudioModule.set_reverb(mix, size) end

---Where positional sounds are heard from (nil: the current camera).
---@param node Node?
function AudioModule.set_listener(node) end

---Fades one MusicNode out (stopping it) while another fades in.
---@param from Node? MusicNode playing now
---@param to Node MusicNode to fade in (started if needed)
---@param seconds number
function AudioModule.crossfade(from, to, seconds) end

---Streams a music track from the given file path.
---@param path AudioPath|string File path, e.g. "assets/audio/theme.ogg"
---@param loop? boolean Whether to loop playback (default true)
function AudioModule.play_music(path, loop) end

---Stops playing the specified music stream.
---@param path AudioPath|string
function AudioModule.stop_music(path) end

---Pauses playback of the specified music stream.
---@param path AudioPath|string
function AudioModule.pause_music(path) end

---Resumes playback of the specified paused music stream.
---@param path AudioPath|string
function AudioModule.resume_music(path) end

---Checks if the specified music stream is currently playing.
---@param path AudioPath|string
---@return boolean
function AudioModule.is_music_playing(path) end

---Sets volume for a specific music stream.
---@param path AudioPath|string
---@param volume number Volume between 0.0 and 1.0
function AudioModule.set_music_volume(path, volume) end

---Sets the global master audio volume.
---@param volume number Volume between 0.0 (silent) and 1.0 (full)
function AudioModule.set_master_volume(volume) end


---@class CameraModule
---Global camera control operating on the active scene's primary CameraNode.
local CameraModule = {}

---Gets current target world position of the camera.
---@return number x
---@return number y
function CameraModule.get_target_position() end

---Sets target world position for the camera.
---@param x number
---@param y number
function CameraModule.set_target_position(x, y) end

---Sets a node for the camera to smoothly follow (nil stops following).
---A follow target picked in the Inspector is set automatically when the scene loads.
---@param target Node?
function CameraModule.set_target(target) end

---@class CameraTargetOptions
---@field weight? number Pull of this target on the framing (default 1)
---@field weight_x? number Horizontal pull (default: weight)
---@field weight_y? number Vertical pull (default: weight)
---@field radius? number Space kept around it when auto-zooming (default 50)
---@field offset_x? number
---@field offset_y? number
---@field priority? integer

---Adds a node to the group the camera frames: it centres on their weighted
---average and, with Auto Zoom on, zooms to keep them all in view. A single
---follow target joins the group first. Adding a node again updates its options.
---@param target Node
---@param options? CameraTargetOptions
function CameraModule.add_target(target, options) end

---Takes a node out of the group.
---@param target Node
function CameraModule.remove_target(target) end

---Stops following: clears the group and the follow target.
function CameraModule.clear_targets() end

---The node the camera follows (single target), or nil.
---@return Node?
function CameraModule.get_target() end

---Every node the camera follows (the group, or the single target).
---@return Node[]
function CameraModule.get_targets() end

---Gets configured target zoom level.
---@return number
function CameraModule.get_zoom() end

---Sets camera target zoom.
---@param zoom number
function CameraModule.set_zoom(zoom) end

---Gets screen offset vector.
---@return number ox
---@return number oy
function CameraModule.get_offset() end

---Sets screen offset vector.
---@param ox number
---@param oy number
function CameraModule.set_offset(ox, oy) end

---Gets camera rotation in degrees.
---@return number
function CameraModule.get_rotation() end

---Sets camera rotation in degrees.
---@param degrees number
function CameraModule.set_rotation(degrees) end

---Triggers screen shake trauma.
---@param strength number Shake intensity (0.0 to 1.0)
---@param duration? number Duration in seconds
function CameraModule.shake(strength, duration) end

---Immediately stops active screen shake.
function CameraModule.stop_shake() end

---Checks if screen shake is active.
---@return boolean
function CameraModule.is_shaking() end

---Constrains camera movement within bounding rectangle limits.
---@param left number
---@param right number
---@param top number
---@param bottom number
function CameraModule.set_limits(left, right, top, bottom) end

---Clears all bounding rectangle limits.
function CameraModule.clear_limits() end

---Transforms screen coordinates to world coordinates.
---@param sx number Screen X
---@param sy number Screen Y
---@return number wx World X
---@return number wy World Y
function CameraModule.screen_to_world(sx, sy) end

---Transforms world coordinates to screen pixel coordinates.
---@param wx number World X
---@param wy number World Y
---@return number sx Screen X
---@return number sy Screen Y
function CameraModule.world_to_screen(wx, wy) end

---Gets visible world bounds rectangle currently seen by camera.
---@return number x
---@return number y
---@return number width
---@return number height
function CameraModule.get_visible_world_bounds() end


---@class PhysicsModule
---Global physics world queries, gravity, and simulation control.
local PhysicsModule = {}

---Gets world gravity vector in pixels per second squared.
---@return number gx
---@return number gy
function PhysicsModule.get_gravity() end

---Sets world gravity vector.
---@param gx number
---@param gy number
function PhysicsModule.set_gravity(gx, gy) end

---Checks if physics simulation is paused.
---@return boolean
function PhysicsModule.is_paused() end

---Pauses or unpauses physics simulation.
---@param paused boolean
function PhysicsModule.set_paused(paused) end

---Casts a ray between start and end world points against non-sensor colliders.
---@param startX number
---@param startY number
---@param endX number
---@param endY number
---@return RaycastHit? hit Raycast hit details or nil if no obstacle was struck
function PhysicsModule.raycast(startX, startY, endX, endY) end

---The project's name for collision layer n (Project Settings > Physics), or "".
---@param n integer 1-16
---@return string name
function PhysicsModule.layer_name(n) end


---@class SceneModule
---Active scene queries, node discovery, switching, and dynamic instantiation.
local SceneModule = {}

---Finds any node in the active scene hierarchy by name.
---@param name NodeName|string Name of node to find
---@return Node? node Found node or nil
function SceneModule.find_node(name) end

---Every node in the active scene with a tag, in tree order.
---@param tag NodeTag|string
---@return Node[]
function SceneModule.find_by_tag(tag) end

---Sets the scene's ambient light (0..1): the colour where no light reaches.
---White = an unlit scene. With LightNodes, the scene is lit by them on top.
---@param r number
---@param g number
---@param b number
---@param a? number
function SceneModule.set_ambient(r, g, b, a) end

---Gets the scene's ambient light (0..1).
---@return number r
---@return number g
---@return number b
---@return number a
function SceneModule.get_ambient() end

---Gets the name of the currently active scene.
---@return string
function SceneModule.get_name() end

---@alias TransitionKind "fade"|"wipe_left"|"wipe_right"|"wipe_up"|"wipe_down"|"circle"

---@class SceneTransition
---@field transition? TransitionKind Default "fade"
---@field duration? number Seconds for each half (cover, uncover); default 0.4
---@field color? number[] {r, g, b} 0..1; default black

---Switches to another scene by name - at once, or behind a transition (the
---screen is covered, the scene switches once its assets are loaded, then
---it's uncovered).
---@param name SceneName Name of registered scene
---@param transition? SceneTransition
function SceneModule.change_scene(name, transition) end

---Starts loading a scene's assets in the background (a little each frame),
---so switching to it later is quick.
---@param name SceneName
function SceneModule.preload(name) end

---@param name SceneName
---@return number progress 0..1
function SceneModule.preload_progress(name) end

---@return boolean
function SceneModule.is_transitioning() end

---Reloads the currently active scene.
function SceneModule.reload() end

---Returns an array of all active nodes in the current scene.
---@return Node[]
function SceneModule.get_nodes() end

---Dynamically instantiates a new scene node and adds it to the active scene graph.
---@param nodeType string "Node", "TextureNode", "ScriptNode", "CameraNode", "ParticleEmitterNode", "TimerNode", "DynamicBodyNode", "StaticBodyNode", "AreaNode", "RaycastNode", "CharacterMoverNode"
---@param name? string Optional node name
---@param parent? Node Optional parent node (defaults to scene root)
---@return Node? node Newly spawned node
function SceneModule.create_node(nodeType, name, parent) end

---Checks if debug collider and bounds rendering is enabled on this scene.
---@return boolean
function SceneModule.get_draw_bounds() end

---Enables or disables debug bounds rendering on the scene.
---@param draw boolean
function SceneModule.set_draw_bounds(draw) end


---@class LogModule
---Engine logging subsystem routed to Odin's logging channels.
local LogModule = {}

---Logs an informational message.
---@param ... any
function LogModule.info(...) end

---Logs a warning message.
---@param ... any
function LogModule.warn(...) end

---Logs an error message.
---@param ... any
function LogModule.error(...) end


-- Global Instances available in every script
---@type EngineModule
Engine = EngineModule

---@type InputModule
Input = InputModule

---@type AudioModule
Audio = AudioModule

---@type CameraModule
Camera = CameraModule

---@type PhysicsModule
Physics = PhysicsModule

---@type SceneModule
Scene = SceneModule
Tween = TweenModule

---@type SaveModule
Save = SaveModule

---@class NavigationModule
local NavigationModule = {}

---Same as map:nav_find_path(x1, y1, x2, y2, opts).
---@param map Node TileMapNode or LdtkLevelNode
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param opts? NavOptions
---@return number[][]? path
function NavigationModule.find_path(map, x1, y1, x2, y2, opts) end

---@type NavigationModule
Navigation = NavigationModule

---The text for a key in the current language (locale/*.csv), with {name}
---placeholders filled from `args`; falls back to another language, then the key.
---@param key string
---@param args? table<string, any>
---@return string
function tr(key, args) end

---@class LocaleModule
local LocaleModule = {}

---Switches the language texts are shown in (a column of the locale tables).
---@param language string e.g. "fr"
function LocaleModule.set(language) end

---@return string language
function LocaleModule.get() end

---@return string[] languages The languages the tables have
function LocaleModule.languages() end

---@type LocaleModule
Locale = LocaleModule

---@type LogModule
Log = LogModule


---@class ProjectModule
---Engine project management, data-driven scene serialization, and .ore package access.
local ProjectModule = {}

---Loads a complete project either from a directory containing project.json or from an .ore package archive.
---@param pathOrDir string Path to directory or .ore file
---@return boolean success
function ProjectModule.load(pathOrDir) end

---Packages a loose project directory into a portable .ore container archive with zlib compression.
---@param projectDir string Source directory path
---@param outOrePath string Target output .ore file path
---@return boolean success
function ProjectModule.export_ore(projectDir, outOrePath) end

---Serializes the currently active scene graph and node states to a JSON formatted string.
---@return string json
function ProjectModule.serialize_scene() end

---Reads a text file either from the mounted .ore archive package or the loose project directory.
---@param relPath string Project-relative file path
---@return string? content File contents as a string, or nil if not found
function ProjectModule.read_file(relPath) end

---Checks if a file exists in the active project (.ore archive or disk).
---@param relPath string Project-relative file path
---@return boolean exists
function ProjectModule.has_file(relPath) end

---@type ProjectModule
Project = ProjectModule

---@class ScriptInstanceBase
---@field node Node The node this script is attached to.
---@field properties table<string, any> Custom exported script properties table.
---@field ready? fun(self: self) Lifecycle callback invoked when the node enters the scene.
---@field update? fun(self: self, dt: number) Lifecycle callback invoked each frame with delta time in seconds.
---@field on_destroy? fun(self: self) Lifecycle callback invoked when the node is destroyed.
---@field on_entered_tree? fun(self: self) Event: the node joined the scene.
---@field on_exited_tree? fun(self: self) Event: the node is being removed.
---@field on_child_added? fun(self: self, child: Node) Event: a child was added.
---@field on_child_removed? fun(self: self, child: Node) Event: a child was removed.
---@field on_timeout? fun(self: self) Event (TimerNode): the duration elapsed.
---@field on_tick? fun(self: self, elapsed: number) Event (TimerNode): each frame while running.
---@field on_body_entered? fun(self: self, other: Node) Event (AreaNode): a body entered.
---@field on_body_exited? fun(self: self, other: Node?) Event (AreaNode): a body left.
---@field on_collision_started? fun(self: self, other: Node) Event (bodies): contact began.
---@field on_collision_ended? fun(self: self, other: Node) Event (bodies): contact ended.
---@field on_hit_started? fun(self: self, other: Node) Event (RaycastNode): the ray hit a node.
---@field on_hit_ended? fun(self: self, other: Node) Event (RaycastNode): the ray stopped hitting it.
---@field on_animation_finished? fun(self: self, name: string?) Event: a non-looping animation ended.
---@field on_state_changed? fun(self: self, state: string) Event (StateMachineNode): entered a state.
---@field on_finished? fun(self: self) Event (Sound/Music): playback ended.
---@field on_clicked? fun(self: self) Event (UIButtonNode): clicked.
---@field on_value_changed? fun(self: self, value: any) Event (UI inputs): the value changed.
---@field on_submitted? fun(self: self, text: string) Event (UITextInputNode): Enter pressed.
---@field on_selected? fun(self: self, index: integer) Event (UI lists): selection changed.
