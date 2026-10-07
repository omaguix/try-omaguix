import Foundation

struct KeyboardPreferences: Equatable {
    var sendsCommandTab: Bool

    static let defaults = Self(sendsCommandTab: false)
}

struct KeyboardPreferenceStore {
    static let key = "keyboardPreferences"
    static let schemaVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> KeyboardPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == Self.schemaVersion else {
            return .defaults
        }
        return KeyboardPreferences(sendsCommandTab: payload.sendsCommandTab)
    }

    func save(_ preferences: KeyboardPreferences) {
        let payload = Payload(
            schemaVersion: Self.schemaVersion,
            sendsCommandTab: preferences.sendsCommandTab
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        let schemaVersion: Int
        let sendsCommandTab: Bool
    }
}

struct KeyboardLaunchConfiguration: Equatable {
    static let sendCommandTabEnvironmentKey = "OMARCHY_QEMU_GPU_SEND_COMMAND_TAB"

    let environment: [String: String]

    static func make(
        baseEnvironment: [String: String],
        preferences: KeyboardPreferences
    ) -> Self {
        var environment = baseEnvironment
        environment[sendCommandTabEnvironmentKey] = preferences.sendsCommandTab ? "1" : "0"
        return Self(environment: environment)
    }
}
