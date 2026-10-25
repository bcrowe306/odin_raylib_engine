# Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`) when a
version tag is pushed:

```sh
git tag v0.1.0          # or v0.2.0-beta.1 (a pre-release)
git push origin v0.1.0
```

The workflow builds:

1. the game runners on macOS, Linux and Windows, and the web runner;
2. the editor on each platform, with **every** platform's runners inside (any
   editor exports macOS, Windows, Linux and web games);
3. a GitHub Release with the packages and `SHA256SUMS.txt`:

| Platform | Files |
|---|---|
| macOS (Apple silicon) | `ore-editor-<version>-macos.dmg` |
| Windows (x64) | `ore-editor-<version>-windows.zip` |
| Linux (x64) | `ore-editor-<version>-linux-x86_64.AppImage`, `-amd64.deb`, `.tar.gz` |

The version (the tag without `v`) is built into the editor and the runners
(`ORE_RELEASE`: the editor's title and `--version`, `project.json`'s
`engine_version`, the update check). A dry run without publishing: Actions >
Release > Run workflow (a version, no tag).

Every push and pull request runs CI (`.github/workflows/ci.yml`): the editor,
runner and Play binary build, and the unit tests run, on all three platforms;
on Linux the runner plays the demo project and the packaged editor is
smoke-tested (`scripts/test_package.sh`). The editor's UI drives
(`scripts/editor_drive.sh`) stay local: they need a GPU.

## Signing (optional)

Without these secrets the packages are unsigned (macOS: ad-hoc signed - users
right-click > Open the first time; Windows: SmartScreen warns).

**macOS** - Developer ID + notarization (`scripts/ci/sign_macos.sh`), needs an
Apple Developer account. Repository secrets:

- `MACOS_CERTIFICATE` - the *Developer ID Application* certificate exported
  as `.p12`, base64 (`base64 -i cert.p12 | pbcopy`)
- `MACOS_CERTIFICATE_PASSWORD` - its password
- `MACOS_SIGNING_IDENTITY` - e.g. `Developer ID Application: Your Name (TEAMID)`
- `MACOS_NOTARY_APPLE_ID`, `MACOS_NOTARY_TEAM_ID`, `MACOS_NOTARY_PASSWORD`
  (an app-specific password from appleid.apple.com)

**Windows** - a code-signing certificate (`scripts/ci/sign_windows.sh`):

- `WINDOWS_CERTIFICATE` - the `.pfx`, base64
- `WINDOWS_CERTIFICATE_PASSWORD`

## Building packages locally

```sh
task editor:package VERSION=0.1.0   # dist/: the .app (macOS) or a folder
task editor:package:test            # runs it from outside the checkout
```

The static libraries the editor links are built by `scripts/build_imgui.sh`,
`scripts/build_lua.sh` and `scripts/build_cmark.sh` (the macOS ones are in the
repo; CI builds the others: `scripts/ci/setup_deps.sh`).
