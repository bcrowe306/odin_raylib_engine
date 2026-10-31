#!/usr/bin/env bash
# Extra `odin build` / `odin test` flags this platform needs (printed; empty
# on macOS and Linux). Windows: raylib.lib is linked whole (/WHOLEARCHIVE) so
# its CloseWindow / ShowCursor are defined before the linker searches
# User32.lib - otherwise rl.CloseWindow can resolve to Win32's (User32.lib
# comes first on the link line through core:os) and the two collide.
# (raylib stays static: the mixer pulls frames from raylib's decoders, which
# raylib.dll doesn't export.)
# macOS in CI (release builds): the oldest macOS the app runs on, as its
# Info.plist says (LSMinimumSystemVersion, scripts/package_editor.sh) -
# without it Odin targets the build machine's macOS (0.6.0 needed 14).
# (Not locally: Homebrew's raylib is built for a newer macOS, and every
# link would warn.)
#   odin build editor $(scripts/odin_flags.sh) ...
MACOS_MIN=12.0
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*)
		echo "-extra-linker-flags:/WHOLEARCHIVE:$(cygpath -w "$(odin root)/vendor/raylib/windows/raylib.lib")" ;;
	Darwin)
		[ -n "${CI:-}" ] && echo "-minimum-os-version:$MACOS_MIN" ;;
esac
