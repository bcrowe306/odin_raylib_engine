package engine

import "core:math"
import "core:os"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

SPINE_FIXTURE :: `{
"skeleton": {"spine": "4.2.22", "width": 100, "height": 200},
"bones": [
	{"name": "root"},
	{"name": "hip", "parent": "root", "y": 100},
	{"name": "arm", "parent": "hip", "length": 50, "rotation": 90},
	{"name": "hand", "parent": "arm", "x": 50, "length": 30},
	{"name": "target", "parent": "root", "x": 60, "y": 150}
],
"slots": [
	{"name": "body", "bone": "hip", "attachment": "body"},
	{"name": "arm", "bone": "arm", "attachment": "armmesh", "color": "ff8080ff"}
],
"ik": [{"name": "reach", "bones": ["arm", "hand"], "target": "target", "mix": 0}],
"skins": [{"name": "default", "attachments": {
	"body": {"body": {"width": 32, "height": 32}, "body2": {"width": 32, "height": 32, "path": "body2"}},
	"arm": {"armmesh": {"type": "mesh", "path": "arm", "uvs": [0, 0, 1, 0, 1, 1, 0, 1], "triangles": [0, 1, 2, 0, 2, 3],
		"vertices": [1, 2, 0, 10, 1, 1, 2, 50, 10, 1, 1, 3, 0, -10, 1, 1, 2, 0, -10, 1]}}
}}],
"events": {"step": {"int": 3}},
"animations": {
	"wave": {
		"bones": {"arm": {"rotate": [{"time": 0, "value": 0, "curve": [0.42, 0, 1, 90]}, {"time": 1, "value": 90}]}},
		"slots": {"body": {"attachment": [{"time": 0.75, "name": "body2"}]}},
		"events": [{"time": 0.5, "name": "step"}]
	},
	"idle": {"bones": {"hip": {"translate": [{"time": 0, "x": 0, "y": 0}, {"time": 2, "x": 0, "y": 10}]}}}
}}`

SPINE_ATLAS_FIXTURE :: `
skel_zz.png
size:64,64
filter:Linear,Linear
body
bounds:0,0,32,32
body2
bounds:32,0,32,32
arm
bounds:0,32,64,32
rotate:90
`

DB_FIXTURE :: `{"frameRate": 24, "name": "Dragon", "version": "5.5", "armature": [{"type": "Armature", "frameRate": 24, "name": "Dragon",
"bone": [
	{"name": "root"},
	{"name": "body", "parent": "root", "length": 40, "transform": {"x": 10, "y": -20, "skX": 30, "skY": 30}},
	{"name": "head", "parent": "body", "transform": {"x": 40}}
],
"slot": [{"name": "head", "parent": "head", "displayIndex": 0}],
"skin": [{"slot": [{"name": "head", "display": [{"name": "parts/head"}, {"name": "parts/head_b"}]}]}],
"animation": [{"name": "nod", "duration": 24, "playTimes": 0,
	"bone": [{"name": "head", "rotateFrame": [{"duration": 12, "tweenEasing": 0, "rotate": 0}, {"duration": 12, "tweenEasing": 0, "rotate": 20}, {"duration": 0, "rotate": 0}]}],
	"slot": [{"name": "head", "displayFrame": [{"duration": 18, "value": 0}, {"duration": 6, "value": 1}]}],
	"frame": [{"duration": 6}, {"duration": 18, "events": [{"name": "blink"}]}]
}]}]}`

DB_TEX_FIXTURE :: `{"imagePath": "dragon_zz_tex.png", "SubTexture": [
	{"name": "parts/head", "x": 0, "y": 0, "width": 20, "height": 20},
	{"name": "parts/head_b", "x": 20, "y": 0, "width": 20, "height": 20}
]}`

// Skeletal animation: the Spine and DragonBones importers (axes flipped /
// skew mapped, atlas regions, weighted meshes, IK, curves, events, slot
// switches), poses and world transforms, and the node: playback, events,
// finished, a bone attachment following its bone, the shared cache, Lua.
@(test)
test_skeleton_import_and_runtime :: proc(t: ^testing.T) {
	// --- Spine ---------------------------------------------------------------------------
	atlas := Skel_ParseAtlas(SPINE_ATLAS_FIXTURE, context.temp_allocator)
	testing.expect(t, len(atlas.pages) == 1 && atlas.pages[0] == "skel_zz.png", "the page")
	arm := atlas.regions["arm"]
	testing.expect(t, arm.rotated && arm.bounds == {0, 32, 32, 64}, "rotated region: the page holds it turned")
	d, ok := Skeleton_LoadSpine(SPINE_FIXTURE, SPINE_ATLAS_FIXTURE, nil, nil)
	testing.expect(t, ok && d != nil, "spine loads")
	if d == nil do return
	defer Skeleton_DataDestroy(d, nil)
	testing.expect(t, len(d.bones) == 5 && d.bones[2].parent == 1 && d.bones[2].rotation == -90 && d.bones[1].y == -100, "bones (y and angles flipped)")
	testing.expect(t, len(d.slots) == 2 && d.slots[1].color[1] < 0.6, "slots")
	nb, hasBody := Skeleton_Attachment(d, 0, 0, "body")
	testing.expect(t, hasBody && nb.(Skel_Region).texture == nil, "a page that didn't load: the region stays (drawn once it has a texture)")

	// With a loader: attachments resolve.
	fake := new(Texture)
	defer free(fake)
	fake.texture = {id = 0, width = 64, height = 64}
	loader :: proc(page: string, data: rawptr) -> ^Texture {return cast(^Texture)data}
	d2, _ := Skeleton_LoadSpine(SPINE_FIXTURE, SPINE_ATLAS_FIXTURE, loader, fake)
	defer {clear(&d2.textures); Skeleton_DataDestroy(d2, nil)}
	body, hb := Skeleton_Attachment(d2, 0, 0, "body")
	testing.expect(t, hb && body.(Skel_Region).uv == {0, 0, 32, 32}, "region from the atlas")
	mesh, hm := Skeleton_Attachment(d2, 0, 1, "armmesh")
	m := mesh.(Skel_Mesh)
	testing.expect(t, hm && len(m.uvs) == 4 && len(m.bonesOf) == 4 && m.bonesOf[1][0] == 2 && m.offsets[0][0] == {0, -10}, "weighted mesh (offsets flipped)")

	pose: Skeleton_Pose
	Skeleton_PoseInit(&pose, d2)
	defer Skeleton_PoseDestroy(&pose)
	wave := Skeleton_AnimationIndex(d2, "wave")
	testing.expect(t, wave >= 0 && abs(d2.animations[wave].duration - 1) < 0.001, "animation duration")
	Skeleton_Apply(&pose, d2, wave, 0.5)
	rot := pose.bones[2].rotation - d2.bones[2].rotation
	testing.expectf(t, rot < 0 && rot > -45, "ease-in curve: under half way at half time (%v)", rot)
	Skeleton_SetupPose(&pose, d2)
	Skeleton_Apply(&pose, d2, wave, 0.8)
	testing.expect_value(t, pose.attachments[0], "body2")
	evs := make([dynamic]Skel_Key, context.temp_allocator)
	Skeleton_EventsBetween(d2, wave, 0.4, 0.6, &evs)
	testing.expect(t, len(evs) == 1 && evs[0].name == "step" && evs[0].ivalue == 3, "event with its defaults")
	clear(&evs)
	Skeleton_EventsBetween(d2, wave, 0.9, 0.1, &evs) // (wrapped: nothing in 0.9..1 / 0..0.1)
	testing.expect_value(t, len(evs), 0)

	// World: the hip 100 px above the origin (y-up in Spine = -y here).
	Skeleton_SetupPose(&pose, d2)
	Skeleton_UpdateWorld(&pose, d2, {200, 300})
	testing.expectf(t, abs(pose.bones[1].wx - 200) < 0.01 && abs(pose.bones[1].wy - 200) < 0.01, "hip world (%v, %v)", pose.bones[1].wx, pose.bones[1].wy)
	// The arm points up (Spine rotation 90 = up): its tip is 50 px above the hip.
	tip := Skeleton_LocalToWorld(pose.bones[2], {50, 0})
	testing.expectf(t, abs(tip.x - 200) < 0.01 && abs(tip.y - 150) < 0.01, "arm tip (%v)", tip)

	// IK: with mix 1 the hand's tip reaches the target (reachable).
	d2.ik[0].mix = 1
	Skeleton_SetupPose(&pose, d2)
	pose.bones[4].x, pose.bones[4].y = 40, -140 // target
	Skeleton_UpdateWorld(&pose, d2, {0, 0})
	hand := pose.bones[3]
	htip := Skeleton_LocalToWorld(hand, {30, 0})
	target := [2]f32{pose.bones[4].wx, pose.bones[4].wy}
	testing.expectf(t, math.sqrt((htip.x - target.x) * (htip.x - target.x) + (htip.y - target.y) * (htip.y - target.y)) < 1, "IK reaches the target (%v vs %v)", htip, target)

	// --- DragonBones ----------------------------------------------------------------------
	db, dok := Skeleton_LoadDragonBones(DB_FIXTURE, DB_TEX_FIXTURE, "", loader, fake)
	testing.expect(t, dok && db != nil, "dragonbones loads")
	if db == nil do return
	defer {clear(&db.textures); Skeleton_DataDestroy(db, nil)}
	testing.expect(t, db.bones[1].rotation == 30 && db.bones[1].shearY == 0 && db.bones[1].y == -20, "skew -> rotation")
	testing.expect_value(t, db.slots[0].attachment, "parts/head")
	nod := Skeleton_AnimationIndex(db, "nod")
	testing.expectf(t, nod >= 0 && abs(db.animations[nod].duration - 1) < 0.001, "duration in seconds (%v)", db.animations[nod].duration)
	dp: Skeleton_Pose
	Skeleton_PoseInit(&dp, db)
	defer Skeleton_PoseDestroy(&dp)
	Skeleton_Apply(&dp, db, nod, 0.75)
	testing.expectf(t, abs(dp.bones[2].rotation - 10) < 0.01, "rotate frames relative to the setup (%v)", dp.bones[2].rotation)
	testing.expect_value(t, dp.attachments[0], "parts/head_b")
	clear(&evs)
	Skeleton_EventsBetween(db, nod, 0.2, 0.3, &evs)
	testing.expect(t, len(evs) == 1 && evs[0].name == "blink", "frame event at 6/24 s")

	// --- the node -----------------------------------------------------------------------------
	dir :: "test_skeleton_zz"
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	_ = os.write_entire_file(dir + "/hero.json", transmute([]u8)string(SPINE_FIXTURE))
	_ = os.write_entire_file(dir + "/hero.atlas", transmute([]u8)string(SPINE_ATLAS_FIXTURE))
	img := rl.GenImageColor(64, 64, rl.WHITE)
	rl.ExportImage(img, dir + "/skel_zz.png")
	rl.UnloadImage(img)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	game.resourceManager.projectDir = game.assetManager.projectDir
	scene := game->createScene("skel", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	sn := cast(^SkeletonNode)Node_CreateByTypeName(scene, "SkeletonNode")
	sn.name = "Hero"
	sn.file = "hero.json"
	sn.animation, sn.loop = "wave", false
	ba := cast(^BoneAttachmentNode)Node_CreateByTypeName(scene, "BoneAttachmentNode", sn)
	ba.bone = "hand"
	twin := cast(^SkeletonNode)Node_CreateByTypeName(scene, "SkeletonNode")
	twin.file = "hero.json"
	steps, finished := 0, 0
	sn.onEvent->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &steps)
	sn.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(1.0 / 60)
	testing.expect(t, sn.data != nil && sn.data == twin.data && Skeleton_CacheCount() == 1, "loaded once, shared")
	for _ in 0 ..< 70 do game->run(1.0 / 60)
	testing.expect(t, steps == 1 && finished == 1 && !sn.playing, "event once, then finished")
	// The attachment sits at the hand bone (local space of the skeleton).
	hb2 := sn.pose.bones[3]
	testing.expectf(t, abs(ba.position.x - hb2.wx) < 0.01 && abs(ba.position.y - hb2.wy) < 0.01, "bone attachment on the hand (%v)", ba.position)

	// Lua.
	L := game.scriptManager.L
	okL := lua.L_dostring(L, `
local h = Scene.find_node("Hero")
n = #h:skeleton_animations()
played = h:skeleton_play("idle", true, 0)
missing = h:skeleton_play("nope")
local p = h:skeleton_bone_position("hip")
hipy = p and p.y or 0
h:skeleton_set_bone_rotation("arm", -45)
`)
	if okL != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	geti :: proc(L: ^lua.State, n: cstring) -> f64 {lua.getglobal(L, n); defer lua.pop(L, 1); return f64(lua.tonumber(L, -1))}
	getb :: proc(L: ^lua.State, n: cstring) -> bool {lua.getglobal(L, n); defer lua.pop(L, 1); return bool(lua.toboolean(L, -1))}
	testing.expect(t, geti(L, "n") == 2 && getb(L, "played") && !getb(L, "missing"), "animations / play")
	testing.expectf(t, abs(geti(L, "hipy") - f64(sn.globalPosition.y - 100)) < 0.5, "bone position in the world (%v)", geti(L, "hipy"))
	game->run(1.0 / 60)
	testing.expectf(t, abs(sn.pose.bones[2].rotation + 45) < 0.01, "bone rotation override (%v)", sn.pose.bones[2].rotation)

	// (#252) skeleton_play's mix is this crossfade's length (Mix Time 0
	// still crossfades), and the animation already playing keeps going.
	sn.mixTime = 0
	testing.expect(t, lua.L_dostring(L, `Scene.find_node("Hero"):skeleton_play("wave", true, 0.5)`) == 0, "Lua ran")
	testing.expect(t, sn.prevAnim >= 0 && sn.mixLength == 0.5, "a 0.5 s crossfade with Mix Time 0")
	for _ in 0 ..< 12 do game->run(1.0 / 60)
	testing.expect(t, sn.prevAnim >= 0, "still mixing after 0.2 s")
	t0 := sn.time
	testing.expect(t, lua.L_dostring(L, `Scene.find_node("Hero"):skeleton_play("wave")`) == 0, "Lua ran")
	testing.expect(t, sn.time == t0 && sn.prevAnim >= 0, "playing it again doesn't restart it")
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	testing.expect(t, sn.prevAnim < 0, "the crossfade ended")

	// Removing both releases the data.
	RemoveNode(scene.manager, sn)
	RemoveNode(scene.manager, twin)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, Skeleton_CacheCount(), 0)
}
