#!/bin/zsh
# Builds LiteWallpaper.app and installs it to ~/Applications.
set -e
cd "${0:A:h}"
APP=build/LiteWallpaper.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos13 main.swift -o "$APP/Contents/MacOS/LiteWallpaper"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
mkdir -p ~/Applications && rm -rf ~/Applications/LiteWallpaper.app && cp -R "$APP" ~/Applications/
echo "installed ~/Applications/LiteWallpaper.app"
