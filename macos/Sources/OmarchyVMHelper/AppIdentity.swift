import Foundation

/// The app identity build-app.sh writes into Info.plist from the selected
/// identity file (macos/README.md, "App identity"). A built app always has
/// every key, so reading a missing one is a build bug and stops the app;
/// nothing falls back to Try Omaguix's values. Tests construct the values
/// they need instead of reading `main`, which in a test runner has none.
struct AppIdentity: Equatable, Sendable {
    static let main = AppIdentity(
        values: (Bundle.main.infoDictionary ?? [:]).compactMapValues { $0 as? String }
    )

    /// The running app's bundle identifier, the prefix of its logger
    /// subsystems and dispatch-queue labels.
    static let bundleIdentifier: String = {
        guard let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty else {
            fatalError("The running app has no bundle identifier")
        }
        return identifier
    }()

    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    init(
        applicationName: String,
        developmentApplicationName: String,
        applicationSupportDirectory: String,
        logsDirectory: String,
        networkHelperService: String?
    ) {
        self.init(values: [
            "RoguixApplicationName": applicationName,
            "RoguixDevelopmentApplicationName": developmentApplicationName,
            "RoguixApplicationSupportDirectory": applicationSupportDirectory,
            "RoguixLogsDirectory": logsDirectory,
            "RoguixNetworkHelperService": networkHelperService ?? "",
        ])
    }

    /// The production name, which also names the VM helper app and its
    /// executable.
    var applicationName: String { value("RoguixApplicationName") }
    /// The name `make install` gives the development build.
    var developmentApplicationName: String { value("RoguixDevelopmentApplicationName") }
    /// The directory under ~/Library/Application Support that holds the VM.
    var applicationSupportDirectory: String { value("RoguixApplicationSupportDirectory") }
    /// The directory under ~/Library/Logs that holds the launcher log.
    var logsDirectory: String { value("RoguixLogsDirectory") }
    /// The bridged-networking helper's launchd service; nil when the app ships
    /// no helper and offers only NAT.
    var networkHelperService: String? {
        let service = value("RoguixNetworkHelperService", mayBeEmpty: true)
        return service.isEmpty ? nil : service
    }

    private func value(_ key: String, mayBeEmpty: Bool = false) -> String {
        guard let value = values[key], mayBeEmpty || !value.isEmpty else {
            fatalError("Info.plist has no \(key); build the app with macos/build-app.sh")
        }
        return value
    }
}
