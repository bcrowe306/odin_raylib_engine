-- The wizard: talking to him (E when close) shows his lines in the
-- Dialogue box (E / Enter goes on).

---@class Npc : ScriptInstanceBase
local Npc = {}

Npc.properties = {
    speaker = { type = "string", default = "Wizard", label = "Name" },
}

local LINES = {
    "Ah, a visitor! The way out is locked, I'm afraid.",
    "The key is in a chest in the next room...",
    "...past the slimes. Space swings your sword. Good luck!",
}

function Npc:hint() return "Talk" end

function Npc:interact(player)
    local lines = {}
    for i, l in ipairs(LINES) do lines[i] = { speaker = self.speaker, text = l } end
    Scene.find_node("Dialogue"):dialogue_show(lines)
end

return Npc
