-- Logs the editor's events (tests/drive/plugin_events.drive); the first
-- Play is refused by before_play.
local refused = false

Editor.on("project_opened", function(name) print("opened=" .. name) end)
Editor.on("selection_changed", function(nodes)
    print("selected=" .. #nodes .. (nodes[1] and (" first=" .. nodes[1].name) or ""))
end)
Editor.on("scene_saved", function(path) print("saved=" .. path) end)
Editor.on("asset_imported", function(path) print("imported=" .. path) end)
Editor.on("after_export", function(preset, dir) print("exported=" .. preset) end)
Editor.on("before_play", function(scene)
    print("before_play=" .. scene)
    if not refused then
        refused = true
        return false, "fix the level first"
    end
end)
