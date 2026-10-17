import AppKit
import GaxoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let identity = DeviceIdentity.loadOrCreate()
    let session = SessionController()
    let statusModel = StatusViewModel()

    private var accepting = true
    private var currentClient: ClientInfo?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.enableFile()
        Log.info("Gaxo starting, device ID \(identity.deviceID)")
        // An unbundled executable starts with no UI rights; claim them before making any.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build(app: self)
        NSApp.applicationIconImage = GaxoArt.appIcon(size: 512)
        statusItem = StatusItemController(app: self)

        let settings = settingsStore.settings
        statusModel.name = settings.name
        statusItem.update(state: .stopped, name: settings.name, accepting: accepting)
        media.playSound = settings.playSound
        mirror.setFloating(settings.keepOnTop)
        session.media = media
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
            currentClient = client
            mirror.present(clientName: client.name)
            // The status window steps aside while mirroring (it comes back afterwards).
            if statusWindowPolicy.sessionStarted(windowVisible: statusWindow.window?.isVisible == true) {
                statusWindow.window?.orderOut(nil)
            }
        case .awaitingCode:
            showStatusWindow()
            // The person is looking at the Mac to read the code: put it in front of everything.
            statusWindow.window?.orderFrontRegardless()
            DispatchQueue.main.async { [self] in
                Log.info("Status window showing code: \(statusWindow.sizeReport)")
            }
        case .ready, .stopped, .failed:
            if currentClient != nil {
                currentClient = nil
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
        }
    }

    private func userClosedMirror() {
        if case .mirroring = session.state {
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
        if old.playSound != new.playSound { media.playSound = new.playSound }
        if SettingsStore.requiresEngineRestart(old, new) {
            Log.info("Settings changed; restarting the receiver as \"\(new.name)\"")
            session.restart(config: settingsStore.engineConfig(identity: identity))
        }
        statusItem.update(state: session.state, name: new.name, accepting: accepting)
    }

    @objc func showMirrorWindow() {
        guard mirror.window?.isVisible == true || currentClient != nil else { return }
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
