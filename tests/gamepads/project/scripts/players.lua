-- Gamepad test game (tests/gamepads/runtime_tests.json): four players'
-- jumps / dashes, player 2's stick, rumble, prompts and hot-plug events.
local Players = {}

function Players:ready()
    self.jumps = {0, 0, 0, 0}
    self.dashes = {0, 0, 0, 0}
    self.log = Scene.find_node("Log")
end

function Players:on_gamepad_connected(player, name)
    self.log.text = self.log.text .. "+" .. player .. ":" .. Input.device(player) .. " "
end

function Players:on_gamepad_disconnected(player)
    self.log.text = self.log.text .. "-" .. player .. " "
end

function Players:update(dt)
    for p = 1, 4 do
        if Input.is_action_pressed("jump", p) then
            self.jumps[p] = self.jumps[p] + 1
            if p == 2 then Input.vibrate(0.5, 1.0, 0.25, 2) end
        end
        if Input.is_action_pressed("dash", p) then self.dashes[p] = self.dashes[p] + 1 end
    end
    Scene.find_node("Jumps").text = table.concat(self.jumps, " ")
    Scene.find_node("Dashes").text = table.concat(self.dashes, " ")
    local x, y = Input.get_vector(2)
    Scene.find_node("Stick").text = string.format("%.1f %.1f %.1f", x, y, Input.get_axis("move_left", "move_right", 2))
    local low, high = Input.get_vibration(2)
    Scene.find_node("Rumble").text = string.format("%.2f %.2f", low, high)
    local devices = {}
    for p = 1, 4 do devices[p] = Input.device(p) end
    Scene.find_node("Devices").text = table.concat(devices, " ")
    Scene.find_node("Count").text = tostring(Input.player_count())
    -- Prompts: player 2's jump button; player 1's (keyboard until a pad is used).
    local g = Input.glyph("jump", 2)
    if g and g ~= self.glyph then
        Scene.find_node("Prompt"):set_texture(g)
        self.glyph = g
    end
    local g1 = Input.glyph("jump")
    if g1 and g1 ~= self.glyph1 then
        Scene.find_node("Prompt1"):set_texture(g1)
        self.glyph1 = g1
    end
end

return Players
