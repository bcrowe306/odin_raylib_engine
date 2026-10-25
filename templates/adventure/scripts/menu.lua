-- A keyboard / gamepad menu made of text: the children named Item1, Item2...
-- are the choices (up / down picks, confirm or jump chooses). Kind "title"
-- is the title screen, "pause" the pause menu (Esc / P / Start opens and
-- closes it; it keeps running while the game is paused: pause_mode always).

---@class Menu : ScriptInstanceBase
local Menu = {}

Menu.properties = {
    kind = { type = "enum", values = { "title", "pause" }, default = "title", label = "Kind" },
}

local SELECTED = "#c0392bff"

function Menu:ready()
    self.items = {}
    for i = 1, 9 do
        local item = self.node:get_child("Item" .. i)
        if not item then break end
        self.items[i] = { node = item, label = item.text, color = item:get_property("color") }
    end
    self.index = 1
    if self.kind == "title" then
        local continue = Save.get("level", nil)
        if not continue then self.items[2].label = "Continue (no save yet)" end
        self.items[2].disabled = continue == nil
        local hint = self.node:get_child("Hint")
        if hint and Save.get("finished", false) then hint.text = "You finished it! Play again?" end
        self.open = true
    else
        self:show(false)
    end
    self:refresh()
end

function Menu:show(open)
    self.open = open
    self.node:set_visible(open)
    for _, c in ipairs(self.node:get_children()) do c:set_visible(open) end
    if self.kind == "pause" then Engine.set_paused(open) end
    self.index = 1
    self:refresh()
end

function Menu:refresh()
    for i, it in ipairs(self.items) do
        local on = i == self.index
        it.node.text = (on and "> " or "") .. it.label .. (on and " <" or "")
        it.node:set_property("color", on and SELECTED or it.color)
    end
end

function Menu:choose(i)
    local name = self.items[i].label
    if self.kind == "title" then
        if i == 1 then
            Save.set("level", "scenes/level1.scene.json")
            Save.set("finished", false)
            Scene.change_scene("scenes/level1.scene.json", { transition = "fade", duration = 0.4 })
        elseif not self.items[2].disabled then
            Scene.change_scene(Save.get("level", "scenes/level1.scene.json"), { transition = "fade", duration = 0.4 })
        end
    else
        self:show(false)
        if name == "Restart level" then Scene.reload()
        elseif name == "Title screen" then Scene.change_scene("scenes/title.scene.json", { transition = "fade", duration = 0.3 }) end
    end
end

function Menu:update(dt)
    if self.kind == "pause" and Input.is_action_pressed("pause") then
        self:show(not self.open)
        return
    end
    if not self.open then return end
    local n = #self.items
    if Input.is_action_pressed("move_down") then self.index = self.index % n + 1; self:refresh() end
    if Input.is_action_pressed("move_up") then self.index = (self.index - 2) % n + 1; self:refresh() end
    if Input.is_action_pressed("confirm") or Input.is_action_pressed("jump") then self:choose(self.index) end
end

return Menu
