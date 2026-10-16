import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("App identity")
struct AppIdentityTests {
    @Test("reads the keys build-app.sh writes; an empty service means NAT only")
    func readsInfoPlistKeys() {
        let values = [
            "OmaguixApplicationName": "Try Omabend",
            "OmaguixDevelopmentApplicationName": "Try Omabend Dev",
            "OmaguixApplicationSupportDirectory": "Try Omabend Data",
            "OmaguixLogsDirectory": "Try Omabend Logs",
            "OmaguixNetworkHelperService": "",
            "OmaguixReleaseRepository": "example/try-omabend",
            "OmaguixReleaseTagPrefix": "try-omabend-v",
            "OmaguixReleaseDMG": "TryOmabend.dmg",
            "OmaguixLegacyReleaseDMGs": "OldOmabend.dmg",
        ]
        #expect(AppIdentity(values: values) == .second)
        #expect(AppIdentity.second.networkHelperService == nil)
        #expect(AppIdentity.second.legacyReleaseDMGs == ["OldOmabend.dmg"])
        #expect(AppIdentity.tryOmaguix.legacyReleaseDMGs == [])
        #expect(AppIdentity.tryOmaguix.networkHelperService == "dev.tryomaguix.network")
    }

    @Test("the launcher and the app read the same Info.plist keys")
    func launcherReadsTheSameKeys() throws {
        let macos = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let launcher = try String(
            contentsOf: macos.appendingPathComponent("run-qemu-gpu.sh"), encoding: .utf8)
        let build = try String(
            contentsOf: macos.appendingPathComponent("build-app.sh"), encoding: .utf8)
        for key in ["OmaguixApplicationName", "OmaguixApplicationSupportDirectory",
                    "OmaguixNetworkHelperService"] {
            #expect(launcher.contains("app_identity \(key)"))
        }
        for key in ["OmaguixApplicationName", "OmaguixDevelopmentApplicationName",
                    "OmaguixApplicationSupportDirectory", "OmaguixLogsDirectory",
                    "OmaguixNetworkHelperService", "OmaguixReleaseRepository",
                    "OmaguixReleaseTagPrefix", "OmaguixReleaseDMG", "OmaguixLegacyReleaseDMGs"] {
            #expect(build.contains("value[\"\(key)\"]"))
        }
        #expect(launcher.contains(
            "QEMU_PERSISTENT_STORAGE_APPLICATION_SUPPORT_DIRECTORY=$application_support_directory"))
    }
}
