import AppKit
import GaxoCore
import SwiftUI

/// What the status window and dropdown header show.
final class StatusViewModel: ObservableObject {
    @Published var state: SessionState = .stopped
    @Published var name = "Gaxo"
    @Published var accepting = true
}

/// Mockup 1B: "Ready to mirror" window.
struct StatusView: View {
    @ObservedObject var model: StatusViewModel
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: GaxoArt.appIcon(size: 96))
                    .resizable()
                    .frame(width: 90, height: 90)
                    .accessibilityHidden(true)
                Text(headline)
                    .font(.title2.weight(.semibold))
                if case let .awaitingCode(code) = model.state {
                    Text(code)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .kerning(8)
                        .textSelection(.enabled)
                        .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                }
                Text(detail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 44)
            .padding(.top, 28)
            .padding(.bottom, 28)

            Divider()

            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(footer).font(.callout)
                Spacer()
                Button("Settings…", action: openSettings)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520)
    }

    private var headline: String {
        switch model.state {
        case .ready: "Ready to mirror"
        case let .mirroring(client): "Mirroring from \(client.name)"
        case .awaitingCode: "Enter this code on your iPhone"
        case .playingVideo: "Playing a video"
        case .stopped: model.accepting ? "Starting…" : "Paused"
        case .failed: "Gaxo can’t receive right now"
        }
    }

    private var detail: AttributedString {
        let markdown: String = switch model.state {
        case .ready:
            "On your iPhone, open Control Center, tap Screen Mirroring, then choose **\(model.name)**."
        case .mirroring:
            "Close the mirror window to disconnect."
        case .playingVideo:
            "Your iPhone is playing a video in Gaxo. Close the mirror window to stop."
        case .awaitingCode:
            "Your iPhone is asking for a code to connect to **\(model.name)**."
        case .stopped:
            model.accepting
                ? "Starting the receiver…"
                : "iPhones can’t see Gaxo. Turn on **Accept connections** in the menu bar to mirror again."
        case let .failed(error):
            StatusMenuModel.failure(error)
        }
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private var footer: String {
        switch model.state {
        case .ready, .mirroring, .awaitingCode, .playingVideo: "Visible on your network as \(model.name)"
        case .stopped: model.accepting ? "Starting…" : "Not visible on the network"
        case .failed: "Not visible on the network"
        }
    }

    private var dotColor: Color {
        switch model.state {
        case .ready, .mirroring, .awaitingCode, .playingVideo: Color(red: 0.18, green: 0.70, blue: 0.31)
        case .stopped: .orange
        case .failed: .red
        }
    }
}

final class StatusWindowController: NSWindowController {
    init(model: StatusViewModel, openSettings: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: true)
        window.title = "Gaxo"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.contentView = NSHostingView(rootView: StatusView(model: model, openSettings: openSettings))
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.setFrameAutosaveName("GaxoStatusWindow")
        super.init(window: window)
    }

    /// For the log: the window's real content size next to what the SwiftUI content needs.
    var sizeReport: String {
        guard let window, let content = window.contentView else { return "no window" }
        let needs = content.fittingSize
        return "visible=\(window.isVisible) key=\(window.isKeyWindow) appActive=\(NSApp.isActive) "
            + "content=\(Int(content.frame.width))×\(Int(content.frame.height)) "
            + "needs=\(Int(needs.width))×\(Int(needs.height))"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
