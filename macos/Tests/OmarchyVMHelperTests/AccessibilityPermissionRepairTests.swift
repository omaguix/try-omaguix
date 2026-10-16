import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Accessibility permission repair", .serialized)
struct AccessibilityPermissionRepairTests {
    @Test("a successful scoped TCC reset is reported")
    func successfulReset() {
        #expect(
            AccessibilityPermissionRepair.resetStaleEntry(
                bundleIdentifier: "dev.tryomarchy.native",
                tccutilURL: URL(fileURLWithPath: "/usr/bin/true")
            )
        )
    }

    @Test("a failed scoped TCC reset does not masquerade as success")
    func failedReset() {
        #expect(
            !AccessibilityPermissionRepair.resetStaleEntry(
                bundleIdentifier: "dev.tryomarchy.native",
                tccutilURL: URL(fileURLWithPath: "/usr/bin/false")
            )
        )
    }

    @Test("a command-line helper without an app identity cannot reset permissions")
    func missingBundleIdentifier() {
        #expect(!AccessibilityPermissionRepair.resetStaleEntry(
            bundleIdentifier: nil,
            tccutilURL: URL(fileURLWithPath: "/usr/bin/true")
        ))
    }

    @Test("repair scopes its reset to the development or production bundle", arguments: [
        "dev.tryomaguix.native", "dev.tryomaguix.native.development"
    ])
    func scopedBundleIdentifier(identifier: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = directory.appendingPathComponent("tccutil")
        let arguments = directory.appendingPathComponent("arguments")
        try "#!/bin/bash\nprintf '%s\\n' \"$@\" > \"${0%/*}/arguments\"\n".write(
            to: probe, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: probe.path)
        #expect(AccessibilityPermissionRepair.resetStaleEntry(
            bundleIdentifier: identifier, tccutilURL: probe
        ))
        #expect(try String(contentsOf: arguments, encoding: .utf8) == "reset\nAccessibility\n\(identifier)\n")
    }

    /// Runs `request` with injected AX and reset functions, recording which
    /// actions ran and in what order.
    private func run(trusted: Bool, resetSucceeds: Bool) -> (
        outcome: AccessibilityPermissionRepair.Outcome, actions: [String]
    ) {
        var actions: [String] = []
        let outcome = AccessibilityPermissionRepair.request(
            isTrusted: { trusted },
            resetStaleEntry: { actions.append("reset"); return resetSucceeds },
            prompt: { actions.append("prompt") },
            openSettings: { actions.append("settings") }
        )
        return (outcome, actions)
    }

    @Test("a trusted app is never reset and nothing is shown", arguments: [true, false])
    func trustedAppKeepsItsGrant(resetSucceeds: Bool) {
        let result = run(trusted: true, resetSucceeds: resetSucceeds)
        #expect(result.outcome == .alreadyTrusted)
        #expect(result.actions.isEmpty)
    }

    @Test("an untrusted app's stale row is reset, then only the prompt is shown")
    func untrustedAppPrompts() {
        let result = run(trusted: false, resetSucceeds: true)
        #expect(result.outcome == .prompted)
        #expect(result.actions == ["reset", "prompt"])
    }

    @Test("when the reset fails, only System Settings is shown")
    func failedResetOpensSettings() {
        let result = run(trusted: false, resetSucceeds: false)
        #expect(result.outcome == .openedSettings)
        #expect(result.actions == ["reset", "settings"])
    }
}
