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

Entity definitions: identifier, size, colour, pivot, whether it can be
resized, its tile, and its **fields**. **Use picked tile** takes the tile
picked in a palette.

## Fields
<!-- topic: fields -->

Values each entity (or level) carries for the game:

- Int, Float, Bool, String, Multilines, Color;
- Enum, Point, FilePath;
- EntityRef, Tile.

Add a field by picking a type and clicking **Add field**. In the game, an
entity's fields set script properties with the same names.

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

Auto-layer rules draw tiles from an IntGrid layer's values.

- **Pattern**: left click requires the picked value, right click forbids
  it, Shift + left / right means any value / no value, and middle click
  clears.
- **Tiles button**: uses the palette's picked tiles. With several tiles,
  one is picked at random per cell; **S** places them as one stamp.
- **X / Y**: also match the pattern mirrored.
- **Dot**: break on match. Later rules don't paint a cell this rule
  painted.
- **Eye**: turns the rule on or off.
- **Chance**: the percentage of matching cells that get tiles.
- **Modulo**: only every Nth cell.
- **Size**: the pattern size (odd numbers, up to 9).

Rules run from the top group down. Changing a rule redraws every level.

## Terrains
<!-- topic: rules.terrain -->

Pick a 3x3 block of tiles in the palette: corners, edges and the middle.
Then click **Terrain from picked 3x3 tiles**. It adds nine rules that draw
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
