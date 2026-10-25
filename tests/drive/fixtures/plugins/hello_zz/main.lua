-- A test plugin (tests/drive/plugins.drive): on_load / on_unload, the
-- sandbox, the scene being edited.
local util = require("util")

function on_load()
    print("hello from a plugin " .. Editor.plugin.version)
    print("sandbox io=" .. type(io) .. " exec=" .. type(os.execute) .. " clock=" .. type(os.clock))
    print("scene ship=" .. tostring(Scene.find_node("PlayerShip") ~= nil))
    print(util.greeting())
end

function on_unload()
    print("bye")
end
