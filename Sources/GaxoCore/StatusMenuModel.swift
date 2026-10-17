/// What the menu bar dropdown shows in each session state (mockup 1A).
/// Pure data, so the AppKit menu is a thin rendering of it.
public enum StatusMenuModel {
    public enum ActionID: Equatable {
        case showWindow, showMirrorWindow, disconnect, settings, quit
    }

    public enum Item: Equatable {
        case header(title: String, status: String)
        /// "Your iPhone lists this Mac as <name>"
        case visibleAs(String)
        case toggle(title: String, isOn: Bool)
        /// `key` is the ⌘ key equivalent ("" for none).
        case action(title: String, key: String, id: ActionID)
        case separator
    }

    public static func items(state: SessionState, name: String, accepting: Bool) -> [Item] {
        var items: [Item] = [
            .header(title: "Gaxo", status: status(state: state, accepting: accepting)),
            .visibleAs(name),
            .separator,
            .toggle(title: "Accept connections", isOn: accepting),
            .separator,
        ]
        if state.isShowingPhone {
            items += [
                .action(title: "Show Mirror Window", key: "", id: .showMirrorWindow),
                .action(title: "Disconnect", key: "", id: .disconnect),
                .separator,
            ]
        }
        items += [
            .action(title: "Show Gaxo Window", key: "1", id: .showWindow),
            .action(title: "Settings…", key: ",", id: .settings),
            .action(title: "Quit Gaxo", key: "q", id: .quit),
        ]
        return items
    }

    /// One-line status, shared by the dropdown header and the status window.
    public static func status(state: SessionState, accepting: Bool) -> String {
        switch state {
        case .ready: "Ready · no device connected"
        case let .mirroring(client): "Mirroring from \(client.name)"
        case let .awaitingCode(code): "Enter code \(code) on your iPhone"
        case .playingVideo: "Playing a video from your iPhone"
        case .stopped: accepting ? "Starting…" : "Paused · not visible to iPhones"
        case let .failed(error): failure(error)
        }
    }

    public static func failure(_ error: EngineError) -> String {
        switch error {
        case let .portInUse(port):
            "Can’t start: port \(port) is in use (is another Gaxo running?)"
        case .registerFailed:
            "Can’t announce Gaxo on the network"
        case .dnssdInit, .raopInit:
            "Can’t start the receiver"
        }
    }
}

extension SessionState {
    /// Mirroring or playing an AirPlay video: the phone's picture is on this Mac.
    public var isShowingPhone: Bool {
        switch self {
        case .mirroring, .playingVideo: true
        default: false
        }
    }
}
