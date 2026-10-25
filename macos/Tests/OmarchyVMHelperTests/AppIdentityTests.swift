import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("App identity")
struct AppIdentityTests {
    @Test("reads the keys build-app.sh writes; an empty service means NAT only")
    func readsInfoPlistKeys() {
        let values = [
            "OmaguixApplicationName": "Try Omabend",
            "OmaguixGuestName": "Omabend",
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
                    "OmaguixReleaseTagPrefix", "OmaguixReleaseDMG", "OmaguixLegacyReleaseDMGs",
                    "OmaguixGuestName"] {
            #expect(build.contains("value[\"\(key)\"]"))
        }
        #expect(launcher.contains(
            "QEMU_PERSISTENT_STORAGE_APPLICATION_SUPPORT_DIRECTORY=$application_support_directory"))
    }

    @Test("windows and messages name the app and its guest from the identity")
    func messagesFollowTheIdentity() {
        AppIdentity.$main.withValue(.second) {
            #expect(StartMenuPresentation.immersiveDetail(isEnabled: true)
                .hasPrefix("Omabend opens Full Screen"))
            #expect(ResetConfirmationPolicy.allowsReset("Try Omabend"))
            #expect(!ResetConfirmationPolicy.allowsReset("Try Omaguix"))
            #expect(AppReleaseCheckState.noRelease.message
                == "No stable Try Omabend release has been published yet.")
        }
    }

    @Test("no Swift source names the app or its guest itself")
    func sourcesNameNoApp() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OmarchyVMHelper")
        // The name as a word outside comments, also inside multiline string
        // literals; the Info.plist keys (OmaguixApplicationName) are no names.
        let name = try NSRegularExpression(pattern: #"(?<![A-Za-z])Omaguix(?![A-Za-z])"#)
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path)
        where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for line in text.split(separator: "\n")
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let text = String(line)
                let range = NSRange(text.startIndex..., in: text)
                #expect(name.firstMatch(in: text, range: range) == nil, "\(file): \(text)")
            }
        }
    }
}
