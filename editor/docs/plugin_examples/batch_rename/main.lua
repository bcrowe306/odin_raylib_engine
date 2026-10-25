-- Renames the selection from a pattern: "#" becomes 1, 2, 3... in selection
-- order, "{name}" the old name ("Enemy_#", "{name}_old").

Editor.add_command{
    id = "rename", label = "Batch Rename...", menu = "Edit", scope = "scene",
    enabled = function() return #Editor.selection() >= 1 end,
    run = function()
        local nodes = Editor.selection()
        Editor.prompt("Rename " .. #nodes .. " nodes (# = number, {name} = old name)", "{name}_#", function(pattern)
            if not pattern or pattern == "" then return end -- cancelled
            Editor.edit("Batch rename", function()
                for i, n in ipairs(nodes) do
                    local name = pattern:gsub("{name}", function() return n.name end)
                    n.name = name:gsub("#", tostring(i))
                end
            end)
            Editor.notify("Renamed " .. #nodes .. " nodes")
        end)
    end,
}
