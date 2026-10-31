-- The island: a Hex (pointy) map. Click a hex and the explorer walks there
-- hex by hex (a path round the water, trees and rocks); D / A / E / Q / C /
-- Z take one step right, left, up-right, up-left, down-right, down-left.
-- Pick every flower.
--
-- Maps: Ground (land and water), Objects (trees, rocks, flowers; Y Sort,
-- so the explorer walks behind trees) and Walk - an invisible map of the
-- hexes that can be walked on, made here from the other two (paths are
-- found in it: on a hex map they step to the six neighbours).

---@class Island : ScriptInstanceBase
local Island = {}

local WATER = 7                                   -- in textures/hex_tiles.png
local FLOWERS = { [8] = true, [9] = true, [10] = true } -- in textures/hex_objects.png (the rest block)

-- One step: the hex's six sides clockwise from the right (map:tilemap_neighbors' order).
local STEP_KEYS = { "step_e", "step_se", "step_sw", "step_w", "step_nw", "step_ne" }

function Island:ready()
    self.ground = Scene.find_node("Ground") ---@type TileMapNode
    self.objects = Scene.find_node("Objects") ---@type TileMapNode
    self.walk = Scene.find_node("Walk") ---@type TileMapNode
    self.unit = Scene.find_node("Explorer"):get_script()
    self.counter = Scene.find_node("Flowers")
    self.message = Scene.find_node("Message")
    self.picked, self.total = 0, 0
    for y = 0, 40 do
        for x = 0, 40 do
            local g, o = self.ground:tilemap_get_tile(x, y), self.objects:tilemap_get_tile(x, y)
            if FLOWERS[o] then self.total = self.total + 1 end
            local open = g >= 0 and g ~= WATER and (o < 0 or FLOWERS[o])
            self.walk:tilemap_set_tile(x, y, open and 0 or -1)
        end
    end
    self:count()
end

function Island:count()
    self.counter.text = "Flowers " .. self.picked .. " / " .. self.total
end

-- walkable: a hex the explorer can stand on.
function Island:walkable(cx, cy)
    return self.walk:tilemap_get_tile(cx, cy) >= 0
end

-- arrived: the explorer stepped onto a hex - a flower there is picked.
function Island:arrived(cx, cy)
    if FLOWERS[self.objects:tilemap_get_tile(cx, cy)] then
        self.objects:tilemap_set_tile(cx, cy, -1)
        self.picked = self.picked + 1
        self:count()
        if self.picked == self.total then self.message.text = "Every flower picked!" end
    end
end

function Island:update(dt)
    -- The mouse: the hex under it; a click walks there.
    local wx, wy = Camera.screen_to_world(Input.get_mouse_position())
    self.cx, self.cy = self.walk:tilemap_cell_at(wx, wy)
    if Input.is_mouse_button_pressed("LEFT") and self:walkable(self.cx, self.cy) then
        self.unit:go_to(self.cx, self.cy)
    end
    -- The keys: one step to a side.
    if not self.unit:busy() then
        local ux, uy = self.unit:cell()
        local sides = self.walk:tilemap_neighbors(ux, uy)
        for i, action in ipairs(STEP_KEYS) do
            if Input.is_action_pressed(action) and self:walkable(sides[i][1], sides[i][2]) then
                self.unit:go_to(sides[i][1], sides[i][2])
            end
        end
    end
end

-- on_draw: the hex under the mouse and the path still to walk (this node
-- is at 0, 0: its space is the world's).
function Island:on_draw()
    if self.cx then
        local pts = self.walk:tilemap_cell_outline(self.cx, self.cy)
        Vector.begin_path()
        Vector.move_to(pts[1][1], pts[1][2])
        for i = 2, #pts do Vector.line_to(pts[i][1], pts[i][2]) end
        Vector.close_path()
        local ok = self:walkable(self.cx, self.cy)
        Vector.fill_color(ok and "#ffffff38" or "#ff404030")
        Vector.fill()
        Vector.stroke_color(ok and "#ffffffd0" or "#ff6060c0")
        Vector.stroke_width(2)
        Vector.stroke()
    end
    for _, p in ipairs(self.unit.path or {}) do
        Vector.begin_path()
        Vector.circle(p[1], p[2], 4)
        Vector.fill_color("#ffe066d0")
        Vector.fill()
    end
end

return Island
