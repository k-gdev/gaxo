import AppKit
import GaxoCore
import SwiftUI

final class SettingsViewModel: ObservableObject {
    @Published var settings: GaxoCore.Settings
    /// The Name field while it is being edited.
    @Published var draftName: String

    init(settings: GaxoCore.Settings) {
        self.settings = settings
        draftName = settings.name
    }

    /// The settings with the edited name, if the edit changes it.
    func settingsWithDraftName() -> GaxoCore.Settings? {
        let changed = settings.applyingNameDraft(draftName)
        draftName = GaxoCore.Settings.cleanName(draftName)
        return changed
    }
}

/// Mockup screen 4. Every change goes through `apply`; the name is applied
/// when editing ends (Return or leaving the field), not on each keystroke.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    var apply: (GaxoCore.Settings) -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section("Receiver") {
                LabeledContent {
                    TextField("Name", text: $model.draftName)
                        .labelsHidden()
                        .frame(width: 200)
                        .focused($nameFocused)
                        .onSubmit(commitName)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Name")
                        Text("Shown in Screen Mirroring on your iPhone")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Open Gaxo at login", isOn: binding(\.openAtLogin))
                Toggle("Show the status window when Gaxo opens", isOn: binding(\.showStatusWindowAtLaunch))
            }
            Section("Video") {
                Picker("Resolution asked of iPhone", selection: binding(\.resolution)) {
                    ForEach(Resolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Frame rate", selection: binding(\.frameRate)) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }
            Section("Window") {
                Toggle("Keep mirror window on top", isOn: binding(\.keepOnTop))
                Toggle("Close window when mirroring stops", isOn: binding(\.closeWindowWhenMirroringStops))
            }
            Section("Sound") {
                Toggle("Play iPhone sound on this Mac", isOn: binding(\.playSound))
            }
            Section {
                Toggle(isOn: binding(\.requireCode)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask for a code before mirroring")
                        Text("A 4-digit code appears on this Mac the first time a device connects; you type it on the iPhone")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Network ports 7100–7102 · the Mac’s own AirPlay Receiver keeps 7000")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<GaxoCore.Settings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = model.settings
                settings[keyPath: keyPath] = newValue
                apply(settings)
            })
    }

    private func commitName() {
        if let settings = model.settingsWithDraftName() { apply(settings) }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Closing the window also applies a name that was typed but not confirmed.
    var onClose: (() -> Void)?

    init(model: SettingsViewModel, apply: @escaping (GaxoCore.Settings) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Gaxo Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.contentView = NSHostingView(rootView: SettingsView(model: model, apply: apply))
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.setFrameAutosaveName("GaxoSettingsWindow")
        super.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
