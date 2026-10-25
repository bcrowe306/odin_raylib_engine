# Platformer Adventure (sample)

The Platformer template grown into a small game: a title screen, two
levels, saved progress and a pause menu. Open it to see how the pieces fit;
copy what you need into your own game.

| Play | |
|---|---|
| Move / jump | as in the Platformer template |
| Menus | up / down to pick, Enter / Space / gamepad A to choose |
| Pause | Esc, P, gamepad Start |

## How it fits together

| | |
|---|---|
| `scenes/title.scene.json` | The first scene (project.json's initial scene): New game / Continue |
| `scenes/level1`, `level2` | Levels; the door's *Next Level* chains them (the last goes back to the title) |
| `scripts/goal.lua` | Finishing a level saves where Continue starts (`Save`) |
| `scripts/menu.lua` | Text menus for the title and the pause menu - the pause menu's node has *Pause Mode: Always*, so it runs while `Engine.set_paused(true)` stops the rest |
| everything else | the Platformer template's scripts |
