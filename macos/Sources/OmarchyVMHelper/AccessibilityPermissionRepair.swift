import Foundation

enum AccessibilityPermissionRepair {
    enum Outcome: Equatable {
        /// The grant already works; nothing was reset or shown.
        case alreadyTrusted
        /// The stale row was removed and macOS's own prompt was shown.
        case prompted
        /// The reset failed, so the prompt may not appear; Settings was opened.
        case openedSettings
    }

    /// Handle the start menu's Open Settings for Accessibility, showing one
    /// window: macOS's prompt, or System Settings when the prompt cannot
    /// appear.
    ///
    /// Whether Accessibility lists the app cannot be read without private API
    /// or TCC.db (which needs Full Disk Access), so the rule is: a trusted
    /// app is never reset, and an untrusted one always is. An untrusted
    /// app's row, if any, is stale (a requirement left by an ad-hoc or older
    /// build, which tccd no longer matches) or switched off; the user asked
    /// for the grant, so removing it is what lets the prompt appear, since
    /// macOS prompts only when the app has no row. The prompt has its own
    /// button to System Settings.
    static func request(
        isTrusted: () -> Bool,
        resetStaleEntry: () -> Bool = { AccessibilityPermissionRepair.resetStaleEntry() },
        prompt: () -> Void,
        openSettings: () -> Void
    ) -> Outcome {
        guard !isTrusted() else { return .alreadyTrusted }
        guard resetStaleEntry() else {
            openSettings()
            return .openedSettings
        }
        prompt()
        return .prompted
    }

    /// Remove only this app's Accessibility decision before asking macOS to
    /// register the currently installed code. This repairs TCC records left
    /// behind when an older or ad-hoc-signed app was replaced.
    static func resetStaleEntry(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        tccutilURL: URL = URL(fileURLWithPath: "/usr/bin/tccutil")
    ) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        let process = Process()
        process.executableURL = tccutilURL
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationReason == .exit && process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
