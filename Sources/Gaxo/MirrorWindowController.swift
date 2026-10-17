import AppKit
import GaxoCore

/// The mirror window: a normal, resizable window that keeps the phone's shape,
/// reshapes around its centre when the phone rotates, and never goes full
/// screen unless the user asks (View → Enter Full Screen or the green button).
final class MirrorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, MirrorActions {
    let videoView = VideoLayerView(frame: NSRect(x: 0, y: 0, width: 320, height: 692))
    /// The user closed the window (as opposed to the session ending).
    var onUserClose: (() -> Void)?
    /// The window was shown (the Dock icon should appear).
    var onShow: (() -> Void)?

    private var videoSize: CGSize?
    private var closingForSessionEnd = false
    private var lastCentre: CGPoint?
    private(set) var floatsOnTop = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 692),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = "iPhone"
        window.isRestorable = false // never come back in full screen from a previous run
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary] // full screen allowed, only when asked
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 120, height: 120)
        window.contentView = videoView
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func present(clientName: String) {
        window?.title = clientName
    }

    func setFloating(_ on: Bool) {
        floatsOnTop = on
        window?.level = on ? .floating : .normal
    }

    /// Main thread. First frame of a session, or the phone rotated.
    func videoSizeChanged(_ size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        let previous = videoSize
        videoSize = size
        window.contentAspectRatio = size
        let visible = contentArea(of: window)

        if !window.isVisible || previous == nil {
            var content = CGRect(origin: .zero, size: WindowSizing.initialContentSize(video: size, visible: visible))
            let centre = lastCentre ?? CGPoint(x: visible.midX, y: visible.midY)
            content.origin = CGPoint(x: centre.x - content.width / 2, y: centre.y - content.height / 2)
            content = WindowSizing.rotatedFrame(current: content, video: size, visible: visible) // clamp on screen
            window.setFrame(window.frameRect(forContentRect: content), display: true)
            showWindow(nil)
            onShow?()
        } else if !window.styleMask.contains(.fullScreen), previous != size {
            let current = window.contentRect(forFrameRect: window.frame)
            let rotated = WindowSizing.rotatedFrame(current: current, video: size, visible: visible)
            window.setFrame(window.frameRect(forContentRect: rotated), display: true, animate: true)
        }
    }

    /// The session ended; close without disconnecting anyone.
    func closeForSessionEnd() {
        guard let window, window.isVisible else { return }
        closingForSessionEnd = true
        window.close()
    }

    /// A new session will start fresh (decoder and sizes reset).
    func resetVideo() {
        videoSize = nil
        videoView.clear()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window { lastCentre = CGPoint(x: window.frame.midX, y: window.frame.midY) }
        if !closingForSessionEnd { onUserClose?() }
        closingForSessionEnd = false
        resetVideo()
    }

    // MARK: - View menu

    @objc func floatOnTop(_ sender: Any?) {
        setFloating(!floatsOnTop)
    }

    @objc func actualSize(_ sender: Any?) {
        guard let window, let videoSize else { return }
        let visible = contentArea(of: window)
        resizeContent(to: WindowSizing.actualSize(video: videoSize, backingScale: window.backingScaleFactor,
                                                  visible: visible), within: visible)
    }

    @objc func fitToScreen(_ sender: Any?) {
        guard let window, let videoSize else { return }
        let visible = contentArea(of: window)
        resizeContent(to: WindowSizing.fitToScreen(video: videoSize, visible: visible), within: visible)
    }

    @objc func takeScreenshot(_ sender: Any?) {
        guard let frame = videoView.lastFrame else {
            NSSound.beep()
            return
        }
        do {
            let url = try Screenshot.save(frame)
            Log.info("Screenshot saved to \(url.path)")
        } catch {
            Log.error("Screenshot failed: \(error)")
            NSSound.beep()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(floatOnTop(_:)):
            menuItem.state = floatsOnTop ? .on : .off
            return true
        case #selector(takeScreenshot(_:)):
            return videoView.lastFrame != nil
        case #selector(actualSize(_:)), #selector(fitToScreen(_:)):
            return videoSize != nil && !(window?.styleMask.contains(.fullScreen) ?? false)
        default:
            return true
        }
    }

    // MARK: - Geometry helpers

    /// The screen area the content (below the title bar) may occupy.
    private func contentArea(of window: NSWindow) -> CGRect {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let titleBar = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height - titleBar)
    }

    private func resizeContent(to size: CGSize, within visible: CGRect) {
        guard let window else { return }
        let current = window.contentRect(forFrameRect: window.frame)
        var content = CGRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                             width: size.width, height: size.height)
        content.origin.x = min(max(content.minX, visible.minX), visible.maxX - content.width)
        content.origin.y = min(max(content.minY, visible.minY), visible.maxY - content.height)
        window.setFrame(window.frameRect(forContentRect: content), display: true, animate: true)
    }
}
