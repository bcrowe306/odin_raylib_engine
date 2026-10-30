package engine

import "core:math"
import "core:strings"
import "core:testing"

// #204: a Sound Effect with several sounds - the play modes' picks,
// weights, variation, cooldown, random delay; saved and loaded.

@(private = "file")
sound_game :: proc(name: string) -> (^Game, ^Scene, ^SoundNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene(name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	sn := cast(^SoundNode)Node_CreateByTypeName(scene, "SoundNode")
	sn.name = "Sfx"
	for p in ([]string{"audio/a.wav", "audio/b.wav", "audio/c.wav"}) do SoundNode_AddSound(sn, nil, p)
	return game, scene, sn
}

@(private = "file")
picks :: proc(sn: ^SoundNode, n: int) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	for _ in 0 ..< n do for i in SoundNode_Pick(sn) do append(&out, i)
	return out[:]
}

@(test)
test_sound_play_modes :: proc(t: ^testing.T) {
	game, _, sn := sound_game("modes")
	defer game->terminate()
	sn.playMode = .Single
	sn.single = 2
	testing.expect_value(t, picks(sn, 1)[0], 1)
	sn.playMode = .All
	testing.expect_value(t, len(SoundNode_Pick(sn)), 3)
	sn.playMode = .Sequential
	sn.nextIndex = 0
	p := picks(sn, 4)
	testing.expect(t, p[0] == 0 && p[1] == 1 && p[2] == 2 && p[3] == 0, "sequential: 0 1 2 0")
	sn.playMode = .Sequential_Reversed
	sn.nextIndex = 0
	p = picks(sn, 4)
	testing.expect(t, p[0] == 2 && p[1] == 1 && p[2] == 0 && p[3] == 2, "reversed: 2 1 0 2")

	// Random: never the same twice in a row; a weight-0 sound never.
	sn.playMode = .Random
	sn.sounds[1].weight = 0
	p = picks(sn, 300)
	for i in 1 ..< len(p) do testing.expect(t, p[i] != p[i - 1], "no immediate repeat")
	for x in p do testing.expect(t, x != 1, "weight 0: never")
	sn.sounds[1].weight = 1

	// Shuffle: each sound once a round, no repeat across rounds.
	sn.playMode = .Shuffle
	p = picks(sn, 9)
	for round in 0 ..< 3 {
		seen: [3]bool
		for k in 0 ..< 3 do seen[p[round * 3 + k]] = true
		testing.expect(t, seen[0] && seen[1] && seen[2], "every sound in each round")
	}
	for i in 1 ..< len(p) do testing.expect(t, p[i] != p[i - 1], "no repeat at a round's start")
}

@(test)
test_sound_variation_cooldown_delay :: proc(t: ^testing.T) {
	game, _, sn := sound_game("variation")
	defer game->terminate()
	sn.volumeRandom, sn.pitchRandom, sn.panRandom = 0.2, 2, 0.5
	lo, hi := math.pow(f32(2), -2.0 / 12), math.pow(f32(2), 2.0 / 12)
	for _ in 0 ..< 200 {
		v := SoundNode_RollVariation(sn)
		testing.expect(t, abs(v.volume) <= 0.2 && abs(v.pan) <= 0.5, "volume / pan within +/-")
		testing.expect(t, v.pitch >= lo - 0.0001 && v.pitch <= hi + 0.0001, "pitch within +/- 2 semitones")
	}
	// The cooldown skips plays until it's over.
	sn.playMode = .Sequential
	sn.cooldown = 0.5
	SoundNode_Play(sn)
	SoundNode_Play(sn)
	testing.expect_value(t, sn.nextIndex, 1)
	SoundNode_Update(sn, &game.gameContext, 0.6)
	SoundNode_Play(sn)
	testing.expect_value(t, sn.nextIndex, 2)
	// A random delay: the play waits.
	sn.cooldown, sn.cooldownLeft = 0, 0
	sn.delayRandom = 1
	for len(sn.pending) == 0 do SoundNode_Play(sn) // (a draw can be ~0: it plays at once)
	SoundNode_Update(sn, &game.gameContext, 1.1)
	testing.expect_value(t, len(sn.pending), 0)
}

@(test)
test_sound_list_saved :: proc(t: ^testing.T) {
	game, scene, sn := sound_game("saved")
	defer game->terminate()
	sn.sounds[1].weight = 0.5
	sn.playMode = .Shuffle
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"sounds": ["audio/a.wav", {"path": "audio/b.wav", "weight": 0.5}, "audio/c.wav"]`), "saved: %s", saved)
	testing.expectf(t, strings.contains(saved, `"playMode": "Shuffle"`), "mode saved: %s", saved)
	again := game->createScene("saved2", false)
	_ = Scene_InstantiateFromJSON(again, transmute([]u8)saved, &game.gameContext)
	ProcessNodeQueues(again.manager, &game.gameContext)
	found := false
	for n in again.manager.nodes do if n != nil && n.typeId == SoundNode {
		s := cast(^SoundNode)n
		found = true
		testing.expect_value(t, len(s.sounds), 3)
		testing.expect_value(t, s.sounds[1].weight, 0.5)
		testing.expect_value(t, s.playMode, Sound_Play_Mode.Shuffle)
	}
	testing.expect(t, found, "loaded")
	// An older scene's single "audio": a one-sound list.
	old := `{"name": "old", "root": {"type": "Node", "name": "root", "children": [{"type": "SoundNode", "name": "Old", "audio": "audio/old.wav"}]}}`
	s3 := game->createScene("old", false)
	_ = Scene_InstantiateFromJSON(s3, transmute([]u8)string(old), &game.gameContext)
	ProcessNodeQueues(s3.manager, &game.gameContext)
	for n in s3.manager.nodes do if n != nil && n.typeId == SoundNode {
		testing.expect_value(t, len((cast(^SoundNode)n).sounds), 1)
		testing.expect(t, strings.has_suffix((cast(^SoundNode)n).sounds[0].path, "audio/old.wav"), "its path")
	}
}
