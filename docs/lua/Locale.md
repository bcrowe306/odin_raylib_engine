## Use it for

- **Translated text**: put the texts in CSV tables in the project's `locale/` folder (`key,en,fr,...`) and show them with `tr("menu.start")`, or mark a [Text](../nodes/TextNode.md) or dialogue box **Localized** so its text is a key.
- **A language option**: `Locale.languages()` lists the tables' languages, `Locale.set("fr")` switches, `Locale.get()` says which one is on.
- **Per-language details**: check `Locale.get()` to swap a flag image or a font that the tables can't hold.

## Example

A button in the options menu that cycles through the project's languages and remembers the choice in the save file. The script is on a [Button](../nodes/UIButtonNode.md).

```lua
---@class LanguageButton : ScriptInstanceBase
local LanguageButton = {}

function LanguageButton:ready()
    -- Restore the player's choice from an earlier run.
    local saved = Save.get("language", nil)
    if saved then Locale.set(saved) end
    self:refresh()
end

function LanguageButton:on_clicked()
    local langs = Locale.languages()
    if #langs == 0 then return end
    local current = Locale.get()
    local next_index = 1
    for i, lang in ipairs(langs) do
        if lang == current then next_index = i % #langs + 1 end
    end
    Locale.set(langs[next_index])
    Save.set("language", langs[next_index])
    self:refresh()
end

function LanguageButton:refresh()
    self.node.text = tr("options.language", { name = Locale.get() })
end

return LanguageButton
```

With a table row like `options.language,"Language: {name}","Langue : {name}"`.

## Notes

- **The language isn't saved for you.** The game starts in Project Settings > General > **Language** each run; store the player's choice (as above, with [Save](Save.md)) and set it at startup.
- **Localized nodes update by themselves** when the language changes. Text you set with `tr` is a one-time copy: set it again after `Locale.set`.
- **Missing texts fall back**: a key with no text in the current language shows another language's text, then the key itself. `Locale.set` accepts any name, even one the tables don't have.
- Tables are re-read when they change, so editing a CSV updates a running game.
