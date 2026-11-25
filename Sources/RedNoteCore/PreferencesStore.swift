import Foundation

public final class PreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.rednotelite.preferences.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        return decoded
    }

    public func save(_ preferences: AppPreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}
