
package asteroids
import e "../engine"
import "core:log"
import "core:fmt"
import rl "vendor:raylib"

CreateGame :: proc() -> ^e.Game {
	asteroids := new(e.Game)
	e.InitializeGame(asteroids)
	asteroids.setup = GameSetup
	asteroids.update = GameUpdate

	return asteroids
}

GameUpdate :: proc(game: ^e.Game, scene: ^e.Scene, deltaTime: f32) {
}


GameSetup :: proc(game: ^e.Game) {
	log.info("Setup")
	scene := game->createScene("main", true)

	// CreateSpaceShip(scene, game)
	CreatePlayer(scene, game, {100,100})
	CreatePlayer(scene, game, {200,200})
	game.state = .Ready
	game.drawBounds = true


}
