-- Carves a crater into the terrain it's attached to and shows the colliders
-- (vector collision golden scene, Phase 14 V.16).
local Crater = {}

function Crater:ready()
    Physics.set_debug_draw(true)
    self.node:vector_cut(Vec2(300, 420), 60)
    self.node:vector_cut_polygon({Vec2(760, 380), Vec2(800, 380), Vec2(780, 430)})
end

return Crater
