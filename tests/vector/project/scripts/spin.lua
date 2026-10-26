-- Benchmark: every character turns (only their transforms change: the
-- cached meshes are drawn with a new matrix each frame).
local Spin = {}

function Spin:ready()
    self.nodes = Scene.find_by_tag("spin")
end

function Spin:update(dt)
    for i, n in ipairs(self.nodes) do
        n.rotation = n.rotation + (20 + i % 7 * 5) * dt
    end
end

return Spin
