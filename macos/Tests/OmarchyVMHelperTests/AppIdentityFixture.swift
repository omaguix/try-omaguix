import Testing
@testable import OmarchyVMHelper

extension AppIdentity {
    /// Try Omaguix's identity as build-app.sh writes it from
    /// macos/apps/try-omaguix.env.
    static let tryOmaguix = AppIdentity(
        applicationName: "Try Omaguix",
        guestName: "Omaguix",
        developmentApplicationName: "Try Omaguix Dev",
        applicationSupportDirectory: "Try Omaguix",
        logsDirectory: "Try Omaguix",
        networkHelperService: "dev.tryomaguix.network",
        releaseRepository: "omaguix/try-omaguix",
        releaseTagPrefix: "try-omaguix-v",
        releaseDMG: "TryOmaguix.dmg",
        legacyReleaseDMGs: []
    )

    /// A second app built from the same sources.
    static let second = AppIdentity(
        applicationName: "Try Omabend",
        guestName: "Omabend",
        developmentApplicationName: "Try Omabend Dev",
        applicationSupportDirectory: "Try Omabend Data",
        logsDirectory: "Try Omabend Logs",
        networkHelperService: nil,
        releaseRepository: "example/try-omabend",
        releaseTagPrefix: "try-omabend-v",
        releaseDMG: "TryOmabend.dmg",
        legacyReleaseDMGs: ["OldOmabend.dmg"]
    )
}

/// Runs a suite's tests with `AppIdentity.main` set to an identity, as the
/// built app reads it from Info.plist; code that names the app or its guest
/// reads it there.
struct AppIdentityTrait: SuiteTrait, TestTrait, TestScoping {
    let identity: AppIdentity

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        try await AppIdentity.$main.withValue(identity) { try await function() }
    }
}

extension Trait where Self == AppIdentityTrait {
    static func identity(_ identity: AppIdentity) -> Self { AppIdentityTrait(identity: identity) }
}
