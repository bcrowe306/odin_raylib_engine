-- Builds the Aseprite test files (TODO E.3) with Aseprite's own scripting:
--   aseprite -b --script tests/aseprite/make_fixtures.lua
-- (scripts/aseprite_fixtures.sh also renders Aseprite's expected frames and
-- metadata next to them: the engine's reader / renderer must match.)
-- Every feature of the format gets a file: layers + every blend mode +
-- opacity, groups, visibility, frames + durations, tags (directions,
-- repeats, colours, user data), linked cels, cel opacity / z-index, slices
-- (9-patch, pivot), user data with every property type, indexed /
-- grayscale colour modes, tilemaps + tilesets (with flips).

local out = app.params["out"] or "tests/aseprite/fixtures/"

local function rgba(r, g, b, a) return app.pixelColor.rgba(r, g, b, a or 255) end

local function fill(img, x0, y0, w, h, c)
    for y = y0, y0 + h - 1 do
        for x = x0, x0 + w - 1 do img:drawPixel(x, y, c) end
    end
end

-- A colourful backdrop: every pixel different, a few transparent.
local function backdrop(w, h)
    local img = Image(w, h, ColorMode.RGB)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local a = ((x + y) % 7 == 0) and 0 or (((x * 3 + y) % 5 == 0) and 128 or 255)
            img:drawPixel(x, y, rgba((x * 13) % 256, (y * 17) % 256, ((x + y) * 9) % 256, a))
        end
    end
    return img
end

local function save(spr, name)
    spr:saveAs(out .. name .. ".aseprite")
    spr:close()
end

-- 1. Every blend mode: a layer per mode over the backdrop, each drawing a
-- semi-transparent pattern in its own column, at its own opacity.
do
    local modes = { BlendMode.NORMAL, BlendMode.MULTIPLY, BlendMode.SCREEN, BlendMode.OVERLAY,
        BlendMode.DARKEN, BlendMode.LIGHTEN, BlendMode.COLOR_DODGE, BlendMode.COLOR_BURN,
        BlendMode.HARD_LIGHT, BlendMode.SOFT_LIGHT, BlendMode.DIFFERENCE, BlendMode.EXCLUSION,
        BlendMode.HSL_HUE, BlendMode.HSL_SATURATION, BlendMode.HSL_COLOR, BlendMode.HSL_LUMINOSITY,
        BlendMode.ADDITION, BlendMode.SUBTRACT, BlendMode.DIVIDE }
    local W, H = #modes * 4, 16
    local spr = Sprite(W, H, ColorMode.RGB)
    spr.layers[1].name = "Backdrop"
    spr:newCel(spr.layers[1], 1, backdrop(W, H), Point(0, 0))
    for i, mode in ipairs(modes) do
        local layer = spr:newLayer()
        layer.name = "Blend" .. i
        layer.blendMode = mode
        layer.opacity = 255 - (i * 9) % 160
        local img = Image(4, H, ColorMode.RGB)
        for y = 0, H - 1 do
            for x = 0, 3 do
                img:drawPixel(x, y, rgba((y * 31 + i * 7) % 256, (x * 60 + y * 5) % 256, (255 - y * 13) % 256, 64 + (y * 12) % 192))
            end
        end
        spr:newCel(layer, 1, img, Point((i - 1) * 4, 0))
    end
    save(spr, "blend_modes")
end

-- 2. Groups: nested, with their own blend mode / opacity; hidden layers
-- and a hidden group; cel opacity.
do
    local spr = Sprite(16, 16, ColorMode.RGB)
    spr.layers[1].name = "Base"
    spr:newCel(spr.layers[1], 1, backdrop(16, 16), Point(0, 0))
    local outer = spr:newGroup(); outer.name = "Outer"; outer.opacity = 200; outer.blendMode = BlendMode.MULTIPLY
    local inner = spr:newGroup(); inner.name = "Inner"; inner.parent = outer; inner.opacity = 180; inner.blendMode = BlendMode.SCREEN
    local a = spr:newLayer(); a.name = "A"; a.parent = outer
    local ia = Image(10, 10, ColorMode.RGB); fill(ia, 0, 0, 10, 10, rgba(250, 40, 40, 200))
    local ca = spr:newCel(a, 1, ia, Point(1, 1)); ca.opacity = 160
    local b = spr:newLayer(); b.name = "B"; b.parent = inner; b.blendMode = BlendMode.DIFFERENCE
    local ib = Image(10, 10, ColorMode.RGB); fill(ib, 0, 0, 10, 10, rgba(40, 220, 90, 230))
    spr:newCel(b, 1, ib, Point(5, 5))
    local hidden = spr:newLayer(); hidden.name = "Hidden"; hidden.isVisible = false
    local ih = Image(16, 16, ColorMode.RGB); fill(ih, 0, 0, 16, 16, rgba(255, 0, 255, 255))
    spr:newCel(hidden, 1, ih, Point(0, 0))
    local hg = spr:newGroup(); hg.name = "HiddenGroup"; hg.isVisible = false
    local hgl = spr:newLayer(); hgl.name = "InHiddenGroup"; hgl.parent = hg
    spr:newCel(hgl, 1, ih, Point(0, 0))
    save(spr, "groups")
end

-- 3. Animation: frames with their own durations, tags in every direction
-- with repeats, colours and user data; a linked cel; moving cels.
do
    local spr = Sprite(8, 8, ColorMode.RGB)
    local layer = spr.layers[1]; layer.name = "Body"
    for f = 1, 8 do
        if f > 1 then spr:newEmptyFrame() end
        spr.frames[f].duration = 0.05 * f
        local img = Image(4, 4, ColorMode.RGB); fill(img, 0, 0, 4, 4, rgba(30 * f, 255 - 25 * f, 100, 255))
        spr:newCel(layer, f, img, Point(f % 5, (f * 2) % 5))
    end
    local function tag(from, to, name, dir, reps, color, text)
        local t = spr:newTag(from, to); t.name = name; t.aniDir = dir; t.repeats = reps; t.color = color
        if text then t.data = text end
        return t
    end
    tag(1, 3, "idle", AniDir.FORWARD, 0, Color { r = 255, g = 0, b = 0 }, "loops")
    tag(3, 5, "walk", AniDir.REVERSE, 2, Color { r = 0, g = 255, b = 0 })
    tag(5, 8, "jump", AniDir.PING_PONG, 1, Color { r = 0, g = 0, b = 255 }, "hop")
    tag(2, 7, "spin", AniDir.PING_PONG_REVERSE, 3, Color { r = 200, g = 100, b = 0 })
    -- A linked cel: frame 8 shares frame 1's image (a second layer).
    local l2 = spr:newLayer(); l2.name = "Linked"
    local limg = Image(2, 2, ColorMode.RGB); fill(limg, 0, 0, 2, 2, rgba(255, 255, 0, 255))
    spr:newCel(l2, 1, limg, Point(6, 6))
    app.range.layers = { l2 }
    app.range.frames = { spr.frames[1], spr.frames[8] }
    app.command.LinkCels()
    save(spr, "animation")
end

-- 4. Cel z-index (cels drawn out of layer order) and cel opacity.
do
    local spr = Sprite(8, 8, ColorMode.RGB)
    local colors = { rgba(255, 0, 0), rgba(0, 255, 0), rgba(0, 0, 255) }
    local layers = { spr.layers[1], spr:newLayer(), spr:newLayer() }
    for i, l in ipairs(layers) do
        l.name = "Z" .. i
        local img = Image(6, 6, ColorMode.RGB); fill(img, 0, 0, 6, 6, colors[i])
        local cel = spr:newCel(l, 1, img, Point(i - 1, i - 1))
        cel.opacity = 255 - i * 40
    end
    layers[1].cels[1].zIndex = 2  -- the bottom layer's cel on top
    layers[3].cels[1].zIndex = -1
    save(spr, "z_index")
end

-- 5. Slices: plain, 9-patch, with a pivot, coloured, with user data.
do
    local spr = Sprite(32, 32, ColorMode.RGB)
    spr:newCel(spr.layers[1], 1, backdrop(32, 32), Point(0, 0))
    local s1 = spr:newSlice(Rectangle(2, 2, 10, 8)); s1.name = "hitbox"; s1.color = Color { r = 255, g = 0, b = 0 }
    local s2 = spr:newSlice(Rectangle(14, 2, 16, 16)); s2.name = "panel"; s2.center = Rectangle(4, 4, 8, 8); s2.data = "9-patch"
    local s3 = spr:newSlice(Rectangle(4, 20, 8, 10)); s3.name = "feet"; s3.pivot = Point(4, 10)
    s3.properties.solid = true
    save(spr, "slices")
end

-- 6. User data with every property type, on the sprite, a layer, a cel,
-- a tag and a slice; text and colour too.
do
    local spr = Sprite(4, 4, ColorMode.RGB)
    local layer = spr.layers[1]; layer.name = "Data"
    local img = Image(4, 4, ColorMode.RGB); fill(img, 0, 0, 4, 4, rgba(10, 20, 30))
    local cel = spr:newCel(layer, 1, img, Point(0, 0))
    spr.data = "sprite text"; spr.color = Color { r = 1, g = 2, b = 3, a = 4 }
    layer.data = "layer text"; layer.color = Color { r = 200, g = 100, b = 50 }
    cel.data = "cel text"
    local p = layer.properties
    p.flag = true
    p.count = 42
    p.neg = -7
    p.big = 5000000000
    p.ratio = 0.25
    p.name = "hero"
    p.where = Point(3, -4)
    p.size = Size(5, 6)
    p.box = Rectangle(1, 2, 3, 4)
    p.list = { 1, 2, 3 }
    p.mixed = { 1, "two", true }
    p.nested = { inner = { deep = "yes" }, n = 9 }
    cel.properties.hit = true
    spr.properties.version = 3
    local t = spr:newTag(1, 1); t.name = "only"; t.data = "tag text"
    t.properties.speed = 1.5
    local s = spr:newSlice(Rectangle(0, 0, 2, 2)); s.name = "spot"
    s.properties.kind = "spawn"
    save(spr, "user_data")
end

-- 7. Indexed colour: a palette with alpha, the transparent index, a
-- background layer (opaque, no transparent index there).
do
    local spr = Sprite(8, 8, ColorMode.INDEXED)
    local pal = Palette(6)
    pal:setColor(0, Color { r = 0, g = 0, b = 0, a = 0 })
    pal:setColor(1, Color { r = 255, g = 0, b = 0 })
    pal:setColor(2, Color { r = 0, g = 255, b = 0 })
    pal:setColor(3, Color { r = 0, g = 0, b = 255, a = 128 })
    pal:setColor(4, Color { r = 255, g = 255, b = 255 })
    pal:setColor(5, Color { r = 20, g = 20, b = 20 })
    spr:setPalette(pal)
    spr.transparentColor = 0
    local bg = spr.layers[1]; bg.name = "Bg"
    local bimg = Image(8, 8, ColorMode.INDEXED)
    for y = 0, 7 do for x = 0, 7 do bimg:drawPixel(x, y, (x + y) % 6) end end
    spr:newCel(bg, 1, bimg, Point(0, 0))
    app.activeLayer = bg
    app.command.BackgroundFromLayer()
    local top = spr:newLayer(); top.name = "Top"
    local timg = Image(6, 6, ColorMode.INDEXED)
    for y = 0, 5 do for x = 0, 5 do timg:drawPixel(x, y, (x * y) % 5) end end
    spr:newCel(top, 1, timg, Point(1, 1))
    save(spr, "indexed")
end

-- 8. Grayscale.
do
    local spr = Sprite(8, 8, ColorMode.GRAYSCALE)
    local img = Image(8, 8, ColorMode.GRAYSCALE)
    for y = 0, 7 do for x = 0, 7 do img:drawPixel(x, y, app.pixelColor.graya((x * 32) % 256, (y * 36 + 30) % 256)) end end
    spr:newCel(spr.layers[1], 1, img, Point(0, 0))
    local l2 = spr:newLayer(); l2.name = "Gray2"; l2.blendMode = BlendMode.SCREEN; l2.opacity = 170
    local i2 = Image(4, 4, ColorMode.GRAYSCALE); fill(i2, 0, 0, 4, 4, app.pixelColor.graya(200, 200))
    spr:newCel(l2, 1, i2, Point(2, 2))
    save(spr, "grayscale")
end

-- 9. A tilemap: a tileset of 4x4 tiles and a tilemap layer using them,
-- some flipped.
do
    local spr = Sprite(16, 16, ColorMode.RGB)
    app.activeSprite = spr
    app.command.NewLayer { tilemap = true, gridBounds = Rectangle(0, 0, 4, 4) }
    local tl = app.activeLayer; tl.name = "Tiles"
    local ts = tl.tileset
    ts.name = "Ground"
    for i = 1, 3 do
        local tile = spr:newTile(ts)
        local img = tile.image
        for y = 0, 3 do for x = 0, 3 do img:drawPixel(x, y, rgba(80 * i, 255 - x * 50, y * 60, 255)) end end
        tile.image = img
        tile.data = "tile " .. i
    end
    local tm = Image(4, 4, ColorMode.TILEMAP)
    for y = 0, 3 do for x = 0, 3 do
        local t = (x + y) % 4
        local flags = 0
        if x == 1 then flags = flags | app.pixelColor.TILE_XFLIP end
        if y == 2 then flags = flags | app.pixelColor.TILE_YFLIP end
        if x == 3 and y == 3 then flags = flags | app.pixelColor.TILE_DFLIP end
        tm:drawPixel(x, y, app.pixelColor.tile(t, flags))
    end end
    spr:newCel(tl, 1, tm, Point(0, 0))
    save(spr, "tilemap")
end
