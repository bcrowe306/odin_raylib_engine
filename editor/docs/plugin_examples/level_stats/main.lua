-- A panel with the open scene's node counts by type. Counting walks the whole
-- tree, so it's cached and redone only when the scene is saved or on Refresh
-- (a panel's draw runs every frame: keep it cheap).

local stats -- {total = n, types = {{type, count}, ...}}

local function count()
    local scene = Editor.scene()
    if not scene then stats = nil return end
    local byType, total = {}, 0
    local function walk(node)
        total = total + 1
        local t = node:get_type()
        byType[t] = (byType[t] or 0) + 1
        for _, child in ipairs(node:get_children()) do walk(child) end
    end
    walk(scene.root)
    local types = {}
    for t, n in pairs(byType) do types[#types + 1] = {t, n} end
    table.sort(types, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    stats = {total = total, types = types}
end

Editor.add_panel{
    id = "stats", title = "Level Stats", dock = "right",
    draw = function(ui)
        if not stats then count() end
        if not stats then ui.dim("No scene open") return end
        ui.text("Nodes: " .. stats.total)
        ui.same_line()
        if ui.button("Refresh") then count() end
        ui.separator()
        if ui.begin_table("types", 2) then
            for _, row in ipairs(stats.types) do
                ui.next_cell() ui.text(row[1])
                ui.next_cell() ui.text(tostring(row[2]))
            end
            ui.end_table()
        end
    end,
}

Editor.on("scene_saved", count)
Editor.on("project_opened", function() stats = nil end)
