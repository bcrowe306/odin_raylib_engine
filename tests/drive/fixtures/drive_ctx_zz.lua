local DriveCtxZz = {}
function DriveCtxZz:ready()
    local ship = Scene.find_node("PlayerShip")
    local tex = "textures/Spaceship_1.png"
    Audio.play_sound("sounds/none.wav")
end
return DriveCtxZz
