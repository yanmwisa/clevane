import Foundation

/// Preferences that live only in memory, for throwaway models (tests, snapshot mode): a named
/// `UserDefaults` suite leaves a plist in ~/Library/Preferences on every run, and the system
/// rewrites it even after removal. Overrides exactly the accessors `AppModel` uses.
final class MemoryPreferences: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ url: URL?, forKey key: String) { values[key] = url }
    override func removeObject(forKey key: String) { values[key] = nil }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func url(forKey key: String) -> URL? { values[key] as? URL }
}
