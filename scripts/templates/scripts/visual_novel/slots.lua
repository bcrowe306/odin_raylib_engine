-- The save / load panel: three slots (Slot1..Slot3 buttons) and Close. In
-- the story scene it saves and loads through vn.lua; on the title screen it
-- only loads (the story scene starts from the slot).

---@class SaveSlots : ScriptInstanceBase
local Slots = {}

local COUNT = 3

function Slots:ready()
    self.open = false
    self.node:set_property("enabled", false)
    for i = 1, COUNT do
        self.node:get_child("Slot" .. i):connect("clicked", function() self:pick(i) end)
    end
    self.node:get_child("Close"):connect("clicked", function() self:hide() end)
end

-- show("save") / show("load")
function Slots:show(mode)
    self.mode, self.open = mode, true
    self.node:set_property("title", mode == "save" and "Save to a slot" or "Load a slot")
    for i = 1, COUNT do
        local data = Save.get("slot" .. i, nil)
        local label = data and (data.preview or ""):gsub("%[.-%]", "") or "(empty)"
        if #label > 48 then label = label:sub(1, 45) .. "..." end
        self.node:get_child("Slot" .. i).text = i .. ".  " .. label
    end
    self.node:set_property("enabled", true)
end

function Slots:hide()
    self.open = false
    self.node:set_property("enabled", false)
end

function Slots:pick(i)
    local vn = Scene.find_node("VN")
    if self.mode == "save" then
        Save.set("slot" .. i, vn:get_script():snapshot())
        Save.flush()
        self:show("save") -- (shows the new label)
        return
    end
    if not Save.has("slot" .. i) then return end
    self:hide()
    if vn then
        vn:get_script():load(Save.get("slot" .. i))
    else
        Save.set("load_slot", "slot" .. i)
        Scene.change_scene("scenes/story.scene.json", { transition = "fade", duration = 0.4 })
    end
end

function Slots:update(dt)
    if self.open and Input.is_action_pressed("cancel") then self:hide() end
end

return Slots
