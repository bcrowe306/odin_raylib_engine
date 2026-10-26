# Installation

Rayzr is one download: the editor, with everything it needs to run and
export games inside it (the game runners for every platform, the Lua
language server, the templates). You don't need a compiler or any other
tools.

## Download

Get the latest version from the [download page](https://rayzr.app/download/)
(or [GitHub Releases](https://github.com/bcrowe306/rayzr/releases)):

| Platform | File |
|---|---|
| macOS (Apple silicon) | `rayzr-editor-<version>-macos.dmg` |
| Windows (x64) | `rayzr-editor-<version>-windows.zip` |
| Linux (x64) | `rayzr-editor-<version>-linux-x86_64.AppImage`, `-amd64.deb` or `.tar.gz` |

Each release lists the SHA-256 checksum of every file (`SHA256SUMS.txt`).

## macOS

1. Open the `.dmg` and drag **Rayzr Editor** to Applications.
2. The first time, right-click the app and choose **Open** (builds that
   aren't notarized yet show a warning otherwise), then **Open** again.

## Windows

1. Extract the `.zip` anywhere (for example `C:\Games\Rayzr`).
2. Run `rayzr-editor.exe`. If SmartScreen warns about an unknown publisher,
   choose **More info > Run anyway**.

## Linux

- **AppImage**: `chmod +x rayzr-editor-*.AppImage`, then run it.
- **Debian / Ubuntu**: `sudo apt install ./rayzr-editor-*-amd64.deb`, then
  start *Rayzr Editor* from your applications menu.
- **Any distribution**: extract the `.tar.gz` and run `rayzr-editor` inside.

## Updates

The editor checks for a newer version when it starts and shows it in the
status bar. Release builds offer releases; development builds also offer
newer development builds (one is published for every change merged into the
engine).

## Next

[Your first game](first-game.md) walks you from the Welcome window to a game
you changed yourself.
