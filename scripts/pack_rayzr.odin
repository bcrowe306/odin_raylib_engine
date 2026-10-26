package pack_rayzr

import "core:fmt"
import "core:os"
import e "../engine"

// Packs a project folder into a .rayzr (the engine's package format,
// engine/RAYZR_FORMAT.md) without the editor - for tests that run projects
// as exported games (scripts/web/test_project.sh: the web runner).
//
//   odin run scripts/pack_rayzr.odin -file -- <project-dir> <out.rayzr>
main :: proc() {
	if len(os.args) != 3 {
		fmt.eprintln("usage: pack_rayzr <project-dir> <out.rayzr>")
		os.exit(2)
	}
	if !e.RayzrPackage_CreateFromDirectory(os.args[1], os.args[2]) {
		fmt.eprintfln("pack_rayzr: could not pack %s", os.args[1])
		os.exit(1)
	}
	fmt.printfln("%s -> %s", os.args[1], os.args[2])
}
