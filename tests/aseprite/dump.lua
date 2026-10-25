-- Writes what Aseprite itself reads in a file as JSON (the reference the
-- engine's reader must match): aseprite -b --script-param file=X
-- --script-param out=Y --script tests/aseprite/dump.lua
local spr = Sprite { fromFile = app.params["file"] }

local function color(c) return c and { c.red, c.green, c.blue, c.alpha } or nil end

local function props(p)
    local out = {}
    for k, v in pairs(p) do out[k] = v end
    return out
end

local function field(v, k)
    local ok, x = pcall(function() return v[k] end)
    if ok then return x end
end

local function value(v)
    local t = type(v)
    if t == "userdata" then
        local x, y, w, h = field(v, "x"), field(v, "y"), field(v, "width"), field(v, "height")
        if x ~= nil and w ~= nil then return { x = x, y = y, width = w, height = h } end
        if w ~= nil then return { width = w, height = h } end
        if x ~= nil then return { x = x, y = y } end
        return tostring(v)
    elseif t == "table" then
        local o = {}
        for k, x in pairs(v) do o[k] = value(x) end
        return o
    end
    return v
end

local function userdata(o)
    local d = { text = o.data, color = color(o.color) }
    local p = {}
    for k, v in pairs(o.properties) do p[k] = value(v) end
    d.properties = p
    return d
end

local function layer_index(l)
    for i, x in ipairs(spr.layers) do if x == l then return i end end
end

local doc = { width = spr.width, height = spr.height, colorMode = spr.colorMode, transparentColor = spr.transparentColor,
    userdata = userdata(spr), frames = {}, layers = {}, tags = {}, slices = {}, palette = {}, tilesets = {} }
for _, f in ipairs(spr.frames) do table.insert(doc.frames, math.floor(f.duration * 1000 + 0.5)) end

-- (Layer objects aren't stable table keys: their place in the tree is.)
local function path(l)
    if l.parent == spr or l.parent == nil or l.parent.__name == "Sprite" then return tostring(l.stackIndex) end
    local ok, p = pcall(function() return l.parent.stackIndex end)
    if not ok then return tostring(l.stackIndex) end
    return path(l.parent) .. "/" .. l.stackIndex
end
local index_of = {}
local function walk(layers, parent, out)
    for _, l in ipairs(layers) do
        index_of[path(l)] = #out
        local e = { name = l.name, parent = parent, visible = l.isVisible, group = l.isGroup, tilemap = l.isTilemap,
            background = l.isBackground, reference = l.isReference, blendMode = l.blendMode, opacity = l.opacity,
            stackIndex = l.stackIndex, userdata = userdata(l) }
        table.insert(out, e)
        if l.isGroup then walk(l.layers, l.name, out) end
    end
end
walk(spr.layers, nil, doc.layers)

doc.cels = {}
for _, c in ipairs(spr.cels) do
    table.insert(doc.cels, { layer = c.layer.name, layerIndex = index_of[path(c.layer)], frame = c.frameNumber, x = c.position.x, y = c.position.y,
        width = c.bounds.width, height = c.bounds.height, opacity = c.opacity, zIndex = c.zIndex, userdata = userdata(c) })
end
for _, t in ipairs(spr.tags) do
    table.insert(doc.tags, { name = t.name, from = t.fromFrame.frameNumber, to = t.toFrame.frameNumber, aniDir = t.aniDir,
        repeats = t.repeats, color = color(t.color), userdata = userdata(t) })
end
for _, s in ipairs(spr.slices) do
    local b, c, p = s.bounds, s.center, s.pivot
    table.insert(doc.slices, { name = s.name, bounds = { b.x, b.y, b.width, b.height },
        center = c and { c.x, c.y, c.width, c.height } or nil, pivot = p and { p.x, p.y } or nil,
        color = color(s.color), userdata = userdata(s) })
end
local pal = spr.palettes[1]
for i = 0, #pal - 1 do table.insert(doc.palette, color(pal:getColor(i))) end
for _, ts in ipairs(spr.tilesets) do
    local e = { name = ts.name, tiles = #ts, grid = { ts.grid.tileSize.width, ts.grid.tileSize.height }, tileData = {} }
    for i = 0, #ts - 1 do table.insert(e.tileData, ts:tile(i).data) end
    table.insert(doc.tilesets, e)
end

local f = io.open(app.params["out"], "w")
f:write(json.encode(doc))
f:close()
