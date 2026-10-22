// Standalone game runner: plays a data-only project (scenes, Lua scripts,
// assets) with no game-specific code. "Export Standalone Game" in the
// editor builds this next to the game's .ore:
//
//   MyGame/
//     MyGame          (this program)
//     game.ore        (the packaged project)
//     fonts/OpenSans-Regular.ttf
//
// Usage: runner [project-dir | game.ore] [--scene <file>] [--frames N]
//        [--screenshot out.png] [--dump-scene out.json] [--hidden]
//        [--user-data <dir>]  (Save data folder instead of the platform's)
// With no project argument it looks for game.ore (or any .ore, or a
// project/ directory) next to the executable.
package main

import "core:fmt"
import "core:log"
import "core:os"
import e "../engine"

main :: proc() {
	context.logger = log.create_console_logger(.Info)
	opts := e.Engine_ParseRunArgs(os.args[1:])
	if opts.projectPath == "" do opts.projectPath = e.Engine_FindBundledProject(os.args[0])
	if opts.projectPath == "" {
		fmt.eprintln("No game found: put game.ore next to the runner, or pass a project directory / .ore file.")
		os.exit(2)
	}
	os.exit(e.Engine_RunProject(opts))
}
