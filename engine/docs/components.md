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
  The nodes inside it have uids in *its* file.
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
               "$added":            {".": [{"type": "Node", "name": "Shield"}]}}}
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
- Renaming a child inside an instance isn't an override; the name comes
  from the component file.

### Older files (no uids)

Component files and scenes saved before uids keep loading unchanged:

- A path segment matches a child by uid first, then by **name**. A scene
  whose overrides use names (`"Thruster/Flame"`) applies them as before.
- A component file without uids gets them the next time it's written (any
  of the three ways above). Files aren't rewritten in bulk.
- A scene switches its override keys to uids the next time it's saved after
  its component file has uids. Until then, a name-keyed override follows
  the node's name, as it always did.

## Limits

- Overrides inside a nested instance are stored as that nested link's whole
  `overrides` object; per-node merging across nested links comes with #79.
- The order of an instance's children isn't saved as an override (#78).
