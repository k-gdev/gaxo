import Foundation
import ServiceManagement

/// "Open Gaxo at login", via the system's login items. Only works for the
/// installed app bundle (not `swift run`).
enum LoginItem {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
