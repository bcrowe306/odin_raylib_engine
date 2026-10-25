-- A test panel (tests/drive/plugin_panels.drive): the ui widgets, docking,
-- show / hide, ui outside a panel.
local count, name, show, pick = 0, "Ada", true, 2

Editor.add_panel{
    id = "stats", title = "Stats ZZ", dock = "right",
    draw = function(ui)
        ui.text("Scene: " .. Editor.scene().name)
        ui.separator("Widgets")
        if ui.button("Count") then
            count = count + 1
            print("count=" .. count)
        end
        local changed
        changed, name = ui.input("Name", name)
        if changed then print("name=" .. name) end
        changed, show = ui.checkbox("Show", show)
        if changed then print("show=" .. tostring(show)) end
        changed, pick = ui.combo("Pick", pick, {"a", "b", "c"})
        if changed then print("pick=" .. pick) end
        if ui.tree_node("More") then
            ui.dim("inside a tree node")
            ui.tree_pop()
        end
    end,
}

Editor.add_command{id = "show", label = "Show Stats ZZ", run = function() Editor.show_panel("stats") end}
Editor.add_command{id = "hide", label = "Hide Stats ZZ", run = function() Editor.show_panel("stats", false) end}
Editor.add_command{id = "bad_ui", label = "Bad UI ZZ", run = function() ui.text("not in a panel") end}
