@testable import OmarchyVMHelper

extension AppIdentity {
    /// Try Omaguix's identity as build-app.sh writes it from
    /// macos/apps/try-omaguix.env.
    static let tryOmaguix = AppIdentity(
        applicationName: "Try Omaguix",
        developmentApplicationName: "Try Omaguix Dev",
        applicationSupportDirectory: "Try Roguix",
        logsDirectory: "Try Roguix",
        networkHelperService: "dev.tryroguix.network",
        releaseRepository: "omaguix/try-omaguix",
        releaseTagPrefix: "try-roguix-v",
        releaseDMG: "TryOmaguix.dmg",
        legacyReleaseDMGs: ["TryRoguix.dmg"]
    )

    /// A second app built from the same sources.
    static let second = AppIdentity(
        applicationName: "Try Omabend",
        developmentApplicationName: "Try Omabend Dev",
        applicationSupportDirectory: "Try Omabend Data",
        logsDirectory: "Try Omabend Logs",
        networkHelperService: nil,
        releaseRepository: "example/try-omabend",
        releaseTagPrefix: "try-omabend-v",
        releaseDMG: "TryOmabend.dmg",
        legacyReleaseDMGs: []
    )
}
