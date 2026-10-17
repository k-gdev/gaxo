import Foundation
@testable import GaxoCore

/// In-memory preferences, so tests never create files in ~/Library/Preferences.
final class MemoryPreferences: PreferenceStore {
    private var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
