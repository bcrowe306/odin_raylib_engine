package engine

import "core:log"
import rl "vendor:raylib"

TextureNode :: struct {
	using node: Node,
	filePath: string,
	size: [2]f32,
	texture: ^Texture,
	origin: rl.Vector2,
	tint: rl.Color `gui:"true"`, // multiplies the texture ({} = white)
}

TextureNode_Init :: proc(texture: ^TextureNode) {
	InitializeNode(texture)
	texture.render = TextureNode_Render
	texture.tint = rl.WHITE
	texture.onDestroy = TextureNode_Destroy
}

// TextureNode_SetTexture swaps the node's texture, releasing the old one.
TextureNode_SetTexture :: proc(tn: ^TextureNode, tex: ^Texture) {
	if tn.texture == tex do return
	if tn.texture != nil do ResourceManager_ReleaseTexture(Node_ResourceManager(tn), tn.texture)
	tn.texture = tex
}

TextureNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	tn := cast(^TextureNode)node
	if tn.texture != nil {
		rm := &gameContext.game.resourceManager if gameContext != nil && gameContext.game != nil else Node_ResourceManager(tn)
		ResourceManager_ReleaseTexture(rm, tn.texture)
		tn.texture = nil
	}
}

TextureNode_Create :: proc(scene: ^Scene, resource_manager: ^ResourceManager, filePath: string) -> ^TextureNode {
	textureNode := CreateNode(scene.manager, TextureNode)
	TextureNode_Init(textureNode)
	tex, ok := resource_manager.loadTexture(resource_manager, filePath)
	if ok {
		textureNode.texture = tex
		textureNode.size.x = auto_cast tex.texture.width
		textureNode.size.y = auto_cast tex.texture.height
		textureNode.origin = {textureNode.size.x * 0.5, textureNode.size.y * 0.5}
	} else {
		log.error("Failed to load texture from file: ", filePath)
	}
	scene->addNode(textureNode)
	return textureNode
}

TextureNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	textureNode := cast(^TextureNode)node
	if textureNode.texture == nil || textureNode.texture.texture.id == 0 do return

	source := rl.Rectangle{
		x = 0,
		y = 0,
		width = auto_cast textureNode.texture.texture.width,
		height = auto_cast textureNode.texture.texture.height,
	}

	pos := textureNode.globalPosition
	scl := textureNode.globalScale
	rot := textureNode.globalRotation

	// The pivot: `origin` (unscaled px), else the centre. A negative scale
	// mirrors the image around it.
	origin := textureNode.origin
	if origin == {0, 0} do origin = textureNode.size * 0.5
	tint := textureNode.tint if textureNode.tint != {} else rl.WHITE
	Texture_DrawScaled(textureNode.texture.texture, source, pos, textureNode.size, scl, origin, rot, tint)
}
