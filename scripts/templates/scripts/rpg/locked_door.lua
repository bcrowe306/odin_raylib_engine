-- The locked door: with the key, E opens it (the wall body goes).

---@class LockedDoor : ScriptInstanceBase
local LockedDoor = {}

function LockedDoor:ready()
    self.open = false
end

function LockedDoor:can_interact() return not self.open end
function LockedDoor:hint(player) return player.has_key and "Unlock" or "Locked" end

function LockedDoor:interact(player)
    if self.open then return end
    if not player.has_key then
        Scene.find_node("HUD"):get_script():message("It's locked.", 1.2)
        return
    end
    self.open = true
    self.node:get_child("Sprite"):animation_play("open")
    -- No longer blocks: the body is switched off (the sprite stays).
    self.node:set_collision_mask()
    self.node:set_collision_layer()
end

return LockedDoor
