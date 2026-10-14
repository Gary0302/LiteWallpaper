# LiteWallpaper

[English](README.md) | **繁體中文** · [官方網站](https://gary0302.github.io/LiteWallpaper/)

輕巧的 macOS 原生動態桌布播放器（約 200 行 Swift，無任何依賴）。

它會在桌面圖示後方循環播放靜音影片，並在**沒人看得到的時候自動暫停**：

- 桌面被視窗完全遮住，或正在使用全螢幕 App
- 螢幕鎖定或休眠
- 低耗電模式
- 使用電池時（可在選單中開關）

所有螢幕共用同一個 `AVPlayer`，每個螢幕各一個桌面層級視窗，多接螢幕不會增加解碼負擔。

## 安裝

在「終端機」貼上這一行（支援 Apple Silicon 與 Intel，macOS 13 以上）：

```sh
curl -fsSL https://raw.githubusercontent.com/Gary0302/LiteWallpaper/main/install.sh | zsh
```

或從[最新版本](https://github.com/Gary0302/LiteWallpaper/releases/latest)下載 **LiteWallpaper.dmg**，把 App 拖進「應用程式」。這個 App 沒有經過 Apple 公證，第一次開啟時 macOS 會阻擋：對 App 按右鍵 →「**打開**」（macOS 15 以上請到「系統設定 → 隱私權與安全性」按「**強制打開**」）。用終端機安裝則不會遇到這個步驟。

## 編譯

需要 macOS 13 以上及 Xcode 命令列工具。

```sh
./build.sh          # 編譯通用版 App 並安裝到 ~/Applications/LiteWallpaper.app
./package.sh        # 產生發佈用的 build/LiteWallpaper.dmg 與 build/LiteWallpaper.zip
```

## 使用

點選單列的螢幕圖示 →「**選擇影片…**」挑選影片。其他選項：暫停/播放、用電池時暫停、開機時啟動，以及「**語言**」（English 或 繁體中文，預設跟隨系統語言）。

想要最低的 CPU/GPU 用量，請把影片轉成 HEVC、解析度與螢幕相同、30 fps 以下，例如：

```sh
ffmpeg -i in.mp4 -an -vf "fps=30,scale=-2:1964" -c:v hevc_videotoolbox -b:v 6M -tag:v hvc1 out.mp4
```

## 圖示

`tools/make-icons.swift` 會從 `Resources/glyph.png` 重新產生 App 圖示與選單列圖示。
