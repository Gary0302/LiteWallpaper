#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) LiteWallpaper.app and installs it to ~/Applications.
# Pass --no-install to only build into build/.
set -e
cd "${0:A:h}"
APP=build/LiteWallpaper.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13 main.swift -o build/LiteWallpaper-$arch
done
lipo -create build/LiteWallpaper-arm64 build/LiteWallpaper-x86_64 -output "$APP/Contents/MacOS/LiteWallpaper"
rm build/LiteWallpaper-arm64 build/LiteWallpaper-x86_64
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
[[ "$1" == --no-install ]] && { echo "built $APP"; exit 0; }
mkdir -p ~/Applications && rm -rf ~/Applications/LiteWallpaper.app && cp -R "$APP" ~/Applications/
echo "installed ~/Applications/LiteWallpaper.app"
