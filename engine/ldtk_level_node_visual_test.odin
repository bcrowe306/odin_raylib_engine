package engine

import "core:testing"

// An LDtk entity's look on its level: its icon in the editor (entities
// aren't spawned there) or with Draw Entity Tiles in the game; without an
// icon, its box in the editor only.
@(test)
test_ldtk_entity_visual :: proc(t: ^testing.T) {
	ln: LdtkLevelNode
	withTile := LdtkEntityInstance{tile = {has = true}}
	noTile := LdtkEntityInstance{}
	icon, box := LdtkLevelNode_EntityVisual(&ln, &withTile)
	testing.expect(t, !icon && !box, "the game: nothing (the spawned node draws itself)")
	ln.drawEntityTiles = true
	icon, box = LdtkLevelNode_EntityVisual(&ln, &withTile)
	testing.expect(t, icon && !box, "the game with Draw Entity Tiles: the icon")
	ln.drawEntityTiles = false
	ln.editorPreview = true
	icon, box = LdtkLevelNode_EntityVisual(&ln, &withTile)
	testing.expect(t, icon, "the editor: the icon")
	icon, box = LdtkLevelNode_EntityVisual(&ln, &noTile)
	testing.expect(t, !icon && box, "the editor, no icon: its box")
}
