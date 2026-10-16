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
        networkHelperService: String?,
        releaseRepository: String,
        releaseTagPrefix: String,
        releaseDMG: String,
        legacyReleaseDMGs: [String]
    ) {
        self.init(values: [
            "OmaguixApplicationName": applicationName,
            "OmaguixDevelopmentApplicationName": developmentApplicationName,
            "OmaguixApplicationSupportDirectory": applicationSupportDirectory,
            "OmaguixLogsDirectory": logsDirectory,
            "OmaguixNetworkHelperService": networkHelperService ?? "",
            "OmaguixReleaseRepository": releaseRepository,
            "OmaguixReleaseTagPrefix": releaseTagPrefix,
            "OmaguixReleaseDMG": releaseDMG,
            "OmaguixLegacyReleaseDMGs": legacyReleaseDMGs.joined(separator: ","),
        ])
    }

    /// The production name, which also names the VM helper app and its
    /// executable.
    var applicationName: String { value("OmaguixApplicationName") }
    /// The name `make install` gives the development build.
    var developmentApplicationName: String { value("OmaguixDevelopmentApplicationName") }
    /// The directory under ~/Library/Application Support that holds the VM.
    var applicationSupportDirectory: String { value("OmaguixApplicationSupportDirectory") }
    /// The directory under ~/Library/Logs that holds the launcher log.
    var logsDirectory: String { value("OmaguixLogsDirectory") }
    /// The bridged-networking helper's launchd service; nil when the app ships
    /// no helper and offers only NAT.
    var networkHelperService: String? {
        let service = value("OmaguixNetworkHelperService", mayBeEmpty: true)
        return service.isEmpty ? nil : service
    }
    /// The GitHub repository (`owner/name`) whose releases the update check reads.
    var releaseRepository: String { value("OmaguixReleaseRepository") }
    /// Release tags are this prefix and X.Y.Z (docs/releasing.md).
    var releaseTagPrefix: String { value("OmaguixReleaseTagPrefix") }
    /// The release's disk image asset, `NAME.dmg`.
    var releaseDMG: String { value("OmaguixReleaseDMG") }
    /// The disk image names older releases of this app published; often none.
    var legacyReleaseDMGs: [String] {
        value("OmaguixLegacyReleaseDMGs", mayBeEmpty: true)
            .split(separator: ",").map(String.init)
    }

    private func value(_ key: String, mayBeEmpty: Bool = false) -> String {
        guard let value = values[key], mayBeEmpty || !value.isEmpty else {
            fatalError("Info.plist has no \(key); build the app with macos/build-app.sh")
        }
        return value
    }
}
