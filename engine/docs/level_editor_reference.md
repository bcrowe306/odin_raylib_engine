# Level Editor
<!-- topic: overview -->

The **Level** tab edits LDtk projects (`.ldtk`, with `.ldtkl` files for
external levels) in place. The file stays an LDtk project: it still opens
in LDtk, and the game's LDtk Level nodes read it and reload when you save.

- **Levels** (left): the world's levels.
- **Layers** (right): the active level's layers and the active layer's
  palette.
- **Canvas** (middle): paint and place things in the active level.
- **Bottom panel**: World, Level, Tilesets, Entities, Enums, Layers, Rules
  and Project tabs.

Hover anything and press **F1** to open its page here. The **?** buttons do
the same.

## Canvas
<!-- topic: canvas -->

The canvas shows the active world. The active level is drawn on top, and the
other levels are dimmed. Click another level to make it active.

| | |
|---|---|
| Pan | Middle drag, or Space + drag |
| Zoom | Mouse wheel (around the mouse); the zoom box in the toolbar |
| Fit the level | Home, or the expand button in the toolbar |
| Grid | G, or the grid button in the toolbar |
| IntGrid colours over auto tiles | the eye button in the toolbar |

The bottom line shows the level, the layer, the cell under the mouse and its
IntGrid value.

# Tools

## Brush
<!-- topic: tool.brush -->

**B**. Paints on the active layer:

- **IntGrid**: the picked value. The right button erases.
- **Tiles**: the picked tiles as a stamp. Flip it with **X** and **Y**.
- **Entities**: places the picked entity on the grid. Hold **Shift** to
  place it off the grid.

**Shift** + drag paints a rectangle instead (as with the Rectangle tool).
Each stroke is one undo step. Auto tiles follow every painted cell.

## Rectangle
<!-- topic: tool.rect -->

**R**. Drag a rectangle and release to fill it with the picked value or
tiles. The tiles repeat across the rectangle. Drag with the right button to
erase the rectangle instead.

## Erase
<!-- topic: tool.erase -->

**E**. Erases the IntGrid value or tiles under the mouse. With the other
tools, the right button erases too.

## Fill
<!-- topic: tool.fill -->

**F**. Fills the connected area of equal cells (the same IntGrid value, or
the same top tile) with the picked value or tiles. The right button fills
that area with nothing (erases it).

## Pick
<!-- topic: tool.pick -->

**I**. Picks the IntGrid value, or the tile (with its flips), under the
mouse, then switches back to the Brush.

## Select
<!-- topic: tool.select, selection -->

**V**, or hold **Alt** with any tool (LDtk's selection).

| | |
|---|---|
| Click | select the entity or cell under the mouse; the layer becomes active |
| **Shift** + click | add to the selection, or remove from it |
| **Shift** + drag on empty space | rectangle selection, over every visible layer |
| Drag the selection | move it: cells by whole cells, entities snapped to the grid (**Shift**: free) |
| **Cmd+Alt** + drag | copy the selection instead of moving it |
| Arrow keys | move the selection by one cell |
| **Delete** | delete what is selected |
| **Cmd+A** / **Cmd+Shift+A** | select everything in the active layer / in every layer |
| **Cmd+C**, **Cmd+X**, **Cmd+V** | copy / cut / paste (pasted under the mouse) |
| **Cmd+D** | duplicate the selection, one cell to the right |
| **Esc** | clear the selection |
| The corner handle | resize a single resizable entity |

Selected cells move or copy together across layers when their grids line
up. Cells that land outside their layer are dropped, and the cells they land
on are replaced. Moving an entity to another Entities layer is in the
**Level** tab, under **Layer**.

## Move levels
<!-- topic: tool.movelevel -->

**M**. Drag levels around the world. In GridVania worlds they snap to the
world grid, and elsewhere to the default grid. In linear layouts, positions
come from the order in the Levels panel.

# Panels

## Levels panel
<!-- topic: panel.levels -->

The active world's levels. Click one to open it, and double-click to frame
it. **+** adds a level next to the active one, in a free spot. The bin
deletes the active level. Right-click a level for more: rename, duplicate,
delete, and frame it.

## Layers panel
<!-- topic: panel.layers -->

The active level's layers, top first, shown as *Type: Name*.

- Click a layer to make it active.
- Drag a layer by its **grip** to put it in another order. That changes
  every level.
- The **eye** hides a layer. This is LDtk's per-level visibility, and it is
  saved.
- **+** opens **New Layer**. The sliders button opens the **Layers** tab.

Right-click a layer for more: settings, rules, hide / show, move up / down,
duplicate, delete.

Under the list is the active layer's **palette**.

## New layer
<!-- topic: layer.new -->

| | |
|---|---|
| **Type** | **IntGrid**: values per cell (collisions, terrain types); with a tileset, its rules draw tiles. **Entities**: placed objects with fields. **Tiles**: tiles painted by hand. **Auto**: tiles drawn by rules that read an IntGrid layer. |
| **Identifier** | Its name (letters, digits, _). |
| **Grid size** | Cell size in pixels. |
| **Tileset** | The tileset its tiles come from. |
| **Rules read** | Auto layers: the IntGrid layer their rules look at. |

New layers go on top of every level.

## IntGrid palette
<!-- topic: palette.intgrid -->

The layer's values. Click one, or press **1-9**, then paint. The value's
colour shows in the canvas. Values are added and named in the **Layers**
tab. Right-click a value to edit it.

## Tile palette
<!-- topic: palette.tiles -->

The layer's tileset. Click a tile, or drag over several to make a stamp.
**X** / **Y** flip what you paint. The zoom slider scales the tileset.

The picked tiles are also used by:

- **Rules**: the tiles button, and terrains;
- **Tilesets**: animating a tile;
- **Entities**: an entity's tile.

## Stamp and Random modes
<!-- topic: tile.modes -->

The dice button switches modes (**Shift+R**):

- **Stamp**: the picked tiles are painted as a block, keeping their places
  in the tileset (any shape: holes stay empty). Rectangles and fills repeat
  the block.
- **Random**: each painted cell gets one of the picked tiles at random.
  This is useful for grass, floors and rubble. Rectangles and fills pick a
  random tile per cell.

## Tile stacking
<!-- topic: tile.stacking -->

The layers button (**Shift+T**) toggles stacking. With stacking on:

- a painted tile goes on top of the tiles already in the cell, so you can
  put decorations over a floor;
- painting the same tile again moves it back to the top;
- an **opaque** tile (no transparent pixel) still replaces the stack;
- erasing removes only the top tile.

## Saved tile groups
<!-- topic: tile.saved -->

Pick several tiles, then click the bookmark button (or press **Shift+S**).
From then on, clicking any tile of that group picks the whole group, in its
mode (Stamp or Random). **Alt** + click picks just the one tile. Saved groups
are outlined in the palette. Right-click the palette to forget a group.
Groups are stored in the tileset (LDtk's saved selections).

## Tileset per level
<!-- topic: layer.tileset.override -->

Right-click a layer, then choose **Tileset in this level**, to draw that
layer with another tileset in the active level only. Examples: a winter
version of a level, or a different palette. The tiles keep their ids, so
the other tileset should have the same layout. **The layer's own** goes back
to the layer's tileset.

## Entity palette
<!-- topic: palette.entities -->

The project's entities. Pick one, then click in the level with the Brush.
Use the **Select** tool to move or resize entities, and **Delete** to
remove them. Right-click an entity to edit its definition.

## Auto-layer rules (palette)
<!-- topic: palette.auto -->

The layer's rule groups. A check box turns an **optional** group on or off
for this level. **Re-run rules** regenerates this level's auto tiles. An
Auto layer has no cells of its own: paint the IntGrid layer it reads.

# Bottom panel

## World tab
<!-- topic: tab.world -->

| | |
|---|---|
| **Layout** | **Free**: levels anywhere. **GridVania**: levels on the world grid. **Linear horizontal / vertical**: in a row or column, in the order of the Levels panel. |
| **World grid** | GridVania's grid cell size. |
| **Map** | Every level of the world. Click one to open it. |

## Level tab
<!-- topic: tab.level -->

The active level's identifier, position, size (Enter applies), depth,
background colour, and level fields. With an entity selected, it shows the
entity instead: position, size, layer, iid and fields.

## Tilesets tab
<!-- topic: tab.tilesets -->

Add tilesets from project images and set tile size, spacing and padding.
Click a tile in the grid to edit its **custom data**, its **animation** and
its **enum tags**. The **tag enum** decides which enum's values can tag
tiles.

## Animated tiles
<!-- topic: tile.animation -->

Pick the frames in a tileset palette (in order: left to right, top to
bottom). In the Tilesets tab, click the first frame, then **Animate with
picked tiles**, and set **fps**. Wherever the first frame is painted or
placed by a rule, it animates in the editors and in the game.

The animation is stored in the tile's custom data:

```
anim=40,41,42,43
fps=6
```

## Entities tab
<!-- topic: tab.entities -->

On the left is the list of entity definitions. Right-click one to place,
duplicate, reorder or delete it. In a narrow panel, the definition's
**Settings** and **Fields** are two tabs; in a wide one they sit side by
side.

| Setting | |
|---|---|
| Identifier, Doc, Tags | Its name, a description, and comma-separated tags. Layers can require or exclude tags, and references can allow them. |
| Size, Resizable X / Y | Its default size, and whether instances can be resized with the corner handle. |
| Keep aspect, Min / Max width / height | Limits for resizing. |
| Pivot | The point placed on the grid. |
| Colour | Its colour in the editor. A field can override it (smart colour). |
| Render | Rectangle, Ellipse, Tile or Cross. |
| Tile, Tile mode | Its picture (**Use picked tile**), and how the picture fills the box: Cover, Fit inside, Repeat, Stretch, Full size (cropped / uncropped), 9-slice (with borders). |
| Tile / Fill / Line opacity, Hollow | How it looks. A hollow entity is selected by its outline only. |
| Show name | Its name above it in the canvas. |
| Max count, Limit, When reached | At most N per layer, per level or per world. Placing one more moves the last one, discards the oldest, or is prevented. |
| Table of contents | List its instances in the project's `toc`, for games. |
| Out of bounds | Instances may stand outside their level. |

## Field definitions
<!-- topic: fields.defs -->

Pick a field in the list (right-click it to duplicate, reorder or delete
it), or add one by picking a type and clicking **Add field**.

| Setting | |
|---|---|
| Identifier, Doc | Its name (a script property with this name gets the value) and a description. |
| Type | Converts the field and its values: String to Multilines and back, FilePath to String and back, Int to Float, Bool to Int, Float to Int (truncate / round), and any field to an array. |
| Min / Max values | Array length limits. |
| Nullable | Whether it can be empty. |
| Default | The value new instances use. |
| Min / Max | Number limits. |
| Regex | String values must match it, written `/pattern/flags`. |
| File types | Accepted extensions for FilePath fields. |
| Language | Multilines syntax (used for LDtk's highlighting). |
| Tileset | Tile fields: where the tiles come from. |
| Can point at, Other levels, Symmetrical, Auto chain | Rules for references. |
| Smart colour | A Color or Enum field gives the entity its colour. |
| Display, Position, Link style, Display colour, Display scale, Always show, In world view, Cut long values, Prefix / Suffix | How the canvas shows it (see *Field display in the canvas*). |
| Table of contents, Searchable | Its value in `toc` entries; searchable values. |

## Fields
<!-- topic: fields -->

Values that each entity (or level) carries for the game. Edit them in the
**Level** tab: the selected entity's fields, or the level's.

| Type | Edited with |
|---|---|
| Int, Float | a number (kept within the definition's min / max) |
| Bool | a check box |
| String | one line; it must match the definition's regex, if there is one |
| Multilines | a text box |
| Color | a colour picker |
| Enum | a list of the enum's values |
| Point | "cx,cy", or the crosshair: click a cell in the level |
| FilePath | a path, or the folder button: a project file of an accepted type |
| EntityRef | the crosshair: click the entity in the level (it may be in another level); the arrow button goes to it |
| Tile | **Use picked tile**: the tiles picked in a tileset palette |

- **Arrays**: **+** adds a value (for points and references, you then
  click in the level, and **Shift** keeps adding). Each value has move up,
  move down and remove buttons.
- **Defaults**: a value that is still the definition's default is dimmed.
  Right-click > **Reset to default** brings the default back. **Clear**
  empties a nullable field.
- **Errors** show in red: a required value missing, a reference to an entity
  that no longer exists or isn't allowed, a string that doesn't match the
  regex, a file of the wrong type.
- **Symmetrical references** (a definition option): pointing A at B makes B
  point at A, and clearing it removes both links.

In the game, an entity's fields set the script properties with the same
names.

## Field display in the canvas
<!-- topic: fields.display -->

Each field definition decides how the canvas shows it (**Display** in the
Entities tab):

| Display | |
|---|---|
| Hidden | not shown |
| Value only / Name and value | text above, at the centre of, or beneath the entity |
| Array count (with / without label) | how many values |
| Entity tile | an enum's icon or a tile field becomes the entity's picture |
| Points / Path / Loop / Star | the points, joined as a path, a closed loop, or lines from the entity |
| Radius (px / grid) | a circle of that radius |
| Reference link (pivots / centres) | an arrow to the referenced entity, in the chosen link style |

Fields still at their default (or empty arrays) are only shown when
**Always show** is on. Errors are always shown, in red.

## Enums tab
<!-- topic: tab.enums -->

Enumerations: lists of named values, for enum fields and tile tags. Add
values with the box under the list.

## Layers tab
<!-- topic: tab.layers -->

Each layer's settings: identifier, grid size, opacity, pixel offset,
tileset, the IntGrid layer an Auto layer reads, order, and **IntGrid
values** (colour, name).

## Rules tab
<!-- topic: tab.rules, rules -->

Auto-layer rules draw tiles from an IntGrid layer's values. An IntGrid
layer with a tileset has rules of its own; an Auto layer reads another
IntGrid layer's values.

The tab has three columns: the layers that have rules, that layer's
groups and rules, and the editor for the picked rule.

**Groups** run from the top down, and their rules run top to bottom. The
check box turns a group on or off, and the arrow folds it. Badges show
whether the group is optional, made by the Assistant, or limited to a
biome. Right-click a group to:

- rename it;
- duplicate and remap it (see below);
- copy it (**Paste** sits next to the add buttons);
- make it optional or global;
- set its colour, or use the picked tile as its icon;
- limit it to a biome;
- set the out-of-bounds value of all its rules;
- move or delete it.

Assistant groups open in the Assistant on a double-click. **Advanced mode**
turns one into plain rules.

**Rules**: each row shows the rule's pattern, its tiles and its options.
Click a row to edit it. Right-click a row to:

- edit it;
- show the cells it matches;
- enable or disable it;
- duplicate it, copy it, or paste after it;
- insert a rule before or after it;
- move it (past the group's edge, it moves into the next group);
- delete it.

**The rule editor**:

- **Pattern**: pick a value above the grid (**\*** means any value). Left
  click requires it, right click forbids it, and middle click clears the
  cell. The yellow cell is the one that gets the tile. **Size**: odd
  numbers, up to 9.
- **Tiles**: individual tiles (one at random per match) or rectangles
  (stamps placed as a block, around the **pivot**). **Use picked tiles**
  replaces them with the palette's selection; **Add picked** adds to
  them. Right-click a tile to remove it.
- **Out of bounds**: what cells outside the level count as.
- **Break on match**: later rules don't paint the cells this rule painted.
- **Flip X / Y**: also match the pattern mirrored; the tiles flip too.
- **Chance**: the percentage of matching cells that get tiles.
- **Opacity** of the tiles.
- Modulo, checker, Perlin noise and offsets have their own sections.

The eye in the rule's header shows the cells it matches in the canvas
(green). Changing a rule redraws every level.

## Rule groups: duplicate and remap
<!-- topic: rules.groups, rules.remap -->

**Duplicate and remap** copies a group. Each IntGrid value it uses can
become another value, and its tiles can move by whole cells in the
tileset. For example, "0, 4" uses the tiles four rows lower: another
terrain drawn in the same layout. Use it to reuse one set of wall rules
for every material.

**Biome**: when the layer has a biome field (Layers tab), a group can
require some of that enum's values in the level's field: any of them
(OR) or all of them (AND).

**Optional** groups are off by default. You turn them on per level with
the check box in the Layers panel.

## Modulo and checker
<!-- topic: rules.modulo -->

**Modulo X, Y** matches only every Nth column / row. **Offset X, Y**
shifts which columns / rows are picked. **Checker** shifts every other
row (horizontal) or column (vertical) by half the modulo, which gives a
checkerboard.

## Perlin noise
<!-- topic: rules.perlin -->

Matches only where a noise is positive, which gives natural-looking
patches (grass, cracks). **Seed** picks another noise. A smaller
**scale** gives bigger patches; more **octaves** give rougher edges.

## Tile offsets
<!-- topic: rules.offsets -->

**Tile offset X, Y** moves the placed tiles by that many pixels.
**Random X / Y min, max** adds a random shift per cell, which breaks up
repeated patterns. The offsets don't change which cells match.

## The Rules Assistant
<!-- topic: rules.wizard -->

The Assistant writes a group of wall rules. It is LDtk's rules wizard.

1. Click **Assistant** in the Rules tab.
2. Name the group, pick the IntGrid **value** the walls draw over, and
   what the edges are **next to**: anything else, or one specific value
   (walls next to water, say).
3. Click a shape in the grid: a single cell, walls, corners, turns, T
   crossings, diagonals, the full centre...
4. Pick its tile(s) in the Layers panel's tileset, then click **Use picked
   tiles**. With several tiles, one is picked at random. Right-click a
   shape to clear it.
5. Click **Create rules**.

Shapes left empty use a mirrored shape when there is one: give **Wall N**
tiles, and **Wall S** uses them flipped. The group remembers its tiles.
Double-click it, or pick **Edit with the Assistant** from its menu, to
change them and **Update rules**.

## Terrains
<!-- topic: rules.terrain -->

Pick a 3x3 block of tiles in the palette: corners, edges and the middle.
Then click **3x3** next to **Empty group**. It adds nine rules that draw
the block over the picked value: edges where the neighbours are empty, and
the middle inside.

## Project tab
<!-- topic: tab.project -->

Defaults for new levels and entities, background colours, the level name
pattern (`%idx`, `%world`), whether to minify the JSON, and the **level
fields**.

# Saving

## Saving and the file format
<!-- topic: saving -->

**Cmd+S** saves the `.ldtk`, plus the `.ldtkl` files of external levels
that changed. The JSON is laid out the way LDtk writes it. Fields this editor
doesn't know about are kept, and a file saved without changes is identical
to the one LDtk wrote.

## Undo
<!-- topic: undo -->

**Cmd+Z** / **Cmd+Shift+Z**. Each stroke, move or edit is one step, and the
editor keeps the last 100.

## Keyboard shortcuts
<!-- topic: shortcuts -->

| Key | |
|---|---|
| B R E F I V M | Brush, Rectangle, Erase, Fill, Pick, Select, Move levels |
| Alt (held) | Select with any tool |
| 1-9 | IntGrid value |
| X / Y | Flip the stamp |
| Shift+R | Stamp / Random tile mode |
| Shift+T | Tile stacking |
| Shift+S | Save the picked tiles as a group |
| Shift + drag | Rectangle with the Brush / Erase |
| G | Grid |
| Home | Fit the level |
| Delete | Delete the selection |
| Arrows | Move the selection |
| Cmd+A / Cmd+Shift+A | Select all (layer / every layer) |
| Cmd+C / X / V / D | Copy, cut, paste, duplicate |
| Esc | Clear the selection |
| Cmd+S | Save |
| Cmd+Z / Cmd+Shift+Z | Undo / redo |
| F1 | This reference, at the hovered item |
| Cmd+Shift+1 / 2 | Game tab / Level tab |
