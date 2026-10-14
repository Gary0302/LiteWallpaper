#!/bin/zsh
# Builds release artifacts in build/: LiteWallpaper.dmg (drag-to-Applications) and LiteWallpaper.zip (used by install.sh).
set -e
cd "${0:A:h}"
./build.sh --no-install
STAGE=build/dmg
rm -rf "$STAGE" build/LiteWallpaper.dmg build/LiteWallpaper.zip
mkdir -p "$STAGE"
cp -R build/LiteWallpaper.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname LiteWallpaper -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/LiteWallpaper.dmg >/dev/null
rm -rf "$STAGE"
ditto -c -k --keepParent build/LiteWallpaper.app build/LiteWallpaper.zip
echo "built build/LiteWallpaper.dmg and build/LiteWallpaper.zip"
