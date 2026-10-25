package engine

// The release version of the engine, the editor and the runners (the git
// tag in CI: -define:ORE_RELEASE=1.2.3; scripts/package_editor.sh). The .ore
// package format has its own number (ORE_VERSION, ore_package.odin).
ORE_RELEASE :: #config(ORE_RELEASE, "0.0.0-dev")
