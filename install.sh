#!/bin/zsh
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/Gary0302/LiteWallpaper/main/install.sh | zsh
set -e
URL=https://github.com/Gary0302/LiteWallpaper/releases/latest/download/LiteWallpaper.zip
DEST=/Applications
[[ -w $DEST ]] || DEST=~/Applications
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading LiteWallpaper…"
curl -fsSL "$URL" -o "$TMP/LiteWallpaper.zip"
ditto -x -k "$TMP/LiteWallpaper.zip" "$TMP"
pkill -x LiteWallpaper 2>/dev/null || true
mkdir -p "$DEST" && rm -rf "$DEST/LiteWallpaper.app"
ditto "$TMP/LiteWallpaper.app" "$DEST/LiteWallpaper.app"
xattr -dr com.apple.quarantine "$DEST/LiteWallpaper.app" 2>/dev/null || true
echo "Installed $DEST/LiteWallpaper.app"
open "$DEST/LiteWallpaper.app"
