package engine

import "core:log"
import rl "vendor:raylib"

TextureNode :: struct {
	using node: Node,
	filePath: string,
	size: [2]f32,
	texture: ^Texture,
	origin: rl.Vector2,
}

TextureNode_Init :: proc(texture: ^TextureNode) {
	InitializeNode(texture)
	texture.render = TextureNode_Render
}

TextureNode_Create :: proc(scene: ^Scene, resource_manager: ^ResourceManager, filePath: string) -> ^TextureNode {
	textureNode := CreateNode(scene.manager, TextureNode)
	TextureNode_Init(textureNode)
	tex, ok := resource_manager.loadTexture(resource_manager, filePath)
	if ok {
		textureNode.texture = tex
		textureNode.size.x = auto_cast tex.texture.width
		textureNode.size.y = auto_cast tex.texture.height
	}
	else {
		log.error("Failed to load teture from file: ", filePath)
	}
	scene->addNode(textureNode)
	return textureNode
}

TextureNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	textureNode := cast(^TextureNode)node
	if textureNode.texture == nil do return
	source := rl.Rectangle{
		x = 0,
		y = 0,
		width = auto_cast textureNode.texture.texture.width,
		height = auto_cast textureNode.texture.texture.height,
	}

	destination := rl.Rectangle{
		x = textureNode.position.x,
		y = textureNode.position.y,
		width = textureNode.size.x * textureNode.scale.x,
		height = textureNode.size.y * textureNode.scale.y
	}
	rl.DrawTexturePro(textureNode.texture.texture, source, destination, textureNode.origin, textureNode.rotation, rl.WHITE)
}
/*
* Inputs:
* textureNode: ^TextureNode
* sizePercentage: f32: Decimal percentage to scale texture node
*/
