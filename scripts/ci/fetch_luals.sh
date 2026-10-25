#!/usr/bin/env bash
# Puts LuaLS's prebuilt release for this platform into lua-language-server/
# (CI doesn't build the submodule: its release is the same version).
#   scripts/ci/fetch_luals.sh [version]
set -euo pipefail
cd "$(dirname "$0")/../.."
version="${1:-3.19.2}" # the lua-language-server submodule's version
case "$(uname -s)-$(uname -m)" in
	Darwin-arm64) asset="lua-language-server-$version-darwin-arm64.tar.gz" ;;
	Darwin-x86_64) asset="lua-language-server-$version-darwin-x64.tar.gz" ;;
	Linux-x86_64) asset="lua-language-server-$version-linux-x64.tar.gz" ;;
	Linux-aarch64) asset="lua-language-server-$version-linux-arm64.tar.gz" ;;
	MINGW*|MSYS*|CYGWIN*) asset="lua-language-server-$version-win32-x64.zip" ;;
	*) echo "No LuaLS release for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac
dst=lua-language-server
if [ -x "$dst/bin/lua-language-server" ] || [ -f "$dst/bin/lua-language-server.exe" ]; then
	echo "$dst is there"
	exit 0
fi
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$asset" "https://github.com/LuaLS/lua-language-server/releases/download/$version/$asset"
mkdir -p "$dst"
case "$asset" in
	*.zip) unzip -q "$tmp/$asset" -d "$dst" ;;
	*) tar -xzf "$tmp/$asset" -C "$dst" ;;
esac
echo "LuaLS $version in $dst"
