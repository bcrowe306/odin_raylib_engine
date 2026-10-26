-- Part swapping from a script: the eyes close and the mouth says "O".
local Swap = {}

function Swap:ready()
    local eyes = self.node:get_node("Eyes")
    local mouth = self.node:get_node("Mouth")
    self.ok = eyes:vector_swap("closed") and mouth:vector_swap("E") and not mouth:vector_swap("nope")
    self.frames = #mouth:vector_frames()
end

return Swap
