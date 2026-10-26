Moves a vector mouth with a voice, from the mouth cues
[Rhubarb Lip Sync](https://github.com/DanielSWolf/rhubarb-lip-sync) writes
for a recording (TSV, or JSON with `-f json`) - saved beside the sound with
the same name (`hello.wav` -> `hello.tsv`), or named in **cues**.

**mouth** is the path to a [Vector Shape](VectorShapeNode.md) whose symbol's
child groups are the mouth shapes, named after Rhubarb's (`A`-`H`, `X`) or
renamed with **mapping** (`A=MBP,B=etc,C=E,D=AI,E=O,F=U,X=rest`). Play its
own **sound** (with **autoplay**, or from a script), or point a Dialogue
node's **lipSync** at it so every voiced line moves the mouth. At the end
the mouth rests and `finished` fires. See the
[vector art guide](../../engine/docs/vector.md#lip-sync).

```lua
local lips = self.node:get_node("LipSync")
lips:lipsync_play("voice/hello.wav")
lips:connect("finished", function() Log.info("done talking") end)
```
