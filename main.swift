// LiteWallpaper — a minimal live-wallpaper player.
// One shared AVPlayer drives a desktop-level window per screen, and playback
// pauses whenever nobody can see it: desktop fully covered, full-screen app,
// screen locked or asleep, Low Power Mode, or (optionally) running on battery.

import AVFoundation
import Cocoa
import IOKit.ps
import ServiceManagement

private let defaults = UserDefaults.standard

enum Language: String, CaseIterable {
    case zh, en

    var displayName: String { self == .zh ? "繁體中文" : "English" }

    static var current: Language {
        get {
            if let raw = defaults.string(forKey: "language"), let lang = Language(rawValue: raw) { return lang }
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
        }
        set { defaults.set(newValue.rawValue, forKey: "language") }
    }
}

/// Picks the string for the current menu language.
private func L(_ zh: String, _ en: String) -> String { Language.current == .zh ? zh : en }

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
    private let chooseItem = NSMenuItem(title: "", action: #selector(chooseVideo), keyEquivalent: "o")
    private let playPauseItem = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "p")
    private let batteryItem = NSMenuItem(title: "", action: #selector(toggleBattery), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "", action: #selector(toggleLogin), keyEquivalent: "")
    private let languageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

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
        if looper == nil { return L("尚未選擇影片", "no video selected") }
        if userPaused { return L("手動暫停", "paused manually") }
        if screenLocked || sessionInactive { return L("螢幕已鎖定", "screen locked") }
        if screensAsleep { return L("螢幕休眠", "display asleep") }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return L("低耗電模式", "Low Power Mode") }
        if pauseOnBattery && onBattery { return L("使用電池中", "on battery") }
        if !windows.contains(where: { $0.occlusionState.contains(.visible) }) { return L("桌面被遮住", "desktop covered") }
        return nil
    }

    private func update() {
        let reason = pauseReason()
        if reason == nil {
            if player.rate == 0 { player.play() }
        } else if player.rate != 0 {
            player.pause()
        }
        let state = reason.map { L("已暫停：\($0)", "Paused: \($0)") } ?? L("播放中", "Playing")
        if state != stateItem.title { NSLog("LiteWallpaper %@", state) }
        stateItem.title = state
        chooseItem.title = L("選擇影片…", "Choose Video…")
        playPauseItem.title = userPaused ? L("播放", "Play") : L("暫停", "Pause")
        batteryItem.title = L("用電池時暫停", "Pause on Battery")
        loginItem.title = L("開機時啟動", "Launch at Login")
        languageItem.title = L("語言", "Language")
        languageItem.submenu?.items.forEach { $0.state = $0.representedObject as? String == Language.current.rawValue ? .on : .off }
        quitItem.title = L("結束", "Quit")
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
        menu.addItem(chooseItem)
        menu.addItem(playPauseItem)
        menu.addItem(batteryItem)
        menu.addItem(loginItem)
        menu.addItem(languageItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }

        let languages = NSMenu()
        for lang in Language.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.rawValue
            item.target = self
            languages.addItem(item)
        }
        languageItem.submenu = languages
        statusItem.menu = menu
    }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = Language(rawValue: raw) else { return }
        Language.current = lang
        update()
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
