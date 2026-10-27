-- Test helper (not part of the tutorials): shows a state machine's history
-- as "idle>fall>idle>jump" in this Text node, so the runner tests
-- (tests/state_machine/runtime_tests.json) can check it in the scene dump.

---@class SmProbe : ScriptInstanceBase
local Probe = {}

Probe.properties = {
    machine = { type = "string", default = "StateMachine", label = "Machine" },
}

function Probe:update(dt)
    local m = Scene.find_node(self.machine)
    if m == nil then return end
    local states = {}
    for _, c in ipairs(m:sm_history()) do states[#states + 1] = c.to end
    self.node.text = table.concat(states, ">")
end

return Probe
