## Use it for

- **Barks and one-liners**: `Subtitles.show` puts a spoken line on the
  track, with an optional `speaker` - a guard shouting, a radio call.
- **Sound captions**: `Subtitles.show(text, {caption = true})` describes a
  sound for players who can't hear it (`"[alarm blaring]"`). It shows only
  when the player has captions on.
- **Timing your own lines**: `duration` sets how long a line stays;
  `Subtitles.hide` takes one down early (when its voice clip is cut off)
  and `Subtitles.clear` empties the track (a scene change, a skipped
  cutscene).
- **Pacing**: `Subtitles.count` tells you whether lines are still up, so a
  script can wait before the next bark.

## Example

A trigger zone that sounds an alarm the first time the player walks in: a
caption for the siren, then a guard's shout once the track is clear. The
script is on an [Area](../nodes/AreaNode.md).

```lua
---@class AlarmZone : ScriptInstanceBase
local AlarmZone = {}

function AlarmZone:ready()
    self.tripped = false
    self.shouted = false
end

---@param other Node?
function AlarmZone:on_body_entered(other)
    if self.tripped or not other or not other:has_tag("player") then return end
    self.tripped = true
    Audio.play_sound("audio/alarm.wav")
    Subtitles.show("[alarm blaring]", { caption = true, duration = 3 })
end

function AlarmZone:update(dt)
    -- The shout waits until the caption has gone.
    if self.tripped and not self.shouted and Subtitles.count() == 0 then
        self.shouted = true
        Subtitles.show("Intruder in the east wing!", { speaker = "Guard" })
    end
end

return AlarmZone
```

## Notes

- Spoken lines show only when the player's **subtitles** setting is on,
  captions only when **captions** is on (see the
  [Accessibility](Accessibility.md) module). When a kind is off, `show`
  returns 0 and nothing appears - your own timing still runs.
- Up to three lines show at once; a fourth pushes the oldest off. Size and
  backdrop follow the player's settings.
- Lines count down in real time, so they keep their pace while the game is
  paused.
- Without `duration`, a line stays for its reading time: 0.8 s plus 15
  characters a second, at least 1.5 s.
- For dialogue with voices, a [Dialogue](../nodes/DialogueNode.md) node in
  **Subtitles** mode times each line to its voice clip. A
  [Sound Effect](../nodes/SoundNode.md) or
  [Music Streamer](../nodes/MusicNode.md) with a **Caption** shows it each
  time it plays.
