-- After an export, zips the export folder next to it (<dir>.zip) with the
-- system's zip - "process" permission (plugin.json). Off by default: turn it
-- on with Tools > Zip Exports.

local enabled = false

Editor.add_command{
    id = "toggle", label = "Zip Exports", menu = "Tools",
    checked = function() return enabled end,
    run = function() enabled = not enabled end,
}

Editor.on("after_export", function(preset, dir)
    if not enabled then return end
    local zip = dir .. ".zip"
    Editor.run("zip", {"-r", "-q", zip, dir}, function(ok, output, code)
        if ok and code == 0 then
            Editor.notify(preset .. ": zipped to " .. zip)
        else
            Editor.warn("zip failed (" .. tostring(code) .. "): " .. output)
        end
    end)
end)
