# Files

The **Files** tab is a file browser for the folders on your computer,
outside the project: asset packs, downloads, other projects. You preview
images, animations, sounds, fonts and text files without leaving the
editor, then load only the ones you want into the project. Previewing never
writes to the project.

## When to use it

- **Picking assets from a pack**: listen to a folder of sound effects or
  look through sprite sheets, then load the few you want.
- **Bringing in files without leaving the editor**: no need to switch to
  Finder or Explorer and drag.
- **Finding a file somewhere on disk**: search a folder and every folder
  below it by name.
- **Loading a whole folder**: load it with everything in it, keeping its
  layout.
- **Not** for files already in the project: use the [Assets](assets.md)
  panel. **Not** for searching inside scripts: use the
  [Search tab](tab-search.md).

## What's in it

### Opening it

- **View > File Browser** - **Cmd+Shift+B** (Ctrl+Shift+B).
- The **Files** tab in the bottom panel.

It opens at the last folder you were in (or your home folder the first
time). Give the bottom panel some height - or use the *Animation* workspace
- for a longer list.

The tab has three parts side by side: the sidebar, the file list and the
preview. Drag the edges between them to resize.

### The toolbar

| Control | What it does |
|---|---|
| **Back** | The folder you were in before - **Alt+Left**. |
| **Forward** | Forward again - **Alt+Right**. |
| **Up** | The folder above - **Alt+Up** or **Backspace**. |
| **Refresh** | Reads the folders again (after files changed outside the editor). |
| Path | The folder shown. Type a path and press **Enter** to go there. A file's path opens its folder with the file selected; `~` is your home folder. A path that doesn't exist is reported in the Console. |
| **Bookmark** (star) | Bookmarks this folder, or removes the bookmark. Lit when bookmarked. |
| **Autoplay** | A selected sound or animation plays straight away. |
| **Loop** | Sounds and animations play again from the start. Off: once. |
| Volume | The preview volume. |

Autoplay and Loop are on by default. All three are remembered and shared
with the Assets panel's preview.

### The sidebar

- **Bookmarks** - your bookmarked folders (shown once you have one). Click
  to go there; right-click > **Remove Bookmark**.
- **Recent** - folders you visited lately (up to 12).
- **Folders** - a folder tree under **Project** (when a project is open),
  **Home** and **Computer** (the root folder; each drive on Windows). Click
  a folder to open it; click its arrow (or double-click) to expand it.
  Right-click: **Bookmark** / **Remove Bookmark**, **Copy Path**.
- Folders are read when you open them, so big trees stay quick.

Bookmarks, recent folders and the last folder belong to the editor, not
the project: they are the same in every project.

### The file list

Above the list:

| Control | What it does |
|---|---|
| **Search** | Shows only names containing the text (any case). |
| **Sub-folders** | With text in Search, looks through every folder below this one too. It searches a few folders a frame, so the editor keeps running; the count shows *N found in M folders (searching…)*. |
| Type filter | **All files**, **Images** (with Aseprite and SVG), **Audio**, **Video**, **Fonts**, or **Game assets** (images, sounds, fonts, Aseprite, SVG, and files the project uses - scripts, scenes, levels, shaders...). Folders always show. |
| Funnel menu | **Sort by Name / Size / Modified / Type**, **Descending**, **Show Hidden Files** (names starting with `.`). |

The list has **Name**, **Size** and **Modified** columns, folders first.

| Action | What it does |
|---|---|
| Click | Selects a file and previews it. |
| Cmd+click (Ctrl+click) | Adds or removes a row from the selection. |
| Shift+click | Selects a range. |
| Double-click a folder | Opens it. |
| Double-click a sound | Plays it. |
| **Up / Down** | Selects the next / previous row (Shift extends the selection). With Autoplay on, it plays. |
| **Right** or **Enter** | Opens the selected folder. |
| **Left** or **Backspace** | Goes up one folder. |
| Drag rows | Onto the [Assets](assets.md) panel or the [Viewport](viewport.md): they are imported, as files dragged from the system file manager are. |

The arrow keys work while the browser has focus and you're not typing.

Right-click a row:

- **Load into Project** (*name* or *N items*) - loads the selection, using
  the bottom bar's settings.
- **Load into Folder** - loads the selection into the project folder you
  pick from the submenu, this time only.
- **Open** and **Bookmark** / **Remove Bookmark** (folders).
- **Show in Folder** (a search result in a sub-folder) - opens its folder.
- **Copy Path**.

### The preview

The selected file (the last one clicked), with its size, date and details:
image size, frames, length, sample rate and channels, glyph count.

| File | Preview |
|---|---|
| Images (PNG, JPG, BMP, TGA, GIF, QOI, PSD, HDR) | The image over a checkerboard. **Fit** or **1:1**; the mouse wheel zooms; drag to pan. Loaded in the background (*Loading…*). |
| Aseprite files, animated GIFs | Their frames play with their own frame times: **Play / Pause** and *frame N / M*. |
| SVGs | The drawing. |
| Sounds (WAV, OGG, MP3, FLAC, QOA, XM, MOD) | **Play / Pause**, **Stop**, and a seek bar with the time and the length. |
| Fonts (TTF, OTF, FNT) | A sample of text in the font. |
| Text (scripts, JSON, LDtk, shaders, CSV, INI, XML, Markdown...) | The text, in the code font; the first 64 KB. |
| Video | Details only: the engine has no video decoder yet. |
| Folders | A note that **Load** brings the folder and everything in it. |

A sound stops when the selection changes, or when you switch to another
tab.

### The load bar

At the bottom of the preview:

| Control | What it does |
|---|---|
| **To** | **Folder for its type (textures/, audio/…)** - each file goes where the importer puts its type - or one project folder you pick (then any file type is copied). |
| Name taken | When a *different* file already has the name: **import beside it** (`name_2.ext`), **replace it**, or **skip it**. The same file is never copied twice. |
| **Load into Project** | Imports the selected files and folders (*Load N Items into Project* for several). Greyed out with nothing selected, or no project open. |

Loading goes through the same importer as [Assets](assets.md) > **Import
Assets...**. Files the importer doesn't know (and videos) need a project
folder under **To**.

## Walkthrough

Load three sound effects from a downloaded pack:

1. Press **Cmd+Shift+B** (Ctrl+Shift+B). The Files tab opens.
2. In the path field, type `~/Downloads/sfx_pack` and press **Enter**.
3. Click the star to bookmark the folder for next time.
4. Set the type filter to **Audio**.
5. Click the first sound: with **Autoplay** on, it plays. Press **Down** to
   hear the next one, and the next.
6. Cmd+click (Ctrl+click) the three you want.
7. Leave **To** on **Folder for its type** (sounds go to `audio/`) and the
   name rule on **import beside it**.
8. Click **Load 3 Items into Project**. The files appear in the Assets
   panel, ready to drag onto an Audio node.

## Tips

- Paste a file's full path into the path field to jump straight to it,
  selected.
- Search with **Sub-folders** on, then right-click a result > **Show in
  Folder** to open the folder it's in.
- **Load into Folder** is the quick way to put one batch somewhere else
  without changing the **To** setting.
- Rows dragged onto the viewport are imported and placed where you drop
  them.
- Related: [Assets](assets.md), [Viewport](viewport.md),
  [Settings](settings.md),
  [Import settings](../../engine/docs/import_settings.md).
