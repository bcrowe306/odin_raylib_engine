#!/usr/bin/env bash
# Builds the tile sheets the Dungeon (isometric) and Hex templates use from
# Kenney's CC0 packs (kenney.nl), into assets/kenney/ - run once after
# downloading and unzipping the packs; make_templates.py copies the result.
#
#   scripts/templates/prep_kenney_art.sh <isometric-miniature-dungeon dir> <hexagon-tiles dir>
#
# Needs ImageMagick (magick). The packs' License.txt files are copied too.
set -euo pipefail
dun="$1/Isometric"
chr="$1/Characters/Male"
hex="$2/Tiles"
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/assets/kenney/iso-dungeon"
hout="$root/assets/kenney/hexagon"
mkdir -p "$out" "$hout"
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

# Dungeon tiles: 128 x 144 each (the pack's 256 x 512 at half size, the
# empty top cut off), 8 a row. The floor's diamond (128 x 64) is 10 px
# above the image's bottom (its slab): the maps' Tile Offset is 0, 10.
tiles=(
	stone_N stoneTile_N stoneUneven_N stoneMissingTiles_N dirt_N dirtTiles_N planks_N stoneInset_N
	stoneWall_N stoneWall_E stoneWall_S stoneWall_W stoneWallCorner_N stoneWallCorner_E stoneWallCorner_S stoneWallCorner_W
	stoneWallDoorClosed_N stoneWallDoorClosed_E stoneWallDoorClosed_S stoneWallDoorClosed_W stoneWallDoorOpen_N stoneWallDoorOpen_E stoneWallDoorOpen_S stoneWallDoorOpen_W
	stoneWallWindow_N stoneWallWindow_E stoneWallWindow_S stoneWallWindow_W stoneWallColumn_N stoneWallColumn_E stoneWallColumn_S stoneWallColumn_W
	chestClosed_N chestClosed_E chestClosed_S chestClosed_W chestOpen_N chestOpen_E chestOpen_S chestOpen_W
	barrel_S barrels_S barrelsStacked_S woodenCrate_S woodenCrates_S stoneColumn_N tableRoundChairs_S woodenPile_S
)
i=0
for t in "${tiles[@]}"; do
	magick "$dun/$t.png" -crop 256x288+0+224 +repage -resize 50% "$tmp/t$(printf %03d $i).png"
	i=$((i + 1))
done
magick montage "$tmp"/t*.png -tile 8x -geometry 128x144+0+0 -background none "$out/tiles.png"

# The hero: 64 x 84 frames (feet at 32, 74), a row per facing - NE, E, SE,
# S, SW, W, NW, N - each: idle, then the 10 run frames.
rm -f "$tmp"/h*.png
for d in 0 1 2 3 4 5 6 7; do
	frames=("$chr/Male_${d}_Idle0.png")
	for f in 0 1 2 3 4 5 6 7 8 9; do frames+=("$chr/Male_${d}_Run$f.png"); done
	k=0
	for f in "${frames[@]}"; do
		magick "$f" -resize 50% -crop 64x84+32+154 +repage "$tmp/h${d}_$(printf %02d $k).png"
		k=$((k + 1))
	done
done
magick montage "$tmp"/h*.png -tile 11x -geometry 64x84+0+0 -background none "$out/hero.png"
cp "$1/License.txt" "$out/License.txt"

# Hex: the land tiles (65 x 89: a 65 x 66 hexagon on a 23 px slab - Tile
# Offset 0, 23), and the things standing on them (65 x 107, bottom-centred).
magick montage "$hex"/tileGrass.png "$hex"/tileGrass_tile.png "$hex"/tileDirt.png "$hex"/tileSand.png "$hex"/tileStone.png "$hex"/tileSnow.png "$hex"/tileAutumn.png "$hex"/tileWater.png \
	-tile 8x -geometry 65x89+0+0 -background none "$hout/tiles.png"
rm -f "$tmp"/o*.png
k=0
for t in treeGreen_mid treeGreen_high pineGreen_mid pineGreen_high treeAutumn_mid rockStone rockStone_moss1 bushGrass flowerRed flowerYellow flowerBlue hillGrass; do
	magick "$hex/$t.png" -background none -gravity south -extent 65x107 "$tmp/o$(printf %02d $k).png"
	k=$((k + 1))
done
magick montage "$tmp"/o*.png -tile 6x -geometry 65x107+0+0 -background none "$hout/objects.png"
cp "$hex/alienBlue.png" "$hout/alien.png"
cp "$2/License.txt" "$hout/License.txt"
echo "Wrote $out and $hout"
