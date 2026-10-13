# LiteWallpaper

A tiny native macOS live-wallpaper player (~200 lines of Swift, no dependencies).

It plays a looping, muted video behind your desktop icons and **pauses automatically whenever nobody can see it**:

- desktop fully covered by windows, or a full-screen app is active
- screen locked or asleep
- Low Power Mode
- running on battery (toggle in the menu)

One shared `AVPlayer` drives a desktop-level window per screen, so multiple displays don't multiply decode work.

## Build

Requires macOS 13+ and the Xcode command line tools.

```sh
./build.sh          # builds and installs to ~/Applications/LiteWallpaper.app
```

## Use

Click the monitor icon in the menu bar → **選擇影片…** to pick a video. Other options: pause/play, pause on battery, launch at login.

For the lowest CPU/GPU cost, encode wallpapers as HEVC at your display's resolution and ≤30 fps, e.g.:

```sh
ffmpeg -i in.mp4 -an -vf "fps=30,scale=-2:1964" -c:v hevc_videotoolbox -b:v 6M -tag:v hvc1 out.mp4
```

## Icons

`tools/make-icons.swift` regenerates the app icon and template menu-bar icon from `Resources/glyph.png`.
