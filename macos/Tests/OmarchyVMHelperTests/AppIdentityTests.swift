import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("App identity")
struct AppIdentityTests {
    @Test("reads the keys build-app.sh writes; an empty service means NAT only")
    func readsInfoPlistKeys() {
        let values = [
            "RoguixApplicationName": "Try Omabend",
            "RoguixDevelopmentApplicationName": "Try Omabend Dev",
            "RoguixApplicationSupportDirectory": "Try Omabend Data",
            "RoguixLogsDirectory": "Try Omabend Logs",
            "RoguixNetworkHelperService": "",
            "RoguixReleaseRepository": "example/try-omabend",
            "RoguixReleaseTagPrefix": "try-omabend-v",
            "RoguixReleaseDMG": "TryOmabend.dmg",
            "RoguixLegacyReleaseDMGs": "",
        ]
        #expect(AppIdentity(values: values) == .second)
        #expect(AppIdentity.second.networkHelperService == nil)
        #expect(AppIdentity.second.legacyReleaseDMGs == [])
        #expect(AppIdentity.tryOmaguix.legacyReleaseDMGs == ["TryRoguix.dmg"])
        #expect(AppIdentity.tryOmaguix.networkHelperService == "dev.tryroguix.network")
    }

    @Test("the launcher and the app read the same Info.plist keys")
    func launcherReadsTheSameKeys() throws {
        let macos = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let launcher = try String(
            contentsOf: macos.appendingPathComponent("run-qemu-gpu.sh"), encoding: .utf8)
        let build = try String(
            contentsOf: macos.appendingPathComponent("build-app.sh"), encoding: .utf8)
        for key in ["RoguixApplicationName", "RoguixApplicationSupportDirectory",
                    "RoguixNetworkHelperService"] {
            #expect(launcher.contains("app_identity \(key)"))
        }
        for key in ["RoguixApplicationName", "RoguixDevelopmentApplicationName",
                    "RoguixApplicationSupportDirectory", "RoguixLogsDirectory",
                    "RoguixNetworkHelperService", "RoguixReleaseRepository",
                    "RoguixReleaseTagPrefix", "RoguixReleaseDMG", "RoguixLegacyReleaseDMGs"] {
            #expect(build.contains("value[\"\(key)\"]"))
        }
        #expect(launcher.contains(
            "QEMU_PERSISTENT_STORAGE_APPLICATION_SUPPORT_DIRECTORY=$application_support_directory"))
    }
}
