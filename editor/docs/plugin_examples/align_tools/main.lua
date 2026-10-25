-- Align and distribute the selection (Tools > Align). Each command is one
-- undo step (Editor.edit).

local function two_or_more() return #Editor.selection() >= 2 end

-- Moves every selected node with fn(node, nodes) -> x, y, as one undo step.
local function move(label, fn)
    local nodes = Editor.selection()
    Editor.edit(label, function()
        for _, n in ipairs(nodes) do n.position = Vec2(fn(n, nodes)) end
    end)
end

local function min_of(nodes, axis)
    local v = math.huge
    for _, n in ipairs(nodes) do v = math.min(v, n.position[axis]) end
    return v
end

Editor.add_command{
    id = "left", label = "Align Left", menu = "Tools/Align", scope = "scene",
    shortcut = "Primary+Alt+Left", enabled = two_or_more,
    run = function()
        local x = min_of(Editor.selection(), "x")
        move("Align left", function(n) return x, n.position.y end)
    end,
}

Editor.add_command{
    id = "top", label = "Align Top", menu = "Tools/Align", scope = "scene",
    shortcut = "Primary+Alt+Up", enabled = two_or_more,
    run = function()
        local y = min_of(Editor.selection(), "y")
        move("Align top", function(n) return n.position.x, y end)
    end,
}

-- Even horizontal spacing between the leftmost and the rightmost node.
Editor.add_command{
    id = "distribute_h", label = "Distribute Horizontally", menu = "Tools/Align", scope = "scene",
    enabled = function() return #Editor.selection() >= 3 end,
    run = function()
        local nodes = Editor.selection()
        table.sort(nodes, function(a, b) return a.position.x < b.position.x end)
        local first, last = nodes[1].position.x, nodes[#nodes].position.x
        local step = (last - first) / (#nodes - 1)
        Editor.edit("Distribute horizontally", function()
            for i, n in ipairs(nodes) do n.position = Vec2(first + step * (i - 1), n.position.y) end
        end)
    end,
}
