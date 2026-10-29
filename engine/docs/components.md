# Components

A component (a prefab) is a node tree saved in its own file,
`components/<Name>.component.json`. A scene doesn't copy it: it keeps a
**linked instance**, which stores the link, the instance's own name and
transform, and what this instance changes (its **overrides**). When the
component file changes, every instance follows it, except for the values
that instance overrides.

The full guide (creating and editing components, the Inspector, nesting,
spawning from Lua) is still to come. This page is the file format.

## File format

### Component file

The file is a node object, the same as a node in a scene file, with a
`"uid"` on every node:

```json
{
  "type": "TextureNode",
  "name": "Ship",
  "uid": "q8v0d2ma",
  "texture": "textures/ship.png",
  "children": [
    {"type": "ParticleEmitterNode", "name": "Thruster", "uid": "k3j9x0ab",
     "children": [{"type": "Node", "name": "Flame", "uid": "p0q9zz11"}]},
    {"type": "Node", "name": "Cannon", "uid": "7c1lz4ee",
     "component": "components/Cannon.component.json"}
  ]
}
```

- **`uid`**: 8 base-36 characters (`0-9a-z`), unique in the file. It
  identifies the node for instance overrides. It doesn't change when the
  node is renamed or moved, and siblings with the same name have different
  uids.
- Uids are given when the file is written: saving the component document,
  Save as Component, and Apply Changes to Component. Nodes that already have
  one keep it. A node without one, or with a uid another node of the file
  already has, gets a new one.
- A nested instance (a node with `"component"`) has a uid in this file too.
  The nodes inside it have uids in *its* file. The nested link's
  `"overrides"` follow the same rules as an instance in a scene (below).
- A copied or duplicated node is a new node: it has no uid until its file
  is written. A node that is cut and pasted keeps its uid.

### Instance in a scene

```json
{"type": "TextureNode", "name": "Ship2", "position": [300, 200],
 "component": "components/Ship.component.json",
 "overrides": {".":                 {"script": {"properties": {"speed": 300}}},
               "k3j9x0ab":          {"properties": {"emitter.amount": 40}},
               "k3j9x0ab/p0q9zz11": {"visible": false},
               "$removed":          ["7c1lz4ee"],
               "$added":            {".": [{"type": "Node", "name": "Shield"}]},
               "$order":            {".": ["+Shield", "k3j9x0ab"]}}}
```

- The instance root stores its name, transform, `enabled`, `visible`,
  `layer` (and tags, connections) directly. An instance in a scene has no
  `uid` of its own.
- **`overrides`** keys are paths from the instance root: `"."` is the root,
  and each segment is a node's **uid**. Each value holds what differs from
  the component file. `properties` and a script's `properties` merge key by
  key, other keys replace the value, and `null` removes a key.
- **`$removed`**: paths of component nodes deleted from this instance.
- **`$added`**: nodes added to this instance, in full, under the path of
  their parent. They are scene data, not nodes of the component, so they
  are saved without uids.
- **`$order`**: a parent's children in this instance's order, by path of
  the parent. It is only saved where the order isn't the natural one (the
  component's children in the component's order, then the added nodes).
  Component children are listed by segment (uid), added nodes by `+` and
  their name. Children it doesn't list (added to the component since) come
  after, in the component's order. Instances that didn't reorder follow the
  component's order when it changes. In the editor, Move Up / Move Down and
  dragging within the same parent work inside an instance; Revert on the
  parent drops its order.
- Renaming a child inside an instance isn't an override; the name comes
  from the component file.

### Nested instances

Paths cross nested instances. A component A nesting B (uid `bina0000`),
which nests C (uid `cinb0000`), and an instance of A overriding a node of
C (uid `1eaf0000`):

```json
"overrides": {"bina0000/cinb0000/1eaf0000": {"position": [5, 5]}}
```

Each level (B's link to C, A's link to B, the instance of A) keeps its own
entry for the node, and they merge per node: the outermost level wins for
a value it sets, and values no level sets follow C. So changing C, B or A
reaches every instance except where an outer level overrides that value.

- An instance's overrides live on the outermost instance whose component
  contains the node. An instance *added* to another instance is saved in
  `$added` as a link with its own `overrides`.
- Saving a component updates its instances in every open document: scenes,
  and component documents that nest it.
- If a nested component's file is missing, entries for nodes inside it are
  kept in that nested link's `overrides`, so they come back with the file.
- Older scenes stored a nested instance's changes as one whole
  `"overrides"` object on the nested node (`{"bina0000": {"overrides":
  {...}}}`). These still load (applied on top of the nested levels) and are
  saved per node from then on.

### Older files (no uids)

Component files and scenes saved before uids keep loading unchanged:

- A path segment matches a child by uid first, then by **name**. A scene
  whose overrides use names (`"Thruster/Flame"`) applies them as before.
- A component file without uids gets them the next time it's written (any
  of the three ways above). Files aren't rewritten in bulk.
- A scene switches its override keys to uids the next time it's saved after
  its component file has uids. Until then, a name-keyed override follows
  the node's name, as it always did.

## Performance

- A component is prepared (read, parsed, defaults filled in, nested
  components expanded) once per path. Instances are built from that copy
  until the component file or any file it nests changes (size or time), or
  the editor writes a component.
- In the editor, each instance remembers the component JSON it was built
  from, so its overrides stay right when the file changes before the
  instance is refreshed. A game doesn't keep that copy (about 2 KB per
  instance of a 12-node component); saving there diffs against the file.
- Numbers: `bench_components` in `scripts/bench.sh`; baselines in
  `engine/GAPS.md`.

## Hot reload

- A running game (Play in the editor or a project folder, not a `.rayzr`
  package) checks the component files its instances use twice a second.
  When one changes, or a file it nests changes, each instance of it in the
  loaded scenes is rebuilt in place. The outermost instance holding it is
  the one rebuilt. Its overrides, transform and place among its parent's
  children are kept.
- The overrides are diffed against the component JSON the instance was
  built from (kept only until the rebuild), so values the instance never
  changed follow the new file.
- A rebuilt instance is made of new nodes: its scripts start again
  (`ready()`), and a script holding one of its old nodes holds a removed
  node. Look the nodes up again (`get_node`, `Scene.find_node`).
- The editor refreshes the instances in its own documents when it saves a
  component; this check is for the running game.

## Limits

- Nodes inside an instance can change order but not parent.
