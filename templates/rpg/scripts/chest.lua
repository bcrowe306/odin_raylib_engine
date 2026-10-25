-- A chest with the key: E opens it (once).

---@class Chest : ScriptInstanceBase
local Chest = {}

function Chest:ready()
    self.opened = false
end

function Chest:can_interact() return not self.opened end
function Chest:hint() return "Open" end

function Chest:interact(player)
    if self.opened then return end
    self.opened = true
    self.node:get_child("Sprite"):animation_play("open")
    player:give_key()
    Scene.find_node("HUD"):get_script():message("You found a key!", 1.5)
end

return Chest
