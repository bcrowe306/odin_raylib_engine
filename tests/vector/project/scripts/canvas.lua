-- Lua drawing (the Vector module from on_draw): a sun with gradient rays,
-- a clock face with arcs and ticks, and a dashed rounded path.
local Canvas = {}

Canvas.properties = {
    hour = { type = "float", default = 10 },
}

function Canvas:on_draw()
    -- Sun: a radial gradient disc and 12 rays.
    Vector.save()
    Vector.translate(-220, 0)
    for i = 0, 11 do
        Vector.save()
        Vector.rotate(i * 30)
        Vector.begin_path()
        Vector.move_to(55, -10)
        Vector.line_to(95, 0)
        Vector.line_to(55, 10)
        Vector.close_path()
        Vector.fill_paint(Vector.linear_gradient(55, 0, 95, 0, { {0, "#ffb300"}, {1, "#ff5722"} }))
        Vector.fill()
        Vector.restore()
    end
    Vector.begin_path()
    Vector.circle(0, 0, 50)
    Vector.fill_paint(Vector.radial_gradient(-15, -15, 70, { {0, "#fff8e1"}, {0.5, "#ffca28"}, {1, "#f57c00"} }))
    Vector.fill()
    Vector.restore()

    -- Clock: face, ticks, hands, an arc for the hour so far.
    Vector.begin_path()
    Vector.circle(0, 0, 80)
    Vector.fill_color("#eceff1")
    Vector.fill()
    Vector.stroke_color("#37474f")
    Vector.stroke_width(6)
    Vector.stroke()
    for i = 0, 59 do
        Vector.save()
        Vector.rotate(i * 6)
        Vector.begin_path()
        Vector.move_to(0, -72)
        Vector.line_to(0, i % 5 == 0 and -60 or -66)
        Vector.stroke_width(i % 5 == 0 and 4 or 1.5)
        Vector.line_cap("round")
        Vector.stroke()
        Vector.restore()
    end
    Vector.begin_path()
    Vector.move_to(0, 0)
    Vector.arc(0, 0, 50, -90, -90 + self.hour * 30)
    Vector.close_path()
    Vector.fill_color(0.26, 0.65, 0.96, 0.35)
    Vector.fill()
    Vector.save()
    Vector.rotate(self.hour * 30)
    Vector.begin_path()
    Vector.move_to(0, 8)
    Vector.line_to(0, -45)
    Vector.stroke_width(7)
    Vector.stroke_color("#263238")
    Vector.stroke()
    Vector.restore()

    -- A porthole: diagonal stripes clipped to a circle (Vector.clip until restore).
    Vector.save()
    Vector.translate(0, 150)
    Vector.begin_path()
    Vector.circle(0, 0, 45)
    Vector.clip()
    for i = -6, 6 do
        Vector.begin_path()
        Vector.save()
        Vector.rotate(35)
        Vector.rect(i * 14 - 4, -80, 8, 160)
        Vector.restore()
        Vector.fill_color(i % 2 == 0 and "#26c6da" or "#00838f")
        Vector.fill()
    end
    Vector.restore()

    -- A dashed, rounded wave.
    Vector.save()
    Vector.translate(140, 0)
    Vector.begin_path()
    Vector.move_to(0, -60)
    Vector.cubic_to(80, -60, 0, 0, 80, 0)
    Vector.cubic_to(160, 0, 80, 60, 160, 60)
    Vector.stroke_color("#ab47bc")
    Vector.stroke_width(8)
    Vector.line_cap("round")
    Vector.line_join("round")
    Vector.dash({20, 14})
    Vector.stroke()
    Vector.restore()
end

return Canvas
