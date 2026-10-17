import AppKit
import GaxoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let identity = DeviceIdentity.loadOrCreate()
    let session = SessionController()
    let statusModel = StatusViewModel()

    private var accepting = true
    private var statusItem: StatusItemController!
    private lazy var statusWindow = StatusWindowController(model: statusModel) { [weak self] in
        self?.showSettings()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Gaxo starting, device ID \(identity.deviceID)")
        // An unbundled executable starts with no UI rights; claim them before making any.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build(app: self)
        NSApp.applicationIconImage = GaxoArt.appIcon(size: 512)
        statusItem = StatusItemController(app: self)

        let settings = settingsStore.settings
        statusModel.name = settings.name
        statusItem.update(state: .stopped, name: settings.name, accepting: accepting)
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
        statusModel.state = state
        statusItem.update(state: state, name: settingsStore.settings.name, accepting: accepting)
        if case .awaitingCode = state {
            showStatusWindow()
        }
    }

    // MARK: - Actions (menu bar dropdown, app menus, status window)

    @objc func showStatusWindow() {
        statusWindow.showWindow(nil)
        updateActivationPolicy()
        NSApp.activate()
    }

    @objc func showSettings() {
        Log.info("Settings window not built yet") // Task 8
    }

    @objc func showMirrorWindow() {
        // Task 7
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
