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
---@field name string The node's name (assigning renames it). Properties read and write as fields: `node.rotation = node.rotation + 5`.
---Represents an engine scene hierarchy node with transform, lifecycle, and optional physics.
local Node = {}

-- --- Node types: each has the Node methods plus its own --------------------------

---Nodes that show text (TextNode, UILabelNode, UIButtonNode).
---@class TextHolder
local TextHolder = {}

---Nodes with a walkable grid (TileMapNode, LdtkLevelNode).
---@class NavGrid
local NavGrid = {}

---The camera the scene is seen through (follow, zoom, shake, limits).
---@class CameraNode : Node
local CameraNode = {}

---Counts down and raises "timeout".
---@class TimerNode : Node
local TimerNode = {}

---@class ScriptNode : Node

---A sprite: draws an image.
---@class TextureNode : Node
local TextureNode = {}

---@class FrameAnimationNode : Node

---Plays frame / sprite-sheet animations with property tracks.
---@class AnimationPlayerNode : Node
local AnimationPlayerNode = {}

---A finite state machine.
---@class StateMachineNode : Node
local StateMachineNode = {}

---A particle effect.
---@class ParticleEmitterNode : Node
local ParticleEmitterNode = {}

---A sound effect.
---@class SoundNode : Node
local SoundNode = {}

---Streamed music.
---@class MusicNode : Node
local MusicNode = {}

---@class StaticBodyNode : Node

---A physics body moved by forces and collisions.
---@class DynamicBodyNode : Node
local DynamicBodyNode = {}

---A character controller (move and slide, floors, walls).
---@class CharacterMoverNode : Node
local CharacterMoverNode = {}

---A sensor: reports bodies that overlap it.
---@class AreaNode : Node
local AreaNode = {}

---A ray that reports what it hits.
---@class RaycastNode : Node
local RaycastNode = {}

---An LDtk level (layers, entities, IntGrid).
---@class LdtkLevelNode : Node, NavGrid
local LdtkLevelNode = {}

---A painted tile map.
---@class TileMapNode : Node, NavGrid

---A 2D point or spot light.
---@class LightNode : Node
local LightNode = {}

---@class JointNode : Node

---Text in the world (fonts, rich text, typewriter).
---@class TextNode : Node, TextHolder
local TextNode = {}

---A dialogue box that types out lines.
---@class DialogueNode : Node
local DialogueNode = {}

---@class NineSliceNode : Node

---@class ParallaxNode : Node

---A polyline.
---@class LineNode : Node
local LineNode = {}

---A fading ribbon behind a moving node.
---@class TrailNode : Node
local TrailNode = {}

---@class PostEffectNode : Node

---@class UIContainerNode : Node

---@class UILabelNode : Node, TextHolder

---@class UIButtonNode : Node, TextHolder

---@class UISliderNode : Node

---@class UICheckboxNode : Node

---@class UIProgressBarNode : Node

---@class UITextInputNode : Node

---@class UIDropdownNode : Node

---@class UIRadioGroupNode : Node

---@class UIToggleSwitchNode : Node

---@class UIKnobNode : Node

---@class UINotchedSliderNode : Node

---@class UIVolumeFaderNode : Node

---@class UIVolumeMeterNode : Node

---@class UISeparatorNode : Node

---@class UIXYPlotNode : Node

---@class UIListViewNode : Node

---@class UITreeViewNode : Node

---@class UIUnorderedListNode : Node

---@class UIOrderedListNode : Node

---@class UITableNode : Node

---@class UIIconNode : Node

---@class UIToolbarNode : Node

---@class UITabContainerNode : Node

---Gets the concrete runtime type of the node (e.g. "Node", "TextureNode", "DynamicBodyNode", "CameraNode").
---
---Example: `if self.node:get_type() == "DynamicBodyNode" then Log.info("physics body") end`
---@return string
function Node:get_type() end

---Gets the display/debug name of the node.
---
---Example: `Log.info("Spawned " .. self.node:get_name())`
---@return string
function Node:get_name() end

---Sets the display/debug name of the node.
---
---Example: `self.node:set_name("Enemy_" .. tostring(index))`
---@param name string
function Node:set_name(name) end

---Gets the local position of the node.
---
---Example: `local x, y = self.node:get_position()`
---@return number x Local X position
---@return number y Local Y position
function Node:get_position() end

---Sets the local position of the node.
---
---Example: `self.node:set_position(320, 180)`
---@param x number Local X position
---@param y number Local Y position
function Node:set_position(x, y) end

---Translates the node position by the given delta offset.
---
---Example: `self.node:translate(self.speed * dt, 0)`
---@param dx number Delta X
---@param dy number Delta Y
function Node:translate(dx, dy) end

---Gets the local rotation of the node in degrees.
---
---Example: `local angle = self.node:get_rotation()`
---@return number rotation Rotation in degrees
function Node:get_rotation() end

---Sets the local rotation of the node in degrees.
---
---Example: `self.node:set_rotation(90)`
---@param degrees number Rotation in degrees
function Node:set_rotation(degrees) end

---Rotates the node by delta degrees.
---
---Example: `self.node:rotate(180 * dt)`
---@param degrees number Delta degrees
function Node:rotate(degrees) end

---Gets the local scale factor of the node.
---
---Example: `local sx, sy = self.node:get_scale()`
---@return number sx Scale X
---@return number sy Scale Y
function Node:get_scale() end

---Sets the local scale factor of the node.
---
---Example: `self.node:set_scale(-1, 1)`
---@param sx number Scale X
---@param sy? number Scale Y (defaults to sx if omitted)
function Node:set_scale(sx, sy) end

---Shows another image on a TextureNode (project-relative path, e.g. a
---`texture` script property). Returns false if it isn't a TextureNode or
---the file can't be loaded.
---
---Example: `local sprite = self.node:get_node("Sprite"); sprite:set_texture("textures/coin.png")`
---@param path TexturePath|string Project-relative texture path
---@return boolean ok
function TextureNode:set_texture(path) end

---Gets the world-space global position of the node calculated from parent transforms.
---
---Example: `local gx, gy = self.node:get_global_position()`
---@return number x Global world X position
---@return number y Global world Y position
function Node:get_global_position() end

---Gets the world-space global rotation of the node in degrees.
---
---Example: `local world_angle = self.node:get_global_rotation()`
---@return number rotation Global world rotation in degrees
function Node:get_global_rotation() end

---Checks if the node is actively updated in the scene loop.
---
---Example: `if not self.node:is_enabled() then return end`
---@return boolean
function Node:is_enabled() end

---Enables or disables updates for the node and its children.
---
---Example: `Scene.find_node("Enemy"):set_enabled(false)`
---@param enabled boolean
function Node:set_enabled(enabled) end

---Checks if the node is rendered in the scene draw loop.
---
---Example: `local shown = self.node:is_visible()`
---@return boolean
function Node:is_visible() end

---Sets whether the node is rendered.
---
---Example: `self.node:get_node("Shield"):set_visible(true)`
---@param visible boolean
function Node:set_visible(visible) end

---Gets the parent node, or nil if this is a root node.
---
---Example: `local parent = self.node:get_parent(); if parent then Log.info(parent:get_name()) end`
---@return Node?
function Node:get_parent() end

---Returns an array of all direct child nodes.
---
---Example: `for _, child in ipairs(self.node:get_children()) do child:set_visible(false) end`
---@return Node[]
function Node:get_children() end

---Adds a tag (group) to the node; false when it already has it.
---
---Example: `self.node:add_tag("enemies")`
---@param tag NodeTag|string
---@return boolean
function Node:add_tag(tag) end

---Removes a tag (group) from the node; returns false when it did not have it.
---
---Example: `local removed = self.node:remove_tag("enemies")`
---@param tag NodeTag|string
---@return boolean removed
function Node:remove_tag(tag) end

---Checks whether the node has the given tag (group).
---
---Example: `if other:has_tag("player") then self:collect() end`
---@param tag NodeTag|string
---@return boolean
function Node:has_tag(tag) end

---Returns an array of all tags (groups) on the node.
---
---Example: `for _, tag in ipairs(self.node:get_tags()) do Log.info(tag) end`
---@return string[]
function Node:get_tags() end

---Finds a direct child node by its exact name.
---
---Example: `local sprite = self.node:get_child("Sprite")`
---@param name NodeName|string
---@return Node?
function Node:get_child(name) end

---Finds a node by path relative to this one: "Gun", "Body/Gun", "../Player", "." (self).
---
---Example: `local gun = self.node:get_node("Body/Gun")`
---@param path string Relative node path
---@return Node? node The node, or nil if there is none
function Node:get_node(path) end

---Reparents a child node under this node.
---
---Example: `local item = Scene.find_node("Key"); self.node:add_child(item)`
---@param child Node
function Node:add_child(child) end

---Detaches a child node from this node.
---
---Example: `self.node:remove_child(self.node:get_child("Shield"))`
---@param child Node
function Node:remove_child(child) end

---Removes this node and all its children from the active scene (at the end
---of the frame, so it's safe from its own update).
---
---Example: `self.node:destroy()`
function Node:destroy() end

---Removes this node and its children at the end of the frame (= destroy).
---
---Example: `if self.health <= 0 then self.node:queue_free() end`
function Node:queue_free() end

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
---| "revealed"           # TextNode: the typewriter reached the end
---| "line_shown"         # DialogueNode: a line was fully shown; value: its index (1-based)

---Events every node raises.
---@alias NodeTreeEvent
---| "entered_tree"       # the node joined the scene
---| "exited_tree"        # the node is being removed
---| "child_added"        # value: the child Node
---| "child_removed"      # value: the child Node
---| "parent_added"       # value: the new parent Node
---| "parent_removed"     # value: the old parent Node

---Connects a handler to an event of this node (from any script). Handlers
---are removed automatically when the connecting script or this node is
---destroyed. A script also receives its own node's events as methods named
---`on_<event>` (e.g. `function MyScript:on_timeout() end`).
---
---Example: `self.conn = timer:connect("timeout", function(value, source) self:fire() end)`
---@param event NodeEvent|ProjectEvent|string Event name (custom ones: the project's `emit` names)
---@param handler fun(value: any, source: Node) Called with the event value and this node
---@return integer id Connection id for `disconnect`
function Node:connect(event, handler) end

---Removes a connection made with `connect`.
---
---Example: `local removed = timer:disconnect(self.conn)`
---@param id integer Connection id
---@return boolean removed
function Node:disconnect(id) end

---Raises a custom event on this node: calls the node script's `on_<event>`
---method and every handler connected to that event name.
---
---Example: `self.node:emit("health_changed", self.health)`
---@param event ProjectEvent|string Event name (the project's custom events complete)
---@param value? any Value passed to handlers
function Node:emit(event, value) end

-- node events begin (generated from the engine: lua_events_definitions_test.odin)

---@alias TimerNodeEvent NodeTreeEvent|"tick"|"timeout"|ProjectEvent
---Connects a handler to one of this node's events: tick (Every frame while the timer runs), timeout (The timer's duration elapsed); the tree events; custom ones.
---@param event TimerNodeEvent|string
---@param handler fun(value: any, source: TimerNode)
---@return integer id Connection id for `disconnect`
function TimerNode:connect(event, handler) end

---@alias FrameAnimationNodeEvent NodeTreeEvent|"animation_finished"|ProjectEvent
---Connects a handler to one of this node's events: animation_finished (A non-looping animation ended); the tree events; custom ones.
---@param event FrameAnimationNodeEvent|string
---@param handler fun(value: any, source: FrameAnimationNode)
---@return integer id Connection id for `disconnect`
function FrameAnimationNode:connect(event, handler) end

---@alias AnimationPlayerNodeEvent NodeTreeEvent|"animation_finished"|ProjectEvent
---Connects a handler to one of this node's events: animation_finished (A non-looping animation ended); the tree events; custom ones.
---@param event AnimationPlayerNodeEvent|string
---@param handler fun(value: any, source: AnimationPlayerNode)
---@return integer id Connection id for `disconnect`
function AnimationPlayerNode:connect(event, handler) end

---@alias StateMachineNodeEvent NodeTreeEvent|"state_changed"|ProjectEvent
---Connects a handler to one of this node's events: state_changed (The state machine entered a state); the tree events; custom ones.
---@param event StateMachineNodeEvent|string
---@param handler fun(value: any, source: StateMachineNode)
---@return integer id Connection id for `disconnect`
function StateMachineNode:connect(event, handler) end

---@alias SoundNodeEvent NodeTreeEvent|"finished"|ProjectEvent
---Connects a handler to one of this node's events: finished (Playback (or the dialogue) ended); the tree events; custom ones.
---@param event SoundNodeEvent|string
---@param handler fun(value: any, source: SoundNode)
---@return integer id Connection id for `disconnect`
function SoundNode:connect(event, handler) end

---@alias MusicNodeEvent NodeTreeEvent|"finished"|ProjectEvent
---Connects a handler to one of this node's events: finished (Playback (or the dialogue) ended); the tree events; custom ones.
---@param event MusicNodeEvent|string
---@param handler fun(value: any, source: MusicNode)
---@return integer id Connection id for `disconnect`
function MusicNode:connect(event, handler) end

---@alias StaticBodyNodeEvent NodeTreeEvent|"collision_started"|"collision_ended"|ProjectEvent
---Connects a handler to one of this node's events: collision_started (Contact with another body began), collision_ended (Contact with another body ended); the tree events; custom ones.
---@param event StaticBodyNodeEvent|string
---@param handler fun(value: any, source: StaticBodyNode)
---@return integer id Connection id for `disconnect`
function StaticBodyNode:connect(event, handler) end

---@alias DynamicBodyNodeEvent NodeTreeEvent|"collision_started"|"collision_ended"|ProjectEvent
---Connects a handler to one of this node's events: collision_started (Contact with another body began), collision_ended (Contact with another body ended); the tree events; custom ones.
---@param event DynamicBodyNodeEvent|string
---@param handler fun(value: any, source: DynamicBodyNode)
---@return integer id Connection id for `disconnect`
function DynamicBodyNode:connect(event, handler) end

---@alias CharacterMoverNodeEvent NodeTreeEvent|"collision_started"|"collision_ended"|ProjectEvent
---Connects a handler to one of this node's events: collision_started (Contact with another body began), collision_ended (Contact with another body ended); the tree events; custom ones.
---@param event CharacterMoverNodeEvent|string
---@param handler fun(value: any, source: CharacterMoverNode)
---@return integer id Connection id for `disconnect`
function CharacterMoverNode:connect(event, handler) end

---@alias AreaNodeEvent NodeTreeEvent|"body_entered"|"body_exited"|ProjectEvent
---Connects a handler to one of this node's events: body_entered (A body entered the area), body_exited (A body left the area); the tree events; custom ones.
---@param event AreaNodeEvent|string
---@param handler fun(value: any, source: AreaNode)
---@return integer id Connection id for `disconnect`
function AreaNode:connect(event, handler) end

---@alias RaycastNodeEvent NodeTreeEvent|"hit_started"|"hit_ended"|ProjectEvent
---Connects a handler to one of this node's events: hit_started (The ray started hitting a node), hit_ended (The ray stopped hitting a node); the tree events; custom ones.
---@param event RaycastNodeEvent|string
---@param handler fun(value: any, source: RaycastNode)
---@return integer id Connection id for `disconnect`
function RaycastNode:connect(event, handler) end

---@alias LdtkLevelNodeEvent NodeTreeEvent|"level_loaded"|"entity_spawned"|ProjectEvent
---Connects a handler to one of this node's events: level_loaded (The LDtk level was built), entity_spawned (An LDtk entity was spawned); the tree events; custom ones.
---@param event LdtkLevelNodeEvent|string
---@param handler fun(value: any, source: LdtkLevelNode)
---@return integer id Connection id for `disconnect`
function LdtkLevelNode:connect(event, handler) end

---@alias TextNodeEvent NodeTreeEvent|"revealed"|ProjectEvent
---Connects a handler to one of this node's events: revealed (The text finished revealing); the tree events; custom ones.
---@param event TextNodeEvent|string
---@param handler fun(value: any, source: TextNode)
---@return integer id Connection id for `disconnect`
function TextNode:connect(event, handler) end

---@alias DialogueNodeEvent NodeTreeEvent|"line_shown"|"finished"|ProjectEvent
---Connects a handler to one of this node's events: line_shown (A dialogue line was fully shown (1-based)), finished (Playback (or the dialogue) ended); the tree events; custom ones.
---@param event DialogueNodeEvent|string
---@param handler fun(value: any, source: DialogueNode)
---@return integer id Connection id for `disconnect`
function DialogueNode:connect(event, handler) end

---@alias UIButtonNodeEvent NodeTreeEvent|"clicked"|ProjectEvent
---Connects a handler to one of this node's events: clicked (The button was clicked); the tree events; custom ones.
---@param event UIButtonNodeEvent|string
---@param handler fun(value: any, source: UIButtonNode)
---@return integer id Connection id for `disconnect`
function UIButtonNode:connect(event, handler) end

---@alias UISliderNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---@param event UISliderNodeEvent|string
---@param handler fun(value: any, source: UISliderNode)
---@return integer id Connection id for `disconnect`
function UISliderNode:connect(event, handler) end

---@alias UICheckboxNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---@param event UICheckboxNodeEvent|string
---@param handler fun(value: any, source: UICheckboxNode)
---@return integer id Connection id for `disconnect`
function UICheckboxNode:connect(event, handler) end

---@alias UITextInputNodeEvent NodeTreeEvent|"value_changed"|"submitted"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed), submitted (Enter was pressed); the tree events; custom ones.
---@param event UITextInputNodeEvent|string
---@param handler fun(value: any, source: UITextInputNode)
---@return integer id Connection id for `disconnect`
function UITextInputNode:connect(event, handler) end

---@alias UIDropdownNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---@param event UIDropdownNodeEvent|string
---@param handler fun(value: any, source: UIDropdownNode)
---@return integer id Connection id for `disconnect`
function UIDropdownNode:connect(event, handler) end

---@alias UIRadioGroupNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---@param event UIRadioGroupNodeEvent|string
---@param handler fun(value: any, source: UIRadioGroupNode)
---@return integer id Connection id for `disconnect`
function UIRadioGroupNode:connect(event, handler) end

---@alias UIKnobNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---@param event UIKnobNodeEvent|string
---@param handler fun(value: any, source: UIKnobNode)
---@return integer id Connection id for `disconnect`
function UIKnobNode:connect(event, handler) end

---@alias UINotchedSliderNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---@param event UINotchedSliderNodeEvent|string
---@param handler fun(value: any, source: UINotchedSliderNode)
---@return integer id Connection id for `disconnect`
function UINotchedSliderNode:connect(event, handler) end

---@alias UIVolumeFaderNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---@param event UIVolumeFaderNodeEvent|string
---@param handler fun(value: any, source: UIVolumeFaderNode)
---@return integer id Connection id for `disconnect`
function UIVolumeFaderNode:connect(event, handler) end

---@alias UIUnorderedListNodeEvent NodeTreeEvent|"selected"|ProjectEvent
---Connects a handler to one of this node's events: selected (The selection changed); the tree events; custom ones.
---@param event UIUnorderedListNodeEvent|string
---@param handler fun(value: any, source: UIUnorderedListNode)
---@return integer id Connection id for `disconnect`
function UIUnorderedListNode:connect(event, handler) end

---@alias UIOrderedListNodeEvent NodeTreeEvent|"selected"|ProjectEvent
---Connects a handler to one of this node's events: selected (The selection changed); the tree events; custom ones.
---@param event UIOrderedListNodeEvent|string
---@param handler fun(value: any, source: UIOrderedListNode)
---@return integer id Connection id for `disconnect`
function UIOrderedListNode:connect(event, handler) end

---@alias UITableNodeEvent NodeTreeEvent|"row_selected"|"sorted"|ProjectEvent
---Connects a handler to one of this node's events: row_selected (A table row was selected), sorted (The table was sorted); the tree events; custom ones.
---@param event UITableNodeEvent|string
---@param handler fun(value: any, source: UITableNode)
---@return integer id Connection id for `disconnect`
function UITableNode:connect(event, handler) end

---@alias UIToolbarNodeEvent NodeTreeEvent|"item_clicked"|ProjectEvent
---Connects a handler to one of this node's events: item_clicked (A toolbar item was clicked); the tree events; custom ones.
---@param event UIToolbarNodeEvent|string
---@param handler fun(value: any, source: UIToolbarNode)
---@return integer id Connection id for `disconnect`
function UIToolbarNode:connect(event, handler) end
-- node events end

-- node properties begin (generated from the engine: lua_properties_definitions_test.odin)

---@class Node
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.

---@alias NodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path NodeProperty|string
---@return any
---@overload fun(self: Node, path: "position"): Vec2
---@overload fun(self: Node, path: "scale"): Vec2
---@overload fun(self: Node, path: "rotation"): number
---@overload fun(self: Node, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: Node, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: Node, path: "paused"): boolean
---@overload fun(self: Node, path: "enabled"): boolean
function Node:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path NodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: Node, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: Node, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: Node, path: "rotation", value: number)
---@overload fun(self: Node, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: Node, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: Node, path: "paused", value: boolean)
---@overload fun(self: Node, path: "enabled", value: boolean)
function Node:set_property(path, value, y) end

---@class CameraNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field isCurrent boolean The camera the game renders through (one per scene).
---@field followMode "Static"|"SingleTarget"|"MultiTarget"|"Manual" Static: stays put. Single Target: follows its Follow Target. Multi Target: frames all t...
---@field dragType "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed" How the camera catches up with its target: none (locked), smooth damp, spring, look-ahe...
---@field targetPosition Vec2 Where the camera is heading (world px).
---@field currentPosition Vec2 Where the camera is now (world px).
---@field smoothDrag boolean Ease towards the target instead of snapping.
---@field smoothDragSpeed Vec2 Smooth-damp time per axis (s): higher lags more.
---@field springConstant number Spring Damp: stiffness pulling the camera to the target.
---@field dampingRatio number Spring Damp: 1 settles without overshoot, lower wobbles.
---@field predictionTime Vec2 Look Ahead: how far ahead of the target to aim, in seconds of its velocity.
---@field maxDistance Vec2 Reserved (not used yet).
---@field offset Vec2 Added to the target position (world px).
---@field smoothOffset boolean Ease offset changes in.
---@field smoothOffsetSpeed number How fast offset changes ease in.
---@field screenOffset Vec2 Where on screen the camera's position appears (px; half the window = centred).
---@field currentRotation number The camera's rotation now (degrees).
---@field targetRotation number Rotation the camera turns to (degrees).
---@field allowRotation boolean Let the camera rotate (else it stays upright).
---@field smoothRotation boolean Ease rotation changes in.
---@field smoothRotationSpeed number How fast rotation eases in.
---@field zoom number Zoom now (1 = 100%, 2 = everything twice as big).
---@field targetZoom number Zoom the camera eases to.
---@field smoothZoom boolean Ease zoom changes in.
---@field smoothZoomSpeed number How fast zoom eases in.
---@field minZoom number Smallest zoom (auto zoom and scripts).
---@field maxZoom number Largest zoom (auto zoom and scripts).
---@field autoZoom boolean Multi Target: zoom out to keep every target on screen.
---@field zoomMargin number Auto zoom: extra space around the targets (0.1 = 10%).
---@field hasLimits boolean Keep the view inside the left / right / top / bottom limits.
---@field smoothLimit boolean Ease into the limits instead of stopping hard.
---@field leftLimit number Left edge the view may not pass (world px).
---@field rightLimit number Right edge the view may not pass (world px).
---@field topLimit number Top edge the view may not pass (world px).
---@field bottomLimit number Bottom edge the view may not pass (world px).
---@field useHMargins boolean Dead zone: the target moves freely between the left / right margins before the camera f...
---@field useVMargins boolean Dead zone: the target moves freely between the top / bottom margins before the camera f...
---@field leftMargin number Left dead-zone margin (fraction of the screen).
---@field rightMargin number Right dead-zone margin (fraction of the screen).
---@field topMargin number Top dead-zone margin (fraction of the screen).
---@field bottomMargin number Bottom dead-zone margin (fraction of the screen).
---@field enableMouseFollow boolean Nudge the camera towards the mouse.
---@field mouseInfluence Vec2 How much the mouse pulls the camera per axis (0-1).
---@field shakePreset "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly" Ready-made shake (gunshot, earthquake...); Custom uses the settings below.
---@field isShaking boolean A shake is running.
---@field shakeSpeed number Custom shake: how fast it shakes.
---@field shakeIntensity number Custom shake: how far it moves (px).
---@field shakeTrauma number Shake strength now (0-1); decays over time.

---@alias CameraNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "isCurrent" # boolean - The camera the game renders through (one per scene).
---| "followMode" # "Static"|"SingleTarget"|"MultiTarget"|"Manual" - Static: stays put. Single Target: follows its Follow Target. Multi Target: frames all t...
---| "dragType" # "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed" - How the camera catches up with its target: none (locked), smooth damp, spring, look-ahe...
---| "targetPosition" # Vec2 - Where the camera is heading (world px).
---| "currentPosition" # Vec2 (runtime) - Where the camera is now (world px).
---| "smoothDrag" # boolean - Ease towards the target instead of snapping.
---| "smoothDragSpeed" # Vec2 - Smooth-damp time per axis (s): higher lags more.
---| "springConstant" # number - Spring Damp: stiffness pulling the camera to the target.
---| "dampingRatio" # number - Spring Damp: 1 settles without overshoot, lower wobbles.
---| "predictionTime" # Vec2 - Look Ahead: how far ahead of the target to aim, in seconds of its velocity.
---| "maxDistance" # Vec2 - Reserved (not used yet).
---| "offset" # Vec2 - Added to the target position (world px).
---| "smoothOffset" # boolean - Ease offset changes in.
---| "smoothOffsetSpeed" # number - How fast offset changes ease in.
---| "screenOffset" # Vec2 - Where on screen the camera's position appears (px; half the window = centred).
---| "currentRotation" # number (runtime) - The camera's rotation now (degrees).
---| "targetRotation" # number - Rotation the camera turns to (degrees).
---| "allowRotation" # boolean - Let the camera rotate (else it stays upright).
---| "smoothRotation" # boolean - Ease rotation changes in.
---| "smoothRotationSpeed" # number - How fast rotation eases in.
---| "zoom" # number - Zoom now (1 = 100%, 2 = everything twice as big).
---| "targetZoom" # number - Zoom the camera eases to.
---| "smoothZoom" # boolean - Ease zoom changes in.
---| "smoothZoomSpeed" # number - How fast zoom eases in.
---| "minZoom" # number - Smallest zoom (auto zoom and scripts).
---| "maxZoom" # number - Largest zoom (auto zoom and scripts).
---| "autoZoom" # boolean - Multi Target: zoom out to keep every target on screen.
---| "zoomMargin" # number - Auto zoom: extra space around the targets (0.1 = 10%).
---| "hasLimits" # boolean - Keep the view inside the left / right / top / bottom limits.
---| "smoothLimit" # boolean - Ease into the limits instead of stopping hard.
---| "leftLimit" # number - Left edge the view may not pass (world px).
---| "rightLimit" # number - Right edge the view may not pass (world px).
---| "topLimit" # number - Top edge the view may not pass (world px).
---| "bottomLimit" # number - Bottom edge the view may not pass (world px).
---| "useHMargins" # boolean - Dead zone: the target moves freely between the left / right margins before the camera f...
---| "useVMargins" # boolean - Dead zone: the target moves freely between the top / bottom margins before the camera f...
---| "leftMargin" # number - Left dead-zone margin (fraction of the screen).
---| "rightMargin" # number - Right dead-zone margin (fraction of the screen).
---| "topMargin" # number - Top dead-zone margin (fraction of the screen).
---| "bottomMargin" # number - Bottom dead-zone margin (fraction of the screen).
---| "enableMouseFollow" # boolean - Nudge the camera towards the mouse.
---| "mouseInfluence" # Vec2 - How much the mouse pulls the camera per axis (0-1).
---| "shakePreset" # "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly" - Ready-made shake (gunshot, earthquake...); Custom uses the settings below.
---| "isShaking" # boolean (runtime) - A shake is running.
---| "shakeSpeed" # number - Custom shake: how fast it shakes.
---| "shakeIntensity" # number - Custom shake: how far it moves (px).
---| "shakeTrauma" # number - Shake strength now (0-1); decays over time.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path CameraNodeProperty|string
---@return any
---@overload fun(self: CameraNode, path: "position"): Vec2
---@overload fun(self: CameraNode, path: "scale"): Vec2
---@overload fun(self: CameraNode, path: "rotation"): number
---@overload fun(self: CameraNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: CameraNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: CameraNode, path: "paused"): boolean
---@overload fun(self: CameraNode, path: "enabled"): boolean
---@overload fun(self: CameraNode, path: "isCurrent"): boolean
---@overload fun(self: CameraNode, path: "followMode"): "Static"|"SingleTarget"|"MultiTarget"|"Manual"
---@overload fun(self: CameraNode, path: "dragType"): "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed"
---@overload fun(self: CameraNode, path: "targetPosition"): Vec2
---@overload fun(self: CameraNode, path: "currentPosition"): Vec2
---@overload fun(self: CameraNode, path: "smoothDrag"): boolean
---@overload fun(self: CameraNode, path: "smoothDragSpeed"): Vec2
---@overload fun(self: CameraNode, path: "springConstant"): number
---@overload fun(self: CameraNode, path: "dampingRatio"): number
---@overload fun(self: CameraNode, path: "predictionTime"): Vec2
---@overload fun(self: CameraNode, path: "maxDistance"): Vec2
---@overload fun(self: CameraNode, path: "offset"): Vec2
---@overload fun(self: CameraNode, path: "smoothOffset"): boolean
---@overload fun(self: CameraNode, path: "smoothOffsetSpeed"): number
---@overload fun(self: CameraNode, path: "screenOffset"): Vec2
---@overload fun(self: CameraNode, path: "currentRotation"): number
---@overload fun(self: CameraNode, path: "targetRotation"): number
---@overload fun(self: CameraNode, path: "allowRotation"): boolean
---@overload fun(self: CameraNode, path: "smoothRotation"): boolean
---@overload fun(self: CameraNode, path: "smoothRotationSpeed"): number
---@overload fun(self: CameraNode, path: "zoom"): number
---@overload fun(self: CameraNode, path: "targetZoom"): number
---@overload fun(self: CameraNode, path: "smoothZoom"): boolean
---@overload fun(self: CameraNode, path: "smoothZoomSpeed"): number
---@overload fun(self: CameraNode, path: "minZoom"): number
---@overload fun(self: CameraNode, path: "maxZoom"): number
---@overload fun(self: CameraNode, path: "autoZoom"): boolean
---@overload fun(self: CameraNode, path: "zoomMargin"): number
---@overload fun(self: CameraNode, path: "hasLimits"): boolean
---@overload fun(self: CameraNode, path: "smoothLimit"): boolean
---@overload fun(self: CameraNode, path: "leftLimit"): number
---@overload fun(self: CameraNode, path: "rightLimit"): number
---@overload fun(self: CameraNode, path: "topLimit"): number
---@overload fun(self: CameraNode, path: "bottomLimit"): number
---@overload fun(self: CameraNode, path: "useHMargins"): boolean
---@overload fun(self: CameraNode, path: "useVMargins"): boolean
---@overload fun(self: CameraNode, path: "leftMargin"): number
---@overload fun(self: CameraNode, path: "rightMargin"): number
---@overload fun(self: CameraNode, path: "topMargin"): number
---@overload fun(self: CameraNode, path: "bottomMargin"): number
---@overload fun(self: CameraNode, path: "enableMouseFollow"): boolean
---@overload fun(self: CameraNode, path: "mouseInfluence"): Vec2
---@overload fun(self: CameraNode, path: "shakePreset"): "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly"
---@overload fun(self: CameraNode, path: "isShaking"): boolean
---@overload fun(self: CameraNode, path: "shakeSpeed"): number
---@overload fun(self: CameraNode, path: "shakeIntensity"): number
---@overload fun(self: CameraNode, path: "shakeTrauma"): number
function CameraNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path CameraNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: CameraNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "rotation", value: number)
---@overload fun(self: CameraNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: CameraNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: CameraNode, path: "paused", value: boolean)
---@overload fun(self: CameraNode, path: "enabled", value: boolean)
---@overload fun(self: CameraNode, path: "isCurrent", value: boolean)
---@overload fun(self: CameraNode, path: "followMode", value: "Static"|"SingleTarget"|"MultiTarget"|"Manual")
---@overload fun(self: CameraNode, path: "dragType", value: "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed")
---@overload fun(self: CameraNode, path: "targetPosition", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "currentPosition", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "smoothDrag", value: boolean)
---@overload fun(self: CameraNode, path: "smoothDragSpeed", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "springConstant", value: number)
---@overload fun(self: CameraNode, path: "dampingRatio", value: number)
---@overload fun(self: CameraNode, path: "predictionTime", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "maxDistance", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "offset", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "smoothOffset", value: boolean)
---@overload fun(self: CameraNode, path: "smoothOffsetSpeed", value: number)
---@overload fun(self: CameraNode, path: "screenOffset", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "currentRotation", value: number)
---@overload fun(self: CameraNode, path: "targetRotation", value: number)
---@overload fun(self: CameraNode, path: "allowRotation", value: boolean)
---@overload fun(self: CameraNode, path: "smoothRotation", value: boolean)
---@overload fun(self: CameraNode, path: "smoothRotationSpeed", value: number)
---@overload fun(self: CameraNode, path: "zoom", value: number)
---@overload fun(self: CameraNode, path: "targetZoom", value: number)
---@overload fun(self: CameraNode, path: "smoothZoom", value: boolean)
---@overload fun(self: CameraNode, path: "smoothZoomSpeed", value: number)
---@overload fun(self: CameraNode, path: "minZoom", value: number)
---@overload fun(self: CameraNode, path: "maxZoom", value: number)
---@overload fun(self: CameraNode, path: "autoZoom", value: boolean)
---@overload fun(self: CameraNode, path: "zoomMargin", value: number)
---@overload fun(self: CameraNode, path: "hasLimits", value: boolean)
---@overload fun(self: CameraNode, path: "smoothLimit", value: boolean)
---@overload fun(self: CameraNode, path: "leftLimit", value: number)
---@overload fun(self: CameraNode, path: "rightLimit", value: number)
---@overload fun(self: CameraNode, path: "topLimit", value: number)
---@overload fun(self: CameraNode, path: "bottomLimit", value: number)
---@overload fun(self: CameraNode, path: "useHMargins", value: boolean)
---@overload fun(self: CameraNode, path: "useVMargins", value: boolean)
---@overload fun(self: CameraNode, path: "leftMargin", value: number)
---@overload fun(self: CameraNode, path: "rightMargin", value: number)
---@overload fun(self: CameraNode, path: "topMargin", value: number)
---@overload fun(self: CameraNode, path: "bottomMargin", value: number)
---@overload fun(self: CameraNode, path: "enableMouseFollow", value: boolean)
---@overload fun(self: CameraNode, path: "mouseInfluence", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "shakePreset", value: "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly")
---@overload fun(self: CameraNode, path: "isShaking", value: boolean)
---@overload fun(self: CameraNode, path: "shakeSpeed", value: number)
---@overload fun(self: CameraNode, path: "shakeIntensity", value: number)
---@overload fun(self: CameraNode, path: "shakeTrauma", value: number)
function CameraNode:set_property(path, value, y) end

---@class TextureNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias TextureNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path TextureNodeProperty|string
---@return any
---@overload fun(self: TextureNode, path: "position"): Vec2
---@overload fun(self: TextureNode, path: "scale"): Vec2
---@overload fun(self: TextureNode, path: "rotation"): number
---@overload fun(self: TextureNode, path: "origin"): Vec2
---@overload fun(self: TextureNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TextureNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TextureNode, path: "paused"): boolean
---@overload fun(self: TextureNode, path: "enabled"): boolean
---@overload fun(self: TextureNode, path: "tint"): number[]
function TextureNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path TextureNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: TextureNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextureNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextureNode, path: "rotation", value: number)
---@overload fun(self: TextureNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextureNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TextureNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TextureNode, path: "paused", value: boolean)
---@overload fun(self: TextureNode, path: "enabled", value: boolean)
---@overload fun(self: TextureNode, path: "tint", value: number[])
function TextureNode:set_property(path, value, y) end

---@class FrameAnimationNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.

---@alias FrameAnimationNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path FrameAnimationNodeProperty|string
---@return any
---@overload fun(self: FrameAnimationNode, path: "position"): Vec2
---@overload fun(self: FrameAnimationNode, path: "scale"): Vec2
---@overload fun(self: FrameAnimationNode, path: "rotation"): number
---@overload fun(self: FrameAnimationNode, path: "origin"): Vec2
---@overload fun(self: FrameAnimationNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: FrameAnimationNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: FrameAnimationNode, path: "paused"): boolean
---@overload fun(self: FrameAnimationNode, path: "enabled"): boolean
function FrameAnimationNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path FrameAnimationNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: FrameAnimationNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: FrameAnimationNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: FrameAnimationNode, path: "rotation", value: number)
---@overload fun(self: FrameAnimationNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: FrameAnimationNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: FrameAnimationNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: FrameAnimationNode, path: "paused", value: boolean)
---@overload fun(self: FrameAnimationNode, path: "enabled", value: boolean)
function FrameAnimationNode:set_property(path, value, y) end

---@class AnimationPlayerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field reverse boolean Play the animation backwards.
---@field autoplay boolean Start playing the current animation when the node becomes ready.
---@field fps number Frames per second of the animations that don't set their own (the Animation tab's FPS b...
---@field defaultAnimation string The animation selected (and autoplayed) when the scene loads; empty = the one saved as ...

---@alias AnimationPlayerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "reverse" # boolean - Play the animation backwards.
---| "autoplay" # boolean - Start playing the current animation when the node becomes ready.
---| "fps" # number - Frames per second of the animations that don't set their own (the Animation tab's FPS b...
---| "defaultAnimation" # string - The animation selected (and autoplayed) when the scene loads; empty = the one saved as ...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path AnimationPlayerNodeProperty|string
---@return any
---@overload fun(self: AnimationPlayerNode, path: "position"): Vec2
---@overload fun(self: AnimationPlayerNode, path: "scale"): Vec2
---@overload fun(self: AnimationPlayerNode, path: "rotation"): number
---@overload fun(self: AnimationPlayerNode, path: "origin"): Vec2
---@overload fun(self: AnimationPlayerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: AnimationPlayerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: AnimationPlayerNode, path: "paused"): boolean
---@overload fun(self: AnimationPlayerNode, path: "enabled"): boolean
---@overload fun(self: AnimationPlayerNode, path: "reverse"): boolean
---@overload fun(self: AnimationPlayerNode, path: "autoplay"): boolean
---@overload fun(self: AnimationPlayerNode, path: "fps"): number
---@overload fun(self: AnimationPlayerNode, path: "defaultAnimation"): string
function AnimationPlayerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path AnimationPlayerNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: AnimationPlayerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: AnimationPlayerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: AnimationPlayerNode, path: "rotation", value: number)
---@overload fun(self: AnimationPlayerNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: AnimationPlayerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: AnimationPlayerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: AnimationPlayerNode, path: "paused", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "enabled", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "reverse", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "autoplay", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "fps", value: number)
---@overload fun(self: AnimationPlayerNode, path: "defaultAnimation", value: string)
function AnimationPlayerNode:set_property(path, value, y) end

---@class ParticleEmitterNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.

---@alias ParticleEmitterNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "emitter.amount" # integer - Particles alive at once (the pool size).
---| "emitter.lifetime" # number - Seconds each particle lives.
---| "emitter.position" # Vec2 (runtime) - Emitter position (follows the node).
---| "emitter.burst" # number - 0 spreads emission evenly over the lifetime, 1 releases every particle at once.
---| "emitter.size" # Vec2 - Particle size (px).
---| "emitter.sizeVariance" # number - How much of Size Spread is applied at random (0-1).
---| "emitter.sizeSpread" # number - Largest random size change (px).
---| "emitter.scaleStart" # Vec2 - Scale at birth (multiplies Size).
---| "emitter.scaleEnd" # Vec2 - Scale at death; it interpolates over the lifetime.
---| "emitter.rotation" # number - Starting rotation (degrees).
---| "emitter.rotationVariance" # number - How much of Rotation Spread is applied at random (0-1).
---| "emitter.rotationSpread" # number - Largest random rotation change (degrees).
---| "emitter.torque" # number - Spin speed (degrees/s).
---| "emitter.torqueVariance" # number - How much of Torque Spread is applied at random (0-1).
---| "emitter.torqueSpread" # number - Largest random spin change (degrees/s).
---| "emitter.torqueAcceleration" # number - Change in spin speed per second.
---| "emitter.useColorRamp" # boolean - Colour over the lifetime from the colour ramp (else Particle Color to Color End).
---| "emitter.particleColor" # number[] - Colour at birth.
---| "emitter.colorEnd" # number[] - Colour at death.
---| "emitter.colorVariance" # number - Random colour variation (0-1).
---| "emitter.spread" # Vec2 - Particles start anywhere within ± this box around the emitter (px).
---| "emitter.velocity" # number - Starting speed (px/s).
---| "emitter.velocityVariance" # number - How much of Velocity Spread is applied at random (0-1).
---| "emitter.velocitySpread" # number - Largest random speed change (px/s).
---| "emitter.velocityScale" # number - Multiplies every particle's movement (slow motion < 1).
---| "emitter.acceleration" # number - Change in speed per second along the direction of travel.
---| "emitter.angle" # number - Emission direction (degrees; 0 = right, 90 = down).
---| "emitter.angleVariance" # number - How much of Angle Spread is applied at random (0-1).
---| "emitter.angleSpread" # number - Largest random change to the angle (± degrees; 180 = all round).
---| "emitter.gravityDirection" # Vec2 - Direction gravity pulls particles.
---| "emitter.gravityVelocity" # number - Strength of that gravity (px/s²).
---| "emitter.wind" # Vec2 - Constant drift added to every particle (px/s).
---| "emitter.collisionEnabled" # boolean - Particles bounce off physics colliders.
---| "emitter.elasticity" # number - Bounciness when colliding (0 stops, 1 keeps all speed).
---| "emitter.shape" # "Circle"|"Ellipse"|"Rectangle"|"Pixel"|"Line"|"Texture"|"Custom" - Shape each particle is drawn as.
---| "emitter.emitting" # boolean - Emit new particles (existing ones finish their lives).
---| "emitter.continuous" # boolean - Keep emitting (else one cycle, then stop).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path ParticleEmitterNodeProperty|string
---@return any
---@overload fun(self: ParticleEmitterNode, path: "position"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "scale"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "rotation"): number
---@overload fun(self: ParticleEmitterNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: ParticleEmitterNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: ParticleEmitterNode, path: "paused"): boolean
---@overload fun(self: ParticleEmitterNode, path: "enabled"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.amount"): integer
---@overload fun(self: ParticleEmitterNode, path: "emitter.lifetime"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.position"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.burst"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.size"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleStart"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleEnd"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotation"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torque"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueAcceleration"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.useColorRamp"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.particleColor"): number[]
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorEnd"): number[]
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.spread"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocitySpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityScale"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.acceleration"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.angle"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityDirection"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityVelocity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.wind"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.collisionEnabled"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.elasticity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.shape"): "Circle"|"Ellipse"|"Rectangle"|"Pixel"|"Line"|"Texture"|"Custom"
---@overload fun(self: ParticleEmitterNode, path: "emitter.emitting"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.continuous"): boolean
function ParticleEmitterNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path ParticleEmitterNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: ParticleEmitterNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "rotation", value: number)
---@overload fun(self: ParticleEmitterNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: ParticleEmitterNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: ParticleEmitterNode, path: "paused", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "enabled", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.amount", value: integer)
---@overload fun(self: ParticleEmitterNode, path: "emitter.lifetime", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.position", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.burst", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.size", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleStart", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleEnd", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotation", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torque", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueAcceleration", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.useColorRamp", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.particleColor", value: number[])
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorEnd", value: number[])
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.spread", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocitySpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityScale", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.acceleration", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.angle", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityDirection", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityVelocity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.wind", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.collisionEnabled", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.elasticity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.shape", value: "Circle"|"Ellipse"|"Rectangle"|"Pixel"|"Line"|"Texture"|"Custom")
---@overload fun(self: ParticleEmitterNode, path: "emitter.emitting", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.continuous", value: boolean)
function ParticleEmitterNode:set_property(path, value, y) end

---@class SoundNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field volume number Volume (0-1), before the bus and master volumes.
---@field pitch number Playback speed / pitch (1 = normal).
---@field autoplay boolean Play once when the node becomes ready.
---@field voices integer Plays over itself up to this many times (1: a new play restarts it).
---@field positional boolean Volume and pan follow the node's distance and side from the listener (the current camera).
---@field minDistance number Positional: full volume within this distance (px).
---@field maxDistance number Positional: silent beyond this distance (px).

---@alias SoundNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "volume" # number - Volume (0-1), before the bus and master volumes.
---| "pitch" # number - Playback speed / pitch (1 = normal).
---| "autoplay" # boolean - Play once when the node becomes ready.
---| "voices" # integer - Plays over itself up to this many times (1: a new play restarts it).
---| "positional" # boolean - Volume and pan follow the node's distance and side from the listener (the current camera).
---| "minDistance" # number - Positional: full volume within this distance (px).
---| "maxDistance" # number - Positional: silent beyond this distance (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path SoundNodeProperty|string
---@return any
---@overload fun(self: SoundNode, path: "position"): Vec2
---@overload fun(self: SoundNode, path: "scale"): Vec2
---@overload fun(self: SoundNode, path: "rotation"): number
---@overload fun(self: SoundNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: SoundNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: SoundNode, path: "paused"): boolean
---@overload fun(self: SoundNode, path: "enabled"): boolean
---@overload fun(self: SoundNode, path: "volume"): number
---@overload fun(self: SoundNode, path: "pitch"): number
---@overload fun(self: SoundNode, path: "autoplay"): boolean
---@overload fun(self: SoundNode, path: "voices"): integer
---@overload fun(self: SoundNode, path: "positional"): boolean
---@overload fun(self: SoundNode, path: "minDistance"): number
---@overload fun(self: SoundNode, path: "maxDistance"): number
function SoundNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path SoundNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: SoundNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: SoundNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: SoundNode, path: "rotation", value: number)
---@overload fun(self: SoundNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: SoundNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: SoundNode, path: "paused", value: boolean)
---@overload fun(self: SoundNode, path: "enabled", value: boolean)
---@overload fun(self: SoundNode, path: "volume", value: number)
---@overload fun(self: SoundNode, path: "pitch", value: number)
---@overload fun(self: SoundNode, path: "autoplay", value: boolean)
---@overload fun(self: SoundNode, path: "voices", value: integer)
---@overload fun(self: SoundNode, path: "positional", value: boolean)
---@overload fun(self: SoundNode, path: "minDistance", value: number)
---@overload fun(self: SoundNode, path: "maxDistance", value: number)
function SoundNode:set_property(path, value, y) end

---@class MusicNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field volume number Volume (0-1), before the bus and master volumes.
---@field pitch number Playback speed / pitch (1 = normal).
---@field pan number Stereo position: 0 left, 0.5 centre, 1 right.
---@field looping boolean Start again at the end.
---@field autoplay boolean Start playing when the node becomes ready.
---@field isPlaying boolean Playing now.
---@field isPaused boolean Paused now.

---@alias MusicNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "volume" # number - Volume (0-1), before the bus and master volumes.
---| "pitch" # number - Playback speed / pitch (1 = normal).
---| "pan" # number - Stereo position: 0 left, 0.5 centre, 1 right.
---| "looping" # boolean - Start again at the end.
---| "autoplay" # boolean - Start playing when the node becomes ready.
---| "isPlaying" # boolean (runtime) - Playing now.
---| "isPaused" # boolean (runtime) - Paused now.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path MusicNodeProperty|string
---@return any
---@overload fun(self: MusicNode, path: "position"): Vec2
---@overload fun(self: MusicNode, path: "scale"): Vec2
---@overload fun(self: MusicNode, path: "rotation"): number
---@overload fun(self: MusicNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: MusicNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: MusicNode, path: "paused"): boolean
---@overload fun(self: MusicNode, path: "enabled"): boolean
---@overload fun(self: MusicNode, path: "volume"): number
---@overload fun(self: MusicNode, path: "pitch"): number
---@overload fun(self: MusicNode, path: "pan"): number
---@overload fun(self: MusicNode, path: "looping"): boolean
---@overload fun(self: MusicNode, path: "autoplay"): boolean
---@overload fun(self: MusicNode, path: "isPlaying"): boolean
---@overload fun(self: MusicNode, path: "isPaused"): boolean
function MusicNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path MusicNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: MusicNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: MusicNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: MusicNode, path: "rotation", value: number)
---@overload fun(self: MusicNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: MusicNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: MusicNode, path: "paused", value: boolean)
---@overload fun(self: MusicNode, path: "enabled", value: boolean)
---@overload fun(self: MusicNode, path: "volume", value: number)
---@overload fun(self: MusicNode, path: "pitch", value: number)
---@overload fun(self: MusicNode, path: "pan", value: number)
---@overload fun(self: MusicNode, path: "looping", value: boolean)
---@overload fun(self: MusicNode, path: "autoplay", value: boolean)
---@overload fun(self: MusicNode, path: "isPlaying", value: boolean)
---@overload fun(self: MusicNode, path: "isPaused", value: boolean)
function MusicNode:set_property(path, value, y) end

---@class StaticBodyNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field debugColor number[] Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---@field oneWay boolean Jump-through platform: bodies pass from below and land on top.

---@alias StaticBodyNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "debugColor" # number[] - Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---| "oneWay" # boolean - Jump-through platform: bodies pass from below and land on top.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path StaticBodyNodeProperty|string
---@return any
---@overload fun(self: StaticBodyNode, path: "position"): Vec2
---@overload fun(self: StaticBodyNode, path: "scale"): Vec2
---@overload fun(self: StaticBodyNode, path: "rotation"): number
---@overload fun(self: StaticBodyNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: StaticBodyNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: StaticBodyNode, path: "paused"): boolean
---@overload fun(self: StaticBodyNode, path: "enabled"): boolean
---@overload fun(self: StaticBodyNode, path: "debugColor"): number[]
---@overload fun(self: StaticBodyNode, path: "oneWay"): boolean
function StaticBodyNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path StaticBodyNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: StaticBodyNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: StaticBodyNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: StaticBodyNode, path: "rotation", value: number)
---@overload fun(self: StaticBodyNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: StaticBodyNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: StaticBodyNode, path: "paused", value: boolean)
---@overload fun(self: StaticBodyNode, path: "enabled", value: boolean)
---@overload fun(self: StaticBodyNode, path: "debugColor", value: number[])
---@overload fun(self: StaticBodyNode, path: "oneWay", value: boolean)
function StaticBodyNode:set_property(path, value, y) end

---@class DynamicBodyNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field linearVelocity Vec2 Velocity (px/s).
---@field angularVelocity number Spin (degrees/s).
---@field linearDamping number Slows movement over time (air drag).
---@field angularDamping number Slows spin over time.
---@field gravityScale number Multiplies the world's gravity for this body (0 floats, negative rises).
---@field sleepThreshold number Below this speed the body may sleep (px/s).
---@field enableSleep boolean Let the body sleep when at rest (saves time; contacts wake it).
---@field isAwake boolean Awake (simulated) now.
---@field fixedRotation boolean Never rotate (characters, upright crates).
---@field isBullet boolean Continuous collision against other moving bodies (fast projectiles).
---@field allowFastRotation boolean Allow very fast spin (wheels); can be less stable.
---@field debugColor number[] Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...

---@alias DynamicBodyNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "linearVelocity" # Vec2 - Velocity (px/s).
---| "angularVelocity" # number - Spin (degrees/s).
---| "linearDamping" # number - Slows movement over time (air drag).
---| "angularDamping" # number - Slows spin over time.
---| "gravityScale" # number - Multiplies the world's gravity for this body (0 floats, negative rises).
---| "sleepThreshold" # number - Below this speed the body may sleep (px/s).
---| "enableSleep" # boolean - Let the body sleep when at rest (saves time; contacts wake it).
---| "isAwake" # boolean - Awake (simulated) now.
---| "fixedRotation" # boolean - Never rotate (characters, upright crates).
---| "isBullet" # boolean - Continuous collision against other moving bodies (fast projectiles).
---| "allowFastRotation" # boolean - Allow very fast spin (wheels); can be less stable.
---| "debugColor" # number[] - Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path DynamicBodyNodeProperty|string
---@return any
---@overload fun(self: DynamicBodyNode, path: "position"): Vec2
---@overload fun(self: DynamicBodyNode, path: "scale"): Vec2
---@overload fun(self: DynamicBodyNode, path: "rotation"): number
---@overload fun(self: DynamicBodyNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: DynamicBodyNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: DynamicBodyNode, path: "paused"): boolean
---@overload fun(self: DynamicBodyNode, path: "enabled"): boolean
---@overload fun(self: DynamicBodyNode, path: "linearVelocity"): Vec2
---@overload fun(self: DynamicBodyNode, path: "angularVelocity"): number
---@overload fun(self: DynamicBodyNode, path: "linearDamping"): number
---@overload fun(self: DynamicBodyNode, path: "angularDamping"): number
---@overload fun(self: DynamicBodyNode, path: "gravityScale"): number
---@overload fun(self: DynamicBodyNode, path: "sleepThreshold"): number
---@overload fun(self: DynamicBodyNode, path: "enableSleep"): boolean
---@overload fun(self: DynamicBodyNode, path: "isAwake"): boolean
---@overload fun(self: DynamicBodyNode, path: "fixedRotation"): boolean
---@overload fun(self: DynamicBodyNode, path: "isBullet"): boolean
---@overload fun(self: DynamicBodyNode, path: "allowFastRotation"): boolean
---@overload fun(self: DynamicBodyNode, path: "debugColor"): number[]
function DynamicBodyNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path DynamicBodyNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: DynamicBodyNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: DynamicBodyNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: DynamicBodyNode, path: "rotation", value: number)
---@overload fun(self: DynamicBodyNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: DynamicBodyNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: DynamicBodyNode, path: "paused", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "enabled", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "linearVelocity", x: number|Vec2|number[], y?: number)
---@overload fun(self: DynamicBodyNode, path: "angularVelocity", value: number)
---@overload fun(self: DynamicBodyNode, path: "linearDamping", value: number)
---@overload fun(self: DynamicBodyNode, path: "angularDamping", value: number)
---@overload fun(self: DynamicBodyNode, path: "gravityScale", value: number)
---@overload fun(self: DynamicBodyNode, path: "sleepThreshold", value: number)
---@overload fun(self: DynamicBodyNode, path: "enableSleep", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "isAwake", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "fixedRotation", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "isBullet", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "allowFastRotation", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "debugColor", value: number[])
function DynamicBodyNode:set_property(path, value, y) end

---@class CharacterMoverNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field radius number Capsule radius (px).
---@field height number Capsule height (px).
---@field velocity Vec2 Velocity now (px/s).
---@field targetSpeedX number Horizontal speed the built-in movement accelerates to (px/s).
---@field maxSpeed number Top running speed (px/s).
---@field acceleration number How quickly it reaches top speed (px/s²).
---@field jumpSpeed number Upward speed of a jump (px/s).
---@field gravityScale number Multiplies the world's gravity for the character.
---@field pushLimit number Most push per step from overlapping bodies (px/s; 0 = unlimited).
---@field clipVelocity boolean Remove velocity into walls and floors it hits (slide along them).
---@field enableKeyboardInput boolean Built-in movement: the move / jump input actions drive it.
---@field isGrounded boolean Standing on something now.
---@field debugColor number[] Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---@field controlMode "BuiltIn"|"Script" Built-in movement, or Script: the script moves it (character_move_and_slide).

---@alias CharacterMoverNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "radius" # number - Capsule radius (px).
---| "height" # number - Capsule height (px).
---| "velocity" # Vec2 (runtime) - Velocity now (px/s).
---| "targetSpeedX" # number (runtime) - Horizontal speed the built-in movement accelerates to (px/s).
---| "maxSpeed" # number - Top running speed (px/s).
---| "acceleration" # number - How quickly it reaches top speed (px/s²).
---| "jumpSpeed" # number - Upward speed of a jump (px/s).
---| "gravityScale" # number - Multiplies the world's gravity for the character.
---| "pushLimit" # number - Most push per step from overlapping bodies (px/s; 0 = unlimited).
---| "clipVelocity" # boolean - Remove velocity into walls and floors it hits (slide along them).
---| "enableKeyboardInput" # boolean - Built-in movement: the move / jump input actions drive it.
---| "isGrounded" # boolean (runtime) - Standing on something now.
---| "debugColor" # number[] - Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---| "controlMode" # "BuiltIn"|"Script" - Built-in movement, or Script: the script moves it (character_move_and_slide).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path CharacterMoverNodeProperty|string
---@return any
---@overload fun(self: CharacterMoverNode, path: "position"): Vec2
---@overload fun(self: CharacterMoverNode, path: "scale"): Vec2
---@overload fun(self: CharacterMoverNode, path: "rotation"): number
---@overload fun(self: CharacterMoverNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: CharacterMoverNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: CharacterMoverNode, path: "paused"): boolean
---@overload fun(self: CharacterMoverNode, path: "enabled"): boolean
---@overload fun(self: CharacterMoverNode, path: "radius"): number
---@overload fun(self: CharacterMoverNode, path: "height"): number
---@overload fun(self: CharacterMoverNode, path: "velocity"): Vec2
---@overload fun(self: CharacterMoverNode, path: "targetSpeedX"): number
---@overload fun(self: CharacterMoverNode, path: "maxSpeed"): number
---@overload fun(self: CharacterMoverNode, path: "acceleration"): number
---@overload fun(self: CharacterMoverNode, path: "jumpSpeed"): number
---@overload fun(self: CharacterMoverNode, path: "gravityScale"): number
---@overload fun(self: CharacterMoverNode, path: "pushLimit"): number
---@overload fun(self: CharacterMoverNode, path: "clipVelocity"): boolean
---@overload fun(self: CharacterMoverNode, path: "enableKeyboardInput"): boolean
---@overload fun(self: CharacterMoverNode, path: "isGrounded"): boolean
---@overload fun(self: CharacterMoverNode, path: "debugColor"): number[]
---@overload fun(self: CharacterMoverNode, path: "controlMode"): "BuiltIn"|"Script"
function CharacterMoverNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path CharacterMoverNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: CharacterMoverNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: CharacterMoverNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: CharacterMoverNode, path: "rotation", value: number)
---@overload fun(self: CharacterMoverNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: CharacterMoverNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: CharacterMoverNode, path: "paused", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "enabled", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "radius", value: number)
---@overload fun(self: CharacterMoverNode, path: "height", value: number)
---@overload fun(self: CharacterMoverNode, path: "velocity", x: number|Vec2|number[], y?: number)
---@overload fun(self: CharacterMoverNode, path: "targetSpeedX", value: number)
---@overload fun(self: CharacterMoverNode, path: "maxSpeed", value: number)
---@overload fun(self: CharacterMoverNode, path: "acceleration", value: number)
---@overload fun(self: CharacterMoverNode, path: "jumpSpeed", value: number)
---@overload fun(self: CharacterMoverNode, path: "gravityScale", value: number)
---@overload fun(self: CharacterMoverNode, path: "pushLimit", value: number)
---@overload fun(self: CharacterMoverNode, path: "clipVelocity", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "enableKeyboardInput", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "isGrounded", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "debugColor", value: number[])
---@overload fun(self: CharacterMoverNode, path: "controlMode", value: "BuiltIn"|"Script")
function CharacterMoverNode:set_property(path, value, y) end

---@class AreaNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field overlapCount integer Bodies overlapping now.
---@field hasOverlaps boolean Anything overlapping now.
---@field debugColor number[] Outline colour when nothing overlaps.
---@field activeColor number[] Outline colour while something overlaps.

---@alias AreaNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "overlapCount" # integer (runtime) - Bodies overlapping now.
---| "hasOverlaps" # boolean (runtime) - Anything overlapping now.
---| "debugColor" # number[] - Outline colour when nothing overlaps.
---| "activeColor" # number[] - Outline colour while something overlaps.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path AreaNodeProperty|string
---@return any
---@overload fun(self: AreaNode, path: "position"): Vec2
---@overload fun(self: AreaNode, path: "scale"): Vec2
---@overload fun(self: AreaNode, path: "rotation"): number
---@overload fun(self: AreaNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: AreaNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: AreaNode, path: "paused"): boolean
---@overload fun(self: AreaNode, path: "enabled"): boolean
---@overload fun(self: AreaNode, path: "overlapCount"): integer
---@overload fun(self: AreaNode, path: "hasOverlaps"): boolean
---@overload fun(self: AreaNode, path: "debugColor"): number[]
---@overload fun(self: AreaNode, path: "activeColor"): number[]
function AreaNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path AreaNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: AreaNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: AreaNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: AreaNode, path: "rotation", value: number)
---@overload fun(self: AreaNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: AreaNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: AreaNode, path: "paused", value: boolean)
---@overload fun(self: AreaNode, path: "enabled", value: boolean)
---@overload fun(self: AreaNode, path: "overlapCount", value: integer)
---@overload fun(self: AreaNode, path: "hasOverlaps", value: boolean)
---@overload fun(self: AreaNode, path: "debugColor", value: number[])
---@overload fun(self: AreaNode, path: "activeColor", value: number[])
function AreaNode:set_property(path, value, y) end

---@class RaycastNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field direction Vec2 Direction of the ray (rotated with the node).
---@field length number Length of the ray (px).
---@field collideWithSensors boolean Sensor shapes (areas) also stop the ray.
---@field isColliding boolean The ray hit something this frame.
---@field hitFraction number Where along the ray it hit (0 start, 1 end).
---@field hitPoint Vec2 World point of the hit (px).
---@field hitNormal Vec2 Surface direction at the hit.
---@field rayColor number[] Ray colour when it hits nothing.
---@field hitColor number[] Ray colour when it hits.

---@alias RaycastNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "direction" # Vec2 - Direction of the ray (rotated with the node).
---| "length" # number - Length of the ray (px).
---| "collideWithSensors" # boolean - Sensor shapes (areas) also stop the ray.
---| "isColliding" # boolean (runtime) - The ray hit something this frame.
---| "hitFraction" # number (runtime) - Where along the ray it hit (0 start, 1 end).
---| "hitPoint" # Vec2 (runtime) - World point of the hit (px).
---| "hitNormal" # Vec2 (runtime) - Surface direction at the hit.
---| "rayColor" # number[] - Ray colour when it hits nothing.
---| "hitColor" # number[] - Ray colour when it hits.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path RaycastNodeProperty|string
---@return any
---@overload fun(self: RaycastNode, path: "position"): Vec2
---@overload fun(self: RaycastNode, path: "scale"): Vec2
---@overload fun(self: RaycastNode, path: "rotation"): number
---@overload fun(self: RaycastNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: RaycastNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: RaycastNode, path: "paused"): boolean
---@overload fun(self: RaycastNode, path: "enabled"): boolean
---@overload fun(self: RaycastNode, path: "direction"): Vec2
---@overload fun(self: RaycastNode, path: "length"): number
---@overload fun(self: RaycastNode, path: "collideWithSensors"): boolean
---@overload fun(self: RaycastNode, path: "isColliding"): boolean
---@overload fun(self: RaycastNode, path: "hitFraction"): number
---@overload fun(self: RaycastNode, path: "hitPoint"): Vec2
---@overload fun(self: RaycastNode, path: "hitNormal"): Vec2
---@overload fun(self: RaycastNode, path: "rayColor"): number[]
---@overload fun(self: RaycastNode, path: "hitColor"): number[]
function RaycastNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path RaycastNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: RaycastNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "rotation", value: number)
---@overload fun(self: RaycastNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: RaycastNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: RaycastNode, path: "paused", value: boolean)
---@overload fun(self: RaycastNode, path: "enabled", value: boolean)
---@overload fun(self: RaycastNode, path: "direction", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "length", value: number)
---@overload fun(self: RaycastNode, path: "collideWithSensors", value: boolean)
---@overload fun(self: RaycastNode, path: "isColliding", value: boolean)
---@overload fun(self: RaycastNode, path: "hitFraction", value: number)
---@overload fun(self: RaycastNode, path: "hitPoint", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "hitNormal", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "rayColor", value: number[])
---@overload fun(self: RaycastNode, path: "hitColor", value: number[])
function RaycastNode:set_property(path, value, y) end

---@class LdtkLevelNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field enablePhysics boolean Build colliders from IntGrid cells whose collision rule is Solid / One Way.
---@field spawnEntities boolean Spawn the level's entities (mapped to components) when ready.
---@field parallax boolean Apply the LDtk layers' parallax factors.
---@field drawBackground boolean Draw the level's background colour / image.
---@field drawEntityTiles boolean Draw entities' LDtk tiles (editor visuals for unspawned entities).
---@field tintColor number[] Multiplies every layer's colours.
---@field drawDebugColliders boolean Outline the generated colliders.
---@field drawDebugEntities boolean Outline entity bounds with their names.

---@alias LdtkLevelNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "enablePhysics" # boolean - Build colliders from IntGrid cells whose collision rule is Solid / One Way.
---| "spawnEntities" # boolean - Spawn the level's entities (mapped to components) when ready.
---| "parallax" # boolean - Apply the LDtk layers' parallax factors.
---| "drawBackground" # boolean - Draw the level's background colour / image.
---| "drawEntityTiles" # boolean - Draw entities' LDtk tiles (editor visuals for unspawned entities).
---| "tintColor" # number[] - Multiplies every layer's colours.
---| "drawDebugColliders" # boolean - Outline the generated colliders.
---| "drawDebugEntities" # boolean - Outline entity bounds with their names.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path LdtkLevelNodeProperty|string
---@return any
---@overload fun(self: LdtkLevelNode, path: "position"): Vec2
---@overload fun(self: LdtkLevelNode, path: "scale"): Vec2
---@overload fun(self: LdtkLevelNode, path: "rotation"): number
---@overload fun(self: LdtkLevelNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LdtkLevelNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LdtkLevelNode, path: "paused"): boolean
---@overload fun(self: LdtkLevelNode, path: "enabled"): boolean
---@overload fun(self: LdtkLevelNode, path: "enablePhysics"): boolean
---@overload fun(self: LdtkLevelNode, path: "spawnEntities"): boolean
---@overload fun(self: LdtkLevelNode, path: "parallax"): boolean
---@overload fun(self: LdtkLevelNode, path: "drawBackground"): boolean
---@overload fun(self: LdtkLevelNode, path: "drawEntityTiles"): boolean
---@overload fun(self: LdtkLevelNode, path: "tintColor"): number[]
---@overload fun(self: LdtkLevelNode, path: "drawDebugColliders"): boolean
---@overload fun(self: LdtkLevelNode, path: "drawDebugEntities"): boolean
function LdtkLevelNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path LdtkLevelNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: LdtkLevelNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LdtkLevelNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LdtkLevelNode, path: "rotation", value: number)
---@overload fun(self: LdtkLevelNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LdtkLevelNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LdtkLevelNode, path: "paused", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "enabled", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "enablePhysics", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "spawnEntities", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "parallax", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "drawBackground", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "drawEntityTiles", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "tintColor", value: number[])
---@overload fun(self: LdtkLevelNode, path: "drawDebugColliders", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "drawDebugEntities", value: boolean)
function LdtkLevelNode:set_property(path, value, y) end

---@class TileMapNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field solid boolean Build static colliders for the painted tiles.
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias TileMapNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "solid" # boolean - Build static colliders for the painted tiles.
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path TileMapNodeProperty|string
---@return any
---@overload fun(self: TileMapNode, path: "position"): Vec2
---@overload fun(self: TileMapNode, path: "scale"): Vec2
---@overload fun(self: TileMapNode, path: "rotation"): number
---@overload fun(self: TileMapNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TileMapNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TileMapNode, path: "paused"): boolean
---@overload fun(self: TileMapNode, path: "enabled"): boolean
---@overload fun(self: TileMapNode, path: "solid"): boolean
---@overload fun(self: TileMapNode, path: "tint"): number[]
function TileMapNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path TileMapNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: TileMapNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TileMapNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TileMapNode, path: "rotation", value: number)
---@overload fun(self: TileMapNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TileMapNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TileMapNode, path: "paused", value: boolean)
---@overload fun(self: TileMapNode, path: "enabled", value: boolean)
---@overload fun(self: TileMapNode, path: "solid", value: boolean)
---@overload fun(self: TileMapNode, path: "tint", value: number[])
function TileMapNode:set_property(path, value, y) end

---@class LightNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field kind "Point"|"Spot" Point: shines all round. Spot: a cone along the node's rotation.
---@field color number[] Colour of the light.
---@field energy number Brightness multiplier.
---@field radius number Reach of the light (px).
---@field falloff number Fade towards the edge: 1 linear, 2 smooth, higher = tighter.
---@field spread number Spot: half-angle of the cone (degrees).
---@field shadows boolean Cast shadows from the scene's physics shapes (bodies, LDtk and tile map colliders; not ...

---@alias LightNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "kind" # "Point"|"Spot" - Point: shines all round. Spot: a cone along the node's rotation.
---| "color" # number[] - Colour of the light.
---| "energy" # number - Brightness multiplier.
---| "radius" # number - Reach of the light (px).
---| "falloff" # number - Fade towards the edge: 1 linear, 2 smooth, higher = tighter.
---| "spread" # number - Spot: half-angle of the cone (degrees).
---| "shadows" # boolean - Cast shadows from the scene's physics shapes (bodies, LDtk and tile map colliders; not ...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path LightNodeProperty|string
---@return any
---@overload fun(self: LightNode, path: "position"): Vec2
---@overload fun(self: LightNode, path: "scale"): Vec2
---@overload fun(self: LightNode, path: "rotation"): number
---@overload fun(self: LightNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LightNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LightNode, path: "paused"): boolean
---@overload fun(self: LightNode, path: "enabled"): boolean
---@overload fun(self: LightNode, path: "kind"): "Point"|"Spot"
---@overload fun(self: LightNode, path: "color"): number[]
---@overload fun(self: LightNode, path: "energy"): number
---@overload fun(self: LightNode, path: "radius"): number
---@overload fun(self: LightNode, path: "falloff"): number
---@overload fun(self: LightNode, path: "spread"): number
---@overload fun(self: LightNode, path: "shadows"): boolean
function LightNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path LightNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: LightNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LightNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LightNode, path: "rotation", value: number)
---@overload fun(self: LightNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LightNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LightNode, path: "paused", value: boolean)
---@overload fun(self: LightNode, path: "enabled", value: boolean)
---@overload fun(self: LightNode, path: "kind", value: "Point"|"Spot")
---@overload fun(self: LightNode, path: "color", value: number[])
---@overload fun(self: LightNode, path: "energy", value: number)
---@overload fun(self: LightNode, path: "radius", value: number)
---@overload fun(self: LightNode, path: "falloff", value: number)
---@overload fun(self: LightNode, path: "spread", value: number)
---@overload fun(self: LightNode, path: "shadows", value: boolean)
function LightNode:set_property(path, value, y) end

---@class JointNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field debugColor number[] Colour of the line drawn between the anchors.

---@alias JointNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "joint.type" # "Distance"|"Filter"|"Motor"|"Mouse"|"Prismatic"|"Revolute"|"Weld"|"Wheel" - Kind of joint; only that kind's settings are shown.
---| "joint.distance.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.distance.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.distance.length" # number - Rest distance between the anchors (px).
---| "joint.distance.enableSpring" # boolean - Make the joint springy instead of rigid.
---| "joint.distance.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.distance.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.distance.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.distance.minLength" # number - Shortest the joint may get (px; with the limit on).
---| "joint.distance.maxLength" # number - Longest the joint may get (px; with the limit on).
---| "joint.distance.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.distance.maxMotorForce" # number - Strongest push the motor applies (pixel-scale bodies are heavy: mass ~ area in px²).
---| "joint.distance.motorSpeed" # number - Speed the motor lengthens (+) or shortens (-) the joint (px/s).
---| "joint.distance.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.motor.linearOffset" # Vec2 - Where body B is driven to, relative to body A (px).
---| "joint.motor.angularOffset" # number - Angle body B is driven to, relative to body A (degrees).
---| "joint.motor.maxForce" # number - Strongest pull towards the offset (pixel-scale bodies are heavy).
---| "joint.motor.maxTorque" # number - Strongest twist towards the angle (pixel-scale bodies are heavy).
---| "joint.motor.correctionFactor" # number - How quickly position errors are corrected (0-1).
---| "joint.motor.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.mouse.target" # Vec2 - World point the body is pulled to (px).
---| "joint.mouse.hertz" # number - Stiffness of the pull (Hz).
---| "joint.mouse.dampingRatio" # number - Damping of the pull: 1 = no overshoot.
---| "joint.mouse.maxForce" # number - Strongest pull applied.
---| "joint.mouse.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.prismatic.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.prismatic.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.prismatic.localAxisA" # Vec2 - Direction body B slides along, in body A's space.
---| "joint.prismatic.referenceAngle" # number - Body B's angle relative to body A that counts as zero (degrees).
---| "joint.prismatic.targetTranslation" # number - Position the spring pulls to along the axis (px).
---| "joint.prismatic.enableSpring" # boolean - Make the joint springy instead of rigid.
---| "joint.prismatic.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.prismatic.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.prismatic.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.prismatic.lowerTranslation" # number - Furthest back along the axis (px; with the limit on).
---| "joint.prismatic.upperTranslation" # number - Furthest forward along the axis (px; with the limit on).
---| "joint.prismatic.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.prismatic.maxMotorForce" # number - Strongest push the motor applies (pixel-scale bodies are heavy).
---| "joint.prismatic.motorSpeed" # number - Sliding speed the motor drives (px/s).
---| "joint.prismatic.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.revolute.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.revolute.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.revolute.referenceAngle" # number - Body B's angle relative to body A that counts as zero (degrees).
---| "joint.revolute.targetAngle" # number - Angle the spring pulls to (degrees).
---| "joint.revolute.enableSpring" # boolean - Make the joint springy instead of rigid.
---| "joint.revolute.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.revolute.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.revolute.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.revolute.lowerAngle" # number - Smallest angle (degrees; with the limit on).
---| "joint.revolute.upperAngle" # number - Largest angle (degrees; with the limit on).
---| "joint.revolute.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.revolute.maxMotorTorque" # number - Strongest twist the motor applies (pixel-scale bodies are heavy).
---| "joint.revolute.motorSpeed" # number - Spin speed the motor drives (radians/s).
---| "joint.revolute.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.weld.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.weld.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.weld.referenceAngle" # number - Body B's angle relative to body A that counts as zero (degrees).
---| "joint.weld.linearHertz" # number - Positional softness (Hz); 0 = rigid.
---| "joint.weld.angularHertz" # number - Angular softness (Hz); 0 = rigid.
---| "joint.weld.linearDampingRatio" # number - Damping of the positional softness.
---| "joint.weld.angularDampingRatio" # number - Damping of the angular softness.
---| "joint.weld.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.wheel.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.wheel.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.wheel.localAxisA" # Vec2 - Suspension direction, in body A's space.
---| "joint.wheel.enableSpring" # boolean - Springy suspension along the axis.
---| "joint.wheel.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.wheel.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.wheel.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.wheel.lowerTranslation" # number - Suspension's lowest travel (px; with the limit on).
---| "joint.wheel.upperTranslation" # number - Suspension's highest travel (px; with the limit on).
---| "joint.wheel.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.wheel.maxMotorTorque" # number - Strongest twist the wheel motor applies (pixel-scale bodies are heavy).
---| "joint.wheel.motorSpeed" # number - Wheel spin speed the motor drives (radians/s).
---| "joint.wheel.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "debugColor" # number[] - Colour of the line drawn between the anchors.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path JointNodeProperty|string
---@return any
---@overload fun(self: JointNode, path: "position"): Vec2
---@overload fun(self: JointNode, path: "scale"): Vec2
---@overload fun(self: JointNode, path: "rotation"): number
---@overload fun(self: JointNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: JointNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: JointNode, path: "paused"): boolean
---@overload fun(self: JointNode, path: "enabled"): boolean
---@overload fun(self: JointNode, path: "joint.type"): "Distance"|"Filter"|"Motor"|"Mouse"|"Prismatic"|"Revolute"|"Weld"|"Wheel"
---@overload fun(self: JointNode, path: "joint.distance.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.distance.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.distance.length"): number
---@overload fun(self: JointNode, path: "joint.distance.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.distance.hertz"): number
---@overload fun(self: JointNode, path: "joint.distance.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.distance.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.distance.minLength"): number
---@overload fun(self: JointNode, path: "joint.distance.maxLength"): number
---@overload fun(self: JointNode, path: "joint.distance.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.distance.maxMotorForce"): number
---@overload fun(self: JointNode, path: "joint.distance.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.distance.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.motor.linearOffset"): Vec2
---@overload fun(self: JointNode, path: "joint.motor.angularOffset"): number
---@overload fun(self: JointNode, path: "joint.motor.maxForce"): number
---@overload fun(self: JointNode, path: "joint.motor.maxTorque"): number
---@overload fun(self: JointNode, path: "joint.motor.correctionFactor"): number
---@overload fun(self: JointNode, path: "joint.motor.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.mouse.target"): Vec2
---@overload fun(self: JointNode, path: "joint.mouse.hertz"): number
---@overload fun(self: JointNode, path: "joint.mouse.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.mouse.maxForce"): number
---@overload fun(self: JointNode, path: "joint.mouse.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.prismatic.localAxisA"): Vec2
---@overload fun(self: JointNode, path: "joint.prismatic.referenceAngle"): number
---@overload fun(self: JointNode, path: "joint.prismatic.targetTranslation"): number
---@overload fun(self: JointNode, path: "joint.prismatic.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.hertz"): number
---@overload fun(self: JointNode, path: "joint.prismatic.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.prismatic.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.lowerTranslation"): number
---@overload fun(self: JointNode, path: "joint.prismatic.upperTranslation"): number
---@overload fun(self: JointNode, path: "joint.prismatic.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.maxMotorForce"): number
---@overload fun(self: JointNode, path: "joint.prismatic.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.prismatic.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.revolute.referenceAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.targetAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.hertz"): number
---@overload fun(self: JointNode, path: "joint.revolute.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.revolute.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.lowerAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.upperAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.maxMotorTorque"): number
---@overload fun(self: JointNode, path: "joint.revolute.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.revolute.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.weld.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.weld.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.weld.referenceAngle"): number
---@overload fun(self: JointNode, path: "joint.weld.linearHertz"): number
---@overload fun(self: JointNode, path: "joint.weld.angularHertz"): number
---@overload fun(self: JointNode, path: "joint.weld.linearDampingRatio"): number
---@overload fun(self: JointNode, path: "joint.weld.angularDampingRatio"): number
---@overload fun(self: JointNode, path: "joint.weld.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.wheel.localAxisA"): Vec2
---@overload fun(self: JointNode, path: "joint.wheel.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.hertz"): number
---@overload fun(self: JointNode, path: "joint.wheel.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.wheel.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.lowerTranslation"): number
---@overload fun(self: JointNode, path: "joint.wheel.upperTranslation"): number
---@overload fun(self: JointNode, path: "joint.wheel.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.maxMotorTorque"): number
---@overload fun(self: JointNode, path: "joint.wheel.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.wheel.collideConnected"): boolean
---@overload fun(self: JointNode, path: "debugColor"): number[]
function JointNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path JointNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: JointNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "rotation", value: number)
---@overload fun(self: JointNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: JointNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: JointNode, path: "paused", value: boolean)
---@overload fun(self: JointNode, path: "enabled", value: boolean)
---@overload fun(self: JointNode, path: "joint.type", value: "Distance"|"Filter"|"Motor"|"Mouse"|"Prismatic"|"Revolute"|"Weld"|"Wheel")
---@overload fun(self: JointNode, path: "joint.distance.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.distance.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.distance.length", value: number)
---@overload fun(self: JointNode, path: "joint.distance.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.distance.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.distance.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.distance.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.distance.minLength", value: number)
---@overload fun(self: JointNode, path: "joint.distance.maxLength", value: number)
---@overload fun(self: JointNode, path: "joint.distance.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.distance.maxMotorForce", value: number)
---@overload fun(self: JointNode, path: "joint.distance.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.distance.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.motor.linearOffset", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.motor.angularOffset", value: number)
---@overload fun(self: JointNode, path: "joint.motor.maxForce", value: number)
---@overload fun(self: JointNode, path: "joint.motor.maxTorque", value: number)
---@overload fun(self: JointNode, path: "joint.motor.correctionFactor", value: number)
---@overload fun(self: JointNode, path: "joint.motor.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.mouse.target", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.mouse.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.mouse.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.mouse.maxForce", value: number)
---@overload fun(self: JointNode, path: "joint.mouse.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.prismatic.localAxisA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.prismatic.referenceAngle", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.targetTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.lowerTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.upperTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.maxMotorForce", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.revolute.referenceAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.targetAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.lowerAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.upperAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.maxMotorTorque", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.weld.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.weld.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.weld.referenceAngle", value: number)
---@overload fun(self: JointNode, path: "joint.weld.linearHertz", value: number)
---@overload fun(self: JointNode, path: "joint.weld.angularHertz", value: number)
---@overload fun(self: JointNode, path: "joint.weld.linearDampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.weld.angularDampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.weld.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.wheel.localAxisA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.wheel.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.lowerTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.upperTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.maxMotorTorque", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "debugColor", value: number[])
function JointNode:set_property(path, value, y) end

---@class TextNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field text string The text; rich text markup when Rich Text is on, a locale key when Localized.
---@field font string Project font (.ttf / .otf / .fnt; "" = the engine font).
---@field fontSize number Text size (px).
---@field color number[] Text colour (rich text [color] overrides it).
---@field align "Left"|"Center"|"Right" Alignment of the lines within the text block.
---@field maxWidth number Wrap lines at this width (px); 0 = only at line breaks.
---@field lineSpacing number Line height as a multiple of the font size.
---@field richText boolean Interpret [color=..] [size=..] [wave] [shake] tags.
---@field localized boolean The text is a key in the locale tables; shows the current language's translation.
---@field sdf boolean Signed-distance-field rendering: stays sharp when scaled or zoomed (vector fonts).
---@field revealSpeed number Typewriter: characters per second (0 = all at once); emits "revealed" when done.

---@alias TextNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "text" # string - The text; rich text markup when Rich Text is on, a locale key when Localized.
---| "font" # string - Project font (.ttf / .otf / .fnt; "" = the engine font).
---| "fontSize" # number - Text size (px).
---| "color" # number[] - Text colour (rich text [color] overrides it).
---| "align" # "Left"|"Center"|"Right" - Alignment of the lines within the text block.
---| "maxWidth" # number - Wrap lines at this width (px); 0 = only at line breaks.
---| "lineSpacing" # number - Line height as a multiple of the font size.
---| "richText" # boolean - Interpret [color=..] [size=..] [wave] [shake] tags.
---| "localized" # boolean - The text is a key in the locale tables; shows the current language's translation.
---| "sdf" # boolean - Signed-distance-field rendering: stays sharp when scaled or zoomed (vector fonts).
---| "revealSpeed" # number - Typewriter: characters per second (0 = all at once); emits "revealed" when done.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path TextNodeProperty|string
---@return any
---@overload fun(self: TextNode, path: "position"): Vec2
---@overload fun(self: TextNode, path: "scale"): Vec2
---@overload fun(self: TextNode, path: "rotation"): number
---@overload fun(self: TextNode, path: "origin"): Vec2
---@overload fun(self: TextNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TextNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TextNode, path: "paused"): boolean
---@overload fun(self: TextNode, path: "enabled"): boolean
---@overload fun(self: TextNode, path: "text"): string
---@overload fun(self: TextNode, path: "font"): string
---@overload fun(self: TextNode, path: "fontSize"): number
---@overload fun(self: TextNode, path: "color"): number[]
---@overload fun(self: TextNode, path: "align"): "Left"|"Center"|"Right"
---@overload fun(self: TextNode, path: "maxWidth"): number
---@overload fun(self: TextNode, path: "lineSpacing"): number
---@overload fun(self: TextNode, path: "richText"): boolean
---@overload fun(self: TextNode, path: "localized"): boolean
---@overload fun(self: TextNode, path: "sdf"): boolean
---@overload fun(self: TextNode, path: "revealSpeed"): number
function TextNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path TextNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: TextNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextNode, path: "rotation", value: number)
---@overload fun(self: TextNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TextNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TextNode, path: "paused", value: boolean)
---@overload fun(self: TextNode, path: "enabled", value: boolean)
---@overload fun(self: TextNode, path: "text", value: string)
---@overload fun(self: TextNode, path: "font", value: string)
---@overload fun(self: TextNode, path: "fontSize", value: number)
---@overload fun(self: TextNode, path: "color", value: number[])
---@overload fun(self: TextNode, path: "align", value: "Left"|"Center"|"Right")
---@overload fun(self: TextNode, path: "maxWidth", value: number)
---@overload fun(self: TextNode, path: "lineSpacing", value: number)
---@overload fun(self: TextNode, path: "richText", value: boolean)
---@overload fun(self: TextNode, path: "localized", value: boolean)
---@overload fun(self: TextNode, path: "sdf", value: boolean)
---@overload fun(self: TextNode, path: "revealSpeed", value: number)
function TextNode:set_property(path, value, y) end

---@class DialogueNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field font string Project font ("" = the engine font).
---@field fontSize number Text size (px).
---@field textColor number[] Colour of the line's text.
---@field speakerColor number[] Colour of the speaker's name.
---@field panelColor number[] Fill colour of the box.
---@field borderColor number[] Colour of the box's border.
---@field padding number Space between the border and the text (px).
---@field revealSpeed number Typewriter speed in characters per second (0 = whole lines).
---@field advanceAction string Input action that shows the rest of the line, then the next ("confirm").
---@field localized boolean Lines are keys in the locale tables (locale/*.csv).

---@alias DialogueNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "font" # string - Project font ("" = the engine font).
---| "fontSize" # number - Text size (px).
---| "textColor" # number[] - Colour of the line's text.
---| "speakerColor" # number[] - Colour of the speaker's name.
---| "panelColor" # number[] - Fill colour of the box.
---| "borderColor" # number[] - Colour of the box's border.
---| "padding" # number - Space between the border and the text (px).
---| "revealSpeed" # number - Typewriter speed in characters per second (0 = whole lines).
---| "advanceAction" # string - Input action that shows the rest of the line, then the next ("confirm").
---| "localized" # boolean - Lines are keys in the locale tables (locale/*.csv).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path DialogueNodeProperty|string
---@return any
---@overload fun(self: DialogueNode, path: "position"): Vec2
---@overload fun(self: DialogueNode, path: "scale"): Vec2
---@overload fun(self: DialogueNode, path: "rotation"): number
---@overload fun(self: DialogueNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: DialogueNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: DialogueNode, path: "paused"): boolean
---@overload fun(self: DialogueNode, path: "enabled"): boolean
---@overload fun(self: DialogueNode, path: "size"): Vec2
---@overload fun(self: DialogueNode, path: "font"): string
---@overload fun(self: DialogueNode, path: "fontSize"): number
---@overload fun(self: DialogueNode, path: "textColor"): number[]
---@overload fun(self: DialogueNode, path: "speakerColor"): number[]
---@overload fun(self: DialogueNode, path: "panelColor"): number[]
---@overload fun(self: DialogueNode, path: "borderColor"): number[]
---@overload fun(self: DialogueNode, path: "padding"): number
---@overload fun(self: DialogueNode, path: "revealSpeed"): number
---@overload fun(self: DialogueNode, path: "advanceAction"): string
---@overload fun(self: DialogueNode, path: "localized"): boolean
function DialogueNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path DialogueNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: DialogueNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: DialogueNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: DialogueNode, path: "rotation", value: number)
---@overload fun(self: DialogueNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: DialogueNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: DialogueNode, path: "paused", value: boolean)
---@overload fun(self: DialogueNode, path: "enabled", value: boolean)
---@overload fun(self: DialogueNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: DialogueNode, path: "font", value: string)
---@overload fun(self: DialogueNode, path: "fontSize", value: number)
---@overload fun(self: DialogueNode, path: "textColor", value: number[])
---@overload fun(self: DialogueNode, path: "speakerColor", value: number[])
---@overload fun(self: DialogueNode, path: "panelColor", value: number[])
---@overload fun(self: DialogueNode, path: "borderColor", value: number[])
---@overload fun(self: DialogueNode, path: "padding", value: number)
---@overload fun(self: DialogueNode, path: "revealSpeed", value: number)
---@overload fun(self: DialogueNode, path: "advanceAction", value: string)
---@overload fun(self: DialogueNode, path: "localized", value: boolean)
function DialogueNode:set_property(path, value, y) end

---@class NineSliceNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field texturePath string Texture to slice.
---@field size Vec2 Drawn size (px); the borders keep their size, the middle stretches.
---@field marginsLT Vec2 Left and top border widths (texture px).
---@field marginsRB Vec2 Right and bottom border widths (texture px).
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias NineSliceNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "texturePath" # string - Texture to slice.
---| "size" # Vec2 - Drawn size (px); the borders keep their size, the middle stretches.
---| "marginsLT" # Vec2 - Left and top border widths (texture px).
---| "marginsRB" # Vec2 - Right and bottom border widths (texture px).
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path NineSliceNodeProperty|string
---@return any
---@overload fun(self: NineSliceNode, path: "position"): Vec2
---@overload fun(self: NineSliceNode, path: "scale"): Vec2
---@overload fun(self: NineSliceNode, path: "rotation"): number
---@overload fun(self: NineSliceNode, path: "origin"): Vec2
---@overload fun(self: NineSliceNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: NineSliceNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: NineSliceNode, path: "paused"): boolean
---@overload fun(self: NineSliceNode, path: "enabled"): boolean
---@overload fun(self: NineSliceNode, path: "texturePath"): string
---@overload fun(self: NineSliceNode, path: "size"): Vec2
---@overload fun(self: NineSliceNode, path: "marginsLT"): Vec2
---@overload fun(self: NineSliceNode, path: "marginsRB"): Vec2
---@overload fun(self: NineSliceNode, path: "tint"): number[]
function NineSliceNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path NineSliceNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: NineSliceNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "rotation", value: number)
---@overload fun(self: NineSliceNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: NineSliceNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: NineSliceNode, path: "paused", value: boolean)
---@overload fun(self: NineSliceNode, path: "enabled", value: boolean)
---@overload fun(self: NineSliceNode, path: "texturePath", value: string)
---@overload fun(self: NineSliceNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "marginsLT", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "marginsRB", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "tint", value: number[])
function NineSliceNode:set_property(path, value, y) end

---@class ParallaxNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field texturePath string Background texture.
---@field factor Vec2 Movement relative to the camera: 1 moves with the world, 0 stays fixed on screen.
---@field repeatX boolean Tile horizontally to fill the view.
---@field repeatY boolean Tile vertically to fill the view.
---@field scrollSpeed Vec2 Drifts by itself (px/s; clouds).
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias ParallaxNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "texturePath" # string - Background texture.
---| "factor" # Vec2 - Movement relative to the camera: 1 moves with the world, 0 stays fixed on screen.
---| "repeatX" # boolean - Tile horizontally to fill the view.
---| "repeatY" # boolean - Tile vertically to fill the view.
---| "scrollSpeed" # Vec2 - Drifts by itself (px/s; clouds).
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path ParallaxNodeProperty|string
---@return any
---@overload fun(self: ParallaxNode, path: "position"): Vec2
---@overload fun(self: ParallaxNode, path: "scale"): Vec2
---@overload fun(self: ParallaxNode, path: "rotation"): number
---@overload fun(self: ParallaxNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: ParallaxNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: ParallaxNode, path: "paused"): boolean
---@overload fun(self: ParallaxNode, path: "enabled"): boolean
---@overload fun(self: ParallaxNode, path: "texturePath"): string
---@overload fun(self: ParallaxNode, path: "factor"): Vec2
---@overload fun(self: ParallaxNode, path: "repeatX"): boolean
---@overload fun(self: ParallaxNode, path: "repeatY"): boolean
---@overload fun(self: ParallaxNode, path: "scrollSpeed"): Vec2
---@overload fun(self: ParallaxNode, path: "tint"): number[]
function ParallaxNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path ParallaxNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: ParallaxNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "rotation", value: number)
---@overload fun(self: ParallaxNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: ParallaxNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: ParallaxNode, path: "paused", value: boolean)
---@overload fun(self: ParallaxNode, path: "enabled", value: boolean)
---@overload fun(self: ParallaxNode, path: "texturePath", value: string)
---@overload fun(self: ParallaxNode, path: "factor", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "repeatX", value: boolean)
---@overload fun(self: ParallaxNode, path: "repeatY", value: boolean)
---@overload fun(self: ParallaxNode, path: "scrollSpeed", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "tint", value: number[])
function ParallaxNode:set_property(path, value, y) end

---@class LineNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field width number Line thickness (px).
---@field color number[] Line colour.
---@field closed boolean Join the last point to the first.
---@field rounded boolean Round joints and caps.

---@alias LineNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "width" # number - Line thickness (px).
---| "color" # number[] - Line colour.
---| "closed" # boolean - Join the last point to the first.
---| "rounded" # boolean - Round joints and caps.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path LineNodeProperty|string
---@return any
---@overload fun(self: LineNode, path: "position"): Vec2
---@overload fun(self: LineNode, path: "scale"): Vec2
---@overload fun(self: LineNode, path: "rotation"): number
---@overload fun(self: LineNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LineNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LineNode, path: "paused"): boolean
---@overload fun(self: LineNode, path: "enabled"): boolean
---@overload fun(self: LineNode, path: "width"): number
---@overload fun(self: LineNode, path: "color"): number[]
---@overload fun(self: LineNode, path: "closed"): boolean
---@overload fun(self: LineNode, path: "rounded"): boolean
function LineNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path LineNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: LineNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LineNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LineNode, path: "rotation", value: number)
---@overload fun(self: LineNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LineNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LineNode, path: "paused", value: boolean)
---@overload fun(self: LineNode, path: "enabled", value: boolean)
---@overload fun(self: LineNode, path: "width", value: number)
---@overload fun(self: LineNode, path: "color", value: number[])
---@overload fun(self: LineNode, path: "closed", value: boolean)
---@overload fun(self: LineNode, path: "rounded", value: boolean)
function LineNode:set_property(path, value, y) end

---@class TrailNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field lifetime number Seconds a point of the trail lasts.
---@field width number Width at the head (it tapers to the tail; px).
---@field color number[] Colour at the head.
---@field endColor number[] Colour at the tail (fades to it).
---@field minDistance number Distance the parent must move before a new point is recorded (px).
---@field emitting boolean Record new points (off: the trail fades away).

---@alias TrailNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "lifetime" # number - Seconds a point of the trail lasts.
---| "width" # number - Width at the head (it tapers to the tail; px).
---| "color" # number[] - Colour at the head.
---| "endColor" # number[] - Colour at the tail (fades to it).
---| "minDistance" # number - Distance the parent must move before a new point is recorded (px).
---| "emitting" # boolean - Record new points (off: the trail fades away).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path TrailNodeProperty|string
---@return any
---@overload fun(self: TrailNode, path: "position"): Vec2
---@overload fun(self: TrailNode, path: "scale"): Vec2
---@overload fun(self: TrailNode, path: "rotation"): number
---@overload fun(self: TrailNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TrailNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TrailNode, path: "paused"): boolean
---@overload fun(self: TrailNode, path: "enabled"): boolean
---@overload fun(self: TrailNode, path: "lifetime"): number
---@overload fun(self: TrailNode, path: "width"): number
---@overload fun(self: TrailNode, path: "color"): number[]
---@overload fun(self: TrailNode, path: "endColor"): number[]
---@overload fun(self: TrailNode, path: "minDistance"): number
---@overload fun(self: TrailNode, path: "emitting"): boolean
function TrailNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path TrailNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: TrailNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TrailNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TrailNode, path: "rotation", value: number)
---@overload fun(self: TrailNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TrailNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TrailNode, path: "paused", value: boolean)
---@overload fun(self: TrailNode, path: "enabled", value: boolean)
---@overload fun(self: TrailNode, path: "lifetime", value: number)
---@overload fun(self: TrailNode, path: "width", value: number)
---@overload fun(self: TrailNode, path: "color", value: number[])
---@overload fun(self: TrailNode, path: "endColor", value: number[])
---@overload fun(self: TrailNode, path: "minDistance", value: number)
---@overload fun(self: TrailNode, path: "emitting", value: boolean)
function TrailNode:set_property(path, value, y) end

---@class UIContainerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field title string Header text.
---@field direction "Vertical"|"Horizontal"|"Grid" Children are laid out in a column, a row or a grid.
---@field alignment "Start"|"Center"|"End"|"Stretch" Where children sit across the layout direction.
---@field spacing number Gap between items (px).
---@field paddingTop number Space above the children (px).
---@field paddingBottom number Space below the children (px).
---@field paddingLeft number Space left of the children (px).
---@field paddingRight number Space right of the children (px).
---@field columns integer Grid layout: columns per row.
---@field autoSizeHeight boolean Grow to fit the children.
---@field drawBackground boolean Fill the background.
---@field drawBorder boolean Draw a border.
---@field showHeader boolean Draw a header with the title.
---@field headerHeight number Height of the header (px).
---@field backgroundColor number[] Fill colour of the background.
---@field headerColor number[] Header fill colour.
---@field borderColor number[] Colour of the border.
---@field titleColor number[] Title text colour.

---@alias UIContainerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "title" # string - Header text.
---| "direction" # "Vertical"|"Horizontal"|"Grid" - Children are laid out in a column, a row or a grid.
---| "alignment" # "Start"|"Center"|"End"|"Stretch" - Where children sit across the layout direction.
---| "spacing" # number - Gap between items (px).
---| "paddingTop" # number - Space above the children (px).
---| "paddingBottom" # number - Space below the children (px).
---| "paddingLeft" # number - Space left of the children (px).
---| "paddingRight" # number - Space right of the children (px).
---| "columns" # integer - Grid layout: columns per row.
---| "autoSizeHeight" # boolean - Grow to fit the children.
---| "drawBackground" # boolean - Fill the background.
---| "drawBorder" # boolean - Draw a border.
---| "showHeader" # boolean - Draw a header with the title.
---| "headerHeight" # number - Height of the header (px).
---| "backgroundColor" # number[] - Fill colour of the background.
---| "headerColor" # number[] - Header fill colour.
---| "borderColor" # number[] - Colour of the border.
---| "titleColor" # number[] - Title text colour.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIContainerNodeProperty|string
---@return any
---@overload fun(self: UIContainerNode, path: "position"): Vec2
---@overload fun(self: UIContainerNode, path: "scale"): Vec2
---@overload fun(self: UIContainerNode, path: "rotation"): number
---@overload fun(self: UIContainerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIContainerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIContainerNode, path: "paused"): boolean
---@overload fun(self: UIContainerNode, path: "enabled"): boolean
---@overload fun(self: UIContainerNode, path: "size"): Vec2
---@overload fun(self: UIContainerNode, path: "title"): string
---@overload fun(self: UIContainerNode, path: "direction"): "Vertical"|"Horizontal"|"Grid"
---@overload fun(self: UIContainerNode, path: "alignment"): "Start"|"Center"|"End"|"Stretch"
---@overload fun(self: UIContainerNode, path: "spacing"): number
---@overload fun(self: UIContainerNode, path: "paddingTop"): number
---@overload fun(self: UIContainerNode, path: "paddingBottom"): number
---@overload fun(self: UIContainerNode, path: "paddingLeft"): number
---@overload fun(self: UIContainerNode, path: "paddingRight"): number
---@overload fun(self: UIContainerNode, path: "columns"): integer
---@overload fun(self: UIContainerNode, path: "autoSizeHeight"): boolean
---@overload fun(self: UIContainerNode, path: "drawBackground"): boolean
---@overload fun(self: UIContainerNode, path: "drawBorder"): boolean
---@overload fun(self: UIContainerNode, path: "showHeader"): boolean
---@overload fun(self: UIContainerNode, path: "headerHeight"): number
---@overload fun(self: UIContainerNode, path: "backgroundColor"): number[]
---@overload fun(self: UIContainerNode, path: "headerColor"): number[]
---@overload fun(self: UIContainerNode, path: "borderColor"): number[]
---@overload fun(self: UIContainerNode, path: "titleColor"): number[]
function UIContainerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIContainerNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIContainerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIContainerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIContainerNode, path: "rotation", value: number)
---@overload fun(self: UIContainerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIContainerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIContainerNode, path: "paused", value: boolean)
---@overload fun(self: UIContainerNode, path: "enabled", value: boolean)
---@overload fun(self: UIContainerNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIContainerNode, path: "title", value: string)
---@overload fun(self: UIContainerNode, path: "direction", value: "Vertical"|"Horizontal"|"Grid")
---@overload fun(self: UIContainerNode, path: "alignment", value: "Start"|"Center"|"End"|"Stretch")
---@overload fun(self: UIContainerNode, path: "spacing", value: number)
---@overload fun(self: UIContainerNode, path: "paddingTop", value: number)
---@overload fun(self: UIContainerNode, path: "paddingBottom", value: number)
---@overload fun(self: UIContainerNode, path: "paddingLeft", value: number)
---@overload fun(self: UIContainerNode, path: "paddingRight", value: number)
---@overload fun(self: UIContainerNode, path: "columns", value: integer)
---@overload fun(self: UIContainerNode, path: "autoSizeHeight", value: boolean)
---@overload fun(self: UIContainerNode, path: "drawBackground", value: boolean)
---@overload fun(self: UIContainerNode, path: "drawBorder", value: boolean)
---@overload fun(self: UIContainerNode, path: "showHeader", value: boolean)
---@overload fun(self: UIContainerNode, path: "headerHeight", value: number)
---@overload fun(self: UIContainerNode, path: "backgroundColor", value: number[])
---@overload fun(self: UIContainerNode, path: "headerColor", value: number[])
---@overload fun(self: UIContainerNode, path: "borderColor", value: number[])
---@overload fun(self: UIContainerNode, path: "titleColor", value: number[])
function UIContainerNode:set_property(path, value, y) end

---@class UILabelNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field text string Label text.
---@field fontSize number Text size (px).
---@field textColor number[] Colour of the text.
---@field align "Left"|"Center"|"Right" Horizontal text alignment.
---@field drawBackground boolean Fill the background.
---@field backgroundColor number[] Fill colour of the background.

---@alias UILabelNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "text" # string - Label text.
---| "fontSize" # number - Text size (px).
---| "textColor" # number[] - Colour of the text.
---| "align" # "Left"|"Center"|"Right" - Horizontal text alignment.
---| "drawBackground" # boolean - Fill the background.
---| "backgroundColor" # number[] - Fill colour of the background.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UILabelNodeProperty|string
---@return any
---@overload fun(self: UILabelNode, path: "position"): Vec2
---@overload fun(self: UILabelNode, path: "scale"): Vec2
---@overload fun(self: UILabelNode, path: "rotation"): number
---@overload fun(self: UILabelNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UILabelNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UILabelNode, path: "paused"): boolean
---@overload fun(self: UILabelNode, path: "enabled"): boolean
---@overload fun(self: UILabelNode, path: "size"): Vec2
---@overload fun(self: UILabelNode, path: "text"): string
---@overload fun(self: UILabelNode, path: "fontSize"): number
---@overload fun(self: UILabelNode, path: "textColor"): number[]
---@overload fun(self: UILabelNode, path: "align"): "Left"|"Center"|"Right"
---@overload fun(self: UILabelNode, path: "drawBackground"): boolean
---@overload fun(self: UILabelNode, path: "backgroundColor"): number[]
function UILabelNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UILabelNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UILabelNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UILabelNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UILabelNode, path: "rotation", value: number)
---@overload fun(self: UILabelNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UILabelNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UILabelNode, path: "paused", value: boolean)
---@overload fun(self: UILabelNode, path: "enabled", value: boolean)
---@overload fun(self: UILabelNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UILabelNode, path: "text", value: string)
---@overload fun(self: UILabelNode, path: "fontSize", value: number)
---@overload fun(self: UILabelNode, path: "textColor", value: number[])
---@overload fun(self: UILabelNode, path: "align", value: "Left"|"Center"|"Right")
---@overload fun(self: UILabelNode, path: "drawBackground", value: boolean)
---@overload fun(self: UILabelNode, path: "backgroundColor", value: number[])
function UILabelNode:set_property(path, value, y) end

---@class UIButtonNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field text string Button caption.
---@field fontSize number Text size (px).
---@field icon "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" Icon shown (Font Awesome).
---@field iconSize number Icon size (px).
---@field normalColor number[] Fill colour at rest.
---@field hoverColor number[] Fill colour under the mouse.
---@field pressedColor number[] Fill colour while pressed.
---@field borderColor number[] Colour of the border.
---@field textColor number[] Colour of the text.
---@field align "Left"|"Center"|"Right" Horizontal text alignment.

---@alias UIButtonNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "text" # string - Button caption.
---| "fontSize" # number - Text size (px).
---| "icon" # "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" - Icon shown (Font Awesome).
---| "iconSize" # number - Icon size (px).
---| "normalColor" # number[] - Fill colour at rest.
---| "hoverColor" # number[] - Fill colour under the mouse.
---| "pressedColor" # number[] - Fill colour while pressed.
---| "borderColor" # number[] - Colour of the border.
---| "textColor" # number[] - Colour of the text.
---| "align" # "Left"|"Center"|"Right" - Horizontal text alignment.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIButtonNodeProperty|string
---@return any
---@overload fun(self: UIButtonNode, path: "position"): Vec2
---@overload fun(self: UIButtonNode, path: "scale"): Vec2
---@overload fun(self: UIButtonNode, path: "rotation"): number
---@overload fun(self: UIButtonNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIButtonNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIButtonNode, path: "paused"): boolean
---@overload fun(self: UIButtonNode, path: "enabled"): boolean
---@overload fun(self: UIButtonNode, path: "size"): Vec2
---@overload fun(self: UIButtonNode, path: "text"): string
---@overload fun(self: UIButtonNode, path: "fontSize"): number
---@overload fun(self: UIButtonNode, path: "icon"): "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut"
---@overload fun(self: UIButtonNode, path: "iconSize"): number
---@overload fun(self: UIButtonNode, path: "normalColor"): number[]
---@overload fun(self: UIButtonNode, path: "hoverColor"): number[]
---@overload fun(self: UIButtonNode, path: "pressedColor"): number[]
---@overload fun(self: UIButtonNode, path: "borderColor"): number[]
---@overload fun(self: UIButtonNode, path: "textColor"): number[]
---@overload fun(self: UIButtonNode, path: "align"): "Left"|"Center"|"Right"
function UIButtonNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIButtonNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIButtonNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIButtonNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIButtonNode, path: "rotation", value: number)
---@overload fun(self: UIButtonNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIButtonNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIButtonNode, path: "paused", value: boolean)
---@overload fun(self: UIButtonNode, path: "enabled", value: boolean)
---@overload fun(self: UIButtonNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIButtonNode, path: "text", value: string)
---@overload fun(self: UIButtonNode, path: "fontSize", value: number)
---@overload fun(self: UIButtonNode, path: "icon", value: "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut")
---@overload fun(self: UIButtonNode, path: "iconSize", value: number)
---@overload fun(self: UIButtonNode, path: "normalColor", value: number[])
---@overload fun(self: UIButtonNode, path: "hoverColor", value: number[])
---@overload fun(self: UIButtonNode, path: "pressedColor", value: number[])
---@overload fun(self: UIButtonNode, path: "borderColor", value: number[])
---@overload fun(self: UIButtonNode, path: "textColor", value: number[])
---@overload fun(self: UIButtonNode, path: "align", value: "Left"|"Center"|"Right")
function UIButtonNode:set_property(path, value, y) end

---@class UISliderNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field value number Current value (between min and max).
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field defaultValue number Value restored by reset (double-click).
---@field fineScale number Drag speed with Shift held (fine adjustment).
---@field isInteger boolean Snap to whole numbers.
---@field showResetButton boolean Show a button that restores the default value.
---@field labelWidth number Width reserved for the label (px); 0 = none.

---@alias UISliderNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "value" # number - Current value (between min and max).
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "defaultValue" # number - Value restored by reset (double-click).
---| "fineScale" # number - Drag speed with Shift held (fine adjustment).
---| "isInteger" # boolean - Snap to whole numbers.
---| "showResetButton" # boolean - Show a button that restores the default value.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UISliderNodeProperty|string
---@return any
---@overload fun(self: UISliderNode, path: "position"): Vec2
---@overload fun(self: UISliderNode, path: "scale"): Vec2
---@overload fun(self: UISliderNode, path: "rotation"): number
---@overload fun(self: UISliderNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UISliderNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UISliderNode, path: "paused"): boolean
---@overload fun(self: UISliderNode, path: "enabled"): boolean
---@overload fun(self: UISliderNode, path: "size"): Vec2
---@overload fun(self: UISliderNode, path: "label"): string
---@overload fun(self: UISliderNode, path: "value"): number
---@overload fun(self: UISliderNode, path: "minValue"): number
---@overload fun(self: UISliderNode, path: "maxValue"): number
---@overload fun(self: UISliderNode, path: "defaultValue"): number
---@overload fun(self: UISliderNode, path: "fineScale"): number
---@overload fun(self: UISliderNode, path: "isInteger"): boolean
---@overload fun(self: UISliderNode, path: "showResetButton"): boolean
---@overload fun(self: UISliderNode, path: "labelWidth"): number
function UISliderNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UISliderNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UISliderNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISliderNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISliderNode, path: "rotation", value: number)
---@overload fun(self: UISliderNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UISliderNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UISliderNode, path: "paused", value: boolean)
---@overload fun(self: UISliderNode, path: "enabled", value: boolean)
---@overload fun(self: UISliderNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISliderNode, path: "label", value: string)
---@overload fun(self: UISliderNode, path: "value", value: number)
---@overload fun(self: UISliderNode, path: "minValue", value: number)
---@overload fun(self: UISliderNode, path: "maxValue", value: number)
---@overload fun(self: UISliderNode, path: "defaultValue", value: number)
---@overload fun(self: UISliderNode, path: "fineScale", value: number)
---@overload fun(self: UISliderNode, path: "isInteger", value: boolean)
---@overload fun(self: UISliderNode, path: "showResetButton", value: boolean)
---@overload fun(self: UISliderNode, path: "labelWidth", value: number)
function UISliderNode:set_property(path, value, y) end

---@class UICheckboxNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field checked boolean Ticked now.
---@field defaultChecked boolean State restored by reset.
---@field accentColor number[] Tick and fill colour.
---@field boxSize number Box size (px).

---@alias UICheckboxNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "checked" # boolean - Ticked now.
---| "defaultChecked" # boolean - State restored by reset.
---| "accentColor" # number[] - Tick and fill colour.
---| "boxSize" # number - Box size (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UICheckboxNodeProperty|string
---@return any
---@overload fun(self: UICheckboxNode, path: "position"): Vec2
---@overload fun(self: UICheckboxNode, path: "scale"): Vec2
---@overload fun(self: UICheckboxNode, path: "rotation"): number
---@overload fun(self: UICheckboxNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UICheckboxNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UICheckboxNode, path: "paused"): boolean
---@overload fun(self: UICheckboxNode, path: "enabled"): boolean
---@overload fun(self: UICheckboxNode, path: "size"): Vec2
---@overload fun(self: UICheckboxNode, path: "label"): string
---@overload fun(self: UICheckboxNode, path: "checked"): boolean
---@overload fun(self: UICheckboxNode, path: "defaultChecked"): boolean
---@overload fun(self: UICheckboxNode, path: "accentColor"): number[]
---@overload fun(self: UICheckboxNode, path: "boxSize"): number
function UICheckboxNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UICheckboxNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UICheckboxNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UICheckboxNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UICheckboxNode, path: "rotation", value: number)
---@overload fun(self: UICheckboxNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UICheckboxNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UICheckboxNode, path: "paused", value: boolean)
---@overload fun(self: UICheckboxNode, path: "enabled", value: boolean)
---@overload fun(self: UICheckboxNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UICheckboxNode, path: "label", value: string)
---@overload fun(self: UICheckboxNode, path: "checked", value: boolean)
---@overload fun(self: UICheckboxNode, path: "defaultChecked", value: boolean)
---@overload fun(self: UICheckboxNode, path: "accentColor", value: number[])
---@overload fun(self: UICheckboxNode, path: "boxSize", value: number)
function UICheckboxNode:set_property(path, value, y) end

---@class UIProgressBarNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field value number Progress (between min and max).
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field fillColor number[] Colour of the filled part.
---@field direction "Horizontal"|"Vertical" Direction the bar fills.
---@field showText boolean Show the percentage.

---@alias UIProgressBarNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "value" # number - Progress (between min and max).
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "fillColor" # number[] - Colour of the filled part.
---| "direction" # "Horizontal"|"Vertical" - Direction the bar fills.
---| "showText" # boolean - Show the percentage.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIProgressBarNodeProperty|string
---@return any
---@overload fun(self: UIProgressBarNode, path: "position"): Vec2
---@overload fun(self: UIProgressBarNode, path: "scale"): Vec2
---@overload fun(self: UIProgressBarNode, path: "rotation"): number
---@overload fun(self: UIProgressBarNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIProgressBarNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIProgressBarNode, path: "paused"): boolean
---@overload fun(self: UIProgressBarNode, path: "enabled"): boolean
---@overload fun(self: UIProgressBarNode, path: "size"): Vec2
---@overload fun(self: UIProgressBarNode, path: "label"): string
---@overload fun(self: UIProgressBarNode, path: "value"): number
---@overload fun(self: UIProgressBarNode, path: "minValue"): number
---@overload fun(self: UIProgressBarNode, path: "maxValue"): number
---@overload fun(self: UIProgressBarNode, path: "fillColor"): number[]
---@overload fun(self: UIProgressBarNode, path: "direction"): "Horizontal"|"Vertical"
---@overload fun(self: UIProgressBarNode, path: "showText"): boolean
function UIProgressBarNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIProgressBarNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIProgressBarNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIProgressBarNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIProgressBarNode, path: "rotation", value: number)
---@overload fun(self: UIProgressBarNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIProgressBarNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIProgressBarNode, path: "paused", value: boolean)
---@overload fun(self: UIProgressBarNode, path: "enabled", value: boolean)
---@overload fun(self: UIProgressBarNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIProgressBarNode, path: "label", value: string)
---@overload fun(self: UIProgressBarNode, path: "value", value: number)
---@overload fun(self: UIProgressBarNode, path: "minValue", value: number)
---@overload fun(self: UIProgressBarNode, path: "maxValue", value: number)
---@overload fun(self: UIProgressBarNode, path: "fillColor", value: number[])
---@overload fun(self: UIProgressBarNode, path: "direction", value: "Horizontal"|"Vertical")
---@overload fun(self: UIProgressBarNode, path: "showText", value: boolean)
function UIProgressBarNode:set_property(path, value, y) end

---@class UITextInputNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field labelWidth number Width reserved for the label (px); 0 = none.
---@field maxLength integer Most characters accepted.

---@alias UITextInputNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.
---| "maxLength" # integer - Most characters accepted.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UITextInputNodeProperty|string
---@return any
---@overload fun(self: UITextInputNode, path: "position"): Vec2
---@overload fun(self: UITextInputNode, path: "scale"): Vec2
---@overload fun(self: UITextInputNode, path: "rotation"): number
---@overload fun(self: UITextInputNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITextInputNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITextInputNode, path: "paused"): boolean
---@overload fun(self: UITextInputNode, path: "enabled"): boolean
---@overload fun(self: UITextInputNode, path: "size"): Vec2
---@overload fun(self: UITextInputNode, path: "label"): string
---@overload fun(self: UITextInputNode, path: "labelWidth"): number
---@overload fun(self: UITextInputNode, path: "maxLength"): integer
function UITextInputNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UITextInputNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UITextInputNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITextInputNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITextInputNode, path: "rotation", value: number)
---@overload fun(self: UITextInputNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITextInputNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITextInputNode, path: "paused", value: boolean)
---@overload fun(self: UITextInputNode, path: "enabled", value: boolean)
---@overload fun(self: UITextInputNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITextInputNode, path: "label", value: string)
---@overload fun(self: UITextInputNode, path: "labelWidth", value: number)
---@overload fun(self: UITextInputNode, path: "maxLength", value: integer)
function UITextInputNode:set_property(path, value, y) end

---@class UIDropdownNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field defaultIndex integer Index restored by reset.
---@field labelWidth number Width reserved for the label (px); 0 = none.
---@field isOpen boolean List open now.

---@alias UIDropdownNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "defaultIndex" # integer - Index restored by reset.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.
---| "isOpen" # boolean - List open now.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIDropdownNodeProperty|string
---@return any
---@overload fun(self: UIDropdownNode, path: "position"): Vec2
---@overload fun(self: UIDropdownNode, path: "scale"): Vec2
---@overload fun(self: UIDropdownNode, path: "rotation"): number
---@overload fun(self: UIDropdownNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIDropdownNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIDropdownNode, path: "paused"): boolean
---@overload fun(self: UIDropdownNode, path: "enabled"): boolean
---@overload fun(self: UIDropdownNode, path: "size"): Vec2
---@overload fun(self: UIDropdownNode, path: "label"): string
---@overload fun(self: UIDropdownNode, path: "selectedIndex"): integer
---@overload fun(self: UIDropdownNode, path: "defaultIndex"): integer
---@overload fun(self: UIDropdownNode, path: "labelWidth"): number
---@overload fun(self: UIDropdownNode, path: "isOpen"): boolean
function UIDropdownNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIDropdownNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIDropdownNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIDropdownNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIDropdownNode, path: "rotation", value: number)
---@overload fun(self: UIDropdownNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIDropdownNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIDropdownNode, path: "paused", value: boolean)
---@overload fun(self: UIDropdownNode, path: "enabled", value: boolean)
---@overload fun(self: UIDropdownNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIDropdownNode, path: "label", value: string)
---@overload fun(self: UIDropdownNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIDropdownNode, path: "defaultIndex", value: integer)
---@overload fun(self: UIDropdownNode, path: "labelWidth", value: number)
---@overload fun(self: UIDropdownNode, path: "isOpen", value: boolean)
function UIDropdownNode:set_property(path, value, y) end

---@class UIRadioGroupNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field labelWidth number Width reserved for the label (px); 0 = none.
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field defaultIndex integer Index restored by reset.
---@field horizontal boolean Options in a row (else a column).

---@alias UIRadioGroupNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "defaultIndex" # integer - Index restored by reset.
---| "horizontal" # boolean - Options in a row (else a column).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIRadioGroupNodeProperty|string
---@return any
---@overload fun(self: UIRadioGroupNode, path: "position"): Vec2
---@overload fun(self: UIRadioGroupNode, path: "scale"): Vec2
---@overload fun(self: UIRadioGroupNode, path: "rotation"): number
---@overload fun(self: UIRadioGroupNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIRadioGroupNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIRadioGroupNode, path: "paused"): boolean
---@overload fun(self: UIRadioGroupNode, path: "enabled"): boolean
---@overload fun(self: UIRadioGroupNode, path: "size"): Vec2
---@overload fun(self: UIRadioGroupNode, path: "label"): string
---@overload fun(self: UIRadioGroupNode, path: "labelWidth"): number
---@overload fun(self: UIRadioGroupNode, path: "selectedIndex"): integer
---@overload fun(self: UIRadioGroupNode, path: "defaultIndex"): integer
---@overload fun(self: UIRadioGroupNode, path: "horizontal"): boolean
function UIRadioGroupNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIRadioGroupNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIRadioGroupNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIRadioGroupNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIRadioGroupNode, path: "rotation", value: number)
---@overload fun(self: UIRadioGroupNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIRadioGroupNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIRadioGroupNode, path: "paused", value: boolean)
---@overload fun(self: UIRadioGroupNode, path: "enabled", value: boolean)
---@overload fun(self: UIRadioGroupNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIRadioGroupNode, path: "label", value: string)
---@overload fun(self: UIRadioGroupNode, path: "labelWidth", value: number)
---@overload fun(self: UIRadioGroupNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIRadioGroupNode, path: "defaultIndex", value: integer)
---@overload fun(self: UIRadioGroupNode, path: "horizontal", value: boolean)
function UIRadioGroupNode:set_property(path, value, y) end

---@class UIToggleSwitchNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field active boolean Switched on.

---@alias UIToggleSwitchNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "active" # boolean - Switched on.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIToggleSwitchNodeProperty|string
---@return any
---@overload fun(self: UIToggleSwitchNode, path: "position"): Vec2
---@overload fun(self: UIToggleSwitchNode, path: "scale"): Vec2
---@overload fun(self: UIToggleSwitchNode, path: "rotation"): number
---@overload fun(self: UIToggleSwitchNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIToggleSwitchNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIToggleSwitchNode, path: "paused"): boolean
---@overload fun(self: UIToggleSwitchNode, path: "enabled"): boolean
---@overload fun(self: UIToggleSwitchNode, path: "size"): Vec2
---@overload fun(self: UIToggleSwitchNode, path: "label"): string
---@overload fun(self: UIToggleSwitchNode, path: "active"): boolean
function UIToggleSwitchNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIToggleSwitchNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIToggleSwitchNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToggleSwitchNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToggleSwitchNode, path: "rotation", value: number)
---@overload fun(self: UIToggleSwitchNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIToggleSwitchNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIToggleSwitchNode, path: "paused", value: boolean)
---@overload fun(self: UIToggleSwitchNode, path: "enabled", value: boolean)
---@overload fun(self: UIToggleSwitchNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToggleSwitchNode, path: "label", value: string)
---@overload fun(self: UIToggleSwitchNode, path: "active", value: boolean)
function UIToggleSwitchNode:set_property(path, value, y) end

---@class UIKnobNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field value number Current value (between min and max).
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field defaultValue number Value restored by reset (double-click).

---@alias UIKnobNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "value" # number - Current value (between min and max).
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "defaultValue" # number - Value restored by reset (double-click).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIKnobNodeProperty|string
---@return any
---@overload fun(self: UIKnobNode, path: "position"): Vec2
---@overload fun(self: UIKnobNode, path: "scale"): Vec2
---@overload fun(self: UIKnobNode, path: "rotation"): number
---@overload fun(self: UIKnobNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIKnobNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIKnobNode, path: "paused"): boolean
---@overload fun(self: UIKnobNode, path: "enabled"): boolean
---@overload fun(self: UIKnobNode, path: "size"): Vec2
---@overload fun(self: UIKnobNode, path: "label"): string
---@overload fun(self: UIKnobNode, path: "value"): number
---@overload fun(self: UIKnobNode, path: "minValue"): number
---@overload fun(self: UIKnobNode, path: "maxValue"): number
---@overload fun(self: UIKnobNode, path: "defaultValue"): number
function UIKnobNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIKnobNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIKnobNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIKnobNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIKnobNode, path: "rotation", value: number)
---@overload fun(self: UIKnobNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIKnobNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIKnobNode, path: "paused", value: boolean)
---@overload fun(self: UIKnobNode, path: "enabled", value: boolean)
---@overload fun(self: UIKnobNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIKnobNode, path: "label", value: string)
---@overload fun(self: UIKnobNode, path: "value", value: number)
---@overload fun(self: UIKnobNode, path: "minValue", value: number)
---@overload fun(self: UIKnobNode, path: "maxValue", value: number)
---@overload fun(self: UIKnobNode, path: "defaultValue", value: number)
function UIKnobNode:set_property(path, value, y) end

---@class UINotchedSliderNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field value number Current value.
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field numNotches integer Number of notch marks.
---@field snapToNotches boolean Snap the value to the notches.
---@field orientation "Horizontal"|"Vertical" Horizontal or vertical.

---@alias UINotchedSliderNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "value" # number - Current value.
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "numNotches" # integer - Number of notch marks.
---| "snapToNotches" # boolean - Snap the value to the notches.
---| "orientation" # "Horizontal"|"Vertical" - Horizontal or vertical.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UINotchedSliderNodeProperty|string
---@return any
---@overload fun(self: UINotchedSliderNode, path: "position"): Vec2
---@overload fun(self: UINotchedSliderNode, path: "scale"): Vec2
---@overload fun(self: UINotchedSliderNode, path: "rotation"): number
---@overload fun(self: UINotchedSliderNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UINotchedSliderNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UINotchedSliderNode, path: "paused"): boolean
---@overload fun(self: UINotchedSliderNode, path: "enabled"): boolean
---@overload fun(self: UINotchedSliderNode, path: "size"): Vec2
---@overload fun(self: UINotchedSliderNode, path: "label"): string
---@overload fun(self: UINotchedSliderNode, path: "value"): number
---@overload fun(self: UINotchedSliderNode, path: "minValue"): number
---@overload fun(self: UINotchedSliderNode, path: "maxValue"): number
---@overload fun(self: UINotchedSliderNode, path: "numNotches"): integer
---@overload fun(self: UINotchedSliderNode, path: "snapToNotches"): boolean
---@overload fun(self: UINotchedSliderNode, path: "orientation"): "Horizontal"|"Vertical"
function UINotchedSliderNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UINotchedSliderNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UINotchedSliderNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UINotchedSliderNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UINotchedSliderNode, path: "rotation", value: number)
---@overload fun(self: UINotchedSliderNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UINotchedSliderNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UINotchedSliderNode, path: "paused", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "enabled", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UINotchedSliderNode, path: "label", value: string)
---@overload fun(self: UINotchedSliderNode, path: "value", value: number)
---@overload fun(self: UINotchedSliderNode, path: "minValue", value: number)
---@overload fun(self: UINotchedSliderNode, path: "maxValue", value: number)
---@overload fun(self: UINotchedSliderNode, path: "numNotches", value: integer)
---@overload fun(self: UINotchedSliderNode, path: "snapToNotches", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "orientation", value: "Horizontal"|"Vertical")
function UINotchedSliderNode:set_property(path, value, y) end

---@class UIVolumeFaderNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field valueDb number Level (dB).
---@field minDb number Bottom of the fader (dB).
---@field maxDb number Top of the fader (dB).
---@field defaultDb number Level restored by reset (dB).

---@alias UIVolumeFaderNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "valueDb" # number - Level (dB).
---| "minDb" # number - Bottom of the fader (dB).
---| "maxDb" # number - Top of the fader (dB).
---| "defaultDb" # number - Level restored by reset (dB).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIVolumeFaderNodeProperty|string
---@return any
---@overload fun(self: UIVolumeFaderNode, path: "position"): Vec2
---@overload fun(self: UIVolumeFaderNode, path: "scale"): Vec2
---@overload fun(self: UIVolumeFaderNode, path: "rotation"): number
---@overload fun(self: UIVolumeFaderNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIVolumeFaderNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIVolumeFaderNode, path: "paused"): boolean
---@overload fun(self: UIVolumeFaderNode, path: "enabled"): boolean
---@overload fun(self: UIVolumeFaderNode, path: "size"): Vec2
---@overload fun(self: UIVolumeFaderNode, path: "label"): string
---@overload fun(self: UIVolumeFaderNode, path: "valueDb"): number
---@overload fun(self: UIVolumeFaderNode, path: "minDb"): number
---@overload fun(self: UIVolumeFaderNode, path: "maxDb"): number
---@overload fun(self: UIVolumeFaderNode, path: "defaultDb"): number
function UIVolumeFaderNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIVolumeFaderNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIVolumeFaderNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeFaderNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeFaderNode, path: "rotation", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIVolumeFaderNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIVolumeFaderNode, path: "paused", value: boolean)
---@overload fun(self: UIVolumeFaderNode, path: "enabled", value: boolean)
---@overload fun(self: UIVolumeFaderNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeFaderNode, path: "label", value: string)
---@overload fun(self: UIVolumeFaderNode, path: "valueDb", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "minDb", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "maxDb", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "defaultDb", value: number)
function UIVolumeFaderNode:set_property(path, value, y) end

---@class UIVolumeMeterNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Caption shown next to the control.
---@field levelL number Left channel level (dB).
---@field levelR number Right channel level (dB).
---@field minDb number Bottom of the meter (dB).
---@field maxDb number Top of the meter (dB).
---@field orientation "Vertical"|"Horizontal" Horizontal or vertical.

---@alias UIVolumeMeterNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Caption shown next to the control.
---| "levelL" # number - Left channel level (dB).
---| "levelR" # number - Right channel level (dB).
---| "minDb" # number - Bottom of the meter (dB).
---| "maxDb" # number - Top of the meter (dB).
---| "orientation" # "Vertical"|"Horizontal" - Horizontal or vertical.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIVolumeMeterNodeProperty|string
---@return any
---@overload fun(self: UIVolumeMeterNode, path: "position"): Vec2
---@overload fun(self: UIVolumeMeterNode, path: "scale"): Vec2
---@overload fun(self: UIVolumeMeterNode, path: "rotation"): number
---@overload fun(self: UIVolumeMeterNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIVolumeMeterNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIVolumeMeterNode, path: "paused"): boolean
---@overload fun(self: UIVolumeMeterNode, path: "enabled"): boolean
---@overload fun(self: UIVolumeMeterNode, path: "size"): Vec2
---@overload fun(self: UIVolumeMeterNode, path: "label"): string
---@overload fun(self: UIVolumeMeterNode, path: "levelL"): number
---@overload fun(self: UIVolumeMeterNode, path: "levelR"): number
---@overload fun(self: UIVolumeMeterNode, path: "minDb"): number
---@overload fun(self: UIVolumeMeterNode, path: "maxDb"): number
---@overload fun(self: UIVolumeMeterNode, path: "orientation"): "Vertical"|"Horizontal"
function UIVolumeMeterNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIVolumeMeterNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIVolumeMeterNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeMeterNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeMeterNode, path: "rotation", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIVolumeMeterNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIVolumeMeterNode, path: "paused", value: boolean)
---@overload fun(self: UIVolumeMeterNode, path: "enabled", value: boolean)
---@overload fun(self: UIVolumeMeterNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeMeterNode, path: "label", value: string)
---@overload fun(self: UIVolumeMeterNode, path: "levelL", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "levelR", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "minDb", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "maxDb", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "orientation", value: "Vertical"|"Horizontal")
function UIVolumeMeterNode:set_property(path, value, y) end

---@class UISeparatorNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field label string Text in the middle of the line ("" = a plain line).
---@field lineColor number[] Colour of the line.

---@alias UISeparatorNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "label" # string - Text in the middle of the line ("" = a plain line).
---| "lineColor" # number[] - Colour of the line.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UISeparatorNodeProperty|string
---@return any
---@overload fun(self: UISeparatorNode, path: "position"): Vec2
---@overload fun(self: UISeparatorNode, path: "scale"): Vec2
---@overload fun(self: UISeparatorNode, path: "rotation"): number
---@overload fun(self: UISeparatorNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UISeparatorNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UISeparatorNode, path: "paused"): boolean
---@overload fun(self: UISeparatorNode, path: "enabled"): boolean
---@overload fun(self: UISeparatorNode, path: "size"): Vec2
---@overload fun(self: UISeparatorNode, path: "label"): string
---@overload fun(self: UISeparatorNode, path: "lineColor"): number[]
function UISeparatorNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UISeparatorNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UISeparatorNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISeparatorNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISeparatorNode, path: "rotation", value: number)
---@overload fun(self: UISeparatorNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UISeparatorNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UISeparatorNode, path: "paused", value: boolean)
---@overload fun(self: UISeparatorNode, path: "enabled", value: boolean)
---@overload fun(self: UISeparatorNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISeparatorNode, path: "label", value: string)
---@overload fun(self: UISeparatorNode, path: "lineColor", value: number[])
function UISeparatorNode:set_property(path, value, y) end

---@class UIXYPlotNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field xMin number Left end of the X axis.
---@field xMax number Right end of the X axis.
---@field yMin number Bottom of the Y axis.
---@field yMax number Top of the Y axis.
---@field autoScaleX boolean Fit the X axis to the data.
---@field autoScaleY boolean Fit the Y axis to the data.
---@field showGrid boolean Draw grid lines.
---@field showPoints boolean Mark each data point.
---@field showCrosshair boolean Crosshair with the value under the mouse.
---@field lineColor number[] Colour of the line.
---@field secondaryLineColor number[] Colour of the second series.
---@field gridColor number[] Grid line colour.

---@alias UIXYPlotNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "xMin" # number - Left end of the X axis.
---| "xMax" # number - Right end of the X axis.
---| "yMin" # number - Bottom of the Y axis.
---| "yMax" # number - Top of the Y axis.
---| "autoScaleX" # boolean - Fit the X axis to the data.
---| "autoScaleY" # boolean - Fit the Y axis to the data.
---| "showGrid" # boolean - Draw grid lines.
---| "showPoints" # boolean - Mark each data point.
---| "showCrosshair" # boolean - Crosshair with the value under the mouse.
---| "lineColor" # number[] - Colour of the line.
---| "secondaryLineColor" # number[] - Colour of the second series.
---| "gridColor" # number[] - Grid line colour.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIXYPlotNodeProperty|string
---@return any
---@overload fun(self: UIXYPlotNode, path: "position"): Vec2
---@overload fun(self: UIXYPlotNode, path: "scale"): Vec2
---@overload fun(self: UIXYPlotNode, path: "rotation"): number
---@overload fun(self: UIXYPlotNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIXYPlotNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIXYPlotNode, path: "paused"): boolean
---@overload fun(self: UIXYPlotNode, path: "enabled"): boolean
---@overload fun(self: UIXYPlotNode, path: "size"): Vec2
---@overload fun(self: UIXYPlotNode, path: "xMin"): number
---@overload fun(self: UIXYPlotNode, path: "xMax"): number
---@overload fun(self: UIXYPlotNode, path: "yMin"): number
---@overload fun(self: UIXYPlotNode, path: "yMax"): number
---@overload fun(self: UIXYPlotNode, path: "autoScaleX"): boolean
---@overload fun(self: UIXYPlotNode, path: "autoScaleY"): boolean
---@overload fun(self: UIXYPlotNode, path: "showGrid"): boolean
---@overload fun(self: UIXYPlotNode, path: "showPoints"): boolean
---@overload fun(self: UIXYPlotNode, path: "showCrosshair"): boolean
---@overload fun(self: UIXYPlotNode, path: "lineColor"): number[]
---@overload fun(self: UIXYPlotNode, path: "secondaryLineColor"): number[]
---@overload fun(self: UIXYPlotNode, path: "gridColor"): number[]
function UIXYPlotNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIXYPlotNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIXYPlotNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIXYPlotNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIXYPlotNode, path: "rotation", value: number)
---@overload fun(self: UIXYPlotNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIXYPlotNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIXYPlotNode, path: "paused", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "enabled", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIXYPlotNode, path: "xMin", value: number)
---@overload fun(self: UIXYPlotNode, path: "xMax", value: number)
---@overload fun(self: UIXYPlotNode, path: "yMin", value: number)
---@overload fun(self: UIXYPlotNode, path: "yMax", value: number)
---@overload fun(self: UIXYPlotNode, path: "autoScaleX", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "autoScaleY", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "showGrid", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "showPoints", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "showCrosshair", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "lineColor", value: number[])
---@overload fun(self: UIXYPlotNode, path: "secondaryLineColor", value: number[])
---@overload fun(self: UIXYPlotNode, path: "gridColor", value: number[])
function UIXYPlotNode:set_property(path, value, y) end

---@class UIListViewNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field itemHeight number Height of each row (px).

---@alias UIListViewNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "itemHeight" # number - Height of each row (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIListViewNodeProperty|string
---@return any
---@overload fun(self: UIListViewNode, path: "position"): Vec2
---@overload fun(self: UIListViewNode, path: "scale"): Vec2
---@overload fun(self: UIListViewNode, path: "rotation"): number
---@overload fun(self: UIListViewNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIListViewNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIListViewNode, path: "paused"): boolean
---@overload fun(self: UIListViewNode, path: "enabled"): boolean
---@overload fun(self: UIListViewNode, path: "size"): Vec2
---@overload fun(self: UIListViewNode, path: "selectedIndex"): integer
---@overload fun(self: UIListViewNode, path: "itemHeight"): number
function UIListViewNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIListViewNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIListViewNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIListViewNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIListViewNode, path: "rotation", value: number)
---@overload fun(self: UIListViewNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIListViewNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIListViewNode, path: "paused", value: boolean)
---@overload fun(self: UIListViewNode, path: "enabled", value: boolean)
---@overload fun(self: UIListViewNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIListViewNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIListViewNode, path: "itemHeight", value: number)
function UIListViewNode:set_property(path, value, y) end

---@class UITreeViewNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field selectedId integer Id of the selected item (-1 = none).
---@field itemHeight number Height of each row (px).

---@alias UITreeViewNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "selectedId" # integer - Id of the selected item (-1 = none).
---| "itemHeight" # number - Height of each row (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UITreeViewNodeProperty|string
---@return any
---@overload fun(self: UITreeViewNode, path: "position"): Vec2
---@overload fun(self: UITreeViewNode, path: "scale"): Vec2
---@overload fun(self: UITreeViewNode, path: "rotation"): number
---@overload fun(self: UITreeViewNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITreeViewNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITreeViewNode, path: "paused"): boolean
---@overload fun(self: UITreeViewNode, path: "enabled"): boolean
---@overload fun(self: UITreeViewNode, path: "size"): Vec2
---@overload fun(self: UITreeViewNode, path: "selectedId"): integer
---@overload fun(self: UITreeViewNode, path: "itemHeight"): number
function UITreeViewNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UITreeViewNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UITreeViewNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITreeViewNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITreeViewNode, path: "rotation", value: number)
---@overload fun(self: UITreeViewNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITreeViewNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITreeViewNode, path: "paused", value: boolean)
---@overload fun(self: UITreeViewNode, path: "enabled", value: boolean)
---@overload fun(self: UITreeViewNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITreeViewNode, path: "selectedId", value: integer)
---@overload fun(self: UITreeViewNode, path: "itemHeight", value: number)
function UITreeViewNode:set_property(path, value, y) end

---@class UIUnorderedListNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field defaultBullet "Disc"|"Circle"|"Square"|"Dash"|"Arrow" Bullet style for items without their own.
---@field itemHeight number Height of each row (px).

---@alias UIUnorderedListNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "defaultBullet" # "Disc"|"Circle"|"Square"|"Dash"|"Arrow" - Bullet style for items without their own.
---| "itemHeight" # number - Height of each row (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIUnorderedListNodeProperty|string
---@return any
---@overload fun(self: UIUnorderedListNode, path: "position"): Vec2
---@overload fun(self: UIUnorderedListNode, path: "scale"): Vec2
---@overload fun(self: UIUnorderedListNode, path: "rotation"): number
---@overload fun(self: UIUnorderedListNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIUnorderedListNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIUnorderedListNode, path: "paused"): boolean
---@overload fun(self: UIUnorderedListNode, path: "enabled"): boolean
---@overload fun(self: UIUnorderedListNode, path: "size"): Vec2
---@overload fun(self: UIUnorderedListNode, path: "selectedIndex"): integer
---@overload fun(self: UIUnorderedListNode, path: "defaultBullet"): "Disc"|"Circle"|"Square"|"Dash"|"Arrow"
---@overload fun(self: UIUnorderedListNode, path: "itemHeight"): number
function UIUnorderedListNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIUnorderedListNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIUnorderedListNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIUnorderedListNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIUnorderedListNode, path: "rotation", value: number)
---@overload fun(self: UIUnorderedListNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIUnorderedListNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIUnorderedListNode, path: "paused", value: boolean)
---@overload fun(self: UIUnorderedListNode, path: "enabled", value: boolean)
---@overload fun(self: UIUnorderedListNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIUnorderedListNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIUnorderedListNode, path: "defaultBullet", value: "Disc"|"Circle"|"Square"|"Dash"|"Arrow")
---@overload fun(self: UIUnorderedListNode, path: "itemHeight", value: number)
function UIUnorderedListNode:set_property(path, value, y) end

---@class UIOrderedListNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field numbering "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper" Numbering style (1, a, i...).
---@field startNumber integer Number of the first item.
---@field itemHeight number Height of each row (px).

---@alias UIOrderedListNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "numbering" # "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper" - Numbering style (1, a, i...).
---| "startNumber" # integer - Number of the first item.
---| "itemHeight" # number - Height of each row (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIOrderedListNodeProperty|string
---@return any
---@overload fun(self: UIOrderedListNode, path: "position"): Vec2
---@overload fun(self: UIOrderedListNode, path: "scale"): Vec2
---@overload fun(self: UIOrderedListNode, path: "rotation"): number
---@overload fun(self: UIOrderedListNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIOrderedListNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIOrderedListNode, path: "paused"): boolean
---@overload fun(self: UIOrderedListNode, path: "enabled"): boolean
---@overload fun(self: UIOrderedListNode, path: "size"): Vec2
---@overload fun(self: UIOrderedListNode, path: "selectedIndex"): integer
---@overload fun(self: UIOrderedListNode, path: "numbering"): "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper"
---@overload fun(self: UIOrderedListNode, path: "startNumber"): integer
---@overload fun(self: UIOrderedListNode, path: "itemHeight"): number
function UIOrderedListNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIOrderedListNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIOrderedListNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIOrderedListNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIOrderedListNode, path: "rotation", value: number)
---@overload fun(self: UIOrderedListNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIOrderedListNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIOrderedListNode, path: "paused", value: boolean)
---@overload fun(self: UIOrderedListNode, path: "enabled", value: boolean)
---@overload fun(self: UIOrderedListNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIOrderedListNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIOrderedListNode, path: "numbering", value: "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper")
---@overload fun(self: UIOrderedListNode, path: "startNumber", value: integer)
---@overload fun(self: UIOrderedListNode, path: "itemHeight", value: number)
function UIOrderedListNode:set_property(path, value, y) end

---@class UITableNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field selectedRow integer Index of the selected row.
---@field sortColumn integer Column the rows are sorted by.
---@field sortAscending boolean Sort ascending (else descending).
---@field headerHeight number Height of the header (px).
---@field rowHeight number Height of each row (px).

---@alias UITableNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "selectedRow" # integer - Index of the selected row.
---| "sortColumn" # integer - Column the rows are sorted by.
---| "sortAscending" # boolean - Sort ascending (else descending).
---| "headerHeight" # number - Height of the header (px).
---| "rowHeight" # number - Height of each row (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UITableNodeProperty|string
---@return any
---@overload fun(self: UITableNode, path: "position"): Vec2
---@overload fun(self: UITableNode, path: "scale"): Vec2
---@overload fun(self: UITableNode, path: "rotation"): number
---@overload fun(self: UITableNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITableNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITableNode, path: "paused"): boolean
---@overload fun(self: UITableNode, path: "enabled"): boolean
---@overload fun(self: UITableNode, path: "size"): Vec2
---@overload fun(self: UITableNode, path: "selectedRow"): integer
---@overload fun(self: UITableNode, path: "sortColumn"): integer
---@overload fun(self: UITableNode, path: "sortAscending"): boolean
---@overload fun(self: UITableNode, path: "headerHeight"): number
---@overload fun(self: UITableNode, path: "rowHeight"): number
function UITableNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UITableNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UITableNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITableNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITableNode, path: "rotation", value: number)
---@overload fun(self: UITableNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITableNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITableNode, path: "paused", value: boolean)
---@overload fun(self: UITableNode, path: "enabled", value: boolean)
---@overload fun(self: UITableNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITableNode, path: "selectedRow", value: integer)
---@overload fun(self: UITableNode, path: "sortColumn", value: integer)
---@overload fun(self: UITableNode, path: "sortAscending", value: boolean)
---@overload fun(self: UITableNode, path: "headerHeight", value: number)
---@overload fun(self: UITableNode, path: "rowHeight", value: number)
function UITableNode:set_property(path, value, y) end

---@class UIIconNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field icon "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" Icon shown (Font Awesome).
---@field iconSize number Icon size (px).
---@field color number[] Icon colour.
---@field align "Left"|"Center"|"Right" Horizontal text alignment.

---@alias UIIconNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "icon" # "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" - Icon shown (Font Awesome).
---| "iconSize" # number - Icon size (px).
---| "color" # number[] - Icon colour.
---| "align" # "Left"|"Center"|"Right" - Horizontal text alignment.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIIconNodeProperty|string
---@return any
---@overload fun(self: UIIconNode, path: "position"): Vec2
---@overload fun(self: UIIconNode, path: "scale"): Vec2
---@overload fun(self: UIIconNode, path: "rotation"): number
---@overload fun(self: UIIconNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIIconNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIIconNode, path: "paused"): boolean
---@overload fun(self: UIIconNode, path: "enabled"): boolean
---@overload fun(self: UIIconNode, path: "size"): Vec2
---@overload fun(self: UIIconNode, path: "icon"): "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut"
---@overload fun(self: UIIconNode, path: "iconSize"): number
---@overload fun(self: UIIconNode, path: "color"): number[]
---@overload fun(self: UIIconNode, path: "align"): "Left"|"Center"|"Right"
function UIIconNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIIconNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIIconNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIIconNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIIconNode, path: "rotation", value: number)
---@overload fun(self: UIIconNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIIconNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIIconNode, path: "paused", value: boolean)
---@overload fun(self: UIIconNode, path: "enabled", value: boolean)
---@overload fun(self: UIIconNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIIconNode, path: "icon", value: "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut")
---@overload fun(self: UIIconNode, path: "iconSize", value: number)
---@overload fun(self: UIIconNode, path: "color", value: number[])
---@overload fun(self: UIIconNode, path: "align", value: "Left"|"Center"|"Right")
function UIIconNode:set_property(path, value, y) end

---@class UIToolbarNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field activeToggleId integer Id of the pressed toggle button.
---@field buttonSize Vec2 Size of each button (px).
---@field spacing number Gap between items (px).

---@alias UIToolbarNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "activeToggleId" # integer - Id of the pressed toggle button.
---| "buttonSize" # Vec2 - Size of each button (px).
---| "spacing" # number - Gap between items (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UIToolbarNodeProperty|string
---@return any
---@overload fun(self: UIToolbarNode, path: "position"): Vec2
---@overload fun(self: UIToolbarNode, path: "scale"): Vec2
---@overload fun(self: UIToolbarNode, path: "rotation"): number
---@overload fun(self: UIToolbarNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIToolbarNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIToolbarNode, path: "paused"): boolean
---@overload fun(self: UIToolbarNode, path: "enabled"): boolean
---@overload fun(self: UIToolbarNode, path: "size"): Vec2
---@overload fun(self: UIToolbarNode, path: "activeToggleId"): integer
---@overload fun(self: UIToolbarNode, path: "buttonSize"): Vec2
---@overload fun(self: UIToolbarNode, path: "spacing"): number
function UIToolbarNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UIToolbarNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UIToolbarNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "rotation", value: number)
---@overload fun(self: UIToolbarNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIToolbarNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIToolbarNode, path: "paused", value: boolean)
---@overload fun(self: UIToolbarNode, path: "enabled", value: boolean)
---@overload fun(self: UIToolbarNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "activeToggleId", value: integer)
---@overload fun(self: UIToolbarNode, path: "buttonSize", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "spacing", value: number)
function UIToolbarNode:set_property(path, value, y) end

---@class UITabContainerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field title string Header text.
---@field direction "Vertical"|"Horizontal"|"Grid" Children are laid out in a column, a row or a grid.
---@field alignment "Start"|"Center"|"End"|"Stretch" Where children sit across the layout direction.
---@field spacing number Gap between items (px).
---@field paddingTop number Space above the children (px).
---@field paddingBottom number Space below the children (px).
---@field paddingLeft number Space left of the children (px).
---@field paddingRight number Space right of the children (px).
---@field columns integer Grid layout: columns per row.
---@field autoSizeHeight boolean Grow to fit the children.
---@field drawBackground boolean Fill the background.
---@field drawBorder boolean Draw a border.
---@field showHeader boolean Draw a header with the title.
---@field headerHeight number Height of the header (px).
---@field backgroundColor number[] Fill colour of the background.
---@field headerColor number[] Header fill colour.
---@field borderColor number[] Colour of the border.
---@field titleColor number[] Title text colour.
---@field tabDirection "Horizontal"|"Vertical" Tabs along the top or the side.
---@field activeTab integer Index of the shown tab (child).
---@field tabSize number Tab height (or width when vertical; px).

---@alias UITabContainerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "title" # string - Header text.
---| "direction" # "Vertical"|"Horizontal"|"Grid" - Children are laid out in a column, a row or a grid.
---| "alignment" # "Start"|"Center"|"End"|"Stretch" - Where children sit across the layout direction.
---| "spacing" # number - Gap between items (px).
---| "paddingTop" # number - Space above the children (px).
---| "paddingBottom" # number - Space below the children (px).
---| "paddingLeft" # number - Space left of the children (px).
---| "paddingRight" # number - Space right of the children (px).
---| "columns" # integer - Grid layout: columns per row.
---| "autoSizeHeight" # boolean - Grow to fit the children.
---| "drawBackground" # boolean - Fill the background.
---| "drawBorder" # boolean - Draw a border.
---| "showHeader" # boolean - Draw a header with the title.
---| "headerHeight" # number - Height of the header (px).
---| "backgroundColor" # number[] - Fill colour of the background.
---| "headerColor" # number[] - Header fill colour.
---| "borderColor" # number[] - Colour of the border.
---| "titleColor" # number[] - Title text colour.
---| "tabDirection" # "Horizontal"|"Vertical" - Tabs along the top or the side.
---| "activeTab" # integer - Index of the shown tab (child).
---| "tabSize" # number - Tab height (or width when vertical; px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---@param path UITabContainerNodeProperty|string
---@return any
---@overload fun(self: UITabContainerNode, path: "position"): Vec2
---@overload fun(self: UITabContainerNode, path: "scale"): Vec2
---@overload fun(self: UITabContainerNode, path: "rotation"): number
---@overload fun(self: UITabContainerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITabContainerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITabContainerNode, path: "paused"): boolean
---@overload fun(self: UITabContainerNode, path: "enabled"): boolean
---@overload fun(self: UITabContainerNode, path: "size"): Vec2
---@overload fun(self: UITabContainerNode, path: "title"): string
---@overload fun(self: UITabContainerNode, path: "direction"): "Vertical"|"Horizontal"|"Grid"
---@overload fun(self: UITabContainerNode, path: "alignment"): "Start"|"Center"|"End"|"Stretch"
---@overload fun(self: UITabContainerNode, path: "spacing"): number
---@overload fun(self: UITabContainerNode, path: "paddingTop"): number
---@overload fun(self: UITabContainerNode, path: "paddingBottom"): number
---@overload fun(self: UITabContainerNode, path: "paddingLeft"): number
---@overload fun(self: UITabContainerNode, path: "paddingRight"): number
---@overload fun(self: UITabContainerNode, path: "columns"): integer
---@overload fun(self: UITabContainerNode, path: "autoSizeHeight"): boolean
---@overload fun(self: UITabContainerNode, path: "drawBackground"): boolean
---@overload fun(self: UITabContainerNode, path: "drawBorder"): boolean
---@overload fun(self: UITabContainerNode, path: "showHeader"): boolean
---@overload fun(self: UITabContainerNode, path: "headerHeight"): number
---@overload fun(self: UITabContainerNode, path: "backgroundColor"): number[]
---@overload fun(self: UITabContainerNode, path: "headerColor"): number[]
---@overload fun(self: UITabContainerNode, path: "borderColor"): number[]
---@overload fun(self: UITabContainerNode, path: "titleColor"): number[]
---@overload fun(self: UITabContainerNode, path: "tabDirection"): "Horizontal"|"Vertical"
---@overload fun(self: UITabContainerNode, path: "activeTab"): integer
---@overload fun(self: UITabContainerNode, path: "tabSize"): number
function UITabContainerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1; enums by name; "script.<name>" a field of the node's script.
---@param path UITabContainerNodeProperty|string
---@param value any
---@param y? number
---@overload fun(self: UITabContainerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITabContainerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITabContainerNode, path: "rotation", value: number)
---@overload fun(self: UITabContainerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITabContainerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITabContainerNode, path: "paused", value: boolean)
---@overload fun(self: UITabContainerNode, path: "enabled", value: boolean)
---@overload fun(self: UITabContainerNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITabContainerNode, path: "title", value: string)
---@overload fun(self: UITabContainerNode, path: "direction", value: "Vertical"|"Horizontal"|"Grid")
---@overload fun(self: UITabContainerNode, path: "alignment", value: "Start"|"Center"|"End"|"Stretch")
---@overload fun(self: UITabContainerNode, path: "spacing", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingTop", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingBottom", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingLeft", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingRight", value: number)
---@overload fun(self: UITabContainerNode, path: "columns", value: integer)
---@overload fun(self: UITabContainerNode, path: "autoSizeHeight", value: boolean)
---@overload fun(self: UITabContainerNode, path: "drawBackground", value: boolean)
---@overload fun(self: UITabContainerNode, path: "drawBorder", value: boolean)
---@overload fun(self: UITabContainerNode, path: "showHeader", value: boolean)
---@overload fun(self: UITabContainerNode, path: "headerHeight", value: number)
---@overload fun(self: UITabContainerNode, path: "backgroundColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "headerColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "borderColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "titleColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "tabDirection", value: "Horizontal"|"Vertical")
---@overload fun(self: UITabContainerNode, path: "activeTab", value: integer)
---@overload fun(self: UITabContainerNode, path: "tabSize", value: number)
function UITabContainerNode:set_property(path, value, y) end
-- node properties end

-- ----------------------------------------------------------------------------
-- DynamicBodyNode Physics Methods
-- ----------------------------------------------------------------------------

---Applies a continuous force to this node (requires DynamicBodyNode).
---
---Example: `self.node:apply_force(0, -500)`
---@param fx number Force X in Newtons
---@param fy number Force Y in Newtons
function DynamicBodyNode:apply_force(fx, fy) end

---Applies an instantaneous impulse to this node (requires DynamicBodyNode).
---
---Example: `self.node:apply_impulse(0, -300)`
---@param ix number Impulse X
---@param iy number Impulse Y
function DynamicBodyNode:apply_impulse(ix, iy) end

---Gets the linear velocity of the physics body or character mover in world units per second.
---
---Example: `local vx, vy = self.node:get_linear_velocity(); if vy > 400 then self.falling = true end`
---@return number vx Linear velocity X
---@return number vy Linear velocity Y
function DynamicBodyNode:get_linear_velocity() end

---Sets the linear velocity of the physics body or character mover directly.
---
---Example: `self.node:set_linear_velocity(200, 0)`
---@param vx number Linear velocity X
---@param vy number Linear velocity Y
function DynamicBodyNode:set_linear_velocity(vx, vy) end

---Gets the angular velocity of the physics body in degrees per second.
---
---Example: `local omega = self.node:get_angular_velocity(); if math.abs(omega) > 720 then Log.info("spinning") end`
---@return number omega Angular velocity in degrees/sec
function DynamicBodyNode:get_angular_velocity() end

---Sets the angular velocity of the physics body in degrees per second.
---
---Example: `self.node:set_angular_velocity(180)`
---@param omega number Angular velocity in degrees/sec
function DynamicBodyNode:set_angular_velocity(omega) end

---Gets the gravity scale multiplier for this physics body.
---
---Example: `local g = self.node:get_gravity_scale(); self.node:set_gravity_scale(g * 0.5)`
---@return number
function DynamicBodyNode:get_gravity_scale() end

---Sets the gravity scale multiplier for this physics body.
---
---Example: `self.node:set_gravity_scale(0)`
---@param scale number
function DynamicBodyNode:set_gravity_scale(scale) end

---Checks whether rotation is locked on this body.
---
---Example: `if not self.node:is_fixed_rotation() then self.node:set_fixed_rotation(true) end`
---@return boolean
function DynamicBodyNode:is_fixed_rotation() end

---Locks or unlocks rotation on this physics body.
---
---Example: `self.node:set_fixed_rotation(true)`
---@param fixed boolean
function DynamicBodyNode:set_fixed_rotation(fixed) end

---Sets the linear drag/damping coefficient.
---
---Example: `self.node:set_linear_damping(2.0)`
---@param damping number
function DynamicBodyNode:set_linear_damping(damping) end

---Sets the angular drag/damping coefficient.
---
---Example: `self.node:set_angular_damping(1.5)`
---@param damping number
function DynamicBodyNode:set_angular_damping(damping) end

---Checks if the physics body is awake and participating in simulation.
---
---Example: `if not self.node:is_awake() then self.node:set_awake(true) end`
---@return boolean
function DynamicBodyNode:is_awake() end

---Wakes up or puts the body to sleep.
---
---Example: `self.node:set_awake(true)`
---@param awake boolean
function DynamicBodyNode:set_awake(awake) end

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
---
---Example: `self.node:set_shader("builtin:flash")`
---@param shader BuiltinShader|string|nil
function Node:set_shader(shader) end

---Sets a shader parameter (a uniform of the shader): a number, up to four
---numbers, a table {r, g, b, a} / {x, y}, or a texture path.
---
---Example: `self.node:set_shader_param("amount", 0.8)`
---@param name string
---@param x number|number[]|string
---@param y? number
---@param z? number
---@param w? number
function Node:set_shader_param(name, x, y, z, w) end

---Gets a shader parameter (its value, else the shader's default): up to four
---numbers, or the texture path.
---
---Example: `local amount = self.node:get_shader_param("amount")`
---@param name string
---@return number|string|nil x
---@return number? y
---@return number? z
---@return number? w
function Node:get_shader_param(name) end

---Sets how the node is blended with what's behind it.
---
---Example: `self.node:set_blend_mode("additive")`
---@param mode BlendMode
function Node:set_blend_mode(mode) end

-- ----------------------------------------------------------------------------
-- LightNode Methods (2D lights; Scene.set_ambient darkens unlit areas)
-- ----------------------------------------------------------------------------

---Sets the light's colour (0..1).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_color(1.0, 0.8, 0.4)`
---@param r number
---@param g number
---@param b number
function LightNode:light_set_color(r, g, b) end

---Sets the light's energy (brightness multiplier, 0..8).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_energy(2.5)`
---@param energy number
function LightNode:light_set_energy(energy) end

---Gets the light's energy (brightness multiplier).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_energy(lamp:light_get_energy() * 0.9)`
---@return number energy
function LightNode:light_get_energy() end

---Sets the light's radius (world units).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_radius(200)`
---@param radius number
function LightNode:light_set_radius(radius) end

-- ----------------------------------------------------------------------------
-- Properties (any node) and collision layers (body nodes)
-- ----------------------------------------------------------------------------


---The node's script instance - the `self` its script sees: read or change its
---fields and call its methods (`enemy:get_script():take_damage(10)`). nil
---when the node has no script.
---
---Example: `local enemy = Scene.find_node("Enemy"); enemy:get_script():take_damage(10)`
---@return table?
function Node:get_script() end

---Pauses this node and its children (except "always" ones).
---
---Example: `Scene.find_node("Enemies"):set_paused(true)`
---@param paused boolean
function Node:set_paused(paused) end

---Checks whether the node is paused, by itself, a parent or the game.
---
---Example: `if self.node:is_paused() then return end`
---@return boolean paused By itself, a parent or the game
function Node:is_paused() end

---Sets how the node reacts to pausing: inherit from its parent, pausable, or always running.
---
---Example: `self.node:set_pause_mode("always")`
---@param mode "inherit"|"pausable"|"always"
function Node:set_pause_mode(mode) end

---Sets the text of a TextNode (restarting its typewriter), UI label or button.
---
---Example: `self.node:get_node("ScoreLabel"):set_text("Score: " .. self.score)`
---@param text string
function TextHolder:set_text(text) end

---Gets the text of a TextNode, UI label or button.
---
---Example: `local text = self.node:get_node("ScoreLabel"):get_text()`
---@return string
function TextHolder:get_text() end

---TextNode: types the text out again (revealSpeed > 0).
---
---Example: `self.node:get_node("Intro"):text_restart()`
function TextNode:text_restart() end

---@class DialogueLine
---@field speaker? string
---@field text string Rich text ([color=..] [size=..] [wave] [shake]), or a locale key when the box is localized

---DialogueNode: opens the box with these lines (strings or {speaker, text}),
---or one line: box:dialogue_show(text, speaker). Each line types out; the
---advance action (default "confirm") shows the rest, then the next line.
---Events: "line_shown"(index), "finished".
---
---Example: `local box = Scene.find_node("Dialogue"); box:dialogue_show({ { speaker = "Guard", text = "Halt!" } })`
---@param lines string|(string|DialogueLine)[]
---@param speaker? string
function DialogueNode:dialogue_show(lines, speaker) end

---Shows the rest of the line, else the next one.
---
---Example: `Scene.find_node("Dialogue"):dialogue_next()`
function DialogueNode:dialogue_next() end

---Closes the dialogue box.
---
---Example: `Scene.find_node("Dialogue"):dialogue_close()`
function DialogueNode:dialogue_close() end

---Checks whether the dialogue box is currently open.
---
---Example: `if Scene.find_node("Dialogue"):dialogue_is_open() then return end`
---@return boolean
function DialogueNode:dialogue_is_open() end

---LineNode: replaces its points (local to the node).
---
---Example: `self.node:get_node("Laser"):line_set_points({ {0, 0}, {120, 0} })`
---@param points number[][] { {x, y}, ... }
function LineNode:line_set_points(points) end

---LineNode: appends a point (local to the node).
---
---Example: `self.node:get_node("Path"):line_add_point(64, 32)`
---@param x number
---@param y number
function LineNode:line_add_point(x, y) end

---LineNode: removes every point.
---
---Example: `self.node:get_node("Path"):line_clear()`
function LineNode:line_clear() end

---TrailNode: drops the recorded ribbon (e.g. after a teleport).
---
---Example: `self.node:set_position(0, 0); self.node:get_node("Trail"):trail_clear()`
function TrailNode:trail_clear() end

---@class NavOptions
---@field diagonal? boolean 8 directions (default true); no cutting past blocked corners
---@field smooth? boolean Straighten where the line of sight is clear (default true)
---@field walkable_painted? boolean TileMap: painted tiles are the floor (default: not `solid`)

---A* path on this TileMap's or LDtk level's grid (TileMap: painted tiles
---are walls when the map is solid; LDtk: IntGrid cells whose collision rule
---is Solid). Waypoints from the start to the end, or nil when unreachable.
---
---Example: `local level = Scene.find_node("Level"); local path = level:nav_find_path(x, y, tx, ty, {diagonal = false})`
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param opts? NavOptions
---@return number[][]? path { {x, y}, ... }
function NavGrid:nav_find_path(x1, y1, x2, y2, opts) end

---Whether the grid cell at a world position is walkable.
---
---Example: `local level = Scene.find_node("Level"); if level:nav_is_walkable(tx, ty) then self.target = {tx, ty} end`
---@param x number
---@param y number
---@param opts? NavOptions
---@return boolean
function NavGrid:nav_is_walkable(x, y, opts) end


---The collision layers this body's shapes are on: project layer names
---(Project Settings > Physics), "LayerN" or numbers 1-16; several or a table.
---
---Example: `self.node:set_collision_layer("player")`
---@param ... CollisionLayer|string|integer|table
function Node:set_collision_layer(...) end

---The collision layers this body's shapes collide with.
---
---Example: `self.node:set_collision_mask("world", "enemies")`
---@param ... CollisionLayer|string|integer|table
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
---
---Example: `local sm = self.node:get_node("StateMachine"); sm:sm_set("on_floor", true)`
---@param name StateMachineParam|string
---@param value number|boolean
function StateMachineNode:sm_set(name, value) end

---Gets the value of a state machine parameter.
---
---Example: `local speed = self.node:get_node("StateMachine"):sm_get("speed")`
---@param name StateMachineParam|string
---@return number value
function StateMachineNode:sm_get(name) end

---Sets a trigger: it stays set until a transition that tests it fires.
---
---Example: `self.node:get_node("StateMachine"):sm_trigger("jump")`
---@param name StateMachineParam|string
function StateMachineNode:sm_trigger(name) end

---Switches to a state now, ignoring conditions.
---
---Example: `local ok = self.node:get_node("StateMachine"):sm_travel("hurt", 0.1)`
---@param state StateMachineState|string
---@param blend? number Crossfade seconds for the state's animation
---@return boolean ok false when there is no such state
function StateMachineNode:sm_travel(state, blend) end

---Asks to go to a state: allowed when an arrow leads there from the current state (or from Any state) and the guards agree (the current state's leave rules - leave after, interruptible, its leave conditions, can_exit_<state> - and the target's enter conditions and can_enter_<state>). The arrow's own conditions are not checked: the script decides when.
---
---Example: `local ok, why = self.node:get_node("StateMachine"):sm_request("dash")`
---@param state StateMachineState|string
---@param blend? number Crossfade seconds (default: the arrow's)
---@return boolean ok true when it changed state
---@return string? reason why not (e.g. "attack: leave after 0.4s (0.12s so far)")
function StateMachineNode:sm_request(state, blend) end

---Gets the name of the current state.
---
---Example: `if self.node:get_node("StateMachine"):sm_state() == "attack" then return end`
---@return string state The current state ("" before it starts)
function StateMachineNode:sm_state() end

---Gets the name of the state before the current one.
---
---Example: `local prev = self.node:get_node("StateMachine"):sm_previous()`
---@return string state The state before the current one
function StateMachineNode:sm_previous() end

---@class SM_Change
---@field from string The state left ("" when it started)
---@field to string The state entered
---@field time number Seconds the machine had run
---@field why string "start", "travel" or "transition N"

---The last state changes (up to 32), oldest first.
---
---Example: `for _, c in ipairs(self.node:get_node("Brain"):sm_history()) do Log.info(c.from, "->", c.to, c.why) end`
---@return SM_Change[] changes
function StateMachineNode:sm_history() end

---Gets the time in seconds spent in the current state.
---
---Example: `if self.node:get_node("StateMachine"):sm_time() > 2 then self:give_up() end`
---@return number seconds Time spent in the current state
function StateMachineNode:sm_time() end

---Starts (or restarts) in a state, or in the initial state.
---
---Example: `self.node:get_node("StateMachine"):sm_start("idle")`
---@param state? string
function StateMachineNode:sm_start(state) end

---Stops checking transitions (the current state stays).
---
---Example: `self.node:get_node("StateMachine"):sm_stop()`
function StateMachineNode:sm_stop() end

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
---
---Example: `local collided = self.node:character_move_and_slide(dt)`
---@param dt? number Defaults to the frame's delta time
---@return boolean collided
function CharacterMoverNode:character_move_and_slide(dt) end

---Gets the velocity in pixels per second (+y is down).
---
---Example: `local vx, vy = self.node:character_get_velocity(); vx = Input.get_axis("left", "right") * 200`
---@return number vx
---@return number vy
function CharacterMoverNode:character_get_velocity() end

---Sets the velocity in pixels per second (+y is down).
---
---Example: `self.node:character_set_velocity(vx, -350)`
---@param vx number
---@param vy number
function CharacterMoverNode:character_set_velocity(vx, vy) end

---Gets the gravity acting on the character: world gravity x its gravity scale.
---
---Example: `local gx, gy = self.node:character_get_gravity(); vy = vy + gy * dt`
---@return number gx
---@return number gy
function CharacterMoverNode:character_get_gravity() end

---Sets the multiplier of the world gravity for this character.
---
---Example: `self.node:character_set_gravity_scale(0.5)`
---@param scale number
function CharacterMoverNode:character_set_gravity_scale(scale) end

---Was the character standing on a floor after the last move?
---
---Example: `if self.node:character_is_on_floor() and Input.is_action_pressed("jump") then vy = -350 end`
---@return boolean
function CharacterMoverNode:character_is_on_floor() end

---Was the character touching a wall after the last move?
---
---Example: `if self.node:character_is_on_wall() then vy = math.min(vy, 60) end`
---@return boolean
function CharacterMoverNode:character_is_on_wall() end

---Was the character touching a ceiling after the last move?
---
---Example: `if self.node:character_is_on_ceiling() then vy = 0 end`
---@return boolean
function CharacterMoverNode:character_is_on_ceiling() end

---The floor's normal (0, -1 on flat ground; tilted on slopes).
---
---Example: `local nx, ny = self.node:character_get_floor_normal(); local on_slope = math.abs(nx) > 0.1`
---@return number nx
---@return number ny
function CharacterMoverNode:character_get_floor_normal() end

---The wall's normal (points away from the wall).
---
---Example: `local nx, ny = self.node:character_get_wall_normal(); self.node:character_set_velocity(nx * 250, -300)`
---@return number nx
---@return number ny
function CharacterMoverNode:character_get_wall_normal() end

---How far the last move actually went.
---
---Example: `local dx, dy = self.node:character_get_last_motion(); self.distance = self.distance + math.abs(dx)`
---@return number dx
---@return number dy
function CharacterMoverNode:character_get_last_motion() end

---"script": the script moves it with character_move_and_slide; "builtin": it moves itself.
---
---Example: `self.node:character_set_control_mode("builtin")`
---@param mode "script"|"builtin"
function CharacterMoverNode:character_set_control_mode(mode) end

---BuiltIn mode: steers the character horizontally and jumps if grounded.
---
---Example: `self.node:character_move(Input.get_axis("left", "right"), Input.is_action_pressed("jump"))`
---@param dirX number Horizontal direction (-1.0 to 1.0), times the node's max speed
---@param jump? boolean Whether to jump if grounded
function CharacterMoverNode:character_move(dirX, jump) end

---Same as character_is_on_floor().
---
---Example: `if self.node:character_is_grounded() then self.coyote = 0.1 end`
---@return boolean
function CharacterMoverNode:character_is_grounded() end

---BuiltIn mode: sets the maximum horizontal run speed.
---
---Example: `self.node:character_set_speed(220)`
---@param speed number
function CharacterMoverNode:character_set_speed(speed) end

---BuiltIn mode: sets the jump speed.
---
---Example: `self.node:character_set_jump_speed(400)`
---@param speed number
function CharacterMoverNode:character_set_jump_speed(speed) end

-- ----------------------------------------------------------------------------
-- AreaNode (Sensor Trigger) Methods
-- ----------------------------------------------------------------------------

---Checks whether any physics nodes are currently inside this sensor area.
---
---Example: `if self.node:get_node("Hitbox"):area_is_overlapping() then self:take_damage(1) end`
---@return boolean
function AreaNode:area_is_overlapping() end

---Returns the number of bodies currently overlapping this sensor area.
---
---Example: `local count = self.node:get_node("Zone"):area_get_overlap_count()`
---@return number
function AreaNode:area_get_overlap_count() end

---Returns an array of all nodes currently overlapping this sensor area.
---
---Example: `for _, n in ipairs(self.node:area_get_overlapping_nodes()) do Log.info(n:get_name()) end`
---@return Node[]
function AreaNode:area_get_overlapping_nodes() end

-- ----------------------------------------------------------------------------
-- RaycastNode Methods
-- ----------------------------------------------------------------------------

---Executes the raycast immediately against the physics world.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_cast()`
function RaycastNode:raycast_cast() end

---Checks whether the raycast is currently intersecting a physics obstacle.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_cast(); local grounded = ray:raycast_is_colliding()`
---@return boolean
function RaycastNode:raycast_is_colliding() end

---Gets the world-space intersection point of the raycast hit.
---
---Example: `local ray = self.node:get_node("Ray"); local x, y = ray:raycast_get_hit_point()`
---@return number x
---@return number y
function RaycastNode:raycast_get_hit_point() end

---Gets the world-space surface normal at the raycast intersection.
---
---Example: `local ray = self.node:get_node("Ray"); local nx, ny = ray:raycast_get_hit_normal()`
---@return number nx
---@return number ny
function RaycastNode:raycast_get_hit_normal() end

---Gets the fraction from 0.0 to 1.0 along the ray length where the hit occurred.
---
---Example: `local ray = self.node:get_node("Ray"); local dist = ray:raycast_get_hit_fraction() * 64`
---@return number fraction
function RaycastNode:raycast_get_hit_fraction() end

---Gets the Node struck by the raycast, or nil if none.
---
---Example: `local ray = self.node:get_node("Ray"); local hit = ray:raycast_get_hit_node(); if hit then Log.info(hit.name) end`
---@return Node?
function RaycastNode:raycast_get_hit_node() end

---Sets the local direction vector for the raycast node.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_set_direction(1, 0)`
---@param dx number
---@param dy number
function RaycastNode:raycast_set_direction(dx, dy) end

---Sets the maximum reach length in pixels for the raycast node.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_set_length(128)`
---@param length number
function RaycastNode:raycast_set_length(length) end

-- ----------------------------------------------------------------------------
-- ParticleEmitterNode Methods
-- ----------------------------------------------------------------------------

---Starts continuous or burst particle emission.
---
---Example: `self.node:get_node("Sparks"):particle_start()`
function ParticleEmitterNode:particle_start() end

---Stops particle emission.
---
---Example: `self.node:get_node("Sparks"):particle_stop()`
function ParticleEmitterNode:particle_stop() end

---Checks if particles are actively being emitted.
---
---Example: `local fx = self.node:get_node("Smoke"); if not fx:particle_is_emitting() then fx:particle_start() end`
---@return boolean
function ParticleEmitterNode:particle_is_emitting() end

---Sets the maximum particle pool count for this emitter.
---
---Example: `self.node:get_node("Sparks"):particle_set_amount(64)`
---@param amount integer
function ParticleEmitterNode:particle_set_amount(amount) end

---Sets the base lifetime in seconds for newly spawned particles.
---
---Example: `self.node:get_node("Sparks"):particle_set_lifetime(1.5)`
---@param lifetime number
function ParticleEmitterNode:particle_set_lifetime(lifetime) end

-- ----------------------------------------------------------------------------
-- TextureNode Methods
-- ----------------------------------------------------------------------------

---Gets the base unscaled pixel width and height of the texture.
---
---Example: `local w, h = self.node:get_node("Sprite"):texture_get_size()`
---@return number width
---@return number height
function TextureNode:texture_get_size() end

---Sets the origin (what it rotates and scales around) in pixels of the image;
---stored as a fraction of it - set_property("origin", fx, fy) takes that.
---
---Example: `local sprite = self.node:get_node("Sprite"); sprite:texture_set_origin(16, 16)`
---@param ox number Origin X in pixels
---@param oy number Origin Y in pixels
function TextureNode:texture_set_origin(ox, oy) end

---Gets the file path string from which this texture was loaded.
---
---Example: `local path = self.node:get_node("Sprite"):texture_get_path()`
---@return string
function TextureNode:texture_get_path() end

-- ----------------------------------------------------------------------------
-- AnimationPlayerNode Methods
-- ----------------------------------------------------------------------------

---Plays an animation, optionally switching to the specified animation name first.
---With `blend` > 0 the previous pose crossfades into the new animation over that many seconds.
---Event tracks fire while playing: method tracks call `self:<method>(frame)` on the
---track's target node script; sound tracks play their audio file on the key's frame.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_play("run", 0.15)`
---@param name? AnimationName|string Animation name (the project's complete)
---@param blend? number Crossfade time in seconds (default 0)
function AnimationPlayerNode:animation_play(name, blend) end

---Stops animation playback and freezes at current frame.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_stop()`
function AnimationPlayerNode:animation_stop() end

---Pauses animation playback.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_pause()`
function AnimationPlayerNode:animation_pause() end

---Resumes animation playback from the current frame.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_resume()`
function AnimationPlayerNode:animation_resume() end

---Resets the animation to the first frame.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_reset()`
function AnimationPlayerNode:animation_reset() end

---Sets playback speed in frames per second.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_set_fps(12)`
---@param fps number
function AnimationPlayerNode:animation_set_fps(fps) end

---Gets the name of the currently active animation track.
---
---Example: `local current = self.node:get_node("AnimationPlayer"):animation_get_current()`
---@return string
function AnimationPlayerNode:animation_get_current() end

-- ----------------------------------------------------------------------------
-- TimerNode Methods
-- ----------------------------------------------------------------------------

---Starts or restarts the timer from zero.
---
---Example: `local timer = self.node:get_node("Cooldown"); timer:timer_start()`
function TimerNode:timer_start() end

---Stops the timer.
---
---Example: `self.node:get_node("Cooldown"):timer_stop()`
function TimerNode:timer_stop() end

---Checks if the timer is actively running.
---
---Example: `if self.node:get_node("Cooldown"):timer_is_running() then return end`
---@return boolean
function TimerNode:timer_is_running() end

---Gets the elapsed time in seconds since start.
---
---Example: `local t = self.node:get_node("Cooldown"):timer_get_elapsed()`
---@return number
function TimerNode:timer_get_elapsed() end

---Sets the timer expiration duration in seconds.
---
---Example: `self.node:get_node("Cooldown"):timer_set_duration(0.5)`
---@param durationSec number
function TimerNode:timer_set_duration(durationSec) end

---Sets whether the timer automatically restarts upon expiring.
---
---Example: `self.node:get_node("SpawnTimer"):timer_set_loop(true)`
---@param loop boolean
function TimerNode:timer_set_loop(loop) end

-- ----------------------------------------------------------------------------
-- SoundNode & MusicNode Methods
-- ----------------------------------------------------------------------------

---Plays the sound effect associated with this SoundNode.
---
---Example: `self.node:get_node("JumpSound"):sound_play()`
function SoundNode:sound_play() end

---Stops playing the sound effect.
---
---Example: `self.node:get_node("EngineSound"):sound_stop()`
function SoundNode:sound_stop() end

---Pauses the sound effect.
---
---Example: `self.node:get_node("EngineSound"):sound_pause()`
function SoundNode:sound_pause() end

---Resumes the paused sound effect.
---
---Example: `self.node:get_node("EngineSound"):sound_resume()`
function SoundNode:sound_resume() end

---Plays or resumes the background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_play()`
function MusicNode:music_play() end

---Stops background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_stop()`
function MusicNode:music_stop() end

---Pauses background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_pause()`
function MusicNode:music_pause() end

---Resumes paused background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_resume()`
function MusicNode:music_resume() end

---Fades this MusicNode's volume to `volume` (0..1) over `seconds`, starting
---it if it isn't playing.
---
---Example: `Scene.find_node("Music"):music_fade(0, 2.0, true)`
---@param volume number
---@param seconds number
---@param stop_at_end? boolean Stop when the fade reaches 0
function MusicNode:music_fade(volume, seconds, stop_at_end) end

-- ----------------------------------------------------------------------------
-- CameraNode (Node-invoked) Methods
-- ----------------------------------------------------------------------------

---Sets the zoom level on this CameraNode.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_zoom(2.0)`
---@param zoom number
function CameraNode:camera_set_zoom(zoom) end

---Gets the configured zoom level on this CameraNode.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_zoom(cam:camera_get_zoom() * 1.1)`
---@return number
function CameraNode:camera_get_zoom() end

---Sets the target Node to follow.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_target(Scene.find_node("Player"))`
---@param target Node?
function CameraNode:camera_set_target(target) end

---Adds a node to the group this camera frames (see Camera.add_target).
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_add_target(Scene.find_node("Boss"), {weight = 2})`
---@param target Node
---@param options? CameraTargetOptions
function CameraNode:camera_add_target(target, options) end

---Takes a node out of this camera's group.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_remove_target(Scene.find_node("Boss"))`
---@param target Node
function CameraNode:camera_remove_target(target) end

---Stops this camera following anything.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_clear_targets()`
function CameraNode:camera_clear_targets() end

---The node this camera follows (single target), or nil.
---
---Example: `local cam = Scene.find_node("MainCamera"); local target = cam:camera_get_target()`
---@return Node?
function CameraNode:camera_get_target() end

---Every node this camera follows.
---
---Example: `local cam = Scene.find_node("MainCamera"); for _, t in ipairs(cam:camera_get_targets()) do Log.info(t.name) end`
---@return Node[]
function CameraNode:camera_get_targets() end

---Sets the fixed world position for the camera target.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_target_position(640, 360)`
---@param x number
---@param y number
function CameraNode:camera_set_target_position(x, y) end

---Triggers trauma screen shake on this CameraNode.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_shake(0.6, 0.3)`
---@param strength number Shake intensity (0.0 to 1.0)
---@param duration? number Duration in seconds (default 0.5)
function CameraNode:camera_shake(strength, duration) end

---Immediately cancels any active screen shake.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_stop_shake()`
function CameraNode:camera_stop_shake() end

---Checks if screen shake is currently active.
---
---Example: `local cam = Scene.find_node("MainCamera"); if not cam:camera_is_shaking() then cam:camera_shake(0.4) end`
---@return boolean
function CameraNode:camera_is_shaking() end

---Constrains camera movement within bounding rectangle limits.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_limits(0, 2560, 0, 720)`
---@param left number
---@param right number
---@param top number
---@param bottom number
function CameraNode:camera_set_limits(left, right, top, bottom) end

---Clears all bounding rectangle limits.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_clear_limits()`
function CameraNode:camera_clear_limits() end

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
---
---Example: `local lv = Scene.find_node("Level"); Log.info("In " .. lv:ldtk_get_level_identifier())`
---@return string
function LdtkLevelNode:ldtk_get_level_identifier() end

---Lists level identifiers (every level, or one world's).
---
---Example: `local lv = Scene.find_node("Level"); for _, id in ipairs(lv:ldtk_get_levels()) do Log.info(id) end`
---@param world? string
---@return string[]
function LdtkLevelNode:ldtk_get_levels(world) end

---Switches to another level (identifier or iid); colliders and entities are rebuilt.
---
---Example: `local lv = Scene.find_node("Level"); local ok = lv:ldtk_load_level("Level_2")`
---@param identifier LdtkLevel|string
---@return boolean ok
function LdtkLevelNode:ldtk_load_level(identifier) end

---Gets a level's details (the current level by default).
---
---Example: `local lv = Scene.find_node("Level"); local info = lv:ldtk_get_level(); Log.info(info.width)`
---@param level? LdtkLevel|string
---@return LdtkLevel?
function LdtkLevelNode:ldtk_get_level(level) end

---Gets the current level size in pixels.
---
---Example: `local lv = Scene.find_node("Level"); local w, h = lv:ldtk_get_level_size(); Log.info(w, h)`
---@return number width
---@return number height
function LdtkLevelNode:ldtk_get_level_size() end

---Gets a level field value (nil if absent or null).
---
---Example: `local lv = Scene.find_node("Level"); local music = lv:ldtk_get_level_field("music")`
---@param name string
---@param level? LdtkLevel|string Another level (default: the current one)
---@return any
function LdtkLevelNode:ldtk_get_level_field(name, level) end

---Gets every field of a level.
---
---Example: `local lv = Scene.find_node("Level"); local fields = lv:ldtk_get_level_fields(); Log.info(fields.music)`
---@param level? LdtkLevel|string
---@return table<string, any>
function LdtkLevelNode:ldtk_get_level_fields(level) end

---Lists a level's neighbours.
---
---Example: `local lv = Scene.find_node("Level"); for _, n in ipairs(lv:ldtk_get_neighbours()) do Log.info(n.dir) end`
---@param level? LdtkLevel|string
---@return LdtkNeighbour[]
function LdtkLevelNode:ldtk_get_neighbours(level) end

---The level at a world position (world mode: any loaded level; otherwise looked up in the world layout).
---
---Example: `local lv = Scene.find_node("Level"); local id = lv:ldtk_level_at(self.node:get_position())`
---@param x number
---@param y number
---@return string?
function LdtkLevelNode:ldtk_level_at(x, y) end

---Lists the project's worlds.
---
---Example: `local lv = Scene.find_node("Level"); for _, w in ipairs(lv:ldtk_get_worlds()) do Log.info(w.identifier) end`
---@return LdtkWorld[]
function LdtkLevelNode:ldtk_get_worlds() end

---Gets the current world identifier.
---
---Example: `local lv = Scene.find_node("Level"); local world = lv:ldtk_get_world()`
---@return string
function LdtkLevelNode:ldtk_get_world() end

---Switches world (its first level, or `level`).
---
---Example: `local lv = Scene.find_node("Level"); local ok = lv:ldtk_set_world("Dungeon", "Dungeon_Entrance")`
---@param world string
---@param level? LdtkLevel|string
---@return boolean ok
function LdtkLevelNode:ldtk_set_world(world, level) end

---World mode: every level of the world at its world position (rebuilds).
---
---Example: `local lv = Scene.find_node("Level"); lv:ldtk_set_world_mode(true)`
---@param on boolean
function LdtkLevelNode:ldtk_set_world_mode(on) end

---Returns true when world mode is on (every level of the world loaded at its world position).
---
---Example: `local lv = Scene.find_node("Level"); if not lv:ldtk_is_world_mode() then lv:ldtk_set_world_mode(true) end`
---@return boolean
function LdtkLevelNode:ldtk_is_world_mode() end

---Lists a level's layers (top first).
---
---Example: `local lv = Scene.find_node("Level"); for _, layer in ipairs(lv:ldtk_get_layers()) do Log.info(layer.type) end`
---@param level? LdtkLevel|string
---@return LdtkLayer[]
function LdtkLevelNode:ldtk_get_layers(level) end

---Shows or hides a layer (in every loaded level).
---
---Example: `local lv = Scene.find_node("Level"); lv:ldtk_set_layer_visible("Background", false)`
---@param name LdtkLayer|string
---@param visible boolean
function LdtkLevelNode:ldtk_set_layer_visible(name, visible) end

---Returns whether a layer is currently shown.
---
---Example: `local lv = Scene.find_node("Level"); lv:ldtk_set_layer_visible("Fog", not lv:ldtk_is_layer_visible("Fog"))`
---@param name LdtkLayer|string
---@return boolean
function LdtkLevelNode:ldtk_is_layer_visible(name) end

---Gets the IntGrid value at a world position (0 = empty).
---
---Example: `local lv = Scene.find_node("Level"); local v = lv:ldtk_get_int_grid("Collisions", self.node:get_position())`
---@param layer LdtkLayer|string IntGrid layer identifier, e.g. "Collisions"
---@param x number World X
---@param y number World Y
---@return integer
function LdtkLevelNode:ldtk_get_int_grid(layer, x, y) end

---Gets the identifier of the IntGrid value at a world position ("" if none / unnamed).
---
---Example: `local lv = Scene.find_node("Level"); local name = lv:ldtk_get_int_grid_name("Collisions", self.node:get_position())`
---@param layer LdtkLayer|string
---@param x number
---@param y number
---@return string
function LdtkLevelNode:ldtk_get_int_grid_name(layer, x, y) end

---Gets the IntGrid value of a cell.
---
---Example: `local lv = Scene.find_node("Level"); local v = lv:ldtk_get_int_grid_cell("Collisions", 4, 7)`
---@param layer LdtkLayer|string
---@param cx integer
---@param cy integer
---@param level? LdtkLevel|string
---@return integer
function LdtkLevelNode:ldtk_get_int_grid_cell(layer, cx, cy, level) end

---Lists an IntGrid layer's values (name, colour, collision).
---
---Example: `local lv = Scene.find_node("Level"); local values = lv:ldtk_get_int_grid_values("Collisions")`
---@param layer LdtkLayer|string
---@return LdtkIntGridValue[]
function LdtkLevelNode:ldtk_get_int_grid_values(layer) end

---World position -> layer cell.
---
---Example: `local lv = Scene.find_node("Level"); local cx, cy = lv:ldtk_world_to_cell("Collisions", self.node:get_position())`
---@param layer LdtkLayer|string
---@param x number
---@param y number
---@return integer cx
---@return integer cy
function LdtkLevelNode:ldtk_world_to_cell(layer, x, y) end

---Layer cell -> world position of its centre.
---
---Example: `local lv = Scene.find_node("Level"); self.node:set_position(lv:ldtk_cell_to_world("Collisions", 4, 7))`
---@param layer LdtkLayer|string
---@param cx integer
---@param cy integer
---@param level? LdtkLevel|string
---@return number x
---@return number y
function LdtkLevelNode:ldtk_cell_to_world(layer, cx, cy, level) end

---Collision at a world position: "solid", "one_way", "trigger" or "none", plus the layer and value name.
---
---Example: `local lv = Scene.find_node("Level"); local kind, layer, value = lv:ldtk_get_collision(self.node:get_position())`
---@param x number
---@param y number
---@return string type
---@return string? layer
---@return string|integer|nil value
function LdtkLevelNode:ldtk_get_collision(x, y) end

---The trigger areas built from IntGrid values set to Trigger ("<Layer>_<value>" -> AreaNode).
---Connect to their "body_entered" / "body_exited" events.
---
---Example: `local lv = Scene.find_node("Level"); local spikes = lv:ldtk_get_triggers()["Collisions_spikes"]`
---@return table<string, Node>
function LdtkLevelNode:ldtk_get_triggers() end

---Gets the tile of a Tiles/AutoLayer layer at a world position.
---
---Example: `local lv = Scene.find_node("Level"); local tile = lv:ldtk_get_tile("Ground", self.node:get_position())`
---@param layer LdtkLayer|string
---@param x number
---@param y number
---@return LdtkTile?
function LdtkLevelNode:ldtk_get_tile(layer, x, y) end

---Gets the enum values tagging the tile at a world position (tileset enum tags).
---
---Example: `local lv = Scene.find_node("Level"); local tags = lv:ldtk_get_tile_enums("Ground", self.node:get_position())`
---@param layer LdtkLayer|string
---@param x number
---@param y number
---@return string[]
function LdtkLevelNode:ldtk_get_tile_enums(layer, x, y) end

---Gets an enum's values (colour, tile, index).
---
---Example: `local lv = Scene.find_node("Level"); for _, v in ipairs(lv:ldtk_get_enum("ItemType") or {}) do Log.info(v.id) end`
---@param name LdtkEnumName
---@return LdtkEnumValue[]?
function LdtkLevelNode:ldtk_get_enum(name) end

---Every enum: name -> value ids.
---
---Example: `local lv = Scene.find_node("Level"); local item_types = lv:ldtk_get_enums()["ItemType"]`
---@return table<string, string[]>
function LdtkLevelNode:ldtk_get_enums() end

---Lists the loaded levels' entities, optionally only those with an identifier.
---
---Example: `local lv = Scene.find_node("Level"); for _, e in ipairs(lv:ldtk_get_entities("Enemy")) do Log.info(e.iid) end`
---@param identifier? LdtkEntity
---@return LdtkEntity[]
function LdtkLevelNode:ldtk_get_entities(identifier) end

---Lists the loaded levels' entities with a tag.
---
---Example: `local lv = Scene.find_node("Level"); local pickups = lv:ldtk_get_entities_by_tag("pickup")`
---@param tag string
---@return LdtkEntity[]
function LdtkLevelNode:ldtk_get_entities_by_tag(tag) end

---Gets an entity anywhere in the project by iid.
---
---Example: `local lv = Scene.find_node("Level"); local e = lv:ldtk_get_entity(self.target_iid)`
---@param iid string
---@return LdtkEntity?
function LdtkLevelNode:ldtk_get_entity(iid) end

---Gets the node spawned for an entity (by iid).
---
---Example: `local lv = Scene.find_node("Level"); local door = lv:ldtk_get_entity_node(self.door_iid)`
---@param iid string
---@return Node?
function LdtkLevelNode:ldtk_get_entity_node(iid) end

---Lists the project's entity definitions.
---
---Example: `local lv = Scene.find_node("Level"); local defs = lv:ldtk_get_entity_defs(); Log.info(defs[1].identifier)`
---@return LdtkEntityDef[]
function LdtkLevelNode:ldtk_get_entity_defs() end

---Lists the resolved EntityRef links between spawned entities.
---
---Example: `local lv = Scene.find_node("Level"); for _, link in ipairs(lv:ldtk_get_links()) do Log.info(link.field) end`
---@return LdtkLink[]
function LdtkLevelNode:ldtk_get_links() end

-- On any node spawned from an LDtk entity:

---The LDtk entity this node was spawned from (nil otherwise).
---
---Example: `local e = self.node:ldtk_entity(); if e then Log.info(e.identifier) end`
---@return LdtkEntity?
function LdtkLevelNode:ldtk_entity() end

---The LdtkLevelNode that spawned this node.
---
---Example: `local level = self.node:ldtk_level_node()`
---@return Node?
function LdtkLevelNode:ldtk_level_node() end

---A field of this node's entity.
---
---Example: `self.health = self.node:ldtk_field("health") or 3`
---@param name string
---@return any
function LdtkLevelNode:ldtk_field(name) end

---The node an EntityRef field points to (the first one for arrays).
---
---Example: `local door = self.node:ldtk_ref("target_door"); if door then door:set_visible(false) end`
---@param field string
---@return Node?
function LdtkLevelNode:ldtk_ref(field) end

---Nodes referenced by a field, or every reference ({field, iid, node}) without one.
---
---Example: `for _, n in ipairs(self.node:ldtk_refs("lights")) do n:set_visible(true) end`
---@param field? string
---@return Node[]|{field: string, iid: string, node: Node?}[]
function LdtkLevelNode:ldtk_refs(field) end

---Entities whose EntityRef fields point at this one.
---
---Example: `for _, r in ipairs(self.node:ldtk_referenced_by("target")) do Log.info(r.field) end`
---@param field? string
---@return {node: Node, field: string}[]
function LdtkLevelNode:ldtk_referenced_by(field) end


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
---
---Example: `local id = Tween.to(self.node, "scale", {1.2, 1.2}, 0.15, "out_quad", {loops = -1, yoyo = true})`
---@param node Node
---@param property string
---@param value number|number[]
---@param duration number Seconds
---@param ease? EaseName Default "out_quad"
---@param options? TweenOptions
---@return integer id
function TweenModule.to(node, property, value, duration, ease, options) end

---Stops a tween (it stays where it is).
---
---Example: `if self.fade_id then Tween.cancel(self.fade_id) end`
---@param id integer
---@return boolean found
function TweenModule.cancel(id) end

---Stops a node's tweens (all, or one property's).
---
---Example: `local stopped = Tween.cancel_all(self.node, "position")`
---@param node Node
---@param property? string
---@return integer count
function TweenModule.cancel_all(node, property) end

---Whether the tween with this id is still playing.
---
---Example: `if not Tween.is_running(self.bounce_id) then self.bounce_id = nil end`
---@param id integer
---@return boolean
function TweenModule.is_running(id) end

---Maps progress 0..1 through an easing curve (for your own animation).
---
---Example: `local k = Tween.ease("in_out_sine", self.elapsed / self.duration)`
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
---
---Example: `if score > Save.get("best_score", 0) then Save.set("best_score", score) end`
---@param key SaveKey|string
---@param value SaveValue
function SaveModule.set(key, value) end

---Returns the stored value for a key, or the default when the key is not set.
---
---Example: `local settings = Save.get("settings", {music = 0.8, fullscreen = false})`
---@param key SaveKey|string
---@param default? SaveValue Returned when the key isn't set
---@return SaveValue
function SaveModule.get(key, default) end

---Whether a value is stored under the key.
---
---Example: `if not Save.has("tutorial_done") then Scene.change_scene("tutorial") end`
---@param key SaveKey|string
---@return boolean
function SaveModule.has(key) end

---Removes a key from the save data.
---
---Example: `Save.delete("checkpoint")`
---@param key SaveKey|string
function SaveModule.delete(key) end

---Returns every stored key, sorted.
---
---Example: `for _, key in ipairs(Save.keys()) do Log.info(key, Save.get(key)) end`
---@return string[] keys Sorted
function SaveModule.keys() end

---Removes every key (the file is rewritten on the next flush).
---
---Example: `Save.clear(); Save.flush()`
function SaveModule.clear() end

---Writes the save file now.
---
---Example: `if not Save.flush() then Log.warn("could not write save file") end`
---@return boolean ok
function SaveModule.flush() end

---Switches to another save file (<name>.json; default "save"), writing the
---current one first. Returns the current slot.
---
---Example: `local previous = Save.slot("slot_2")`
---@param name? string
---@return string slot
function SaveModule.slot(name) end

---Returns the file path of the current save slot.
---
---Example: `Log.info("saving to", Save.path())`
---@return string path The current save file
function SaveModule.path() end

-- ============================================================================

---@class EngineModule
---Core engine statistics, frame timing, and display information.
local EngineModule = {}

---Gets current display refresh frames per second.
---
---Example: `Log.info("FPS: " .. Engine.get_fps())`
---@return integer
function EngineModule.get_fps() end

---Gets the last frame duration in seconds.
---
---Example: `local dt = Engine.get_delta_time(); self.elapsed = self.elapsed + dt`
---@return number
function EngineModule.get_delta_time() end

---Gets running time in seconds since the engine launched.
---
---Example: `local t = Engine.get_time(); self.node:set_position(self.base_x, self.base_y + math.sin(t * 2) * 8)`
---@return number
function EngineModule.get_time() end

---Gets current physical window width and height in screen pixels.
---
---Example: `local w, h = Engine.get_window_size()`
---@return integer width
---@return integer height
function EngineModule.get_window_size() end

---Gets virtual canvas reference resolution (e.g. 1280x720).
---
---Example: `local vw, vh = Engine.get_virtual_size(); self.node:set_position(vw / 2, vh / 2)`
---@return number width
---@return number height
function EngineModule.get_virtual_size() end

---Pauses the game: nodes with pause mode "pausable" (the default) stop
---updating and physics stops; "always" nodes keep running (pause menus).
---
---Example: `if Input.is_action_pressed("pause") then Engine.set_paused(not Engine.is_paused()) end`
---@param paused boolean
function EngineModule.set_paused(paused) end

---Returns whether the game is currently paused.
---
---Example: `if Engine.is_paused() then return end`
---@return boolean
function EngineModule.is_paused() end

---Fullscreen on or off: the window covers the screen at its resolution (the
---game is scaled to it) or goes back to the project's window size.
---
---Example: `if Input.is_key_pressed("F11") then Engine.set_fullscreen(not Engine.is_fullscreen()) end`
---@param on boolean
function EngineModule.set_fullscreen(on) end

---Whether the game is fullscreen.
---
---Example: `local full = Engine.is_fullscreen(); Log.info("Fullscreen: " .. tostring(full))`
---@return boolean
function EngineModule.is_fullscreen() end


---@class InputModule
---Engine input subsystem for keyboard, mouse, and mapped action queries.
---Actions are named in Settings > Project > Input (project.json "input"):
---built-in names (move_up, move_down, move_left, move_right, jump, fire,
---secondary, boost, interact, pause, confirm, cancel, custom1..4) plus any
---the project adds, each bound to keys, mouse buttons or gamepad input.
local InputModule = {}

---Checks if an action was pressed this frame (just triggered).
---
---Example: `if Input.is_action_pressed("jump") then self.vy = -self.jump_speed end`
---@param action InputAction Action name from the project's Input settings (e.g. "move_up", "fire", "jump", "dash")
---@return boolean
function InputModule.is_action_pressed(action) end

---Checks if an action is currently held down.
---
---Example: `if Input.is_action_down("fire") then self:shoot() end`
---@param action InputAction
---@return boolean
function InputModule.is_action_down(action) end

---Checks if an action was released this frame.
---
---Example: `if Input.is_action_released("jump") and self.vy < 0 then self.vy = self.vy * 0.5 end`
---@param action InputAction
---@return boolean
function InputModule.is_action_released(action) end

---Calculates a 1D axis value between -1.0 and 1.0 from negative and positive action names.
---
---Example: `local dir = Input.get_axis("move_left", "move_right"); self.vx = dir * self.speed`
---@param neg_action InputAction Action name representing negative direction (e.g. "move_left")
---@param pos_action InputAction Action name representing positive direction (e.g. "move_right")
---@return number axis Value from -1.0 to 1.0
function InputModule.get_axis(neg_action, pos_action) end

---Calculates a normalized 2D direction vector from 4 directional action inputs.
---
---Example: `local dx, dy = Input.get_vector("move_left", "move_right", "move_up", "move_down")`
---@param left? InputAction
---@param right? InputAction
---@param up? InputAction
---@param down? InputAction
---@return number x Normalized X axis
---@return number y Normalized Y axis
function InputModule.get_vector(left, right, up, down) end

-- key names begin (generated: lua_keys_definitions_test.odin)
---Keyboard keys (raylib names; also RETURN, ESC, SHIFT, CTRL, ALT and "0"-"9").
---@alias KeyName
---| "APOSTROPHE"
---| "COMMA"
---| "MINUS"
---| "PERIOD"
---| "SLASH"
---| "ZERO"
---| "ONE"
---| "TWO"
---| "THREE"
---| "FOUR"
---| "FIVE"
---| "SIX"
---| "SEVEN"
---| "EIGHT"
---| "NINE"
---| "SEMICOLON"
---| "EQUAL"
---| "A"
---| "B"
---| "C"
---| "D"
---| "E"
---| "F"
---| "G"
---| "H"
---| "I"
---| "J"
---| "K"
---| "L"
---| "M"
---| "N"
---| "O"
---| "P"
---| "Q"
---| "R"
---| "S"
---| "T"
---| "U"
---| "V"
---| "W"
---| "X"
---| "Y"
---| "Z"
---| "LEFT_BRACKET"
---| "BACKSLASH"
---| "RIGHT_BRACKET"
---| "GRAVE"
---| "SPACE"
---| "ESCAPE"
---| "ENTER"
---| "TAB"
---| "BACKSPACE"
---| "INSERT"
---| "DELETE"
---| "RIGHT"
---| "LEFT"
---| "DOWN"
---| "UP"
---| "PAGE_UP"
---| "PAGE_DOWN"
---| "HOME"
---| "END"
---| "CAPS_LOCK"
---| "SCROLL_LOCK"
---| "NUM_LOCK"
---| "PRINT_SCREEN"
---| "PAUSE"
---| "F1"
---| "F2"
---| "F3"
---| "F4"
---| "F5"
---| "F6"
---| "F7"
---| "F8"
---| "F9"
---| "F10"
---| "F11"
---| "F12"
---| "LEFT_SHIFT"
---| "LEFT_CONTROL"
---| "LEFT_ALT"
---| "LEFT_SUPER"
---| "RIGHT_SHIFT"
---| "RIGHT_CONTROL"
---| "RIGHT_ALT"
---| "RIGHT_SUPER"
---| "KB_MENU"
---| "KP_0"
---| "KP_1"
---| "KP_2"
---| "KP_3"
---| "KP_4"
---| "KP_5"
---| "KP_6"
---| "KP_7"
---| "KP_8"
---| "KP_9"
---| "KP_DECIMAL"
---| "KP_DIVIDE"
---| "KP_MULTIPLY"
---| "KP_SUBTRACT"
---| "KP_ADD"
---| "KP_ENTER"
---| "KP_EQUAL"
---| "BACK"
---| "MENU"
---| "VOLUME_UP"
---| "VOLUME_DOWN"
---| "RETURN"
---| "ESC"
---| "SHIFT"
---| "CTRL"
---| "ALT"
-- key names end

---Mouse buttons.
---@alias MouseButton "LEFT"|"RIGHT"|"MIDDLE"|"SIDE"|"EXTRA"|"FORWARD"|"BACK"

---Queries raw keyboard key press state for a single frame.
---
---Example: `if Input.is_key_pressed("F5") then Scene.reload() end`
---@param key KeyName|string Key name like "SPACE", "W", "Z", "F5", "LEFT_ALT"
---@return boolean
function InputModule.is_key_pressed(key) end

---Queries raw keyboard key held state.
---
---Example: `if Input.is_key_down("LEFT_SHIFT") then speed = speed * 2 end`
---@param key KeyName|string Key name
---@return boolean
function InputModule.is_key_down(key) end

---Queries raw keyboard key release state for a single frame.
---
---Example: `if Input.is_key_released("SPACE") then self.charging = false end`
---@param key KeyName|string Key name
---@return boolean
function InputModule.is_key_released(key) end

---Queries mouse button pressed state for a single frame.
---
---Example: `if Input.is_mouse_button_pressed("LEFT") then self:shoot() end`
---@param button MouseButton|string
---@return boolean
function InputModule.is_mouse_button_pressed(button) end

---Queries mouse button held state.
---
---Example: `if Input.is_mouse_button_down("RIGHT") then self.aiming = true end`
---@param button MouseButton|string
---@return boolean
function InputModule.is_mouse_button_down(button) end

---Queries mouse button release state for a single frame.
---
---Example: `if Input.is_mouse_button_released("LEFT") then self.dragging = false end`
---@param button MouseButton|string
---@return boolean
function InputModule.is_mouse_button_released(button) end

---Gets the current mouse cursor position in screen pixels.
---
---Example: `local mx, my = Input.get_mouse_position(); local wx, wy = Camera.screen_to_world(mx, my)`
---@return number x Mouse X
---@return number y Mouse Y
function InputModule.get_mouse_position() end

---Gets mouse wheel scroll delta for this frame.
---
---Example: `local wheel = Input.get_mouse_wheel_move(); Camera.set_zoom(Camera.get_zoom() + wheel * 0.1)`
---@return number
function InputModule.get_mouse_wheel_move() end


---@class AudioModule
---Engine audio playback and volume control.
local AudioModule = {}

---Plays a sound effect from the given file path. Calls in quick succession
---overlap (up to 4 voices per sound) instead of restarting it.
---
---Example: `Audio.play_sound("sounds/jump.wav", 0.8, 1.1)`
---@param path AudioPath|string File path, e.g. "assets/audio/laser.wav"
---@param volume? number 0..1 (default 1), times the sfx bus
---@param pitch? number Default 1
function AudioModule.play_sound(path, volume, pitch) end

---Plays a one-shot heard from a world position: quieter with distance from
---the listener (the camera, or Audio.set_listener) and panned to its side.
---
---Example: `local x, y = self.node:get_position(); Audio.play_sound_at("sounds/explosion.wav", x, y)`
---@param path AudioPath|string
---@param x number
---@param y number
---@param volume? number
function AudioModule.play_sound_at(path, x, y, volume) end

---@alias AudioBus "master"|"music"|"sfx"

---Sets a bus volume (0..1) and applies it to what's playing.
---
---Example: `Audio.set_bus_volume("music", 0.5)`
---@param bus AudioBus
---@param volume number
function AudioModule.set_bus_volume(bus, volume) end

---Returns the current volume (0..1) of an audio bus.
---
---Example: `local vol = Audio.get_bus_volume("sfx"); Audio.set_bus_volume("sfx", vol * 0.5)`
---@param bus AudioBus
---@return number volume
function AudioModule.get_bus_volume(bus) end

---A low-pass filter on the whole mix (e.g. underwater, a pause menu).
---
---Example: `Audio.set_lowpass(800)  -- muffled while the pause menu is open`
---@param hz number Cutoff in Hz; 0 turns it off
function AudioModule.set_lowpass(hz) end

---Reverb on the whole mix.
---
---Example: `Audio.set_reverb(0.4, 0.8)`
---@param mix number 0..1 (0 turns it off)
---@param size? number Room size 0..1 (default 0.5)
function AudioModule.set_reverb(mix, size) end

---Where positional sounds are heard from (nil: the current camera).
---
---Example: `Audio.set_listener(Scene.find_node("Player"))`
---@param node Node?
function AudioModule.set_listener(node) end

---Fades one MusicNode out (stopping it) while another fades in.
---
---Example: `Audio.crossfade(Scene.find_node("ExploreMusic"), Scene.find_node("BattleMusic"), 2.0)`
---@param from Node? MusicNode playing now
---@param to Node MusicNode to fade in (started if needed)
---@param seconds number
function AudioModule.crossfade(from, to, seconds) end

---Streams a music track from the given file path.
---
---Example: `Audio.play_music("music/theme.ogg", true)`
---@param path AudioPath|string File path, e.g. "assets/audio/theme.ogg"
---@param loop? boolean Whether to loop playback (default true)
function AudioModule.play_music(path, loop) end

---Stops playing the specified music stream.
---
---Example: `Audio.stop_music("music/theme.ogg")`
---@param path AudioPath|string
function AudioModule.stop_music(path) end

---Pauses playback of the specified music stream.
---
---Example: `Audio.pause_music("music/theme.ogg")`
---@param path AudioPath|string
function AudioModule.pause_music(path) end

---Resumes playback of the specified paused music stream.
---
---Example: `Audio.resume_music("music/theme.ogg")`
---@param path AudioPath|string
function AudioModule.resume_music(path) end

---Checks if the specified music stream is currently playing.
---
---Example: `if not Audio.is_music_playing("music/theme.ogg") then Audio.play_music("music/theme.ogg") end`
---@param path AudioPath|string
---@return boolean
function AudioModule.is_music_playing(path) end

---Sets volume for a specific music stream.
---
---Example: `Audio.set_music_volume("music/theme.ogg", 0.6)`
---@param path AudioPath|string
---@param volume number Volume between 0.0 and 1.0
function AudioModule.set_music_volume(path, volume) end

---Sets the global master audio volume.
---
---Example: `Audio.set_master_volume(0.75)`
---@param volume number Volume between 0.0 (silent) and 1.0 (full)
function AudioModule.set_master_volume(volume) end


---@class CameraModule
---Global camera control operating on the active scene's primary CameraNode.
local CameraModule = {}

---Gets current target world position of the camera.
---
---Example: `local cx, cy = Camera.get_target_position()`
---@return number x
---@return number y
function CameraModule.get_target_position() end

---Sets target world position for the camera.
---
---Example: `local x, y = self.node:get_position(); Camera.set_target_position(x, y)`
---@param x number
---@param y number
function CameraModule.set_target_position(x, y) end

---Sets a node for the camera to smoothly follow (nil stops following).
---A follow target picked in the Inspector is set automatically when the scene loads.
---
---Example: `Camera.set_target(Scene.find_node("Player"))`
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
---
---Example: `Camera.add_target(Scene.find_node("Boss"), {weight = 2, radius = 120})`
---@param target Node
---@param options? CameraTargetOptions
function CameraModule.add_target(target, options) end

---Takes a node out of the group.
---
---Example: `Camera.remove_target(Scene.find_node("Boss"))`
---@param target Node
function CameraModule.remove_target(target) end

---Stops following: clears the group and the follow target.
---
---Example: `Camera.clear_targets()`
function CameraModule.clear_targets() end

---The node the camera follows (single target), or nil.
---
---Example: `local target = Camera.get_target(); if target then Log.info(target.name) end`
---@return Node?
function CameraModule.get_target() end

---Every node the camera follows (the group, or the single target).
---
---Example: `for _, node in ipairs(Camera.get_targets()) do Log.info(node.name) end`
---@return Node[]
function CameraModule.get_targets() end

---Gets configured target zoom level.
---
---Example: `local zoom = Camera.get_zoom(); Camera.set_zoom(zoom * 1.1)`
---@return number
function CameraModule.get_zoom() end

---Sets camera target zoom.
---
---Example: `Camera.set_zoom(2.0)`
---@param zoom number
function CameraModule.set_zoom(zoom) end

---Gets screen offset vector.
---
---Example: `local ox, oy = Camera.get_offset()`
---@return number ox
---@return number oy
function CameraModule.get_offset() end

---Sets screen offset vector.
---
---Example: `Camera.set_offset(0, -40)`
---@param ox number
---@param oy number
function CameraModule.set_offset(ox, oy) end

---Gets camera rotation in degrees.
---
---Example: `local deg = Camera.get_rotation(); Camera.set_rotation(deg + 90 * dt)`
---@return number
function CameraModule.get_rotation() end

---Sets camera rotation in degrees.
---
---Example: `Camera.set_rotation(15)`
---@param degrees number
function CameraModule.set_rotation(degrees) end

---Triggers screen shake trauma.
---
---Example: `Camera.shake(0.6, 0.3)`
---@param strength number Shake intensity (0.0 to 1.0)
---@param duration? number Duration in seconds
function CameraModule.shake(strength, duration) end

---Immediately stops active screen shake.
---
---Example: `Camera.stop_shake()`
function CameraModule.stop_shake() end

---Checks if screen shake is active.
---
---Example: `if not Camera.is_shaking() then Camera.shake(0.3, 0.2) end`
---@return boolean
function CameraModule.is_shaking() end

---Constrains camera movement within bounding rectangle limits.
---
---Example: `Camera.set_limits(0, 3200, 0, 1800)`
---@param left number
---@param right number
---@param top number
---@param bottom number
function CameraModule.set_limits(left, right, top, bottom) end

---Clears all bounding rectangle limits.
---
---Example: `Camera.clear_limits()`
function CameraModule.clear_limits() end

---Transforms screen coordinates to world coordinates.
---
---Example: `local wx, wy = Camera.screen_to_world(Input.get_mouse_position())`
---@param sx number Screen X
---@param sy number Screen Y
---@return number wx World X
---@return number wy World Y
function CameraModule.screen_to_world(sx, sy) end

---Transforms world coordinates to screen pixel coordinates.
---
---Example: `local sx, sy = Camera.world_to_screen(self.node:get_position())`
---@param wx number World X
---@param wy number World Y
---@return number sx Screen X
---@return number sy Screen Y
function CameraModule.world_to_screen(wx, wy) end

---Gets visible world bounds rectangle currently seen by camera.
---
---Example: `local x, y, w, h = Camera.get_visible_world_bounds()`
---@return number x
---@return number y
---@return number width
---@return number height
function CameraModule.get_visible_world_bounds() end


---@class PhysicsModule
---Global physics world queries, gravity, and simulation control.
local PhysicsModule = {}

---Gets world gravity vector in pixels per second squared.
---
---Example: `local gx, gy = Physics.get_gravity()`
---@return number gx
---@return number gy
function PhysicsModule.get_gravity() end

---Sets world gravity vector.
---
---Example: `Physics.set_gravity(0, 980)`
---@param gx number
---@param gy number
function PhysicsModule.set_gravity(gx, gy) end

---Draws collision shapes, joints and areas while the game runs (debugging);
---the project's Show Colliders setting (physics.debug_draw) sets the start.
---
---Example: `if Input.is_key_pressed("F3") then Physics.set_debug_draw(not Physics.get_debug_draw()) end`
---@param on boolean
function PhysicsModule.set_debug_draw(on) end

---Whether colliders are drawn while the game runs.
---
---Example: `local showing = Physics.get_debug_draw()`
---@return boolean
function PhysicsModule.get_debug_draw() end

---Checks if physics simulation is paused.
---
---Example: `if Physics.is_paused() then Physics.set_paused(false) end`
---@return boolean
function PhysicsModule.is_paused() end

---Pauses or unpauses physics simulation.
---
---Example: `Physics.set_paused(true)`
---@param paused boolean
function PhysicsModule.set_paused(paused) end

---Casts a ray between start and end world points against non-sensor colliders.
---
---Example: `local hit = Physics.raycast(x, y, x, y + 64); if hit and hit.node then Log.info(hit.node.name) end`
---@param startX number
---@param startY number
---@param endX number
---@param endY number
---@return RaycastHit? hit Raycast hit details or nil if no obstacle was struck
function PhysicsModule.raycast(startX, startY, endX, endY) end

---The project's name for collision layer n (Project Settings > Physics), or "".
---
---Example: `local name = Physics.layer_name(3); Log.info("Layer 3: " .. name)`
---@param n integer 1-16
---@return string name
function PhysicsModule.layer_name(n) end


---@class SceneModule
---Active scene queries, node discovery, switching, and dynamic instantiation.
local SceneModule = {}

---Finds any node in the active scene hierarchy by name.
---
---Example: `local player = Scene.find_node("Player"); if player then player:queue_free() end`
---@param name NodeName|string Name of node to find
---@return Node? node Found node or nil
function SceneModule.find_node(name) end

---Every node in the active scene with a tag, in tree order.
---
---Example: `for _, enemy in ipairs(Scene.find_by_tag("enemy")) do enemy:queue_free() end`
---@param tag NodeTag|string
---@return Node[]
function SceneModule.find_by_tag(tag) end

---Sets the scene's ambient light (0..1): the colour where no light reaches.
---White = an unlit scene. With LightNodes, the scene is lit by them on top.
---
---Example: `Scene.set_ambient(0.2, 0.2, 0.35)`
---@param r number
---@param g number
---@param b number
---@param a? number
function SceneModule.set_ambient(r, g, b, a) end

---Gets the scene's ambient light (0..1).
---
---Example: `local r, g, b, a = Scene.get_ambient()`
---@return number r
---@return number g
---@return number b
---@return number a
function SceneModule.get_ambient() end

---Gets the name of the currently active scene.
---
---Example: `Log.info("Entered scene: " .. Scene.get_name())`
---@return string
function SceneModule.get_name() end

---@alias TransitionKind "fade"|"wipe_left"|"wipe_right"|"wipe_up"|"wipe_down"|"circle"

---@class SceneTransition
---@field transition? TransitionKind Default "fade"
---@field duration? number Seconds for each half (cover, uncover); default 0.4
---@field color? number[] {r, g, b} 0..1; default black

---Switches to another scene by name (or its file, e.g. a `scene` property) -
---at once, or behind a transition (the screen is covered, the scene switches
---once its assets are loaded, then it's uncovered).
---
---Example: `Scene.change_scene("level_2", {transition = "fade", duration = 0.5})`
---@param name SceneName|ScenePath A scene's name, or its file
---@param transition? SceneTransition
function SceneModule.change_scene(name, transition) end

---Starts loading a scene's assets in the background (a little each frame),
---so switching to it later is quick.
---
---Example: `Scene.preload("level_2")`
---@param name SceneName
function SceneModule.preload(name) end

---Returns how far a scene started with Scene.preload has loaded, from 0 to 1.
---
---Example: `local p = Scene.preload_progress("level_2"); Log.info("Loading: " .. math.floor(p * 100) .. "%")`
---@param name SceneName
---@return number progress 0..1
function SceneModule.preload_progress(name) end

---Returns whether a scene transition is currently in progress.
---
---Example: `if Scene.is_transitioning() then return end`
---@return boolean
function SceneModule.is_transitioning() end

---Reloads the currently active scene.
---
---Example: `if Input.is_key_pressed("R") then Scene.reload() end`
function SceneModule.reload() end

---Returns an array of all active nodes in the current scene.
---
---Example: `Log.info("Node count: " .. #Scene.get_nodes())`
---@return Node[]
function SceneModule.get_nodes() end

---Dynamically instantiates a new scene node and adds it to the active scene graph.
---
---Example: `local timer = Scene.create_node("TimerNode", "Cooldown", self.node)`
---@param nodeType string "Node", "TextureNode", "ScriptNode", "CameraNode", "ParticleEmitterNode", "TimerNode", "DynamicBodyNode", "StaticBodyNode", "AreaNode", "RaycastNode", "CharacterMoverNode"
---@param name? string Optional node name
---@param parent? Node Optional parent node (defaults to scene root)
---@return Node? node Newly spawned node
function SceneModule.create_node(nodeType, name, parent) end

---Instances a component at runtime - `Scene.instantiate("components/Bullet.component.json", self.node:get_parent(), self.node.position)`.
---Added under `parent` (else the scene's root), at x, y local to it (two
---numbers or a Vec2). Returns its root node (typed per component), or nil.
---
---Example: `local b = Scene.instantiate("components/Bullet.component.json", self.node:get_parent(), self.node.position)`
---@param component ComponentPath|string
---@param parent? Node
---@param x? number|Vec2
---@param y? number
---@return Node?
function SceneModule.instantiate(component, parent, x, y) end

---Checks if debug collider and bounds rendering is enabled on this scene.
---
---Example: `local on = Scene.get_draw_bounds(); Scene.set_draw_bounds(not on)`
---@return boolean
function SceneModule.get_draw_bounds() end

---Enables or disables debug bounds rendering on the scene.
---
---Example: `Scene.set_draw_bounds(true)`
---@param draw boolean
function SceneModule.set_draw_bounds(draw) end


---@class LogModule
---Engine logging subsystem routed to Odin's logging channels.
local LogModule = {}

---Logs an informational message.
---
---Example: `Log.info("player spawned at", x, y)`
---@param ... any
function LogModule.info(...) end

---Logs a warning message.
---
---Example: `Log.warn("missing texture:", "textures/coin.png")`
---@param ... any
function LogModule.warn(...) end

---Logs an error message.
---
---Example: `Log.error("could not load level", "level_2")`
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

---Sampling curve script properties ({ type = "curve" }: points {t, v}).
---@class CurveModule
CurveModule = {}

---The curve's value at t (linear between points; clamped at the ends).
---
---Example: `local speed = self.max_speed * Curve.sample(self.speed_curve, self.elapsed / 2.0)`
---@param points number[][] The property's value ({{t, v}, ...})
---@param t number 0..1 (any value works)
---@return number
function CurveModule.sample(points, t) end

---Sampling gradient script properties ({ type = "gradient" }: stops {t, r, g, b, a}).
---@class GradientModule
GradientModule = {}

---The gradient's colour at t (linear between stops), 0..1 channels.
---
---Example: `local r, g, b, a = Gradient.sample(self.tint, self.health / self.max_health)`
---@param stops number[][] The property's value ({{t, r, g, b, a}, ...})
---@param t number 0..1
---@return number r
---@return number g
---@return number b
---@return number a
function GradientModule.sample(stops, t) end


-- ----------------------------------------------------------------------------
-- Vectors: Vec2 / Vec3 / Vec4 (vector properties come back as Vec2; setters
-- taking x, y also take a vector). v[1] / v[2] work too.
-- ----------------------------------------------------------------------------

---A 2D vector: v.x, v.y (also v[1]...); + - * / with a vector or a number.
---@class Vec2
---@field x number
---@field y number
---@operator add(Vec2|number): Vec2
---@operator sub(Vec2|number): Vec2
---@operator mul(Vec2|number): Vec2
---@operator div(Vec2|number): Vec2
---@operator unm: Vec2
local Vec2_ = {}
---Returns the vector's length (magnitude).
---
---Example: `local speed = self.velocity:length()`
---@return number
function Vec2_:length() end
---Returns the squared length, cheaper than length() for comparisons.
---
---Example: `if (target - pos):length_squared() < 16 * 16 then self.arrived = true end`
---@return number
function Vec2_:length_squared() end
---A vector of length 1 in the same direction (zero stays zero).
---
---Example: `local dir = (target - pos):normalized()`
---@return Vec2
function Vec2_:normalized() end
---Returns the dot product with another vector.
---
---Example: `local facing = forward:dot((target - pos):normalized())`
---@param other Vec2
---@return number
function Vec2_:dot(other) end
---Returns the distance to another vector.
---
---Example: `local d = pos:distance(target)`
---@param other Vec2
---@return number
function Vec2_:distance(other) end
---Returns the vector interpolated toward other by t (0 = this, 1 = other).
---
---Example: `local mid = a:lerp(b, 0.5)`
---@param other Vec2
---@param t number 0..1
---@return Vec2
function Vec2_:lerp(other, t) end
---Returns a new vector with the same components.
---
---Example: `local start = pos:copy()`
---@return Vec2
function Vec2_:copy() end
---The components as values: `local x, y = v:unpack()`.
---
---Example: `local x, y = Vec2(3, 4):unpack()`
---@return number ...
function Vec2_:unpack() end

---A 3D vector: v.x, v.y, v.z (also v[1]...); + - * / with a vector or a number.
---@class Vec3
---@field x number
---@field y number
---@field z number
---@operator add(Vec3|number): Vec3
---@operator sub(Vec3|number): Vec3
---@operator mul(Vec3|number): Vec3
---@operator div(Vec3|number): Vec3
---@operator unm: Vec3
local Vec3_ = {}
---Returns the vector's length (magnitude).
---
---Example: `local len = Vec3(1, 2, 2):length()`
---@return number
function Vec3_:length() end
---Returns the squared length, cheaper than length() for comparisons.
---
---Example: `local len2 = Vec3(1, 2, 3):length_squared()`
---@return number
function Vec3_:length_squared() end
---A vector of length 1 in the same direction (zero stays zero).
---
---Example: `local axis = Vec3(1, 2, 3):normalized()`
---@return Vec3
function Vec3_:normalized() end
---Returns the dot product with another vector.
---
---Example: `local d = Vec3(1, 0, 0):dot(Vec3(0, 1, 0))`
---@param other Vec3
---@return number
function Vec3_:dot(other) end
---Returns the distance to another vector.
---
---Example: `local d = Vec3(0, 0, 0):distance(Vec3(1, 2, 2))`
---@param other Vec3
---@return number
function Vec3_:distance(other) end
---Returns the vector interpolated toward other by t (0 = this, 1 = other).
---
---Example: `local mid = Vec3(0, 0, 0):lerp(Vec3(10, 20, 30), 0.5)`
---@param other Vec3
---@param t number 0..1
---@return Vec3
function Vec3_:lerp(other, t) end
---Returns a new vector with the same components.
---
---Example: `local backup = Vec3(1, 2, 3):copy()`
---@return Vec3
function Vec3_:copy() end
---The components as values: `local x, y = v:unpack()`.
---
---Example: `local x, y, z = Vec3(1, 2, 3):unpack()`
---@return number ...
function Vec3_:unpack() end

---A 4D vector: v.x, v.y, v.z, v.w (also v[1]...); + - * / with a vector or a number.
---@class Vec4
---@field x number
---@field y number
---@field z number
---@field w number
---@operator add(Vec4|number): Vec4
---@operator sub(Vec4|number): Vec4
---@operator mul(Vec4|number): Vec4
---@operator div(Vec4|number): Vec4
---@operator unm: Vec4
local Vec4_ = {}
---Returns the vector's length (magnitude).
---
---Example: `local len = Vec4(1, 1, 1, 1):length()`
---@return number
function Vec4_:length() end
---Returns the squared length, cheaper than length() for comparisons.
---
---Example: `local len2 = Vec4(1, 2, 3, 4):length_squared()`
---@return number
function Vec4_:length_squared() end
---A vector of length 1 in the same direction (zero stays zero).
---
---Example: `local q = Vec4(0, 0, 1, 1):normalized()`
---@return Vec4
function Vec4_:normalized() end
---Returns the dot product with another vector.
---
---Example: `local d = Vec4(1, 0, 0, 0):dot(Vec4(0.5, 0.5, 0, 0))`
---@param other Vec4
---@return number
function Vec4_:dot(other) end
---Returns the distance to another vector.
---
---Example: `local d = Vec4(1, 0, 0, 1):distance(Vec4(0, 1, 0, 1))`
---@param other Vec4
---@return number
function Vec4_:distance(other) end
---Returns the vector interpolated toward other by t (0 = this, 1 = other).
---
---Example: `local c = Vec4(1, 0, 0, 1):lerp(Vec4(0, 0, 1, 1), t)`
---@param other Vec4
---@param t number 0..1
---@return Vec4
function Vec4_:lerp(other, t) end
---Returns a new vector with the same components.
---
---Example: `local backup = Vec4(1, 2, 3, 4):copy()`
---@return Vec4
function Vec4_:copy() end
---The components as values: `local x, y = v:unpack()`.
---
---Example: `local x, y, z, w = Vec4(1, 0, 0, 1):unpack()`
---@return number ...
function Vec4_:unpack() end

---The angle of the vector in degrees (0 = right, 90 = down).
---
---Example: `local deg = (target - pos):angle(); self.node:set_rotation(deg)`
---@return number
function Vec2_:angle() end
---The vector rotated by degrees (clockwise on screen).
---
---Example: `local spread = Vec2.RIGHT:rotated(15) * 300`
---@param degrees number
---@return Vec2
function Vec2_:rotated(degrees) end

---Makes a Vec2: `Vec2(3, 4)`; constants Vec2.ZERO, ONE, UP, DOWN, LEFT, RIGHT.
---@class Vec2Constructor
---@overload fun(x?: number, y?: number): Vec2
---@field ZERO Vec2
---@field ONE Vec2
---@field UP Vec2
---@field DOWN Vec2
---@field LEFT Vec2
---@field RIGHT Vec2
---@field new fun(x?: number, y?: number): Vec2

---Makes a Vec3: `Vec3(1, 2, 3)`.
---@class Vec3Constructor
---@overload fun(x?: number, y?: number, z?: number): Vec3
---@field new fun(x?: number, y?: number, z?: number): Vec3

---Makes a Vec4: `Vec4(1, 2, 3, 4)`.
---@class Vec4Constructor
---@overload fun(x?: number, y?: number, z?: number, w?: number): Vec4
---@field new fun(x?: number, y?: number, z?: number, w?: number): Vec4

---@type Vec2Constructor
Vec2 = {}
---@type Vec3Constructor
Vec3 = {}
---@type Vec4Constructor
Vec4 = {}

---@type CurveModule
Curve = CurveModule

---@type GradientModule
Gradient = GradientModule

---@type SceneModule
Scene = SceneModule
Tween = TweenModule

---@type SaveModule
Save = SaveModule

---@class NavigationModule
local NavigationModule = {}

---Same as map:nav_find_path(x1, y1, x2, y2, opts).
---
---Example: `local path = Navigation.find_path(Scene.find_node("Level"), x, y, tx, ty, {smooth = false})`
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
---
---Example: `self.node:set_text(tr("greeting", {name = player_name}))`
---@param key LocaleKey|string
---@param args? table<string, any>
---@return string
function tr(key, args) end

---@class LocaleModule
local LocaleModule = {}

---Switches the language texts are shown in (a column of the locale tables).
---
---Example: `Locale.set("fr")`
---@param language Language|string e.g. "fr" (the project's locale tables' languages)
function LocaleModule.set(language) end

---Returns the current language.
---
---Example: `if Locale.get() == "fr" then self.flag = "textures/flag_fr.png" end`
---@return string language
function LocaleModule.get() end

---Returns the languages available in the project's locale tables.
---
---Example: `for _, lang in ipairs(Locale.languages()) do Log.info(lang) end`
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
---
---Example: `local ok = Project.load("assets/demo_project.ore")`
---@param pathOrDir string Path to directory or .ore file
---@return boolean success
function ProjectModule.load(pathOrDir) end

---Packages a loose project directory into a portable .ore container archive with zlib compression.
---
---Example: `local ok = Project.export_ore("assets/demo_project", "bin/demo_project.ore")`
---@param projectDir string Source directory path
---@param outOrePath string Target output .ore file path
---@return boolean success
function ProjectModule.export_ore(projectDir, outOrePath) end

---Serializes the currently active scene graph and node states to a JSON formatted string.
---
---Example: `local json = Project.serialize_scene(); Log.info(#json, "bytes")`
---@return string json
function ProjectModule.serialize_scene() end

---Reads a text file either from the mounted .ore archive package or the loose project directory.
---
---Example: `local text = Project.read_file("data/items.json"); if text then Log.info(text) end`
---@param relPath string Project-relative file path
---@return string? content File contents as a string, or nil if not found
function ProjectModule.read_file(relPath) end

---Checks if a file exists in the active project (.ore archive or disk).
---
---Example: `if Project.has_file("levels/level_2.json") then Scene.change_scene("level_2") end`
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
