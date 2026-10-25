-- Exercises add_inspector / add_overlay / add_importer (tests/drive/plugin_extend.drive).

Editor.add_inspector{
    id = "info", title = "Extend ZZ", type = "TextureNode",
    draw = function(ui, node)
        ui.text("Type: " .. node:get_type())
        if ui.button("Spin") then
            Editor.edit("Spin", function() node.rotation = node.rotation + 90 end)
        end
    end,
}

-- Only for Node: never shown for a TextureNode.
Editor.add_inspector{
    id = "plain", title = "Plain ZZ", type = "Node",
    draw = function(ui, node) ui.text("plain") end,
}

-- A handle on each selected node: dragging moves it.
Editor.add_overlay{
    id = "move", title = "Move ZZ",
    draw = function(g, view)
        for _, n in ipairs(Editor.selection()) do
            local p = n.position
            g.circle(p, 30, "#ffcc00")
            g.line(p, p + Vec2(30, 0), "#ffcc00", 2)
            g.text(p + Vec2(0, 34), n.name)
            local moved, to = g.handle(n.name, p)
            if moved then n.position = to end
        end
    end,
}

-- .zzdata: "key=value" lines -> data/<name>.json
Editor.add_importer{
    ext = ".zzdata",
    import = function(name, data)
        local fields = {}
        for k, v in data:gmatch("(%w+)=(%w+)") do fields[#fields + 1] = string.format("%q: %q", k, v) end
        if #fields == 0 then return nil, "no key=value lines" end
        local base = name:gsub("%.zzdata$", "")
        return {["data/" .. base .. ".json"] = "{" .. table.concat(fields, ", ") .. "}"}
    end,
}

Editor.add_command{
    id = "bad_g", label = "Bad G ZZ",
    run = function() __Ore_Overlay_G.line(Vec2(0, 0), Vec2(1, 1)) end,
}
