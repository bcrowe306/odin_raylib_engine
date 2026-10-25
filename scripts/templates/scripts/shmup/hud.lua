-- The HUD: score, best score (saved: Save), lives, game over.

---@class Hud : ScriptInstanceBase
local Hud = {}

function Hud:ready()
    self.score = 0
    self.best = Save.get("best_score", 0)
    self:refresh()
end

function Hud:refresh()
    self.node:get_child("Score").text = string.format("Score %d", self.score)
    self.node:get_child("High").text = string.format("Best %d", self.best)
end

function Hud:add_score(n)
    self.score = self.score + n
    if self.score > self.best then
        self.best = self.score
        Save.set("best_score", self.best)
    end
    self:refresh()
end

function Hud:set_lives(n)
    self.node:get_child("Lives").text = string.format("Lives %d", math.max(n, 0))
end

function Hud:game_over()
    self.node:get_child("Message").text = "Game over\nFire to play again"
    Save.flush()
end

return Hud
