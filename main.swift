// LiteWallpaper — a minimal live-wallpaper player.
// One shared AVPlayer drives a desktop-level window per screen, and playback
// pauses whenever nobody can see it: desktop fully covered, full-screen app,
// screen locked or asleep, Low Power Mode, or (optionally) running on battery.

import AVFoundation
import Cocoa
import IOKit.ps
import ServiceManagement

private let defaults = UserDefaults.standard

final class DesktopWindow: NSWindow {
    init(screen: NSScreen, player: AVPlayer) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.videoGravity = .resizeAspectFill
        view.layer?.addSublayer(layer)
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var windows: [DesktopWindow] = []

    private var statusItem: NSStatusItem!
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let playPauseItem = NSMenuItem(title: "暫停", action: #selector(togglePause), keyEquivalent: "p")
    private let batteryItem = NSMenuItem(title: "用電池時暫停", action: #selector(toggleBattery), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "開機時啟動", action: #selector(toggleLogin), keyEquivalent: "")

    private var userPaused = false
    private var screensAsleep = false
    private var screenLocked = false
    private var sessionInactive = false
    private var onBattery = false

    private var pauseOnBattery: Bool {
        get { defaults.object(forKey: "pauseOnBattery") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "pauseOnBattery") }
    }

    private var videoPath: String? {
        get { defaults.string(forKey: "videoPath") }
        set { defaults.set(newValue, forKey: "videoPath") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        buildMenu()
        rebuildWindows()
        observeSystem()
        refreshPowerSource()

        // Power-source changes are rare; a lazy poll is cheaper than an IOKit callback bridge.
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshPowerSource()
        }
        timer.tolerance = 10

        if let path = videoPath, FileManager.default.fileExists(atPath: path) {
            load(URL(fileURLWithPath: path))
        } else {
            chooseVideo()
        }
    }

    // MARK: Playback

    private func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: item)
        videoPath = url.path
        update()
    }

    private func pauseReason() -> String? {
        if looper == nil { return "尚未選擇影片" }
        if userPaused { return "手動暫停" }
        if screenLocked || sessionInactive { return "螢幕已鎖定" }
        if screensAsleep { return "螢幕休眠" }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return "低耗電模式" }
        if pauseOnBattery && onBattery { return "使用電池中" }
        if !windows.contains(where: { $0.occlusionState.contains(.visible) }) { return "桌面被遮住" }
        return nil
    }

    private func update() {
        let reason = pauseReason()
        if reason == nil {
            if player.rate == 0 { player.play() }
        } else if player.rate != 0 {
            player.pause()
        }
        let state = reason.map { "已暫停：\($0)" } ?? "播放中"
        if state != stateItem.title { NSLog("LiteWallpaper %@", state) }
        stateItem.title = state
        playPauseItem.title = userPaused ? "播放" : "暫停"
        batteryItem.state = pauseOnBattery ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func refreshPowerSource() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let battery = type == "Battery Power"
        if battery != onBattery {
            onBattery = battery
            update()
        }
    }

    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { DesktopWindow(screen: $0, player: player) }
        windows.forEach { $0.orderFrontRegardless() }
        update()
    }

    // MARK: System events

    private func observeSystem() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildWindows()
        }
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let flags: [(Notification.Name, (AppDelegate) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, { $0.screensAsleep = true }),
            (NSWorkspace.screensDidWakeNotification, { $0.screensAsleep = false }),
            (NSWorkspace.sessionDidResignActiveNotification, { $0.sessionInactive = true }),
            (NSWorkspace.sessionDidBecomeActiveNotification, { $0.sessionInactive = false }),
        ]
        for (name, apply) in flags {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                apply(self)
                self.update()
            }
        }

        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.screenLocked = locked
                self?.update()
            }
        }
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // A stable autosave name lets menu bar managers like Bartender remember this item.
        statusItem.autosaveName = "LiteWallpaper"
        let icon = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "display", accessibilityDescription: "LiteWallpaper")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "LiteWallpaper"

        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "選擇影片…", action: #selector(chooseVideo), keyEquivalent: "o"))
        menu.addItem(playPauseItem)
        menu.addItem(batteryItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        statusItem.menu = menu
    }

    @objc private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Wallpapers")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    @objc private func togglePause() {
        userPaused.toggle()
        update()
    }

    @objc private func toggleBattery() {
        pauseOnBattery.toggle()
        update()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        update()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
