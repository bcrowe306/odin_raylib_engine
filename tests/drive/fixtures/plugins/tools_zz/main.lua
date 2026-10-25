-- Exercises the Editor API (tests/drive/plugin_api.drive): commands in the
-- menus, selection, one-undo-step edits, nodes, files, dialogs, permissions.

Editor.add_command{
    id = "select_two", label = "Select Two ZZ",
    run = function()
        Editor.select({Scene.find_node("PlayerShip"), Scene.find_node("Asteroid_Alpha")})
    end,
}

Editor.add_command{
    id = "align_left", label = "Align Left ZZ", menu = "Tools/Align ZZ", scope = "scene",
    enabled = function() return #Editor.selection() >= 2 end,
    run = function()
        local nodes = Editor.selection()
        local x = math.huge
        for _, n in ipairs(nodes) do x = math.min(x, n.position.x) end
        Editor.edit("Align left", function()
            for _, n in ipairs(nodes) do n.position = Vec2(x, n.position.y) end
        end)
    end,
}

Editor.add_command{
    id = "report", label = "Report ZZ",
    run = function()
        local nodes = Editor.selection()
        local same = #nodes >= 2
        for _, n in ipairs(nodes) do same = same and n.position.x == nodes[1].position.x end
        print("selected=" .. #nodes .. " same=" .. tostring(same))
    end,
}

Editor.add_command{
    id = "add_marker", label = "Add Marker ZZ", menu = "Tools",
    run = function()
        Editor.edit("Add marker", function()
            local m = Editor.create_node("Node", nil, "MarkerZZ")
            m.position = Vec2(10, 20)
            Editor.select(m)
        end)
    end,
}

Editor.add_command{
    id = "files", label = "Files ZZ",
    run = function()
        local scenes = Editor.assets("scenes", ".scene.json")
        print("scenes>0=" .. tostring(#scenes > 0) .. " first=" .. tostring(scenes[1]))
        Editor.fs.write("plugin_out_zz.txt", "written by a plugin")
        print("read=" .. Editor.fs.read("plugin_out_zz.txt"))
        print("escape=" .. tostring((pcall(Editor.fs.read, "/etc/hosts"))))
        print("run=" .. tostring((pcall(Editor.run, "ls", {}, function() end))))
        print("project=" .. Editor.project().name .. " scene=" .. Editor.scene().name)
    end,
}

Editor.add_command{
    id = "ask", label = "Ask ZZ",
    run = function()
        Editor.prompt("Your name?", "Bob", function(v) print("prompt=" .. tostring(v)) end)
    end,
}

Editor.add_command{
    id = "boom", label = "Boom ZZ",
    run = function() error("command boom") end,
}
