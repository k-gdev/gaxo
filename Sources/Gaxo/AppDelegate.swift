import AppKit
import GaxoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let identity = DeviceIdentity.loadOrCreate()
    let session = SessionController()
    let statusModel = StatusViewModel()

    private var accepting = true
    private var showingPhone = false
    private var pendingSessionEnd: DispatchWorkItem?
    private var statusWindowPolicy = StatusWindowPolicy()
    private var statusItem: StatusItemController!
    private lazy var statusWindow = StatusWindowController(model: statusModel) { [weak self] in
        self?.showSettings()
    }
    private lazy var mirror: MirrorWindowController = {
        let mirror = MirrorWindowController()
        mirror.onUserClose = { [weak self] in self?.userClosedMirror() }
        mirror.onShow = { [weak self] in self?.updateActivationPolicy() }
        return mirror
    }()
    private let audioPlayer = AudioPlayer()
    private lazy var settingsModel = SettingsViewModel(settings: settingsStore.settings)
    private lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController(model: settingsModel) { [weak self] settings in
            self?.applySettings(settings)
        }
        controller.onClose = { [weak self] in
            guard let self, let settings = settingsModel.settingsWithDraftName() else { return }
            applySettings(settings)
        }
        return controller
    }()
    private lazy var media = MediaRouter(mirror: mirror, audioPlayer: audioPlayer)
    private lazy var videoPlayer = VideoPlayerController(mirror: mirror)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.enableFile()
        Log.info("Gaxo starting, device ID \(identity.deviceID)")
        // An unbundled executable starts with no UI rights; claim them before making any.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build(app: self)
        NSApp.applicationIconImage = GaxoArt.appIcon(size: 512)
        statusItem = StatusItemController(app: self)

        // "Ask for a code" saved before fixed codes existed gets its code now.
        let settings = settingsStore.settings.ensuringPairingCode()
        settingsStore.settings = settings
        statusModel.name = settings.name
        statusItem.update(state: .stopped, name: settings.name, accepting: accepting)
        media.playSound = settings.playSound
        videoPlayer.muted = !settings.playSound
        mirror.setFloating(settings.keepOnTop)
        session.media = media
        session.videoPlayer = videoPlayer
        session.onStateChange = { [weak self] state in self?.sessionStateChanged(state) }
        session.start(config: settingsStore.engineConfig(identity: identity))

        // The Dock icon follows Gaxo's windows: shown while one is open.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
            [weak self] _ in
            DispatchQueue.main.async { self?.updateActivationPolicy() }
        }
        if settings.showStatusWindowAtLaunch {
            showStatusWindow()
        } else {
            updateActivationPolicy()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
        SessionController.controlQueue.sync {} // let the engine unregister from Bonjour before exit
        Log.info("Gaxo quit")
    }

    // MARK: - Session

    private func sessionStateChanged(_ state: SessionState) {
        Log.info("State: \(state)")
        statusModel.state = state
        statusItem.update(state: state, name: settingsStore.settings.name, accepting: accepting)

        switch state {
        case let .mirroring(client):
            mirror.present(clientName: client.name)
        case .awaitingCode:
            showStatusWindow()
            // The person is looking at the Mac to read the code: put it in front of everything.
            statusWindow.window?.orderFrontRegardless()
            DispatchQueue.main.async { [self] in
                Log.info("Status window showing code: \(statusWindow.sizeReport)")
            }
        case .playingVideo, .ready, .stopped, .failed:
            break
        }

        if state.isShowingPhone {
            pendingSessionEnd?.cancel()
            pendingSessionEnd = nil
            if !showingPhone {
                // Mirroring or an AirPlay video began: the status window steps aside.
                showingPhone = true
                if statusWindowPolicy.sessionStarted(windowVisible: statusWindow.window?.isVisible == true) {
                    statusWindow.window?.orderOut(nil)
                }
            }
        } else if showingPhone, state.endsShowingPhone, pendingSessionEnd == nil {
            // A YouTube video starts right after the mirror stream stops: wait a moment,
            // so the window does not flicker shut and reopen.
            let work = DispatchWorkItem { [weak self] in self?.endShowingPhone() }
            pendingSessionEnd = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    private func endShowingPhone() {
        pendingSessionEnd = nil
        guard showingPhone, session.state.endsShowingPhone else { return }
        showingPhone = false
        media.sessionEnded()
        if settingsStore.settings.closeWindowWhenMirroringStops {
            mirror.closeForSessionEnd()
        } else {
            mirror.resetVideo()
        }
        if statusWindowPolicy.sessionEnded() {
            statusWindow.showWindow(nil) // without activating Gaxo: no focus stealing
            updateActivationPolicy()
        }
    }

    private func userClosedMirror() {
        if session.state.isShowingPhone {
            Log.info("Mirror window closed; disconnecting the iPhone")
            session.disconnect()
        }
    }

    // MARK: - Actions (menu bar dropdown, app menus, status window)

    @objc func showStatusWindow() {
        statusWindow.showWindow(nil)
        updateActivationPolicy()
        NSApp.activate()
    }

    @objc func showSettings() {
        if LoginItem.isAvailable, settingsStore.settings.openAtLogin != LoginItem.isEnabled {
            // The user may have changed it in System Settings → General → Login Items.
            var settings = settingsStore.settings
            settings.openAtLogin = LoginItem.isEnabled
            settingsStore.settings = settings
        }
        settingsModel.settings = settingsStore.settings
        settingsModel.draftName = settingsStore.settings.name
        settingsWindow.showWindow(nil)
        updateActivationPolicy()
        NSApp.activate()
    }

    private func applySettings(_ requested: Settings) {
        let old = settingsStore.settings
        var new = requested
        new.name = Settings.cleanName(new.name)
        new = new.ensuringPairingCode()

        if old.openAtLogin != new.openAtLogin {
            do {
                try LoginItem.set(new.openAtLogin)
            } catch {
                Log.error("Could not change Open at login: \(error)")
                new.openAtLogin = old.openAtLogin
                NSSound.beep()
            }
        }
        settingsStore.settings = new
        settingsModel.settings = new
        statusModel.name = new.name
        if old.keepOnTop != new.keepOnTop { mirror.setFloating(new.keepOnTop) }
        if old.playSound != new.playSound {
            media.playSound = new.playSound
            videoPlayer.muted = !new.playSound
        }
        if SettingsStore.requiresEngineRestart(old, new) {
            Log.info("Settings changed; restarting the receiver as \"\(new.name)\"")
            session.restart(config: settingsStore.engineConfig(identity: identity))
        }
        statusItem.update(state: session.state, name: new.name, accepting: accepting)
    }

    @objc func showMirrorWindow() {
        guard mirror.window?.isVisible == true || showingPhone else { return }
        mirror.showWindow(nil)
        updateActivationPolicy()
        NSApp.activate()
    }

    @objc func disconnect() {
        session.disconnect()
    }

    @objc func toggleAccepting() {
        accepting.toggle()
        statusModel.accepting = accepting
        session.setAcceptingConnections(accepting)
        statusItem.update(state: session.state, name: settingsStore.settings.name, accepting: accepting)
    }

    // MARK: - Dock icon

    private func updateActivationPolicy() {
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
    }
}

private extension SessionState {
    /// Back to Ready, stopped or failed (a code prompt does not end what is on screen).
    var endsShowingPhone: Bool {
        switch self {
        case .ready, .stopped, .failed: true
        case .mirroring, .playingVideo, .awaitingCode: false
        }
    }
}
