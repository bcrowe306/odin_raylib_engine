## Use it for

- **An options menu**: `Accessibility.get` fills each control with the
  player's current value and `Accessibility.set` applies a change at once -
  the UI grows, the colour filter switches, shakes calm down.
- **Keeping the player's choices**: `Accessibility.save` writes them for
  the next run; they're loaded over your defaults when the game starts.
- **A "reset" button**: `Accessibility.reset` goes back to the project's
  defaults (**Project Settings > Accessibility**); call `save` to keep it.
- **Reading a setting in your own code**: check `"subtitles"`,
  `"screen_shake"` or `"colorblind"` before showing something that depends
  on them; `Accessibility.get_all` returns every setting in one table.

## Example

A small options panel: a [Checkbox](../nodes/UICheckboxNode.md) named
`CalmCamera` turns screen shake off, and a [Button](../nodes/UIButtonNode.md)
named `FilterButton` steps through the colour filters. The script is on the
UI Container that holds them, and saves the choices when the panel closes.

```lua
---@class QuickOptions : ScriptInstanceBase
local QuickOptions = {}

local FILTERS = { "none", "protanopia", "deuteranopia", "tritanopia" }

function QuickOptions:ready()
    local calm = self.node:get_node("CalmCamera") ---@type UICheckboxNode
    calm.checked = Accessibility.get("screen_shake") == 0
    calm:connect("value_changed", function(on)
        Accessibility.set("screen_shake", on and 0 or 1)
    end)

    self.filter = self.node:get_node("FilterButton") ---@type UIButtonNode
    self:show_filter()
    self.filter:connect("clicked", function()
        local current = Accessibility.get("colorblind")
        local next = FILTERS[1]
        for i, name in ipairs(FILTERS) do
            if name == current then next = FILTERS[i % #FILTERS + 1] end
        end
        Accessibility.set("colorblind", next)
        self:show_filter()
    end)
end

function QuickOptions:show_filter()
    self.filter.text = "Colour filter: " .. Accessibility.get("colorblind")
end

function QuickOptions:on_destroy()
    Accessibility.save()
end

return QuickOptions
```

## Notes

- Keys: `ui_scale` (0.5..3), `colorblind` (`"none"`, `"protanopia"`,
  `"deuteranopia"`, `"tritanopia"`), `colorblind_strength` (0..1),
  `colorblind_simulate`, `subtitles`, `captions`, `subtitle_scale`
  (0.5..3), `subtitle_background` (0..1) and `screen_shake` (0..2).
  Numbers outside a range are clamped.
- `set` returns false (with a warning) for an unknown key or filter name;
  `get` returns nil for an unknown key.
- Settings are saved to `accessibility.json` next to the save files (the
  [Save](Save.md) module's folder), only what differs from your defaults.
- The **Accessibility Menu** script template builds a full menu of these
  rows. The [accessibility guide](../../engine/docs/accessibility.md)
  covers the colour filter, UI scale and subtitles in depth.
