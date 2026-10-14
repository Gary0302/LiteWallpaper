# LiteWallpaper

**English** | [繁體中文](README.zh-TW.md) · [Website](https://gary0302.github.io/LiteWallpaper/)

A tiny native macOS live-wallpaper player (~200 lines of Swift, no dependencies).

It plays a looping, muted video behind your desktop icons and **pauses automatically whenever nobody can see it**:

- desktop fully covered by windows, or a full-screen app is active
- screen locked or asleep
- Low Power Mode
- running on battery (toggle in the menu)

One shared `AVPlayer` drives a desktop-level window per screen, so multiple displays don't multiply decode work.

## Install

One line in Terminal (Apple Silicon or Intel, macOS 13+):

```sh
curl -fsSL https://raw.githubusercontent.com/Gary0302/LiteWallpaper/main/install.sh | zsh
```

Or download **LiteWallpaper.dmg** from the [latest release](https://github.com/Gary0302/LiteWallpaper/releases/latest) and drag the app into Applications. The app isn't notarized, so on first launch macOS will block it: right-click the app → **Open** (on macOS 15+, go to System Settings → Privacy & Security → **Open Anyway**). The Terminal installer avoids this step.

## Build

Requires macOS 13+ and the Xcode command line tools.

```sh
./build.sh          # builds a universal app and installs it to ~/Applications/LiteWallpaper.app
./package.sh        # builds build/LiteWallpaper.dmg and build/LiteWallpaper.zip for a release
```

## Use

Click the monitor icon in the menu bar → **Choose Video… / 選擇影片…** to pick a video. Other options: pause/play, pause on battery, launch at login, and **Language / 語言** (English or 繁體中文; defaults to your system language).

For the lowest CPU/GPU cost, encode wallpapers as HEVC at your display's resolution and ≤30 fps, e.g.:

```sh
ffmpeg -i in.mp4 -an -vf "fps=30,scale=-2:1964" -c:v hevc_videotoolbox -b:v 6M -tag:v hvc1 out.mp4
```

## Icons

`tools/make-icons.swift` regenerates the app icon and template menu-bar icon from `Resources/glyph.png`.
