import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Keyboard preferences", .identity(.tryOmaguix))
struct KeyboardPreferenceStoreTests {
    @Test("Command-Tab stays with macOS until the user changes it")
    func defaultsToMacOS() {
        let fixture = DefaultsFixture()

        #expect(fixture.store.load() == .defaults)
        #expect(!fixture.store.load().sendsCommandTab)
    }

    @Test("Send Command-Tab choice persists")
    func savesChoice() {
        let fixture = DefaultsFixture()
        fixture.store.save(KeyboardPreferences(sendsCommandTab: true))

        let reopened = KeyboardPreferenceStore(defaults: fixture.defaults)
        #expect(reopened.load() == KeyboardPreferences(sendsCommandTab: true))
    }

    @Test("Invalid or future preferences fail safely")
    func invalidPreferencesUseDefault() throws {
        let fixture = DefaultsFixture()
        fixture.defaults.set(Data("junk".utf8), forKey: KeyboardPreferenceStore.key)
        #expect(fixture.store.load() == .defaults)

        let future = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": KeyboardPreferenceStore.schemaVersion + 1,
            "sendsCommandTab": true,
        ])
        fixture.defaults.set(future, forKey: KeyboardPreferenceStore.key)
        #expect(fixture.store.load() == .defaults)
    }

    private final class DefaultsFixture {
        let suiteName = "KeyboardPreferenceStoreTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: KeyboardPreferenceStore

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            store = KeyboardPreferenceStore(defaults: defaults)
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

@Suite("Keyboard launch configuration", .identity(.tryOmaguix))
struct KeyboardLaunchConfigurationTests {
    @Test("Publishes the Command-Tab choice and replaces inherited values")
    func publishesChoice() {
        let inherited = [
            "KEEP_ME": "yes",
            KeyboardLaunchConfiguration.sendCommandTabEnvironmentKey: "invalid",
        ]

        let guest = KeyboardLaunchConfiguration.make(
            baseEnvironment: inherited,
            preferences: KeyboardPreferences(sendsCommandTab: true)
        )
        #expect(guest.environment["KEEP_ME"] == "yes")
        #expect(guest.environment[KeyboardLaunchConfiguration.sendCommandTabEnvironmentKey] == "1")

        let host = KeyboardLaunchConfiguration.make(
            baseEnvironment: inherited,
            preferences: .defaults
        )
        #expect(host.environment["KEEP_ME"] == "yes")
        #expect(host.environment[KeyboardLaunchConfiguration.sendCommandTabEnvironmentKey] == "0")
    }
}
