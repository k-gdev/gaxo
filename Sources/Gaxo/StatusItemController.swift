import AppKit
import GaxoCore
import SwiftUI

/// The menu bar icon and its dropdown (mockup 1A), rendered from `StatusMenuModel`.
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        item.button?.image = GaxoArt.menuBarGlyph()
        item.button?.toolTip = "Gaxo"
        let frame = item.button?.window?.frame ?? .zero
        Log.info("Menu bar item visible=\(item.isVisible) at x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width))")
    }

    func update(state: SessionState, name: String, accepting: Bool) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in StatusMenuModel.items(state: state, name: name, accepting: accepting) {
            menu.addItem(makeItem(entry))
        }
        item.menu = menu
    }

    private func makeItem(_ entry: StatusMenuModel.Item) -> NSMenuItem {
        switch entry {
        case let .header(title, status):
            return viewItem(MenuHeader(title: title, status: status, healthy: isHealthy(status)))
        case let .visibleAs(name):
            return viewItem(VisibleAsBox(name: name))
        case let .toggle(title, isOn):
            let menuItem = NSMenuItem(title: title, action: #selector(AppDelegate.toggleAccepting), keyEquivalent: "")
            menuItem.target = app
            menuItem.state = isOn ? .on : .off
            return menuItem
        case let .action(title, key, id):
            let menuItem = NSMenuItem(title: title, action: selector(id), keyEquivalent: key)
            menuItem.target = id == .quit ? NSApp : app
            return menuItem
        case .separator:
            return .separator()
        }
    }

    private func selector(_ id: StatusMenuModel.ActionID) -> Selector {
        switch id {
        case .showWindow: #selector(AppDelegate.showStatusWindow)
        case .showMirrorWindow: #selector(AppDelegate.showMirrorWindow)
        case .disconnect: #selector(AppDelegate.disconnect)
        case .tryAgain: #selector(AppDelegate.tryAgain)
        case .settings: #selector(AppDelegate.showSettings)
        case .quit: #selector(NSApplication.terminate(_:))
        }
    }

    private func isHealthy(_ status: String) -> Bool {
        !status.hasPrefix("Can’t") && !status.hasPrefix("Paused")
    }

    private func viewItem(_ view: some View) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view.frame(width: 284, alignment: .leading))
        hosting.frame.size = hosting.fittingSize
        let menuItem = NSMenuItem()
        menuItem.view = hosting
        return menuItem
    }
}

private struct MenuHeader: View {
    let title: String
    let status: String
    let healthy: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: GaxoArt.appIcon(size: 48))
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(healthy ? Color(red: 0.18, green: 0.70, blue: 0.31) : .orange)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct VisibleAsBox: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your iPhone lists this Mac as").font(.caption).foregroundStyle(.secondary)
            Text(name).font(.title3.weight(.semibold))
            Text("Control Center → Screen Mirroring → \(name)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}
