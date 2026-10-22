package engine

import "core:mem"
import rl "vendor:raylib"

// ============================================================================
// Standardized Engine Asset Types
// ============================================================================

AssetType :: enum {
	Unknown = 0,
	Texture,
	AudioSound,
	AudioMusic,
	Script,
	Font,
	Scene,
	LdtkProject,
}

AssetMetadata :: struct {
	path:        string,
	type:        AssetType,
	byteSize:    int,
	isEmbedded:  bool,
	isPacked:    bool,
}

TextureAsset :: struct {
	using metadata: AssetMetadata,
	texture:        rl.Texture2D,
	width:          int,
	height:         int,
}

AudioAsset :: struct {
	using metadata: AssetMetadata,
	isMusic:        bool,
	sound:          rl.Sound,
	music:          rl.Music,
}

ScriptAsset :: struct {
	using metadata: AssetMetadata,
	sourceCode:     string,
	properties:     [dynamic]ScriptProperty,
}

FontAsset :: struct {
	using metadata: AssetMetadata,
	font:           rl.Font,
	baseSize:       int,
}

SceneAsset :: struct {
	using metadata: AssetMetadata,
	jsonContent:    string,
}
