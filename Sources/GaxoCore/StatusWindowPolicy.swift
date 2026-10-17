/// The status window steps aside while a phone is mirroring, and comes back
/// when the session ends — but only if it was open when the session started
/// (someone running Gaxo from the menu bar is not interrupted).
public struct StatusWindowPolicy {
    private var hiddenForSession = false

    public init() {}

    /// Returns true when the window should be hidden now.
    public mutating func sessionStarted(windowVisible: Bool) -> Bool {
        if windowVisible { hiddenForSession = true }
        return windowVisible
    }

    /// Returns true when the window should be shown again.
    public mutating func sessionEnded() -> Bool {
        defer { hiddenForSession = false }
        return hiddenForSession
    }
}
